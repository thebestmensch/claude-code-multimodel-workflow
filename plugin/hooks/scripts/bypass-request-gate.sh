#!/usr/bin/env bash
# bypass-request-gate - blocks writing to skip_*_gate before any QA attempt.
#
# Rationale: feedback_never_default_bypass - run /visual-qa or /code-review
# first, bypass last. This hook enforces "QA first" before a bypass can be
# requested for any of the gates below.
#
# Per-lens prerequisites (each new lens has its own dispatch marker):
#
#   skip_commit_gate          - any of: visual_qa, code_review (covers
#                               visual + code review for pre-commit-gate)
#   skip_sdd_gate             - any of: visual_qa, code_review
#   skip_types_drift_gate     - none (deterministic gate; user approves
#                               explicitly via bypass_approved)
#   skip_mobile_pattern_gate  - mobile_pattern_dispatched
#   skip_migration_review_gate     - migration_review_dispatched
#   skip_celery_review_gate        - celery_review_dispatched
#   skip_sentry_review_gate        - sentry_review_dispatched
#   skip_external_api_review_gate  - external_api_review_dispatched
#   skip_admin_template_review_gate - admin_template_review_dispatched
#   skip_gpt_tool_review_gate      - gpt_tool_review_dispatched
#
# A bypass-request without the prerequisite marker is denied. This forces
# Claude to actually run the relevant agent before claiming "bypass needed."
#
# IMPORTANT: this hook gates Claude's ability to *write* a skip request.
# The actual bypass still requires user approval via:
#   ! echo approved > /tmp/cc-gates/<session>/bypass_approved
# That second step happens in a user-controlled shell, so even if this hook
# is somehow circumvented, the user remains the sole approver.
set -o pipefail

input=$(cat)
tool=$(echo "$input" | jq -r '.tool_name // empty')
session_id=$(echo "$input" | jq -r '.session_id // empty')
[ -z "$session_id" ] && exit 0

gate_dir="/tmp/cc-gates/$session_id"

# Detect whether this tool call is trying to write to a bypass path
target=""
case "$tool" in
  Write|Edit)
    fp=$(echo "$input" | jq -r '.tool_input.file_path // empty')
    case "$fp" in
      */skip_commit_gate)              target="skip_commit_gate" ;;
      */skip_sdd_gate)                 target="skip_sdd_gate" ;;
      */skip_types_drift_gate)         target="skip_types_drift_gate" ;;
      */skip_mobile_pattern_gate)      target="skip_mobile_pattern_gate" ;;
      */skip_migration_review_gate)    target="skip_migration_review_gate" ;;
      */skip_celery_review_gate)       target="skip_celery_review_gate" ;;
      */skip_sentry_review_gate)       target="skip_sentry_review_gate" ;;
      */skip_external_api_review_gate) target="skip_external_api_review_gate" ;;
      */skip_admin_template_review_gate) target="skip_admin_template_review_gate" ;;
      */skip_gpt_tool_review_gate)     target="skip_gpt_tool_review_gate" ;;
      */skip_visual_qa_gate)           target="skip_visual_qa_gate" ;;
      */skip_interaction_qa_gate)      target="skip_interaction_qa_gate" ;;
      */skip_creative_director_gate)   target="skip_creative_director_gate" ;;
      */skip_commit_drift_gate)        target="skip_commit_drift_gate" ;;
    esac
    ;;
  Bash)
    cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
    # Match the rightmost skip token in the command. Order: longer tokens
    # before potential prefixes (skip_commit_drift_gate before skip_commit_gate;
    # neither is a substring of the other, but the longer one is listed
    # first for clarity and forward-compat).
    for tok in skip_gpt_tool_review_gate skip_admin_template_review_gate \
               skip_external_api_review_gate skip_sentry_review_gate \
               skip_celery_review_gate skip_migration_review_gate \
               skip_mobile_pattern_gate skip_types_drift_gate \
               skip_creative_director_gate \
               skip_interaction_qa_gate skip_visual_qa_gate \
               skip_commit_drift_gate \
               skip_commit_gate skip_sdd_gate; do
      case "$cmd" in
        *"$tok"*) target="$tok"; break ;;
      esac
    done
    ;;
