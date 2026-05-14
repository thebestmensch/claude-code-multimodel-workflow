---
effort: high
---

Reflect on this session and fold durable lessons into standing instructions, then surface what comes next.

> Invoke after a work session concludes. Distils lessons into reusable rules, surfaces unfinished work, and proposes next steps.

## Process

### 1. Self-Reflection *(chat only — do not persist)*

1. Review every turn from the session's first user message
2. Produce **≤ 10** bullet points covering:
   - Behaviours that worked well
   - Behaviours the user corrected or expected differently
   - Actionable, transferable lessons
3. Do **not** write these bullets to any file

### 2. Classify & Route Updates

For each lesson, decide where it belongs:

| Destination | When to Use | File |
|-------------|-------------|------|
| **Hook** | Behavior that got skipped despite existing rules — enforcement > advice | Your hooks dir + `settings.json` |
| Project instructions | Applies to this codebase specifically | `CLAUDE.md` (root or subdir) |
| **User context** | Fact about the **user as a person** — identity, voice, taste, work preference, life context | Your user-context memory dir, if configured |
| Cross-project ops memory | Harness behavior, hook quirk, tool footgun, CLI gotcha — **about the tooling, not the user** | Your global-ops memory dir, if configured |
| Project ops memory | Specific to one codebase's services, patterns, footguns | Project-specific memory dir, if configured |
| Slash command | Improves an existing workflow command | `.claude/commands/*.md` |
| Nowhere | Too session-specific or already covered | — |

**Hook-first principle:** If a lesson addresses a behavior that was *corrected* (not just learned), ask: "Did a rule already exist that should have prevented this?" If yes, the fix is a hook that blocks completion, not another rule. Memory rules don't survive momentum — hooks do.

**Shape gate before any memory write.** Before routing to a user-context memory dir, ask out loud (in thinking):

> "Is this a fact about **the user as a person** (identity, voice, taste, work-preference, life-context), or about **the harness/tools** (codex, hooks, CLI quirks, file-locking, daemon behavior)?"

- If **person** → user-context dir is correct.
- If **tooling** → it does NOT belong in the user-context dir regardless of how cross-cutting it feels. Route to a cross-project ops memory dir or project memory dir.

**Why this gate exists:** the harness `autoMemoryDirectory` setting funnels every auto-save into one location regardless of shape. Without an explicit shape gate at retro time, harness-ops content silently accumulates in the identity dir and dilutes its purpose ("who is this user, how do they sound, what do they like").

### 3. Update Rules

For each routed lesson:

**a. Generalise** — Strip session-specific details. Formulate as a reusable principle.

**b. Integrate** —
  - If a matching rule exists → refine it in place
  - If new → add to the appropriate section
  - If contradicts existing → replace with the updated version

**c. Quality requirements:**
  - Imperative voice — "Always …", "Never …", "If X then Y"
  - Concise — no verbosity or overlap
  - Organised — respect existing file structure and grouping

### 4. Structural Hygiene

- Deduplicate: merge overlapping guidance into a single canonical rule
- Tighten: rewrite verbose rules without losing intent
- Audit length: if CLAUDE.md or MEMORY.md is getting long, propose splits

### 5. Memory & Config Audit

Run a quick health check on the setup. The exact dirs depend on how the user configured their memory plumbing — adapt the checks below to whatever auto-loaded memory paths exist.

**Memory files:**
- Any memory file > 40 lines? → propose splitting into topic-specific files with precise descriptions. Prefer 2-way splits unless the content has 3+ truly orthogonal sections — every new file inflates MEMORY.md and multiplies cross-references.
- Any memory content duplicated in CLAUDE.md? → remove from CLAUDE.md (memory is selective; CLAUDE.md loads unconditionally)
- Any stale memories referencing files/functions that no longer exist? → flag for removal
- Any `project_*` memory file unmodified for >60 days? → flag for re-validation ("Is this still live, or has the situation resolved?"). Skip `feedback_*` and `reference_*` — those are durable by design.
- Is MEMORY.md index still accurate after any splits/renames? → update pointers
- **After any split/rename**, sweep for orphan references to the old filename: `grep -rn "<old-stem>" <memory-dir>/` — sibling memory files often cross-link by name and will rot silently when one gets renamed.
- **Shape audit across auto-loaded memory dirs.** Each memory dir typically has a defined shape (user-context vs cross-project ops vs project-specific). Audit for cross-contamination — misfits dilute scope and waste session context. If the user has multiple memory dirs, run a quick `grep` for project-specific service names in the user-context dir, or vice versa, and surface mismatches.

**Settings (`~/.claude/settings.json` and equivalents):**
- Permissions: any redundant patterns that could be consolidated? (e.g. 10 `git` subcommands → `Bash(git *)`)
- Plugins: any enabled plugins not used this session or recently? → suggest disabling
- MCP servers: any broken/unused servers adding tool overhead? → suggest disabling

**Hooks:**
- Did any existing hook fail to catch a mistake this session? → check matcher patterns, file path globs
- Did I skip a process step despite knowing better? → that's a hook candidate, not a memory update
- Any hooks with overly narrow scope that should be generalized? → widen patterns

