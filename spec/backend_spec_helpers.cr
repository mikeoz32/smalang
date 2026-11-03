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

  def self.link_and_compare_full_width_result(ir : Smalang::IrModule, expected : UInt64) : Int32
    object_bytes = Smalang::X86_64Backend.new.emit(ir)
    base_path = File.join(Dir.tempdir, "smalang-backend-wide-#{Process.pid}")
    object_path = "#{base_path}.o"
    library_path = "#{base_path}.so"
    harness_path = "#{base_path}.c"
    executable_path = "#{base_path}-harness"

    begin
      File.write(object_path, String.new(object_bytes.to_unsafe, object_bytes.size))
      library_error = IO::Memory.new
      library_status = Process.run(
        "cc",
        ["-shared", object_path, "-o", library_path],
        output: Process::Redirect::Close,
        error: library_error
      )
      raise "cc failed to link shared object: #{library_error}" unless library_status.success?

      File.write(harness_path, <<-C)
        #include <dlfcn.h>
        #include <stddef.h>
        #include <stdint.h>

        int main(void) {
          void *library = dlopen("#{library_path}", RTLD_NOW | RTLD_LOCAL);
          if (library == NULL) return 2;

          uint64_t (*entry)(void) = (uint64_t (*)(void)) dlsym(library, "main");
          if (entry == NULL) {
            dlclose(library);
            return 3;
          }

          int status = entry() == UINT64_C(#{expected}) ? 0 : 1;
          dlclose(library);
          return status;
        }
        C

      harness_error = IO::Memory.new
      harness_status = Process.run(
        "cc",
        [harness_path, "-ldl", "-o", executable_path],
        output: Process::Redirect::Close,
        error: harness_error
      )
      raise "cc failed to compile result harness: #{harness_error}" unless harness_status.success?

      Process.run(
        executable_path,
        output: Process::Redirect::Close,
        error: Process::Redirect::Close
      ).exit_code
    ensure
      [object_path, library_path, harness_path, executable_path].each do |path|
        File.delete(path) if File.exists?(path)
      end
    end
  end
end
