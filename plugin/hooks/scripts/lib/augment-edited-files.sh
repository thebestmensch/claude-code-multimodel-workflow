#!/usr/bin/env bash
# Bash-mediated edit gap closure: augments gate_dir/edited_files with files
# git knows about but PostToolUse Edit|Write tracking missed.
#
# Why: track-edited-files.sh only fires on Edit|Write tools. Mutations via
# `sed -i`, generators, formatters, code patches via shell, and tee
# redirection are invisible. The Codex stop-gate and pre-commit-gate then
# silently approve unreviewed code because edited_files is empty (or stale).
#
# Strategy: at gate-fire time, ask git what's actually changed. Filter out
# non-code surfaces (same case rules as track-edited-files.sh's exclusion
# list) and append untracked-by-edit paths to edited_files. The gate's
# downstream logic (freshness, dispatched/handled markers) then treats them
# as real edits.
#
# Args:
#   $1 = gate_dir (e.g. /tmp/cc-gates/<session_id>)
#   $2 = git diff mode: "cached" | "worktree"
#        cached  → `git diff --cached --name-only -z` (about-to-commit)
#        worktree → `git diff --name-only -z HEAD`    (uncommitted)
#
# Repo discovery: uses $PWD. Hooks run with cwd inherited from the user's
# Claude session, which is typically the project root. If git rev-parse fails
# (not in a repo), this is a no-op; same fail-soft behavior as the existing
# tracker.
#
# Performance: git diff --name-only is O(staged-files) and reliably <100ms
# even on repos with >1000 files.

set -o pipefail

gate_dir="$1"
mode="${2:-cached}"

[ -z "$gate_dir" ] && exit 0
[ -d "$gate_dir" ] || exit 0

# Bail if not in a git repo (e.g. user is committing nothing in particular,
# or PWD landed somewhere unusual). Quietly, don't pollute hook stdout.
git rev-parse --git-dir >/dev/null 2>&1 || exit 0

case "$mode" in
  cached)   diff_args=(--cached --name-only -z) ;;
  worktree) diff_args=(--name-only -z HEAD) ;;
  *) exit 0 ;;
esac

# In worktree mode, also include untracked files. `git diff --name-only HEAD`
# reports tracked changes only, so a `tee > new_file.py` or generator that
# creates a brand-new file is invisible. Merging `ls-files --others
# --exclude-standard` covers that. (Closes Codex round-1 medium #2 on this
# diff; see commit history.)
include_untracked=0
if [ "$mode" = "worktree" ]; then
  include_untracked=1
fi

edited_file="$gate_dir/edited_files"

# Read existing tracked files into a set (one per line, normalized to absolute
# paths). edited_file may not exist yet.
existing_set=$(mktemp)
trap 'rm -f "$existing_set" "$candidates" "$repo_root_file"' EXIT
candidates=$(mktemp)
repo_root_file=$(mktemp)

if [ -f "$edited_file" ]; then
  sort -u "$edited_file" > "$existing_set"
fi

# Use `pwd -P` inside the toplevel to canonicalize the path (resolves
# symlinks like macOS /var → /private/var). Without this, a session that
# cwd'd through a symlinked path produces edited_files entries that don't
# dedupe against track-edited-files.sh entries written from CC's resolved
# path. Real-world CC sessions rarely sit in /tmp, but the canonicalization
# is cheap insurance.
repo_root=$( (cd "$(git rev-parse --show-toplevel 2>/dev/null)" 2>/dev/null && pwd -P) || true )
[ -z "$repo_root" ] && exit 0

session_start_marker="$gate_dir/.session_start"

# Mtime filter applies ONLY in worktree mode (Stop-time augmentation). In
# cached mode, files are *about to ship* via `git commit` regardless of when
# they were edited; the codex-pre-commit-gate must see all staged code paths
# or pre-existing dirty files become a silent bypass surface (Codex finding
# #1, 2026-05-08). Keep the filter strictly worktree-scoped: the runaway
# false-positive that motivated the marker only happens when the augmenter
# pulls in carryover WIP unrelated to this session, which only manifests in
# worktree mode.
apply_mtime_filter=0
if [ "$mode" = "worktree" ] && [ -f "$session_start_marker" ]; then
  apply_mtime_filter=1
fi

filter_and_emit() {
  while IFS= read -r -d '' path; do
    [ -z "$path" ] && continue
    # Skip directory entries: `git ls-files --others` reports untracked dirs
    # (registered worktrees under .claude/worktrees/, vendor caches, etc.) with
    # a trailing slash. They're not files-to-review; they're false positives.
    case "$path" in
      */) continue ;;
      *.md|*.json|*.yml|*.yaml|*.toml|*.txt|*.csv|*.lock) continue ;;
    esac
    abs_path="$repo_root/$path"
    [ -d "$abs_path" ] && continue
    if [ "$apply_mtime_filter" = "1" ] && [ -f "$abs_path" ]; then
      if [ ! "$abs_path" -nt "$session_start_marker" ]; then
        continue
      fi
    fi
    # Normalize to absolute path so it dedupes against entries that
    # track-edited-files.sh wrote (those come straight from tool_input.file_path
    # which CC always provides as absolute).
    printf '%s\n' "$abs_path"
  done
}

{
  git diff "${diff_args[@]}" 2>/dev/null | filter_and_emit
  if [ "$include_untracked" = "1" ]; then
    git ls-files --others --exclude-standard -z 2>/dev/null | filter_and_emit
  fi
} > "$candidates"

# Append candidates not already present. comm -23 needs sorted input.
sort -u "$candidates" > "${candidates}.sorted"
mv "${candidates}.sorted" "$candidates"

if [ -s "$existing_set" ]; then
  comm -23 "$candidates" "$existing_set" >> "$edited_file"
else
  cat "$candidates" >> "$edited_file"
fi

exit 0
