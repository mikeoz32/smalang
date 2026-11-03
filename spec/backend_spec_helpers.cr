require "../src/smalang/ir"
require "../src/smalang/x86_64_backend"

module BackendSpecHelpers
  def self.link_and_run(ir : Smalang::IrModule) : Int32
    object_bytes = Smalang::X86_64Backend.new.emit(ir)
    object_path = File.join(Dir.tempdir, "smalang-backend-#{Process.pid}.o")
    executable_path = File.join(Dir.tempdir, "smalang-backend-#{Process.pid}")

    begin
      File.write(object_path, String.new(object_bytes.to_unsafe, object_bytes.size))
      linker_error = IO::Memory.new
      link_status = Process.run(
        "cc",
        [object_path, "-o", executable_path],
        output: Process::Redirect::Close,
        error: linker_error
      )
      raise "cc failed: #{linker_error}" unless link_status.success?

      Process.run(
        executable_path,
        output: Process::Redirect::Close,
        error: Process::Redirect::Close
      ).exit_code
    ensure
      File.delete(object_path) if File.exists?(object_path)
      File.delete(executable_path) if File.exists?(executable_path)
    end
  end
end
