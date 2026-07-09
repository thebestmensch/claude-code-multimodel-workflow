# Decision Brief: Stop-Hook/Gate Topology vs. the `Workflow` Tool

**Ticket:** JM-759 (research spike)
**Date:** 2026-07-09
**Verdict:** **NO-GO** on *replacing* the enforcement layer with the `Workflow` tool; **HYBRID** as the constructive path — keep the Stop/PreToolUse hooks as the enforcer, fix the diff-reconstruction rot that actually causes the 14 footguns, and adopt the `Workflow` tool only as an *optional, opt-in executor* for heavy review passes.
**First slice:** a **diff-pinning refactor** of the existing dispatch/gate internals (not a topology swap). See "Recommendation."

---

## TL;DR

The ticket asks: could the enforcement layer (codex-stop-gate, visual-qa-stop-gate, pre-commit-gate + their marker machinery) be *replaced* by dynamic `Workflow`-tool orchestration?

**No.** Three properties of the `Workflow` tool make it structurally unable to be an enforcer:

1. **It is opt-in gated.** The tool's own contract says "ONLY call this tool when the user has explicitly opted into multi-agent orchestration." A review path that only exists when the user opts in cannot be the *default* that fires on every session. An enforcer must be default-on.
2. **It is agent-invoked with no Stop-event equivalent.** A workflow runs because the agent chose to call the tool this turn. There is no "fire at Stop regardless of the agent" hook for workflows. The load-bearing property of the gates — *enforcement even when the agent forgets* — has no workflow analog.
3. **`agent()` spawns the session model (Claude).** The codex gate's entire value is GPT-5.x cross-provider non-overlap. A workflow can only reach Codex by having a sub-agent shell out to `codex-companion.mjs` — i.e. the *current* dispatch mechanism, wrapped in orchestration overhead, with no structural gain.

**But** the footgun pain is real and worth fixing. The key finding: the 14 footguns are **not caused by "hooks are brittle."** ~8 of them are caused by one thing — the gate **reconstructs the diff at fire-time** from Edit|Write tracking + `git diff` mode heuristics + mtime-marker freshness. Those dissolve if the reviewer receives a **single, explicitly-pinned diff**. That fix lives *inside* the existing dispatch/gate path and does **not** require the `Workflow` tool. Adopting workflows to get it would be paying a large structural cost (loss of enforcement) for a benefit obtainable with a cheaper refactor.

---

## Correcting the premise: what the `Workflow` tool actually is

This section exists because it is easy — and a prior draft of this brief did — to model `Workflow` as a shell-orchestration layer that runs `git diff`, `git add -N`, `git commit`, and sets `$REVIEW_PASSED`. It is not that. From the tool contract:

- **Scripts are plain JavaScript with no filesystem, shell, or Node API access.** The script body **cannot run git** (no `git diff`, `git restore --staged`, `git add -N`, `git commit`). It orchestrates via `agent()` / `parallel()` / `pipeline()` and returns data.
- **Git-touching work must happen *inside* a spawned `agent()`.** A sub-agent has Bash and can run git — but it runs against *its own cwd*, re-exposing the same staged/untracked/sibling-repo/worktree ambiguity, one level down. Moving the git dance into an agent does not make the ambiguity disappear; it relocates it.
- **`agent()` spawns the session's model** (Claude) by default. Cross-provider (Codex) is only reachable by an agent shelling out to the Codex CLI.
- **The tool is background/turn-scoped.** It returns a task id and re-invokes the caller on completion. There is **no Stop-event workflow** and **no way for a hook to force a workflow call** (the opt-in gate blocks that).
- **It is explicitly opt-in.** Not a default-on capability.

Every "workflow equivalent" claim below is evaluated against *this* tool, not against a hypothetical bash layer.

---

## What the three gates enforce today

The "three gates" are really **three enforcement checks across two harness events**, all reading shared markers under `/tmp/cc-gates/$session_id/` that PostToolUse trackers write.

**Trackers (PostToolUse, silent bookkeepers):**
- `track-edited-files.sh` (Edit|Write) → appends code paths to `edited_files` (filters `*.md/*.json/*.yml/*.yaml/*.toml/*.txt/*.csv/*.lock`).
- `template-edit-counter.sh` / `backend-edit-counter.sh` (Edit|Write) → `template_files` / `backend_files` counts + lists.
- `codex-bash-tracker.sh` (Bash) → sets `codex_diff_dispatched` / `codex_diff_handled` / `codex_plan_dispatched` on `codex-companion.mjs` invocations.
- `dispatch-tracker.sh` (Agent|Skill) → sets `visual_qa_dispatched` / `code_review_dispatched` / etc. by matching the Agent description or Skill name.

