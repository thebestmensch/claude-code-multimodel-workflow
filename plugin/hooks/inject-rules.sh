#!/usr/bin/env bash
# claude-code-multimodel-workflow SessionStart hook: inject dispatch rules as additional context.
#
# Claude Code's plugin loader does not auto-inject markdown from a `rules/`
# directory the way it does for `skills/` or `agents/`. To make these rules
# active default behavior, we read every `*.md` under `${CLAUDE_PLUGIN_ROOT}/rules/`
# at session start and emit the concatenated content on stdout, which CC
# captures as additional system context.
#
# Adopters can disable by removing the SessionStart entry in the plugin's
# settings, or by deleting individual rule files.

set -o errexit -o pipefail -o nounset

rules_dir="${CLAUDE_PLUGIN_ROOT:-}/rules"

if [[ -z "${CLAUDE_PLUGIN_ROOT:-}" ]] || [[ ! -d "$rules_dir" ]]; then
  # Standalone install or no rules shipped: nothing to inject.
  exit 0
fi

shopt -s nullglob
files=("$rules_dir"/*.md)
shopt -u nullglob

if (( ${#files[@]} == 0 )); then
  exit 0
fi

printf '# claude-code-multimodel-workflow dispatch rules\n\n'
printf 'These rules govern how Claude dispatches subagents, code reviewers, '
printf 'visual QA, and Codex for cross-provider review in this session. '
printf 'Treat them as standing instructions until overridden.\n\n'

for f in "${files[@]}"; do
  name="$(basename "$f")"
  printf -- '---\n## %s\n\n' "$name"
  cat "$f"
  printf '\n'
done
