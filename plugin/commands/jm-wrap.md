---
effort: high
---

End-of-session cleanup. Run retro (if needed), handle trivial deferreds inline, ticket the non-trivial ones, and leave the repo in a clean state ready for `/clear` or `/exit`.

> Usage: `/jm-wrap`
>
> No arguments. Runs against the current session's state.
>
> Goal: after this command, the user can `/clear` with zero loose ends, no uncommitted work, no stranded worktrees, no forgotten deferreds, no unticketed follow-ups.

## Why this exists

Sessions accumulate "we'll handle that next" residue: throwaway files, half-noted deferreds, abandoned worktrees, mental TODOs that never become tickets. Without an explicit wrap step, that residue compounds across sessions. This command runs the standard wrap-up sequence end-to-end.

## Process

### 1. Retro gate

Decide whether `/jm-retro` needs to run first. It does NOT need to run if:

- A retro already ran earlier in this session (check transcript for the `## What's Next` block)
- The session was a single trivial task (one-line fix, lookup question, doc edit) with no durable lessons

It DOES need to run if:

- Substantive work shipped this session (feature, bug fix, refactor, infra change)
- The user invoked corrections, validated non-obvious choices, or shared new preferences
- New rules / hooks / memory entries would plausibly be worth distilling

If retro is needed: invoke `/jm-retro` and consume its output. The "What's Next" block from § 7 of retro becomes the input to § 3 below.

If retro already ran: scroll back, re-read the "What's Next" block, use it as input.

If no retro is needed: skip to § 3 with an empty deferred list, the only remaining work is the clean-state check in § 4.

### 2. Memory + config audit (already covered by retro)

If retro ran, it already ran the audit. Don't re-run. If you skipped retro, you also skip this, `/jm-wrap` is not a smaller `/jm-retro`.

### 3. Process deferreds and next steps

For every line in retro's "Deferred (optional)" and "Suggested next steps" blocks, classify into one of three buckets. Announce each bucket inline.

| Bucket | Criteria | Action |
|---|---|---|
| **Trivial, execute now** | Safe, reversible, in scope, no user decision needed. Same criteria as retro § 7d "execute, don't list", but in practice retro already executed those; this catches anything retro chose to surface that could in fact be done inline (often because retro was conservative or new info has surfaced since). | Do the work. Re-run any relevant verification. Commit if it produces a diff. |
| **Non-trivial, ticket** | Requires more than 5-10 minutes, crosses files, needs review, or warrants async tracking | Create a tracker issue using whichever issue tracker the project uses (Linear via `mcp__linear__create_issue`, GitHub issues via `gh issue create`, etc.). Ask the user once at session start if the tracker isn't obvious. Title format: clear seed, not `TBD:`: this is a real ticket, not a phone stub. Include context: which session, which PR/commit if relevant, why it's deferred. |
| **Drop** | Was an idea at the time but isn't worth a ticket. Stale, overtaken by other changes, or YAGNI. | Note in the final report that it was considered and dropped, with a one-line reason. |

**Sanity audit before ticketing.** For each candidate ticket, re-run retro's § 7d audit: safe? reversible? in scope? Already done on disk? Actually declared in a source artifact? Don't create tickets for hallucinated work. A ticket created from a wrong premise is worse than no ticket, it propagates the wrong premise into the next session.

**Cap tickets at a reasonable count.** If the deferred list has 10+ candidates, surface that and ask which to ticket vs. drop. Don't dump 12 tickets into the tracker without checking, that's noise, not signal.

### 4. Repo clean-state check

Run, in this order, in the active project root (and any active worktree):

```bash
git status --short                    # any uncommitted work?
git log --oneline @{upstream}..HEAD   # any unpushed commits?
git stash list                        # any forgotten stashes?
```

For each finding:

- **Uncommitted changes:** Diagnose. If they're throwaway debugging residue → delete. If they're real work the user forgot → surface to the user, don't auto-commit. If they're generated files → check `.gitignore` coverage.
- **Unpushed commits:** Push, unless the branch is intentionally local. Surface to the user before pushing if the branch is unusual (not the session's feature branch).
- **Stashes:** Surface. Don't auto-drop. Stashes are usually intentional; the user owns the decision to discard.

### 5. Worktree cleanup

```bash
git worktree list                     # any active worktrees?
```

For each worktree the session created:

- If clean (committed + pushed + PR opened or merged): exit via `ExitWorktree` if it's the current cwd, then `git worktree remove <path>`. If the branch is fully merged into base, delete it.
- If dirty: surface to the user, don't remove. Worktrees with uncommitted work are unfinished, escalate.
- If pre-existing (not created this session): leave alone.

Then prune:

```bash
git worktree prune --verbose
```

This removes administrative entries for worktrees whose directories were deleted but whose metadata lingers.

### 6. Background process check

Are any background jobs from this session still running?

- Background Bash commands (search session for `run_in_background: true` invocations that haven't been monitored)
- Background subagents (Codex dispatches, devil's-advocate, research-agent)
- Long-running watchers (dev servers, file watchers, `gh pr checks --watch`)

For each: either confirm completion (`Monitor` until done) or kill (`KillShell`). Don't leave runaway processes for the next session to discover.

### 7. Final report

Present in chat:

```
## Session wrap

**Trivial executed inline:**
- ...

**Tickets created:**
- <ticket-id> <title>: <one-line context>
- ...

**Dropped (with reason):**
- <idea>: <why>

**Repo state:**
- Branch: <name> @ <SHA>
- Uncommitted: <count> files (or "clean")
- Unpushed: <count> commits (or "clean")
- Worktrees removed: <list>
- Worktrees retained: <list with reason>

**Background processes:**
- All clear (or list anything still running with reason)

**Ready to `/clear` or `/exit`.**
```

If anything blocks a clean wrap, lead with that instead of the "Ready to" line, and state exactly what's holding the wrap open.

## Guardrails

- **Never auto-merge a PR** or push to main. Those are user actions.
- **Never drop a stash** or discard uncommitted work without explicit user confirmation.
- **Never delete a worktree** that has uncommitted changes.
- **Never close tracker tickets** as part of wrap: only create new ones for deferreds.
- **Don't re-run `/jm-retro`** if it already ran this session. Retro is once-per-session by design.
- **Don't create vanity tickets.** A ticket needs a clear acceptance bar, not just "look into this someday." If the deferred is too vague to write 2-3 acceptance criteria for, drop it or surface to the user for refinement instead.
- **Don't substitute wrap for retro.** If retro is needed (per § 1), run retro. Wrap without retro on a substantive session loses the lessons.

## Boundary

`/jm-wrap` runs **after the work is done**: including any PR ping-pong via `/jm-pr`. It is the final step before `/clear` or `/exit`. It does NOT cover:

- Driving open PRs to green: use `/jm-pr` first
- Distilling session lessons: that's `/jm-retro` (which wrap chains into when needed)
- Deploying or promoting code: those are user-triggered (`/deploy` or manual)
