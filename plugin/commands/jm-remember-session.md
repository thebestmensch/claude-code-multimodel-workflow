---
effort: high
---

Distil this session's durable lessons into standing instructions and push memory off-machine, then — only when real loose ends are detected — close out the session cleanly.

> Usage: `/jm-remember-session`
>
> No arguments. Runs against the current session's state.
>
> **Mode-less by construction.** The memory writeback (Part A) always runs — identical mid-session and end-of-session, idempotent, safe before every `/compact`. The session-close tail (Part C) fires only when Part B *detects* real residue (uncommitted work, worktrees, background jobs, real transcript-derived deferreds). Nothing detected → the command stops after memory with a clean report. There is **no mode flag and no "wrapping or continuing?" ask** — the command decides from detected state alone.
>
> This replaces the former `/jm-retro` + `/jm-wrap` + `/jm-precompact` trio. Those three were the same memory writeback at three timing-collars; the fork existed only because retro's old "What's Next" block *manufactured* speculative deferreds mid-session. Part B designs that bug out: it reads real state instead of inventing next-steps, so one command is safe at every point in a session.

## Why this exists

`/compact` and `/exit` both destroy the raw transcript. Lessons that haven't been routed to standing instructions or committed to a memory repo by then are lost — paraphrased at best, dropped at worst. And sessions accumulate "we'll handle that next" residue: throwaway files, half-noted deferreds, abandoned worktrees, mental TODOs that never become tickets. This command locks in the lessons every time, and clears the residue when there is any.

**The load-bearing invariant:** mid-session runs must never ticket deferreds or emit speculative unfinished-work state. Part B reads `git status` / `git worktree list` / background jobs — you cannot hallucinate a worktree that isn't there. A clean mid-session tree yields an empty detection and a memory-only report.

## Process

---

# Part A — Memory writeback *(ALWAYS runs)*

### A1. Self-Reflection *(chat only: do not persist)*

1. Review every turn from the session's first user message
2. Produce **≤ 10** bullet points covering:
   - Behaviours that worked well
   - Behaviours the user corrected or expected differently
   - Actionable, transferable lessons
   - Skill iterations: any skill whose output you corrected *durably* this session, or skill file you edited by hand
3. Do **not** write these bullets to any file

### A2. Classify & Route Updates

For each lesson, decide where it belongs:

| Destination | When to Use | File |
|-------------|-------------|------|
| **Hook** | Behavior that got skipped despite existing rules, enforcement > advice | Your hooks dir + `settings.json` |
| Project instructions | Applies to this codebase specifically | `CLAUDE.md` (root or subdir) |
| **User context** | Fact about the **user as a person**: identity, voice, taste, work preference, life context | Your user-context memory dir, if configured |
| Cross-project ops memory | Harness behavior, hook quirk, tool footgun, CLI gotcha, **about the tooling, not the user** | Your global-ops memory dir, if configured |
| Project ops memory | Specific to one codebase's services, patterns, footguns | Project-specific memory dir, if configured |
| Slash command | Improves an existing workflow command | `.claude/commands/*.md` |
| Nowhere | Too session-specific or already covered | — |

**Hook-first principle:** If a lesson addresses a behavior that was *corrected* (not just learned), ask: "Did a rule already exist that should have prevented this?" If yes, the fix is a hook that blocks completion, not another rule. Memory rules don't survive momentum, hooks do.

**Shape gate before any memory write.** Before routing to a user-context memory dir, ask out loud (in thinking):

> "Is this a fact about **the user as a person** (identity, voice, taste, work-preference, life-context), or about **the harness/tools** (codex, hooks, CLI quirks, file-locking, daemon behavior)?"

- If **person** → user-context dir is correct.
- If **tooling** → it does NOT belong in the user-context dir regardless of how cross-cutting it feels. Route to a cross-project ops memory dir or project memory dir.

**Why this gate exists:** the harness `autoMemoryDirectory` setting funnels every auto-save into one location regardless of shape. Without an explicit shape gate, harness-ops content silently accumulates in the identity dir and dilutes its purpose ("who is this user, how do they sound, what do they like").

**Skill iterations.** If you invoked a skill this session and corrected its output in a way that should hold for *every* future run, or you hand-edited a skill file, fold that into the skill's source of truth (which is not always the skill body — a voice skill may read from a separate voice doc). Trivial + reversible → fold inline and commit. Non-trivial (restructures the skill, spans multiple, needs a judgment call) → carry to Part C's ticketing on a session-close run, or surface as a note in the Part D report mid-session. Promote behavior changes, not one-off outputs.

### A3. Update Rules

For each routed lesson:

**a. Generalise**: Strip session-specific details. Formulate as a reusable principle.

**b. Integrate**: - If a matching rule exists → refine it in place
  - If new → add to the appropriate section
  - If contradicts existing → replace with the updated version

**c. Quality requirements:**
  - Imperative voice: "Always …", "Never …", "If X then Y"
  - Concise: no verbosity or overlap
  - Organised: respect existing file structure and grouping

### A4. Structural Hygiene

