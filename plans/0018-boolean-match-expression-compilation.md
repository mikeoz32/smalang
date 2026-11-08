# Boolean Match Expression Compilation

## Goal

Complete the first source-level boolean `match` slice so examples can compile to native binaries and run. Build on the parsed AST and existing Match core.

## Agreed Behavior

- The scrutinee has type `bool`. Supported patterns are `true`, `false`, and wildcard `_`.
- Cases are exhaustive if they contain one `true` and one `false` pattern, or one bool literal followed by a final wildcard. Reject duplicate, missing, or unreachable cases during semantic analysis.
- Every case produces a value of the same exact type. The whole match has that type; do not add implicit conversions.
- Evaluate the scrutinee once. Lower selection through the existing `branch`/`phi` Match core; extend that core to normalize wildcard cases to the missing boolean outcome.
- Keep expression syntax, inline case results, and four-space indentation from plan 0017. Do not add other pattern forms, guards, bindings, arbitrary case statements, or backend Match opcodes.

## Acceptance Criteria

- Semantic analysis validates scrutinee type, exhaustiveness, duplicate and unreachable patterns, and exact result type agreement with source-located compile-time diagnostics.
- IR lowering handles match expressions in returns, call arguments, nested matches, and result expressions, evaluates each scrutinee once, and emits verified IR using the existing Match core.
- Add two `.py` examples: an explicit `true`/`false` match that exercises both branches, and a literal-plus-wildcard default match.
- End-to-end specs compile the checked-in examples through semantic analysis, IR lowering, native linking, and execution; assert their exit values.
- Invalid source matches fail before IR lowering with specific diagnostics.

## Implementation Steps

1. Add failing source-program behavior tests for both patterns forms and each invalid semantic case.
2. Implement semantic typing and validation for `MatchExpressionNode`, preserving contextual integer-literal typing and exact type matching.
3. Extend Match core wildcard normalization and lower match expression results through `branch` and `phi`, including nested expression and call cases.
4. Add the two examples and specs that compile and execute those files.
5. Update README to describe the now-supported compile-time and runtime behavior; run documented checks and review the full diff against `AGENTS.md`.

## Verification

- Confirm each new behavior test fails for the intended reason before implementing it.
- Run focused semantic, Match core, and IR lowering specs during implementation.
- Run `crystal tool format --check`, `crystal spec`, and `git diff --check` after implementation.
