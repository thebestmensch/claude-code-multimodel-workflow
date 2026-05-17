#!/usr/bin/env bash
# PostToolUse hook (Bash), touches Codex dispatch markers when a Bash command
# successfully invokes the codex-companion.mjs review/adversarial-review/task/
# result helpers. The /codex:* slash commands are user-only
# (disable-model-invocation: true), so the model dispatches Codex by calling
# the underlying script via Bash. This hook detects that and tells the
# codex-stop-gate the dispatch (and/or retrieval) happened.
#
# Three markers, by design:
#   codex_diff_dispatched, set ONLY when a `review` / `adversarial-review`
#                           runs (sync OR background dispatch). mtime =
#                           "moment dispatch started." `result` retrieval does
#                           NOT touch this marker, orphan retrieval (dispatch
#                           in a prior session) must NOT fake dispatch in the
#                           current session, or it would silently certify the
#                           current session's unreviewed edits.
#   codex_diff_handled   , set when review results LAND in model context:
#                           sync review (stdout has header) OR `result`
#                           retrieval (stdout has header). Background-only
#                           dispatch leaves this UNSET, the gate stays armed
#                           until `result` retrieves the findings.
#                           Stop-gate releases only when BOTH _dispatched
#                           AND _handled are fresher than the most recent
#                           edit (prevents the edit→dispatch→edit→result
#                           stale-certification path).
#   codex_plan_dispatched, set on `task` (used by codex:codex-rescue subagent
#                           for plan-mode / diagnosis review pre-impl).
#                           Informational only; does not satisfy the stop gate.
#
# Hardened against substring spoofing via the tool_input.command field: that
# field is what CC actually dispatched (not arbitrary echoed text), so
# matching `codex-companion.mjs <subcommand>` against it is robust on its own.
# The exit_code=0 / interrupted=false guards below close the failed-wrapper
# spoof path.
#
# `_dispatched` (review / adversarial-review) fires on command-match alone —
# stdout banner is NOT required, because codex-companion.mjs 1.0.4
# `handleReviewCommand` ignores `--background` and runs sync, and CC's
# auto-background heuristic captures PostToolUse before the banner reaches
# stdout for long-running invocations. Requiring stdout would silently miss
# legitimate dispatches.
#
# `_handled` still requires the review-result header, it certifies that the
# review TEXT landed in the model's context, not just that dispatch happened.
#
# Silent bookkeeper, no output.
set -o pipefail

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
command=$(echo "$input" | jq -r '.tool_input.command // empty')
interrupted=$(echo "$input" | jq -r '.tool_response.interrupted // false')
exit_code=$(echo "$input" | jq -r '.tool_response.exit_code // empty')
stdout=$(echo "$input" | jq -r '.tool_response.stdout // ""')

[ -z "$session_id" ] && exit 0
[ -z "$command" ] && exit 0
[ "$interrupted" = "true" ] && exit 0
# If exit_code is present in tool_response, require success. If absent, the
# interrupted check above is the strongest signal we have. Closes Codex round-3
# High: a failed wrapper that printed Codex banner output should not certify
# dispatch.
[ -n "$exit_code" ] && [ "$exit_code" != "0" ] && exit 0

# Pre-classify stdout for the `_handled` decision below. `_dispatched` fires
# from command-match alone, so stdout-banner detection is no longer a
# precondition for reaching the case block.
has_review_header=0
case "$stdout" in
  *"# Codex Adversarial Review"*|*"# Codex Review"*) has_review_header=1 ;;
esac

gate_dir="${CC_GATE_DIR_BASE:-/tmp/cc-gates}/$session_id"
[ -d "$gate_dir" ] || mkdir -p "$gate_dir"

# Match codex-companion.mjs invocations and route to the appropriate marker.
# `setup`, `status`, `cancel` are plumbing, never satisfy the gate.
#
# adversarial-review and review are split into two case branches: both touch
# the same dispatch/handled markers, but only adversarial increments the
# loop-scope cap counter (codex_adversarial_count, read by
# codex-adversarial-cap.sh). The gentler `review` is exempt, the loop
# pattern documented in feedback_codex_loop_scope_mismatch.md is empirically
# adversarial-only, and the cap exists to break that specific loop.
case "$command" in
  *codex-companion.mjs*\ adversarial-review*)
    touch "$gate_dir/codex_diff_dispatched"
    # Sync path (header in stdout) → results already in context, _handled fires.
    # Background path (only banner) → _handled stays untouched, awaiting `result`.
    [ "$has_review_header" = "1" ] && touch "$gate_dir/codex_diff_handled"
    # Per-edit-batch counter for the adversarial-review cap. Reset semantics
    # live in codex-adversarial-cap.sh (compares counter mtime vs edited_file
    # mtime); this branch only increments on successful dispatch.
    counter_file="$gate_dir/codex_adversarial_count"
    count=0
    if [ -f "$counter_file" ]; then
      raw=$(cat "$counter_file" 2>/dev/null || echo 0)
      case "$raw" in
        ''|*[!0-9]*) count=0 ;;
        *) count=$raw ;;
      esac
    fi
    echo $((count + 1)) > "$counter_file"
    ;;
  *codex-companion.mjs*\ review*)
    touch "$gate_dir/codex_diff_dispatched"
    [ "$has_review_header" = "1" ] && touch "$gate_dir/codex_diff_handled"
    ;;
  *codex-companion.mjs*\ result*)
    # Retrieval brings results into context. Header check guards against
    # `result` invocations that returned non-review content (status-only output
    # from `result` for plan-mode tasks would lack the review header).
    #
    # Only `_handled` is touched here, never `_dispatched`. `_dispatched`
    # mtime is reserved for "moment dispatch started" so the stop-gate can
    # require dispatch-time > most-recent-edit. Orphan retrieval (no prior
    # dispatch in this session) leaves `_dispatched` absent, which makes the
    # gate block, exactly the right outcome (closes stale-certification
    # bug: `result` alone must not satisfy the gate for unreviewed edits).
    if [ "$has_review_header" = "1" ]; then
      touch "$gate_dir/codex_diff_handled"
    fi
    ;;
  *codex-companion.mjs*\ task*)
    touch "$gate_dir/codex_plan_dispatched"
    ;;
esac

exit 0
