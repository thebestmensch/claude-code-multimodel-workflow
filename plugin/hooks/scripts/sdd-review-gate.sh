#!/usr/bin/env bash
# Hook: SDD Review Gate (PreToolUse on TaskUpdate)
# Blocks marking a task as completed unless BOTH spec review and code review
# have been dispatched since the last implementer. Also blocks if UI files
# were edited without visual QA.
set -o pipefail

input=$(cat)

# Only gate TaskUpdate with status=completed
status=$(echo "$input" | jq -r '.tool_input.status // empty')
[ "$status" != "completed" ] && exit 0

session_id=$(echo "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

gate_dir="/tmp/cc-gates/$session_id"
[ -d "$gate_dir" ] || exit 0

# Per-gate escape hatch: requires a non-empty reason string.
# Usage: echo "reason here" > /tmp/cc-gates/<session>/skip_sdd_gate
if [ -f "$gate_dir/skip_sdd_gate" ]; then
  reason=$(cat "$gate_dir/skip_sdd_gate" | tr -d '[:space:]')
  if [ -n "$reason" ]; then
    # Log the bypass with timestamp
    echo "$(date '+%Y-%m-%d %H:%M:%S') | sdd-review-gate | $(cat "$gate_dir/skip_sdd_gate")" >> "$gate_dir/bypass_log.txt"
    exit 0
  fi
  # Empty file (bare touch): reject and explain
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "🚫 Bypass file exists but has no reason. Write a justification: echo 'reason here' > $gate_dir/skip_sdd_gate"
  }
}
EOF
  exit 0
fi

# ── Phase 1: Spec review gate ──
if [ -f "$gate_dir/sdd_needs_spec_review" ]; then
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "🚫 Task completion blocked: implementer dispatched without spec review. Dispatch a spec reviewer subagent before marking complete. To bypass, write a reason: echo 'reason' > $gate_dir/skip_sdd_gate (logged and surfaced in retros)"
  }
}
EOF
  exit 0
fi

# ── Phase 2: Code review gate ──
if [ -f "$gate_dir/sdd_needs_code_review" ]; then
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "🚫 Task completion blocked: implementer dispatched without code review. Dispatch /code-review or a code quality reviewer before marking complete. To bypass, write a reason: echo 'reason' > $gate_dir/skip_sdd_gate (logged and surfaced in retros)"
  }
}
EOF
  exit 0
fi

# ── Phase 3: Visual QA gate for UI tasks ──
# If UI files were edited since last visual QA, block completion.
template_files="$gate_dir/template_files"
if [ -f "$template_files" ]; then
  vqa_marker="$gate_dir/visual_qa_dispatched"
  if [ ! -f "$vqa_marker" ] || [ "$template_files" -nt "$vqa_marker" ]; then
    ui_count=$(wc -l < "$template_files" | tr -d ' ')
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "🚫 Task completion blocked: ${ui_count} UI files edited without visual QA. Dispatch /visual-qa before marking complete. To bypass, write a reason: echo 'reason' > $gate_dir/skip_sdd_gate (logged and surfaced in retros)"
  }
}
EOF
    exit 0
  fi
fi

exit 0
