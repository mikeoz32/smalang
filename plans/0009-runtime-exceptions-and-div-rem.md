# Runtime Exceptions and Integer Division Plan

## Goal

Add signed and unsigned `div`/`rem` to typed IR and Linux x86_64 code generation, with runtime-only division-by-zero exceptions, explicit propagation, cleanup ownership, stack traces, and a standalone ELF entry. The generated executable must not depend on a C compiler, libc, `libgcc_s`, or LLVM `libunwind`.

## Agreed behavior

- The semantic-analysis pass rejects division by a compile-time zero. This plan covers only divisors that are zero at runtime.
- `div` and `rem` remain typed SSA operations over matching `isize` or `usize`; this feature does not add `/` or `%` syntax.
- Signed division truncates toward zero; signed remainder follows the dividend. `INT_MIN / -1` yields `INT_MIN`, and remainder yields `0`. Unsigned operations use unsigned quotient and remainder semantics.
- Runtime zero produces a catchable compiler-private `DivisionByZero` exception. No source `raise`, enums, classes, or structs are added.
- Every generated Smalang function uses a private result ABI: `RAX` contains its ordinary result, `RDX` contains an owned exception pointer, and `RDX == 0` means success. `return` clears `RDX`; `resume` returns the exception pointer in `RDX`.
- `invoke` branches on `RDX`, defining its ordinary result on the normal edge and its exception value on the exceptional edge. Calls are potentially throwing; no may-throw analysis is added.
- Exception SSA values have explicit ownership. `phi` and dispatch transfer ownership along the selected edge; `resume` transfers ownership to the caller; `suppress(new, old)` consumes both and returns `new` owning the suppressed chain; `exception.release` consumes a caught exception. The verifier rejects use after consumption, duplicate ownership transfer, and paths that abandon an owned exception.
- Cleanup blocks are ordinary IR control flow. If cleanup raises a new exception, suppression attaches the previous exception to the new active one.
- The backend emits Smalang runtime functions and `_start` directly into the ELF object. The runtime uses Linux x86_64 `mmap`, `munmap`, `write`, and `exit` syscalls. `ld` is the only external tool permitted for producing an executable.
- Generated functions maintain a compiler-owned frame chain with function name and current source file/line. Raising copies at most 64 active frames into the exception record. The runtime prints uncaught exceptions and their suppressed chain, then exits nonzero.
- Keep `.eh_frame` CFI and DWARF data for conventional debuggers. They do not participate in exception propagation. Do not emit a personality routine, `.gcc_except_table`, or `_Unwind_*` reference.
- Keep the S-expression dump diagnostic-only and expose the exception ownership operation there.

## Scope

- Preserve the existing verified IR control-flow foundation, `invoke`, exception dispatch, suppression, and signed/unsigned division operations.
- Add exception release and ownership verification to IR.
- Replace the C/libgcc unwinder path with a generated private ABI, exception/frame records, Linux syscall runtime routines, and standalone entry code.
- Lower calls, `resume`, dispatch, suppression, `div`, and `rem` through the explicit propagation ABI.
- Preserve source locations through AST-to-IR and backend metadata so runtime traces identify function, file, and line.
- Produce ELF64 relocatable objects that link with `ld` and require no undefined runtime/library symbols.

## Non-goals

- Add source-level `try/catch`, `finally`, `raise`, `/`, or `%` syntax.
- Add user-defined exception types or foreign exception interoperability.
- Add thread support; the initial compiler has no source threading feature and uses one process-level frame chain.
- Add compile-time constant-expression validation to IR or backend; known zero divisors are rejected by semantic analysis.
- Define overflow behavior for arithmetic other than `INT_MIN / -1`.

## Implementation steps

1. **Record the revised boundary — complete.** Update README and this plan to replace C runtime/system unwinder with the explicit generated ABI and syscall-only runtime.
2. **Define exception ownership in IR — complete.** Add `exception.release`, update the S-expression dump, and verify exception ownership transfers through invoke edges, phi, dispatch, suppress, release, and resume.
3. **Generate runtime data and syscall helpers — complete.** Add exception records, frame-chain records, source strings, allocation/release, suppression, reporting, and syscall instruction support to the x86_64 backend and ELF writer.
4. **Lower exception-aware control flow — complete.** Implement the `RAX`/`RDX` ABI for returns and invokes, frame push/update/pop, selector dispatch by built-in kind, suppression, and exception resume. Remove C runtime, personality, and LSDA code.
5. **Lower `div` and `rem` — complete.** Emit zero checks and signed/unsigned division/remainder instructions; preserve the agreed `INT_MIN / -1` result. Only runtime divisors are tested.
6. **Emit standalone entry and traces — complete.** Generate `_start`, call `__smalang_user_main`, report uncaught and suppressed errors with source locations, and exit through syscalls. Retain debugger CFI/DWARF sections.
7. **Verify complete ELF behavior — complete.** Link generated objects with `ld`; test normal and exceptional paths, catches, cleanup replacement, division results, source traces, and absence of runtime/library dependencies.

## Acceptance criteria

- The IR verifier enforces exception ownership and preserves the established S-expression form for CFG, invoke, phi, dispatch, suppression, and release.
- Calls and `resume` propagate exception pointers across nested generated functions using `RDX`; normal return values remain in `RAX`.
- A runtime zero divisor raises `DivisionByZero`; kind-specific and catch-all dispatch choose the correct IR successor.
- A caught exception can be released; suppression preserves the prior exception chain; cleanup failure makes the new exception active.
- Signed and unsigned division/remainder match the agreed semantics, including `INT_MIN / -1`.
- Uncaught errors print function, file, line, and suppressed errors, then exit nonzero.
- `ld` links the generated object without C startup objects, libc, GCC/LLVM unwinder, or unresolved symbols. The resulting ELF has no dynamic library dependency.
- `.eh_frame` and DWARF remain readable by standard tools; exception handling does not depend on them.
- No source grammar changes are introduced.

## Verification

- Follow test-first behavior development for each implementation slice.
- Test IR contracts with focused verifier and dump specs; test backend behavior by linking and executing generated ELF objects with `ld`.
- Inspect ELF sections and symbol/relocation tables to confirm there are no C runtime, `_Unwind_*`, `libgcc_s`, libc, or libunwind references.
- Run Crystal formatting, the documented `crystal spec` suite, and `git diff --check` before each implementation checkpoint is committed.

## Design references

- [System V AMD64 ABI](https://gitlab.com/x86-psABIs/x86-64-ABI)
- [DWARF Version 5 standard](https://dwarfstd.org/doc/DWARF5.pdf)
