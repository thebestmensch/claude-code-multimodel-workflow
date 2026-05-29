#!/usr/bin/env bash
# Backend Edit Counter (PostToolUse on Edit|Write)
# Counts edits to production code/infra so pre-commit-gate.sh can require a
# /lens-review dispatch on substantive commits. Covers:
#   - Python anywhere under services/<svc>/ (app/, CLI packages like tickets/)
#   - Container/deploy infra: Dockerfile, docker-compose*.yml, service shell scripts
#   - Repo-wide infra: justfile, GitHub Actions workflows
# Tests excluded: test-only commits don't need a code-review dispatch.
set -o pipefail

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')

[ -z "$session_id" ] || [ -z "$file_path" ] && exit 0

# Skip test files: test-only commits shouldn't require a code-review dispatch
case "$file_path" in
  */tests/*|*/test_*.py|*_test.py) exit 0 ;;
esac

# Bash case `*` is greedy and matches `/`, so `*/services/*/*.py` catches any
# Python file at any depth under services/<svc>/ (including app/, app/routes/,
# tickets/, etc.). Repo-wide infra (justfile, .github/workflows/) is matched
# unrooted because the gate file lives at /tmp regardless of repo path.
case "$file_path" in
  # Python under any services/<svc>/ subtree
  */services/*/*.py) ;;
  # Container & deploy infra (per-service)
  */services/*/Dockerfile|*/services/*/docker-compose*.yml|*/services/*/*.sh) ;;
  # Repo-wide infra
  */justfile|*/.github/workflows/*.yml) ;;
  *) exit 0 ;;
esac

gate_dir="/tmp/cc-gates/$session_id"
[ -d "$gate_dir" ] || exit 0

count_file="$gate_dir/backend_edit_count"
if [ -f "$count_file" ]; then
  count=$(cat "$count_file")
  count=$((count + 1))
else
  count=1
fi
echo "$count" > "$count_file"

echo "$file_path" >> "$gate_dir/backend_files"

exit 0
