#!/usr/bin/env bash
# PreToolUse on mcp__linear__save_issue
# Blocks adding `agent-eligible` to a ticket until the assistant has
# explicitly affirmed the ticket scope is clear of self-modification
# patterns (services/tickets/, .claude/commands/work-ticket.md, etc.).
#
# Why: Memory rule `feedback_agent_eligible_self_mod_filing_check.md`
# documents the requirement to grep ticket scope before applying the
# label. Memory rules don't survive momentum (cf. retro skill); this
# hook is the enforcement layer.
#
# Bypass: Claude writes to /tmp/cc-gates/<session>/agent-eligible-
# verified-<ticket-id> after verifying scope. File is consumed on use
# (one-shot); re-affirm for each ticket.
set -o pipefail

input=$(cat)

# Match only mcp__linear__save_issue
tool=$(echo "$input" | jq -r '.tool_name // empty')
[[ "$tool" != "mcp__linear__save_issue" ]] && exit 0

# Fire only when labels are being set AND include agent-eligible.
# `tool_input.labels` is replace-all; absent means labels are unchanged.
has_label=$(echo "$input" | jq -r '
  (.tool_input.labels // []) as $labels
  | $labels | map(select(. == "agent-eligible")) | length > 0
')
[[ "$has_label" != "true" ]] && exit 0

ticket_id=$(echo "$input" | jq -r '.tool_input.id // "new"')
session_id=$(echo "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

gate_dir="/tmp/cc-gates/$session_id"
mkdir -p "$gate_dir"
bypass_file="$gate_dir/agent-eligible-verified-${ticket_id}"

if [ -f "$bypass_file" ]; then
  reason=$(cat "$bypass_file" | tr -d '\n' | head -c 200)
  echo "$(date '+%Y-%m-%d %H:%M:%S') | agent-eligible-self-mod | VERIFIED | $ticket_id | $reason" >> "$gate_dir/bypass_log.txt"
  rm -f "$bypass_file"  # one-shot
  exit 0
fi

# Block: message instructs assistant to verify + write bypass file
cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "BLOCKED: 'agent-eligible' label requires scope verification (CLAUDE.md line 40 + memory feedback_agent_eligible_self_mod_filing_check.md). Never apply this label to tickets that modify services/tickets/, .claude/commands/work-ticket.md, or the agent profile system; agent will bounce on self-mod and burn 1 of 2 bounce slots. To proceed: (1) read the ticket's ## Scope section; (2) confirm none of those paths are in scope; (3) run: mkdir -p $gate_dir && echo 'scope verified clear of services/tickets and work-ticket.md' > $bypass_file ; (4) retry the save_issue call. The bypass file is single-use per ticket."
  }
}
EOF
exit 0
