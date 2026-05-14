#!/usr/bin/env bash
# Hook 2 — Template Edit Counter (PostToolUse on Edit|Write)
# Counts UI file edits and reminds about visual QA every 5th edit.
set -o pipefail

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

[ -z "$session_id" ] || [ -z "$file_path" ] && exit 0

# Only count .html, .css, .js files
case "$file_path" in
  *.html|*.css|*.js|*.tsx|*.jsx) ;;
  *) exit 0 ;;
esac

# Exclude throwaway brainstorm visual-companion screens — they are gitignored
# design aids, not shipping UI. The user reviews them live in the browser as
# the QA mechanism itself.
case "$file_path" in
  */.superpowers/brainstorm/*) exit 0 ;;
  */superpowers/brainstorm/*) exit 0 ;;
esac

gate_dir="/tmp/cc-gates/$session_id"
[ -d "$gate_dir" ] || exit 0

# Increment counter
count_file="$gate_dir/template_edit_count"
if [ -f "$count_file" ]; then
  count=$(cat "$count_file")
  count=$((count + 1))
else
  count=1
fi
echo "$count" > "$count_file"

# Append to file list (deduped on read, not write — simpler)
echo "$file_path" >> "$gate_dir/template_files"

# Reminder every 5th edit (only if no visual QA dispatched)
if [ $((count % 5)) -eq 0 ] && [ ! -f "$gate_dir/visual_qa_dispatched" ]; then
  echo "⚠️ $count UI files edited without visual QA. Consider /visual-qa before continuing."
fi

exit 0
