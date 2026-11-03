---
name: independent-code-review
description: Independently review a code change before commit, fix confirmed findings, and repeat review until no actionable issues remain.
---

# Independent Code Review

- Review the complete change against its intended behavior and applicable `AGENTS.md` rules. Delegate a read-only review to a subagent; ask for actionable bugs, regressions, missed requirements, or clear rule violations, with file locations and evidence.
- Verify each finding. Fix confirmed issues and run the relevant checks.
- Ask a fresh subagent to review the full updated change. Repeat until it reports no actionable issues.
- If subagents are unavailable, say independent review was not completed. Do not commit, merge, or push as part of this skill.
