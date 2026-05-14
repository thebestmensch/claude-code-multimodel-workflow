#!/usr/bin/env bash
# PreToolUse / Bash — blocks `chezmoi apply --force`.
#
# --force bypasses the "target has changed since last apply" safety check, which
# exists precisely to prevent silent data loss when source is stale. Reaching for
# --force to silence a warning has caused silent wipes of active target edits.
#
# Escape hatch for rare legitimate cases: set CHEZMOI_FORCE_OK=1 in the command
# itself, e.g. `CHEZMOI_FORCE_OK=1 chezmoi apply --force ...`. The presence of
# that env assignment signals the operator has accepted the risk.
set -o pipefail

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // empty')

# Strip heredoc bodies and quoted strings so the matcher doesn't false-positive
# on docs/messages that mention `chezmoi apply --force` literally (e.g. a
# `git commit -m "...<<EOF ... chezmoi apply --force ... EOF"` body).
stripped=$(printf '%s' "$command" | /usr/bin/python3 -c '
import sys, re
s = sys.stdin.read()
# Remove heredoc bodies: <<EOF ... EOF (and <<"EOF", <<-EOF, <<~EOF variants)
s = re.sub(r"<<-?~?\s*([\x27\x22]?)(\w+)\1.*?^\2\s*$", "", s, flags=re.DOTALL | re.MULTILINE)
# Remove single-quoted strings
s = re.sub(r"\x27[^\x27]*\x27", "", s)
# Remove double-quoted strings (handle escaped quotes)
s = re.sub(r"\x22(?:[^\x22\\\\]|\\\\.)*\x22", "", s)
print(s)
')

# Only gate when the STRIPPED command text shows chezmoi apply --force as an
# actual invocation (not a literal string in a message/heredoc)
case "$stripped" in
  *chezmoi*apply*--force*) ;;
  *) exit 0 ;;
esac

# Allow when explicitly authorized via env var in the command
if echo "$command" | grep -qE '(^|[^A-Za-z0-9_])CHEZMOI_FORCE_OK=1\b'; then
  exit 0
fi

cat >&2 <<'MSG'
BLOCKED: `chezmoi apply --force` bypasses the safety gate that detects
target-side edits. Using it with a stale source silently wipes those edits.

Before using --force:
  1. Read both copies to confirm direction:
       sed -n 'LINE,LINEp' <target>
       sed -n 'LINE,LINEp' $(chezmoi source-path <target>)
  2. Decide which copy has the edits you want to keep.
  3. If SOURCE is canonical: back up target, then run WITHOUT --force and
     address the prompt by confirming target will be overwritten.
  4. If TARGET is canonical: use `chezmoi re-add` instead (source <- target).

If you are certain --force is needed, prefix the command with
CHEZMOI_FORCE_OK=1 to bypass this gate.
MSG
exit 2
