---
effort: high
---

Pre-compaction retro. Distill lessons and commit memory **before** running `/compact` so durable rules survive the summarization pass.

> Usage: `/jm-precompact`
>
> No arguments. Runs against the current session.
>
> Goal: when the context window is filling and `/compact` is imminent, lock in lessons + push memory off-machine **before** the raw transcript gets paraphrased into a summary.

## Why this exists

`/compact` replaces the raw conversation history with a model-written summary. Lessons that haven't been routed to standing instructions or committed to a memory repo at compaction time are lost. The summarizer paraphrases them at best, drops them at worst. `/jm-retro` is the right body of work, but its § 7 "What's Next" block assumes the session is ending; mid-session it manufactures hallucinated "Unfinished / Deferred" items that survive compaction as authoritative state. This command runs the retro body without the end-of-session framing.

Not the same as `/jm-wrap`. Wrap handles worktrees, background processes, ticketing deferreds. None of that applies mid-session.

## Process

Run the same self-reflection + routing + rule-update + memory audit + commit flow as `/jm-retro`, **stopping at § 6 (Report)**. Skip § 7 entirely.

### 1. Self-Reflection *(chat only, do not persist)*

Follow `/jm-retro` § 1.

### 2. Classify & Route Updates

Follow `/jm-retro` § 2. Same shape-gate, same auto-load caveat.

### 3. Update Rules

Follow `/jm-retro` § 3.

### 4. Structural Hygiene

Follow `/jm-retro` § 4.

### 5. Memory & Config Audit

Follow `/jm-retro` § 5, including the memory backup commit. **This is the load-bearing step for pre-compact.** Lessons routed to memory files but not yet pushed are still in the working tree of a memory dir; they survive compaction. Lessons that exist only in the conversation transcript do not.

If a memory dir has uncommitted writes from this session, commit + push them before reporting. Skipping the commit here defeats the purpose of running this command.

### 6. Report

Present in chat:
- Session summary: 2-3 sentences on what was accomplished so far
- `✅ Rules updated` or `ℹ️ No updates needed`
- The self-reflection bullets from § 1
- Summary of what changed and where
- Memory/config audit findings from § 5
- Memory commit SHAs (per dir) so the user can verify off-machine state

End the report with:

```text
Ready to compact. Run `/compact` when you want to continue with a fresh window.
```

### 7. Do NOT run "What's Next"

Explicitly skipped. The session is not ending. Unfinished work is still live in the upcoming post-compact context; listing it here as "Deferred" risks the summarizer treating those bullets as authoritative future-session inputs.

If you find yourself drafting an "Unfinished" or "Deferred" block, stop. That's `/jm-retro` / `/jm-wrap` territory, not this command.

## Guardrails

- Do **not** invoke `/compact` yourself; `/compact` is a built-in CC command and is not model-invocable. The user runs it after this command finishes.
- Do **not** create new documentation files unless explicitly asked.
- Do **not** persist session logs, task details, or project-specific trivia.
- If a change is safe, reversible, and within scope, execute it. Do not ask permission.
- Memory commit is mandatory if any memory file was touched this session. Don't report "ready to compact" with uncommitted memory entries.
- **Verify before memorializing.** Same rule as `/jm-retro`: unverified factual claims about system behavior must not be committed as durable rules. The retro is the most dangerous place for unverified claims; pre-compact is the same hazard plus a hard deadline.

## Boundary

- Lessons distillation + memory commit → this command.
- End-of-session cleanup (worktrees, background processes, ticketing) → `/jm-wrap`.
- Full retro with "What's Next" → `/jm-retro` (at session end).
- Actually running compaction → user types `/compact`.
