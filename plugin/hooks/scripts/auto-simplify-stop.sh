#!/usr/bin/env bash
# Stop hook — suggests code simplification if files were edited this session.
# Opt-in: only fires if ~/.claude/.auto-simplify exists.
# Dedup: skips if already simplified this session.
set -o pipefail

# Opt-in gate
[ -f "$HOME/.claude/.auto-simplify" ] || exit 0

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

gate_dir="/tmp/cc-gates/$session_id"
edited_file="$gate_dir/edited_files"
simplify_marker="$gate_dir/simplified"

# No files edited, or already simplified — skip
[ -f "$edited_file" ] || exit 0
[ -f "$simplify_marker" ] && exit 0

# Deduplicate the file list
file_count=$(sort -u "$edited_file" | wc -l | tr -d ' ')
[ "$file_count" -eq 0 ] && exit 0

# Get unique file list
file_list=$(sort -u "$edited_file" | head -20)

# Mark as simplified so we don't fire again this session
touch "$simplify_marker"

cat <<EOF
$file_count code file(s) were modified this session. Run /simplify to review them for clarity, consistency, and maintainability:

$file_list
EOF
