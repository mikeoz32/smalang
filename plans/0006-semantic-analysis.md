# Semantic Analysis Feature Plan

## Goal

Add semantic analysis as a distinct compiler pass between the syntax AST and typed IR. The pass resolves declarations and checks types, but does not modify the AST or generate IR.

## Agreed behavior

- Run semantic analysis only for a syntactically valid `ParsedModule`.
- Keep the parser AST immutable and syntax-only. `SemanticModule` retains that same `ParsedModule` and stores semantic facts in side tables keyed by `NodeId`.
- Assign each function and parameter declaration a `SymbolId`; map identifier and call uses to their resolved symbol IDs.
- Make all module functions visible regardless of declaration order. Collect function signatures before checking bodies, so direct and mutual recursive calls resolve as ordinary calls.
- Represent source types with canonical `TypeId`s. Initially the type table contains only `int` and `uint`.
- Use only a module function scope and a parameter scope per function. Defer nested scopes, local variables, and shadowing rules.
- Stop at the first semantic error. Return its source-located diagnostic without a usable `SemanticModule`; generate IR only after successful analysis.
- Validate duplicate declarations, name resolution, call arity and argument types, matching operand types for `+`/`-`, return types, and the documented `main() -> int` entry point.
- Keep AST-to-IR lowering and typed IR generation in a later, separate feature.

## Scope

- Define semantic IDs, the initial canonical type table, symbol/scope storage, `SemanticModule`, and a fail-fast result/diagnostic API.
- Resolve the identifiers and direct function calls present in valid ASTs, recording their symbol identities and expression types for later IR generation.
- Resolve forward and recursive calls through the module function scope; do not add call-graph analysis or tail-call optimization.
- Reject the first invalid semantic construct with its source location.
- Update `README.md` to show the semantic pass between parser + AST and typed IR.

## Deferred decisions

- The type of an integer literal in an unsigned context is not defined by the current documentation. This plan covers the existing signed-integer example and typed `uint` expressions, without choosing a new literal-typing rule.
- Tail-call optimization and any guarantee of constant stack use are deferred. Recursive calls use ordinary function-call behavior.

## Acceptance criteria

- `examples/first_program.py` passes semantic analysis and records types and symbol bindings for its declarations, parameter use, call, and expressions.
- Forward, direct recursive, and mutually recursive calls resolve to their module function symbols.
- The analyzer rejects duplicate function or parameter names, unknown names, invalid call arity or argument types, mixed-type arithmetic, return-type mismatches, and an invalid `main` signature.
- A semantic failure reports only the first diagnostic, with the correct source location, and does not yield a model for IR generation.
- The semantic model references the original `ParsedModule`; no semantic nodes are appended to or substituted into the AST.
- No IR lowering or IR generation is added.

## Implementation steps

1. Add `SymbolId`, `TypeId`, the initial type table, module/function symbol scopes, semantic side tables, and source-located diagnostics.
2. Implement name resolution and type checking over the syntax AST, recording each resolved use and expression type.
3. Enforce function signatures, call signatures, arithmetic operand compatibility, and the `main` entry-point contract; stop on the first error.
4. Add focused behavior specs for accepted programs and the listed semantic errors, following the repository's test-first rules.
5. Document the semantic pass and its boundary from typed IR in `README.md`.

## Verification

- Run focused semantic specs and the full `crystal spec` suite.
- Run Crystal formatting checks and `git diff --check`.
- Tests should assert accepted/rejected source behavior and diagnostics; inspect semantic IDs only where needed to verify the contract consumed by later IR generation.
