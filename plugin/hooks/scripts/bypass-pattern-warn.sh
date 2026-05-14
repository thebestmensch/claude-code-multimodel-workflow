#!/usr/bin/env bash
# PreToolUse on Bash — block commands that bypass safety gates.
#
# Origin: 2026-05-03 retro. After a pre-push hook fired (480 tests, real
# infra problem — missing `collectstatic` in worktree), I suggested
# `SKIP_PRE_PUSH_TESTS=1` as the next step. User pushed back: "why
# should we bypass?" — the gate was correct, the env was broken.
# Memory rule `feedback_never_default_bypass.md` already covered this
# (multiple prior corrections noted) — got skipped under momentum.
# Hook over rule.
#
# Patterns blocked (token-level match — must be actual argv tokens, not
# substrings inside quoted strings):
#  - SKIP_*=1 env-var prefix to a command (SKIP_PRE_PUSH_TESTS, etc.)
#  - --no-verify (git commit/push)
#  - --no-gpg-sign
#  - git push --force / git push -f (NOT --force-with-lease)
#  - git reset --hard
#  - git checkout .  /  git restore .  (whole-worktree discard)
#
# Each match emits a tailored block message naming the underlying
# concern, so the operator picks resolution (fix env, write the test,
# resolve drift) instead of routing around.
#
# Bypass paths (mirror git-push-bundled-commits-guard.sh):
#  1. BYPASS_PATTERN_WARN_OK=1 in the harness's startup env
#     (interactive shell, set BEFORE starting CC)
#  2. /tmp/cc-gates/<session_id>/skip_bypass_pattern_warn exists
#     (in-session, after explicit user authorization)
# Inline `VAR=1 cmd` does NOT propagate to PreToolUse hook child
# processes — env var only works when set in the parent shell.

set -o pipefail

[ "${BYPASS_PATTERN_WARN_OK:-}" = "1" ] && exit 0

input=$(cat)

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

if [ -n "$session_id" ] && [ -f "/tmp/cc-gates/$session_id/skip_bypass_pattern_warn" ]; then
  exit 0
fi

[ -z "$command" ] && exit 0

# Token-level pattern match. shlex respects quoting so commands like
# `printf '... --no-verify ...'` (the flag inside a quoted string) don't
# false-positive as actual --no-verify use.
match=$(printf '%s' "$command" | /usr/bin/python3 -c '
import shlex, sys, re
cmd = sys.stdin.read()
try:
    tokens = shlex.split(cmd, posix=True, comments=False)
except ValueError:
    sys.exit(0)

# 1. SKIP_*=1 env-var prefix (only as standalone token, before the command)
for t in tokens:
    if re.match(r"^SKIP_[A-Z_]+=1$", t):
        print(f"skip_env:{t}")
        sys.exit(0)
    # First non-VAR=value token marks end of env prefix region — stop scanning
    if "=" not in t.split("/")[-1]:
        break

# 2. --no-verify  /  --no-gpg-sign  (anywhere in argv)
for t in tokens:
    if t == "--no-verify":
        print("no_verify")
        sys.exit(0)
    if t == "--no-gpg-sign":
        print("no_gpg_sign")
        sys.exit(0)

# 3. git push --force / -f  (NOT --force-with-lease)
# 4. git reset --hard
# 5. git checkout . / git restore .
for i in range(len(tokens) - 1):
    if tokens[i] != "git":
        continue
    sub = tokens[i+1] if i+1 < len(tokens) else ""
    rest = tokens[i+2:]
    if sub == "push":
        for j, t in enumerate(rest):
            if t == "--force" or t == "-f":
                print("git_push_force")
                sys.exit(0)
            # --force-with-lease and --force-with-lease=... are safe
    elif sub == "reset":
        if "--hard" in rest:
            print("git_reset_hard")
            sys.exit(0)
    elif sub == "checkout":
        if "." in rest or "--" in rest and rest[-1] == ".":
            print("git_checkout_dot")
            sys.exit(0)
    elif sub == "restore":
        # `git restore .` or `git restore --staged .` or with --worktree
        if "." in rest:
            print("git_restore_dot")
            sys.exit(0)
' 2>/dev/null)

[ -z "$match" ] && exit 0

# Resolve match → human-readable block message.
case "$match" in
  skip_env:*)
    var="${match#skip_env:}"
    cat >&2 <<EOF
