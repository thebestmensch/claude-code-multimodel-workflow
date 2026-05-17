#!/usr/bin/env bash
# check-runbook-drift.sh: flag semantic drift between two near-mirror
# runbook .md files while ignoring identifier-substitution noise.
#
# Strips before diffing (substitutions normalize so two near-mirror runbooks
# from different projects collapse to the same canonical form):
#   - project names from $RUNBOOK_PROJECT_NAMES (comma-separated, default empty)
#     example: RUNBOOK_PROJECT_NAMES="acme,beta-svc"
#   - ticket prefixes from $RUNBOOK_TICKET_PREFIXES (comma-separated, default
#     empty). Matches both literal numbers (PROJ-1234) and the template-N form
#     (PROJ-N).
#     example: RUNBOOK_TICKET_PREFIXES="ABC,XYZ"
#   - Linear URL slugs: linear.app/<anything>
#   - Linear short-IDs (12-hex after a project slug)
#   - UUIDs (Linear view/project IDs)
#   - per-project MCP tool names: mcp__linear-<slug>__ → mcp__linear__
#
# Deliberately NOT stripped:
#   - branch words (`main`, `staging`): collapsing them masks direction
#     reversals like `merge staging into main` vs `merge main into staging`,
#     which is exactly the semantic drift this tool catches.
#
# Usage:
#   check-runbook-drift.sh FILE_A FILE_B
#   RUNBOOK_PROJECT_NAMES=acme,beta DRIFT_THRESHOLD=80 \
#       check-runbook-drift.sh FILE_A FILE_B
#
# Exit codes:
#   0  drift events <= threshold
#   1  drift events > threshold (prints summary to stderr)
#   2  usage or file error

set -o errexit -o nounset -o pipefail

THRESHOLD="${DRIFT_THRESHOLD:-50}"
if ! [[ "$THRESHOLD" =~ ^[0-9]+$ ]]; then
  echo "error: DRIFT_THRESHOLD must be a non-negative integer, got: $THRESHOLD" >&2
  exit 2
fi

if [[ $# -ne 2 ]]; then
  echo "usage: $(basename "$0") FILE_A FILE_B" >&2
  echo "  env DRIFT_THRESHOLD=N (default 50)" >&2
  echo "  env RUNBOOK_PROJECT_NAMES=name1,name2 (project tokens to collapse)" >&2
  echo "  env RUNBOOK_TICKET_PREFIXES=ABC,XYZ (ticket prefixes to collapse)" >&2
  exit 2
fi

FILE_A="$1"
FILE_B="$2"

for f in "$FILE_A" "$FILE_B"; do
  if [[ ! -f "$f" ]]; then
    echo "error: not a file: $f" >&2
    exit 2
  fi
done

# Build perl alternation groups from env-var lists.
project_alt=""
if [[ -n "${RUNBOOK_PROJECT_NAMES:-}" ]]; then
  # quotemeta each name for safety, then join with |
  project_alt=$(printf '%s' "$RUNBOOK_PROJECT_NAMES" | perl -ne 'chomp; print join("|", map { quotemeta } split(/,/));')
fi

# Ticket prefixes are typically uppercase. Build both the literal and the
# template-N form (PROJ-1234 / PROJ-N).
ticket_alt=""
if [[ -n "${RUNBOOK_TICKET_PREFIXES:-}" ]]; then
  ticket_alt=$(printf '%s' "$RUNBOOK_TICKET_PREFIXES" | perl -ne 'chomp; print join("|", map { quotemeta(uc $_) } split(/,/));')
fi

# Loud warning when both env vars are unset. The strip phase still removes
# UUIDs / Linear URLs, but project-name and ticket-prefix tokens will pass
# through and show up as drift. Better to emit a visible signal than to
# silently undercount or overcount drift events. Suppress with RUNBOOK_DRIFT_QUIET=1.
if [[ -z "$project_alt" && -z "$ticket_alt" && -z "${RUNBOOK_DRIFT_QUIET:-}" ]]; then
  echo "warning: RUNBOOK_PROJECT_NAMES and RUNBOOK_TICKET_PREFIXES are both unset." >&2
  echo "         Project names and ticket IDs will NOT be normalized before diffing; " >&2
  echo "         expect inflated drift event counts. Set the env vars or pass" >&2
  echo "         RUNBOOK_DRIFT_QUIET=1 to suppress this warning." >&2
fi

# Perl for portable \b across BSD (macOS) and GNU sed.
strip_identifiers() {
  perl -pe '
    s{[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}}{UUID}g;
    s{linear\.app/[A-Za-z0-9_-]+}{linear.app/PROJECT}g;
    s{\bmcp__linear(?:-[a-z]+)?__}{mcp__linear__}g;
    if ($ENV{PROJECT_ALT} ne "") {
      my $alt = $ENV{PROJECT_ALT};
      s{\b(?:$alt)\b}{PROJECT}g;
    }
    if ($ENV{TICKET_ALT} ne "") {
      my $alt = $ENV{TICKET_ALT};
      s{\b(?:$alt)-(?:\d+|N)\b}{TICKET-N}g;
      my $lower = lc $alt;
      s{\b(?:$lower)-linear-(work|new|status)-ticket\b}{PROJECT-linear-$1-ticket}g;
    }
    s{\bPROJECT-[0-9a-f]{12}\b}{PROJECT-LINEARID}g;
  '
}
export PROJECT_ALT="$project_alt"
export TICKET_ALT="$ticket_alt"

A_STRIP="$(mktemp)"
B_STRIP="$(mktemp)"
trap 'rm -f "$A_STRIP" "$B_STRIP"' EXIT

strip_identifiers <"$FILE_A" >"$A_STRIP"
strip_identifiers <"$FILE_B" >"$B_STRIP"

# diff returns 1 when files differ; tolerate that under errexit.
EVENTS="$(diff "$A_STRIP" "$B_STRIP" | grep -cE '^[<>]' || true)"

echo "drift events: $EVENTS  (threshold: $THRESHOLD)"
echo "  A: $FILE_A"
echo "  B: $FILE_B"

if [[ "$EVENTS" -gt "$THRESHOLD" ]]; then
  echo "drift exceeds threshold by $((EVENTS - THRESHOLD)) events" >&2
  exit 1
fi

exit 0