**Memory backup commit:**
If memory entries were added or modified this session AND the memory dir is a git repo, commit + push the affected memory dir as part of the retro. Each memory dir is typically the only off-machine recovery path (dotfile managers like chezmoi do NOT track memory — it's state, not config).

If a memory dir lacks a `.git/` and the user would benefit from backup, surface that and offer to set one up.

**Sweep for orphan entries before committing.** Run `git status --short` in each memory dir before staging. If untracked `feedback_*.md` / `reference_*.md` / `project_*.md` files exist that ARE indexed in `MEMORY.md` (or its split siblings) but were never pushed (residue from prior sessions whose retro got interrupted), include them in this retro's backup commit. Indexed-but-unpushed orphans are the worst-of-both: the index references a file that doesn't exist on origin, so anyone who clones the repo gets a broken `[[link]]` and a dangling pointer.

### 6. Report

Present in chat:
- Session summary: 2-3 sentences on what was accomplished
- `✅ Rules updated` or `ℹ️ No updates needed`
- The self-reflection bullets from § 1
- Summary of what changed and where
- Memory/config audit findings from § 5

### 7. What's Next?

After presenting the report, proactively answer "What's next?" as if the user asked:

**a. Surface unfinished work:**

**Scope strictly to the live operator's pending work** — what THIS session (you + the user at the terminal) still owes. Do NOT list:
- Backgrounded agent sessions you dispatched (`claude --bg`, headless agents) — those are *other sessions* running asynchronously.
- Child agent runs that already finished within this session — completed work isn't unfinished.
- Open PRs from earlier this session that are simply awaiting CodeRabbit / human review — those aren't *your* unfinished work, they're the reviewer's pending action.

What DOES belong here:
- Tasks you created but didn't mark complete (TaskList state)
- Work the user explicitly deferred ("we'll do that later", "save that for next time")
- Blockers that need user action *from you, the live operator* (auth, external tools, decisions)

If you genuinely need to surface "things that are in-flight but not yours to act on" (e.g. 4 bg agents working), put them in a separate **Background context** block AFTER "Suggested next steps", not in "Unfinished". The unfinished list is the live operator's plate, not a session-wide async status board.

**b. Capture deferred improvements:**
- Technical debt spotted but not addressed
- Refactors mentioned but skipped
- "Nice to have" items that came up

**c. Propose logical next steps:**
- If feature work: what's the natural continuation?
- If debugging: are there related areas to audit?
- If refactoring: are there siblings to update?

**d. Audit each candidate before listing it.** For every item you're about to put under "Deferred (optional)" or "Suggested next steps", run this check:
- Is the action **safe** (can't cause data loss or user-visible impact)?
- Is it **reversible**, including impact? Edit-reversibility (git revert works) ≠ impact-reversibility — a config removal can silently break a downstream workflow with no Slack alert until the next nightly run. If the safety judgment depends on facts you haven't checked (which workflows use `require()`, which callers consume the flag), the dependency audit must happen before listing — don't list "drop the stale X flag" without first verifying nothing live depends on it.
- Is it **in scope** (within the concern of the session that just ended)?
- Does the user **need to decide anything** first (credentials, preferences, strategy)?
- **Is it already done?** Verify on disk before listing. A ticket marked Todo doesn't mean the work isn't done — check artifacts (config files committed, app installed, endpoint reachable). Re-recommending completed work wastes the user's time and erodes trust in the retro.
- **Was it actually declared in the source artifact?** Verify against the original PR body / ticket / plan doc, not against summary-recall from a prior retro. Retro "Deferred" lines get treated as authoritative by the next session, so a hallucinated continuation item ("PR #X listed these follow-up adopters") propagates forward as fact. Open the actual artifact (`git log --format=%B -n 1 <sha>` for squash commits, `gh issue view`, `cat plans/<file>.md`) and confirm the item is there. If not, drop it or restate as "candidate for future work" without claiming pedigree.

**Hard rule:** if all three "safes" are yes and the user has no decision to make → you MUST execute the action inline before writing the "What's Next" block, then report it under "What changed." Listing such an item instead is a failure mode of this command — the user shouldn't have to re-ask for something you already judged safe + reversible + in-scope. The audit is mandatory, not advisory.

If you find yourself drafting a "Deferred (optional)" line, stop and answer the four questions out loud (or in thinking) for that line before continuing. Only items that genuinely need user input or are out of scope survive into the list.

Examples of "execute, don't list":
- Delete `.gitignored` throwaway files after reconciled import
- Update a command/skill doc with a lesson from the session
- Remove a temp file created during debugging
- Re-run a verification query to confirm final state
- Bump `package.json` / version metadata after shipping a feature build (so the next packaged artifact doesn't filename-collide with the prior one)

Examples of "list, don't execute":
- Deploying code to staging/prod (user-visible)
- Running OTA updates (user-visible, explicit feedback rule)
- Decisions requiring domain judgment (which feature to build next)
- Anything that modifies another user's state (PRs, messages, releases)

**e. Format:**
```
## What's Next

**Unfinished:**
- [ ] ...

**Deferred (optional):**
- ...

**Suggested next steps:**
1. ...
```

If nothing is unfinished and no obvious next steps exist, say so: "Session wrapped cleanly — no pending items."

## Guardrails

- Do **not** create new documentation files unless explicitly asked
- Do **not** persist session logs, task details, or project-specific trivia
- If a change is safe, reversible, and within scope — execute it. Do not ask for permission.
- Memory files: check for existing entries before adding new ones. Update > duplicate.
- Hooks: creating enforcement hooks is encouraged when a rule was violated — propose the hook, explain what it blocks, then create it.
- **Verify before memorializing.** Any memory entry that makes a factual claim about system behavior (e.g. "X fires on Y", "the hook does/doesn't run on Z", "ref A is reachable from B") MUST be verified by running the relevant command before the entry gets committed. Truncated console output, scrolled-off pytest runs, and "I think I saw this" are not sources. The retro itself is the most dangerous place for unverified claims because they get cemented as durable rules. If you can't verify a claim now, surface it as a question to the user instead of writing it.
