#!/usr/bin/env bash
# Hook — ScheduleWakeup Loop Gate (PreToolUse on ScheduleWakeup)
# Blocks ScheduleWakeup unless the prompt is a real /loop input or the
# autonomous-loop-dynamic sentinel. ScheduleWakeup is *only* for /loop dynamic
# mode — it is NOT a generic "wait for thing" timer. For polling/waiting on a
# background task, use Bash with `until <check>; do sleep 20; done` and
# `run_in_background: true` instead — the runtime fires a notification when
# the background command exits.
#
# Bypass: touch /tmp/cc-gates/$SESSION/skip_schedule_wakeup_gate
set -o pipefail

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

gate_dir="/tmp/cc-gates/$session_id"
mkdir -p "$gate_dir"

# Explicit bypass → allow
[ -f "$gate_dir/skip_schedule_wakeup_gate" ] && exit 0

prompt=$(echo "$input" | jq -r '.tool_input.prompt // empty')

# Allow: autonomous-loop sentinel
[ "$prompt" = "<<autonomous-loop-dynamic>>" ] && exit 0

# Allow: prompt is a real /loop user message (starts with "/loop ")
case "$prompt" in
  "/loop "*|"/loop") exit 0 ;;
esac

reason="ScheduleWakeup is /loop-dynamic-mode ONLY. The prompt you passed is neither a real /loop input nor the <<autonomous-loop-dynamic>> sentinel — that's the misuse pattern flagged in feedback_afk_no_prompts.md and re-violated multiple sessions running. To wait for a background task, run Bash with run_in_background:true and \`until <check>; do sleep 20; done\` — the runtime auto-notifies on completion. To genuinely use ScheduleWakeup, this must be a /loop session and the prompt must echo the /loop input verbatim. To bypass (rarely justified): touch $gate_dir/skip_schedule_wakeup_gate"

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": $(echo "$reason" | jq -Rs .)
  }
}
EOF
exit 0
