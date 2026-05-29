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

## Codex Second Seat (co-dispatch with Devil's Advocate)

When the Devil's Advocate complexity gate fires, **also dispatch Codex as a cross-provider second seat** on the same plan text, if you have the Codex CLI / `openai-codex` plugin installed (opt-in). The two reviewers run in parallel; their findings are presented together before the user decides whether to proceed, revise, or reconsider.

**Why co-dispatch:** Claude reviewers share blind spots within the model family. Codex (GPT-5.x) gives non-overlap signal on the *plan*, just like `codex-dispatch.md` mandates non-overlap signal on the *diff*. Plan-time non-overlap is cheaper than commit-time non-overlap: catch the design flaw before any code is written.

**Trigger:** identical complexity gate as the Devil's Advocate above (any one of: 2+ components, new external dep, multiple viable approaches, 3+ tasks or cross-component plan). Co-dispatch is the default when Codex is available; skip it only with a one-sentence reason in the announcement.

**Mechanism (use `task` mode, not `review`):** the plan is text, not a git diff. The `review` / `adversarial-review` modes resolve their prompt from `git diff` and silently no-op on plan text. This plugin ships a wrapper at `plugin/tools/codex-plan-critique.sh` that bakes in the read-only critique envelope (prioritized findings, no code patches, no file edits):

```bash
# Feed the same plan text the devils-advocate received
$HOME/.claude/plugins/cache/claude-code-multimodel-workflow/*/plugin/tools/codex-plan-critique.sh --plan-file /tmp/plan.md
# or:
echo "$PLAN_TEXT" | $HOME/.claude/plugins/cache/claude-code-multimodel-workflow/*/plugin/tools/codex-plan-critique.sh
```

The wrapper dispatches `node …/codex-companion.mjs task --effort high --background` and returns a job id; fetch with the wrapper's `result <job-id>` passthrough.

**Announce:** "Dispatching the devil's advocate and Codex plan-critique on this design in parallel." If skipping Codex specifically: "Dispatching the devil's advocate; skipping Codex plan-critique because [specific reason]."

**Results handling:** present *both* the Claude DA verdict and the Codex findings side-by-side. Group Codex findings by severity (Critical / Important / Minor). Don't auto-act on Codex output; mirror the Polish-QA pattern from `visual-qa-dispatch.md`: the user decides what to fold in.

**Cap:** plan critique is **advisory and does not consume the commit-time Codex slot.** The budget is per-surface: one plan critique during planning AND one diff-level `adversarial-review` before shipping implementation. Subsequent code changes still need `codex-dispatch.sh adversarial-review` (or a written diff-gate bypass) per `codex-dispatch.md`: plan critique never substitutes for diff review, because the implementation may diverge from the plan or introduce new failure modes the plan-text reviewer couldn't see. Don't run multiple plan critiques against the same plan iteration in the same session; that's the plan-time loop-drain.

**`task` mode does NOT trigger the codex-stop-gate.** The gate keys off `review`/`adversarial-review` jobs against a diff; plan critique runs in parallel and leaves the diff-time gate untouched.

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