- Deduplicate: merge overlapping guidance into a single canonical rule
- Tighten: rewrite verbose rules without losing intent
- Audit length: if CLAUDE.md or MEMORY.md is getting long, propose splits

### A5. Memory & Config Audit + backup commit

**This is the load-bearing step for pre-`/compact` runs.** Lessons routed to memory files but not yet committed are still only in a working tree; they survive compaction. Lessons that exist only in the transcript do not. The exact dirs depend on how the user configured their memory plumbing; adapt the checks to whatever auto-loaded memory paths exist.

**Memory files:**
- Any memory file > 40 lines? → propose splitting into topic-specific files with precise descriptions. Prefer 2-way splits unless the content has 3+ truly orthogonal sections.
- Any memory content duplicated in CLAUDE.md? → remove from CLAUDE.md (memory is selective; CLAUDE.md loads unconditionally)
- Any stale memories referencing files/functions that no longer exist? → flag for removal
- Any `project_*` memory file unmodified for >60 days? → flag for re-validation. Skip `feedback_*` and `reference_*`: those are durable by design.
- Is the MEMORY.md index still accurate after any splits/renames? → update pointers
- **After any split/rename**, sweep for orphan references to the old filename: `grep -rn "<old-stem>" <memory-dir>/` — sibling files cross-link by name and rot silently on rename.
- **Shape audit across auto-loaded memory dirs.** Each dir typically has a defined shape (user-context vs cross-project ops vs project-specific). Audit for cross-contamination; misfits dilute scope and waste session context.

**Settings (`~/.claude/settings.json` and equivalents):**
- Permissions: any redundant patterns that could be consolidated? (e.g. 10 `git` subcommands → `Bash(git *)`)
- Plugins: any enabled plugins not used this session or recently? → suggest disabling
- MCP servers: any broken/unused servers adding tool overhead? → suggest disabling

**Hooks:**
- Did any existing hook fail to catch a mistake this session? → check matcher patterns, file path globs
- Did I skip a process step despite knowing better? → that's a hook candidate, not a memory update
- Any hooks with overly narrow scope that should be generalized? → widen patterns

**Memory backup commit.** If memory entries were added or modified this session AND the memory dir is a git repo, commit + push the affected memory dir now. Each memory dir is typically the only off-machine recovery path — dotfile managers track config, not state, so memory needs its own backup path. If a memory dir lacks a `.git/` and the user would benefit from backup, surface that and offer to set one up.

**Sweep for orphan entries before committing.** Run `git status --short` in each memory dir before staging. If untracked `feedback_*.md` / `reference_*.md` / `project_*.md` files exist that ARE indexed in `MEMORY.md` (or its split siblings) but were never pushed (residue from an interrupted prior session), include them in this backup commit. Indexed-but-unpushed orphans are the worst of both — the index references a file that doesn't exist on origin, so a fresh clone gets a broken `[[link]]`.

**Committing memory here is mandatory if any memory file was touched** — this is the whole point of a pre-`/compact` run. Don't report "ready" with uncommitted memory entries.

---

# Part B — Detect real state *(ALWAYS runs — replaces the old speculative "What's Next")*

Read real loose ends. **Never invent next-steps; never ticket here.** This is the step that makes the command mode-less: the difference between "mid-session" and "end-of-session" is simply whether this detection *finds* anything, not a flag.

Run, in the active project root (and any active worktree):

```bash
git status --short                    # uncommitted work?
git rev-parse --abbrev-ref @{upstream} >/dev/null 2>&1 \
  && git log --oneline @{upstream}..HEAD \
  || echo "[no upstream configured]"  # unpushed commits? (guard: skip on detached HEAD / no upstream)
git stash list                        # forgotten stashes?
git worktree list                     # active worktrees?
```

