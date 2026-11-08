# Match Expression Lexer and Parser

## Goal

Add Python-inspired source syntax for boolean `match` expressions. This feature ends at parsing and AST construction; semantic validation, IR lowering, and backend support remain separate features.

## Agreed Behavior

- `match` is an expression. Each `case` contains a result expression, and the AST represents the whole construct as an expression.
- The initial scrutinee and patterns are boolean: `true`, `false`, and wildcard `_`.
- Match syntax is layout-based. Each `case` is nested one indentation level below its `match` header; the case result expression follows `:` on the same line.
- Example:

  ```python
  def choose(value: bool) -> int:
      return match value:
          case true: 1
          case false: 0
  ```

- Keep the existing four-space indentation rule. The parser builds the AST and reports syntax errors; it does not check exhaustiveness, duplicate or unreachable patterns, scrutinee types, or result type agreement.
- Parsing errors continue to produce partial ASTs and recover within the function, including across malformed or nested match cases.

## Acceptance Criteria

- The lexer recognizes `match` and `case` as whole-word keywords while preserving longer identifiers containing those words.
- The parser builds arena-owned AST nodes for a match expression, ordered cases, boolean literal patterns, and wildcard patterns, with source spans and `NodeId` links.
- A match expression parses wherever the current expression grammar accepts an expression, including as a function's returned expression.
- Valid two-literal matches and literal-plus-final-wildcard forms parse; semantic validity is deferred.
- Missing scrutinees, malformed case headers/patterns, and missing case results produce source-located parser diagnostics and recover to following functions.
- Invalid indentation remains a source-located lexical error under the existing lexer contract.
- Existing lexer and parser behavior remains unchanged for programs without `match`.

## Implementation Steps

1. Add failing lexer tests for `match`/`case` keyword recognition and identifier boundaries.
2. Add failing parser behavior tests for match AST construction, case ordering, supported patterns, expression results, and nested layout.
3. Extend the AST arena and visitor with match-expression, case, and pattern nodes; update existing visitor implementations for the new AST variants.
4. Parse match expressions and case clauses using the existing indentation tokens and function-level recovery.
5. Add focused malformed-syntax and recovery tests, then run the documented checks.

## Verification

- Run the focused lexer and parser specs while implementing each behavior.
- Run `crystal tool format --check`, `crystal spec`, and `git diff --check` after implementation.
- Review the full feature diff against `AGENTS.md` before commit.
