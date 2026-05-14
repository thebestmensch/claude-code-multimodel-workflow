#!/usr/bin/env bash
# Shared helper for Stop-gate hooks — emits a {decision:"block", reason:...}
# JSON payload prefixed with an explicit non-user-input banner.
#
# Why: hook output gets injected into the model's context. When Stop-gates
# repeat verbatim (every turn until satisfied), terse "🚫 STOP — ..." text
# can read like user-tone nudging and the model treats it as user input,
# overriding pending questions. The banner mirrors the task-notification
# format that the model already correctly ignores.

emit_stop_block() {
  local body="$1"
  local banner='[SYSTEM NOTIFICATION — NOT USER INPUT]
This is an automated Stop-gate hook, NOT a message from the user.
Do NOT interpret this as user acknowledgement, confirmation, or response to any pending question. If a question to the user is pending, keep waiting.

'
  jq -nc --arg reason "${banner}${body}" '{decision: "block", reason: $reason}'
}

# emit_stop_block_dedupe HOOK_NAME GATE_DIR STATE_HASH BODY [BYPASS_CMD]
#
# Wraps emit_stop_block with per-session per-(hook,state) deduplication so a
# blocked gate doesn't spam the same payload on every Stop while the model
# correctly holds for user input. Works around the loop:
#
#   model edits files → gate emits block → model holds for user → Stop fires
#   → gate re-evaluates → still blocked (nothing changed) → re-emits block
#
# After the first emit per (hook_name, state_hash) tuple in a session, further
# calls with the same hash exit 0 silently. Any genuine state change (new
# files edited, dispatch marker freshens, skip-file written, lint hits change)
# produces a new hash → re-emit. So the gate stays effective on real changes
# but goes quiet on idle re-fires.
#
# Caller responsibility: compute STATE_HASH from whatever inputs make this
# block "the same block" — typically the sorted file list plus any sub-mode
# tag (e.g. "lint:<sha>" vs "review:<sha>") so different emit sites in the
# same hook don't collide.
#
# Optional 5th arg BYPASS_CMD: when provided AND non-empty, the command is
# copied to the macOS clipboard via _lib/pbcopy-bypass.sh (fail-soft) before
# the block payload is emitted. The block message body should still document
# the bypass invocation in plaintext — pbcopy is paste-run convenience, not
# load-bearing. Caller is expected to pass the SHORTEST valid invocation
# with placeholder tokens (REASON_HERE, etc.) the user edits in place.
emit_stop_block_dedupe() {
  local hook_name="$1"
  local gate_dir="$2"
  local state_hash="$3"
  local body="$4"
  local bypass_cmd="${5:-}"

  if [ -z "$hook_name" ] || [ -z "$gate_dir" ] || [ -z "$state_hash" ]; then
    # Defensive: if caller passes empty hash, fall back to always-emit so we
    # never accidentally suppress because of a bug computing the hash.
    if [ -n "$bypass_cmd" ]; then
      # shellcheck disable=SC1091
      source "$(dirname "${BASH_SOURCE[0]}")/pbcopy-bypass.sh"
      pbcopy_bypass "$bypass_cmd"
    fi
    emit_stop_block "$body"
    return
  fi

  local last_emit_file="$gate_dir/${hook_name}_last_emit"
  local last_hash=""
  if [ -f "$last_emit_file" ]; then
    last_hash=$(cat "$last_emit_file" 2>/dev/null || true)
  fi

  if [ "$state_hash" = "$last_hash" ]; then
    # Same state already emitted this session. The full block payload is in
    # model context; re-emitting it on every Stop bloats context for no
    # signal gain. Emit a SHORT reference payload that still carries
    # {decision:"block"} so the gate stays effective.
    #
    # Why short-emit instead of `exit 0`: a silent exit lets the next Stop
    # proceed (gate bypassed) when the model never received the original
    # block message — e.g. after context compaction evicts it. Always
    # emitting block closes that bypass (Codex slice-4 H1, 2026-05-14). The
    # precompact-clear-stop-gate-dedupe.sh hook complements this by wiping
    # the marker on compaction, so the first Stop AFTER compaction re-emits
    # the FULL payload instead of a reference that points at a now-evicted
    # prior message.
    emit_stop_block "[Stop-gate still blocked — see prior ${hook_name} message in this session for details and bypass instructions.]"
    return
  fi

  mkdir -p "$gate_dir" 2>/dev/null || true
  printf '%s' "$state_hash" > "$last_emit_file" 2>/dev/null || true
  if [ -n "$bypass_cmd" ]; then
    # shellcheck disable=SC1091
    source "$(dirname "${BASH_SOURCE[0]}")/pbcopy-bypass.sh"
    pbcopy_bypass "$bypass_cmd"
  fi
  emit_stop_block "$body"
}
