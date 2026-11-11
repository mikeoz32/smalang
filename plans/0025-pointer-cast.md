# Typed Pointer Cast

## Goal

Add `cast[U](address)` as an explicit unsafe conversion between scalar raw-pointer types. It provides typed access to existing storage without changing the address.

## Agreed Behavior

- Source spelling is `cast[U](address: ptr[T])`, with result `ptr[U]`.
- `T` and `U` are scalar types in the first implementation. Pointers to arrays, structs, or classes are not added to IR.
- The operation is available only inside `unsafe:` and the name `cast` is reserved for this builtin.
- It evaluates its address operand once and preserves the exact address while changing only the static pointer type.
- It performs no memory access and checks neither address validity, alignment, nor lifetime. It does not create a null pointer.
- Casting does not add implicit conversions or pointer-to-integer conversions.
- The parser represents `cast[U](address)` as an ordinary call expression with an explicit type argument. Semantic analysis resolves the reserved native function `cast`; no cast-specific AST node or lexer token is added.
- Typed IR represents the cast, verifies its pointer types, and includes it in the existing S-expression dump format. The backend preserves the same machine address bits; it may reuse the source value without emitting a machine instruction.
- The cast itself has no memory effect.

## Acceptance Criteria

- A `.py` program casts an `alloc_stack` pointer from `ptr[int]` to `ptr[uint]`, writes through the converted pointer, then reads the same storage through the original pointer and exits with the expected value.
- End-to-end tests compile and execute all 121 ordered source/target pairs across the 11 supported scalar types and verify that stores through converted pointers reach the original storage.
- Semantic checks reject use outside `unsafe:`, a non-pointer operand, unsupported pointee types, wrong arity, and a user declaration named `cast` before IR generation.
- A misaligned address can be cast when it is not dereferenced; the cast itself performs no alignment check or memory access.
- Typed IR verifies the source and result pointer types and prints the cast in S-expression notation.
- The x86-64 backend preserves the address through the cast; the end-to-end program links with `ld` and runs without a C compiler or external runtime.
- Existing pointer operations, stack allocation, offsets, and fixed-array behavior remain unchanged.

## Implementation Steps

1. Add a failing end-to-end behavior case and focused parser and semantic error cases; confirm each fails for its intended reason.
2. Parse the generic type argument into the ordinary call-expression AST.
3. Resolve the reserved native function and enforce unsafe-context, arity, operand-pointer, and scalar-target rules.
4. Add the typed IR cast instruction, verifier rules, S-expression dump, and AST-to-IR lowering.
5. Lower the cast to the same machine address value in the x86-64 backend.
6. Add a checked-in `.py` example and run the documented verification.

## Verification

- `crystal tool format --check`
- `crystal spec`
- Compile the checked-in `.py` example, link its object with `ld`, and run it.
- Confirm existing pointer-offset and stack-allocation examples still behave the same.
- `git diff --check`

## Out of Scope

- `stack_storage`, heap storage/free, `copy_memory`, and array desugaring.
- Aggregate pointee types, null pointers, pointer comparisons, pointer-to-integer conversion, and runtime validity/alignment/lifetime checks.
- Changing source array semantics or existing pointer-operation signatures.
