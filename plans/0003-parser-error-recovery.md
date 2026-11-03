# Parser Error Recovery Feature Plan

## Goal

Let the parser return a useful partial AST and multiple syntax diagnostics for incomplete or malformed source, so future editor tooling can inspect valid parts of the file.

## Confirmed behavior

- Recover inside functions; preserve valid parts before and after malformed syntax.
- Represent malformed or missing syntax in the AST with an `ErrorNode`.
- Return diagnostics with source spans and clear messages instead of aborting at the first parser error.
- Keep parsing syntax only. Do not add name resolution, type checking, or LSP protocol code.
- Lexer failures remain fail-fast and are outside this feature.

## Recovery boundaries

- At module level, resume at the next top-level `def` or EOF.
- In parameter and call argument lists, synchronize at commas or the closing parenthesis, preserving later valid elements.
- In expressions, synchronize at operators, list delimiters, newline, dedent, or EOF where safe.
- Guarantee that every recovery path consumes input or returns at a recognized synchronization token.
- Do not run semantic analysis or produce typed IR when parser diagnostics exist.

## Result and AST API

- Return a parse result containing the partial `ParsedModule` and an ordered diagnostic list.
- Add a generic `ErrorNode` to the AST union and typed visitor API.
- Let error nodes retain a recovered subtree when one is available; diagnostics for missing syntax use zero-width spans.
- Preserve the current AST and source-span behavior for valid programs.

## Acceptance

- The checked-in example produces the same AST and no diagnostics.
- A syntax error inside an expression produces a diagnostic and an error node while later valid syntax remains available in the AST.
- Errors in a parameter or argument list do not discard later valid list elements.
- Multiple independent syntax errors are reported in one parse result.
- Diagnostics identify the source location; the parser does not raise on ordinary syntax errors.
- The lexer still reports lexical errors through its existing fail-fast API.

## Implementation and verification

1. Add behavior tests for partial AST recovery, multiple diagnostics, preserved list elements, and valid-input compatibility.
2. Add the diagnostic/result API and `ErrorNode` visitor dispatch.
3. Replace fail-fast parser exits with context-specific synchronization and error-node insertion.
4. Update README and verify formatting plus `crystal spec`.
