#!/usr/bin/env bash
# pre-commit-runbook-drift.sh — adopter snippet
#
# Append to .git/hooks/pre-commit (or use as the whole file) to run
# check-runbook-drift on the two near-mirror runbooks when either is
# staged. Edit the two paths + the script location below to match your
# checkout.
#
# Install (raw `.git/hooks/pre-commit`):
#   1. Copy this body into `.git/hooks/pre-commit`
#   2. `chmod +x .git/hooks/pre-commit`
#   3. Edit RUNBOOK_A, RUNBOOK_B, DRIFT_SCRIPT to absolute paths
#
# Bypass for a single commit: `git commit --no-verify`
# Bump threshold:               `DRIFT_THRESHOLD=80 git commit ...`

set -o errexit -o nounset -o pipefail

# --- Configure (edit these three lines) ---------------------------------
RUNBOOK_A="${HOME}/Documents/local/oneonme/.claude/commands/oom-linear-work-ticket.md"
RUNBOOK_B="${HOME}/Documents/local/jm/home-lab/.claude/commands/jm-linear-work-ticket.md"
DRIFT_SCRIPT="${HOME}/Documents/local/jm-workflow/plugin/tools/check-runbook-drift.sh"
# ------------------------------------------------------------------------

# Only run if the work-ticket runbook is staged. The configured RUNBOOK_A/B
# below are the work-ticket pair; if you also mirror `*-linear-new-ticket.md`
# or `*-linear-status-ticket.md`, duplicate this block (or add a second
# hook file) with that class's regex + matching paths. Don't broaden the
# regex without broadening the args — staged new/status files would run
# against the work-ticket pair and silently pass.
STAGED="$(git diff --cached --name-only --diff-filter=ACM)"
if ! grep -qE '(^|/)[a-z]+-linear-work-ticket\.md$' <<<"$STAGED"; then
  exit 0
fi

if [[ ! -x "$DRIFT_SCRIPT" ]]; then
  echo "pre-commit: drift script missing or not executable: $DRIFT_SCRIPT" >&2
  exit 1
fi

"$DRIFT_SCRIPT" "$RUNBOOK_A" "$RUNBOOK_B"
