#!/usr/bin/env bash
# Hook: Cache Warmth Tracker (Stop)
# Records when the model finished responding so the cache-cold-warn hook
# can detect when the next user prompt is likely to miss the Anthropic
# prompt cache (5-minute TTL from last hit/write).
set -o pipefail

mkdir -p "$HOME/.claude/state"
date +%s > "$HOME/.claude/state/last_response_ts"

exit 0
