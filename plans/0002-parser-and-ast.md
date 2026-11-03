# Parser and AST Feature Plan

## Goal

Parse the lexer token stream into an AST stored in an index-based arena. The parser handles syntax only; semantic analysis and typed IR are later features.

## Confirmed syntax

- A module contains only top-level function definitions. No nested functions or top-level statements.
- Function signatures use `def name(parameters) -> type:`. Parameters have explicit `int` or `uint` types.
- Each function body contains exactly one `return expression` statement.
- Calls use a direct function name and zero or more positional expression arguments. No method calls or named arguments.
- Expressions contain decimal integer literals, identifiers, calls, parentheses, and binary `+`/`-`.
- `+` and `-` have equal precedence and associate left to right. Parentheses group expressions. Unary minus is not supported.
- Reuse lexer `NEWLINE`, `INDENT`, `DEDENT`, and source spans.

## Confirmed grammar detail

- Omit trailing commas from parameter and argument lists in the initial grammar.

## AST representation

- Return a parsed module that retains its `SourceFile` and owns an `AstArena`.
- Store a union of immutable, node-specific AST structs in a contiguous `Array(AstNode)`; refer to nodes with `Int32` `NodeId` indices, never raw pointers.
- Store variable-length lists (module functions, parameters, call arguments) in a shared contiguous `Array(NodeId)` using start/count ranges.
- Store names and literals as `SourceSpan`s into the retained source. Store types and operators as small enums; do not allocate per-node strings or arrays.
- Give node variants common visitor methods; keep type switches out of AST consumers. Do not add a custom unsafe bump allocator.
- Keep syntax-node variants limited to the agreed grammar: module, function, parameter, return, binary expression, call, identifier, and integer literal.

## Parser boundary

- Build the AST and reject malformed syntax with source-located parse errors.
- Do not resolve names, validate duplicate declarations or function existence, check call arity or type compatibility, or require `main`. These checks belong to semantic analysis when producing typed IR.

## Steps

1. Define `AstArena`, `NodeId`, child ranges, and immutable syntax-node structs using the selected indexed representation.
2. Add behavior tests for the example AST, function signatures, expression grouping/associativity, nested calls, and source-located syntax errors.
3. Implement recursive-descent parsing for declarations and primaries, plus precedence climbing for `+`/`-` expressions.
4. Verify the checked-in example parses and the parser test suite passes.

## Acceptance

- `examples/first_program.py` produces a module AST with both functions, parameter and return types, return expressions, calls, and arithmetic.
- Parentheses and left-associative `+`/`-` produce the agreed AST structure.
- Invalid token sequences fail with a clear source location.
- The parser performs no semantic analysis and emits no IR.
