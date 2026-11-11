# Stack Storage

## Goal

Implement the `stack_storage(bytes, alignment) -> ptr[uint8]` unsafe builtin from ADR 0004 as a fixed, uninitialized byte region reserved in the current x86-64 stack frame.

## Agreed Behavior

- `stack_storage` is a native builtin represented by an ordinary call expression. No lexer token or builtin-specific AST node is added.
- The call is allowed only inside `unsafe:`; its name is reserved for the builtin and it takes exactly two `uint` arguments.
- `bytes` and `alignment` must be compile-time constant expressions. Reuse the current constant-expression subset: integer literals and `+`/`-` expressions; identifiers, including immutable local bindings, and function calls are not compile-time constants.
- Evaluate the arguments with checked arithmetic. Reject zero `bytes`, zero `alignment`, non-power-of-two alignment, and compile-time overflow during semantic analysis.
- Reserve enough uninitialized frame space for `bytes` plus at most `alignment - 1` bytes of padding. Align the returned address upward at runtime so alignments larger than the ABI's 16-byte stack guarantee work. Return a non-null `ptr[uint8]` to exactly the requested storage region. The storage lives for the function frame, is not zero-filled, and is not released with `free` or `heap_free`.
- The IR allocation has explicit memory effects and records its compile-time size and alignment. The verifier rejects invalid size/alignment metadata.
- The x86-64 backend assigns a fixed frame region and emits its address. Reject storage or total frame layouts that exceed representable x86-64 frame offsets.
- Preserve the existing `alloc_stack(value)` behavior and source-level array rules.

## Acceptance Criteria

- Semantic analysis accepts valid calls in `unsafe:` and rejects calls outside it, a user function named `stack_storage`, incorrect arity or argument types, non-constant arguments, zero size/alignment, non-power-of-two alignment, and compile-time overflow.
- Typed IR verifies and dumps the storage allocation with its byte size and alignment.
- End-to-end `.py` programs cast the returned `ptr[uint8]` to scalar pointer types, initialize the storage before reading, and demonstrate independent stack regions.
- Backend layout tests show that returned frame addresses satisfy requested alignments, including alignments larger than the natural alignment of the surrounding values.
- Existing stack allocation, pointer cast, pointer offset, and fixed-array behavior remains unchanged.

## Implementation Steps

1. Add failing semantic and end-to-end cases for valid storage, invalid arguments, region independence, and alignment layout.
2. Parse `stack_storage(...)` as a normal `CallExpr` and add reserved-name and unsafe-only semantic handling.
3. Add checked compile-time evaluation and validation for size/alignment.
4. Add the typed IR storage instruction, verifier rules, memory effect, and S-expression dump.
5. Extend x86-64 frame planning and emission to reserve aligned uninitialized byte regions and return their addresses.
6. Add a source example and update README/ADR implementation status.

## Verification

- `crystal tool format --check`
- `crystal spec`
- Compile, link with `ld`, and run the checked-in `.py` example through the end-to-end test helper.
- Confirm existing stack allocation, cast, pointer offset, and fixed-array examples still behave the same.
- `git diff --check`

## Out of Scope

- Runtime-sized stack allocation, heap storage/free, `copy_memory`, `address_of`, and AST-to-AST array lowering.
- Zero-initialization, typed storage, implicit pointer casts, null pointers, or runtime alignment checks.
- Changes to `alloc_stack(value)` or source array semantics.
