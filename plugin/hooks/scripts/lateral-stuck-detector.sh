#!/usr/bin/env bash
# Hook: Lateral Stuck Detector
# Two trigger surfaces:
#   1. UserPromptSubmit: detects frustration keywords in user prompt
#   2. PostToolUse(Edit|Write): detects 4+ edits to the same file in this session
# When triggered, injects a context note nudging the main session to /lateral.
# Self-silences for the rest of the session once /lateral runs (lateral_dispatched marker).
set -o pipefail

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

gate_dir="/tmp/cc-gates/$session_id"
mkdir -p "$gate_dir"

# Once /lateral has fired this session, stop nudging (cap = 1 per session).
[ -f "$gate_dir/lateral_dispatched" ] && exit 0

# Cooldown: at most one nudge per 5 user prompts to avoid spam.
nudge_count_file="$gate_dir/lateral_nudge_count"
last_nudge_file="$gate_dir/lateral_nudge_last_prompt"

hook_event=$(echo "$input" | jq -r '.hook_event_name // empty')

case "$hook_event" in
  UserPromptSubmit)
    # Fast-path skip when nudge already emitted this session; atomic claim
    # below handles the race; this just avoids the regex work in the common case.
    [ -f "$gate_dir/lateral_nudge_emitted" ] && exit 0

    prompt=$(echo "$input" | jq -r '.prompt // empty' | tr '[:upper:]' '[:lower:]')
    [ -z "$prompt" ] && exit 0

    # Frustration / stuck signals (word-boundary matches only)
    stuck=0
    if echo "$prompt" | grep -qwE "(still (broken|failing|not working)|tried (everything|three|3|four|4) times|i'?m stuck|we'?re stuck|stuck on this|can'?t figure (this|it) out|same error again|keeps failing|why doesn'?t this work|this isn'?t working|i give up|nothing works)"; then
      stuck=1
    fi

    [ "$stuck" -eq 0 ] && exit 0

    # Inject context note. UserPromptSubmit hooks emit stdout as context.
    # Atomically claim emission via noclobber so two concurrent hooks cannot
    # both pass the earlier check-then-act window.
    if ( set -o noclobber; : > "$gate_dir/lateral_nudge_emitted" ) 2>/dev/null; then
      printf "Stuck-signal detected in user prompt. Consider invoking /lateral to fan out 5 reframing personas (hacker, researcher, simplifier, architect, contrarian) in parallel. One announce-line, then 5 parallel Agent calls. Only fires once per session.\n"
    fi
    exit 0
    ;;

  PostToolUse)
    tool_name=$(echo "$input" | jq -r '.tool_name // empty')
    case "$tool_name" in
      Edit|Write|NotebookEdit) ;;
      *) exit 0 ;;
    esac

    file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
    [ -z "$file_path" ] && exit 0

    # Increment per-file edit counter
    counter_dir="$gate_dir/edit_counts"
    mkdir -p "$counter_dir"
    # Hash the path so filenames stay short and shell-safe
    if command -v shasum >/dev/null 2>&1; then
      hash=$(printf "%s" "$file_path" | shasum | awk '{print $1}' | cut -c1-12)
    elif command -v sha1sum >/dev/null 2>&1; then
      hash=$(printf "%s" "$file_path" | sha1sum | awk '{print $1}' | cut -c1-12)
    else
      hash=$(printf "%s" "$file_path" | openssl sha1 | awk '{print $NF}' | cut -c1-12)
    fi
    counter_file="$counter_dir/$hash"

    if [ -f "$counter_file" ]; then
      count=$(cat "$counter_file")
      count=$((count + 1))
    else
      count=1
    fi
    echo "$count" > "$counter_file"

    # Nudge at exactly 4 edits to the same file (not 5+ to avoid repeats)
    if [ "$count" -eq 4 ]; then
      base=$(basename "$file_path")
      jq -nc --arg base "$base" '{
        hookSpecificOutput: {
          hookEventName: "PostToolUse",
          additionalContext: ("Same file edited 4 times this session: \($base). If you keep retrying the same fix shape, consider /lateral (5 reframing personas in parallel) to break out of the local-minimum approach.")
        }
      }'
    fi
    exit 0
    ;;

  *)
    exit 0
    ;;
esac
