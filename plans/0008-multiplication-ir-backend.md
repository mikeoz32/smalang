# IR and Backend Multiplication Plan

## Goal

Add integer multiplication as an operation in the typed IR and Linux x86_64 backend. Do not add multiplication syntax to smalang source programs in this feature.

## Agreed behavior

- Represent multiplication as a typed SSA-producing `mul` instruction, following the existing `add` and `sub` instruction model.
- Require both operands and the result to have the same IR integer type (`isize` or `usize`); reject malformed IR through the existing verifier.
- Include multiplication in the diagnostic S-expression dump as `(%vN TYPE (mul %vL %vR))`. The dump remains diagnostic output, not a serialization format.
- Lower the operation in the x86_64 backend to a 64-bit integer multiply. Use the register or spill-slot source location selected by the existing allocator. The low 64-bit product is the machine result; add no overflow checks, consistent with the current unspecified overflow behavior.
- Keep the source grammar, AST, semantic analysis, and AST-to-IR lowering unchanged. In particular, source `*` remains unsupported.

## Scope

- Add the IR instruction, visitor dispatch, function emission API, verifier behavior, and S-expression rendering.
- Add x86_64 machine-operation selection and instruction encoding for multiplication with register and spill-slot operands.
- Update the README's typed IR operation list and diagnostic example while retaining the documented source grammar boundary.
- Add focused IR contract tests and a backend behavior test that emits an object, links it with `cc`, and checks the executable result.

## Acceptance criteria

- A valid IR function can construct and verify a `mul` instruction over matching `isize` or `usize` values.
- The IR dump shows the documented `mul` S-expression; the verifier reports mismatched operand/result types and undefined uses as it does for other binary operations.
- The x86_64 backend emits valid multiplication code when the right operand is in a register or spill slot.
- A generated object links with `cc` and its executable returns the expected result for a multiplication case.
- No source parser, AST, semantic-analysis, source-language syntax, or AST-to-IR changes are introduced.

## Implementation steps

1. Add a failing IR behavior spec for constructing, verifying, and dumping multiplication, including malformed operand types.
2. Implement the typed IR instruction, visitor integration, builder method, verifier integration, and `mul` dump rendering.
3. Add a failing backend behavior spec that builds a small multiplication module, emits its object, links it, and checks its result.
4. Select multiplication in the x86_64 backend and encode the 64-bit register and spill-memory forms using the existing allocation and frame layout.
5. Update README documentation for the typed IR operation and its diagnostic S-expression, without changing source grammar documentation.
6. Run focused IR/backend specs, the complete `crystal spec` suite, Crystal formatting, and `git diff --check`.

## Verification

- Confirm the new IR behavior test fails before implementing multiplication for the intended missing instruction/contract.
- Confirm the backend behavior test fails before machine-code support and passes after implementation by linking and running the emitted object.
- Run the documented Crystal suite and formatting checks; inspect the final diff to confirm no parser or source grammar changes.
