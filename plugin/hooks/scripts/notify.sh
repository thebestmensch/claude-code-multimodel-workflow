#!/bin/bash
# Notify when Claude Code needs attention.
# macOS notification via osascript + terminal bell.

INPUT=$(cat)
NOTIF_TYPE=$(echo "$INPUT" | jq -r '.notification_type // empty')

case "$NOTIF_TYPE" in
  permission_prompt) MSG="Waiting for permission" ;;
  idle_prompt)       MSG="Waiting for input" ;;
  *)                 MSG="Needs attention" ;;
esac

# Suppress only if this tmux pane is the active one AND Ghostty is focused
FOCUSED=$(osascript -e 'tell application "System Events" to name of first process whose frontmost is true' 2>/dev/null)
if [[ "$FOCUSED" == "Ghostty" ]]; then
  ACTIVE_PANE=$(tmux display-message -p '#{pane_id}' 2>/dev/null)
  MY_PANE=${TMUX_PANE:-}
  if [[ -n "$MY_PANE" && "$ACTIVE_PANE" == "$MY_PANE" ]]; then
    exit 0
  fi
fi

# Terminal bell
printf '\a'

# Custom sound (uncomment and point at any audio file you have)
# afplay "$HOME/path/to/your-sound.mp3" &

# Session name from tmux
SESSION=$(tmux display-message -p '#{session_name}' 2>/dev/null || echo "claude")

# macOS notification via osascript
osascript -e "display notification \"$MSG\" with title \"Claude Code [$SESSION]\"" &>/dev/null &

exit 0
