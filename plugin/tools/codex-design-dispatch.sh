#!/usr/bin/env bash
# Codex design-dispatch wrapper: cross-provider design recon at the proposal stage.
#
# Sibling to codex-plan-critique.sh (adversarial plan reviewer) and
# codex-dispatch.sh (diff-time review/adversarial-review). This one
# wraps `task` mode with a *thoughtful frontend designer* envelope: produces
# named-font, pinned-hex, verified-contrast proposals instead of adversarial
# critique.
#
# Why a separate wrapper: envelope shape determines output shape. The
# adversarial wrapper hardcodes "critique this plan for missing cases"; that
# returns useful meta-recon but never concrete design proposals (validated on
# a personal-site footer recon). New use case = new envelope.
#
# Same gap-coverage as codex-plan-critique.sh: `task` mode reads stdin or
# --brief-file, ignores git state, and does NOT trigger the codex-stop-gate
# (which keys off review jobs against a diff).
#
# Usage:
#   echo "<brief>" | codex-design-dispatch.sh
#   codex-design-dispatch.sh --brief-file path/to/brief.md
#   codex-design-dispatch.sh status [job-id]
#   codex-design-dispatch.sh result [job-id]
#
# Exit codes:
#   0: job dispatched (job id printed to stdout)
#   2: pre-flight failure (no brief text, missing companion, etc.)

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
BRIEF_FILE=""
if [ "${1:-}" = "--brief-file" ]; then
  BRIEF_FILE="${2:-}"
  [ -n "${BRIEF_FILE}" ] || { echo "ERROR: --brief-file requires a path" >&2; exit 2; }
  [ -f "${BRIEF_FILE}" ] || { echo "ERROR: brief file not found: ${BRIEF_FILE}" >&2; exit 2; }
fi

# ---- read brief text --------------------------------------------------------
if [ -n "${BRIEF_FILE}" ]; then
  BRIEF_TEXT=$(cat "${BRIEF_FILE}")
else
  if [ -t 0 ]; then
    echo "ERROR: no brief text on stdin and no --brief-file given." >&2
    echo "Usage: echo \"<brief>\" | $(basename "$0")  OR  $(basename "$0") --brief-file <path>" >&2
    exit 2
  fi
  BRIEF_TEXT=$(cat)
fi

if [ -z "${BRIEF_TEXT//[[:space:]]/}" ]; then
  echo "ERROR: brief text is empty." >&2
  exit 2
fi

# ---- compose designer envelope ----------------------------------------------
WRAPPED_PROMPT_FILE=$(mktemp -t codex-design-dispatch.XXXXXX)
trap 'rm -f "${WRAPPED_PROMPT_FILE}"' EXIT

cat >"${WRAPPED_PROMPT_FILE}" <<'EOF_HEADER'
You are a thoughtful frontend designer with strong typographic and visual
sensibility. Read the codebase at the current cwd and propose concrete,
implementable design changes that push it toward the target vibe described
below.

NOT a plan critique. NOT adversarial review. PROPOSE the design.

READ-ONLY MODE - STRICT:
- Do NOT modify any files.
- Do NOT execute commands that change state.
- Do NOT propose code patches as diffs to apply (snippets-as-illustration are fine).
- You MAY (and SHOULD) read files to verify current state before proposing.

Verify current state first. For every surface you recommend changing:
- Read the relevant file.
- Quote the current value verbatim, then propose the replacement.
- Do not propose changes to surfaces that already match the target. Focus
  the proposal on the gaps.

For each recommendation, include:
- **Surface**: file or system being changed
- **Current**: quote/describe what's there (verified by reading)
- **Proposal**: specific, implementable change. Be concrete:
  - Font: name, weight axis, source (e.g. `@fontsource-variable/eb-garamond` v5.x), license note, fallback stack
  - Color: actual hex code, intended role (background / body ink / accent / muted ink), and verified WCAG AA contrast ratio against its paired background (cite the ratio)
  - Size: rem/px values
  - Spacing: rem or em values
  - Structural: new class name, container split, etc.
- **Why this serves the vibe**: one sentence tying it to the target

Group by severity:
- **Cornerstone**: the 1-3 changes that produce 80% of the visual shift toward target
- **Important**: meaningful refinements
- **Polish**: final-pass touches (small caps, ligatures, ornaments, hover states)

End with a concrete **acceptance test**: 2-3 sentences describing the felt
experience after the changes ship, in the form "after these changes, a user
viewing X should ...".

Value comes from cross-provider non-overlap: focus on what a Claude design
agent is most likely to miss: package-license verification, OpenType
feature coverage in specific `@fontsource` variable builds, mathematical
contrast verification, named font research with concrete fallback stacks,
implementation-cost realism.

--- DESIGN BRIEF FOLLOWS ---

EOF_HEADER

printf '%s\n' "${BRIEF_TEXT}" >>"${WRAPPED_PROMPT_FILE}"

# ---- dispatch ---------------------------------------------------------------
echo "[dispatch] Starting Codex design recon (task --effort high, background)..." >&2
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
