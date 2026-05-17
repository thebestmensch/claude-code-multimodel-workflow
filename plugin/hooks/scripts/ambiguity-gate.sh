#!/usr/bin/env bash
# Hook: Ambiguity Gate (PreToolUse on ExitPlanMode)
# Blocks ExitPlanMode when the plan text contains too many ambiguity markers.
# Mechanical heuristic only: counts hedging words / unresolved-decision markers.
# Pattern borrowed from ouroboros: spec-first, refuse to code until ambiguity collapses.
#
# Skip for trivial plans (< 600 chars AND < 3 numbered tasks).
# Bypass: touch /tmp/cc-gates/$SESSION/skip_ambiguity_gate
set -o pipefail

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

gate_dir="/tmp/cc-gates/$session_id"
mkdir -p "$gate_dir"

# Explicit bypass → allow
[ -f "$gate_dir/skip_ambiguity_gate" ] && exit 0

plan=$(echo "$input" | jq -r '.tool_input.plan // empty')
plan_len=${#plan}
task_count=$(echo "$plan" | grep -cE '^[[:space:]]*[0-9]+\.' || true)

# Skip trivial plans: same complexity gate as devils-advocate-plan-gate.sh
if [ "$task_count" -lt 3 ] && [ "$plan_len" -lt 600 ]; then
  exit 0
fi

# Lowercase for matching
lower=$(printf "%s" "$plan" | tr '[:upper:]' '[:lower:]')

# Count ambiguity markers: each pattern represents an unresolved decision.
# Patterns are intentionally narrow to avoid false positives on prose.
m_tbd=$(printf "%s" "$lower" | grep -oE '\btbd\b' | wc -l | tr -d ' ')
m_todo=$(printf "%s" "$lower" | grep -oE '\btodo\b' | wc -l | tr -d ' ')
m_decide_later=$(printf "%s" "$lower" | grep -oE '(decide later|figure (this|it) out later|we will see|we.ll see|punt on)' | wc -l | tr -d ' ')
m_hedge=$(printf "%s" "$lower" | grep -oE '\b(maybe|probably|might|possibly)\b' | wc -l | tr -d ' ')
m_uncertain=$(printf "%s" "$lower" | grep -oE '(not sure|unclear|undecided|depends on|tbd:|open question)' | wc -l | tr -d ' ')
m_question=$(printf "%s" "$plan" | grep -oE '\?{2,}' | wc -l | tr -d ' ')

total=$((m_tbd + m_todo + m_decide_later + m_hedge + m_uncertain + m_question))

# Threshold scales with plan length: bigger plans tolerate more hedging
# Floor of 5 markers; one extra allowed per 500 chars beyond 600
threshold=5
if [ "$plan_len" -gt 600 ]; then
  extra=$(( (plan_len - 600) / 500 ))
  threshold=$((threshold + extra))
fi

if [ "$total" -le "$threshold" ]; then
  exit 0
fi

# Build a readable breakdown for the deny message
parts=""
[ "$m_tbd" -gt 0 ] && parts="$parts tbd=$m_tbd"
[ "$m_todo" -gt 0 ] && parts="$parts todo=$m_todo"
[ "$m_decide_later" -gt 0 ] && parts="$parts decide-later=$m_decide_later"
[ "$m_hedge" -gt 0 ] && parts="$parts hedge=$m_hedge"
[ "$m_uncertain" -gt 0 ] && parts="$parts uncertain=$m_uncertain"
[ "$m_question" -gt 0 ] && parts="$parts unresolved-?=$m_question"

reason="Plan ambiguity over threshold (markers=$total, threshold=$threshold, breakdown:$parts). Resolve hedging / TBD / decide-later items before exiting plan mode; each one is a decision the user has not made yet. Options: (a) ask the user to resolve them, (b) dispatch /lateral if you're stuck on which way to go, (c) bypass with: touch $gate_dir/skip_ambiguity_gate (only if you have a written reason these markers are intentional)."

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "$reason"
  }
}
EOF
exit 0
