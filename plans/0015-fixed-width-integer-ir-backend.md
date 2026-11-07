# Fixed-Width Integer IR and Backend Plan

## Goal

Extend typed IR, source lowering, and the Linux x86_64 backend to support the eight fixed-width integer types already accepted by the frontend.

## Proposed behavior

- Add distinct IR types for `int8`/`uint8`, `int16`/`uint16`, `int32`/`uint32`, and `int64`/`uint64`. Keep `int`/`uint` as distinct pointer-sized `isize`/`usize` types, even where widths match.
- Preserve exact type matching. Do not add implicit conversions, casts, literal suffixes, or source syntax.
- Accept fixed-width integer types in constants, function signatures, calls, returns, `phi`, and integer `branch` conditions. Integer branches remain false for zero and true for nonzero.
- Allow all existing integer IR operations (`add`, `sub`, `mul`, `div`, and `rem`) for every integer IR type; continue to reject bool and exception values as arithmetic operands.
- Validate constants against the declared type's signed or unsigned range.
- Apply the existing integer arithmetic contract at the declared width `n`: `add`, `sub`, and `mul` wrap modulo `2^n`, with signed results interpreted as two's-complement values. Signed `div` truncates toward zero, signed `rem` has the dividend's sign, and the minimum signed value divided by `-1` produces that minimum value with remainder zero. Unsigned `div` and `rem` remain unsigned. A runtime zero divisor continues to produce the existing `DivisionByZero` exception.
- Keep the private Smalang ABI transport in 64-bit registers and stack slots. Normalize signed values by sign extension and unsigned values by zero extension at value boundaries; keep results in `RAX` and exception status in `RDX`. C ABI and FFI remain out of scope.

## Scope

- Extend IR type metadata, verifier rules, builders, S-expression dumps, and lowering from all frontend integer types.
- Extend x86_64 machine lowering for typed constants, arithmetic, division/remainder, branching, calls, parameters, and results while preserving the 64-bit register allocator and private ABI layout.
- Update `README.md` to remove the frontend-only limitation and record the width-aware IR/backend semantics.
- Add focused IR, lowering, and generated-binary behavior specs.

## Acceptance criteria

- Each frontend integer type lowers to a distinct IR type with the expected width and signedness; `int64`/`uint64` remain distinct from `isize`/`usize`.
- The verifier accepts in-range constants and all existing integer operations for fixed-width types, and rejects out-of-range constants, mixed integer types, and non-integer arithmetic.
- S-expression dumps print the fixed-width type names and preserve the existing dump style.
- Generated programs pass fixed-width values through parameters, calls, results, and stack arguments using the documented canonical representation.
- Generated code produces correct width-aware results for signed and unsigned `add`, `sub`, `mul`, `div`, and `rem`, including wraparound, signed minimum divided by `-1`, and runtime division by zero.
- Integer branch conditions preserve zero/nonzero behavior for fixed-width types; bool behavior and exception propagation remain intact.
- Objects continue to link with the system linker without C runtime or external unwinder dependencies.
- The source language gains no new operators, conversions, or ABI declarations.

## Implementation steps

1. Add failing IR behavior specs for fixed-width types, signatures, constants, arithmetic, range validation, branches, and dump output; extend IR type metadata and verifier behavior.
2. Add failing lowering specs for each source integer type in function signatures, literals, arithmetic, and calls; map semantic types to their corresponding IR types.
3. Add failing generated-binary behavior specs for width-aware constants, normalization, arithmetic, division/remainder, branches, and call/return transport; implement width-aware x86_64 emission while keeping 64-bit allocation and ABI slots.
4. Update README with the fixed-width support boundary and operation semantics.
5. Run focused specs, the complete Crystal spec suite, formatting checks, and `git diff --check`.

## Verification

- Verify IR contracts and malformed-module diagnostics through focused IR specs.
- Compile source programs using fixed-width signatures and `+`/`-`, then check generated executable behavior.
- Exercise IR-only `mul`, `div`, and `rem` behavior using generated objects linked by `ld`, including signed/unsigned boundaries and exceptional zero division.
- Run `crystal spec`, the repository's documented formatting checks, and `git diff --check`.
