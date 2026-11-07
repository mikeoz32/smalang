# Pattern Matching Core

## Goal

Establish pattern matching as a hard architectural requirement and add the first compiler-internal Match core slice using boolean literal patterns.

## Agreed behavior

- Language constructs that select behavior must build on one shared Match model.
- Match operates on an ordered bundle of scrutinee values and clauses, so future function clauses can dispatch over multiple positional and named arguments.
- The argument bundle is a compiler-level representation; runtime `*args`/`**kwargs` containers are not required.
- This slice supports only `true` and `false` patterns over one `bool` scrutinee. It requires both cases exactly once.
- Match lowers to existing `branch` and `phi` IR and preserves the selected result type.
- Every invalid Match-core construction must fail during compilation with its specific diagnostic before mutating IR or reaching backend emission.
- Since Match has no source syntax or source span yet, this slice validates diagnostic kind/message and compile-time rejection; source file/line rendering is deferred until a source construct provides locations.
- Source-level `match`, boolean operators, function clauses, multi-dispatch, type patterns, guards, and bindings remain out of scope.

## Implementation steps

1. Document the hard Match-core requirement and future consumers in `README.md`.
2. Add failing compiler-core specs for selecting each bool case, result type preservation, and every invalid-input rejection path in the Match validator.
3. Add the typed Match model and lower the initial bool-pattern slice into existing CFG and `phi` instructions.
4. Verify generated native behavior, run the relevant specs and full documented checks, and review the complete diff against `AGENTS.md`.

## Acceptance criteria

- The Match model carries multiple ordered scrutinees and per-clause patterns without requiring runtime argument containers.
- The initial lowerer accepts exactly one bool scrutinee and two distinct bool literal patterns.
- Valid matches select the corresponding result at runtime, preserve result types through `phi`, and pass IR verification.
- Missing, duplicate, mismatched, unsupported, or structurally invalid Match inputs each produce the expected compile-time diagnostic before changing IR.
- README records Match as a core requirement and states that future choice constructs must reuse it.

## Invalid-input diagnostic coverage

Test each applicable validator failure independently: unsupported scrutinee count/type, undefined or non-dominating SSA values; unknown, terminated, or aliased source/join/body blocks; non-empty join; wrong clause count; pattern arity mismatch; unsupported pattern kind; missing or duplicate bool cases; duplicate body blocks; external body predecessors; body blocks that do not jump to the join; unexpected join predecessors; mismatched or unavailable result values. Assert the specific diagnostic kind/message and that lowering has not appended IR instructions, values, or blocks.

## Verification

- Test both bool outcomes through generated native code and `ld`.
- Test every listed invalid-input diagnostic and confirm rejection occurs before IR mutation.
- Run focused specs, `crystal tool format --check`, `crystal spec`, and `git diff --check`.
