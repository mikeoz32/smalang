# Const and Mutable Bindings

## Goal

Add explicitly typed local bindings and assignments, with immutable bindings as the default and opt-in mutability through `mut[T]`.

## Agreed Behavior

- `name: T = value` declares an immutable local binding.
- `name: const[T] = value` is an explicit immutable spelling; `name: mut[T] = value` declares a mutable binding.
- `mut[T]` and `const[T]` are binding qualifiers for parameters and locals. Function result types remain plain `T`.
- Parameters are immutable by default. A `mut[T]` parameter may be reassigned locally; calls continue passing values by value.
- Every binding has an initializer and explicit type. No type inference or uninitialized declarations.
- Assignment uses `name = value`; only mutable bindings may be reassigned, repeatedly.
- Parameters and locals share one function scope. Duplicate names and shadowing are rejected.
- A binding is visible after its declaration. Function bodies contain declarations and assignments followed by exactly one final `return`; no expression statements.

## Acceptance Criteria

- The lexer and parser recognize assignment and binding qualifier syntax, preserving source spans and parser recovery.
- Semantic analysis rejects duplicate names, invalid qualifiers, assignment to immutable bindings, unknown names, and mismatched initializer/assignment types at compile time.
- Mutable parameter reassignment changes only the function's local value.
- Lowering represents reassignment by updating the current SSA value for the binding; it does not add runtime memory operations.
- Compiled `.py` examples demonstrate default immutability, explicit `const[T]`, local `mut[T]`, and mutable parameters.
- Negative behavior tests verify compile-time diagnostics for invalid use.

## Implementation Steps

1. Add failing lexer and parser behavior tests for the binding, qualifier, assignment, and statement syntax.
2. Add AST nodes and parse sequential function statements while preserving recovery and the required final return.
3. Add semantic symbols for local bindings and parameter mutability; validate scope, types, initialization, and assignments.
4. Lower bindings to SSA values and reassignment to the updated value associated with a mutable symbol.
5. Add positive and negative end-to-end compiler tests, examples, and README documentation.

## Verification

- `crystal tool format --check`
- `crystal spec`
- Compile and run the checked-in binding examples through the native backend specs.
- `git diff --check`
