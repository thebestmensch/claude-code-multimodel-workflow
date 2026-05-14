#!/usr/bin/env bash
# Shared helper — copies a bypass invocation to the macOS clipboard so the
# user can paste-run rather than retype. Fail-soft by design: missing pbcopy,
# non-macOS, broken pipe → silent no-op. This is convenience plumbing, NOT a
# load-bearing security feature; the gate's own block message must still
# document the bypass command in plaintext for environments where pbcopy
# isn't available.
#
# Caller responsibility: pass the SHORTEST valid invocation, with placeholder
# tokens (e.g. REASON_HERE) the user can edit in place. The clipboard payload
# is the contract — if it's wrong, the user's paste is wrong.
#
# Usage:
#   source "$(dirname "$0")/_lib/pbcopy-bypass.sh"
#   pbcopy_bypass "echo 'REASON' > /tmp/cc-gates/$SID/skip_X_gate"

pbcopy_bypass() {
  local cmd="$1"
  [ -z "$cmd" ] && return 0
  command -v pbcopy >/dev/null 2>&1 || return 0
  printf '%s' "$cmd" | pbcopy 2>/dev/null || true
}
