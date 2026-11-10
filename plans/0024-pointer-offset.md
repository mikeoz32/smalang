# Typed Raw Pointer Offsets

## Goal

Add `offset(address, index)` as a source-visible unsafe operation for calculating an element address from a typed raw pointer.

## Proposed Contract

- `offset(address, index)` accepts `ptr[T]` and `uint`, and returns `ptr[T]`.
- `index` counts elements, not bytes. The backend scales it by the target storage size of `T` before adding it to the pointer address.
- The operation computes an address only; it does not read or write memory.
- It performs no bounds, alignment, lifetime, or address-overflow check. The caller inside `unsafe:` is responsible for ensuring that the computed address is valid before using it. Negative offsets are unsupported.
- Both arguments are evaluated once in source order. The operation is allowed only inside `unsafe:` and its name is reserved for the builtin.
- The first implementation supports the scalar pointee types already supported by `ptr[T]`.
- Source spelling is `offset(address, index)`.

## Acceptance Criteria

- The parser recognizes `offset` as a dedicated memory operation.
- Semantic analysis accepts supported `ptr[T]` plus `uint` inputs inside `unsafe:` and preserves the pointer type in the result. It rejects use outside `unsafe:`, wrong arity, a non-pointer address, an index of another type, and a user function named `offset`.
- Typed IR represents the operation in S-expression notation and its verifier rejects invalid pointer or index types.
- The x86-64 backend computes `address + index * size_of(T)` using the pointee's target width, including 1-, 2-, 4-, and 8-byte scalar pointees.
- End-to-end `.py` checks link with `ld` and run: zero offset is dereferenced to verify the original value, and a one-past offset from a one-element stack slot is computed and passed onward without dereferencing it.
- Existing heap/stack allocation and fixed-array behavior remains unchanged.

## Implementation Steps

1. Add failing parser, semantic, IR-verifier, and end-to-end cases for `offset(address, index)`.
2. Add the AST node and semantic checks, including unsafe context, arity, supported pointer types, and `uint` index validation.
3. Add a typed pointer-offset IR instruction, verifier rules, and S-expression dump.
4. Add x86-64 address scaling and addition for the supported scalar widths.
5. Add a checked-in `.py` example and focused tests for zero and one-past offsets.

## Verification

- `crystal tool format --check`
- `crystal spec`
- Compile, link with `ld`, and run the checked-in offset example.
- Confirm stack-allocation and fixed-array examples still behave the same.
- `git diff --check`

## Out of Scope

- Negative or signed offsets, casts, dereferencing checks, bounds checking, multi-element allocation, memory copying, and array desugaring.
- Pointer comparisons or pointer-to-integer conversions.

This is the next operation in the memory primitive sequence recorded in [ADR 0004](../adr/0004-array-desugaring-and-memory-primitives.md).

## Result

- Implemented source parsing, unsafe semantic checks, typed IR verification and S-expression dumping, AST-to-IR lowering, and x86-64 address scaling for `offset(address, index)`.
- Added a native `.py` example for reading through a zero offset and passing a one-past address without dereferencing it. Backend checks exercise 1-, 2-, 4-, and 8-byte pointee strides.
- `crystal tool format --check`, `crystal spec` (256 examples), `git diff --check`, and Markdown-link checks pass.
