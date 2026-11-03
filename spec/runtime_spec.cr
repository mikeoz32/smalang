require "spec"

describe "Smalang runtime exceptions" do
  it "captures frames before an unhandled unwind and owns suppressed exceptions" do
    base_path = File.join(Dir.tempdir, "smalang-runtime-#{Process.pid}")
    harness_path = "#{base_path}.c"
    executable_path = "#{base_path}-harness"
    compiler_error = IO::Memory.new

    File.write(harness_path, <<-C)
      #include "smalang_runtime.h"
      #include <unwind.h>

      __attribute__((noinline)) static int verify_capture(void) {
        struct smalang_exception *exception = smalang_exception_new(SMALANG_EXCEPTION_DIVISION_BY_ZERO);
        if (exception == 0) return 1;
        if (smalang_exception_kind(exception) != SMALANG_EXCEPTION_DIVISION_BY_ZERO) return 2;

        _Unwind_Reason_Code reason = smalang_exception_raise(exception);
        if (reason != _URC_END_OF_STACK) return 3;
        if (smalang_exception_frame_count(exception) < 3) return 4;
        if (smalang_exception_frame_at(exception, 0) == 0) return 5;

        smalang_exception_delete(exception);
        return 0;
      }

      static int verify_suppressed_ownership(void) {
        struct smalang_exception *active = smalang_exception_new(SMALANG_EXCEPTION_DIVISION_BY_ZERO);
        struct smalang_exception *previous = smalang_exception_new(SMALANG_EXCEPTION_DIVISION_BY_ZERO);
        struct smalang_exception *oldest = smalang_exception_new(SMALANG_EXCEPTION_DIVISION_BY_ZERO);
        if (active == 0 || previous == 0 || oldest == 0) return 6;
        if (!smalang_exception_suppress(active, previous)) return 7;
        if (!smalang_exception_suppress(previous, oldest)) return 8;
        if (smalang_exception_suppressed_count(active) != 2) return 9;
        if (smalang_exception_suppress(oldest, active)) return 10;
        smalang_exception_delete(active);
        return 0;
      }

      int main(void) {
        int result = verify_capture();
        return result == 0 ? verify_suppressed_ownership() : result;
      }
      C

    begin
      compiler_status = Process.run(
        "cc",
        [
          "-std=c11",
          "-Wall",
          "-Wextra",
          "-Werror",
          "-fno-omit-frame-pointer",
          "-I#{__DIR__}/../src/runtime",
          harness_path,
          "#{__DIR__}/../src/runtime/smalang_runtime.c",
          "-o",
          executable_path,
        ],
        output: Process::Redirect::Close,
        error: compiler_error
      )
      raise "C runtime harness failed to compile: #{compiler_error}" unless compiler_status.success?

      Process.run(
        executable_path,
        output: Process::Redirect::Close,
        error: Process::Redirect::Close
      ).exit_code.should eq(0)
    ensure
      File.delete(harness_path) if File.exists?(harness_path)
      File.delete(executable_path) if File.exists?(executable_path)
    end
  end
end
