---
effort: medium
---

# /jm-linear-groom

On-demand grooming pass over a Linear workspace. Walks five phases — snapshot, open-tickets report, close-completed sweep, close-stale + stuck sweep, prioritize + estimate — surfacing suggestions and applying writes only with confirmation.

> Usage:
> ```
> /jm-linear-groom              # all five phases, interactive
> /jm-linear-groom --phase=N    # single phase (N = 1..5)
> /jm-linear-groom --read-only  # phases 1+2 only, no writes
> /jm-linear-groom --dry-run    # walk all phases, skip every write, print would-have-done
> /jm-linear-groom --cleanup-labels  # delete groomed:* labels older than 60d
> ```

## Why this exists

Linear workspaces have no built-in housekeeping. Three failure modes accumulate: completed work stays open, stale tickets squat, work-ready tickets lack priority and estimate. This command fixes all three in one pass without ticket-by-ticket discipline burden.

## Workspace config

Fill this in per workspace before invoking. Re-verify team / state / label names via `mcp__linear__list_teams()` + `list_issue_statuses(teamId)` + `list_issue_labels(teamId)` on first run if you're not sure they match — state UUIDs resolve at runtime, so a name mismatch surfaces as an empty state walk (not silent wrong writes), but it's still worth checking once.

```yaml
workspace:
  expected_team: <TeamName>           # e.g. Engineering, Platform, etc.
  expected_id_prefix: <PREFIX>        # e.g. ENG, PLAT — the issue-id prefix Linear assigns
  workspace_url_key: <slug>           # the subdomain piece in https://linear.app/<slug>/
  service_labels: []                  # labels naming services / surfaces in your codebase
  queue_labels: []                    # labels naming triage buckets (misc, personal, etc.)
  work_shape_labels: [bug, feature, improvement, research, idea]
  special_labels: []                  # workspace-specific (e.g. agent-eligible, blocked-external)
  active_states: [Todo, "In Progress", "In Review"]
  open_states: [Backlog, Todo, "In Progress", "In Review"]
  completed_state: Done
  canceled_state: Canceled
  duplicate_state: Duplicate
```

**Prerequisite (one-time):** Linear team estimate field must be enabled with Fibonacci scale (Settings → Estimates). The skill assumes this is already configured — it doesn't probe.

## Process

### 0. Validate workspace routing

Before any read or write:

1. Call `mcp__linear__list_teams()`.
2. Confirm a team matching `expected_team` exists in the result.
3. If not, refuse with: "Current Linear MCP is bound to `<other workspace>`. Switch to the repo whose `.mcp.json` / settings route the Linear MCP to the target workspace, then re-run."

This is the only routing primitive — don't shell out across workspaces.

### 1. Phase 1 — Snapshot (read-only)

Single `list_issues` call per state in `open_states`, plus `Done` and `Canceled` filtered to last 90 days. Compose a one-screen overview:

```text
Workspace: <workspace_url_key> (team: <expected_team>)
Snapshot taken: <ISO timestamp>

Backlog:        <n>
Todo:           <n>
In Progress:    <n>
In Review:      <n>
Done (90d):     <n>
Canceled (90d): <n>

Anomalies:
  • <PREFIX>-N In Progress <d>d (no recent activity)
  • <PREFIX>-N In Review <d>d (stuck)
  • <PREFIX>-N Todo <d>d (untouched)
```

**Anomaly thresholds:**
- `In Progress` > 14d AND no comments since `startedAt`.
- `In Review` > 7d.
- `Todo` > 30d untouched (no `updatedAt` movement).

**Workspace-age phase-skip.** Compute days since the oldest ticket's `createdAt` (proxy for workspace age). If age < a phase's threshold, explicitly announce the skip (e.g. "Phase 4a skipped: workspace 19d old, no candidates >60d") instead of walking an empty filter. Same for Phase 3 / 4b when their target state buckets are all empty — call it out, don't silently no-op.

Anomalies reported only — they flow into phases 2–5 naturally. No writes.

### 2. Phase 2 — Open-tickets report (read-only)

