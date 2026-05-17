#!/usr/bin/env bash
# Stop hook, blocks completion when substantive code edits ship without a
# Codex *diff* review dispatch. Plan-mode dispatches (`codex_plan_dispatched`)
# are informational and do not satisfy this gate; only post-impl review of the
# working tree counts.
#
# Bypassed via codex_diff_dispatched marker (touched by codex-bash-tracker on
# successful review/adversarial-review invocations) or a reasoned
# skip_codex_gate file. Both must be FRESHER than the most recent tracked
# edit, staleness re-fires the gate (closes round-2 H1).
#
# SCOPE: this gate enforces review for files tracked via Edit|Write hooks
# (~/.claude/hooks/track-edited-files.sh) PLUS files surfaced at gate-fire
# time by the augmentation helper (`git diff --name-only HEAD`). The
# augmentation closes the Bash-mediated edit gap, `sed -i`, generators,
# formatters, and shell-driven patches now show up in edited_files via the
# git working-tree diff. Remaining gap: user-facing copy in *.md / *.json /
# *.yml / *.yaml / *.toml / *.txt is filtered out by both the upstream
# tracker AND the augmentation, even though codex-dispatch.md lists it as
# mandatory adversarial-review territory. Same discipline, the rule's Red
# Flags table tells you when to dispatch.
#
# Mirrors the visual-qa-stop-gate pattern. Decision of which Codex command to
# run (review vs adversarial-review) lives in ~/.claude/rules/codex-dispatch.md,
# not here, the hook only enforces "Codex diff review was dispatched at all."
set -o pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/_lib/stop-gate-emit.sh"

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

gate_dir="${CC_GATE_DIR_BASE:-/tmp/cc-gates}/$session_id"
edited_file="$gate_dir/edited_files"

# Augment edited_files with working-tree paths the Edit|Write tracker missed.
# Mode "worktree" → `git diff --name-only -z HEAD`, uncommitted modifications.
# Closes the Bash-mediated edit gap for sessions that edit via shell tools and
# stop without ever going through git commit (which would have triggered the
# pre-commit-gate's --cached augmentation). No-op outside a git repo.
mkdir -p "$gate_dir" 2>/dev/null || true
"$(dirname "$0")/lib/augment-edited-files.sh" "$gate_dir" worktree

[ -f "$edited_file" ] || exit 0

# Freshness check: gate releases only when BOTH _dispatched AND _handled are
# fresher than the most recent tracked edit. `edited_files` mtime updates on
# every append (one append per Edit|Write), so it tracks "time of most recent
# edit."
#
# Why both markers, not just _handled (closes stale-certification bug):
#   - `_dispatched` mtime = "moment dispatch started" (set only by
#     review/adversarial-review invocation, never by `result` retrieval).
#     Requiring it newer than every edit guarantees the dispatched diff
#     covered the current working tree, no edits snuck in between dispatch
#     and now.
#   - `_handled` mtime = "moment results landed in model context" (set by
#     sync review OR `result` retrieval). Requiring it newer than every edit
#     guarantees the findings are actually in context, not just enqueued.
#
# Failure paths this prevents:
#   1. edit → background dispatch → edit → result → Stop. Old code passed
#      because `_handled` (touched on result) was newer than the second edit.
#      Now `_dispatched` is older than the second edit → block.
#   2. Orphan `result` from a prior session: `_dispatched` absent in this
#      session's gate_dir → block. The tracker no longer fakes `_dispatched`
#      on orphan retrieval, so this case can't slip through.
#
# Closes Codex round-2 H1 (staleness bypass) and the round-? stale-cert bug.
if [ -f "$gate_dir/codex_diff_handled" ] \
   && [ -f "$gate_dir/codex_diff_dispatched" ] \
   && ! [ "$edited_file" -nt "$gate_dir/codex_diff_handled" ] \
   && ! [ "$edited_file" -nt "$gate_dir/codex_diff_dispatched" ]; then
  exit 0
fi

