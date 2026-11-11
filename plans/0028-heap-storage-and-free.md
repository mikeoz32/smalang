# Heap Storage and Release

## Goal

Implement `heap_storage` and `heap_free` from ADR 0004 for Linux x86_64. Keep this feature limited to the heap memory API; do not implement `copy_memory` or array lowering.

## Agreed Behavior

- `heap_storage(bytes: uint, alignment: uint) -> ptr[uint8]` allocates uninitialized raw bytes. `bytes` may be runtime-dependent; `alignment` must be a compile-time constant, nonzero power of two.
- A compile-time zero size, invalid compile-time alignment, or compile-time-known padded-size overflow is a compilation error. A runtime zero size or overflow while calculating padded allocation size raises a catchable `InvalidArgument` exception. Mapping failure raises `OutOfMemory`.
- The returned address satisfies the requested alignment, including alignments larger than the system page size. The API does not initialize the returned region.
- `heap_free(address: ptr[uint8], bytes: uint, alignment: uint) -> unit` releases the complete allocation created by `heap_storage`. `alignment` is compile-time and must match the allocation. The supplied address, byte count, and alignment must match the allocation; mismatch, double-free, or freeing a foreign address remains undefined behavior in `unsafe` and needs no runtime validation.
- `heap_storage` is an expression returning `ptr[uint8]`. `heap_free` is a standalone operation because source-level `unit` values and general expression statements are not supported.
- Both names are reserved and require `unsafe:`. Use existing ordinary call AST forms; do not add lexer tokens or builtin-specific parser nodes. Semantic analysis and lowering recognize the native calls.
- Use Linux `mmap`/`munmap` syscalls emitted by the Smalang backend; no C runtime, external allocator, or external unwinder dependency is introduced. Preserve mapping metadata privately so `heap_free` can unmap aligned allocations reliably.
- `alloc(value)` and `free(address)` retain their existing typed, initialized, single-scalar contract.

## Acceptance Criteria

- Semantic analysis validates unsafe context, arity, argument types, compile-time alignment, zero compile-time size, and invalid alignment; runtime-dependent sizes are accepted.
- IR represents heap allocation as an exceptional operation with `ALLOCATE` memory effects and `OutOfMemory`/`InvalidArgument` paths. Heap release has explicit `FREE` memory effects and a `unit` IR result.
- Backend allocation returns correctly aligned, uninitialized storage for several sizes and alignments, including an alignment larger than a page; release unmaps the entire backing mapping.
- Runtime zero size and padded-size overflow are catchable as `InvalidArgument`; mmap failure is catchable as `OutOfMemory`.
- End-to-end `.py` programs compile to an object, link with `ld`, and exercise allocation, typed casts, load/store, release, and reallocation without libc or unresolved runtime symbols.
- Existing `alloc`/`free`, `stack_storage`, pointer operations, and exception behavior continue to pass their tests.
- README and ADR 0004 record the implemented scope and remaining work.

## Implementation Steps

1. Add failing semantic and end-to-end tests for valid heap storage/release, runtime sizes, alignment, invalid arguments, and allocation failure.
2. Add `InvalidArgument` to IR exception kinds and backend runtime construction, dispatch, and reporting.
3. Add semantic handling for `heap_storage` and standalone `heap_free` calls using existing AST representations.
4. Add typed IR allocation and release operations with explicit exception flow and memory effects; update verifier and S-expression dumps.
5. Lower the operations and emit aligned `mmap`/`munmap` logic with hidden mapping metadata and overflow checks.
6. Add examples and update README/ADR 0004 status.

## Verification

- `crystal tool format --check`
- `crystal spec`
- Compile/link/run the checked-in heap-storage example through the existing `ld` test helper.
- Verify an object has no unresolved allocator, libc, or unwinder symbols.
- `git diff --check`

## Out of Scope

- `copy_memory`, array AST-to-AST lowering, array layout queries, or array/index `address_of`.
- Runtime validation of `heap_free` ownership or matching arguments; violations remain undefined behavior.
- `heap_alloc` as an alternate name; retain the ADR API name `heap_storage`.
