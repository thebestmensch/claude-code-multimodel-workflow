# Agent Dispatch Requirements

When dispatching agents via the `Agent` tool, **always include `subagent_type`** in the tool call parameters. This field is required for the HUD status line to display meaningful agent labels.

- If the agent is a specialized type (e.g., `Explore`, `devils-advocate`, or plugin-provided agents like `superpowers:code-reviewer` / `codex:codex-rescue` when those plugins are installed), use that type name
- If the agent is a general-purpose implementer or investigator, use `subagent_type: "general-purpose"`
- Never omit `subagent_type`. The HUD falls back to a generic label when it's missing

This applies to all agent dispatches: SDD implementers, parallel agents, review agents, and ad-hoc agents.

## Verify the agent exists in the current project

Before dispatching, confirm `subagent_type` is in the available-agents list for the active session. The list is in the system prompt (Agent tool description), and the set differs per project. Workspace-specific agents (e.g. domain reviewers, creative directors) only exist in workspaces that define them, and plugin-provided agents (e.g. `superpowers:code-reviewer`) only exist when the plugin is installed. Don't dispatch from training memory.

If the desired agent isn't available locally, fall back to `general-purpose` with a strong directive prompt, and tell the user up front rather than letting the dispatch fail.

## Isolate write-mode agents in a worktree

When dispatching an agent that will **write or edit files** (SDD implementers, refactors, multi-file changes, code-fix agents), include `isolation: "worktree"` in the `Agent` tool call. The agent works on a temporary git worktree on its own branch, and the change merges back explicitly when it returns.

**Why:** Agents and the main session share the same git index. If you stage files, then an agent commits, your staged work lands under the agent's commit message. If a parallel CC session does `git reset --soft HEAD~1`, it can drop your already-pushed commit from local history. Worktrees give each writer its own index, the only durable fix for index collisions.

**When to use:**
- Always for SDD implementer dispatches
- Always when the agent will edit 3+ files or touch shared code (`services/shared/`, root CSS, n8n workflows)
- Always for any agent dispatched in background (`run_in_background: true`) that writes files

**When to skip:**
- Read-only agents (Explore, research-agent, devils-advocate, code-reviewer, visual-qa, accessibility-qa, tone-qa): no writes, no collision surface
- Single-file edits in the main session (you have full context, faster to do directly)
- Agents that need to run dev servers/ports (worktrees can't bind a port already held by the main session)

The worktree auto-cleans if the agent makes no changes; otherwise the path and branch come back in the result for explicit merge.
