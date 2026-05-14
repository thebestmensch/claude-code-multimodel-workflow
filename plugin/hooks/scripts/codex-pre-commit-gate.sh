#!/usr/bin/env bash
# Pre-commit gate — blocks `git commit` when substantive code edits are about
# to be committed without a Codex cross-provider *diff* review having landed
# in context. Mirrors the freshness + bypass semantics of codex-stop-gate.sh
# but fires at the right moment: BEFORE the commit, not at session end.
#
# Why this exists alongside codex-stop-gate:
# The stop-gate only fires on Stop. By then commits + pushes + merges have
# already happened, and `codex-companion.mjs` evaluates the working tree —
# which no longer contains the changes that just shipped. The dispatched
# review reads garbage (clean tree or unrelated drift) and approves it,
# satisfying the gate while shipping unreviewed code. This hook closes that
# gap by enforcing the same dispatch+freshness invariant at PreToolUse.
#
# Bypass mechanism: same `skip_codex_gate` file as the stop-gate, with the
# same staleness logic. Reuse keeps the user-facing UX and documentation
# consistent across both moments.
#
# Bash-mediated edit closure: prior to firing, runs the augmentation helper
# against `git diff --cached` so files staged via `sed -i` / generators /
# `tee` / shell-driven patches are appended to edited_files. The downstream
# freshness logic then treats them as real edits — closing the gap that
# previously left them invisible. Edit|Write paths still come through
# track-edited-files.sh; this only adds what the tool tracker missed.
#
# Matcher: ~/.claude/hooks/lib/match-git-commit.py (shared with pre-commit-gate.sh).
set -o pipefail

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty')

matches=$(/usr/bin/python3 "$(dirname "$0")/lib/match-git-commit.py" "$command")
[ "$matches" != "match" ] && exit 0

