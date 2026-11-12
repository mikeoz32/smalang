# Copy Memory

## Goal

Implement the `copy_memory` unsafe operation from ADR 0004 for Linux x86_64, preserving its byte-oriented `memmove` contract without a C runtime or external library.

## Agreed Behavior

- The source API is `copy_memory(dst: ptr[uint8], src: ptr[uint8], bytes: uint) -> unit`.
- The operation is available only inside `unsafe:` and is written as a standalone call statement, following the current source-level `unit` rules. Its name is reserved for the native operation.
- It copies exactly `bytes` bytes and supports overlapping regions in either direction as well as self-copy.
- A zero byte count performs no memory reads or writes.
- Both pointers have the exact `ptr[uint8]` type and the byte count has type `uint`; no typed-element scaling or hidden size multiplication is performed.
- IR represents the operation as an ordinary non-throwing instruction with a `unit` result and explicit read-plus-write memory effects. Its S-expression dump follows the existing notation. Optimizations must preserve memory-operation order unless safe non-aliasing is proven.
- The backend emits the copy logic itself. It must not introduce `memmove`, libc, a C compiler, or another runtime dependency.

## Acceptance Criteria

- Semantic analysis accepts valid calls and rejects calls outside `unsafe:`, use as a value, wrong arity, wrong pointer or byte-count types, and conflicting declarations of the reserved name.
- Typed IR construction and verification enforce the operand types, `unit` result, and combined read/write effects; the dump includes the operation.
- End-to-end `.py` programs exercise disjoint copying, overlap where the destination is above the source, overlap where the destination is below the source, self-copy, and zero bytes.
- Generated objects link with `ld` and run without libc or unresolved external copy/runtime symbols.
- Existing pointer, allocation, array, exception, and backend behavior remains passing.
- README and ADR 0004 report `copy_memory` as implemented while leaving array AST-to-AST desugaring explicitly pending.

## Implementation Steps

1. Add focused failing semantic and end-to-end behavior tests for the accepted and rejected source forms, overlap directions, self-copy, and zero-byte behavior.
2. Add `copy_memory` to the reserved unsafe operation names and semantic handling for its exact signature and standalone-call restriction.
3. Add an IR instruction and builder method, a combined read/write memory effect, verifier checks, and an S-expression representation.
4. Lower the source call arguments once in source order and emit the IR operation.
5. Generate overlap-safe x86_64 copy code that exits before any memory access for a zero length and handles both overlap directions without clobbering live allocated values.
6. Add a focused example and update README and ADR 0004 implementation status.

## Verification

- Confirm each behavior test fails for the intended reason before implementing it.
- `crystal tool format --check`
- `crystal spec`
- Run end-to-end tests that compile source to an object, link with `ld`, and check process results.
- Verify no unresolved `memmove`, libc, or external runtime symbols are introduced.
- `git diff --check`

## Out of Scope

- AST-to-AST desugaring of arrays, removing existing array-specific IR/backend operations, or expanding array layout queries.
- Typed or aggregate copy APIs, array bounds checks, allocation, and ownership changes.
- SIMD specialization or a general-purpose optimizer / Memory SSA implementation.
