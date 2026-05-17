#!/usr/bin/env bash
# PostToolUse hook (Edit|Write): tracks all files edited during this session.
# The auto-simplify Stop hook reads this list.
set -o pipefail

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

[ -z "$session_id" ] || [ -z "$file_path" ] && exit 0

# Skip non-code files
case "$file_path" in
  *.md|*.json|*.yml|*.yaml|*.toml|*.txt|*.csv|*.lock) exit 0 ;;
esac

gate_dir="${CC_GATE_DIR_BASE:-/tmp/cc-gates}/$session_id"
[ -d "$gate_dir" ] || mkdir -p "$gate_dir"

# Append to tracked file list (deduped by the consumer)
echo "$file_path" >> "$gate_dir/edited_files"

exit 0