Default render is counts + anomalies, same shape as Phase 1 with explicit per-anomaly lines:

```text
Backlog:        <n>
Todo:           <n>   (<np> with No priority, <ne> without estimate)
In Progress:    <n>   (<s> stuck > 14d)
In Review:      <n>   (<s> stuck > 7d)

Anomalies:
  • <PREFIX>-N In Progress 18d (no recent activity)
  • <PREFIX>-N In Review 12d (stuck)
  • <PREFIX>-N Todo 47d (untouched)
```

User can drill down inline:

- `show todo` / `show in-progress` / `show in-review` / `show backlog` → full table for that state.
- `show <PREFIX>-N` → single-issue detail via `get_issue`.

Full table format when drilled:

```text
=== Todo (7) ===
ID       Title (truncated)                        Age   Updated   Pri      Labels        Est  Blocked
<PREFIX>-184   Hook: announce cross-repo edit scope    0d    today     None     improvement   -    -
<PREFIX>-183   Add /me init skill to bootstrap …       0d    today     Medium   infra,feature 3    -
…
```

Sort: stuck/stale first (highlight), then by `updatedAt` desc. `Blocked` column shows first blocker ID if any.

No writes.

### 3. Phase 3 — Close-completed sweep (writes: → Done)

Walk every ticket in the `active_states` set. For each:

1. Read `gitBranchName` from the ticket.
2. Look for a linked PR via `gh pr list --search "head:<branch>" --state all --json number,state,mergedAt --limit 5`.
3. Also inspect Linear git attachments (`get_issue` `attachments` / `relations`) for explicit PR links — the suggested branch name isn't always the actual branch.
4. If a PR is **merged** OR the branch is deleted upstream, propose `→ Done`.

Render per ticket:

```text
<PREFIX>-N: <title>
  PR: <url> (merged <timestamp>)
  Propose: → Done
  → apply / skip / open  [default: apply]
```

Single keystroke (`a` / `s` / `o`). Default = apply (auto-close on merged-PR signal is requested behavior).

End of phase: `apply all remaining suggestions? [Y/n]`.

If user types `completed: <PREFIX>-N` inline, also propose `→ Done` for that ticket. Don't infer completion from anything else.

**Write call shape:** `save_issue(id="<UUID>", stateId="<Done state UUID>")`. Resolve state UUIDs from the `list_issue_statuses(teamId=...)` cache fetched once at phase start.

### 4. Phase 4 — Close-stale + stuck sweep

Two sub-walks, both per-ticket confirm only (no bulk apply — every action needs judgment).

#### 4a. Stale Backlog / Todo

Filter: `state IN (Backlog, Todo)` AND `updatedAt > 60d ago` AND no comments in the same window AND **no fresh `groomed:YYYY-MM-DD` label** (i.e. no `groomed:` label whose date is within the last 60 days). A fresh groomed label suppresses re-surface; an older groomed label, or no groomed label at all, allows it.

Per ticket prompt:

```text
<PREFIX>-N: <title>
  Backlog, 87d untouched, last comment: never
  → keep / cancel / duplicate-of <PREFIX>-M / open
```

- `keep` → remove any prior `groomed:*` label, add `groomed:<today>` label. No state change, no comment.
- `cancel` → `state="Canceled"`.
- `duplicate-of <PREFIX>-M` → `state="Duplicate"`, `duplicateOf="<PREFIX>-M UUID>"`.

#### 4b. Stuck In Progress / In Review

Filter: `state="In Progress"` AND age > 14d (no comments since `startedAt`); OR `state="In Review"` AND age > 7d.

Per ticket prompt:

```text
<PREFIX>-N: <title>
  In Progress, 18d, no activity since 2026-04-26
  → still-working / back-to-todo / back-to-backlog / cancel / open
```

- `still-working` → add `groomed:<today>` label (suppresses re-surface).
- `back-to-todo` → `state="Todo"`.
- `back-to-backlog` → `state="Backlog"`.
- `cancel` → `state="Canceled"`.

### `groomed:*` label lifecycle

