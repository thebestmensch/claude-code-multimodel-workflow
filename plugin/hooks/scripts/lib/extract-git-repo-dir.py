#!/usr/bin/env python3
"""Extract the target git repo directory from a shell command.

Used by codex-pre-commit-gate.sh to determine which repo the about-to-run
`git commit` is actually committing to, when the command is `cd X && git
commit` or `git -C X commit`. The augmenter then reads the right repo's
staged diff instead of falling back to $PWD (the harness's session cwd,
not the bash subprocess's cwd).

Usage: python3 extract-git-repo-dir.py "<shell command>"
  Prints the resolved repo directory on stdout (with ~ expanded), or nothing
  if neither `cd` nor `git -C` was present. Caller is expected to default
  to $PWD when stdout is empty. Always exits 0.

Precedence (last-wins within each class, -C beats cd):
  git -C <path> commit          # explicit git flag wins
  cd <path> && git commit       # cwd-change
  (else)                        # caller defaults to $PWD

Closes Codex slice-4 H2 finding: pre-commit gate uses $PWD for repo
discovery, which is wrong when the bash command runs `git commit` against
a different repo than the harness's session cwd.
"""
from __future__ import annotations

import os
import shlex
import sys


def extract(cmd: str) -> str | None:
    try:
        tokens = shlex.split(cmd, posix=True, comments=False)
    except ValueError:
        return None

    last_cd: str | None = None
    last_c_flag: str | None = None

    i = 0
    while i < len(tokens):
        tok = tokens[i]
        # `cd <path>`, only treat as cwd-change when path isn't a flag.
        # `cd -` (jump to previous dir) is not supportable here.
        if tok == "cd" and i + 1 < len(tokens):
            nxt = tokens[i + 1]
            if not nxt.startswith("-"):
                last_cd = os.path.expanduser(nxt)
            i += 2
            continue
        # `git ... -C <path> ... <subcmd>`, walk options looking for -C.
        # Basename comparison so /usr/bin/git is matched too.
        if os.path.basename(tok) == "git":
            j = i + 1
            while j < len(tokens):
                if tokens[j] == "-C" and j + 1 < len(tokens):
                    last_c_flag = os.path.expanduser(tokens[j + 1])
                    j += 2
                    continue
                if tokens[j].startswith("--git-dir=") and len(tokens[j]) > len("--git-dir="):
                    # --git-dir points at the .git directory; derive the repo
                    # root by trimming /.git if present.
                    gd = os.path.expanduser(tokens[j].split("=", 1)[1])
                    last_c_flag = gd[:-5] if gd.endswith("/.git") else gd
                    j += 1
                    continue
                if tokens[j].startswith("-"):
                    j += 1
                    continue
                # Reached the subcommand. Stop scanning this git invocation.
                break
            i = j if j > i else i + 1
            continue
        i += 1

    return last_c_flag or last_cd


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(0)
    result = extract(sys.argv[1])
    if result:
        print(result)
    sys.exit(0)
