require "../src/smalang/ir"
require "../src/smalang/x86_64_backend"

module BackendSpecHelpers
  def self.link_and_run(ir : Smalang::IrModule) : Int32
    link_and_capture(ir)[:exit_code]
  end

  def self.link_and_check_heap_pointer_alignment(ir : Smalang::IrModule, alignment : UInt64) : Int32
    base_path = File.join(Dir.tempdir, "smalang-heap-alignment-#{Process.pid}")
    object_path = "#{base_path}.o"
    assembly_path = "#{base_path}.s"
    harness_path = "#{base_path}-harness.o"
    executable_path = "#{base_path}-harness"
    assembly = <<-ASM
      .section .text
      .global _check_alignment
      .type _check_alignment, @function
      .extern __smalang_user_main
    _check_alignment:
      xor %r15, %r15
      call __smalang_user_main
      test %rdx, %rdx
      jne .Lalignment_failure
      movabs $#{alignment - 1_u64}, %r10
      test %r10, %rax
      jne .Lalignment_failure
      xor %rdi, %rdi
      jmp .Lalignment_exit
    .Lalignment_failure:
      mov $1, %rdi
    .Lalignment_exit:
      mov $60, %rax
      syscall
    ASM

    begin
      object_bytes = Smalang::X86_64Backend.new.emit(ir)
      File.write(object_path, String.new(object_bytes.to_unsafe, object_bytes.size))
      File.write(assembly_path, assembly)

      assembler_error = IO::Memory.new
      assembler_status = Process.run(
        "as",
        ["--64", "-o", harness_path, assembly_path],
        output: Process::Redirect::Close,
        error: assembler_error
      )
      raise "assembler failed for heap alignment check: #{assembler_error}" unless assembler_status.success?

      linker_error = IO::Memory.new
      linker_status = Process.run(
        "ld",
        ["-e", "_check_alignment", object_path, harness_path, "-o", executable_path],
        output: Process::Redirect::Close,
        error: linker_error
      )
      raise "ld failed for heap alignment check: #{linker_error}" unless linker_status.success?

      Process.run(
        executable_path,
        output: Process::Redirect::Close,
        error: Process::Redirect::Close
      ).exit_code
    ensure
      [object_path, assembly_path, harness_path, executable_path].each do |path|
        File.delete(path) if File.exists?(path)
      end
    end
  end

  def self.link_and_capture(
    ir : Smalang::IrModule,
    virtual_memory_limit_kib : Int32? = nil,
  ) : NamedTuple(exit_code: Int32, stdout: String, stderr: String)
    object_bytes = Smalang::X86_64Backend.new.emit(ir)
    object_path = File.join(Dir.tempdir, "smalang-backend-#{Process.pid}.o")
    executable_path = File.join(Dir.tempdir, "smalang-backend-#{Process.pid}")

    begin
      File.write(object_path, String.new(object_bytes.to_unsafe, object_bytes.size))
      linker_error = IO::Memory.new
      link_status = Process.run(
        "ld",
        ["-e", "_start", object_path, "-o", executable_path],
        output: Process::Redirect::Close,
        error: linker_error
      )
      raise "ld failed: #{linker_error}" unless link_status.success?

      output = IO::Memory.new
      error = IO::Memory.new
      status = if memory_limit_kib = virtual_memory_limit_kib
                 Process.run(
                   "bash",
                   ["-c", "ulimit -v \"$1\"; exec \"$2\"", "smalang-test", memory_limit_kib.to_s, executable_path],
                   output: output,
                   error: error
                 )
               else
                 Process.run(
                   executable_path,
                   output: output,
                   error: error
                 )
               end
      exit_code = status.exit_code? || 128 + status.exit_signal?.not_nil!.to_i
      {exit_code: exit_code, stdout: output.to_s, stderr: error.to_s}
    ensure
      File.delete(object_path) if File.exists?(object_path)
      File.delete(executable_path) if File.exists?(executable_path)
    end
  end

  def self.link_and_compare_full_width_result(ir : Smalang::IrModule, expected : UInt64) : Int32
    object_bytes = Smalang::X86_64Backend.new.emit_with_main_result_assertion(ir, expected)
    base_path = File.join(Dir.tempdir, "smalang-backend-wide-#{Process.pid}")
    object_path = "#{base_path}.o"
    executable_path = "#{base_path}-harness"

    begin
      File.write(object_path, String.new(object_bytes.to_unsafe, object_bytes.size))
      linker_error = IO::Memory.new
      link_status = Process.run(
        "ld",
        ["-e", "_start", object_path, "-o", executable_path],
        output: Process::Redirect::Close,
        error: linker_error
      )
      raise "ld failed to link full-width result check: #{linker_error}" unless link_status.success?

      Process.run(
        executable_path,
        output: Process::Redirect::Close,
        error: Process::Redirect::Close
      ).exit_code
    ensure
      [object_path, executable_path].each do |path|
        File.delete(path) if File.exists?(path)
      end
    end
  end

  def self.link_binary_and_compare_full_width_result(
    type : Smalang::IrType,
    left_value : Int128,
    right_value : Int128,
    expected_result : UInt64,
    &operation : Smalang::IrFunction, Smalang::BlockId, Smalang::ValueId, Smalang::ValueId -> Smalang::ValueId
  ) : Int32
    ir = Smalang::IrModule.new
    function = ir.add_function("main", Array(Smalang::IrType).new, type)
    entry = function.entry_block_id
    left = function.emit_constant(entry, type, left_value)
    right = function.emit_constant(entry, type, right_value)
    result = operation.call(function, entry, left, right)
    function.emit_return(entry, result)

    link_and_compare_full_width_result(ir, expected_result)
  end

  def self.link_invoke_binary_and_compare_full_width_result(
    type : Smalang::IrType,
    left_value : Int128,
    right_value : Int128,
    expected_result : UInt64,
    &operation : Smalang::IrFunction, Smalang::BlockId, Smalang::ValueId, Smalang::ValueId, Smalang::BlockId, Smalang::BlockId -> Smalang::IrInvokeResults
  ) : Int32
    ir = Smalang::IrModule.new
    function = ir.add_function("main", Array(Smalang::IrType).new, type)
    entry = function.entry_block_id
    left = function.emit_constant(entry, type, left_value)
    right = function.emit_constant(entry, type, right_value)
    normal = function.add_block("normal")
    unwind = function.add_block("unwind")
    result = operation.call(function, entry, left, right, normal, unwind)
    function.emit_return(normal, result.value_id)
    function.emit_resume_exception(unwind, result.exception_id)

    link_and_compare_full_width_result(ir, expected_result)
  end
end
