# Uppercase Boolean Literals

## Goal

Use Python-style capitalization for boolean literals throughout Smalang source syntax.

## Agreed Behavior

- `True` and `False` are the only boolean literal spellings in expressions and `match` patterns.
- `true` and `false` are ordinary identifiers, not keywords or aliases.
- The type name remains lowercase `bool`; internal IR values and semantics do not change.

## Acceptance Criteria

- The lexer emits boolean literal tokens only for exact `True` and `False` spellings.
- Lowercase `true` and `false` tokenize as identifiers and receive normal name-resolution behavior.
- Parser, semantic, and end-to-end tests cover both capitalized literals and lowercase identifiers.
- Match examples and README syntax use `True` and `False` consistently.
- All documented checks pass.

## Implementation Steps

1. Add failing lexer, parser, and behavior specs for capitalized literals and lowercase identifiers.
2. Update lexer recognition, diagnostics, examples, and documentation.
3. Run formatting and the full spec suite; review the complete diff against `AGENTS.md`.

## Verification

- `crystal tool format --check`
- `crystal spec`
- `git diff --check`
