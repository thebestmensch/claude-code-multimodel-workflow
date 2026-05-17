#!/usr/bin/env bash
# Codex dispatch wrapper: pre-flight git hygiene + hang-bail polling.
#
# Closes the manual-discipline gaps documented in ~/.claude/rules/codex-dispatch.md:
#   - gap #5: staged-but-not-committed diff invisible to Codex     (auto-unstaged)
#   - gap #6: untracked files invisible to git diff                 (auto-marked intent-to-add)
#   - gap #7: hung jobs burning 10+ minutes in `verifying` phase   (auto-cancelled at 4.5 min silent log)
#
# Gaps NOT closed mechanically (still require operator judgment):
#   - gap #3: cwd vs. sibling-repo edits   (the operator must cd into the right repo first)
#   - gap #4: dispatch BEFORE commit       (the operator must not commit first)
#   - gap #8: stale gate marker post-add   (write bypass with completed-review evidence)
#
# Usage:
#   codex-dispatch.sh [--no-wait] adversarial-review
#   codex-dispatch.sh [--no-wait] review
#   codex-dispatch.sh status [job-id]
#   codex-dispatch.sh result [job-id]
#   codex-dispatch.sh cancel <job-id>
#
# Exit codes:
#   0: review completed; result printed to stdout
#   2: pre-flight failure (no diff, missing companion, etc.)
#   3: hang-bail fired (job cancelled; bypass required)

set -o errexit -o pipefail -o nounset

COMPANION_GLOB="${HOME}/.claude/plugins/cache/openai-codex/codex/*/scripts/codex-companion.mjs"
# shellcheck disable=SC2086  # intentional glob expansion
COMPANION=$(ls -1 $COMPANION_GLOB 2>/dev/null | sort -V | tail -1)
[ -n "${COMPANION:-}" ] || { echo "ERROR: codex-companion.mjs not found at ${COMPANION_GLOB}" >&2; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required (brew install jq)" >&2; exit 2; }

# ---- subcommand passthrough -------------------------------------------------
case "${1:-}" in
  status|result|cancel)
    exec node "${COMPANION}" "$@"
    ;;
esac

# ---- argument parsing -------------------------------------------------------
NO_WAIT=0
if [ "${1:-}" = "--no-wait" ]; then
  NO_WAIT=1
  shift
fi
MODE="${1:-adversarial-review}"
case "${MODE}" in
  adversarial-review|review) ;;
  *) echo "ERROR: mode must be 'adversarial-review' or 'review' (got: ${MODE})" >&2; exit 2 ;;
esac

git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
  || { echo "ERROR: cwd is not inside a git work tree (gap #3: cd into the repo whose diff you want reviewed)" >&2; exit 2; }

# ---- pre-flight: gap #5 (staged) --------------------------------------------
if ! git diff --cached --quiet; then
  staged_files=$(git diff --cached --name-only | head -5 | tr '\n' ' ')
  echo "[pre-flight] Unstaging changes (Codex needs working-tree diff). Files: ${staged_files}…"
  git restore --staged -- .
fi

# ---- pre-flight: gap #6 (untracked) ------------------------------------------
# Exclude nested git worktrees / submodules: any directory containing .git is
# a separate repo and intent-to-adding it would either fail or sweep unrelated
# content into the review path (Codex 2026-05-15 finding).
UNTRACKED_RAW=$(git ls-files --others --exclude-standard)
UNTRACKED=""
SKIPPED_NESTED=""
if [ -n "${UNTRACKED_RAW}" ]; then
  while IFS= read -r p; do
    [ -z "$p" ] && continue
    # Strip trailing slash for filesystem checks
    bare=${p%/}
    if [ -e "${bare}/.git" ]; then
      SKIPPED_NESTED+="${p}"$'\n'
      continue
    fi
    UNTRACKED+="${p}"$'\n'
  done <<<"${UNTRACKED_RAW}"
fi

if [ -n "${SKIPPED_NESTED}" ]; then
  skipped_count=$(printf '%s' "${SKIPPED_NESTED}" | grep -c '.' || true)
  echo "[pre-flight] Skipping ${skipped_count} nested git repo/worktree path(s) (not part of this diff):"
  printf '%s' "${SKIPPED_NESTED}" | sed 's/^/  - /'
fi

if [ -n "${UNTRACKED}" ]; then
  untracked_count=$(printf '%s' "${UNTRACKED}" | grep -c '.' || true)
  echo "[pre-flight] Marking ${untracked_count} untracked path(s) as intent-to-add (gap #6)..."
  printf '%s' "${UNTRACKED}" | while IFS= read -r p; do
    [ -z "$p" ] && continue
    git add -N -- "$p"
  done
fi

# ---- pre-flight: confirm non-empty diff -------------------------------------
if git diff --quiet; then
  echo "ERROR: working tree has no changes for Codex to review." >&2
  echo "  - If you edited files in a sibling repo: cd into that repo first (gap #3)." >&2
  echo "  - If you already committed: dispatch must happen BEFORE commit (gap #4)." >&2
  exit 2
