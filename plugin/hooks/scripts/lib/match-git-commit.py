#!/usr/bin/env python3
"""Shared matcher: returns "match" iff the given shell command invokes
`git commit` as an actual program token (not as a substring inside a quoted
arg to printf/echo/pbcopy/etc.).

Used by both ~/.claude/hooks/codex-pre-commit-gate.sh and
~/.claude/hooks/pre-commit-gate.sh — same matcher, two gates, no drift.

Usage (script): python3 match-git-commit.py "<shell command>"
  exit 0 + stdout "match" iff `git commit` invocation detected.
  exit 0 + no stdout otherwise.
  Always exits 0 — caller checks stdout.

Tolerated invocation shapes (Codex flagged these as bypasses; closed):
  git commit
  git -c user.name=bot commit
  git --no-pager commit
  git -C /path/to/repo commit
  /usr/bin/git commit                  (absolute path)
  /opt/homebrew/bin/git commit         (absolute path)
  FOO=bar git commit                   (env-var assignment prefix)
  env FOO=bar git commit               (env wrapper)
  command git commit                   (builtin wrapper)
  exec git commit                      (exec wrapper)
  nohup git commit                     (nohup wrapper)
  bash -c "git commit"                 (shell -c payload)
  bash -lc "git commit"                (shell short-flag cluster)
  git add . && git commit              (compound segment)

NOT matched (intentional):
  sudo git commit                      (sudo changes user; explicit operator action)
  /usr/bin/giff commit                 (basename != "git")
  printf "git commit"                  (inside quoted arg, single token)
"""
import os
import re
import shlex
import subprocess
import sys

WRAPPERS = {"env", "command", "exec", "nohup"}
SHELL_WRAPPERS = {"bash", "sh", "zsh", "fish", "dash", "ksh"}
GIT_TAKES_ARG = {"-c", "-C", "--git-dir", "--work-tree", "--namespace", "--exec-path"}
# `env` flags that take a separate operand. `-S` carries a shell-formatted
# command payload; we split + recurse into it. Conservative: any unknown env
# flag is treated as taking-an-arg to avoid silently consuming the program.
ENV_TAKES_ARG = {"-u", "-S", "--unset", "--split-string", "--chdir", "-C"}

_ALIAS_NAME_RE = re.compile(r"^[A-Za-z0-9._-]+$")


def is_assignment(tok: str) -> bool:
    """FOO=bar style prefix (variable name LHS, anything RHS)."""
    if tok.startswith("-") or "=" not in tok:
        return False
    lhs = tok.split("=", 1)[0]
    return bool(lhs) and lhs.replace("_", "").isalnum()


def _alias_resolves_to_commit(name: str) -> bool:
    """Check global git aliases for `name`. If the expansion begins with
    `commit` (followed by whitespace or end), treat as a commit invocation.
    Local-repo aliases are intentionally not consulted here — that would
    require knowing the repo cwd at hook time and complicates the contract."""
    if not _ALIAS_NAME_RE.match(name):
        return False
    try:
        result = subprocess.run(
            ["git", "config", "--global", "--get-all", f"alias.{name}"],
            capture_output=True, text=True, timeout=1,
        )
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        return False
    if result.returncode != 0:
        return False
    for line in result.stdout.splitlines():
        line = line.strip()
        # Shell aliases (`!sh -c "..."`), treat as commit conservatively
        # only if the shell payload mentions `git commit`. Otherwise skip.
        if line.startswith("!"):
            if "git commit" in line:
                return True
            continue
        first = line.split(None, 1)[0] if line else ""
        if first == "commit":
            return True
    return False


