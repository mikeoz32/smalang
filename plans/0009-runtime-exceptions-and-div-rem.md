# Runtime Exceptions and Integer Division Plan

## Goal

Add signed and unsigned integer `div`/`rem` to the typed IR and Linux x86_64 backend, with a complete runtime exception path for runtime-dependent failures. The exception model includes explicit IR control flow, system unwinding, cleanup behavior, source-level stack traces, and reporting of uncaught exceptions.

## Agreed behavior

- This work consumes verified IR. The semantic-analysis pass rejects division by a compile-time zero before lowering; this plan covers only a divisor that is zero at runtime.
- `div` and `rem` are typed SSA operations over matching `isize` or `usize` operands and results. They do not add `/` or `%` to source syntax in this feature.
- Signed division truncates toward zero. Signed remainder has the sign of the dividend. For `INT_MIN / -1`, the quotient is `INT_MIN` and the remainder is `0`, matching Go.
- Unsigned `div` and `rem` use unsigned quotient and remainder semantics.
- A zero divisor detected at runtime creates a catchable runtime-generated `DivisionByZero` exception. Explicit user-raised exceptions are deferred.
- Runtime exception kinds are compiler/runtime-private tags; they do not require source enums, classes, or structs. IR handlers can match a built-in kind or catch any exception.
- Every function call is potentially throwing in the first version; no may-throw effect analysis is added.
- A potentially throwing operation is represented by an `invoke` terminator with normal and exceptional successors. The exceptional successor receives an opaque exception SSA value. SSA merges use explicit `phi` instructions with predecessor/value pairs.
- Cleanup blocks are represented from the start. If cleanup throws during unwinding, the new exception becomes active and the prior exception is retained as a suppressed error.
- Handler dispatch is explicit in IR: an exception-dispatch terminator lists ordered built-in-kind cases, an optional catch-all, and a propagation default. The personality matches kinds from LSDA actions and enters the landing pad with a selector; the landing pad dispatches to the selected IR block.
- Use the system DWARF/Itanium unwinder. Emit unwind metadata and source line locations sufficient for source-level stack traces.
- A common smalang runtime owns the process entry: its C `main` calls a generated `__smalang_entry` wrapper. That wrapper invokes source `main` and has a catch-all landing pad that reports an uncaught exception through the runtime after cleanups run.
- Keep the S-expression form as a diagnostic IR dump and extend it to show the new operations and control-flow edges; it is not a serialization format.

## Frozen compiler/runtime boundary

- Implement the runtime in C and link its common static archive into each generated executable with the existing `cc` linker boundary. Use the system `libgcc_s` implementation of the Itanium `_Unwind_*` base interface; do not depend on the C++ exception runtime or C++ typed-exception ABI.
- Give the runtime exception record a private layout beginning with `_Unwind_Exception`, followed by a fixed-width built-in kind tag and ownership of a suppressed-exception chain. Allocate records on the heap; the record cleanup callback releases the record and any suppressed records it owns.
- Use a Smalang-specific personality routine with two-phase search/cleanup behavior. Emit `.eh_frame` CFI and a versioned Smalang LSDA in `.gcc_except_table`; the LSDA stores invoke call-site ranges, landing-pad offsets, cleanup actions, and built-in catch-kind/catch-all actions. Foreign exceptions are not catchable by Smalang handlers; cleanup actions still run while they pass through Smalang frames.
- Encode frame, personality, and LSDA references as PC-relative signed 32-bit pointers where representable. Extend ELF relocations for `.eh_frame`, `.gcc_except_table`, and debug sections; the system linker may create `.eh_frame_hdr`/`PT_GNU_EH_FRAME` from `.eh_frame`.
- Rename the source `main` function to `__smalang_user_main`. The runtime archive supplies ELF `main` and calls a generated `__smalang_entry` wrapper, which invokes the source function and provides the top-level catch-all landing pad. The runtime reports the exception after stack cleanups and returns a nonzero process status. If `_Unwind_RaiseException` unexpectedly reports no handler, the runtime uses the previously captured stack as a fallback.
- Before calling `_Unwind_RaiseException`, capture frame addresses with `_Unwind_Backtrace` into the exception record. This preserves the source call stack for printing after phase-two unwinding reaches the top-level handler. Use the Itanium exception cleanup callback to release the record and its suppressed chain when the handler finishes.
- Emit DWARF 5 `.debug_line` and `.debug_line_str`, plus a minimal `.debug_info` compile unit and `.debug_abbrev` reference for standard DWARF consumers. The runtime reads line rows from `/proc/self/exe`, adjusts PCs by the main executable's load bias for PIE, and uses the executable's `.symtab` to name frames. It uses `_Unwind_Backtrace` for frame addresses; return-address frames are looked up at the preceding instruction address.
- Preserve source filename and line on IR operations/call sites so the line table can map generated code. Missing locations in hand-built backend fixtures remain explicitly absent and produce an unknown-source frame rather than fabricated locations.

## Scope

- Extend typed IR with the required multi-block control flow, terminators, exceptional edges, exception values, `phi`, cleanup representation, and signed/unsigned `div` and `rem`.
- Extend IR verification and its diagnostic S-expression dump for those contracts.
- Extend the x86_64 backend and ELF writer to lower integer division/remainder, emit runtime checks/calls, and write the system unwinder and source-line metadata with necessary symbols and relocations.
- Provide the runtime exception ABI and operations for creating, matching, propagating, suppressing, and reporting runtime exceptions.
- Carry source file and line locations from existing source/semantic facts through AST-to-IR into generated metadata, without changing the source grammar.
- Integrate the generated executable with the common runtime and system unwinder.

