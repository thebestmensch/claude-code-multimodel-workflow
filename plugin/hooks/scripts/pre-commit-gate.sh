#!/usr/bin/env bash
# Hook 3: Pre-commit Gate (PreToolUse on Bash)
# Blocks git commit when UI files were edited without visual QA or code review.
set -o pipefail

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty')

# Shared matcher: handles env wrappers, abs paths, shell -c, compound
# segments, alias resolution. Same lib as codex-pre-commit-gate.sh; keeps the
# two gates in lockstep on what counts as a `git commit` invocation.
matches=$(/usr/bin/python3 "$(dirname "$0")/lib/match-git-commit.py" "$command" 2>/dev/null)
[ "$matches" != "match" ] && exit 0

session_id=$(echo "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

gate_dir="/tmp/cc-gates/$session_id"
[ -d "$gate_dir" ] || exit 0

# Two-step bypass: Claude writes a request, user must approve.
# Step 1: Claude writes reason to skip_commit_gate (request)
# Step 2: User runs: ! echo approved > /tmp/cc-gates/<session>/bypass_approved
bypass_request="$gate_dir/skip_commit_gate"
bypass_approved="$gate_dir/bypass_approved"

if [ -f "$bypass_approved" ]; then
  approval=$(cat "$bypass_approved" | tr -d '[:space:]')
  if [ "$approval" = "approved" ]; then
    # User approved: log and allow
    reason="(user-approved)"
    [ -f "$bypass_request" ] && reason=$(cat "$bypass_request")
    echo "$(date '+%Y-%m-%d %H:%M:%S') | commit-gate | USER APPROVED | $reason" >> "$gate_dir/bypass_log.txt"
    # Note: bypass tokens are now deleted by commit-gate-cleanup.sh
    # (PostToolUse) only on successful commit, so a downstream failure
    # (e.g. "nothing staged") doesn't force user re-approval.
    exit 0
  fi
fi

if [ -f "$bypass_request" ]; then
  reason=$(cat "$bypass_request")
  if [ -n "$reason" ]; then
    # Claude requested bypass but user hasn't approved yet. pbcopy the
    # approval invocation so the user can paste-run after reviewing the
    # request reason in chat.
    # shellcheck disable=SC1091
    source "$(dirname "$0")/_lib/pbcopy-bypass.sh"
    pbcopy_bypass "echo approved > $gate_dir/bypass_approved"
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "⏳ Bypass requested: $reason\n\nTo approve, run: ! echo approved > $gate_dir/bypass_approved\n(That command is already in your clipboard via pbcopy.)"
  }
}
EOF
    exit 0
  fi
fi

# Count UI + backend edits
ui_count=0
backend_count=0
[ -f "$gate_dir/template_edit_count" ] && ui_count=$(cat "$gate_dir/template_edit_count")
[ -f "$gate_dir/backend_edit_count" ] && backend_count=$(cat "$gate_dir/backend_edit_count")

# No relevant edits → no gate
if [ "$ui_count" -eq 0 ] 2>/dev/null && [ "$backend_count" -eq 0 ] 2>/dev/null; then
  exit 0
fi

# Staleness pivot: newer of template_files / backend_files mtime is the
# most recent edit timestamp. Markers must be newer than this to count as fresh.
template_files="$gate_dir/template_files"
backend_files="$gate_dir/backend_files"
latest_edit="$template_files"
if [ -f "$backend_files" ]; then
  if [ ! -f "$latest_edit" ] || [ "$backend_files" -nt "$latest_edit" ]; then
    latest_edit="$backend_files"
  fi
fi

is_stale() {
  local marker="$1" pivot="${2:-$latest_edit}"
  [ ! -f "$marker" ] && return 0            # missing = stale
  [ ! -f "$pivot" ] && return 1             # no edits tracked = not stale
  [ "$pivot" -nt "$marker" ] && return 0
  return 1
}

# Check visual QA: only required when UI files were edited.
# Staleness pivot is template_files specifically (backend edits do not invalidate
# a prior visual QA dispatch; the rendered UI hasn't changed).
if [ "$ui_count" -gt 0 ] 2>/dev/null && is_stale "$gate_dir/visual_qa_dispatched" "$template_files"; then
  # pbcopy the skip-request template. User pastes / model re-issues with edited
  # REASON only AFTER posting evidence that /visual-qa is genuinely inapplicable.
  # shellcheck disable=SC1091
  source "$(dirname "$0")/_lib/pbcopy-bypass.sh"
  pbcopy_bypass "echo 'REASON: non-capturable-ui|css-only-no-render-change' > $gate_dir/skip_commit_gate"
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "🚫 Commit blocked: $ui_count UI files edited without visual QA. Dispatch /visual-qa first, then re-run the commit; the gate will clear automatically once the QA marker is fresh.\n\nDO NOT write skip_commit_gate just because the commit was blocked. Only write a skip if /visual-qa is genuinely inapplicable (e.g. CSS for non-capturable UI) AND you've posted evidence for that in chat.\n\nTo request bypass (only if QA truly doesn't apply): echo 'REASON: non-capturable-ui|css-only-no-render-change' > $gate_dir/skip_commit_gate\n(skip-request template is in your clipboard via pbcopy.)\nThen user approves: ! echo approved > $gate_dir/bypass_approved"
  }
}
EOF
  exit 0
fi

# Check code review: required when UI OR backend files were edited
if is_stale "$gate_dir/code_review_dispatched"; then
  scope_desc=""
  if [ "$ui_count" -gt 0 ] 2>/dev/null && [ "$backend_count" -gt 0 ] 2>/dev/null; then
    scope_desc="$ui_count UI + $backend_count backend files"
  elif [ "$ui_count" -gt 0 ] 2>/dev/null; then
    scope_desc="$ui_count UI files"
  else
    scope_desc="$backend_count backend files"
  fi
  # pbcopy the skip-request template with valid-reason hints.
  # shellcheck disable=SC1091
  source "$(dirname "$0")/_lib/pbcopy-bypass.sh"
  pbcopy_bypass "echo 'REASON: docs-only|whitespace|trivial-config' > $gate_dir/skip_commit_gate"
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "🚫 Commit blocked: $scope_desc edited without code review. Dispatch /code-review first, then re-run the commit; the gate will clear automatically once the review marker is fresh.\n\nDO NOT write skip_commit_gate just because the commit was blocked. Only write a skip if /code-review is genuinely inapplicable (e.g. pure docs commit) AND you've posted evidence for that in chat.\n\nTo request bypass (only if review truly doesn't apply): echo 'REASON: docs-only|whitespace|trivial-config' > $gate_dir/skip_commit_gate\n(skip-request template is in your clipboard via pbcopy.)\nThen user approves: ! echo approved > $gate_dir/bypass_approved"
  }
}
EOF
  exit 0
fi

# All applicable markers present → allow
exit 0
