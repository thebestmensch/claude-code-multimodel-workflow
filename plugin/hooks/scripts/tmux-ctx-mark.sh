#!/usr/bin/env bash
# UserPromptSubmit hook — writes per-pane sub-chat ctx snapshot for the Visor
# Tmux HUD: project / branch / linear-ticket of the active sub-chat.
#
# Why a hook (vs the statusLine exporter): the Claude Agents UI (post-2026-05-11)
# never fires the local statusLine for sub-chats, so the previous exporter-driven
# write at /tmp/.tmux_claude_ctx_<pane> stayed empty / stale forever in that UI.
# UserPromptSubmit DOES fire for every sub-chat, so this hook owns the snapshot.
#
# Output: /tmp/.tmux_claude_ctx_<pane>  TSV: project<TAB>branch<TAB>ticket
# Read by: ~/.claude/visor-hud.sh parse_ctx() with a 300s freshness gate.
set -o pipefail

[ -n "$TMUX_PANE" ] || exit 0
PANE_NUM=${TMUX_PANE#%}
CTX_FILE="/tmp/.tmux_claude_ctx_${PANE_NUM}"

# Critical: every exit path that returns BEFORE writing real data MUST
# invalidate the file with an empty snapshot. The renderer trusts any ctx file
# younger than 300s as authoritative, so leaving a stale file in place after a
# failed-cwd prompt would keep the HUD showing the previous sub-chat's project
# and ticket as if they were current (Codex adversarial-review 2026-05-13 r4).
# The empty `\t\t` payload triggers parse_ctx's `ctx_present=1, project=empty`
# state → renderer shows `@…` (acknowledged-stale), never wrong-but-confident.
#
# Atomic write via mktemp + mv -f: rename(2) at CTX_FILE unlinks any
# pre-planted symlink rather than following it, defeating /tmp symlink-
# clobber attacks on the shared 1777 dir; also gives crash-safe writes.
atomic_write() {
    local tmp
    tmp=$(mktemp "${CTX_FILE}.XXXXXX") || return 1
    if ! cat > "$tmp" || ! mv -f "$tmp" "$CTX_FILE"; then
        rm -f "$tmp"
        return 1
    fi
}

# write_empty: invalidation MUST succeed (the file's freshness contract). If
# atomic_write fails (ENOSPC, sticky-bit cross-owner blockage on the mv, etc.),
# fall back to plain unlink — same end state for the renderer's parse_ctx
# (file absent → ctx_present=0). If unlink also fails, the 300s freshness gate
# in parse_ctx is the last line of defense against trusting a stale snapshot.
# Returns 0 on best-effort completion so callers stay simple (Codex r6 finding).
write_empty() {
    printf '\t\t' | atomic_write || rm -f "$CTX_FILE" || true
}

input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null)
if [ -z "$cwd" ] || [ ! -d "$cwd" ]; then
    write_empty
    exit 0
fi

# Walk to the nearest .git ancestor — handles regular repos and worktrees.
walk="$cwd"
git_root=""
while [ -n "$walk" ] && [ "$walk" != "/" ]; do
    if [ -e "$walk/.git" ]; then
        git_root="$walk"
        break
    fi
    walk="${walk%/*}"
done

if [ -z "$git_root" ]; then
    # Non-repo cwd — empty snapshot, same reasoning as above.
    write_empty
    exit 0
fi

project=$(basename "$git_root")
branch=$(git -C "$git_root" symbolic-ref --quiet --short HEAD 2>/dev/null)
ticket=""
if [[ "$branch" =~ ([A-Za-z]{2,})-([0-9]+) ]]; then
    prefix=$(echo "${BASH_REMATCH[1]}" | tr 'a-z' 'A-Z')
    ticket="${prefix}-${BASH_REMATCH[2]}"
fi

# Data-write must invalidate on failure for the same reason write_empty does:
# leaving a stale snapshot would render as wrong-but-confident in the HUD.
printf '%s\t%s\t%s' "$project" "$branch" "$ticket" | atomic_write || rm -f "$CTX_FILE" || true
exit 0
