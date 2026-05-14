#!/usr/bin/env bash
# Stop hook — blocks completion when UI files were edited without visual QA.
# Bypassed via visual_qa_dispatched marker (touched by dispatch-tracker when /visual-qa runs)
# or a reasoned skip_visual_qa_gate file.
set -o pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/_lib/stop-gate-emit.sh"

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

gate_dir="/tmp/cc-gates/$session_id"
edited_file="$gate_dir/edited_files"

[ -f "$edited_file" ] || exit 0
[ -f "$gate_dir/visual_qa_dispatched" ] && exit 0

# Reasoned bypass
if [ -f "$gate_dir/skip_visual_qa_gate" ]; then
  reason=$(tr -d '[:space:]' < "$gate_dir/skip_visual_qa_gate")
  if [ -n "$reason" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') | visual-qa-stop-gate | $(cat "$gate_dir/skip_visual_qa_gate")" >> "$gate_dir/bypass_log.txt"
    exit 0
  fi
fi

ui_files=$(sort -u "$edited_file" | grep -E 'mobile-app/(components|app|ui|screens)/' \
  | grep -E '\.(tsx|ts)$' \
  | grep -vE '(__tests__|\.test\.|\.spec\.|\.d\.ts$|types\.ts$|\.generated\.ts$|constants/|hooks/|utils/)' \
  || true)

[ -z "$ui_files" ] && exit 0

file_count=$(echo "$ui_files" | wc -l | tr -d ' ')

reason_text="🚫 STOP — ${file_count} UI file(s) edited this session without visual QA.

Files:
${ui_files}

Run /visual-qa on the affected screen(s) — screenshot + review.

If the changes are truly non-visual (pure refactor, no rendered output change), write a reason:
  echo 'reason' > ${gate_dir}/skip_visual_qa_gate

Do not skip by default. The user wants every UI change visually inspected."

state_hash="ui:$(printf '%s' "$ui_files" | shasum | awk '{print $1}')"
# pbcopy a templated skip invocation with inline valid-reason hints. UI
# bypass is reserved for genuinely non-visual changes.
visual_qa_bypass="echo 'REASON: pure-refactor|no-render-change|non-visual' > ${gate_dir}/skip_visual_qa_gate"
emit_stop_block_dedupe "visual_qa" "$gate_dir" "$state_hash" "$reason_text" "$visual_qa_bypass"
