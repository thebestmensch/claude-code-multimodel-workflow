#!/usr/bin/env bash
# check-runbook-drift.sh — flag semantic drift between two near-mirror
# runbook .md files while ignoring identifier-substitution noise.
#
# Strips before diffing:
#   - project names: oneonme, home-lab
#   - ticket prefixes: OOM-1234, JM-1234, OOM-N, JM-N (literal template form)
#   - Linear URL slugs: linear.app/<anything>
#   - Linear short-IDs (12-hex after a project slug)
#   - UUIDs (Linear view/project IDs)
#   - command names: {oom,jm}-linear-{work,new,status}-ticket
#   - per-project MCP tool names: mcp__linear-oom__ / mcp__linear-jm__ / mcp__linear__
#
# Deliberately NOT stripped:
#   - branch words (`main`, `staging`): collapsing them masks direction
#     reversals like `merge staging into main` vs `merge main into staging`,
#     which is exactly the semantic drift this tool catches.
#
# Usage:
#   check-runbook-drift.sh FILE_A FILE_B
#   DRIFT_THRESHOLD=80 check-runbook-drift.sh FILE_A FILE_B
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

# Perl for portable \b across BSD (macOS) and GNU sed.
strip_identifiers() {
  perl -pe '
    s{[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}}{UUID}g;
    s{linear\.app/[A-Za-z0-9_-]+}{linear.app/PROJECT}g;
    s{\bmcp__linear(?:-[a-z]+)?__}{mcp__linear__}g;
    s{\b(?:oom|jm)-linear-(work|new|status)-ticket\b}{PROJECT-linear-$1-ticket}g;
    s{\b(?:OOM|JM)-(?:\d+|N)\b}{TICKET-N}g;
    s{\boneonme\b}{PROJECT}g;
    s{\bhome-lab\b}{PROJECT}g;
    s{\bPROJECT-[0-9a-f]{12}\b}{PROJECT-LINEARID}g;
  '
}

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
