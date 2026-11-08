# Unit values in IR

## Goal

Add a language-neutral `unit` value to the typed IR and support it in the Linux x86-64 backend. This gives future frontends a way to represent a single no-payload value such as Python-like `None`, without making the IR depend on source-language spelling or syntax.

## Agreed behavior

- `unit` is a full SSA value with exactly one inhabitant, not an absence of an IR result.
- A unit value may appear as a function parameter or result, an `invoke` normal result, a `phi` value, and a `return` operand.
- IR can explicitly produce the single unit value.
- The x86-64 representation has zero size: it receives no register, stack slot, or argument slot. Unit arguments are omitted when laying out the private internal ABI; non-unit arguments retain their relative order. A unit return carries no payload. The exception status remains in `RDX` as before.
- No source syntax, parser, semantic rule, or source-level `None` support is added in this feature.
- `unit` has no arithmetic or comparison operations; the IR currently has no general equality operation.

## Acceptance criteria

- The IR type and its diagnostic S-expression representation identify `unit` distinctly from integer and boolean types.
- The verifier accepts unit values in all agreed SSA positions and rejects using an integer or boolean constant as a unit value.
- The backend emits no machine storage or argument movement for unit values, while calls with mixed unit and non-unit arguments pass each non-unit argument to the matching parameter.
- Unit-returning functions and calls preserve normal and exceptional control flow; the caller still checks `RDX` and an exceptional return remains distinguishable from a successful unit return.
- The backend rejects `main -> unit`, because `_start` must use `main`'s result as the process exit status.
- The README documents the IR unit value and its private x86-64 ABI behavior.

## Implementation steps

1. Add `IrType::Unit` and a dedicated unit-constant instruction; integrate them with IR building, S-expression dumping, and verification.
2. Ensure function signatures, returns, `phi`, and call/invoke validation preserve unit types through the existing typed SSA model.
3. Teach machine lowering and register allocation that unit values have no physical location. Omit unit parameters and call arguments from machine argument layout, and emit no return payload for unit results while retaining the exception result in `RDX`.
4. Add focused IR and backend behavior coverage for unit constants, `phi`, direct and nested calls, mixed unit/non-unit parameters, unit returns, and exception propagation.
5. Update README architecture and ABI documentation.
6. Run the documented compiler checks and inspect the final diff.

## Verification

- Confirm the IR verifier accepts and rejects the cases specified above.
- Compile representative typed IR through the backend and verify generated executables return the expected integer result after unit-valued calls.
- Exercise a unit-returning function that propagates an exception and confirm the caller follows the exceptional edge.
- Run the repository's documented checks and review the full diff against `AGENTS.md`.
