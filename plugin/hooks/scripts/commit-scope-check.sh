#!/usr/bin/env bash
# PreToolUse (Bash): Commit Scope Check
# Blocks `git commit` when the staged changeset includes files that were NOT
# edited during this session (detected via /tmp/cc-gates/<session>/edited_files,
# populated by track-edited-files.sh). Prevents accidentally bundling pre-existing
# in-flight user work into Claude's commits.
#
# Bypass: same two-step pattern as pre-commit-gate.sh
#   1. Claude:  echo "reason" > /tmp/cc-gates/<session>/skip_commit_scope
#   2. User:    ! echo approved > /tmp/cc-gates/<session>/bypass_scope_approved
set -o pipefail

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty')

# Only gate git commit commands; skip --amend without new adds
case "$command" in
  *git\ commit*) ;;
  *) exit 0 ;;
esac

session_id=$(echo "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

gate_dir="/tmp/cc-gates/$session_id"
mkdir -p "$gate_dir"

bypass_request="$gate_dir/skip_commit_scope"
bypass_approved="$gate_dir/bypass_scope_approved"

# Approved bypass: consume and allow
if [ -f "$bypass_approved" ]; then
  approval=$(tr -d '[:space:]' < "$bypass_approved")
  if [ "$approval" = "approved" ]; then
    reason="(user-approved)"
    [ -f "$bypass_request" ] && reason=$(cat "$bypass_request")
    echo "$(date '+%Y-%m-%d %H:%M:%S') | scope-check | USER APPROVED | $reason" >> "$gate_dir/bypass_log.txt"
    rm -f "$bypass_approved" "$bypass_request"
    exit 0
  fi
fi

# Pending bypass request: surface to user for approval
if [ -f "$bypass_request" ]; then
  reason=$(cat "$bypass_request")
  if [ -n "$reason" ]; then
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "⏳ Commit-scope bypass requested: $reason\n\nTo approve, run: ! echo approved > $bypass_approved"
  }
}
EOF
    exit 0
  fi
fi

# Get staged files (absolute paths to match the tracked list)
repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
staged_rel=$(git diff --cached --name-only 2>/dev/null)

# Detect `-a` / `-am` / `--all` flags: they auto-stage modified tracked files
# at commit time, which the staged-set check above can't see (the staging hasn't
# happened yet at PreToolUse). Augment with working-tree modifications.
# Match: bare `-a`, bundled flag like `-am`/`-ma`, or `--all`, but NOT `--allow-*`.
if echo "$command" | grep -Eq ' -[a-zA-Z]*a([a-zA-Z]*)?( |$)| --all( |$)'; then
  worktree_rel=$(git diff --name-only 2>/dev/null)  # tracked-modified, not yet staged
  if [ -n "$worktree_rel" ]; then
    staged_rel=$(printf '%s\n%s\n' "$staged_rel" "$worktree_rel" | sort -u | grep -v '^$')
  fi
fi

[ -z "$staged_rel" ] && exit 0  # empty staged set (e.g. --amend --no-edit): allow

# Filter out extensions that track-edited-files.sh skips; otherwise those files
# are always "unexpected" and every config/docs commit needs bypass.
staged_rel=$(echo "$staged_rel" | grep -Ev '\.(md|json|yml|yaml|toml|txt|csv|lock)$' || true)
[ -z "$staged_rel" ] && exit 0  # only skipped-extension files staged: allow

# Build absolute-path staged list
staged_abs=$(echo "$staged_rel" | sed "s|^|$repo_root/|")

# Session-edited files (deduped)
edited_file="$gate_dir/edited_files"
if [ ! -f "$edited_file" ]; then
  # No tracking data: can't enforce, allow (session may predate tracker)
  exit 0
fi
edited_abs=$(sort -u "$edited_file")

# Find staged files that aren't in the edited set
unexpected=$(comm -23 <(echo "$staged_abs" | sort -u) <(echo "$edited_abs"))

if [ -z "$unexpected" ]; then
  exit 0  # clean scope
fi

# Count + sample for the deny message
count=$(echo "$unexpected" | wc -l | tr -d ' ')
sample=$(echo "$unexpected" | head -5 | sed "s|^$repo_root/||" | sed 's/^/  • /')
extra=""
[ "$count" -gt 5 ] && extra="  … and $((count - 5)) more\n"

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "🚫 Commit blocked: $count staged file(s) were NOT edited by Claude this session:\n$sample\n$extra\nUnstage them (git reset HEAD -- <path>) or request bypass:\n  echo 'reason' > $bypass_request\nThen user approves: ! echo approved > $bypass_approved"
  }
}
EOF
exit 0
