#!/usr/bin/env bash
# Hook — parallel CC session warn (SessionStart)
# Detects when another Claude Code session already has the same git working
# tree as cwd, so we spin up a worktree before HEAD/index collisions bite.
# Emits a warning to stdout (captured as additionalContext). Never blocks.
set -o pipefail

# Discard stdin (we don't need the session payload).
cat >/dev/null 2>&1 || true

cwd=$(pwd -P)
[ -z "$cwd" ] && exit 0

# Only warn inside git repos — non-git cwds can't collide on HEAD.
git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || exit 0

toplevel=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
[ -z "$toplevel" ] && exit 0

# Walk every running Claude Code process. The CC binary's process name is
# `2.1.111` (versioned binary), not `claude` — `pgrep -x claude` returns
# nothing. Match the install-path substring instead.
# Sibling worktrees have distinct toplevels, so they are NOT flagged.
sibling_count=0
for pid in $(pgrep -f "claude/versions/" 2>/dev/null); do
  other_cwd=$(lsof -p "$pid" 2>/dev/null | awk '$4 == "cwd" {print $NF; exit}')
  [ -z "$other_cwd" ] && continue
  other_top=$(git -C "$other_cwd" rev-parse --show-toplevel 2>/dev/null)
  [ "$other_top" = "$toplevel" ] && sibling_count=$((sibling_count + 1))
done

# Self always matches; need at least one OTHER session to warn.
[ "$sibling_count" -le 1 ] && exit 0

branch=$(git -C "$toplevel" rev-parse --abbrev-ref HEAD 2>/dev/null)
others=$((sibling_count - 1))

cat <<EOF
⚠ Parallel Claude Code session detected in this working tree
  Tree:   $toplevel
  Branch: ${branch:-<detached>}
  Other CC sessions sharing this cwd: $others

  Heads up: index/HEAD collisions ahead. Staging, checkout, rebase, and
  commits will race across sessions. If this session will edit code, spin
  up a worktree first:

    git worktree add .claude/worktrees/<slug> -b <new-branch>
    cd .claude/worktrees/<slug>

  See ~/.claude/rules/agent-dispatch.md for conventions and
  feedback_worktree_for_deploys.md for collision recovery patterns.
EOF

# Auto-fetch + show incoming commits so this session sees what parallel
# sessions are shipping (closes the gap that recurred 2026-05-06: spec doc
# drafted into a path that another session had just merged via PR #33).
# 3s timeout — fail silently on offline/slow networks rather than blocking.
if [ -n "$branch" ] && [ "$branch" != "HEAD" ]; then
  if (cd "$toplevel" && timeout 3 git fetch origin "$branch" --quiet) 2>/dev/null; then
    ahead_behind=$(git -C "$toplevel" rev-list --left-right --count "HEAD...origin/$branch" 2>/dev/null)
    if [ -n "$ahead_behind" ]; then
      ahead=$(printf '%s' "$ahead_behind" | cut -f1)
      behind=$(printf '%s' "$ahead_behind" | cut -f2)
      if [ "${behind:-0}" -gt 0 ] 2>/dev/null; then
        cat <<EOF

  Origin status: local is ${ahead:-0} ahead, $behind behind origin/$branch.
  Incoming commits (last 10):
EOF
        git -C "$toplevel" log --oneline "HEAD..origin/$branch" 2>/dev/null | head -10 | sed 's/^/    /'
        cat <<EOF

  → \`git pull --ff-only\` (or check incoming changes) BEFORE drafting
    new files in shared dirs (docs/, services/, .claude/). Naming
    collisions land at commit time and force a rewrite.
EOF
      fi
    fi
  fi
fi

exit 0
