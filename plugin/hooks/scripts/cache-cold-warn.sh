#!/usr/bin/env bash
# Hook — Cache Cold Warning (UserPromptSubmit)
# Warns when the time since the last model response exceeds the 5-minute
# Anthropic prompt cache TTL, so the user (and Claude) know this turn
# pays full system-prompt + tool-def token cost.
#
# Threshold: 270s (45s of safety margin under the 300s TTL).
set -o pipefail

TS_FILE="$HOME/.claude/state/last_response_ts"
[ -f "$TS_FILE" ] || exit 0

LAST=$(cat "$TS_FILE" 2>/dev/null)
[ -z "$LAST" ] && exit 0

NOW=$(date +%s)
ELAPSED=$((NOW - LAST))

if [ "$ELAPSED" -ge 270 ]; then
  # Format elapsed as Mm Ss for readability
  MM=$((ELAPSED / 60))
  SS=$((ELAPSED % 60))
  echo "⏱  Anthropic prompt cache likely cold (${MM}m${SS}s since last response, TTL≈5m). This turn will re-cache the system prompt and tool definitions; subsequent turns within 5 min will hit cache."
fi

exit 0