# Reasoned bypass, must name a real reason, not just "skip", and must be
# fresher than the latest edit (same staleness logic as the marker).
if [ -f "$gate_dir/skip_codex_gate" ] \
   && ! [ "$edited_file" -nt "$gate_dir/skip_codex_gate" ]; then
  reason=$(tr -d '[:space:]' < "$gate_dir/skip_codex_gate")
  if [ -n "$reason" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') | codex-stop-gate | $(cat "$gate_dir/skip_codex_gate")" >> "$gate_dir/bypass_log.txt"
    exit 0
  fi
fi

# Trust upstream filter (track-edited-files.sh): anything in edited_files is
# code-or-equivalent. If the list is non-empty, the gate fires.
code_files=$(sort -u "$edited_file" || true)
[ -z "$code_files" ] && exit 0

# Codex unavailability handling, runs ONLY after the handled-marker and
# skip-reason fast-paths above, so a fresh review or written bypass remains
# reachable even when codex auth lapses (closes Codex round-5 H1: previous
# ordering made the documented escape hatches unrecoverable when codex was
# unavailable).
#
# Host (interactive): fail closed. If codex auth lapses with no fresh marker
# or skip, the gate fires with decision: "block" so the operator sees it
# and either re-auths or writes a skip_codex_gate reason. Silent bypass on
# auth drift is exactly the failure mode the gate exists to prevent.
#
# Linear-agent container (headless `claude -p`): an explicit env-var opt-in
# (CODEX_GATE_FAIL_OPEN=1, set in docker-compose.yml) trades cross-provider
# review for liveness. Without it, decision: "block" would loop the agent
# until stop-token exhaustion. Subscription quota / 429s at API call time do
# NOT trip this branch: background dispatch is fire-and-forget at enqueue,
# so the marker is set before any OpenAI request.
if ! command -v codex >/dev/null 2>&1 || ! timeout 5 codex login status >/dev/null 2>&1; then
  if [ "${CODEX_GATE_FAIL_OPEN:-}" = "1" ]; then
    # Even with fail-open opted in, refuse to silently skip when a review was
    # dispatched but never retrieved into context, fail-opening here would
    # lose the dispatched review's findings entirely (closes Codex round-6
    # H1, round-7 H1). Detection: dispatched marker exists AND either no
    # handled marker, OR dispatched is newer than handled (fresh dispatch
    # superseded a prior handle). Edited_file freshness is deliberately NOT
    # part of this check, post-dispatch edits don't change the fact that
    # the dispatched review is unhandled. Force `result` retrieval (often
    # still works because the task queue is local state) or an explicit
    # skip reason naming the lost-review case.
    if [ -f "$gate_dir/codex_diff_dispatched" ] \
       && { ! [ -f "$gate_dir/codex_diff_handled" ] \
            || [ "$gate_dir/codex_diff_dispatched" -nt "$gate_dir/codex_diff_handled" ]; }; then
      lost_review_reason="🚫 STOP — codex unavailable, but a Codex diff review was dispatched and never retrieved. Silent fail-open here would lose those findings. Resolve one of:

1. Try retrieval anyway (task queue is local state — often still works after auth lapse): \`node \$HOME/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs result\`
2. Bypass with a reason naming the lost-review case: \`echo 'lost review: codex auth lapsed before result fetched' > ${gate_dir}/skip_codex_gate\`"
      state_hash="lost_review:$(printf '%s' "$code_files" | shasum | awk '{print $1}')"
      lost_review_bypass="echo 'lost-review: codex auth lapsed before result fetched' > ${gate_dir}/skip_codex_gate"
      emit_stop_block_dedupe "codex" "$gate_dir" "$state_hash" "$lost_review_reason" "$lost_review_bypass"
      exit 0
    fi
    # Audit log lands in CODEX_GATE_AUDIT_FILE if set (compose binds this to a
    # durable mount path, e.g. /home/agent/appdata/codex-gate-bypass.log on the
    # linear-agent container, closes Codex round-7 H1: bypass_log.txt under
    # /tmp/cc-gates is wiped on container restart, erasing the audit trail
    # exactly when fail-open silently let an unreviewed change ship). Falls
    # back to the session gate_dir for interactive host runs.
    audit_file="${CODEX_GATE_AUDIT_FILE:-$gate_dir/bypass_log.txt}"
    mkdir -p "$(dirname "$audit_file")" 2>/dev/null || true
    echo "$(date '+%Y-%m-%d %H:%M:%S') | codex-stop-gate | degraded (FAIL_OPEN=1): codex unavailable (cli or auth missing), gate skipped" >> "$audit_file"
    exit 0
  fi
  unavail_reason="🚫 STOP — codex CLI is missing or \`codex login status\` reports not-logged-in. The cross-provider review gate cannot be satisfied by dispatch.

Resolve one of:
1. Restore codex availability: \`codex login\` (or reinstall via \`claude plugin install codex@openai-codex\`).
2. Bypass with a written reason: \`echo 'codex unavailable, skipping review' > ${gate_dir}/skip_codex_gate\`
3. (Headless deployments only) Set CODEX_GATE_FAIL_OPEN=1 in the container env to opt into auditable fail-open behavior."
  state_hash="unavail:$(printf '%s' "$code_files" | shasum | awk '{print $1}')"
  unavail_bypass="echo 'codex unavailable, skipping review' > ${gate_dir}/skip_codex_gate"
  emit_stop_block_dedupe "codex" "$gate_dir" "$state_hash" "$unavail_reason" "$unavail_bypass"
  exit 0
fi

file_count=$(echo "$code_files" | wc -l | tr -d ' ')

# Truncate long file lists for display
display_files=$(echo "$code_files" | head -20)
truncated_note=""
if [ "$file_count" -gt 20 ]; then
  truncated_note="
… and $((file_count - 20)) more"
fi

# Heads-up if a diff review WAS dispatched but never retrieved into context.
# This is the cross-session-loss case: dispatch happened (background), session
# is ending, but no `result` call brought the findings into model context.
pending_note=""
if [ -f "$gate_dir/codex_diff_dispatched" ]; then
  pending_note="

⚠ A Codex diff review WAS dispatched but the results have not been retrieved into context. Run:
\`\`\`bash
node \$HOME/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs result
\`\`\`
to fetch — that satisfies the gate. If retrieval failed and you want to skip, write a reason to ${gate_dir}/skip_codex_gate."
fi

# Heads-up if a plan-mode dispatch happened but no diff dispatch yet
plan_note=""
if [ -f "$gate_dir/codex_plan_dispatched" ]; then
  plan_note="

Note: a Codex plan-mode dispatch (\`task\` / rescue subagent) was recorded earlier in this session. That counts as pre-impl review, not the post-impl diff review this gate requires."
fi

reason_text="🚫 STOP — ${file_count} code file(s) edited this session without a Codex cross-provider *diff* review landing in context.

Files:
${display_files}${truncated_note}${pending_note}${plan_note}

Read \`~/.claude/rules/codex-dispatch.md\` if you haven't this session, then choose:

1. **Default — dispatch adversarial review** (preferred):
   \`\`\`bash
   node \$HOME/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs adversarial-review --background
   \`\`\`

2. **Downgrade to gentler review** (only if you can articulate a reason that survives the Red Flags table):
   \`\`\`bash
   node \$HOME/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs review --background
   \`\`\`

3. **Bypass with a written reason** (must name *why* the gate is wrong here):
   \`\`\`bash
   echo 'reason' > ${gate_dir}/skip_codex_gate
   \`\`\`

Note: the path uses an unquoted glob (\`codex/*/scripts/...\`) so the shell expands it to the installed plugin version. Do NOT wrap the whole path in double quotes — that would prevent expansion. The leading \\\$HOME is fine; only the glob segment needs to stay unquoted.

Always announce in one line before invoking. Lazy = pick adversarial. Codex's value is non-overlap with Claude's blind spots — same-family reviewers don't substitute for it."

# State hash mixes file list + dispatch-marker presence so a freshly-dispatched-
# but-not-yet-handled review (which surfaces a different `pending_note`) re-emits.
pending_marker_state="0"
[ -f "$gate_dir/codex_diff_dispatched" ] && pending_marker_state="1"
[ -f "$gate_dir/codex_plan_dispatched" ] && pending_marker_state="${pending_marker_state}p"
state_hash="review:${pending_marker_state}:$(printf '%s' "$code_files" | shasum | awk '{print $1}')"
# pbcopy a templated skip invocation with inline valid-reason hints. Per
# codex-dispatch.md the valid bypass reasons are: doc-only, whitespace,
# generated, covered-by-X, config-only. User pastes, edits the REASON token,
# runs.
review_bypass="echo 'REASON: doc-only|whitespace|generated|covered-by-X|config-only' > ${gate_dir}/skip_codex_gate"
emit_stop_block_dedupe "codex" "$gate_dir" "$state_hash" "$reason_text" "$review_bypass"
