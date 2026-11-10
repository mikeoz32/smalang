# Initialized Stack Allocation

## Goal

Add `alloc_stack(value)` as the stack-backed counterpart to the existing heap `alloc(value)` operation. It provides a typed raw pointer to initialized stack storage and is available only inside an `unsafe:` block.

## Agreed Behavior

- `alloc_stack(value)` requires one initial value, evaluates it once, copies it into a stack-frame slot, and returns `ptr[T]`, where `T` is the value's type.
- The first implementation supports the same scalar types as the existing `alloc(value)` operation.
- One frame slot is reserved for each source call site. Re-executing that call site in a function activation reuses the slot and initializes it from the newly evaluated value; the operation does not grow or adjust the runtime stack pointer.
- The pointer is valid only during the current function activation. It is not heap-owned and must not be passed to `free`. Raw-pointer escape and lifetime validity remain the unsafe caller's responsibility.
- The operation requires `unsafe:`. Existing `load` and `store` access the pointed-to scalar using their current typed memory rules.
- This is a general value-allocation primitive. It has no array-specific count, decay, or indexing behavior. Pointer offset is a separate later operation.

## Acceptance Criteria

- The parser and semantic analyzer accept `alloc_stack(value)` only inside `unsafe:` and reject incorrect arity and unsupported value types before IR generation.
- The result is typed as `ptr[T]`, and the initial value is evaluated exactly once.
- Typed IR represents the operation, prints it using S-expression notation, and verifies its operand and result types.
- The x86-64 backend reserves a correctly sized and aligned frame slot and initializes it from the input value at the operation's execution point.
- An end-to-end `.py` program obtains a stack pointer, stores a different value through it, loads that value, links with `ld`, and exits with the expected result.
- Existing `alloc`, `load`, `store`, `free`, and fixed-array behavior remains unchanged.

## Implementation Steps

1. Add failing parser, semantic, and end-to-end behavior cases for `alloc_stack(value)`.
2. Add the AST node and semantic checks, including unsafe-context and value-type validation.
3. Add a typed IR operation, verifier rules, and S-expression dump.
4. Add x86-64 frame-slot layout and initialization at the operation's execution point.
5. Add a focused `.py` example that uses `alloc_stack`, `store`, and `load` inside `unsafe:`.

## Verification

- `crystal tool format --check`
- `crystal spec`
- Compile, link with `ld`, and run the checked-in stack-allocation example.
- Confirm the existing pointer and fixed-array end-to-end examples still behave the same.
- `git diff --check`

## Out of Scope

- Pointer offset, array or aggregate pointee types, raw memory copying, dynamic heap buffers, globals, and slices.
- Addressing existing SSA local bindings or changing their aliasing behavior.
- AST-to-AST array rewriting or removal of array-specific IR/backend operations.

This is the first low-level primitive in the direction recorded in [ADR 0004](../adr/0004-array-desugaring-and-memory-primitives.md). Later steps can add pointer offset, memory copying, and array desugaring independently.

## Result

- Implemented `alloc_stack(value)` in the parser, semantic analyzer, typed IR, and x86-64 backend.
- Added checked-in examples for independent `int` slots and round trips through every supported scalar type; behavior checks cover typed widths, unsafe and arity errors, unsupported values, IR verification, and single evaluation of the initializer.
- `crystal tool format --check`, `crystal spec` (249 examples), `git diff --check`, and Markdown-link checks pass. Independent review found no actionable issues.
