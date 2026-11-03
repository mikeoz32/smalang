# Agent Guidance

Read [README.md](README.md) for project goals and design.

## Code

- Use intention-revealing names.
- Keep functions small and single-purpose.
- Keep computational functions pure: no I/O, mutation, or other side effects. Confine required effects to explicit boundary functions.
- Remove duplication and needless comments.
- Handle errors explicitly.
- Leave touched code clearer than you found it.

## Design

- Use polymorphism instead of type- or variant-based conditional dispatch. Keep simple value mappings conditional.
- Prefer instance methods. Use static methods only when they cannot benefit from instance state or polymorphism.

## Compilation

- Resolve at compile time everything whose inputs are known then. Defer only runtime-dependent work.
- Reject invalid programs during compilation.
- Do not implement unresolved language or compiler design decisions. Record confirmed decisions in README and raise ambiguities before proceeding.

## Testing

- Write one failing behavior test before implementing each behavior; confirm it fails for the intended reason.
- Make it pass with the minimum code. Refactor only while all tests pass.
- Test observable behavior, not private methods, call order, or internal structure.
- Add tests only for requirements, regressions, or meaningful risks. Never add tests for coverage alone.
- Prefer real, deterministic collaborators. Mock only external, slow, or nondeterministic boundaries.
- Keep tests focused, deterministic, independent, and fast.
- Test language features by compiling `.py` programs and checking binary behavior. Test internal IR only when its format or semantics are a stable contract.

## Repository Workflow

- Before implementing a feature, use `$feature-interview`; save the plan in `plans/` and wait for explicit approval before coding.
- Use `main` as the trunk. Do not create `dev` or `stage` branches.
- Create each short-lived `feature/*` or `fix/*` branch from up-to-date `main` in a dedicated Git worktree at `.worktrees/<branch-name>`; do not switch the primary working tree to feature branches. Reuse that worktree while continuing the branch. Merge branches back promptly and delete them after merging.
- Tag verified commits on `main` as `vMAJOR.MINOR.PATCH`.
- Before every commit, reread this file, review the full diff against its rules, and run the documented checks. Fix violations and exclude unrelated changes.
