# Agent Conventions

This project hosts an autonomous Linear ticket agent (invoked via the `tickets` CLI or your own equivalent; see the "Slash command source of truth" section below for the runbook contract).

## Branch naming

The agent creates worktrees and branches with the prefix `<AGENT_BRANCH_PREFIX>`,
NOT the human convention `<HUMAN_BRANCH_PREFIX>` documented in CLAUDE.md.

| Branch prefix | Used by |
|---|---|
| `<HUMAN_BRANCH_PREFIX><feature>` | Humans, manual feature work |
| `<AGENT_BRANCH_PREFIX><ticket-slug>` | Autonomous Linear ticket agent, never overlaps with human work |

This deliberate distinction means agent-created PRs are reviewable as a separate stream from human PRs. Branch protection / CI rules can target each prefix independently.

## PR base branch

Agent PRs target `<DEFAULT_PR_BASE>` (this repo's default). Human feature branches follow the same convention.

## Worktrees

Agent worktrees live at `.claude/worktrees/<slug>/`. After `git worktree add`, run any project-specific setup the new worktree needs (env-file symlinks, dependency installs, generated-asset rebuilds) before the agent starts work. Fresh worktrees miss gitignored state and the agent's pre-push / pre-commit hooks will fail without it.

### Cleanup (safe: verifies work is preserved before delete)

The worktree itself can be removed once its branch is merged. The branch deletion is the risky step: `git branch -D` discards local commits with no recovery path other than `git reflog`. Use the guarded recipe below.

```bash
SLUG="<slug>"
BRANCH="<AGENT_BRANCH_PREFIX>${SLUG}"

# 1. Worktree must be clean (no uncommitted work)
git -C ".claude/worktrees/${SLUG}" status --porcelain | grep -q . && {
  echo "Worktree has uncommitted changes, aborting cleanup"; exit 1; }

# 2. Branch must have an upstream and zero unpushed commits
git rev-parse --abbrev-ref "${BRANCH}@{u}" >/dev/null 2>&1 || {
  echo "Branch ${BRANCH} has no upstream; push first or rebase onto remote"; exit 1; }
[ "$(git rev-list --count "${BRANCH}@{u}..${BRANCH}")" = "0" ] || {
  echo "Branch ${BRANCH} has unpushed commits; push or recover first"; exit 1; }

# 3. Now safe to remove worktree and delete branch with the non-force flag
git worktree remove ".claude/worktrees/${SLUG}"
git branch -d "${BRANCH}"   # -d (lowercase) refuses to delete unmerged branches
```

Force-delete (`git branch -D`) only after you have confirmed the work is preserved elsewhere: a merged PR, an explicit backup branch, or a deliberate decision to discard the work.

## Agent file location

Project-specific code-review reviewers (and any other workspace-specific agents) live at `.claude/agents/` (project-scoped), NOT `~/.claude/agents/` (global). Workspace-specific agents travel with the workspace; they load automatically when CC starts in any worktree of this project.

Universal reviewers (silent-failure-hunter, concurrency-auditor, api-contract-reviewer, sentry-discipline-reviewer, test-gap-analyzer, type-design-analyzer) and cross-project meta-agents (devils-advocate, research-agent) remain at `~/.claude/agents/` because they apply across projects.

When adding a new project-specific reviewer: write it under `.claude/agents/<noun>-reviewer.md` and add a row to `.claude/rules/code-review-<PROJECT>.md`. Don't write it to `~/.claude/agents/`.

## Slash command source of truth

`<RUNBOOK_NAME>.md` lives at `.claude/commands/<RUNBOOK_NAME>.md` (project-scoped, this repo). The Linear Task Agent loads it from the project's own commands path when launched in a worktree of this repo.

The per-project agent profile (`.claude/agent-profiles/code.yaml`) sets `slash_command: <RUNBOOK_COMMAND>`, which the `tickets` CLI reads when spawning `claude -p`.
