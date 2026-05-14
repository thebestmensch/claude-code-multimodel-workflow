#!/usr/bin/env bash
# Stop hook — blocks completion when interaction-related code was edited without interaction QA.
# Platform-aware: web pseudo-classes/transitions, RN touch handlers.
set -o pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/_lib/stop-gate-emit.sh"

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

gate_dir="/tmp/cc-gates/$session_id"
edited_file="$gate_dir/edited_files"

[ -f "$edited_file" ] || exit 0
[ -f "$gate_dir/interaction_qa_dispatched" ] && exit 0

# Reasoned bypass
if [ -f "$gate_dir/skip_interaction_qa_gate" ]; then
  reason=$(tr -d '[:space:]' < "$gate_dir/skip_interaction_qa_gate")
  if [ -n "$reason" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') | interaction-qa-stop-gate | $(cat "$gate_dir/skip_interaction_qa_gate")" >> "$gate_dir/bypass_log.txt"
    exit 0
  fi
fi

web_patterns=':hover|:active|:focus|transition:|animation:|@keyframes'
mobile_patterns='Pressable|onPress|onPressIn|onPressOut|onLongPress|TouchableOpacity|TouchableHighlight'

web_files=$(grep -E '\.(css|scss|less|html|tsx|jsx)$' "$edited_file" | grep -vE 'mobile-app/' || true)
mobile_files=$(grep -E 'mobile-app/.*\.(tsx|ts)$' "$edited_file" || true)

web_hits=""
mobile_hits=""

if [ -n "$web_files" ]; then
  web_hits=$(echo "$web_files" | xargs -I{} sh -c '[ -f "{}" ] && grep -lE "'"$web_patterns"'" "{}" 2>/dev/null' || true)
fi
if [ -n "$mobile_files" ]; then
  mobile_hits=$(echo "$mobile_files" | xargs -I{} sh -c '[ -f "{}" ] && grep -lE "'"$mobile_patterns"'" "{}" 2>/dev/null' || true)
fi

all_hits=$(printf '%s\n%s\n' "$web_hits" "$mobile_hits" | grep -v '^$' | sort -u || true)

[ -z "$all_hits" ] && exit 0

hit_count=$(echo "$all_hits" | wc -l | tr -d ' ')

reason_text="🚫 STOP — ${hit_count} file(s) with interaction patterns edited without interaction QA.

Files:
${all_hits}

Run /interaction-qa on the affected screen(s). Interaction bugs (broken hover, missing focus rings, dead touch targets) are invisible without explicit testing.

If these edits don't affect rendered interaction states, write a reason:
  echo 'reason' > ${gate_dir}/skip_interaction_qa_gate"

state_hash="interaction:$(printf '%s' "$all_hits" | shasum | awk '{print $1}')"
emit_stop_block_dedupe "interaction_qa" "$gate_dir" "$state_hash" "$reason_text"
