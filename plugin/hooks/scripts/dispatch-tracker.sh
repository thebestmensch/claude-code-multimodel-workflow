#!/usr/bin/env bash
# Dispatch Tracker (PostToolUse on Agent|Skill)
# Tracks when review agents/skills are dispatched by touching marker files
# under /tmp/cc-gates/$session_id/. Silent bookkeeper; no output.
# Other gate hooks (visual-qa-stop-gate, codex-stop-gate, etc.) read these
# markers to decide whether the required review fired before stop.
set -o pipefail

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
tool_name=$(echo "$input" | jq -r '.tool_name // empty')

[ -z "$session_id" ] && exit 0

gate_dir="/tmp/cc-gates/$session_id"
[ -d "$gate_dir" ] || exit 0

if [ "$tool_name" = "Agent" ]; then
  desc=$(echo "$input" | jq -r '.tool_input.description // empty' | tr '[:upper:]' '[:lower:]')

  case "$desc" in
    *visual-qa*|*visual\ qa*|*vqa*) touch "$gate_dir/visual_qa_dispatched" ;;
  esac
  case "$desc" in
    *code-review*|*code\ review*|*code\ reviewer*) touch "$gate_dir/code_review_dispatched" ;;
  esac
  case "$desc" in
    *brainstorm*) touch "$gate_dir/brainstorm_dispatched" ;;
  esac
  case "$desc" in
    *frontend*design*|*design*frontend*) touch "$gate_dir/frontend_design_dispatched" ;;
  esac
  case "$desc" in
    *devils-advocate*|*devil\'s\ advocate*|*devils\ advocate*) touch "$gate_dir/devils_advocate_dispatched" ;;
  esac
  case "$desc" in
    *sentry-discipline*|*sentry\ discipline*) touch "$gate_dir/sentry_review_dispatched" ;;
  esac
  # Codex cross-provider review (added 2026-05-04): Agent dispatches by
  # description set the *plan* marker, not the diff marker, because the
  # rescue subagent forwards to `codex-companion.mjs task` internally (plan-
  # mode / diagnosis path). Diff review goes through Bash review/adversarial-
  # review, tracked by codex-bash-tracker.sh.
  case "$desc" in
    *codex*review*|*codex*rescue*|*codex*plan*) touch "$gate_dir/codex_plan_dispatched" ;;
  esac

  # Also catch subagent_type-based dispatches where description omits the agent name
  subagent_type=$(echo "$input" | jq -r '.tool_input.subagent_type // empty' | tr '[:upper:]' '[:lower:]')
  case "$subagent_type" in
    *devils-advocate*) touch "$gate_dir/devils_advocate_dispatched" ;;
  esac
  case "$subagent_type" in
    *code-reviewer*|*code-review*) touch "$gate_dir/code_review_dispatched" ;;
  esac
  case "$subagent_type" in
    *visual-qa*) touch "$gate_dir/visual_qa_dispatched" ;;
  esac
  case "$subagent_type" in
    *sentry-discipline-reviewer*) touch "$gate_dir/sentry_review_dispatched" ;;
  esac
  # Codex rescue subagent → plan marker (forwards to codex-companion.mjs task)
  case "$subagent_type" in
    *codex*rescue*|*codex-rescue*|codex:codex-rescue) touch "$gate_dir/codex_plan_dispatched" ;;
  esac

elif [ "$tool_name" = "Skill" ]; then
  skill=$(echo "$input" | jq -r '.tool_input.skill // empty' | tr '[:upper:]' '[:lower:]')

  case "$skill" in
    *visual-qa*|*visual\ qa*|*vqa*) touch "$gate_dir/visual_qa_dispatched" ;;
  esac
  case "$skill" in
    *code-review*|*code\ review*)
      touch "$gate_dir/code_review_dispatched"
      # Also clear the SDD code review flag (skill-based review counts)
      rm -f "$gate_dir/sdd_needs_code_review"
      ;;
  esac
  case "$skill" in
    *brainstorm*) touch "$gate_dir/brainstorm_dispatched" ;;
  esac
  case "$skill" in
    *frontend*design*|*frontend-design*) touch "$gate_dir/frontend_design_dispatched" ;;
  esac
  case "$skill" in
    *devils-advocate*) touch "$gate_dir/devils_advocate_dispatched" ;;
  esac
fi

exit 0