## Non-goals

- Add source-level `try/catch`, `finally`, `raise`, `/`, or `%` syntax.
- Add source enums, classes, structs, or a general user-defined exception hierarchy.
- Add FFI, foreign exception interoperability, custom DWARF unwinding, or call-effect analysis.
- Add compile-time constant-expression validation to IR or the backend; known constant zero divisors are rejected by semantic analysis.
- Define overflow behavior for arithmetic other than the agreed signed division edge case `INT_MIN / -1`.

## Implementation steps

1. **Freeze the compiler/runtime boundary — complete.** README and this section record exception ownership, runtime entry ABI, system unwinder/personality contract, LSDA, ELF relocations, and DWARF line strategy.
2. **Add the IR control-flow foundation — complete.** The IR now has blocks, terminators, `invoke`, exception edge values, predecessor-based `phi`, exception dispatch, suppression, resume, verification, and S-expression dumps.
3. **Add division operations to IR — complete.** Typed signed/unsigned `div` and `rem` are `invoke` operations with explicit normal and exceptional successors. This slice models only runtime-dependent zero; compile-time constants remain semantic analysis' responsibility.
4. **Add x86_64 control-flow lowering — complete.** Emit conditional branches, jumps, `invoke` call normal continuations, and `phi` edge copies. Multi-block functions currently use stack locations so values remain correct across arbitrary CFG edges. A zero `branch` condition means false. Runtime exception propagation and division machine code are still pending; `resume` is currently an unreachable trap in this intermediate slice.
5. **Emit unwind frame metadata — emission implemented.** Generate CFI for function prologues, epilogues, and return sites; add `.eh_frame` and its PC-relative relocations to ELF objects. `readelf` validates the CIE/FDE rules and relocations. Verify traversal through nested generated frames after runtime raising is wired in.
6. **Implement the exception runtime core.** Add private heap exception records and suppressed-error ownership, stack-address capture, and `_Unwind_RaiseException` / `_Unwind_Resume` integration through the system `libgcc_s` unwinder.
7. **Implement personality and LSDA.** Emit versioned Smalang call-site/action data in `.gcc_except_table`; add two-phase handler matching, landing pads, cleanup execution, catch dispatch, and replacement/suppressed exception behavior.
8. **Lower runtime division and remainder.** Emit signed and unsigned quotient/remainder instructions, zero checks that raise `DivisionByZero`, and the `INT_MIN / -1` result rule. Test runtime divisors only; constant-zero rejection belongs to semantic analysis.
9. **Add runtime entry and source-level traces.** Add the C runtime's process `main`, generated `__smalang_entry` catch-all wrapper, uncaught reporting, DWARF 5 line tables, minimal compile-unit metadata, and source/symbol resolution for captured PCs.
10. **Integrate and verify vertical slices.** Cover runtime signed/unsigned results, zero-divisor handling, matching/catch-all, cleanup, suppressed errors, nested calls, and uncaught source traces. Run the documented project checks after each slice.

### Current implementation checkpoint

Steps 1–4 and `.eh_frame` object emission from step 5 are implemented in the feature worktree. Ordinary calls cannot yet produce runtime exceptions because no throwing machine operation is emitted; exception dispatch, suppression, LSDA, and actual unwinding remain subsequent steps. Do not treat the intermediate `resume` trap as the completed exception behavior.

## Acceptance criteria

- The verifier accepts valid `invoke`, exceptional successors, `phi`, cleanup, `div`, and `rem` forms and rejects malformed types, definitions, uses, predecessor lists, or terminators.
- The S-expression diagnostic dump exposes the new division operations, normal/exceptional edges, exception values, `phi`, and cleanup flow.
- Generated code produces correct signed and unsigned quotient/remainder results, including truncation toward zero, dividend-signed remainder, and `INT_MIN / -1`.
- A runtime zero divisor raises a catchable `DivisionByZero` exception; a handler can match its built-in kind or catch all.
- A cleanup that throws replaces the active exception while preserving the previous exception in the suppressed chain.
- Generated ELF objects link against the selected system unwinder and common runtime; calls and exception propagation unwind correctly across nested smalang functions.
- An uncaught exception prints a source-level stack trace with file and line information and exits with a nonzero status.
- Source `main` links as `__smalang_user_main`; the common runtime supplies ELF `main`, and the generated `__smalang_entry` wrapper preserves the source result and provides the top-level exception landing pad.
- No source grammar or language-level exception type changes are introduced.

## Verification

- Follow the repository's test-first behavior workflow for each implementation slice.
- Test IR invariants where they form part of the stable IR contract; test backend/runtime behavior by linking and executing generated ELF objects.
- Check ELF unwind and DWARF sections/relocations when diagnosing failures, and verify observable exception behavior in generated executables.
- Run Crystal formatting, the documented `crystal spec` suite, and `git diff --check` before considering the implementation complete.

## Design references

- [Itanium C++ ABI, Level I exception and unwinder interface](https://itanium-cxx-abi.github.io/cxx-abi/abi-eh.html)
- [System V AMD64 ABI](https://gitlab.com/x86-psABIs/x86-64-ABI)
- [DWARF Version 5 standard](https://dwarfstd.org/doc/DWARF5.pdf)
