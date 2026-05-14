#!/usr/bin/env bash
# PreToolUse on Bash — block `git push` when HEAD is more than 1 commit
# ahead of upstream. Forces explicit acknowledgment of bundled prior
# commits before they reach the remote.
#
# Origin: 2026-04-29 retro. Pushed 2 prior local-only user commits
# (`68f4bb4` ⌘P PR opener + `ea6ba6d` drift-guard tightening) alongside
# my soft-card commit, because I didn't audit `git log @{u}..HEAD` first.
# Memory rule `feedback_check_push_payload.md` (4 days old) already
# covered this — got skipped under momentum. Hook over rule.
#
# Behavior:
# - Triggers only on Bash commands containing `git push`
# - Reads cwd from `cd <path> && git push` if present, else $PWD
# - Computes unpushed commit count via `git log @{u}..HEAD --oneline`
# - 0 commits (or no upstream): pass — push will fail at git's level anyway
# - 1 commit: pass — single commit ahead is the expected case
# - 2+ commits: BLOCK with the commit list so the operator can rebase /
#   reset / acknowledge before pushing
#
# Escape hatches (two paths — env doesn't propagate to PreToolUse hooks
# from inline `VAR=1 cmd` invocations, so a touchfile is the only viable
# bypass for in-CC-session pushes; env var still works when set in the
# user's shell BEFORE the CC session starts):
#  1. GIT_PUSH_BUNDLED_OK=1 in the harness's startup env (interactive shell)
#  2. /tmp/cc-gates/<session_id>/skip_push_bundle_check exists (in-session)
# Touchfile is per-session and auto-cleared when session-init.sh runs at
# next session start — bypass doesn't persist across restarts.

set -o pipefail

[ "${GIT_PUSH_BUNDLED_OK:-}" = "1" ] && exit 0

input=$(cat)

# Extract command + session_id from tool_input.
command=$(printf '%s' "$input" | /usr/bin/python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get("tool_input", {}).get("command", ""))
except Exception:
    pass
' 2>/dev/null)

session_id=$(printf '%s' "$input" | /usr/bin/python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get("session_id", ""))
except Exception:
    pass
' 2>/dev/null)

# Touchfile bypass — created by Claude with explicit user authorization
# for an intentional bundled push within this session.
if [ -n "$session_id" ] && [ -f "/tmp/cc-gates/$session_id/skip_push_bundle_check" ]; then
  exit 0
fi

# Token-level match — `git push` must be ADJACENT argv tokens, not a substring
# inside a quoted argument to printf/echo/cat/etc. shlex.split respects shell
# quoting so `printf '... git push ...'` is one token (the quoted string),
# not three. Only fires when git+push are actual command words.
matches=$(printf '%s' "$command" | /usr/bin/python3 -c '
import shlex, sys
cmd = sys.stdin.read()
try:
    tokens = shlex.split(cmd, posix=True, comments=False)
except ValueError:
    # Unbalanced quotes — fall back to NO match (avoid false positives on
    # malformed commands, which are usually quote-juggling shell tricks).
    sys.exit(0)
for i in range(len(tokens) - 1):
    if tokens[i] == "git" and tokens[i+1] == "push":
        print("match")
        break
' 2>/dev/null)
[ "$matches" != "match" ] && exit 0

# Resolve cwd. If the command is `cd <path> && git push ...`, use that path —
# matches the pattern Claude uses to push from chezmoi sources, worktrees, etc.
cwd=""
if printf '%s' "$command" | grep -qE '^[[:space:]]*cd[[:space:]]'; then
  cwd=$(printf '%s' "$command" | sed -nE 's|^[[:space:]]*cd[[:space:]]+([^[:space:]&;|]+).*|\1|p' | head -1)
  cwd="${cwd//\"/}"
  cwd="${cwd//\'/}"
  case "$cwd" in
    "~"*) cwd="${HOME}${cwd:1}" ;;
  esac
fi
[ -z "$cwd" ] && cwd="$PWD"
[ ! -d "$cwd" ] && exit 0

# Get unpushed commits. `@{u}` errors silently if no upstream — exit 0.
unpushed=$(cd "$cwd" 2>/dev/null && git log '@{u}..HEAD' --oneline 2>/dev/null)
[ -z "$unpushed" ] && exit 0

count=$(printf '%s\n' "$unpushed" | grep -c .)
[ "$count" -lt 2 ] && exit 0

cat >&2 <<EOF
⚠️  Blocking \`git push\` — HEAD is $count commits ahead of upstream.

Pushing carries every local commit ahead of the remote, not just the
one you authored. The list below MAY include parallel-session work,
hand-typed commits from another window, or earlier local-only work
that the user did not intend to publish in this push.

Commits that would land on the remote:
$unpushed

Decide before retrying:
  - All $count commits are intentional, in-CC-session push →
    \`touch /tmp/cc-gates/$session_id/skip_push_bundle_check\` then re-run.
  - All $count commits are intentional, interactive shell with env preset →
    \`export GIT_PUSH_BUNDLED_OK=1\` (in your shell BEFORE starting CC) and
    push from a new session. Inline \`VAR=1 cmd\` does NOT work — env
    doesn't reach PreToolUse hook child processes.
  - Some commits should not push yet → \`git reset --soft <keep-sha>\`,
    \`git rebase -i\`, or stash the unwanted commits to a branch first.
  - One of these is from a parallel CC session you don't control →
    surface it to the user and let them authorize.

Reference: \`feedback_check_push_payload.md\` in your project memory.
EOF

exit 2