Plus:
- **Background jobs** — search this session for `run_in_background: true` Bash invocations not yet monitored, background subagents (Codex, devil's-advocate, research-agent), long-running watchers (dev servers, `gh pr checks --watch`).
- **Real transcript-derived deferreds** — work the *user explicitly deferred* this session ("we'll do that later", "save that for next time"), or tasks you created but didn't mark complete (TaskList state). NOT free-associated "we could also do X" — only what actually came up while doing the session's work.

**The invariant:** if this detection comes back empty (clean tree, no bg jobs, no explicit deferreds), Part C is **skipped silently** and Part D reports a clean memory-only run. Do NOT manufacture a "Deferred" or "Suggested next steps" block to fill the space — that speculation is exactly the bug this design removes. An empty plate is a valid, common result (every mid-session `/compact`).

---

# Part C — Session-close tail *(runs ONLY when Part B detected real residue)*

Skip this entire part — silently — when Part B found nothing. When it did, work the sub-steps below. Surface irreversible actions for confirmation (never auto-drop a stash, auto-remove the cwd worktree, or auto-merge a PR).

### C1. Process deferreds

For every real deferred surfaced in Part B, classify into one of three buckets. Announce each inline.

**Session-scope filter (apply BEFORE bucketing).** A deferred only earns a bucket if it traces to *this* session's work. Drop (don't ticket, don't execute) any candidate that:
- References a file or surface this session never touched — no Read/Edit/Write, no Bash command that named it (grep, git, tests, linters), no commit authored this session.
- Restates a pre-existing `TODO`/`FIXME` that `git blame` shows was not authored this session.
- Belongs to a parallel session's branch / worktree / PR this session didn't touch.
- Is a free-associated "we should also do X" idea that didn't come up while doing this session's actual work.

Surface filtered items under "Dropped" with a one-line reason; don't ticket them.

| Bucket | Criteria | Action |
|---|---|---|
| **Trivial, execute now** | Safe, reversible, in scope, no user decision needed | Do the work. Re-run any relevant verification. Commit if it produces a diff. |
| **Non-trivial, ticket** | >5-10 min, crosses files, needs review, or warrants async tracking | Create a tracker issue using whichever issue tracker the project uses (Linear via `mcp__linear__create_issue`, GitHub issues via `gh issue create`, etc.). Ask the user once at session start if the tracker isn't obvious. Title = clear seed, not `TBD:`. Include context: which session, which PR/commit, why deferred. |
| **Drop** | Idea at the time, not worth a ticket. Stale / overtaken / YAGNI. | Note in the report that it was considered and dropped, one-line reason. |

**Sanity audit before ticketing.** For each candidate: safe? reversible? in scope? Already done on disk? Actually declared in a source artifact (verify against the real PR body / ticket / plan doc, not summary-recall)? Don't create tickets for hallucinated work — a ticket from a wrong premise is worse than no ticket.

**Cap tickets.** If the deferred list has 10+ candidates, surface that and ask which to ticket vs. drop.

**Execute-don't-list, when safe.** If a deferred is safe + reversible + in scope + needs no user decision → just do it (delete throwaway files, update a command doc with a session lesson, re-run a verification query). Only *list* items that genuinely need user input or are out of scope (deploys, anything user-visible, domain-judgment calls, anything that modifies another user's state).

Any non-trivial skill iteration carried from A1 → ticket it here per the non-trivial bucket.

### C2. Repo clean-state handling

For each Part B git finding:
- **Uncommitted changes:** Diagnose. Throwaway debugging residue → delete. Real work the user forgot → surface, don't auto-commit. Generated files → check `.gitignore`.
- **Unpushed commits:** Push, unless the branch is intentionally local. Surface before pushing if the branch is unusual.
- **Stashes:** Surface. Don't auto-drop. The user owns the decision to discard.

### C3. Worktree cleanup

For each worktree the session created:
- **Clean (committed + pushed + PR opened or merged):** if it's the current cwd, exit via `ExitWorktree` first, then `git worktree remove <path>`. If the branch is fully merged into base, delete it. Do NOT remove the cwd worktree from inside it without exiting first — removing the cwd mid-session leaves subsequent hooks/commands spawning into a dead directory.
- **Dirty:** surface, don't remove. Escalate.
- **Pre-existing (not created this session):** leave alone.

Then prune: `git worktree prune --verbose` (clears administrative entries for worktrees whose directories were deleted but whose metadata lingers).

### C4. Background process check

For each still-running background job from Part B: either confirm completion (`Monitor` until done) or kill (`KillShell`). Don't leave runaway processes for the next session.

---

# Part D — Report

### D1. Memory-only run (Part B found nothing session-introduced)

Present in chat:
- Session summary: 2-3 sentences on what was accomplished so far
- `✅ Rules updated` or `ℹ️ No updates needed`
- The self-reflection bullets from A1
- Summary of what changed and where
- Memory/config audit findings from A5
- Memory commit SHAs (per dir) so off-machine state is verifiable
- Any non-trivial skill iteration as a one-line **note** (NOT ticketed — mid-session)

End with:
```text
Memory locked in — clean tree, nothing to close. Ready to /compact or keep working.
```

### D2. Session-close run (Part C ran)

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
- **Mid-session must never ticket deferreds or emit speculative unfinished-work state.** Part B reads real state; Part C only runs on detected residue. If you're drafting an "Unfinished / Deferred" block on a clean tree, stop — that's the removed-by-design bug.
- **Don't create vanity tickets.** A ticket needs a clear acceptance bar, not just "look into this someday." Too vague to write 2-3 acceptance criteria → drop or surface for refinement.
- **Do NOT invoke `/compact` yourself** — it's a built-in CC command, not model-invocable. The user runs it after this command finishes.
- **Verify before memorializing.** Any memory entry that makes a factual claim about system behavior (e.g. "X fires on Y", "ref A is reachable from B") MUST be verified by running the relevant command before commit. Truncated console output and "I think I saw this" are not sources. This command is the most dangerous place for unverified claims — they get cemented as durable rules. Can't verify now → surface as a question to the user instead of writing it.

## Boundary

`/jm-remember-session` runs the memory writeback at any point (mid-session before `/compact`, or at session end) and closes out the session when real loose ends exist. It runs **after the work is done** — including any PR ping-pong via `/jm-pr`. It does NOT cover:

- Driving open PRs to green → `/jm-pr` first
- Deploying or promoting code → user-triggered
- Actually running compaction → the user types `/compact`
