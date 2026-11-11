# Type Layout Queries and Local Addresses

## Goal

Implement `size_of`, `align_of`, and `address_of` from ADR 0004 as unsafe native builtins, before array desugaring.

## Agreed Behavior

- All three names are reserved and callable only inside `unsafe:`. They remain ordinary call expressions; no lexer token or builtin-specific AST node is added.
- `size_of(type_name)` and `align_of(type_name)` take a type spelling as their single argument and return a compile-time `uint` value.
- The first slice supports the existing scalar types and `ptr[T]` where `T` is a supported scalar type. `array[T, N]` queries are deferred. `ptr[T]` is written in the call argument using existing type spelling; its size and alignment do not depend on `T`.
- The parser must accept existing type spellings as arguments specifically to `size_of` and `align_of`. These are parsed into the existing ordinary call-expression representation; no new token, AST node, or type-as-runtime-value feature is introduced.
- Layout uses the Linux x86_64 target: scalar sizes and alignments follow their declared widths (with `bool` occupying one byte), and a pointer has size and alignment of 8 bytes. These query results are compile-time constants and can be used in `stack_storage`, for example `stack_storage(size_of(uint64), align_of(uint64))`.
- `address_of(place)` accepts a scalar local binding or parameter and returns `ptr[T]` to that binding's actual stack storage. It does not take the address of a temporary, array, indexed element, or pointer-typed binding in this slice. The name is unsafe because writes through the raw pointer can bypass source-level immutability; the caller owns that risk.
- Address-taking does not extend lifetime. The returned pointer is valid only while the binding's function frame is alive. Reads and assignments through the binding remain coherent with reads and writes through the pointer, including when the pointer is passed to another function.
- Address-taken scalar bindings use stable stack slots. Other bindings keep their current SSA lowering.
- Existing `ptr[T]` restrictions, stack-storage contracts, array source semantics, and the signatures of other memory operations remain unchanged.

## Acceptance Criteria

- Semantic analysis accepts scalar and pointer layout queries in `unsafe:` and rejects unknown/unsupported type operands, wrong arity, and use outside `unsafe:`; all three builtin names are reserved.
- Query values have type `uint`, are represented as compile-time constants, and compose with checked `+`/`-` expressions and `stack_storage` arguments.
- Query results match x86_64 layouts for all supported scalar types and pointers, including `bool` and pointers to different scalar types.
- `address_of` rejects non-place expressions and unsupported place types. Writes through the returned pointer are observed by later reads of the binding; ordinary assignments are observed through the pointer; mutation through a pointer in a called function is visible to the caller.
- A `.py` example compiles to an object, links with `ld`, and runs with the expected result.
- Existing stack allocation, stack storage, pointer casts/offsets, and fixed-array behavior remain unchanged.

## Implementation Steps

1. Add failing semantic and end-to-end tests for the three builtins, including type-query composition inside `stack_storage` and pointer-visible local mutation.
2. Extend call-argument parsing so scalar type names and `ptr[T]` spellings can appear in the ordinary arguments of `size_of` and `align_of`; keep the existing call-expression AST representation.
3. Add semantic type-layout queries for supported scalar and pointer types and reject unsupported type operands.
4. Record query results as compile-time `uint` facts, teach checked constant evaluation to consume those facts, and lower queries to typed IR constants.
5. Track scalar bindings whose addresses are taken. Lower those bindings to stable stack storage and use explicit loads/stores for reads and assignments so aliases remain coherent across calls.
6. Lower `address_of` to the stable binding pointer, verify memory effects and backend frame layout, and add the source example.
7. Update README and ADR 0004 implementation status.

## Verification

- `crystal tool format --check`
- `crystal spec`
- Compile the checked-in `.py` example, link its object with `ld`, and run it.
- Confirm existing pointer, stack-storage, and fixed-array examples still behave the same.
- `git diff --check`

## Out of Scope

- `size_of`/`align_of` for arrays, structs, or classes.
- `address_of` for arrays, indexed elements, pointer-typed bindings, fields, or globals.
- `heap_storage`, `heap_free`, `copy_memory`, and AST-to-AST array desugaring.
- New pointer types, pointer-to-pointer support, nullable pointers, implicit casts, or lifetime extension.