fi

DIFF_STAT=$(git diff --shortstat)
HEAD_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "<no-commits>")
echo "[pre-flight] HEAD=${HEAD_SHA} diff:${DIFF_STAT}"

# ---- dispatch ---------------------------------------------------------------
# Capture the job id from --json output so we correlate against THIS dispatch,
# not whatever else might be running. Codex 2026-05-15 finding: guessing the
# job from snapshot polling can cancel/report on an unrelated job.
echo "[dispatch] Starting ${MODE} (background)..."
DISPATCH_JSON=$(node "${COMPANION}" "${MODE}" --background --json 2>&1)
DISPATCH_EXIT=$?
if [ "${DISPATCH_EXIT}" != "0" ]; then
  echo "ERROR: dispatch failed (exit ${DISPATCH_EXIT}). Output:" >&2
  echo "${DISPATCH_JSON}" >&2
  exit 2
fi

JOB_ID=$(printf '%s' "${DISPATCH_JSON}" | jq -r '.jobId // empty' 2>/dev/null || echo "")
if [ -z "${JOB_ID}" ]; then
  # Fall back to text-parse if --json didn't yield a jobId (older companion?).
  JOB_ID=$(printf '%s' "${DISPATCH_JSON}" | sed -nE 's/.*background as ([A-Za-z0-9-]+)\..*/\1/p' | head -1)
fi
if [ -z "${JOB_ID}" ]; then
  echo "ERROR: dispatch did not return a job id. Output:" >&2
  echo "${DISPATCH_JSON}" >&2
  exit 2
fi
echo "[dispatch] JOB_ID=${JOB_ID}"

if [ "${NO_WAIT}" = "1" ]; then
  echo "[dispatch] Job dispatched. Use:"
  echo "  ${0##*/} status ${JOB_ID}   # check progress"
  echo "  ${0##*/} result ${JOB_ID}   # fetch result"
  exit 0
fi

# ---- hang-bail polling loop -------------------------------------------------
POLL_INTERVAL=90
MAX_STABLE_POLLS=3      # 3 × 90s = 4.5 min silent-log cap (per codex-dispatch.md gap #7)
INITIAL_SETTLE=10       # wait briefly before first status query so job has a chance to land

prev_size=-1
stable=0
elapsed=${INITIAL_SETTLE}

sleep "${INITIAL_SETTLE}"

while :; do
  sleep "${POLL_INTERVAL}"
  elapsed=$((elapsed + POLL_INTERVAL))

  # Per-job status returns { workspaceRoot, job: <enriched> }.
  # JOB_ID is guaranteed by the dispatch step above (script exits 2 otherwise).
  snapshot=$(node "${COMPANION}" status "${JOB_ID}" --json 2>/dev/null || echo '{}')
  job_status=$(echo "${snapshot}" | jq -r '.job.status // empty')
  phase=$(echo "${snapshot}"     | jq -r '.job.phase  // empty')
  log_path=$(echo "${snapshot}"  | jq -r '.job.logFile // empty')

  if [ -n "${job_status}" ] && [ "${job_status}" != "queued" ] && [ "${job_status}" != "running" ]; then
    echo "[poll] Job finished: status=${job_status} (elapsed: ${elapsed}s)"
    break
  fi

  cur_size=0
  if [ -n "${log_path}" ] && [ -f "${log_path}" ]; then
    cur_size=$(wc -c <"${log_path}" 2>/dev/null | tr -d ' ' || echo 0)
  fi

  if [ "${cur_size}" = "${prev_size}" ] && [ "${phase}" = "verifying" ]; then
    stable=$((stable + 1))
    echo "[poll] phase=verifying, log stable (${stable}/${MAX_STABLE_POLLS}) at ${cur_size}B (elapsed: ${elapsed}s)"
    if [ "${stable}" -ge "${MAX_STABLE_POLLS}" ]; then
      echo "" >&2
      echo "[hang-bail] Job hung after ${MAX_STABLE_POLLS}×${POLL_INTERVAL}s in verifying with no log growth. Cancelling." >&2
      if [ -n "${JOB_ID}" ]; then
        node "${COMPANION}" cancel "${JOB_ID}" >&2 || true
      fi
      echo "" >&2
      echo "Bypass required. Suggested reason:" >&2
      echo "  'Codex adversarial-review hung at ${elapsed}s of silent log (gap #7 deterministic hang)." >&2
      echo "   Cancelled per cap. <add a second sentence naming review evidence on this diff:" >&2
      echo "    regression tests passing, mirrors a documented pattern, low-blast-radius surface, etc.>'" >&2
      exit 3
    fi
  else
    stable=0
    echo "[poll] phase=${phase:-?} status=${job_status:-?} log=${cur_size}B (elapsed: ${elapsed}s)"
  fi
  prev_size=${cur_size}
done

echo
echo "[result]"
node "${COMPANION}" result ${JOB_ID:+"${JOB_ID}"}
