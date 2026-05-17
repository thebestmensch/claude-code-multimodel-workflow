#!/usr/bin/env bash
# Hook: Devils Advocate Plan Gate (PreToolUse on ExitPlanMode)
# Blocks ExitPlanMode on non-trivial plans until devils-advocate has been dispatched.
# Complexity gate: plan has 3+ numbered tasks OR length > 600 chars.
# Bypass: touch /tmp/cc-gates/$SESSION/skip_devils_advocate
set -o pipefail

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

gate_dir="/tmp/cc-gates/$session_id"
mkdir -p "$gate_dir"

# Already dispatched this round → allow
[ -f "$gate_dir/devils_advocate_dispatched" ] && exit 0

# Explicit bypass → allow
[ -f "$gate_dir/skip_devils_advocate" ] && exit 0

plan=$(echo "$input" | jq -r '.tool_input.plan // empty')
plan_len=${#plan}
task_count=$(echo "$plan" | grep -cE '^[[:space:]]*[0-9]+\.' || true)

# Complexity gate: trivial plans pass silently
if [ "$task_count" -lt 3 ] && [ "$plan_len" -lt 600 ]; then
  exit 0
fi

reason="Plan meets complexity gate (tasks=$task_count, len=$plan_len). Dispatch the devils-advocate agent with this plan text as input. Wait for its verdict. Then retry ExitPlanMode (revise first if REVISE/RECONSIDER). To skip: touch $gate_dir/skip_devils_advocate"

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "$reason"
  }
}
EOF
exit 0
