#!/usr/bin/env bash
# Hook: main checkout branch drift guard (SessionStart)
# Convention: feature work happens in linked worktrees (e.g. .claude/worktrees/<slug>),
# the primary checkout stays on the default branch (main/master).
# When the primary worktree is sitting on a non-default branch, downstream
# tooling (HUD display, gh pr lookups) attaches the wrong PR to this session.
# Warn so the user can recover before working.
set -o pipefail

# Discard stdin (we don't need the session payload).
cat >/dev/null 2>&1 || true

cwd=$(pwd -P)
[ -z "$cwd" ] && exit 0

# In a git repo?
git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Distinguish primary worktree from linked worktree.
#   Primary:  --git-dir == --git-common-dir
#   Linked:   --git-dir is .git/worktrees/<slug>, --git-common-dir is the shared .git
git_dir=$(git -C "$cwd" rev-parse --git-dir 2>/dev/null)
common_dir=$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null)

# Resolve to absolute paths (--git-dir/--git-common-dir can be relative).
[ -d "$git_dir" ] && git_dir=$(cd "$git_dir" && pwd -P)
[ -d "$common_dir" ] && common_dir=$(cd "$common_dir" && pwd -P)

# Linked worktree → fine, exit silently.
[ "$git_dir" != "$common_dir" ] && exit 0

# Determine the default branch. Prefer the remote HEAD; fall back to main/master.
default_branch=""
if git -C "$cwd" symbolic-ref refs/remotes/origin/HEAD >/dev/null 2>&1; then
  default_branch=$(git -C "$cwd" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
fi
if [ -z "$default_branch" ]; then
  if git -C "$cwd" show-ref --verify --quiet refs/heads/main; then
    default_branch="main"
  elif git -C "$cwd" show-ref --verify --quiet refs/heads/master; then
    default_branch="master"
  fi
fi
[ -z "$default_branch" ] && exit 0

# Current branch
branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
[ -z "$branch" ] && exit 0

# All good?
[ "$branch" = "$default_branch" ] && exit 0

# Tree dirty?
dirty="no"
if [ -n "$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
  dirty="yes"
fi

# Associated PR (if any).
pr_url=""
pr_num=""
if command -v gh >/dev/null 2>&1; then
  pr_info=$(gh pr list --head "$branch" --state all --limit 1 \
              --json number,url \
              --jq '.[0] | select(. != null) | "\(.number) \(.url)"' 2>/dev/null)
  if [ -n "$pr_info" ]; then
    pr_num=$(echo "$pr_info" | awk '{print $1}')
    pr_url=$(echo "$pr_info" | awk '{print $2}')
  fi
fi

cat <<EOF
⚠ Primary checkout drifted off default branch
  Tree:    $cwd
  Branch:  $branch (expected: $default_branch)
  Dirty:   $dirty
EOF

if [ -n "$pr_url" ]; then
  cat <<EOF
  PR:      $pr_url
EOF
fi

cat <<'EOF'

  Convention: feature work belongs in a linked worktree
  (e.g. .claude/worktrees/<slug>); the primary checkout stays on
  the default branch. Otherwise the chat title, HUD, and gh-pr
  tooling attach this branch's PR to every session that opens here.

  Recovery:
EOF

if [ "$dirty" = "no" ]; then
  cat <<EOF
    git checkout $default_branch
EOF
else
  cat <<EOF
    git stash push -u -m "main-checkout-drift-$(date +%Y-%m-%d)"
    git checkout $default_branch

  Or, if the WIP belongs on '$branch', commit/push and switch back to
  $default_branch from a worktree next time.
EOF
fi

exit 0