### 1. codex-stop-gate.sh (Stop event)
**Enforces:** substantive code edits must have a Codex cross-provider *diff* review that both **dispatched** and **landed in context** before the turn ends.
**Mechanism:** releases only when BOTH `codex_diff_dispatched` AND `codex_diff_handled` are *newer than* `edited_files` (dual-marker freshness — closes the edit→dispatch→edit→result stale-certification path). Augments `edited_files` at fire-time via `git diff --name-only -z HEAD` + untracked, to catch Bash-mediated edits. Fails closed on Codex unavailability (host); env-opt-in fail-open (headless container) with audit logging. Reasoned bypass via `skip_codex_gate` (must be fresher than the latest edit). Plan-mode dispatch (`codex_plan_dispatched`) is informational — does not satisfy.

### 2. pre-commit-gate.sh (PreToolUse on Bash `git commit`)
**Enforces:** a `git commit` is blocked if UI files were edited without a fresh `/visual-qa` dispatch, or if UI/backend files were edited without a fresh `/lens-review` dispatch.
**Mechanism:** `is_stale()` compares `visual_qa_dispatched` / `code_review_dispatched` mtimes against the newer of `template_files` / `backend_files`. Visual-QA is checked only against UI edits (backend edits don't invalidate a prior UI screenshot); code-review against both. **Two-step human-approved bypass:** the agent writes a reason to `skip_commit_gate`, the *user* must `echo approved > bypass_approved`. (`codex-pre-commit-gate.sh` is the sibling that enforces the Codex marker at commit time, with `--cached` augmentation.)

### 3. visual-qa-stop-gate.sh (Stop event)
**Enforces:** mobile-app UI edits (`mobile-app/(components|app|ui|screens)/**` `.tsx/.ts`) must have a `visual_qa_dispatched` marker before the turn ends.
**Mechanism:** simple *marker-presence* check — **no staleness comparison** (a real gap: a stale visual-QA from before the latest edit still satisfies it). Single-step reasoned bypass via `skip_visual_qa_gate`. Web UI is out of scope for this gate (the pre-commit-gate covers web UI at commit time instead).

**Shared machinery:** `_lib/stop-gate-emit.sh` emits `{decision:"block"}` with per-`(hook,state-hash)` dedupe so an idle re-fire doesn't spam context; `precompact-clear-stop-gate-dedupe.sh` wipes the dedupe marker on compaction; the CC 2.1.147 harness force-clears after 8 consecutive blocks.

---

## Mapping each gate to a `Workflow` equivalent

Split every gate into two separable jobs: **execution** (actually run the review) and **enforcement** (guarantee it runs, at the right time, regardless of the agent). The Workflow tool is strong at the first and structurally incapable of the second.

| Gate | Execution → workflow? | Enforcement → workflow? |
|---|---|---|
| **code-review** (`/lens-review`) | ✅ **Excellent fit.** A `review-changes` workflow (dimensions → find → adversarially verify → synthesize) is a *better executor* than one ad-hoc `/lens-review` dispatch — it's the canonical Workflow pattern. | ❌ No equivalent. Opt-in gated + agent-invoked + no Stop-event. |
| **visual-qa** (`/visual-qa`) | ✅ **Good fit.** A workflow can screenshot + fan out Bug/Polish/A11y/Tone QA agents in parallel and consolidate. | ❌ No equivalent (same three blockers). Plus: screenshots require a rendered surface, which a headless workflow agent can only reach via Playwright MCP — same capture constraint the gate already has. |
| **codex** (cross-provider diff review) | ⚠️ **Weak fit.** `agent()` is Claude; Codex non-overlap requires an agent shelling out to `codex-companion.mjs` — the *current* dispatch with extra hops. No gain. | ❌ No equivalent (same three blockers). |

**Read the table as:** workflows can *execute* review well (better than manual serial dispatch for code-review and visual-qa), but *cannot enforce* any of it. Since the gates exist to **enforce**, a workflow is not a replacement — at best it's a better executor that a still-present enforcer would trigger.

---

## The load-bearing property (AC: is the gap acceptable?)

The gates' defining property is **enforcement at Stop regardless of agent cooperation.** The agent can forget a dispatch, rationalize a skip, or run out of context mid-task — the Stop hook fires anyway. This is precisely the failure mode the dispatch rules' "Red Flags" table catalogs: deadline pressure is *when* an agent talks itself out of review, and the involuntary gate is the backstop.

A workflow has none of this: it runs iff the agent calls the tool, iff the user has opted into orchestration, and never at Stop.

**Is giving up that property acceptable? No.** The whole reason the gate layer was built (and hardened across 14 documented footguns) is that "trust the agent to remember" empirically fails. Trading involuntary enforcement for voluntary invocation re-opens exactly the hole the gates close. The prior draft floated an "advisory workflow that auto-fires at Stop via the harness" — **that mechanism does not exist**: there is no Stop-event workflow trigger, and the opt-in gate forbids a hook from forcing the call. It cannot be built on the current contract.

**Therefore the enforcer stays a hook.** Any improvement must live *under* the enforcement layer, not replace it.

---

## The 14 footguns, by root cause (AC: survive / dissolve / new)

Numbering matches `~/.claude/rules/codex-dispatch.md` § "Gate Scope and Known Limitations." The insight is that they cluster into **four root causes**, and only one cluster is large — and that cluster is fixable *without* the Workflow tool.

### Cluster A — diff reconstructed at fire-time (8 of 14). The real rot.
These exist because the gate infers "what changed" from Edit|Write tracking + `git diff` mode + marker mtimes, rather than being handed one pinned diff.

| # | Footgun | Under a diff-pinning fix |
|---|---|---|
| 3 | Sibling-repo edits → "no diff" (cwd-relative) | **Dissolves** — pin an explicit repo root + range, not cwd. |
| 4 | Dispatch after commit sees only HEAD | **Dissolves** — pin an explicit revision range, not the working tree. |
| 5 | Staged-but-uncommitted invisible to `git diff` | **Dissolves** — the pinned range includes `--cached`. |
| 6 | Untracked new files invisible | **Dissolves** — the pinned set includes `ls-files --others`. |
| 8 | Completed review no longer satisfies gate after `git add` | **Dissolves** — key the marker to a *content hash of the pinned diff*, not the currently-staged file set. |
| 9 | Bypass mtime race (augmenter bumps `edited_files` first) | **Dissolves** — no mtime-freshness comparison; check "review covers this diff-hash." |
| 13 | Codex job tracker keyed by checkout path (worktree miss) | **Dissolves** — key by diff-hash, portable across checkouts. |
| 14 | Reading wrapper output ≠ "result retrieved" marker | **Dissolves** — "did a review of this diff-hash land" is a content check, not a marker-call check. |

**Crucial:** none of these dissolve *because of* the Workflow tool. They dissolve because the reviewer gets a pinned diff. A workflow would achieve that only as a side effect of its agent computing the diff once — and it would *re-introduce* #3/#13 inside the agent's cwd. The cheaper, enforcement-preserving way to get the same win is to pin the diff in the existing dispatch path.

### Cluster B — file-filter policy (2 of 14). Orthogonal to topology.
| # | Footgun | Note |
|---|---|---|
| 1 | Bash-mediated mutations invisible to Edit\|Write tracker | Already mitigated by the fire-time `git diff` augmenter; a pinned-diff model subsumes it. Not a topology question. |
| 2 | User-facing copy in `*.md/*.json/…` filtered upstream | A *policy* choice (what's review-worthy), independent of hooks vs. workflows. Survives unless the filter is changed deliberately. |

### Cluster C — the external Codex CLI (1 of 14). Survives either way.
| # | Footgun | Note |
|---|---|---|
| 7 | Hung Codex jobs, bail at ~5 min | The `codex-companion.mjs` process can hang regardless of what triggers it. A workflow reframes it as one failed `agent()` stage (returns null, filtered) — marginally nicer — but the CLI still hangs. Survives; the wrapper's hang-bail already handles it. |

### Cluster D — hook plumbing (3 of 14). Dissolve *only* by removing hooks — which we can't.
| # | Footgun | Note |
|---|---|---|
| 10 | Stop-hook block cap (8 blocks → turn ends) | Exists *because* there's a Stop hook. Removing hooks removes it — but that sacrifices enforcement (unacceptable). |
| 11 | Stale printed `session_id` / `current` symlink; grep `edited_files` to find the live gate dir | Session-dir routing artifact of the marker model. A simpler single-marker model reduces it; full removal needs no hooks (unacceptable). |
| 12 | Bundling bypass-write with `git commit` in one Bash call → PreToolUse denies both | Exists *because* there's a PreToolUse commit gate. Same tradeoff. |

**Honest tally.** "13/14 dissolve under workflows" (the prior draft) is wrong. Attributable to the Workflow tool *specifically*, net of the enforcement it would sacrifice: **≈0 genuinely dissolve for free.** Cluster A (8) is fixable by diff-pinning without workflows and while keeping enforcement. Cluster D (3) only "dissolves" by removing the enforcement we must keep. Clusters B (2) and C (1) survive either way. And a workflow model **newly introduces** the enforcement gap itself (agent-invoked, opt-in, no Stop-event) — the single most important property, lost.

---

## Recommendation

**NO-GO** on replacing the enforcement layer with the `Workflow` tool. **HYBRID** in the constructive sense: keep the hooks as the enforcer, and attack the footguns at their real root cause.

### First slice (actionable): pin the diff, key markers to its hash

A refactor of the *existing* dispatch/gate internals — **no workflow adoption, no hook removal, enforcement preserved.**

1. **One canonical diff, computed once.** Introduce a `lib/pin-diff.sh` (or extend the existing `augment-edited-files.sh`) that produces a single explicit changeset for the session: explicit repo root (canonicalized, symlink-resolved), explicit range that unions working-tree + `--cached` + untracked (`ls-files --others --exclude-standard`). This replaces the Edit|Write-tracking + fire-time-augmentation + `git-diff-mode` heuristics as the source of truth for "what changed."
2. **Hash the pinned diff.** The gate's satisfied-check becomes "a review of diff-hash `H` landed in context," where `H` is the content hash of the pinned changeset — not "marker mtime > `edited_files` mtime," and not "marker covers the currently-staged file set."
3. **Hand the pinned diff to the reviewer.** `codex-companion.mjs` / `/lens-review` / `/visual-qa` receive the pinned range explicitly instead of resolving cwd/working-tree state themselves.
4. **Retire the mtime-freshness + staged/untracked/worktree special-cases** that Cluster A footguns live in. Verify each of #3/#4/#5/#6/#8/#9/#13/#14 is closed by construction with a fixture test.

Expected payoff: **8 of 14 footguns closed** (Cluster A), the two-marker freshness dance simplified, worktree/sibling-repo/post-commit blind spots gone — at a fraction of the cost and risk of a topology swap, with enforcement fully intact.

### Optional parallel track (opt-in only): workflow as executor

Where the user opts into orchestration (e.g. `ultracode` / an explicit "run the full review" ask), author a `review-changes` **workflow** that consumes the *same pinned diff* and runs the canonical pattern — dimensions → find → adversarially verify → synthesize — for code-review and visual-qa (both spawn Claude agents, so these fit natively). This is a strictly *better executor* than serial manual dispatch, and it composes with the diff-pinning slice (shared diff input). It is **not** an enforcer and **not** default-on; the hooks still trigger and still cover the forgot-to-run case. Codex stays a direct CLI dispatch — a workflow adds only hops.

### Explicitly rejected
- **Replace codex-stop-gate with a workflow.** Loses cross-provider signal (Claude agents) and enforcement (opt-in + agent-invoked). No.
- **"Advisory workflow auto-fires at Stop."** No such mechanism exists; the opt-in gate forbids a hook from forcing a workflow call. Not buildable on the current contract.

### If GO were ever reconsidered
Only if the `Workflow` tool contract changes to add (a) a hook-invocable Stop-event workflow that runs *without* per-session user opt-in, and (b) a first-class cross-provider agent. Absent both, the enforcement layer stays hooks.

---

## Acceptance criteria — coverage

- **GO/NO-GO/HYBRID brief, in-repo (durable-docs: code-coupled to the plugin gates):** this doc. **NO-GO** on replace, **HYBRID** constructive.
- **Enumerate each gate + map to workflow equivalent / why none:** "What the three gates enforce" + "Mapping" tables. Execution maps (code-review/visual-qa well, codex weakly); enforcement maps for none, and why.
- **Load-bearing property (enforcement at Stop regardless of cooperation) — is the gap acceptable:** "The load-bearing property" section. **Not acceptable to lose** → enforcer stays a hook. Three structural reasons the tool can't provide it.
- **14 footguns — survive / dissolve / newly introduced:** "The 14 footguns, by root cause." Cluster A (8) dissolve via diff-pinning (not via the tool); D (3) only by removing hooks (rejected); B (2)+C (1) survive; the enforcement gap is newly introduced.
- **Concrete recommendation + first slice / clear stop:** diff-pinning first slice (closes 8 footguns, keeps enforcement) + optional opt-in workflow executor; clear stop on replacing the layer.

## References
- Gates (canonical source, this repo): `plugin/hooks/scripts/{codex-stop-gate,codex-pre-commit-gate,pre-commit-gate,visual-qa-stop-gate,dispatch-tracker,codex-bash-tracker,track-edited-files}.sh`, `plugin/hooks/scripts/_lib/stop-gate-emit.sh`, `plugin/hooks/scripts/lib/augment-edited-files.sh`, registered in `plugin/hooks/hooks.json`.
- 14 footguns: `~/.claude/rules/codex-dispatch.md` § "Gate Scope and Known Limitations."
- Dispatch rules the gates enforce: `~/.claude/rules/{codex-dispatch,visual-qa-dispatch,code-review-dispatch}.md`.
- `Workflow` tool contract: Claude Code system prompt (opt-in requirement, JS/no-shell script model, `agent()`/`pipeline()`/`parallel()` primitives, background/turn-scoped invocation).
