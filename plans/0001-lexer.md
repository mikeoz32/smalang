# Lexer Feature Plan

## Goal

Implement a Crystal lexer that converts smalang source text into tokens. This feature ends at the token stream; it does not include a parser, AST, IR, or backend.

## Agreed rules

- Emit `NEWLINE`, `INDENT`, and `DEDENT` tokens.
- Require exactly four spaces per indentation level and increase indentation one level at a time. Dedents may close multiple levels. Reject tabs, incomplete indentation levels, and inconsistent dedents.
- Do not support comments in this first lexer.

## Data representation

- Let `SourceFile` own the source `String` and line-start byte offsets (`0`, then the offset after each LF), appended during scanning. Scan the read-only `Bytes` view from `String#to_slice`.
- Define `TokenKind : UInt8` and immutable `SourceSpan` and `Token` structs. Use `SourceSpan(start : Int32, length : Int32)` with half-open byte ranges; keep the token as kind plus span.
- Return a `TokenStream` that retains its `SourceFile` and stores tokens in a contiguous `Array(Token)`. Give the array a source-size-based initial capacity estimate; keep the estimate tunable.
- Store no lexeme strings, parsed literal values, or line/column fields per token. Resolve lexemes from source spans; resolve 1-based line and byte-column positions by binary-searching the line-start offsets.
- Use the actual source bytes for ordinary token spans. Give synthetic `INDENT`, `DEDENT`, and `EOF` tokens zero-length spans at their triggering source offset.
- Track indentation as an integer depth; fixed four-space levels do not require a general indentation stack.
- Classify the four fixed keywords with direct byte comparisons. Do not allocate strings or intern names in the lexer.
- Scan bytes in one pass. Avoid per-character arrays, regex tokenization, and substring allocation.

Crystal arrays store struct values inline, so this avoids one heap allocation per token. Struct alignment may add padding; do not assume a packed byte size or introduce bit-packing that limits token/source lengths. These choices match Crystal's byte-oriented String API and `Int32` byte size, while keeping source ownership explicit for later parser and AST spans. Keep unsafe pointer tricks out of the initial implementation; tune the scan loop only if benchmarks show it is a bottleneck. The capacity estimate and scan-loop optimizations are performance details, not public representation contracts.

## Token set

- Keywords/types: `def`, `return`, `int`, `uint`.
- Names and literals: ASCII identifiers (`[A-Za-z_][A-Za-z0-9_]*`) and decimal integer literals. `-` is always a separate token.
- Operators and punctuation: `+`, `-`, `(`, `)`, `:`, `,`, `->`.
- Structure: `NEWLINE`, `INDENT`, `DEDENT`, and `EOF`.

Lexing rules: ignore blank lines; accept LF and CRLF; map byte offsets to 1-based line and column positions through the source line-start table; synthesize a final `NEWLINE` when needed, then flush `DEDENT`s before `EOF`. Reject unsupported characters with a location-aware lexical error.

## Steps

1. Define `SourceFile`, `TokenKind`, immutable `SourceSpan` and `Token` structs, and `TokenStream` using the proposed data representation.
2. Write focused token-stream and lexical-error tests; confirm they fail for the expected reasons.
3. Implement scanning for the agreed token set and indentation rules.
4. Verify the token stream for `examples/first_program.py` and run the lexer tests.

## Acceptance

- The example produces the expected ordered token stream, including indentation and end-of-file tokens.
- Invalid characters, tabs, and malformed indentation produce clear errors with source locations.
- The lexer does not parse syntax or build an AST.
