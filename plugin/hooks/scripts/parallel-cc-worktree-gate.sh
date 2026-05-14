#!/usr/bin/env bash
# Hook — parallel CC worktree gate (PreToolUse on Edit|Write)
#
# Enforces the worktree-first rule (memory: feedback_parallel_cc_cwd_warn.md).
# When a sibling Claude Code session shares this git toplevel AND the current
# session is operating in the main checkout (not under .claude/worktrees/),
# any code edit risks index/HEAD collisions across sessions. Block with an
# "ask" decision so the user spins a worktree before the first edit lands.
#
# Bypass: write a reason to $CC_GATE_DIR_BASE/$session_id/skip_worktree_gate
#   (e.g. "single-file edit in main checkout, no parallel commits planned")
#
# Headless safety: in headless (CLAUDE_CODE_ENTRYPOINT=sdk-cli) the hook
# returns "allow" + additionalContext instead of "ask" so the autonomous
# linear-agent doesn't stall waiting on a UI confirm that doesn't exist.
set -o pipefail

GATE_DIR_BASE="${CC_GATE_DIR_BASE:-/tmp/cc-gates}"

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // "unknown"')
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

# No file_path → not an Edit/Write we care about.
[ -z "$file_path" ] && exit 0

session_dir="$GATE_DIR_BASE/$session_id"
mkdir -p "$session_dir" 2>/dev/null || true

# Bypass — user wrote a reason to skip the gate this session.
[ -f "$session_dir/skip_worktree_gate" ] && exit 0

# Once-per-session: don't re-prompt on every edit. After the first ask the
# user has either spun a worktree (collision risk gone) or written a bypass.
[ -f "$session_dir/worktree_gate_fired" ] && exit 0

cwd=$(pwd -P)
[ -z "$cwd" ] && exit 0

# Only fires inside git repos.
git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || exit 0

toplevel=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
[ -z "$toplevel" ] && exit 0

# Already in a worktree under .claude/worktrees/ → safe, exit silently.
case "$toplevel" in
  */.claude/worktrees/*) exit 0 ;;
esac

# Walk every running Claude Code process. The CC binary's process name is
# `2.1.111` (versioned binary), not `claude` — `pgrep -x claude` returns
# nothing. Match the install-path substring instead.
# Self counts as 1; > 1 means a collision.
sibling_count=0
for pid in $(pgrep -f "claude/versions/" 2>/dev/null); do
  other_cwd=$(lsof -p "$pid" 2>/dev/null | awk '$4 == "cwd" {print $NF; exit}')
  [ -z "$other_cwd" ] && continue
  other_top=$(git -C "$other_cwd" rev-parse --show-toplevel 2>/dev/null)
  [ "$other_top" = "$toplevel" ] && sibling_count=$((sibling_count + 1))
done

# Self always matches; need at least one OTHER session to fire.
[ "$sibling_count" -le 1 ] && exit 0

others=$((sibling_count - 1))
touch "$session_dir/worktree_gate_fired"

# Headless-aware payload — sdk-cli has no UI to confirm against, so emit
# additionalContext + allow rather than stalling on "ask".
is_headless=0
[ "${CLAUDE_CODE_ENTRYPOINT:-}" = "sdk-cli" ] && is_headless=1

reason=$(cat <<EOF
PARALLEL CC SESSION DETECTED — worktree-first rule violation risk

  Tree:                 $toplevel
  Other CC sessions:    $others
  About to edit:        $file_path

Editing the main checkout while a sibling session shares it risks index/HEAD
collisions: staged files land under the wrong commit, soft-resets drop a sibling-session pushed commit, race-y rebases lose changes.

Spin a worktree before the first edit:

  git worktree add .claude/worktrees/<slug> -b <new-branch>
  cd .claude/worktrees/<slug>

Bypass (single-file edit, doc-only change, etc.):

  echo "<reason>" > "$session_dir/skip_worktree_gate"
EOF
)

if [ "$is_headless" -eq 1 ]; then
  jq -nc --arg ctx "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "allow",
      additionalContext: $ctx
    }
  }'
else
  jq -nc --arg reason "$reason" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $reason
    }
  }'
fi

exit 0