⚠️  Blocking command — \`$var\` bypasses a safety gate.

The gate fired for a reason. Investigate the underlying failure
(missing dep, broken env, real test failure) before bypassing.
This pattern has been corrected multiple times; the user does not
want bypass-as-default.

Examples of underlying causes for SKIP_PRE_PUSH_TESTS:
  - Worktree missing \`collectstatic\` (gitignored \`staticfiles/\`)
  - Worktree missing \`.env.development\` (gitignored)
  - Test fixtures stale (run with \`-x\` to find first failure)
  - Real regression introduced by your change (fix the test)

Reference: \`feedback_never_default_bypass.md\` in your project memory.

To override (after explicit user authorization):
  \`touch /tmp/cc-gates/$session_id/skip_bypass_pattern_warn\` then re-run.
EOF
    ;;
  no_verify)
    cat >&2 <<EOF
⚠️  Blocking command — \`--no-verify\` skips git hooks.

Hooks (pre-commit, commit-msg, pre-push) catch real issues.
Skipping them under momentum is how broken commits ship.

If a hook is firing falsely, fix the hook or the underlying state.
If a hook is firing correctly, do the work it's asking for.

Reference: \`feedback_never_default_bypass.md\` in your project memory.

To override (after explicit user authorization):
  \`touch /tmp/cc-gates/$session_id/skip_bypass_pattern_warn\` then re-run.
EOF
    ;;
  no_gpg_sign)
    cat >&2 <<EOF
⚠️  Blocking command — \`--no-gpg-sign\` bypasses commit signing.

If signing is failing, fix the signing setup (GPG agent, key access,
expired key) rather than producing unsigned commits in a signed repo.

To override (after explicit user authorization):
  \`touch /tmp/cc-gates/$session_id/skip_bypass_pattern_warn\` then re-run.
EOF
    ;;
  git_push_force)
    cat >&2 <<EOF
⚠️  Blocking command — \`git push --force\` (or \`-f\`) overwrites remote
history without checking what's there.

Use \`--force-with-lease\` instead — it refuses the push if the remote
moved (someone else pushed, parallel session, etc.) and the override
becomes a deliberate choice rather than a silent overwrite.

  git push --force-with-lease

If you genuinely need raw \`--force\` (rewriting history on a branch
nobody else has), state why and override:
  \`touch /tmp/cc-gates/$session_id/skip_bypass_pattern_warn\` then re-run.
EOF
    ;;
  git_reset_hard)
    cat >&2 <<EOF
⚠️  Blocking command — \`git reset --hard\` discards uncommitted work
and unbranched commits with no recovery path short of reflog.

Safer alternatives for common cases:
  - Discard one file:        \`git checkout HEAD -- <file>\`
  - Discard staged changes:  \`git reset HEAD\` (mixed, default)
  - Move HEAD, keep changes: \`git reset --soft <sha>\`
  - Stash before resetting:  \`git stash push -m '<reason>'\`

If the hard reset is genuinely intentional (clean slate before
re-applying a known-good state), state that and override:
  \`touch /tmp/cc-gates/$session_id/skip_bypass_pattern_warn\` then re-run.
EOF
    ;;
  git_checkout_dot)
    cat >&2 <<EOF
⚠️  Blocking command — \`git checkout .\` discards ALL uncommitted
worktree changes with no recovery.

If you mean to discard one file, name it explicitly:
  \`git checkout HEAD -- path/to/file\`

If you mean to discard everything (rare, deliberate), override:
  \`touch /tmp/cc-gates/$session_id/skip_bypass_pattern_warn\` then re-run.
EOF
    ;;
  git_restore_dot)
    cat >&2 <<EOF
⚠️  Blocking command — \`git restore .\` discards ALL uncommitted
worktree changes with no recovery.

If you mean to restore one file, name it explicitly:
  \`git restore path/to/file\`

If you mean to discard everything (rare, deliberate), override:
  \`touch /tmp/cc-gates/$session_id/skip_bypass_pattern_warn\` then re-run.
EOF
    ;;
esac

exit 2
