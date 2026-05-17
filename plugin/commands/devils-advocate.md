---
description: Challenge a design or plan by dispatching the devils-advocate agent (shipped under `plugin/agents/`). Returns claim/evidence/severity/alternative for each weak point.
effort: medium
---

Challenge a design or plan by dispatching the devil's advocate agent.

## Arguments

`$ARGUMENTS` is one of:
- A file path to a design doc or plan (e.g., `docs/superpowers/specs/2026-03-30-foo-design.md`)
- Pasted text describing an approach to challenge
- Empty (will review the most recent spec in `docs/superpowers/specs/`)

## Process

1. **Resolve input**:
   - If `$ARGUMENTS` is a file path → read the file
   - If `$ARGUMENTS` is text → use it directly
   - If empty → find the most recent file in `docs/superpowers/specs/` and read it
2. **Gather context**: read CLAUDE.md and any files referenced in the design/plan for codebase context
3. **Announce**: tell the user what you're about to challenge and that you're dispatching the devil's advocate agent (one line)
4. **Dispatch** the `devils-advocate` agent with:
   - The full design/plan text
   - Relevant codebase context (referenced files, existing patterns)
   - The research question: "Review this design/plan. Challenge it along your six axes."
5. **Present findings** to the user with the agent's structured output and verdict

## Output

```
## Devil's Advocate Review

**Target:** [document name or "inline text"]
**Verdict:** [PROCEED | REVISE | RECONSIDER]

### Challenges

[Agent's structured findings: claim, evidence, severity, confidence, alternative for each]

### Summary

[One-line overall assessment]
```
