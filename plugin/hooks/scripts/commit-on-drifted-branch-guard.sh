#!/usr/bin/env bash
# PreToolUse on Bash, block `git commit` when committing on a primary
# checkout that's drifted off the default branch (main/master).
#
# Origin: 2026-05-02 retro. SessionStart fired the drift warning at
# session start (`jm/rename-ticket-commands-linear-prefix`, expected main).
# Mid-session, user requested commit + push of code-review lens work
# (unrelated topic). I committed on the drifted branch instead of
# proposing a branch correction first. Memory rule
# `feedback_drift_warning_revisit_at_commit.md` covers the lesson —
# this hook makes drift-state revisit non-skippable at commit time.
#
# Behavior:
# - Triggers only on `git commit` (token-adjacent), skips `--amend`
# - Skips when in a linked worktree (drift impossible, convention)
# - Skips when on the default branch
# - Skips when the operation isn't a primary-checkout drift
# - Otherwise: BLOCK with the SessionStart drift message + a directive
#   to propose a branch correction OR explicitly bypass if the work
#   genuinely belongs on this branch
#
# Companions: complements `git-push-bundled-commits-guard.sh` (catches
# multi-commit pushes) and `pre-commit-gate.sh` (catches QA-skip
# commits). This hook fills the single gap they leave: a single,
# topic-mismatched commit on a drifted primary checkout.
#
# Escape hatches:
#  1. GIT_COMMIT_ON_DRIFTED_BRANCH_OK=1 in the harness's startup env
#     (interactive shell, set BEFORE starting the CC session)
#  2. Two-step user-approved bypass (mirrors pre-commit-gate.sh's pattern,
#     but uses a DRIFT-SPECIFIC approval token to avoid cross-gate leak):
#       a. Claude writes reasoning:
#            echo 'reason' > /tmp/cc-gates/<session>/skip_commit_drift_gate
#       b. User approves in their own shell (the `!` prefix matters):
#            ! echo approved > /tmp/cc-gates/<session>/bypass_commit_drift_approved
#     Claude cannot bypass alone, step (b) runs in the user's shell.
#     Both files are consumed by commit-gate-cleanup.sh on successful commit.
#     Why a drift-specific approval (not the shared `bypass_approved`):
#     `bypass_approved` also releases pre-commit-gate.sh's visual-qa /
#     code-review checks. A drift approval (branch/topic fit) and a QA
#     approval (UI was reviewed) are different intents, sharing the token
#     would let a drift bypass silently waive QA. Codex review caught this.

set -o pipefail

[ "${GIT_COMMIT_ON_DRIFTED_BRANCH_OK:-}" = "1" ] && exit 0

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

# Two-step bypass. REQUIRES BOTH a Claude-written reason AND a drift-specific
# user approval. Uses bypass_commit_drift_approved (not the shared
# bypass_approved) so a drift approval cannot silently waive pre-commit-gate's
# visual-qa / code-review requirements.
if [ -n "$session_id" ]; then
  bypass_request="/tmp/cc-gates/$session_id/skip_commit_drift_gate"
  bypass_approved="/tmp/cc-gates/$session_id/bypass_commit_drift_approved"
  if [ -f "$bypass_request" ] && [ -f "$bypass_approved" ]; then
    approval=$(cat "$bypass_approved" 2>/dev/null | tr -d '[:space:]')
    if [ "$approval" = "approved" ]; then
      reason=$(cat "$bypass_request" 2>/dev/null)
      [ -z "$reason" ] && reason="(no reason recorded)"
      echo "$(date '+%Y-%m-%d %H:%M:%S') | drift-gate | USER APPROVED | $reason" \
        >> "/tmp/cc-gates/$session_id/bypass_log.txt" 2>/dev/null
      exit 0
    fi
  fi
fi