def matches_git_commit(tokens: list[str]) -> bool:
    i = 0
    while i < len(tokens):
        tok = tokens[i]
        if is_assignment(tok):
            i += 1
            continue
        # Shell wrapper invoking a payload via -c: bash/sh/zsh/fish/dash/ksh.
        # Match on basename so `/bin/bash -c "git commit"` is caught. Also
        # recognize short-flag clusters ending in `c` (e.g. `bash -lc CMD`,
        # `bash -lic CMD`), `-c` must be last in the cluster because it
        # consumes the next argv.
        if os.path.basename(tok) in SHELL_WRAPPERS:
            j = i + 1
            while j < len(tokens):
                flag = tokens[j]
                # Bare -c, or short cluster ending in c (-lc, -lic, etc.).
                is_dash_c = flag == "-c" or (
                    len(flag) >= 2
                    and flag.startswith("-")
                    and not flag.startswith("--")
                    and flag.endswith("c")
                    and flag[1:].isalpha()
                )
                if is_dash_c and j + 1 < len(tokens):
                    payload = tokens[j + 1]
                    for seg in split_segments(payload):
                        try:
                            seg_tokens = shlex.split(seg, posix=True, comments=False)
                        except ValueError:
                            return True  # fail-closed
                        if matches_git_commit(seg_tokens):
                            return True
                    j += 2
                    continue
                if flag.startswith("-"):
                    j += 1
                    continue
                break
            return False  # shell without -c (e.g. `bash script.sh`)
        if tok in WRAPPERS:
            j = i + 1
            while j < len(tokens) and tokens[j].startswith("-"):
                flag = tokens[j]
                if flag.startswith("--") and "=" in flag:
                    j += 1
                    continue
                # -S<payload> stuck-together form (no space): peel and recurse.
                if tok == "env" and flag.startswith("-S") and len(flag) > 2:
                    try:
                        sub = shlex.split(flag[2:], posix=True, comments=False)
                    except ValueError:
                        return True
                    if matches_git_commit(sub):
                        return True
                    j += 1
                    continue
                # -S <payload>: consume operand, recurse.
                if tok == "env" and flag == "-S" and j + 1 < len(tokens):
                    try:
                        sub = shlex.split(tokens[j + 1], posix=True, comments=False)
                    except ValueError:
                        return True
                    if matches_git_commit(sub):
                        return True
                    j += 2
                    continue
                if tok == "env" and flag in ENV_TAKES_ARG and j + 1 < len(tokens):
                    j += 2
                    continue
                j += 1
            if tok == "env":
                while j < len(tokens) and is_assignment(tokens[j]):
                    j += 1
            i = j
            continue
        break

    if i >= len(tokens) or os.path.basename(tokens[i]) != "git":
        return False

    j = i + 1
    while j < len(tokens):
        nxt = tokens[j]
        if nxt.startswith("--") and "=" in nxt:
            j += 1
            continue
        if nxt in GIT_TAKES_ARG:
            j += 2
            continue
        if nxt.startswith("-"):
            j += 1
            continue
        if nxt == "commit":
            return True
        return _alias_resolves_to_commit(nxt)
    return False


def split_segments(s: str) -> list[str]:
    """Split a shell command into segments separated by &&, ||, ;, |, newline,
    respecting single/double quotes and backslash escapes. Each segment is the
    text BEFORE the operator. Use to catch compound shells like
    `git add . && git commit` where the gated subcommand is not the first
    program token."""
    out: list[str] = []
    buf: list[str] = []
    i, n = 0, len(s)
    quote: str | None = None
    while i < n:
        ch = s[i]
        if quote is not None:
            buf.append(ch)
            if ch == "\\" and quote == "\"" and i + 1 < n:
                buf.append(s[i + 1])
                i += 2
                continue
            if ch == quote:
                quote = None
            i += 1
            continue
        if ch in ("\"", "'"):
            quote = ch
            buf.append(ch)
            i += 1
            continue
        if ch == "\\" and i + 1 < n:
            buf.append(ch)
            buf.append(s[i + 1])
            i += 2
            continue
        if s[i : i + 2] in ("&&", "||"):
            out.append("".join(buf))
            buf = []
            i += 2
            continue
        if ch in (";", "|", "\n", "&"):
            out.append("".join(buf))
            buf = []
            i += 1
            continue
        buf.append(ch)
        i += 1
    if buf:
        out.append("".join(buf))
    return [seg.strip() for seg in out if seg.strip()]


def is_git_commit(cmd: str) -> bool:
    """Module-level entry point. Returns True iff `cmd` invokes git commit."""
    for segment in split_segments(cmd):
        try:
            seg_tokens = shlex.split(segment, posix=True, comments=False)
        except ValueError:
            continue
        if matches_git_commit(seg_tokens):
            return True
    return False


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(0)
    if is_git_commit(sys.argv[1]):
        print("match")
    sys.exit(0)
