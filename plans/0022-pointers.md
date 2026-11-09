# Raw Pointers and Unsafe Memory Operations

## Goal

Add typed raw pointers and a minimal unsafe memory API that compiles to working Linux x86_64 binaries.

## Agreed Behavior

- `ptr[T]` is a non-owning raw address type. Initially, `T` may be any existing scalar type: `bool`, `int`, `uint`, or a fixed-width integer.
- Pointer types are valid in local, parameter, and function result annotations. They are distinct from integers and have no implicit integer conversion.
- A raw pointer value is copyable. Copying it copies only the address, not ownership of the pointed-to allocation. After `free`, every copy is stale; using one remains the unsafe caller's responsibility. No runtime pointer-validity checks are added.
- `unsafe:` marks a block in which `alloc`, `load`, `store`, and `free` may be used. These operations are rejected outside that context. The block shares the function's existing flat scope; it does not introduce shadowing. Unsafe functions and nested unsafe blocks are out of scope.
- `alloc(value)` allocates and initializes one scalar value and returns `ptr[T]`. A literal argument uses the expected `ptr[T]` type as context; this does not add general type inference.
- `load(address)` reads and returns the pointed-to `T`. `store(address, value)` writes a value of the matching `T`. `free(address)` releases the single-value allocation. `store` and `free` are standalone statements permitted only inside `unsafe:`; arbitrary expression statements remain unsupported.
- A failed allocation raises the existing runtime exception mechanism with the `OutOfMemory` kind; success never returns an empty pointer.
- For Linux x86_64, pointers occupy 64 bits. Integers use their declared widths in memory; `bool` occupies one byte and is stored canonically as `0` or `1`.
- This slice uses the existing direct Linux `mmap`/`munmap` syscall approach for one-value allocations. A raw pointer carries no bounds or lifetime proof. The unsafe caller is responsible for valid addresses, initialization, alignment, use after free, and correct release.
- Pointer arithmetic (`offset`), casts, dynamic buffers, fixed-size array and other non-scalar pointees, custom allocators, safe owners over raw memory, FFI, and ownership tracking are deferred.

## Acceptance Criteria

- `ptr[T]` parses and type-checks in declarations, parameters, and result types for the supported scalar `T` types.
- The compiler rejects unsupported pointee types, integer/pointer mismatches, mismatched `load`/`store` types, wrong operation arity, and every unsafe operation outside an `unsafe:` block before IR generation.
- A `.py` program can allocate a scalar, store a new value, load it, free the allocation, and return the observed value from its native binary.
- Compiled behavior covers boolean and fixed-width scalar memory representation, plus pointer passing through a function parameter/result.
- Allocation failure follows the `OutOfMemory` runtime path and produces the normal uncaught-runtime diagnostic.
- `store` and `free` work as statements inside `unsafe:` without enabling general expression statements.
- README and ADR 0003 describe the implemented pointer-copy, scalar layout, allocation-failure, and unsafe-operation contracts; examples demonstrate the supported API.

## Implementation Steps

1. Add failing lexer/parser behavior tests for `ptr[T]`, `unsafe:` blocks, and the restricted `store`/`free` statement forms, including recovery and source spans.
2. Extend the existing `AstTypeSyntax`/`AstTypeArena` and semantic type-table pattern with a pointer type constructor; add AST nodes for unsafe blocks and memory operations, keeping one AST model.
3. Add semantic checks for pointer signatures and bindings, unsafe context, builtin arity, pointee/value compatibility, and literal context propagation.
4. Add a distinct pointer type and typed allocation/load/store/free operations to IR, including verifier checks and an `OutOfMemory` exceptional path.
5. Implement Linux x86_64 pointer register/stack handling, scalar-width memory accesses, and single-value allocation/release through `mmap`/`munmap`.
6. Add native positive/negative behavior tests, a deterministic allocation-failure check, a checked-in example, and update README/ADR 0003.

## Verification

- `crystal tool format --check`
- `crystal spec`
- Compile and run the checked-in pointer example through the native backend.
- Verify compile-time diagnostics for invalid pointer and unsafe usage.
- `git diff --check`
