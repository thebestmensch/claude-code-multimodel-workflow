#!/usr/bin/env bash
# Hook: SDD Review Tracker (PostToolUse on Agent)
# Tracks implementer vs reviewer dispatches for the two-phase SDD review gate.
# Implementer dispatches set TWO flags (spec + code); each reviewer type clears its own.
set -o pipefail

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
tool_name=$(echo "$input" | jq -r '.tool_name // empty')

[ -z "$session_id" ] || [ "$tool_name" != "Agent" ] && exit 0

gate_dir="/tmp/cc-gates/$session_id"
[ -d "$gate_dir" ] || exit 0

desc=$(echo "$input" | jq -r '.tool_input.description // empty' | tr '[:upper:]' '[:lower:]')

# Implementer: description matches "task" + a number (Task 1, Tasks 3+4, etc.)
# but NOT if it also contains "review"/"spec"/"quality" (those are reviewers).
# Sets both review flags; both must clear before task completion.
case "$desc" in
  *review*|*spec*|*quality*) ;;
  *task*[0-9]*)
    touch "$gate_dir/sdd_needs_spec_review"
    touch "$gate_dir/sdd_needs_code_review"
    ;;
esac

# Spec reviewer: description contains "spec" near "review"
# (e.g., "spec review tasks 1-2", "verify spec compliance")
# Excludes visual/qa/polish/tone agents.
case "$desc" in
  *visual*|*qa*|*polish*|*tone*|*bug*) ;;
  *spec*review*|*spec*compliance*|*verify*spec*)
    rm -f "$gate_dir/sdd_needs_spec_review"
    ;;
esac

# Code reviewer: description contains "code review" or "quality review"
# Also cleared by /lens-review skill dispatch (handled by dispatch-tracker.sh
# which touches code_review_dispatched, but this flag is separate).
case "$desc" in
  *visual*|*qa*|*polish*|*tone*|*bug*|*spec*) ;;
  *code*review*|*quality*review*|*code*quality*|*lensed*review*)
    rm -f "$gate_dir/sdd_needs_code_review"
    ;;
esac

exit 0