- One label per date: `groomed:2026-05-14`, `groomed:2026-05-21`, …
- On apply, remove any prior `groomed:*` label, add the new one. Net per-ticket count: 1.
- Filter next-pass: `list_issues` with label query `groomed:`, parse the date suffix on each label, and treat a label as **fresh** if its date is `>= today - 60d` (i.e. within the last 60 days). Fresh labels suppress re-surface in Phase 4; stale labels (older than 60 days) do not.
- **Preserve pre-existing labels.** `save_issue(labels=[...])` replaces the full set, so read current labels via `get_issue`, mutate, write back. Never blindly send a new label list.

### 5. Phase 5 — Prioritize + estimate (writes: priority + estimate)

Walk `Todo` tickets only. Skip Backlog (triage is separate), skip In Progress / In Review (already prioritized by virtue of pickup).

**Partition before walking.** If Todo has 30+ tickets, group them by label (`bug` / `feature` / `improvement` / `research` vs `idea` / `personal` queue-dump). Offer to bulk-move queue-dump (`idea` / `personal` / `media`) tickets to Backlog before per-ticket walk — these are Life Queue items mistakenly sitting in Todo (common after Trilium migration). Bulk Todo→Backlog is permitted (the reverse Backlog→Todo is gated by promote-tbd; this direction is not). After the partition, Phase 5 walks only the remaining work-shape tickets.

**Bulk-confirm matrix.** For >15 remaining tickets, present the priority+estimate suggestions as a single table and apply via one bulk-confirm rather than per-ticket prompts. The runbook's per-ticket prompt format is the fallback for small batches or when individual rationale matters.

**Estimate rubric** (render once at phase start, reference "see rubric above" on subsequent prompts):

| Value | Shape | Examples |
|---|---|---|
| **1** | Agent one-shot. Single file, mechanical. <30min agent time. | Rename function, typo fix, missing label, single-line config tweak. |
| **3** | Bounded agent task. Multi-file but scoped. ~1–2 agent iterations. | New endpoint, refactor a module, new label workflow. |
| **5** | Human-in-loop. Multi-component, agent assists not drives. | Cross-service feature, non-trivial refactor, integration. |
| **8** | Research / architecture. Probably should split. | New service, schema redesign, vendor eval. Decompose if stays 8 after one triage pass. |

**Blocked-ticket handling.** For each ticket, call `get_issue(id, includeRelations=true)` and read the `blockedBy` relation.

- **No blockers** → run normal suggestion flow.
- **Blocked by open ticket** → don't prompt priority on the blocked ticket. Surface the chain inline and offer to jump-prioritize the blocker:

  ```text
  <PREFIX>-100 (blocked) — chain: <PREFIX>-100 ← <PREFIX>-099 ← <PREFIX>-080 (Todo, No priority, est=null)
    Re-prioritize blocker <PREFIX>-080 instead? [y/skip]
  ```

  Accept → recurse the suggestion flow on the blocker (one level of blocker recursion max). Skip → next ticket.
- **Blocked by closed ticket (Done/Canceled)** → treat as unblocked but flag the stale relation in the per-ticket render for later cleanup.

**Priority heuristic** (for unblocked tickets):

- `bug` label AND `createdAt < 7d` → suggest `High` (2).
- `bug` label, older → suggest `Medium` (3).
- `feature` or `improvement` AND No-priority → suggest `Medium` (3).
- `idea` AND `updatedAt > 30d` → suggest `Low` (4).
- Anything else with No-priority → suggest `Medium` (3) (No-priority on Todo is a smell).
- Ticket already has a priority that disagrees → surface both, let user pick.

**Estimate heuristic:**

- `estimate=null` → ask inline (1/3/5/8 rubric).
- Already set → skip unless user types `re-estimate <PREFIX>-N`.

Per-ticket prompt (unchanged suggestion):

```text
<PREFIX>-N: <title>
  Current:    priority=Medium, estimate=3
  Suggestion: priority=Medium (unchanged), estimate=3 (unchanged)
  → keep / change / open
```

Per-ticket prompt (new suggestion + missing estimate):

