# Bool IR and Backend Plan

## Goal

Add typed `bool` support to Smalang IR, AST-to-IR lowering, and the Linux x86_64 backend, building on the existing frontend support.

## Agreed behavior

- Represent booleans as a distinct `IrType::Bool` with only canonical values `0` and `1`; render the type as `bool` in diagnostic S-expression dumps.
- Support bool constants, function parameters and results, returns, internal calls, and `phi` values. Preserve exact type matching; do not allow implicit conversion between `bool`, `isize`, and `usize`.
- Allow `bool` as a `branch` condition. Keep the existing integer branch behavior where zero is false and any nonzero integer is true.
- Do not add boolean arithmetic, logical operators, comparisons, source-language conditions, or changes to the `main() -> int` requirement.
- The private Smalang ABI passes bool values as canonical `0` or `1` in the existing 64-bit argument registers/stack slots; a bool result is canonical in `RAX`, while exception status remains in `RDX`.
- C ABI and FFI remain a separate future feature. This work adds no C-compatible declarations, exports, external calls, or boundary adapters.

## Scope

- Extend typed IR, verifier, visitor dispatch, diagnostic dumps, and builder APIs for bool values.
- Lower existing semantic bool types and `true`/`false` literals into typed IR.
- Extend x86_64 code generation for bool constants and bool values flowing through parameters, returns, calls, `phi`, and conditional branches.
- Update `README.md` to record the IR representation and private ABI while keeping C FFI deferred.
- Add focused IR, lowering, and generated-binary behavior specs.

## Acceptance criteria

- Valid IR supports bool constants, signatures, calls, returns, `phi`, and bool-controlled branches; malformed bool constants and bool arithmetic are rejected by the verifier.
- Diagnostic S-expression output uses `bool` for bool-typed values and signatures.
- Source lowering maps `true` and `false`, bool parameters/results, and nested bool calls to verified IR.
- Generated code passes canonical bool values through the private 64-bit ABI and chooses the correct branch for both `false` and `true`.
- Existing integer branch behavior, exception propagation through `RDX`, and `main() -> int` behavior remain intact.
- No C ABI/FFI behavior or boolean source operators/conditions are introduced.

## Implementation steps

1. Add failing IR behavior specs for bool constants, signatures, return/call/phi flow, bool branches, S-expression output, and invalid bool values or arithmetic.
2. Implement the bool IR type, verifier rules, builder support, visitor handling, and diagnostic dump representation.
3. Add failing source-lowering specs for bool literals, parameters, results, and nested calls; implement bool type/literal lowering and ensure produced modules verify.
4. Add failing backend specs that link emitted objects with `ld` and exercise bool arguments, results, and true/false branch outcomes; implement x86_64 lowering using the existing 64-bit ABI slots and registers.
5. Update README to document bool IR semantics and the private ABI boundary, explicitly leaving C FFI for a later feature.
6. Run focused specs, the full Crystal spec suite, formatting checks, and `git diff --check`.

## Verification

- For each behavior, first confirm its focused test fails for the missing bool behavior, then implement the smallest change that makes it pass.
- Link generated objects with `ld` and run them without `cc`.
- Run `crystal tool format --check`, `crystal spec`, and `git diff --check`.
