#!/usr/bin/env bash
# PostToolUse/Bash hook — stamps last_verify when a runtime-verifying command runs.
# Feeds the Stop-event backend-verification-gate: evidence, not ritual.
set -o pipefail

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
command=$(echo "$input" | jq -r '.tool_input.command // empty')

[ -z "$session_id" ] && exit 0
[ -z "$command" ] && exit 0

gate_dir="/tmp/cc-gates/$session_id"
[ -d "$gate_dir" ] || mkdir -p "$gate_dir"

# Verifying command patterns — things that exercise code at runtime.
# Broad on purpose: over-capture is fine (false positive = gate releases early),
# under-capture is worse (blocks legitimate work). Only cares that SOMETHING ran.
case "$command" in
  *curl*|*pytest*|*"just test"*|*"just visual-test"*|*"just visual-update"*|\
  *"just dev"*|*"just rebuild-"*|*"docker exec"*|*"docker compose run"*|\
  *"docker compose up"*|*"docker compose exec"*|*"docker logs"*|*playwright*|\
  *"python -c"*|*"python3 -c"*|*"node -e"*|*"uv run"*|*"gh api"*|\
  *"ssh "*|*"browser_"*|*http*://*|*npx*|*"tsx "*|*"node "*)
    touch "$gate_dir/last_verify"
    ;;
esac

exit 0
