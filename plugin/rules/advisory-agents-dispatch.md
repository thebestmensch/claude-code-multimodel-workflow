# Advisory Agent Integration

When running brainstorming or writing-plans workflows, auto-dispatch advisory agents at the points below.

**Always announce.** One line: "Dispatching the research agent to investigate X" or "Dispatching the devil's advocate to challenge this design; it crosses multiple components."

## Research Agent (during brainstorming)

When a clarifying question reveals a topic needing deep investigation (existing tools, library comparisons, infrastructure fit), dispatch in background:

```text
Agent(subagent_type="research-agent", run_in_background=true)
```

Continue brainstorming while it runs. Incorporate the returned 2-3 options + tradeoffs into approach proposals.

**Preflight before tool/vendor/library evaluations.** Elicit constraints that shape the search space *first* (billing model, integration shape, diversity vs. existing tools, self-host preference, scale). The research-agent skill owns the full prompt list. Constraints surfaced after a research pass invalidate it.

**Don't dispatch for:** user-preference questions (ask them), topics answerable from codebase exploration, simple factual lookups.

## Devil's Advocate (during brainstorming and planning)

After proposing 2-3 approaches OR drafting a plan, evaluate the complexity gate.

**Fire when ANY:**
- Design involves 2+ components or services
- New external dependencies introduced
- Multiple viable approaches with real tradeoffs
- Plan has 3+ tasks or crosses component boundaries

**Skip when ALL:** single-file/config/copy change, user specified exact approach, purely additive with no tradeoffs, trivial scope.

```
Agent(subagent_type="devils-advocate", model="opus", run_in_background=true)
```

Pass: the full design/plan text + relevant codebase context.

**Results:** `PROCEED` → note briefly and continue. `REVISE` → fold revision points into the proposal before presenting. `RECONSIDER` → present the challenge to the user and discuss before proceeding.

## Lateral Debate (when one voice isn't enough)

Devil's advocate is one perspective. `/lateral` fans out **five** lateral-thinking personas (hacker, researcher, simplifier, architect, contrarian) in parallel, each returns a single reframe, the user picks. Pattern borrowed from ouroboros's `ooo unstuck`.

**Auto-trigger surfaces (hook-driven, no manual invocation needed):**
- `lateral-stuck-detector.sh` fires on `UserPromptSubmit` when the prompt contains frustration / stuck signals ("still failing", "tried 3 times", "i'm stuck", "keeps failing", "this isn't working", "i give up", "nothing works"). Injects a context note nudging `/lateral`.
- Same hook fires on `PostToolUse(Edit|Write|NotebookEdit)` at the 4th edit to the same file in a session: signal that you're cycling on the same fix shape and a reframe may unstick faster than another retry.

**Cap:** one nudge per session (UserPromptSubmit path) + one nudge at 4th same-file edit. Once `/lateral` runs, the dispatch marker (`lateral_dispatched`) silences both surfaces for the rest of the session.

**Direct invocation:** `/lateral "stuck statement"` or `/lateral` with a file path, or empty to use the last 5–10 turns. Don't use `/lateral` when one persona obviously fits (use devil's advocate) or when the user has already picked an approach.

## Ambiguity Gate (before exiting plan mode)

`ambiguity-gate.sh` fires on `PreToolUse(ExitPlanMode)` and **denies** exit when the plan text contains too many ambiguity markers: TBD, TODO, "decide later", "maybe", "probably", "not sure", "unclear", "depends on", `???`. Pattern borrowed from ouroboros's Seed-readiness check: refuse to leave plan mode while unresolved decisions remain.

**Behavior:** trivial plans (< 3 numbered tasks AND < 600 chars) pass silently. Above that, threshold is `5 + (plan_len - 600) / 500` markers. Above threshold → deny with a breakdown of which marker classes hit.

**How to clear:** resolve hedging by asking the user, dispatch `/lateral` if the choice itself is the blocker, or bypass with `touch /tmp/cc-gates/$SESSION_ID/skip_ambiguity_gate` (only when the markers are intentional, e.g. the plan documents known open questions that don't block first steps).

Runs alongside `devils-advocate-plan-gate.sh`: both fire on `ExitPlanMode`; the ambiguity gate is mechanical / cheap, devil's advocate is LLM / thorough.

## Restate-Goal Gate (before destructive actions)

`restate-goal-gate.sh` fires on `PreToolUse(Bash)` and **denies the first destructive command** in a session until the goal is restated and explicitly approved. Pattern borrowed from ouroboros's restate-before-seed gate: force one beat of reflection before irreversible work.

**Destructive surfaces gated:** `git push` (any form except `--dry-run`), `gh pr create / merge / ready`, `git reset --hard`, `rm -rf`.

**Approval handshake:** restate (a) the goal in one sentence and (b) the blast radius / risk in one sentence, then `touch /tmp/cc-gates/$SESSION_ID/goal_restated`. Once approved, the rest of the session is unblocked (one-time gate per session, not per command).

**Bypass:** `touch /tmp/cc-gates/$SESSION_ID/skip_restate_gate` when the destructive action *is* the entire goal ("force-push the fix you already approved").
