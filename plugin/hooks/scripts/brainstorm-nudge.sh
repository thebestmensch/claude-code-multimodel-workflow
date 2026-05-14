#!/usr/bin/env bash
# Hook — UI Skill Nudge (PreToolUse on Edit|Write)
# Nudges when editing UI files without prior brainstorming or frontend-design invocation.
# Fires once at the start of UI work, then again every 8 UI edits as a checkpoint reminder.
set -o pipefail

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

# Match UI files across all stacks
case "$file_path" in
  *.html|*.css|*.scss|*.tsx|*.jsx) ;;
  *) exit 0 ;;
esac

session_id=$(echo "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

gate_dir="/tmp/cc-gates/$session_id"
mkdir -p "$gate_dir"

# Track UI edit count
count_file="$gate_dir/ui_edit_count"
if [ -f "$count_file" ]; then
  count=$(cat "$count_file")
  count=$((count + 1))
else
  count=1
fi
echo "$count" > "$count_file"

# Skip if brainstorming or frontend-design already dispatched
[ -f "$gate_dir/brainstorm_dispatched" ] && [ -f "$gate_dir/frontend_design_dispatched" ] && exit 0

# First edit: initial nudge
if [ "$count" -eq 1 ]; then
  nudge=""
  [ ! -f "$gate_dir/brainstorm_dispatched" ] && nudge="If design decisions remain, use brainstorming first."
  [ ! -f "$gate_dir/frontend_design_dispatched" ] && nudge="$nudge For UI implementation, invoke the frontend-design skill."

  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "UI edit without design skills invoked. $nudge"
  }
}
EOF
  exit 0
fi

# Checkpoint nudge: every 8 UI edits, remind about visual QA
if [ $((count % 8)) -eq 0 ]; then
  nudge="$count UI edits this session."
  [ ! -f "$gate_dir/visual_qa_dispatched" ] && nudge="$nudge No visual QA dispatched yet — consider /visual-qa at this checkpoint."
  [ ! -f "$gate_dir/frontend_design_dispatched" ] && nudge="$nudge frontend-design skill was never invoked."

  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "$nudge"
  }
}
EOF
  exit 0
fi

exit 0
