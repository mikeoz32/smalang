# Boolean Type Frontend Plan

## Goal

Add the `bool` type and boolean literals to the source-language frontend, with semantic checking for typed function signatures and calls.

## Agreed behavior

- Add `bool` as a reserved type name and `true` / `false` as reserved boolean literals.
- Parse boolean literals into a dedicated AST expression node and allow `bool` in parameter and result annotations.
- Semantic analysis assigns boolean literals and bool parameters/calls the canonical `bool` type, and checks arguments and returns against declared types.
- Keep exact type matching: do not implicitly convert between `bool`, `int`, and `uint`.
- Keep `main() -> int` as the executable entry-point requirement.
- Do not add boolean operators, comparisons, conditions, or local variables.
- Do not add bool support to IR or the native backend. IR lowering must reject bool expressions explicitly. Boolean ABI and binary support remain deferred to a separate feature.

## Scope

- Extend lexer tokens, parser type parsing, AST, and semantic type checking for `bool`, `true`, and `false`.
- Update `README.md` to document the frontend support and explicitly mark bool IR/backend support as pending.
- Add focused source-level lexer, parser, and semantic behavior specs.

## Acceptance criteria

- `bool` is accepted in function parameter and result annotations; other type names remain rejected.
- `true` and `false` parse as boolean literal expressions and receive the `bool` semantic type.
- Bool parameters, returns, and direct function calls pass semantic analysis when types match.
- Mismatched `bool`/`int`/`uint` arguments and return values are rejected with source-located diagnostics.
- Arithmetic operators reject bool operands.
- The `main() -> int` entry-point rule is unchanged.
- No bool support, IR representation, or code generation is added to IR lowering or the backend; lowering explicitly rejects bool literals as unsupported.
- No ABI, logical operator, or control-flow behavior is added.

## Implementation steps

1. Add lexer tokens for `bool`, `true`, and `false`, and cover keyword boundaries and identifiers that merely share their prefixes.
2. Add `AstType::Bool` and a boolean literal AST node; update the AST visitor and parser for type annotations and literals.
3. Add the canonical semantic bool type and type boolean literals, parameters, returns, and calls; preserve strict type matching and the existing `main` rule.
4. Make IR lowering explicitly reject boolean literal expressions without adding bool IR support.
5. Add focused behavior specs for accepted and rejected source programs, then update the README with the feature boundary.

## Verification

- Run focused lexer, parser, and semantic specs, followed by `crystal spec`.
- Run Crystal formatting checks and `git diff --check`.
- Assert source acceptance, rejection, and diagnostics; do not add tests for IR/backend behavior in this feature.
