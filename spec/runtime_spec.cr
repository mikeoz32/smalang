require "spec"
require "../src/smalang/ir"
require "../src/smalang/x86_64_backend"
require "./backend_spec_helpers"

module RuntimeSpecHelpers
  def self.division(type : Smalang::IrType, left : Int128, right : Int128, remainder : Bool = false) : Smalang::IrModule
    ir = Smalang::IrModule.new
    main = ir.add_function("main", Array(Smalang::IrType).new, type)
    entry = main.entry_block_id
    normal = main.add_block("normal")
    failed = main.add_block("failed")
    left_value = main.emit_constant(entry, type, left)
    right_value = main.emit_constant(entry, type, right)
    result = if remainder
               main.emit_invoke_remainder(entry, type, left_value, right_value, normal, failed)
             else
               main.emit_invoke_divide(entry, type, left_value, right_value, normal, failed)
             end
    main.emit_return(normal, result.value_id)
    main.emit_exception_release(failed, result.exception_id)
    fallback = main.emit_constant(failed, type, 0)
    main.emit_return(failed, fallback)
    ir
  end
end

describe "Smalang generated exception runtime" do
  it "implements signed and unsigned division and remainder without libc" do
    signed_division = RuntimeSpecHelpers.division(Smalang::IrType::Isize, 84, 2)
    BackendSpecHelpers.link_and_compare_full_width_result(signed_division, 42_u64).should eq(0)

    signed_remainder = RuntimeSpecHelpers.division(Smalang::IrType::Isize, -23, 5, true)
    BackendSpecHelpers.link_and_compare_full_width_result(signed_remainder, 0xffff_ffff_ffff_ffff_u64 - 2_u64).should eq(0)

    unsigned_division = RuntimeSpecHelpers.division(Smalang::IrType::Usize, 85, 2)
    BackendSpecHelpers.link_and_compare_full_width_result(unsigned_division, 42_u64).should eq(0)

    unsigned_remainder = RuntimeSpecHelpers.division(Smalang::IrType::Usize, 85, 2, true)
    BackendSpecHelpers.link_and_compare_full_width_result(unsigned_remainder, 1_u64).should eq(0)
  end

  it "defines signed INT_MIN divided by negative one as INT_MIN and remainder zero" do
    minimum = Int64::MIN.to_i128
    quotient = RuntimeSpecHelpers.division(Smalang::IrType::Isize, minimum, -1)
    BackendSpecHelpers.link_and_compare_full_width_result(quotient, 0x8000_0000_0000_0000_u64).should eq(0)

    remainder = RuntimeSpecHelpers.division(Smalang::IrType::Isize, minimum, -1, true)
    BackendSpecHelpers.link_and_compare_full_width_result(remainder, 0_u64).should eq(0)
  end

  it "dispatches and releases a caught division-by-zero exception" do
    ir = Smalang::IrModule.new
    main = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    entry = main.entry_block_id
    normal = main.add_block("normal")
    dispatch = main.add_block("dispatch")
    caught = main.add_block("caught")
    resume = main.add_block("resume")
    left = main.emit_constant(entry, Smalang::IrType::Isize, 7)
    zero = main.emit_constant(entry, Smalang::IrType::Isize, 0)
    result = main.emit_invoke_divide(entry, Smalang::IrType::Isize, left, zero, normal, dispatch)
    main.emit_return(normal, result.value_id)
    main.emit_exception_dispatch(dispatch, result.exception_id, [
      Smalang::IrExceptionCase.new(Smalang::IrExceptionKind::DivisionByZero, caught),
    ], resume)
    main.emit_exception_release(caught, result.exception_id)
    recovered = main.emit_constant(caught, Smalang::IrType::Isize, 42)
    main.emit_return(caught, recovered)
    main.emit_resume_exception(resume, result.exception_id)

    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "dispatches and releases a caught invalid heap storage argument" do
    ir = Smalang::IrModule.new
    main = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    entry = main.entry_block_id
    normal = main.add_block("normal")
    dispatch = main.add_block("dispatch")
    caught = main.add_block("caught")
    resume = main.add_block("resume")
    zero = main.emit_constant(entry, Smalang::IrType::Usize, 0)
    allocation = main.emit_invoke_heap_storage(entry, zero, 16, normal, dispatch)
    success = main.emit_constant(normal, Smalang::IrType::Isize, 0)
    main.emit_return(normal, success)
    main.emit_exception_dispatch(dispatch, allocation.exception_id, [
      Smalang::IrExceptionCase.new(Smalang::IrExceptionKind::InvalidArgument, caught),
    ], resume)
    main.emit_exception_release(caught, allocation.exception_id)
    recovered = main.emit_constant(caught, Smalang::IrType::Isize, 42)
    main.emit_return(caught, recovered)
    main.emit_resume_exception(resume, allocation.exception_id)

    ir.verify.should be_empty
    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "keeps a user function named _start local to the generated entry point" do
    ir = Smalang::IrModule.new
    user_function = ir.add_function("_start", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    user_value = user_function.emit_constant(user_function.entry_block_id, Smalang::IrType::Isize, 42)
    user_function.emit_return(user_function.entry_block_id, user_value)

    main = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    normal = main.add_block("normal")
    failed = main.add_block("failed")
    target = ir.internal_call_target(user_function.id).not_nil!
    call = main.emit_invoke_call(main.entry_block_id, target, Array(Smalang::ValueId).new, normal, failed)
    main.emit_return(normal, call.value_id)
    main.emit_resume_exception(failed, call.exception_id)

    BackendSpecHelpers.link_and_run(ir).should eq(42)
  end

  it "reports a replacement exception and its suppressed predecessor" do
    ir = Smalang::IrModule.new
    main = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    entry = main.entry_block_id
    first_normal = main.add_block("first_normal")
    first_dispatch = main.add_block("first_dispatch")
    cleanup = main.add_block("cleanup")
    second_normal = main.add_block("second_normal")
    second_failed = main.add_block("second_failed")
    first_left = main.emit_constant(entry, Smalang::IrType::Isize, 1)
    zero = main.emit_constant(entry, Smalang::IrType::Isize, 0)
    first = main.emit_invoke_divide(entry, Smalang::IrType::Isize, first_left, zero, first_normal, first_dispatch)
    main.emit_return(first_normal, first.value_id)
    main.emit_exception_dispatch(first_dispatch, first.exception_id, [
      Smalang::IrExceptionCase.new(nil, cleanup),
    ])

    second_left = main.emit_constant(cleanup, Smalang::IrType::Isize, 2)
    second = main.emit_invoke_divide(cleanup, Smalang::IrType::Isize, second_left, zero, second_normal, second_failed)
    main.emit_exception_release(second_normal, first.exception_id)
    main.emit_return(second_normal, second.value_id)
    suppressed = main.emit_suppress_exception(second_failed, second.exception_id, first.exception_id)
    main.emit_resume_exception(second_failed, suppressed)

    result = BackendSpecHelpers.link_and_capture(ir)
    result[:exit_code].should eq(1)
    result[:stderr].should contain("Uncaught exception: DivisionByZero")
    result[:stderr].should contain("Suppressed exception: DivisionByZero")
  end

  it "preserves an existing suppressed chain when appending another exception" do
    ir = Smalang::IrModule.new
    main = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    entry = main.entry_block_id
    first_normal = main.add_block("first_normal")
    first_dispatch = main.add_block("first_dispatch")
    cleanup = main.add_block("cleanup")
    second_normal = main.add_block("second_normal")
    second_failed = main.add_block("second_failed")
    third_normal = main.add_block("third_normal")
    third_failed = main.add_block("third_failed")
    first_value = main.emit_constant(entry, Smalang::IrType::Isize, 1)
    zero = main.emit_constant(entry, Smalang::IrType::Isize, 0)
    first = main.emit_invoke_divide(entry, Smalang::IrType::Isize, first_value, zero, first_normal, first_dispatch)
    main.emit_return(first_normal, first.value_id)
    main.emit_exception_dispatch(first_dispatch, first.exception_id, [
      Smalang::IrExceptionCase.new(nil, cleanup),
    ])

    second_value = main.emit_constant(cleanup, Smalang::IrType::Isize, 2)
    second = main.emit_invoke_divide(cleanup, Smalang::IrType::Isize, second_value, zero, second_normal, second_failed)
    main.emit_exception_release(second_normal, first.exception_id)
    main.emit_return(second_normal, second.value_id)

    combined = main.emit_suppress_exception(second_failed, second.exception_id, first.exception_id)
    third_value = main.emit_constant(second_failed, Smalang::IrType::Isize, 3)
    third = main.emit_invoke_divide(second_failed, Smalang::IrType::Isize, third_value, zero, third_normal, third_failed)
    main.emit_exception_release(third_normal, combined)
    main.emit_return(third_normal, third.value_id)
    appended = main.emit_suppress_exception(third_failed, combined, third.exception_id)
    main.emit_resume_exception(third_failed, appended)

    result = BackendSpecHelpers.link_and_capture(ir)
    result[:exit_code].should eq(1)
    result[:stderr].lines.count { |line| line.starts_with?("Suppressed exception:") }.should eq(2)
  end

  it "links with ld and emits no external unwinder or dynamic runtime dependency" do
    ir = Smalang::IrModule.new
    main = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    zero = main.emit_constant(main.entry_block_id, Smalang::IrType::Isize, 0)
    main.emit_return(main.entry_block_id, zero)
    object_path = File.join(Dir.tempdir, "smalang-runtime-object-#{Process.pid}.o")
    executable_path = File.join(Dir.tempdir, "smalang-runtime-object-#{Process.pid}")

    begin
      object_bytes = Smalang::X86_64Backend.new.emit(ir)
      File.write(object_path, String.new(object_bytes.to_unsafe, object_bytes.size))
      symbol_output = IO::Memory.new
      symbol_status = Process.run("readelf", ["-Ws", object_path], output: symbol_output, error: Process::Redirect::Close)
      symbol_status.success?.should eq(true)
      symbol_output.to_s.should_not contain("_Unwind_")
      symbol_output.to_s.should_not contain("__smalang_personality_v1")
      symbol_output.to_s.lines.count do |line|
        fields = line.split
        fields.size > 6 && fields[6] == "UND"
      end.should eq(1)

      section_output = IO::Memory.new
      section_status = Process.run("readelf", ["-SW", object_path], output: section_output, error: Process::Redirect::Close)
      section_status.success?.should eq(true)
      section_output.to_s.should_not contain(".gcc_except_table")
      section_output.to_s.should contain(".eh_frame")

      linker_error = IO::Memory.new
      linker_status = Process.run("ld", ["-e", "_start", object_path, "-o", executable_path], output: Process::Redirect::Close, error: linker_error)
      linker_status.success?.should eq(true), linker_error.to_s

      dynamic_output = IO::Memory.new
      dynamic_status = Process.run("readelf", ["-d", executable_path], output: dynamic_output, error: Process::Redirect::Close)
      dynamic_status.success?.should eq(true)
      dynamic_output.to_s.should contain("There is no dynamic section")
    ensure
      File.delete(object_path) if File.exists?(object_path)
      File.delete(executable_path) if File.exists?(executable_path)
    end
  end

  it "captures nested source frames and reports an uncaught exception" do
    ir = Smalang::IrModule.new
    divide = ir.add_function("divide", [Smalang::IrType::Isize, Smalang::IrType::Isize], Smalang::IrType::Isize)
    normal = divide.add_block("normal")
    failed = divide.add_block("failed")
    division = divide.emit_invoke_divide(
      divide.entry_block_id,
      Smalang::IrType::Isize,
      divide.parameters[0].value_id,
      divide.parameters[1].value_id,
      normal,
      failed,
      Smalang::IrSourceLocation.new("trace_case.py", 11)
    )
    divide.emit_return(normal, division.value_id)
    divide.emit_resume_exception(failed, division.exception_id)

    main = ir.add_function("main", Array(Smalang::IrType).new, Smalang::IrType::Isize)
    left = main.emit_constant(main.entry_block_id, Smalang::IrType::Isize, 5)
    right = main.emit_constant(main.entry_block_id, Smalang::IrType::Isize, 0)
    call_normal = main.add_block("call_normal")
    call_failed = main.add_block("call_failed")
    target = ir.internal_call_target(divide.id).not_nil!
    call = main.emit_invoke_call(
      main.entry_block_id,
      target,
      [left, right],
      call_normal,
      call_failed,
      Smalang::IrSourceLocation.new("trace_case.py", 6)
    )
    main.emit_return(call_normal, call.value_id)
    main.emit_resume_exception(call_failed, call.exception_id)

    result = BackendSpecHelpers.link_and_capture(ir)
    result[:exit_code].should eq(1)
    result[:stderr].should contain("Uncaught exception: DivisionByZero")
    result[:stderr].should contain("at divide (trace_case.py:11)")
    result[:stderr].should contain("at main (trace_case.py:6)")
  end
end
