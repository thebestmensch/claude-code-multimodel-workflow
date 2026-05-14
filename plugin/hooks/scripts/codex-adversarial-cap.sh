#!/usr/bin/env bash
# PreToolUse Bash gate — hard-blocks the 3rd Codex adversarial-review
# dispatch against the same edit batch (cap = 2).
#
# Pattern this catches (per feedback_codex_loop_scope_mismatch.md):
#   adversarial-review → finds X
#   fix X
#   adversarial-review → finds Y in different layer of same root concern
#   fix Y
#   adversarial-review → finds Z in a third layer
#
# When each pass returns a new finding on different manifestations of the
# same root concern, the fix is mis-scoped. Stop iterating, name the framing,
# propose options to the user (keep iterating / merge as-is + follow-up /
# revert hunk).
#
# Counter scope: per-edit-batch. Resets when edited_files mtime > counter
# mtime. Fresh edits = new diff batch = fresh budget. Mirrors the freshness
# pattern of codex-stop-gate's _dispatched / _handled markers
# (feedback_counter_scope_freshness_marker.md). Per-session counter would
# falsely cap multi-task sessions.
#
# `review` (gentler) is NOT counted — only adversarial. The motivation is
# adversarial's higher per-dispatch cost AND the loop pattern only being
# observed empirically against adversarial.
set -o pipefail

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty')

# Fast path: not an adversarial-review dispatch. The matcher must be precise
# enough to avoid catching unrelated commands that happen to mention the
# string — codex-companion.mjs path with adversarial-review subcommand.
case "$command" in
  *codex-companion.mjs*\ adversarial-review*) ;;
  *) exit 0 ;;
esac

session_id=$(echo "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

gate_dir="${CC_GATE_DIR_BASE:-/tmp/cc-gates}/$session_id"
mkdir -p "$gate_dir" 2>/dev/null || true

counter_file="$gate_dir/codex_adversarial_count"
edited_file="$gate_dir/edited_files"

# Per-edit-batch reset: new edits since last counted dispatch → fresh budget.
# When edited_file is missing, can't compare — leave counter as-is (fresh
# session has count=0 anyway).
if [ -f "$counter_file" ] && [ -f "$edited_file" ] && [ "$edited_file" -nt "$counter_file" ]; then
  rm -f "$counter_file"
fi

# Read counter (default 0; treat malformed as 0 to fail open, not closed —
# this gate exists to slow down loops, not to block on bookkeeping bugs).
count=0
if [ -f "$counter_file" ]; then
  raw=$(cat "$counter_file" 2>/dev/null || echo 0)
  case "$raw" in
    ''|*[!0-9]*) count=0 ;;
    *) count=$raw ;;
  esac
fi

# Cap = 2. The 3rd attempt is blocked. Tracker (codex-bash-tracker.sh)
# increments AFTER successful dispatch, so count=2 here means 2 prior
# adversarial dispatches landed; this would be the 3rd.
if [ "$count" -lt 2 ]; then
  exit 0
fi

# pbcopy the reset command so the user can paste-run after a deliberate
# scope-decision. Fail-soft per the lib helper.
reset_cmd="rm -f ${counter_file}"

# shellcheck disable=SC1091
source "$(dirname "$0")/_lib/pbcopy-bypass.sh"
pbcopy_bypass "$reset_cmd"

reason_text="🚫 Codex adversarial-review CAP reached (2 dispatches against this edit batch).

Per \`feedback_codex_loop_scope_mismatch.md\` — when each adversarial pass returns a new finding in a different layer of the same root concern, the fix is mis-scoped. Three options:

  (A) Keep iterating fixes — accept widening scope, force-reset the counter
  (B) Merge as-is + follow-up PR for the design work
  (C) Revert this hunk and re-author with proper scope

To force-reset the counter (only after explicit framing decision):
  ${reset_cmd}

(That command is already in your clipboard via pbcopy — paste-run after deciding A/B/C.)

The cap auto-resets when new edits land — fresh diff batch = fresh budget."

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": $(jq -Rs . <<<"$reason_text")
  }
}
EOF
exit 0
