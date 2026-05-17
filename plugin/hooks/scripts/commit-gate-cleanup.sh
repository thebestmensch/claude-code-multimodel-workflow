#!/usr/bin/env bash
# PostToolUse hook (Bash): cleans up commit-gate bypass tokens only after a
# successful `git commit`. Prevents the "bypass consumed on blocked commit"
# bug where users had to re-approve after any downstream commit failure.
set -o pipefail

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty')

# Only act on git commit commands
case "$command" in
  *git\ commit*) ;;
  *) exit 0 ;;
esac

# Check commit success via tool_response; treat missing fields as failure
# to avoid deleting tokens on ambiguous outcomes.
stdout=$(echo "$input" | jq -r '.tool_response.stdout // ""')
stderr=$(echo "$input" | jq -r '.tool_response.stderr // ""')
interrupted=$(echo "$input" | jq -r '.tool_response.interrupted // false')

[ "$interrupted" = "true" ] && exit 0

# Successful git commit prints "[<branch> <sha>]" or similar to stdout.
# If stdout contains no bracket-prefixed branch line, treat as failed.
if ! echo "$stdout" | grep -qE '^\[[a-zA-Z0-9_/-]+ [0-9a-f]+\]'; then
  exit 0
fi

session_id=$(echo "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

gate_dir="/tmp/cc-gates/$session_id"
[ -d "$gate_dir" ] || exit 0

# Commit succeeded: consume the bypass tokens. Each gate has its own
# approval sentinel: pre-commit-gate uses bypass_approved (visual-qa /
# code-review); commit-on-drifted-branch-guard uses
# bypass_commit_drift_approved (branch/topic fit), separate so a drift
# approval cannot silently waive QA review.
rm -f "$gate_dir/bypass_approved" \
      "$gate_dir/skip_commit_gate" \
      "$gate_dir/bypass_commit_drift_approved" \
      "$gate_dir/skip_commit_drift_gate"

exit 0
