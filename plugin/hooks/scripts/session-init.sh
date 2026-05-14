#!/usr/bin/env bash
# Hook 0 — Session Init (UserPromptSubmit)
# Creates per-session state directory and maintains the 'current' symlink.
# Prunes sessions older than 24h.
set -o pipefail

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')

[ -z "$session_id" ] && exit 0

gate_dir="/tmp/cc-gates/$session_id"
mkdir -p "$gate_dir"
# Timestamp marker for augment-edited-files.sh — only files mtime-newer than
# this are considered "edited this session" by the worktree augmenter.
# Pre-existing dirty files from prior sessions stay out of the gate.
[ -f "$gate_dir/.session_start" ] || touch "$gate_dir/.session_start"
ln -sfn "$gate_dir" /tmp/cc-gates/current

# Clean up sessions older than 24h
find /tmp/cc-gates -maxdepth 1 -type d -mmin +1440 -not -name "cc-gates" -exec rm -rf {} + 2>/dev/null

exit 0
