#!/usr/bin/env bash
# PostToolUse hook: warn when an Edit/Write modified a chezmoi-managed target.
# Memory entry [Chezmoi-aware dotfile editing] fires silently otherwise — this makes it loud.

set -o pipefail

# chezmoi not installed → nothing to check
command -v chezmoi >/dev/null 2>&1 || exit 0

# Read hook input (JSON on stdin)
input=$(cat)

# Extract file_path from tool input (Edit/Write both use file_path)
file_path=$(printf '%s' "$input" | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null)

[ -z "$file_path" ] && exit 0
[ ! -e "$file_path" ] && exit 0

# Only care about paths under $HOME
case "$file_path" in
  "$HOME"/*) ;;
  *) exit 0 ;;
esac

# Resolve to absolute (chezmoi managed emits paths relative to $HOME without leading $HOME)
rel_path="${file_path#$HOME/}"

# chezmoi managed is fast (reads manifest); check membership
if chezmoi managed 2>/dev/null | grep -qxF "$rel_path"; then
  src_path=$(chezmoi source-path "$file_path" 2>/dev/null)
  # Templates can't round-trip via `chezmoi re-add` — it silently no-ops because
  # chezmoi can't reverse-engineer template directives from a rendered file.
  # For .tmpl sources, the only fix is to edit the source directly.
  if [ -n "$src_path" ] && [ "${src_path##*.}" = "tmpl" ]; then
    printf >&2 '⚠️  %s is a chezmoi TEMPLATE — `chezmoi re-add` will silently no-op.\n   Edit the source directly with the env-var escape hatch:\n     CHEZMOI_SOURCE_EDIT_OK=1  (set in env, not in the command)\n   Source: %s\n   Otherwise next `chezmoi apply` will silently revert this change.\n' "$file_path" "$src_path"
  else
    printf >&2 '⚠️  %s is chezmoi-managed — run `chezmoi re-add %s` NOW so the edit lands in source. Otherwise next `chezmoi apply` will silently revert this change.\n' "$file_path" "$file_path"
  fi
  # exit 2 surfaces stderr to Claude so the warning is actionable, not silent.
  exit 2
fi

exit 0
