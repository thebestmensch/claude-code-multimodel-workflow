#!/usr/bin/env bash
# Clears Stop-gate dedupe markers on PreCompact so that after context
# compaction evicts the original {decision:"block"} payload, the next Stop
# re-emits the FULL block message (not just the short reference that the
# in-session dedupe now uses).
#
# Why this exists (paired with _lib/stop-gate-emit.sh dedupe design):
#
# `emit_stop_block_dedupe` deduplicates repeat blocks within a session. On
# first emit per (hook,state) it writes the full payload; on subsequent
# emits it sends a SHORT reference like "[Stop-gate still blocked — see
# prior message for details]" carrying decision:"block" (so the gate stays
# effective; never silent). Two pressures reconciled:
#   - bypass prevention: gate always emits block (closes Codex slice-4 H1)
#   - context economy: full payload only emitted once per state per session
#
# Compaction breaks the second pressure: when CC summarizes earlier turns,
# the full block payload is evicted from context. The short reference then
# points at a "prior message" that the model can no longer see — useless.
#
# Fix: on PreCompact, wipe ${hook_name}_last_emit markers. The next Stop
# treats the state as first-seen and emits the FULL payload again. Dedupe
# then re-engages from that fresh full emit.
#
# Scope: only `*_last_emit` markers. Other gate state (skip-* touchfiles,
# edited_files, dispatch markers, .session_start timestamp) is durable
# across compaction and must not be wiped.

set -o pipefail

payload=$(cat 2>/dev/null || true)
session_id=$(printf '%s' "$payload" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$session_id" ] && exit 0

gate_dir="${CC_GATE_DIR_BASE:-/tmp/cc-gates}/$session_id"
[ -d "$gate_dir" ] || exit 0

# Wipe per-(hook,state) dedupe markers. Stop-gate scripts that emit via
# emit_stop_block_dedupe (codex-stop-gate, visual-qa-stop-gate,
# interaction-qa-stop-gate, mobile-pattern-stop-gate) write *_last_emit
# files. Other gate state (skip-* touchfiles, edited_files, dispatch markers,
# session-start timestamp) is preserved — those are deliberately durable
# across compaction.
find "$gate_dir" -maxdepth 1 -type f -name '*_last_emit' -delete 2>/dev/null || true

exit 0
