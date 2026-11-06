# Fixed-Width Integer Types Plan

## Goal

Add explicit signed and unsigned fixed-width integer types to the source frontend and type checker.

## Agreed behavior

- Add `int8`/`uint8`, `int16`/`uint16`, `int32`/`uint32`, and `int64`/`uint64`.
- Keep `int` and `uint` pointer-sized (`isize`/`usize`); on Linux x86_64 they remain 64 bits. Fixed-width types are distinct from `int`/`uint`, including `int64`/`uint64` on this target.
- Do not add `byte`; it may later be an alias for `uint8`.
- Keep function parameters and results explicitly typed. A decimal integer literal has no fixed runtime type until an explicit expected integer type supplies one, such as a function result type, call parameter, or the other typed arithmetic operand. An enclosing expected type also applies through an arithmetic expression containing only literals.
- Reject a literal at compile time if its value is outside the range of its resolved integer type. Do not default unresolved literals to a type.
- Preserve exact matching for already-typed integer values: no implicit widening, signedness conversion, or conversion between fixed-width and pointer-sized types. `+` and `-` require matching integer operand types; a literal may take the matching type from its context.
- Keep the current source grammar and operators otherwise unchanged. Do not add unary minus, casts, literal suffixes, or new overflow behavior.
- Implement only lexer, parser/AST, and semantic analysis. Do not add IR or backend support in this feature.

## Scope

- Recognize the eight fixed-width type names and parse them in function parameter and result annotations.
- Represent each integer type canonically in semantic analysis, preserving signedness and bit width for range checks and diagnostics.
- Resolve decimal literal types from explicit contexts and reject out-of-range values during semantic analysis.
- Update `README.md` to document the type family, literal typing, exact matching, and frontend-only boundary.
- Add focused source behavior specs for declarations, calls, arithmetic, literal typing, range failures, and incompatible types.

## Acceptance criteria

- All eight fixed-width types are accepted in parameter and result annotations; unknown type names are rejected.
- Each fixed-width type has the documented signedness and width; `int64`/`uint64` remain distinct from `int`/`uint`.
- A literal in a typed return, call argument, or arithmetic expression resolves to the expected integer type.
- In-range literals are accepted and out-of-range literals are rejected at compile time with source-located diagnostics.
- `uint` functions can return an in-range literal such as `1`.
- Typed values with different widths or signedness are rejected in calls, returns, and arithmetic; literals may adapt to a known matching type.
- No changes are made to IR, backend, arithmetic overflow rules, or runtime behavior.

## Implementation steps

1. Add lexer tokens for each fixed-width type name, preserving whole-identifier keyword matching.
2. Add source AST type variants and parser mappings for the new annotations.
3. Extend the semantic type table with canonical signedness and width metadata; use it to validate type compatibility and literal ranges.
4. Propagate expected integer types from function returns, call parameters, and typed arithmetic operands into literal expressions; reject literals without a resolvable context.
5. Add behavior specs for accepted and rejected source programs, then update the README.

## Verification

- Run focused lexer, parser, and semantic specs, followed by `crystal spec`.
- Run Crystal formatting checks and `git diff --check`.
- Assert source acceptance, rejection, and diagnostics. Do not add IR/backend tests or change their behavior.