# Token-level match, `git commit` must be ADJACENT argv tokens.
# Also detect `--amend` (amending a commit doesn't change branch state).
match_info=$(printf '%s' "$command" | /usr/bin/python3 -c '
import shlex, sys
cmd = sys.stdin.read()
try:
    tokens = shlex.split(cmd, posix=True, comments=False)
except ValueError:
    sys.exit(0)
matched = False
amend = False
for i in range(len(tokens) - 1):
    if tokens[i] == "git" and tokens[i+1] == "commit":
        matched = True
        # Look for --amend in remaining tokens up to the next shell separator
        for t in tokens[i+2:]:
            if t in ("&&", "||", ";", "|"):
                break
            if t == "--amend":
                amend = True
                break
        break
if matched and not amend:
    print("match")
' 2>/dev/null)
[ "$match_info" != "match" ] && exit 0

# Resolve cwd. If the command is `cd <path> && git commit ...`, use that path.
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

# In a git repo?
git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1 || exit 0

# Linked worktree → fine, exit silently. Drift is a primary-checkout concern.
git_dir=$(git -C "$cwd" rev-parse --git-dir 2>/dev/null)
common_dir=$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null)
[ -d "$git_dir" ] && git_dir=$(cd "$git_dir" && pwd -P)
[ -d "$common_dir" ] && common_dir=$(cd "$common_dir" && pwd -P)
[ "$git_dir" != "$common_dir" ] && exit 0

# Determine the default branch.
default_branch=""
if git -C "$cwd" symbolic-ref refs/remotes/origin/HEAD >/dev/null 2>&1; then
  default_branch=$(git -C "$cwd" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
fi
if [ -z "$default_branch" ]; then
  if git -C "$cwd" show-ref --verify --quiet refs/heads/main; then
    default_branch="main"
  elif git -C "$cwd" show-ref --verify --quiet refs/heads/master; then
    default_branch="master"
  fi
fi
[ -z "$default_branch" ] && exit 0

branch=$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null)
[ -z "$branch" ] && exit 0
[ "$branch" = "$default_branch" ] && exit 0

# Drifted. Gather context for the deny message: branch's recent commit
# subjects (what topic does this branch own?) so the operator can compare
# against the staged diff.
recent_subjects=$(git -C "$cwd" log --oneline -5 "$branch" 2>/dev/null)
staged_files=$(git -C "$cwd" diff --cached --name-only 2>/dev/null | head -10)

cat >&2 <<EOF
⚠️  Blocking \`git commit\` — primary checkout drifted off default branch.

  Tree:    $cwd
  Branch:  $branch (expected: $default_branch)

The convention is: feature work happens in a linked worktree
(.claude/worktrees/<slug>); the primary checkout stays on $default_branch.
Committing here on the drifted branch silently bundles work into this
branch's PR — fine if the work belongs to the branch's topic, a mistake
if it doesn't.

Branch's recent commits (what is this branch about?):
$recent_subjects

Staged files (what are you about to commit?):
$staged_files

Decide before retrying:
  - Staged work is unrelated to the branch's topic → propose a branch
    correction:
      \`git stash push -u -m "wip-\$(date +%Y-%m-%d)"\`
      \`git checkout $default_branch\`
      \`git checkout -b <topic-branch>\` (or worktree)
      \`git stash pop\`
    Then retry the commit on the new branch.
  - Staged work matches the branch's topic → request bypass (TWO STEPS):
      1. Claude writes the reason:
           echo 'topic-match reasoning' > /tmp/cc-gates/$session_id/skip_commit_drift_gate
      2. User approves in their own shell (note the leading \`!\`):
           ! echo approved > /tmp/cc-gates/$session_id/bypass_commit_drift_approved
    Then re-run the commit. Claude cannot bypass alone — step (2) must
    run in the user's shell. The previous one-step \`touch skip_commit_drift_check\`
    bypass is gone (Claude could self-approve).
  - Working from interactive shell with env preset →
    \`export GIT_COMMIT_ON_DRIFTED_BRANCH_OK=1\` in your shell BEFORE
    starting CC. Inline \`VAR=1 cmd\` does NOT work — env doesn't
    propagate to PreToolUse hook child processes.

Reference: \`feedback_drift_warning_revisit_at_commit.md\` in project memory.
EOF

exit 2
