#!/usr/bin/env bash
# Hook — tweakcc drift warn (SessionStart)
# Detects when CC's live binary version no longer matches what tweakcc has
# patched, so theming regressions don't arrive silently after auto-updates.
# Emits a warning to stdout (captured as additionalContext). Never blocks.
set -o pipefail

# Discard stdin (we don't need the session payload)
cat >/dev/null 2>&1 || true

config="$HOME/.tweakcc/config.json"
symlink="$HOME/.local/bin/claude"

# Soft-exit if either side is missing — nothing meaningful to check.
[ -f "$config" ] || exit 0
[ -L "$symlink" ] || exit 0

# Version tweakcc last patched against
patched_version=$(jq -r '.ccVersion // empty' "$config" 2>/dev/null)
# Version currently symlinked as live
live_target=$(readlink "$symlink")
live_version=$(basename "$live_target")

[ -z "$patched_version" ] && exit 0
[ -z "$live_version" ] && exit 0

if [ "$patched_version" != "$live_version" ]; then
  cat <<EOF
⚠ tweakcc drift detected (version mismatch)
  tweakcc patched: $patched_version
  live CC binary:  $live_version
  → Theming + prompt patches will NOT apply until you run:
      tweakcc-pin
  Then relaunch this CC session.
EOF
  exit 0
fi

# Content check: same version string but binary may have been re-downloaded
# or rolled back to upstream. Greps for a stable signature from the custom
# length-preserving prompt patches (prompt-patch.py). The literal string
# "tweakcc" is NOT a reliable marker on this pipeline — it sometimes lives
# inside Bun's compressed JS snapshot or is dropped by repack — so we instead
# check for a phrase prompt-patch.py injects and verify is present in the
# live binary as plaintext.
SIGNATURE='Err on the side of more explanation'
if [ -f "$live_target" ] && ! LANG=C grep -aqF "$SIGNATURE" "$live_target" 2>/dev/null; then
  cat <<EOF
⚠ tweakcc drift detected (binary reset)
  Version $live_version matches tweakcc config, but custom prompt patches are
  missing from the live binary — it was likely replaced (auto-update, manual
  reinstall, or upstream restore).
  → Run to re-apply theme + prompt patches:
      tweakcc-pin
  Then relaunch this CC session.
EOF
fi

exit 0
