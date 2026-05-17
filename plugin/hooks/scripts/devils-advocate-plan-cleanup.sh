#!/usr/bin/env bash
# Hook: Devils Advocate Plan Cleanup (PostToolUse on ExitPlanMode)
# Clears the dispatched sentinel after a plan successfully exits, so the next
# plan presented in the same session re-requires an adversarial review.
set -o pipefail

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

rm -f "/tmp/cc-gates/$session_id/devils_advocate_dispatched"
exit 0