```text
<PREFIX>-N: <title>
  Current:    priority=None, estimate=null
  Suggestion: priority=Medium (no-priority on Todo smells), estimate=?
  Pick estimate [1/3/5/8]: _
  → apply / skip / open
```

**8-estimate decomposition nudge:** if user picks 8, warn: "Estimate 8 means this should probably split into 2–3 smaller tickets. File the split or accept anyway?" Default = accept. Not a block.

End of phase: `apply all confirmed changes? [Y/n]`. One ticket = one `save_issue` call carrying both fields if both changed.

## Pagination

`list_issues` paginates at 250/page. Loop the `cursor` until exhausted — don't assume single-page.

## Confirmation UX

- Single-ticket: `a` (apply) / `s` (skip) / `o` (open in browser) / `q` (quit phase). Default = `a` for Phase 3, no default for Phase 4 sub-walks, `a` for Phase 5 when suggestion is "unchanged".
- Bulk end-of-phase: `apply all remaining? [Y/n]` (Phase 3 and Phase 5 only — Phase 4 has no bulk path).
- Quit at any time persists writes already applied (no rollback). On exit, print: `Applied N changes, skipped M, deferred K.`

## Audit log

Append one JSON line per write to `~/.claude/logs/linear-groom.jsonl` (create the directory on first run if missing). Use the configured `workspace_url_key` so multi-workspace logs are distinguishable:

```json
{"ts":"<ISO timestamp>","workspace":"<workspace_url_key>","ticket":"<PREFIX>-N","change":{"priority":[null,3],"estimate":[null,3]}}
```

For state transitions:

```json
{"ts":"...","workspace":"<workspace_url_key>","ticket":"<PREFIX>-N","change":{"state":["In Review","Done"]}}
```

For label edits in Phase 4:

```json
{"ts":"...","workspace":"<workspace_url_key>","ticket":"<PREFIX>-N","change":{"labels_added":["groomed:2026-05-14"],"labels_removed":["groomed:2026-03-12"]}}
```

Keep the audit trail in `~/.claude/logs/` — it's session state, not user-context.

## Flags reference

- `--phase=N` (1..5): run only that phase.
- `--read-only`: phases 1+2 only, refuse any write.
- `--dry-run`: walk all five phases, render every suggestion, but skip every `save_issue` call. Print `would-have-done: <call>` instead.
- `--cleanup-labels`: list all **stale** `groomed:*` labels (date older than 60 days — i.e. labels that no longer suppress re-surface), confirm bulk-delete via `mcp__linear__*` label deletion (manual fallback: open Linear settings if MCP doesn't expose label-delete).

## Don't

- Don't create tickets — that's a separate workflow.
- Don't transition `Backlog → Todo` — that's a structural-gate-validated promotion job, not a grooming concern. (Reverse, Todo → Backlog, is permitted in Phase 5 partition for queue-dump items.)
- Don't write to projects, cycles, milestones.
- Don't run on a recurring schedule — on-demand only.
- Don't auto-close tickets the user typed "completed: <PREFIX>-N" for without confirming the user actually meant the current ticket (echo the title back before applying).
- Don't infer completion from anything other than a merged PR or explicit user statement.

## Quick reference — Linear MCP calls used

- `mcp__linear__list_teams()` — workspace validation.
- `mcp__linear__list_issue_statuses(teamId)` — resolve state UUIDs (Done, Canceled, Duplicate, Todo, Backlog).
- `mcp__linear__list_issues(teamId, stateId?, labelIds?, includeArchived=false, after?)` — per-state walks. Loop `after` cursor.
- `mcp__linear__get_issue(id, includeRelations=true)` — Phase 5 blocker chain, current labels read-modify-write.
- `mcp__linear__list_comments(issueId)` — Phase 1+4 staleness check.
- `mcp__linear__save_issue(id, stateId?, priority?, estimate?, labelIds?, duplicateOf?)` — all writes.
- `mcp__linear__list_issue_labels(teamId)` — `groomed:*` lifecycle, cleanup-labels flag.