esac

[ -z "$target" ] && exit 0

# Each target maps to a list of acceptable dispatch markers.
# If ANY listed marker exists, the bypass request is permitted to proceed
# (subject to the user's separate approval step).
ok=0
case "$target" in
  skip_commit_gate|skip_sdd_gate)
    [ -f "$gate_dir/visual_qa_dispatched" ] && ok=1
    [ -f "$gate_dir/code_review_dispatched" ] && ok=1
    ;;
  skip_visual_qa_gate)
    [ -f "$gate_dir/visual_qa_dispatched" ] && ok=1
    ;;
  skip_interaction_qa_gate)
    [ -f "$gate_dir/interaction_qa_dispatched" ] && ok=1
    ;;
  skip_creative_director_gate)
    [ -f "$gate_dir/creative_director_dispatched" ] && ok=1
    ;;
  skip_types_drift_gate)
    # Deterministic gate - no Claude-side prerequisite. The user's explicit
    # approval (bypass_approved) is the sole control surface.
    ok=1
    ;;
  skip_commit_drift_gate)
    # Branch-drift bypass: purely a routing/topic-match judgment by Claude
    # (no agent or skill marker maps to it). Deterministic ok=1; the actual
    # block is enforced by commit-on-drifted-branch-guard.sh requiring BOTH
    # this skip file AND user-echoed bypass_approved before allowing commit.
    ok=1
    ;;
  skip_mobile_pattern_gate)
    [ -f "$gate_dir/mobile_pattern_dispatched" ] && ok=1
    ;;
  skip_migration_review_gate)
    [ -f "$gate_dir/migration_review_dispatched" ] && ok=1
    ;;
  skip_celery_review_gate)
    [ -f "$gate_dir/celery_review_dispatched" ] && ok=1
    ;;
  skip_sentry_review_gate)
    [ -f "$gate_dir/sentry_review_dispatched" ] && ok=1
    ;;
  skip_external_api_review_gate)
    [ -f "$gate_dir/external_api_review_dispatched" ] && ok=1
    ;;
  skip_admin_template_review_gate)
    [ -f "$gate_dir/admin_template_review_dispatched" ] && ok=1
    ;;
  skip_gpt_tool_review_gate)
    [ -f "$gate_dir/gpt_tool_review_dispatched" ] && ok=1
    ;;
esac

if [ "$ok" = "1" ]; then
  exit 0
fi

# Map each gate to the agent/skill the user expects Claude to have tried first
case "$target" in
  skip_commit_gate|skip_sdd_gate)
    advice="Run /visual-qa or /code-review first." ;;
  skip_visual_qa_gate)
    advice="Run /visual-qa first." ;;
  skip_interaction_qa_gate)
    advice="Run /interaction-qa first." ;;
  skip_sentry_review_gate)
    advice="Dispatch sentry-discipline-reviewer first." ;;
  skip_codex_gate)
    advice="Run a Codex adversarial-review first (see codex-dispatch.md)." ;;
  skip_devils_advocate)
    advice="Dispatch the devils-advocate agent on the plan first." ;;
  skip_backend_gate)
    advice="Run a verification command (curl, pytest, just test, etc.) before claiming done." ;;
  skip_worktree_gate)
    advice="Move into a worktree (git worktree add .claude/worktrees/<slug>) before continuing." ;;
  *)
    advice="Run the corresponding review first." ;;
esac

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "🚫 Bypass blocked for $target: no prerequisite review attempt this session. $advice Bypass is the last resort, not the first move (feedback_never_default_bypass)."
  }
}
EOF
exit 0
