#!/usr/bin/env bash
# mobile-pattern-stop-gate - Stop hook that blocks turn end when mobile-app
# files were edited but /code-review has not been dispatched since the
# latest mobile edit. Only relevant for projects that contain a mobile-app
# directory layout - graceful no-op otherwise.
#
# Mirrors visual-qa-stop-gate.sh. Two-step bypass via skip_mobile_pattern_gate.
#
# History: a regex-based PostToolUse lint hook (mobile-pattern-lint.sh) used
# to populate `mobile_lint_violations` and trigger a separate CRITICAL-block
# branch here. Removed 2026-05-08: the lint produced false positives on
# aliased imports the regex could not parse and added friction without
# catching anything the deeper reviewer wouldn't. Lint-equivalent enforcement
# now belongs in CI, not the stop gate.
set -o pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/_lib/stop-gate-emit.sh"

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

gate_dir="/tmp/cc-gates/$session_id"
edited_file="$gate_dir/edited_files"

[ -f "$edited_file" ] || exit 0

# Has the user requested a reasoned skip?
if [ -f "$gate_dir/skip_mobile_pattern_gate" ]; then
  reason=$(tr -d '[:space:]' < "$gate_dir/skip_mobile_pattern_gate")
  if [ -n "$reason" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') | mobile-pattern-stop-gate | $(cat "$gate_dir/skip_mobile_pattern_gate")" >> "$gate_dir/bypass_log.txt"
    exit 0
  fi
fi

# Filter for in-scope mobile-app files
mobile_files=$(sort -u "$edited_file" | grep -E 'mobile-app/.*\.(tsx|ts)$' \
  | grep -vE '(__tests__|__mocks__|\.test\.|\.spec\.|\.d\.ts$|\.generated\.ts$|/\.maestro/|/\.rnstorybook/)' \
  || true)

[ -z "$mobile_files" ] && exit 0

file_count=$(echo "$mobile_files" | wc -l | tr -d ' ')

# Deeper review dispatch (agent or /code-review)
#
# Staleness pivot must be **mobile-only**. Earlier versions used `edited_files`
# mtime as the pivot, but that file is appended on every edit including non-
# mobile work (~/.claude/hooks/, memory files, etc.), so any later edit
# anywhere in the repo invalidated a fresh mobile dispatch marker. Real fix:
# pivot on the most recent per-file edit_count marker that maps to a mobile
# file currently in `mobile_files`. Per-file markers come from
# investigate-before-acting.sh (PreToolUse hook on Edit|Write).
stat_mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

# Most recent dispatch marker (newest of any wins).
marker_mtime=0
for marker in "$gate_dir/mobile_pattern_dispatched" "$gate_dir/code_review_dispatched"; do
  if [ -f "$marker" ]; then
    m_mtime=$(stat_mtime "$marker")
    if [ "$m_mtime" -gt "$marker_mtime" ]; then
      marker_mtime=$m_mtime
    fi
  fi
done

# Most recent edit time among the currently-listed mobile files.
latest_mobile_edit=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  norm=$(echo "$f" | sed 's/[^a-zA-Z0-9]/_/g')
  ec_file="$gate_dir/edit_count_$norm"
  [ -f "$ec_file" ] || continue
  e_mtime=$(stat_mtime "$ec_file")
  if [ "$e_mtime" -gt "$latest_mobile_edit" ]; then
    latest_mobile_edit=$e_mtime
  fi
done <<< "$mobile_files"

# Pass when there's a marker AND it's at or newer than the latest mobile edit.
# When `latest_mobile_edit=0` (no per-file marker for any listed mobile file in
# this session, typical when files were edited in a prior session and only
# carry over via `edited_files`), trust the dispatch marker alone: the listed
# files weren't touched this session, so a marker dated to *any* prior dispatch
# this session covers them.
if [ "$marker_mtime" -gt 0 ] && [ "$marker_mtime" -ge "$latest_mobile_edit" ]; then
  exit 0
fi

reason_text=$(cat <<EOF
🚫 STOP - $file_count mobile-app file(s) edited this session without a fresh deeper review.

Files:
$mobile_files

Dispatch /code-review on the diff. A code reviewer catches semantic patterns (Pressable nesting, worklet correctness, navigation footguns) the type checker cannot.

If the deeper review is genuinely inapplicable (e.g., trivial type-only change, comment fix), request bypass:
  echo "reason" > $gate_dir/skip_mobile_pattern_gate
  Then user approves: ! echo approved > $gate_dir/bypass_approved
EOF
)

state_hash="review:$(printf '%s' "$mobile_files" | shasum | awk '{print $1}')"
# pbcopy a templated skip invocation with inline valid-reason hints. Same
# shape as codex-stop-gate's review_bypass; caller pastes and edits REASON.
mobile_pattern_bypass="echo 'REASON: type-only|comment-fix|trivial' > ${gate_dir}/skip_mobile_pattern_gate"
emit_stop_block_dedupe "mobile_pattern" "$gate_dir" "$state_hash" "$reason_text" "$mobile_pattern_bypass"
