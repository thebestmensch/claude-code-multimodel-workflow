#!/usr/bin/env bash
# Stop hook — blocks completion when backend files edited without observed runtime verification.
# Evidence-based: releases only when a verifying Bash command ran AFTER the most recent edit.
# (See track-verify-commands.sh for what counts as verification.)
set -o pipefail

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

gate_dir="/tmp/cc-gates/$session_id"
edited_file="$gate_dir/edited_files"

# Nothing edited → nothing to gate
[ -f "$edited_file" ] || exit 0

# Reasoned bypass — requires a written justification (not just a bare touch)
if [ -f "$gate_dir/skip_backend_gate" ]; then
  reason=$(tr -d '[:space:]' < "$gate_dir/skip_backend_gate")
  if [ -n "$reason" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') | backend-verification-gate | $(cat "$gate_dir/skip_backend_gate")" >> "$gate_dir/bypass_log.txt"
    exit 0
  fi
fi

# Which edited files actually need runtime verification
backend_files=$(sort -u "$edited_file" \
  | grep -E '(routes/.*\.py|/routes\.py|templates/.*\.html|static/.*\.(js|css)|app/.*\.py|services/[^/]+/app/.*\.py)' \
  | grep -vE '(tests/|test_|migrations/|__pycache__|\.pyc$|conftest)' \
  || true)

[ -z "$backend_files" ] && exit 0

# Evidence check: a verify command must have run AFTER the last edit.
last_verify="$gate_dir/last_verify"
if [ -f "$last_verify" ] && [ "$last_verify" -nt "$edited_file" ]; then
  exit 0
fi

file_count=$(echo "$backend_files" | wc -l | tr -d ' ')

reason_text="🚫 STOP — ${file_count} backend file(s) were edited without observed runtime verification.

Files:
${backend_files}

Any of these counts as evidence and will release the gate automatically:
  • curl the affected endpoint
  • uv run pytest / just test
  • docker exec <container> python -c '...'
  • playwright / just visual-test
  • ssh <host> docker exec ...

Do NOT claim 'tests should pass' or 'this should work' without running it. The gate is evidence-based — it observes your Bash activity, not a touchfile.

To bypass (logged and surfaced in retros), write a reason:
  echo 'reason here' > ${gate_dir}/skip_backend_gate"

jq -nc --arg reason "$reason_text" '{decision: "block", reason: $reason}'