session_id=$(echo "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

gate_dir="${CC_GATE_DIR_BASE:-/tmp/cc-gates}/$session_id"
mkdir -p "$gate_dir" 2>/dev/null || true
edited_file="$gate_dir/edited_files"

# Augment edited_files with paths the Edit|Write tracker missed. Run BOTH
# cached AND worktree:
#   cached   → catches plain `git commit` (pre-staged via `git add`).
#   worktree → catches `git commit -a` / `-am` / `--all` (git stages tracked
#              modifications during the commit, *after* PreToolUse — at
#              hook-fire time those edits aren't in the index yet, so cached
#              alone misses them). Worktree mode also picks up untracked
#              files created by generators / `tee > new.py`.
# Filter rules match track-edited-files.sh in both modes.
#
# Repo discovery: the augmenter uses its own cwd to find the repo. When the
# user's bash command is `cd X && git commit` or `git -C X commit`, the
# augmenter inherits the HARNESS cwd (not the bash subprocess's cwd) and
# evaluates the wrong repo — empty staged diff → silent gate bypass. Extract
# the target repo from $command and cd into it before invoking the augmenter.
# Defaults to $PWD when the command has neither `cd` nor `-C` (the original
# behavior). Closes Codex slice-4 H2 finding.
repo_dir=$(/usr/bin/python3 "$(dirname "$0")/lib/extract-git-repo-dir.py" "$command")
repo_dir="${repo_dir:-$PWD}"
(cd "$repo_dir" 2>/dev/null && "$(dirname "$0")/lib/augment-edited-files.sh" "$gate_dir" cached)
(cd "$repo_dir" 2>/dev/null && "$(dirname "$0")/lib/augment-edited-files.sh" "$gate_dir" worktree)

[ -f "$edited_file" ] || exit 0

# Same freshness gate as codex-stop-gate.sh: BOTH dispatched AND handled
# markers must be fresher than the most recent tracked edit. Logic copied
# verbatim — keep them in lockstep so the two gates can never disagree about
# what counts as "covered".
if [ -f "$gate_dir/codex_diff_handled" ] \
   && [ -f "$gate_dir/codex_diff_dispatched" ] \
   && ! [ "$edited_file" -nt "$gate_dir/codex_diff_handled" ] \
   && ! [ "$edited_file" -nt "$gate_dir/codex_diff_dispatched" ]; then
  exit 0
fi

# Reasoned bypass — must name a real reason, must be fresher than the latest
# edit. Same file as the stop-gate (skip_codex_gate) so a single bypass
# satisfies both moments.
if [ -f "$gate_dir/skip_codex_gate" ] \
   && ! [ "$edited_file" -nt "$gate_dir/skip_codex_gate" ]; then
  reason=$(tr -d '[:space:]' < "$gate_dir/skip_codex_gate")
  if [ -n "$reason" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') | codex-pre-commit-gate | $(cat "$gate_dir/skip_codex_gate")" >> "$gate_dir/bypass_log.txt"
    exit 0
  fi
fi

# Trust upstream filter (track-edited-files.sh + augmentation): anything in
# edited_files is code-or-equivalent. If the list is non-empty, the gate fires.
code_files=$(sort -u "$edited_file" || true)
[ -z "$code_files" ] && exit 0

# Codex unavailability handling — same fail-closed-by-default logic as the
# stop-gate. Without an explicit FAIL_OPEN opt-in, refuse to silently bypass
# when codex is not callable.
# Internal probe budget kept under the hook's outer timeout so the script can
# always emit its deterministic deny/audit JSON. Outer hook timeout is set to
# 10s in settings.json; reserve ~7s for response work.
if ! command -v codex >/dev/null 2>&1 || ! timeout 3 codex login status >/dev/null 2>&1; then
  if [ "${CODEX_GATE_FAIL_OPEN:-}" = "1" ]; then
    audit_file="${CODEX_GATE_AUDIT_FILE:-$gate_dir/bypass_log.txt}"
    mkdir -p "$(dirname "$audit_file")" 2>/dev/null || true
    echo "$(date '+%Y-%m-%d %H:%M:%S') | codex-pre-commit-gate | degraded (FAIL_OPEN=1): codex unavailable, gate skipped" >> "$audit_file"
    exit 0
  fi
  unavail_reason="🚫 Commit blocked: codex CLI is missing or \`codex login status\` reports not-logged-in. The cross-provider review gate cannot be satisfied by dispatch.

Resolve one of:
1. Restore codex availability: \`codex login\` (or reinstall via \`claude plugin install codex@openai-codex\`).
2. Bypass with a written reason: \`echo 'codex unavailable, skipping review' > ${gate_dir}/skip_codex_gate\`
3. (Headless deployments only) Set CODEX_GATE_FAIL_OPEN=1 in the container env to opt into auditable fail-open behavior."
  # shellcheck disable=SC1091
  source "$(dirname "$0")/_lib/pbcopy-bypass.sh"
  pbcopy_bypass "echo 'codex unavailable, skipping review' > ${gate_dir}/skip_codex_gate"
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": $(jq -Rs . <<<"$unavail_reason")
  }
}
EOF
  exit 0
fi

file_count=$(echo "$code_files" | wc -l | tr -d ' ')
display_files=$(echo "$code_files" | head -20)
truncated_note=""
if [ "$file_count" -gt 20 ]; then
  truncated_note="
… and $((file_count - 20)) more"
fi

# Heads-up if a diff review WAS dispatched but never retrieved.
pending_note=""
if [ -f "$gate_dir/codex_diff_dispatched" ]; then
  pending_note="

⚠ A Codex diff review WAS dispatched but the results have not been retrieved into context. Run:
\`\`\`bash
node \$HOME/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs result
\`\`\`
to fetch — that satisfies the gate."
fi

reason_text="🚫 Commit blocked: ${file_count} code file(s) edited this session without a Codex cross-provider *diff* review landing in context.

Files:
${display_files}${truncated_note}${pending_note}

This is the right moment to dispatch — \`codex-companion.mjs\` reviews the working tree, so dispatching BEFORE the commit lets it actually see the changes. Dispatching after \`git commit\` reads stale state (changes in HEAD, working tree clean) and silently approves nothing.

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
   echo 'REASON: doc-only|whitespace|generated|covered-by-X|config-only' > ${gate_dir}/skip_codex_gate
   \`\`\`

Note: the path uses an unquoted glob (\`codex/*/scripts/...\`) so the shell expands it to the installed plugin version. Do NOT wrap the whole path in double quotes — that would prevent expansion. The leading \\\$HOME is fine; only the glob segment needs to stay unquoted."

# shellcheck disable=SC1091
source "$(dirname "$0")/_lib/pbcopy-bypass.sh"
pbcopy_bypass "echo 'REASON: doc-only|whitespace|generated|covered-by-X|config-only' > ${gate_dir}/skip_codex_gate"

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": $(jq -Rs . <<<"$reason_text")
  }
}
EOF
exit 0
