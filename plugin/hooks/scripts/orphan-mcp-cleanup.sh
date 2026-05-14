#!/bin/bash
# Sweep orphaned stdio MCP server processes at SessionStart.
#
# Symptom: stdio MCP servers (registered with `command: ...` in mcpServers
# config) can survive abnormal CC session exits — their parent CC dies,
# they're reparented to launchd (ppid=1), and they linger indefinitely.
# Some (notably @heroku/mcp-server) actively spawn CPU-intensive subprocess
# trees, compounding into a real battery drain.
#
# Strategy: each SessionStart, find known-leaky MCP processes whose parent
# is launchd — meaning their original session is dead — and kill them with
# their subprocess trees. Active sessions are unaffected because their
# MCP server's ppid points at a live CC PID, not 1.
#
# Add new patterns below as more leaky MCPs surface.

set -u

PATTERNS=(
  "heroku-mcp-server\.mjs"
  "npm exec heroku@latest --repl"
)

killed=0
for pattern in "${PATTERNS[@]}"; do
  for pid in $(pgrep -f "$pattern" 2>/dev/null); do
    ppid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    if [ "$ppid" = "1" ]; then
      pkill -P "$pid" 2>/dev/null
      kill "$pid" 2>/dev/null && killed=$((killed + 1))
    fi
  done
done

if [ "$killed" -gt 0 ]; then
  printf '{"systemMessage":"Cleaned up %d orphan MCP process(es) from prior sessions"}\n' "$killed"
fi

exit 0
