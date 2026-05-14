#!/usr/bin/env bash
# UserPromptSubmit hook — detects magic keywords and injects skill routing hints.
# Runs BEFORE Claude processes the message, so the hint appears in context.
# Only matches keywords at word boundaries, not inside other words.
# Skips informational intent ("what is ralph", "how does teams work").
set -o pipefail

input=$(cat)
prompt=$(echo "$input" | jq -r '.prompt // empty')

[ -z "$prompt" ] && exit 0

# Lowercase for matching
lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')

# Skip informational intent — don't trigger skills for questions ABOUT the keyword
if echo "$lower" | grep -qE '(what is|what are|how does|how do|explain|tell me about|describe) .*(ralph|teams|debug|trace|simplif)'; then
  exit 0
fi

hints=""

# Ralph mode
if echo "$lower" | grep -qwE '(ralph|ralph mode|keep going|dont stop|don.t stop until)'; then
  hints="${hints}Use /ralph to activate persistent execution mode for this goal.\n"
fi

# Teams
if echo "$lower" | grep -qwE '(team up|use teams|agent teams)'; then
  hints="${hints}Use /teams to orchestrate coordinated agents.\n"
fi

# Debugging
if echo "$lower" | grep -qwE '(debug this|trace this|root cause|why is .* broken|why is .* failing)'; then
  hints="${hints}Use superpowers:systematic-debugging for structured root cause investigation.\n"
fi

# Simplify
if echo "$lower" | grep -qwE '(simplify|clean up code|refactor for clarity)'; then
  hints="${hints}Use /simplify to review recently modified code for clarity and maintainability.\n"
fi

# Output hints if any matched
if [ -n "$hints" ]; then
  printf "$hints"
fi

exit 0
