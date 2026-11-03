require "../src/smalang/ir"
require "../src/smalang/x86_64_backend"

module BackendSpecHelpers
  def self.link_and_run(ir : Smalang::IrModule) : Int32
    link_and_capture(ir)[:exit_code]
  end

  def self.link_and_capture(ir : Smalang::IrModule) : NamedTuple(exit_code: Int32, stdout: String, stderr: String)
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
      status = Process.run(
        executable_path,
        output: output,
        error: error
      )
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
end
