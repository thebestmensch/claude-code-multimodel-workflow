#!/usr/bin/env bash
# Hook: Restate Goal Gate (PreToolUse on Bash)
# Before the FIRST irreversible/destructive command in a session, requires the
# main session to restate the goal and explicitly mark approval.
# Pattern borrowed from ouroboros: restate-gate before seed/execute handoff.
#
# Destructive surfaces gated (any one match fires):
#   - git push (incl. --force, -f)
#   - gh pr create / gh pr merge / gh pr ready
#   - git reset --hard
#   - git push --force / --force-with-lease
#   - rm -rf
#
# Once approved this session (via touch goal_restated), allow everything
# for the rest of the session.
#
# Bypass: touch /tmp/cc-gates/$SESSION/skip_restate_gate
set -o pipefail

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

gate_dir="/tmp/cc-gates/$session_id"
mkdir -p "$gate_dir"

# Approved this session → allow
[ -f "$gate_dir/goal_restated" ] && exit 0
[ -f "$gate_dir/skip_restate_gate" ] && exit 0

command=$(echo "$input" | jq -r '.tool_input.command // empty')
[ -z "$command" ] && exit 0

# Split the command into segments on shell separators (&&, ||, ;, |, &, newline)
# so each invocation is evaluated independently. A `git push --dry-run` in one
# segment must NOT exempt a real `git push` in a later segment.
segments=$(printf "%s" "$command" | awk '
  BEGIN { RS="\n"; }
  {
    # Replace shell separators with newlines so each segment is on its own line.
    gsub(/&&|\|\||[;|&]/, "\n", $0); print
  }
')

is_destructive=0
matched=""

# Check each segment independently
while IFS= read -r seg; do
  # Trim leading/trailing whitespace
  seg=$(printf "%s" "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
  [ -z "$seg" ] && continue

  # git push: destructive UNLESS this specific invocation has --dry-run
  if printf "%s" "$seg" | grep -qE '(^|[[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+push([[:space:]]|$)'; then
    if ! printf "%s" "$seg" | grep -qE '(^|[[:space:]])--dry-run([[:space:]]|$)'; then
      is_destructive=1; matched="git push"; break
    fi
  fi

  # gh pr create / merge / ready
  if printf "%s" "$seg" | grep -qE '(^|[[:space:]])gh[[:space:]]+pr[[:space:]]+(create|merge|ready)([[:space:]]|$)'; then
    sub=$(printf "%s" "$seg" | grep -oE 'gh[[:space:]]+pr[[:space:]]+(create|merge|ready)' | awk '{print $3}')
    is_destructive=1; matched="gh pr ${sub:-create/merge/ready}"; break
  fi

  # git reset --hard (any flag position)
  if printf "%s" "$seg" | grep -qE '(^|[[:space:]])git[[:space:]]+reset([[:space:]]|$)' && \
     printf "%s" "$seg" | grep -qE '(^|[[:space:]])--hard([[:space:]]|$)'; then
    is_destructive=1; matched="git reset --hard"; break
  fi

  # rm with both -r/-R/--recursive and -f/-F/--force in any form
  # (covers `rm -rf`, `rm -r -f`, `rm -fR`, `rm --recursive --force`, etc.)
  if printf "%s" "$seg" | grep -qE '(^|[[:space:]])rm([[:space:]]|$)'; then
    has_recursive=0; has_force=0
    if printf "%s" "$seg" | grep -qE '(^|[[:space:]])(-[a-zA-Z]*[rR][a-zA-Z]*|--recursive)([[:space:]]|$)'; then
      has_recursive=1
    fi
    if printf "%s" "$seg" | grep -qE '(^|[[:space:]])(-[a-zA-Z]*[fF][a-zA-Z]*|--force)([[:space:]]|$)'; then
      has_force=1
    fi
    if [ "$has_recursive" -eq 1 ] && [ "$has_force" -eq 1 ]; then
      is_destructive=1; matched="rm -rf"; break
    fi
  fi
done <<<"$segments"

[ "$is_destructive" -eq 0 ] && exit 0

reason="First destructive action this session: ${matched:-unknown}. Restate-goal gate (ouroboros pattern): before irreversible work, restate (a) the goal in one sentence and (b) the blast radius / risk in one sentence. Then explicitly approve by running: touch $gate_dir/goal_restated, and retry the command. After approval, the rest of the session is unblocked. Bypass without restate: touch $gate_dir/skip_restate_gate (only when the destructive action is itself the entire goal, e.g. user said 'force-push the fix')."

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "$reason"
  }
}
EOF
exit 0
