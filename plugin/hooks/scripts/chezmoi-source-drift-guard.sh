#!/usr/bin/env bash
# PreToolUse on Edit/Write — block source-side edits to chezmoi files when the
# corresponding TARGET has drifted from source. Forces the operator to read
# both copies and decide direction before touching the source.
#
# Origin: 2026-04-25 retro. Edited the chezmoi source for `visor-hud.sh`
# under the assumption it was canonical, when the target had a substantial
# newer redesign. Source-side edits would have rolled back the target on
# the next `chezmoi apply`. The existing target-edit-warn hook didn't fire
# because the path was under the source tree, not under $HOME.
#
# Behavior: scoped to the SPECIFIC file being edited — unrelated drift in
# other managed files does NOT block this edit. Only the corresponding
# target's drift counts.
#
# Escape hatch: set CHEZMOI_SOURCE_EDIT_OK=1 in the environment when source
# is genuinely canonical and the target needs to be brought into line via
# `chezmoi apply`. The variable signals operator has read both copies.

set -o pipefail

[ "${CHEZMOI_SOURCE_EDIT_OK:-}" = "1" ] && exit 0
command -v chezmoi >/dev/null 2>&1 || exit 0

input=$(cat)
file_path=$(printf '%s' "$input" | /usr/bin/python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get("tool_input", {}).get("file_path", ""))
except Exception:
    pass
' 2>/dev/null)

[ -z "$file_path" ] && exit 0

# Resolve chezmoi source root once — fast, just reads config
src_root=$(chezmoi source-path 2>/dev/null)
[ -z "$src_root" ] && exit 0

# Only fire on edits inside the chezmoi source tree
case "$file_path" in
  "$src_root"/*) ;;
  *) exit 0 ;;
esac

# Compute the target path for this specific source file. chezmoi has a
# `target-path` subcommand that does the inverse mapping, including all
# attribute decoders (dot_, executable_, private_, encrypted_, etc.).
target_path=$(chezmoi target-path "$file_path" 2>/dev/null)
[ -z "$target_path" ] && exit 0

# If the target file doesn't exist on disk, there are no uncaptured edits to
# protect. This covers two false-positive cases: (1) run_once_* scripts that
# execute but never write a target, (2) cross-OS files (e.g. a Linux-only
# binary on a Mac source-of-truth machine) where chezmoi apply was never run.
# In both cases `chezmoi diff` shows "new file" which the bare empty-check
# below would mistake for drift.
[ -e "$target_path" ] || exit 0

# Run chezmoi diff scoped to JUST this target. Empty output = no drift.
diff_output=$(chezmoi diff "$target_path" 2>/dev/null)
[ -z "$diff_output" ] && exit 0

# Drift exists for THIS target. Block the source-side edit.
cat >&2 <<EOF
⚠️  Blocking source-side edit on a chezmoi file with target drift.

  Source:  $file_path
  Target:  $target_path

The TARGET has uncaptured edits that differ from source. Editing the source
now will produce changes against a stale baseline; running \`chezmoi apply\`
later would roll back the target's in-place work.

Required next steps:
  1. Read both copies and decide which is canonical:
       sed -n '1,80p' "$target_path"
       sed -n '1,80p' "$file_path"
  2. If the TARGET is canonical (in-place edits you want to keep):
       chezmoi re-add "$target_path"
     ...then re-attempt this edit.
  3. If the SOURCE is canonical and you intend to roll back the target:
       CHEZMOI_SOURCE_EDIT_OK=1  (set in env, not in the command)
     ...then re-attempt this edit.

Inspect the drift:
  chezmoi diff "$target_path"
EOF
exit 2
