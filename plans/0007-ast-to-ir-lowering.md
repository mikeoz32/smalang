# AST to Typed IR Lowering Plan

## Goal

Lower a successfully analyzed smalang module into the existing architecture-independent typed SSA IR. Keep semantic analysis, IR construction, and the native backend as distinct passes.

## Agreed behavior

- The lowerer accepts a successful `SemanticModule` and uses its original syntax AST, symbol bindings, and expression types.
- Map source `int` to IR `isize` and source `uint` to IR `usize`.
- Declare all IR functions before lowering any body. Preserve source order for `FunctionId`s and map semantic function `SymbolId`s to those IDs. This supports forward and recursive calls.
- Map each parameter `SymbolId` to the corresponding IR parameter `ValueId`.
- Lower integer literals to typed `const`, identifier uses to their parameter values, `+` and `-` to typed SSA instructions, direct calls to internal function targets, and each return expression to a `return` terminator.
- Each lowered function has the existing single entry block and straight-line instruction sequence.
- Verify the completed `IrModule` before returning success. The generated IR does not retain AST nodes.

## Scope

- Add an AST-to-IR lowering pass that consumes semantic facts rather than resolving names or rechecking source types.
- Cover only the currently supported AST and IR operations: constants, identifiers, addition, subtraction, direct calls, and returns.
- Keep source parsing, semantic diagnostics, new IR instructions, control-flow blocks, optimizations, backend changes, and a compiler CLI outside this feature.

## Acceptance criteria

- `examples/first_program.py` lowers to a verified typed IR module with the expected function signatures, parameter references, constants, arithmetic, call target, and return values.
- Typed `uint` parameter expressions lower to `usize` instructions.
- Function and parameter references use the `FunctionId` and `ValueId` identities recorded during lowering; forward and mutually recursive calls target the correct module functions.
- A source program lowered through the existing backend links and runs with the expected process status (`42` for the checked-in example).
- Lowering adds no AST nodes and the resulting IR contains no AST or semantic-model references.
- No new IR operations or machine-code behavior are introduced.

## Implementation steps

1. Define the lowering result and source-located failure representation; create an `IrModule` from a `SemanticModule`.
2. Add every IR function and build `SymbolId` to `FunctionId` mappings before lowering bodies.
3. For each function, map parameter symbols to IR parameter values and lower its return expression recursively into SSA instructions.
4. Resolve calls through semantic symbol IDs, emit typed internal calls, and verify the completed module.
5. Add focused behavior specs, including an end-to-end run of the checked-in `.py` program through the existing backend.

## Verification

- Follow the repository's test-first behavior workflow and run `crystal spec`.
- Check that generated IR passes `IrModule#verify`; do not make the diagnostic S-expression dump a stable test contract.
- Link and execute the lowered example through the existing backend to confirm its process status.
- Run Crystal formatting and `git diff --check`.
