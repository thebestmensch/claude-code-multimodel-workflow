#!/usr/bin/env bash
# Codex plan-critique wrapper: second-seat cross-provider plan review.
#
# Sibling to codex-dispatch.sh, but for `task` mode (free-form prompt)
# instead of `review`/`adversarial-review` (git-diff only). Used to co-dispatch
# Codex alongside the Claude devils-advocate agent during brainstorming /
# writing-plans, per advisory-agents-dispatch.md.
#
# Why a separate wrapper: review modes resolve the prompt from `git diff` and
# refuse a clean tree (gap #4/#5/#6/#3 hygiene in codex-dispatch.sh). Plan text
# isn't a diff. `task` mode reads stdin or --plan-file, ignores git state, and
# does NOT trigger the codex-stop-gate (which keys off review jobs).
#
# Usage:
#   echo "<plan text>" | codex-plan-critique.sh
#   codex-plan-critique.sh --plan-file path/to/plan.md
#   codex-plan-critique.sh status [job-id]
#   codex-plan-critique.sh result [job-id]
#
# Exit codes:
#   0: job dispatched (job id printed to stdout)
#   2: pre-flight failure (no plan text, missing companion, etc.)

set -o errexit -o pipefail -o nounset

COMPANION_ROOT="${HOME}/.claude/plugins/cache/openai-codex/codex"
# Pick the newest companion version portably: numeric field sort orders multi-digit
# versions correctly (1.0.10 after 1.0.9) on BSD/macOS without GNU-only `sort -V`.
_ver=$(find "${COMPANION_ROOT}" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed "s#.*/##" | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1)
COMPANION="${COMPANION_ROOT}/${_ver}/scripts/codex-companion.mjs"
[ -n "${_ver:-}" ] && [ -f "${COMPANION}" ] || { echo "ERROR: codex-companion.mjs not found at ${COMPANION_ROOT}/*/scripts/codex-companion.mjs" >&2; exit 2; }

# Passthrough subcommands (status/result/cancel) so callers don't need a second wrapper.
case "${1:-}" in
  status|result|cancel)
    exec node "${COMPANION}" "$@"
    ;;
esac

# ---- argument parsing -------------------------------------------------------
PLAN_FILE=""
if [ "${1:-}" = "--plan-file" ]; then
  PLAN_FILE="${2:-}"
  [ -n "${PLAN_FILE}" ] || { echo "ERROR: --plan-file requires a path" >&2; exit 2; }
  [ -f "${PLAN_FILE}" ] || { echo "ERROR: plan file not found: ${PLAN_FILE}" >&2; exit 2; }
fi

# ---- read plan text ---------------------------------------------------------
if [ -n "${PLAN_FILE}" ]; then
  PLAN_TEXT=$(cat "${PLAN_FILE}")
else
  if [ -t 0 ]; then
    echo "ERROR: no plan text on stdin and no --plan-file given." >&2
    echo "Usage: echo \"<plan>\" | $(basename "$0")  OR  $(basename "$0") --plan-file <path>" >&2
    exit 2
  fi
  PLAN_TEXT=$(cat)
fi

if [ -z "${PLAN_TEXT//[[:space:]]/}" ]; then
  echo "ERROR: plan text is empty." >&2
  exit 2
fi

# ---- compose critique envelope ----------------------------------------------
WRAPPED_PROMPT_FILE=$(mktemp -t codex-plan-critique.XXXXXX)
trap 'rm -f "${WRAPPED_PROMPT_FILE}"' EXIT

cat >"${WRAPPED_PROMPT_FILE}" <<'EOF_HEADER'
You are an adversarial plan reviewer. Critique the plan below for missing
cases, hidden assumptions, scope creep, complexity, and risk.

READ-ONLY MODE - STRICT:
- Do NOT modify any files.
- Do NOT execute commands that change state.
- Do NOT propose code patches or diffs.
- You MAY read files and run read-only queries to verify claims in the plan.

Output: prioritized findings (Critical / Important / Minor). For each finding,
state (1) what is wrong or risky, (2) evidence or reasoning, (3) what the
plan author should reconsider, but do NOT write the fix yourself.

Value comes from cross-provider non-overlap signal: focus on what a Claude
devils-advocate reviewer is most likely to miss (data-flow edge cases, retry
and idempotency gaps, concurrency, ordering, failure modes under partial
success, hidden coupling).

--- PLAN TEXT FOLLOWS ---

EOF_HEADER

printf '%s\n' "${PLAN_TEXT}" >>"${WRAPPED_PROMPT_FILE}"

# ---- dispatch ---------------------------------------------------------------
echo "[dispatch] Starting Codex plan critique (task --effort high, background)..." >&2
DISPATCH_JSON=$(node "${COMPANION}" task \
  --background \
  --fresh \
  --effort high \
  --prompt-file "${WRAPPED_PROMPT_FILE}" \
  --json 2>&1) || {
  echo "ERROR: dispatch failed. Output:" >&2
  echo "${DISPATCH_JSON}" >&2
  exit 2
}

JOB_ID=$(printf '%s' "${DISPATCH_JSON}" | node -e '
  let buf = ""; process.stdin.on("data", d => buf += d);
  process.stdin.on("end", () => {
    try { const o = JSON.parse(buf); process.stdout.write(o.jobId || ""); }
    catch { process.stdout.write(""); }
  });
' 2>/dev/null || echo "")

if [ -z "${JOB_ID}" ]; then
  JOB_ID=$(printf '%s' "${DISPATCH_JSON}" | sed -nE 's/.*background as ([A-Za-z0-9-]+)\..*/\1/p' | head -1)
fi

if [ -z "${JOB_ID}" ]; then
  echo "ERROR: dispatch did not return a job id. Output:" >&2
  echo "${DISPATCH_JSON}" >&2
  exit 2
fi

echo "[dispatch] JOB_ID=${JOB_ID}" >&2
echo "  Poll:  $(basename "$0") status ${JOB_ID}" >&2
echo "  Fetch: $(basename "$0") result ${JOB_ID}" >&2
printf '%s\n' "${JOB_ID}"
