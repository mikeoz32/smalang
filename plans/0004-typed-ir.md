# Typed SSA IR Feature Plan

## Goal

Introduce smalang's architecture-independent typed SSA IR as typed compiler structures, with a human-readable S-expression dump. Keep the IR independent of the AST representation and ready for a backend to lower its explicit operations to machine code.

## Agreed behavior

- The IR is smalang-owned and does not depend on WebAssembly or a target architecture.
- The compiler stores IR in typed structures. The WAT-inspired S-expression is only a diagnostic dump; it is not an input language or a stable serialization format.
- `isize` and `usize` are the IR types corresponding to source `int` and `uint`. The target determines their width; Linux x86_64 uses 64 bits.
- SSA values are defined once. Function parameters define initial values, and each value-producing instruction defines one typed result. Operands reference SSA values explicitly.
- Each function in this first slice has one entry block, a straight-line instruction sequence, and a `return` terminator. There are no `jump`, `branch`, or `phi` instructions yet; add them with the language's control-flow constructs.
- The first operation set is integer `const`, `add`, `sub`, direct typed `call`, and `return`.
- A call has a typed callable target and explicit SSA arguments. In the first slice, the target is a module function identity; the representation stays extensible to future typed external symbols. Function references are module-level identities, separate from SSA value definitions.
- Preserve extensibility for future typed external calls. Do not implement FFI or put ABI rules in this IR feature; ABI decisions remain in the backend.
- Integer overflow behavior remains as documented in `README.md`: the initial slice gives no guarantee for overflowing arithmetic.

## Scope

- Define the in-memory IR model for modules, functions, parameters, the entry block, typed SSA values, and the agreed instruction set.
- Use index-addressed typed storage, following the AST arena's ID-based ownership pattern without reusing its arena or node types: the module owns functions by `FunctionId`, and each function owns its local values, instructions, and blocks by IDs. References use IDs rather than raw pointers; ordinary growable arrays are sufficient, with no custom bump allocator.
- Add structural verification for unique value definitions, valid SSA uses, operand/result type consistency, call signatures, and function termination.
- Add a deterministic S-expression dump for inspecting the initial IR forms.
- Keep AST-to-IR lowering and machine-code generation outside this feature. Both will consume the agreed IR contract in later work.

## Implementation steps

1. Add intention-revealing module-level `FunctionId` and function-local `ValueId`, `InstructionId`, and `BlockId` identifiers, plus typed array-backed storage. Follow repository design guidance with polymorphic instruction behavior and a typed callable-target abstraction, rather than centralized variant dispatch.
2. Implement an IR verifier for the first straight-line subset, including function signatures and direct calls.
3. Implement the diagnostic S-expression dump from the typed structures.
4. Add a representative IR fixture for `increment` and `main` and verify the structure, invalid-IR diagnostics, and readable dump.

## Acceptance criteria

- A typed IR module can represent the `increment` and `main` example in `README.md` without retaining AST nodes or source-expression trees.
- Every parameter and computed result has an explicit IR type and SSA identity; arithmetic, calls, and returns have explicit operands.
- Function-local arena IDs remain stable references as growable arrays expand, and no IR edge relies on a raw pointer.
- The verifier rejects malformed first-slice IR, including duplicate definitions, invalid value uses, type mismatches, invalid call signatures, and blocks without `return`.
- The S-expression dump clearly shows the module, function signatures, entry blocks, SSA definitions, operations, calls, and returns.
- No AST lowering, branch/phi support, FFI behavior, target ABI logic, or machine-code generation is introduced.

## Verification

- Add focused behavior tests for a valid representative module and verifier rejection of malformed IR, following the repository's test-first instructions.
- Run the documented project checks and `crystal spec` after implementation; do not assert an exact stable serialization contract for the diagnostic dump.
