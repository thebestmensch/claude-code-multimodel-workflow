#!/usr/bin/env bash
# Hook: Investigate Checkpoint Reminder (PreToolUse on Edit|Write)
# Soft, non-blocking. Surfaces a reflection prompt every 5th edit per file.
#
# Previous behavior used permissionDecision="ask" on the first edit, which
# stalled headless runs and broke flow in interactive mode (and never reached
# the model in autonomous sessions). The "ask" path was removed 2026-05-08
# during hook audit; see ~/.claude/rules/<audit notes>. Now strictly
# advisory: emits additionalContext on the 5th, 10th, 15th, ... edit per file.
set -o pipefail

input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // empty')
session_id=$(echo "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

gate_dir="${CC_GATE_DIR_BASE:-/tmp/cc-gates}/$session_id"
mkdir -p "$gate_dir"

file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
[ -z "$file_path" ] && exit 0

norm_path=$(echo "$file_path" | sed 's/[^a-zA-Z0-9]/_/g')
edit_count_file="$gate_dir/edit_count_$norm_path"

if [ -f "$edit_count_file" ]; then
  count=$(cat "$edit_count_file")
  count=$((count + 1))
else
  count=1
fi
echo "$count" > "$edit_count_file"

# Only surface checkpoint every 5th edit. First edit is silent; the model
# already self-checks via system prompt; redundant ceremony just adds noise.
if [ $((count % 5)) -ne 0 ]; then
  exit 0
fi

if [ "$tool_name" = "Edit" ]; then
  msg="INVESTIGATE CHECKPOINT: Edit #$count to this file. Verify you're not drifting into assumption-based changes. Re-read if uncertain."
else
  msg="INVESTIGATE CHECKPOINT: Write #$count to this file. Are you rewriting based on assumptions about what failed?"
fi

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "additionalContext": "$msg"
  }
}
EOF
