# Runtime Integer Overflow Semantics Plan

## Goal

Make overflow behavior for runtime `int` and `uint` arithmetic an explicit language and IR/backend contract.

## Agreed behavior

- Integer types have target-defined width `n`; on Linux x86_64, `n = 64`.
- Runtime `uint` addition, subtraction, and multiplication are computed modulo `2^n`.
- Runtime `int` addition, subtraction, and multiplication keep the low `n` result bits and interpret them as a two's-complement signed value. Overflow is deterministic and does not raise a runtime exception.
- These rules apply to typed IR `add`, `sub`, and `mul` for both signed and unsigned integer types. They do not add source-language multiplication syntax.
- Existing `div` and `rem` behavior remains unchanged, including `INT_MIN / -1 == INT_MIN` and remainder `0`.
- Compile-time constant overflow is outside this feature's scope.

## Scope

- Add linked backend behavior tests that check full-width overflow results for signed and unsigned `add`, `sub`, and `mul` at boundary values.
- Confirm the x86_64 backend preserves the agreed behavior through register allocation, spills, and executable return/control flow; change backend code only if a test exposes a mismatch.
- Replace the README roadmap item that leaves overflow unspecified with the agreed runtime semantics, and update the runtime/division plan's outdated non-goal.
- Do not change IR operations, S-expression dumps, source syntax, division semantics, or exception propagation.

## Implementation steps

1. **Add behavior tests first — complete.** Build typed IR programs that exercise overflow boundaries and link/run their generated ELF objects with `ld`. Check the complete 64-bit result through control flow rather than relying only on the process's 8-bit exit status.
2. **Check backend behavior — complete.** The new tests pass with the current x86_64 `add`, `sub`, and low-half `imul` instructions, so no backend change is needed.
3. **Record the contract — complete.** Update README with the runtime semantics and target-width rule; remove the obsolete overflow non-goal from plan 0009.
4. **Run the full verification suite — complete.** Format Crystal sources, run `crystal spec`, link/run the overflow behavior tests with `ld`, and check `git diff --check`.

## Acceptance criteria

- For both `isize` and `usize`, runtime `add`, `sub`, and `mul` return the agreed low-`n`-bit result at overflow boundaries.
- Signed overflow does not become an exception or trap; unsigned arithmetic wraps modulo `2^n`.
- Tests verify all result bits and pass through the generated ELF executable linked with `ld`.
- README no longer describes runtime integer overflow behavior as unspecified.
- No source grammar, IR dump, `div`/`rem`, or exception ABI changes are introduced.

## Verification

- Add behavior tests first and confirm they establish the contract against generated ELF results. If a future backend change is needed, first confirm a failing test identifies the intended mismatch.
- Run `crystal tool format --check`, `crystal spec`, and `git diff --check` before committing.
