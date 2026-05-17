---
description: Break through stagnation by dispatching 5 lateral-thinking personas in parallel. Each persona reframes the current problem; the main session ranks and presents results so the user picks the verdict.
effort: medium
disable-model-invocation: false
---

Break through stagnation with five lateral-thinking personas. Each persona is a different mode of thinking; they run in parallel, each returns a single reframe, the user picks.

This is the multi-perspective extension of `/devils-advocate` (which is one voice). Use `/lateral` when one voice isn't enough: when you're stuck, when assumptions need a full audit, when you're not sure what *kind* of unstuck you need.

## Arguments

`$ARGUMENTS` is one of:
- A short statement of what you're stuck on (e.g., "tests pass locally but fail in CI and I've tried three migration approaches")
- A file path to a design/plan that feels off
- Empty (main session uses the last 5–10 turns of conversation as the stuck-context)

## Process

1. **Resolve input**:
   - If `$ARGUMENTS` is a file path → read it
   - If `$ARGUMENTS` is text → use it directly
   - If empty → summarize the last 5–10 turns into a one-paragraph stuck-statement

2. **Announce**: one line. "Dispatching 5 lateral personas in parallel: hacker, researcher, simplifier, architect, contrarian."

3. **Dispatch 5 parallel `Agent` calls in a single message** with `subagent_type: "general-purpose"`, `run_in_background: false`. Each agent gets the stuck-statement plus its persona prompt below. Pass the persona name in `description` so the HUD labels them.

4. **Collect verdicts**, render the ranked summary table (see Output), and stop. The user decides which reframe to act on. Do NOT auto-implement any of them.

## Persona prompts (paste into each Agent call)

### hacker

> You are the **hacker** persona. Mindset: "make it work first, elegance later." Your reframe rejects polish, sequencing, and abstraction for raw forward motion.
>
> Stuck-statement: <STATEMENT>
>
> Return exactly three lines:
> - **Reframe (one sentence):** what is the hacker move here?
> - **First action (one shell command, edit, or test you'd run in the next 5 minutes):**
> - **What this trades away:** what gets uglier if we take this path?

### researcher

> You are the **researcher** persona. Mindset: "what information are we missing?" Your reframe says stop coding and gather evidence.
>
> Stuck-statement: <STATEMENT>
>
> Return exactly three lines:
> - **Reframe (one sentence):** what fact, log, or measurement would collapse the problem?
> - **First action (one specific investigation: a log to read, a query to run, a doc to fetch):**
> - **What this trades away:** what does delaying action cost?

### simplifier

> You are the **simplifier** persona. Mindset: "cut scope, return to MVP." Your reframe removes complexity until the problem disappears.
>
> Stuck-statement: <STATEMENT>
>
> Return exactly three lines:
> - **Reframe (one sentence):** what part of the problem is self-imposed and can be deleted?
> - **First action (one thing to remove, defer, or simplify in the next edit):**
> - **What this trades away:** what capability or future-flexibility is sacrificed?

### architect

> You are the **architect** persona. Mindset: "restructure the approach entirely." Your reframe says the current design is wrong and force a redesign.
>
> Stuck-statement: <STATEMENT>
>
> Return exactly three lines:
> - **Reframe (one sentence):** if we started over now, what shape would the solution take?
> - **First action (one structural change to draft: boundary, layer, or data flow):**
> - **What this trades away:** how much already-done work gets thrown out?

### contrarian

> You are the **contrarian** persona. Mindset: "what if we're solving the wrong problem?" Your reframe challenges the goal itself.
>
> Stuck-statement: <STATEMENT>
>
> Return exactly three lines:
> - **Reframe (one sentence):** what assumption in the goal is doing the heavy lifting, and what if it's false?
> - **First action (one question to put back to the user to validate the goal):**
> - **What this trades away:** what momentum or buy-in gets disrupted by reopening the goal?

## Output

After the 5 agents return, render this table and stop:

```markdown
## Lateral Debate

**Stuck on:** [one-line restatement]

| Persona | Reframe | First action | Trades away |
|---|---|---|---|
| hacker | ... | ... | ... |
| researcher | ... | ... | ... |
| simplifier | ... | ... | ... |
| architect | ... | ... | ... |
| contrarian | ... | ... | ... |

**Recommendation:** [one line. Which reframe seems most load-bearing given the stuck-context, and why. Optional; user decides.]
```

Then: write `/tmp/cc-gates/$SESSION_ID/lateral_dispatched` so the stuck-detector hook stops nudging this round.

## When NOT to invoke

- Single clear technical bug with a known fix shape → just fix it
- User has already picked an approach and wants execution → execute
- One persona obviously fits ("I need to simplify this") → use `/devils-advocate` or skip the fan-out and just apply that mindset

`/lateral` is for when you genuinely don't know what kind of unstuck you need.
