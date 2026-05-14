# jm-workflow — Package Specification

Durable artifact capturing audit findings + decisions from the planning conversation.
**Read this first** when picking up work on the package in a fresh session.

## Goal

Ship a redistributable Claude Code package that gives less-advanced CC users as close to JM's "ahead of the curve" workflow as possible, with an update mechanism for ongoing iteration.

**Scope:** Pure CC-workflow. No terminal stack (no Ghostty, tmux, Visor HUD, starship, chezmoi).

## Audience

Engineers comfortable with Claude Code but not on the cutting edge of plugin/hook/dispatch authoring. They want JM's discipline patterns out of the box.

## Three-layer model

| Layer | Distribution | Updates |
|---|---|---|
| **1. Plugin (model-side)** | `claude plugin install` from marketplace | Automatic via `claude plugin update` |
| **2. Install (host-side)** | `bootstrap.sh` from git repo | `git pull` + idempotent `install.sh --update` |
| **3. Personal (templates)** | Empty scaffolds — teammate fills in | Never auto-updates |

## Tier structure (install-time prompts)

```
Tier 1 — Plugin (required)            # commands, agents, hooks, rules, skills
Tier 2 — Prompt customization         # tweakcc + 11 active patches [DEFAULT YES]
Tier 3 — Cross-provider review        # Codex CLI + codex-stop-gate [OPT-IN]
Tier 4 — Token savings                # rtk
Tier 5 — MCP secret management        # op CLI + claude()/codex() zsh wrappers
```

Excluded: autonomous Linear ticket agent (separate package if ever shipped).

## Active tweakcc patches (11 total)

### Existing (6, already in `~/.tweakcc/prompt-patch.py`)

1. `system-prompt-communication-style` — reader-understanding > terseness; cold-pickup writing; end-of-turn summary
2. `system-prompt-doing-tasks-no-additions` — collaborator-not-executor; flag adjacent issues; no drive-by; verify before reporting
3. `system-prompt-tone-concise-output-short` — **empty** (kills stock "be concise" so it doesn't fight #1)
4. `system-prompt-phase-four-of-plan-mod` — Plan mode Phase 4: brief context + file list + reuse refs + verification + 40-line target
5. `agent-prompt-claude-guide-agent` — err on explanation in claude-guide subagent
6. `system-prompt-output-efficiency` — legacy back-compat of #1

### New for v0.1 (5, from catalog audit)

7. `system-prompt-doing-tasks-read-first` — strengthen to "read before AND after"; investigate before acting; reread modified hunks after Edit/Write
8. `system-prompt-action-safety-and-truthful-reporting` — verify-before-claiming-done; enumerate-losses-before-destructive; "verified by X" wording
9. `tool-description-bash-git-commit-and-pr-creation-instructions` — rebase default for multi-commit; no `--repo` guessing in-repo cwd; enumerate before merge
10. `agent-prompt-explore` + `agent-prompt-general-purpose` — extend `claude-guide-agent` precedent: err on explanation; flag adjacent; return file:line refs
11. `system-prompt-comment-discipline` — **empty** (duplicates patched #1; eliminates drift)

### Held for future iteration

- `system-prompt-doing-tasks-focus` — complexity gate (one-liner vs recon)
- `system-prompt-no-premature-abstractions` + `no-unnecessary-error-handling` — codebase-helper-first wedge
- `agent-prompt-verification-specialist` — Codex pointer (gate on Codex tier install)
- `system-prompt-subagent-prompt-writing-examples` + `system-prompt-writing-subagent-prompts` — both confirmed injected in standard CLI (verified 2026-05-12 by inspecting active session's system prompt; example blocks use `Agent({description, prompt, subagent_type})` shape matching `subagent-prompt-writing-examples.md`, plus the "Writing the prompt" prose from `writing-subagent-prompts.md`). The sibling `subagent-delegation-examples.md` uses the `${AGENT_TOOL_NAME}({name: ...})` shape with deferred-notification pattern — that's the cloud Managed-Agents mode, NOT injected in the standard CLI context. Patch the two CLI-injected files; the third is dead code for standard CLI users.
- `tool-description-todowrite` — soften proactivity (more opinionated; assess after teammate feedback)

### Patch system properties

- All patches are length-preserving (whitespace pad/trim)
- System-prompt patches stable across CC versions (per `reference_tweakcc_diagnostics.md`)
- **Theme patches NOT shipped** — JM-personal cosmetic; teammate picks via stock tweakcc UI
- No CC version pin
- `DISABLE_AUTOUPDATER=1` recommended (not forced)
- `tweakcc-reapply.sh` is the recovery path after teammate consciously upgrades CC
- doctor.sh detects when patches got wiped (binary fingerprint check)
- Future: per-prompt opt-out via `~/.jm-workflow/disabled-patches.txt`

## Plugin contents (Layer 1)

### Commands — 9 ship-able

Slice-3 audit reclassified the original 21-ship plan: actual personal `~/.claude/commands/` inventory is 37 files, of which most are tightly coupled to JM's home-lab or OneOnMe stack (Heroku/Django/Maestro/menu_sql/core_appversionconfig/oom-/menu-) and not redistributable.

**Ship as-is (6 universal):** `agent-grep`, `code-review` (default range tightened to follow what's staged so a pre-commit review actually covers the committed diff), `accessibility-qa`, `tone-qa`, `visual-qa`, `teams` (`disable-model-invocation: true`; user-invoke only because it spawns coordinated agents across services). All seven model-invocable QA/discovery commands carry a `description:` so Claude can decide to dispatch them.

**Templated (3, `jm-`/coupling stripped):** `commit` (renamed from `jm-commit`; scope examples generalized; toolchain step made stack-neutral; `disable-model-invocation: true` because the workflow performs a `git commit`), `devils-advocate` (renamed from `jm-devils-advocate`; depends on the `devils-advocate` agent shipped in slice 2 — adopters install the assembled plugin so the cross-slice dependency is dev-time only), `interaction-qa` (OOM bundle ID example replaced; philosophy lookup switched from `~/.claude/docs/` to project-local `.claude/docs/` with rules fallback)

**Don't ship (28):**
- 14 personal `jm-*`: `jm-account`, `jm-catchup`, `jm-color-options`, `jm-email`, `jm-linear-promote-tbd`, `jm-meta-command`, `jm-meta-generate`, `jm-plugin-audit`, `jm-research`, `jm-research-claude`, `jm-retro`, `jm-spincraft`, `jm-voice`, `jm-watch-pr`
- 1 personal: `me` (shipped via `dot-me` plugin)
- 3 OneOnMe-specific: `oom-linear-promote-tbd`, `oom-teams`, `oom-visual-qa`
- 3 home-lab menu-service: `menu-agent-auth`, `menu-agent-status`, `menu-import`
- 6 OneOnMe stack-coupled: `deploy` (Heroku/Django), `run-e2e` (Maestro), `release-notes` (OOM app stores), `update-app-versions` (OOM Django table), `investor-update` (OOM data sources), `make-tests` (Django-specific patterns)
- 1 deferred to slice 4: `bypass-audit` (depends on `~/.claude/hooks/lib/bypass-digest.py`; ship in hooks slice)

### Agents — 11 ship-able

**Ship as-is (8 universal):** `silent-failure-hunter`, `test-gap-analyzer`, `type-design-analyzer`, `concurrency-auditor`, `api-contract-reviewer`, `sentry-discipline-reviewer`, `devils-advocate`, `research-agent`

**Templated / generalized (3):** `homelab-explorer` → renamed to `repo-explorer` (drop homelab path bake-in, keep concise read-only exploration contract); `n8n-patcher` (drop Unraid / SSH / `/mnt/user` specifics, keep the n8n SQLite three-table mechanics that are the agent's value); `security-reviewer` (drop "homelab running FastAPI services with Google OAuth" project-specific opening line, keep generic OWASP-shaped review focus areas adopters can apply to any stack).

**Don't ship (1):** `n8n-pattern-reviewer` (home-lab hardcoded)

### Hooks — 47 scripts shipped (46 wires)

Slice-4 audit reclassified the original ~38 estimate. Source inventory: 57 hooks + 5 helpers in `~/.claude/hooks/`. Shipped at `plugin/hooks/scripts/`.

**Plugin layout** (matches `dot-me`/`superpowers` precedent):

```
plugin/hooks/
  hooks.json             — manifest, mirrors settings.json hook block
  scripts/*.sh           — 47 hook scripts
  scripts/_lib/*.sh      — 2 internal helpers (pbcopy-bypass, stop-gate-emit)
  scripts/lib/*.sh       — 1 helper (augment-edited-files.sh)
  scripts/lib/*.py       — 2 helpers (match-git-commit.py, bypass-digest.py)
```

Path rewrite applied two places:
- `hooks.json` references hooks as `${CLAUDE_PLUGIN_ROOT}/hooks/scripts/<name>.sh` — the harness substitutes the plugin root at registration time.
- Internal cross-script refs that were `$HOME/.claude/hooks/lib/...` rewritten to `$(dirname "$0")/lib/...` (relative to the script's own location). 4 sites in `codex-pre-commit-gate.sh` (1 + 2), `codex-stop-gate.sh` (1), `pre-commit-gate.sh` (1).

**Drop (9):** `needs-input-mark.sh` / `needs-input-mark-stop.sh` / `needs-input-clear.sh` (HUD lifecycle), `creative-director-gate.sh` (SpenschSuite globs), `event-emitter.sh` (home-lab tickets infra), `ssh-tower-python3-block.sh` + `agent-worktree-tower-block.sh` (Unraid hostname), `types-drift-guard.sh` (OneOnMe paths), `me-integrity.sh` (already shipped by `dot-me` plugin), `ota-deploy-gate.sh` (mobile-OOM personal).

**Templated for redistribution (7):** `dispatch-tracker.sh` (stripped JM-103 tickets-infra block + OneOnMe-specific lensed-reviewer matchers — kept generic ones: visual-qa, code-review, brainstorm, frontend-design, devils-advocate, sentry-discipline, codex-rescue), `notify.sh` (placeholder sound path), `parallel-cc-worktree-gate.sh` (dropped JM memory file ref), `codex-pre-commit-gate.sh` (dropped JM memory ref), `gh-actions-yaml-lint.sh` (dropped Slack-notifier comment), `backend-verification-gate.sh` (`ssh tower` → `ssh <host>` example), `track-verify-commands.sh` (`ssh tower` → `ssh ` regex token).

**Universal-with-deps** (graceful no-op when tool absent): `chezmoi-*-guard` (3 hooks; `command -v chezmoi || exit 0`), `codex-*-{cap,gate,tracker}` (4 hooks), `tweakcc-drift-warn`, `gh-actions-yaml-lint`, `agent-eligible-self-mod-check` (matches `mcp__linear__save_issue` only).

**Wired but not in JM's settings.json (4 added):** `commit-scope-check.sh` (PreToolUse Bash), `commit-gate-cleanup.sh` (PostToolUse Bash), `devils-advocate-plan-gate.sh` (PreToolUse ExitPlanMode), `devils-advocate-plan-cleanup.sh` (PostToolUse ExitPlanMode). Useful patterns for adopters.

### Rules — 5 ship-able

`advisory-agents-dispatch.md`, `agent-dispatch.md`, `code-review-dispatch.md`, `codex-dispatch.md`, `visual-qa-dispatch.md`

**Don't ship:** `workspace-layout.md` (jm/oom tmux session names)

### Skills — none

- ~~`story` skill (Storybloq)~~ — **dropped** 2026-05-14: not used in personal workflow, no value to redistribute. Plugin ships no skills layer.

### Templates — 6 shipped (JM-173 slice 7)

Project-overlay scaffolds in `plugin/templates/`, with `<PROJECT>`/`<USER>` placeholders for adopters to substitute. Phase 1 already shipped `tools/check-runbook-drift.sh` + `templates/git-hooks/` + `templates/ci/` for the linear-* runbook-drift workflow.

| Path | Purpose |
|---|---|
| `CLAUDE.md.tmpl` | Project root scaffold — services table, core flow, conventions, dev env, common commands, external services, Linear pointer, project-memory @-import |
| `project-overlay/.claude/rules/agent-conventions.md` | Branch naming (`<AGENT_BRANCH_PREFIX>` vs `<HUMAN_BRANCH_PREFIX>`), PR base, worktree setup, agent file location, slash-command source-of-truth |
| `project-overlay/.claude/rules/code-review-PROJECT.md.tmpl` | Reviewer table shape — auto-dispatch triggers, ⭐ priority, 2-reviewer cap, CodeRabbit-overlap rule |
| `project-overlay/.claude/agent-profiles/code.yaml.tmpl` | Linear Task Agent execution contract — slash_command + mcp_servers + allowed_tools + output_verifier |
| `project-overlay/.claude/skills/daily-recap/SKILL.md.tmpl` | End-of-day operator recap — git activity + Linear activity + open threads + tomorrow's lead |
| `project-overlay/MEMORY.md.tmpl` | Split-when-bloated meta-index pattern (Project/Feedback/Reference sections; split siblings when MEMORY.md > ~24 KB) |

**Item dropped:** `project-overlay/.claude/commands/linear-{work,new,status}-ticket.md.tmpl` (canonical-plus-overlay) — superseded by Phase 1's drift-test architecture decision (Option 1, see Phase 1 recon). Canonical-plus-overlay was rejected in favor of drift-test because today's drift is ~80% identifier-swap noise + small true-fork; drift-test captures visibility without changing CC's command-loader semantics.

**Drift-fix-first principle:** Already satisfied by Phase 1 shipping `check-runbook-drift.sh` + pre-commit hook + CI workflow against JM's own repos.

## Install layer (Layer 2)

### `install/install.sh`

Interactive tier selection (default), `--all` / `--tier=X` / `--update` / `--dry-run` flags.

Saves tier selections to `~/.jm-workflow/install.conf` for idempotent updates.

### `install/doctor.sh`

Post-install + on-demand health check. Verifies:
- `CLAUDE_CODE_TMUX_TRUECOLOR=1` exported (if Tier 2 installed)
- Claude Max subscription (`.credentials.json` has `subscriptionType=max`) — NEVER `ANTHROPIC_API_KEY`
- Codex OAuth done (`~/.codex/auth.json` exists, if Tier 3)
- `op` authed for required vaults (if Tier 5)
- Plugin installed (`claude plugin list` includes `jm-workflow`)
- Required brew deps present (jq, gh, ripgrep)
- tweakcc patches not wiped (binary fingerprint check)

### `install/tweakcc-install.sh`

`npm i -g tweakcc`. Runs `tweakcc --apply --patches <list>` for native patches. Then runs `prompt-patch.py` against installed CC native binary with the 11 shipped patches.

### `install/tweakcc-reapply.sh`

Idempotent. Run after teammate consciously upgrades CC. Re-applies all patches.

### `install/shell-snippets/claude-codex-wrappers.zsh`

Opt-in source line for `~/.zshrc`:
- `claude()` — cwd-gated MCP env injection (without this, shipped MCPs lose secrets when teammate `cd`s away from project root)
- `codex()` — same shape for Codex CLI

### `install/codex/config.toml.tmpl`

Codex config template with the easy-to-miss `ignore_default_excludes = true` (required for MCP env interpolation per JM's setup).

## Personal layer (Layer 3, templates only)

`personal-template/dot-me/`:

- `identity.yaml.tmpl` — schema only (name / handle / pronouns / blurb / location / knows_about / work / pets / family / inner_circle)
- `preferences.yaml.tmpl` — sections only (tools / aesthetics / media / workflow / notes)
- `voice.md.tmpl` — headings only (Tone & Dimensions / Mechanics / Lexicon / Anti-patterns / Register / Sample Passages)
- `memory/MEMORY.md.tmpl` — split-when-bloated meta-index pattern + "How to add" guide

JM's actual `dot-me` plugin already ships at `~/.me/` with `examples/` and `.claude-plugin/marketplace.json` — this template aligns with that.

## CLAUDE.md handling

JM's `~/.claude/CLAUDE.md` is ~75% transferable principles + ~25% personal wiring.

**Ship:** `Approach`, `Execution`, `Verification`, `Communication`, `Housekeeping` sections.

**Templated:** The 3 `@`-imports:
- `@~/.me/identity.yaml` → optional template stub
- `@~/.claude/projects/-Users-jm/memory/MEMORY.md` → optional empty memory dir
- `@RTK.md` → Tier 4 only

## Update channels

| Layer | Channel | Frequency |
|---|---|---|
| Plugin | `claude plugin update jm-workflow` | Whenever JM pushes to marketplace repo |
| Install | `git pull && bootstrap.sh --update` | Tagged releases (semver) |
| Personal | None (teammate's data) | Never |
| Patches | Auto-updates with plugin; reapply needed after CC upgrade | Reapply on-demand |

## Friction calls (resolved)

| Question | Decision | Date |
|---|---|---|
| Codex CLI tier | Opt-in (not default) | 2026-05-12 |
| Autonomous ticket agent | Excluded from package | 2026-05-12 |
| Plugin name | `jm-workflow` | 2026-05-12 |
| Force old CC version? | No — apply against current CC | 2026-05-12 |
| Theme patches | Don't ship (personal cosmetic) | 2026-05-12 |
| Interactive install with secret capture? | Component selection yes, secret capture no | 2026-05-12 |

## Open questions for future iteration

- Future addendum patches for shell-compat / command-prefix-aliases learnings
- Future: ship a `jm-linear-agent` companion package?

### Resolved during Phase 1

- **Which subagent-prompt files does CC actually inject? (2026-05-12)** — Verified by inspecting the active session's system prompt at jm-workflow cwd. CC injects **both** `system-prompt-subagent-prompt-writing-examples.md` (the `<example>` blocks using `Agent({description, prompt, subagent_type})`) and `system-prompt-writing-subagent-prompts.md` (the prose "Writing the prompt" section with the smart-colleague metaphor). The sibling `system-prompt-subagent-delegation-examples.md` uses the `${AGENT_TOOL_NAME}({name: ...})` shape with deferred-notification pattern — that's the cloud Managed-Agents mode, NOT injected for standard CLI users. Implication for the patch catalog: target the two CLI-injected files; treat `subagent-delegation-examples.md` as out-of-scope for the standard-CLI tier.

## Resolved design decisions

### Per-prompt opt-out config (2026-05-12)

**Shape:** `~/.jm-workflow/disabled-patches.txt` — one tweakcc marker name per line, `#` comments allowed, blank lines ignored. Missing file = nothing disabled (all default).

```
# ~/.jm-workflow/disabled-patches.txt
# Disable the prompt patches you don't want applied
system-prompt-phase-four-of-plan-mod  # broken on CC 2.1.139, pending upstream
# communication-style                  # uncomment to skip
```

**Install-time behavior:** `install.sh --select` writes this file based on interactive component picks. Hand-editable afterward — re-run `install.sh --apply` re-reads it.

**Apply-time behavior:** Pre-apply step in `tweakcc-install` walks marker list, skips any whose name appears in disabled-patches.txt. Implementation: `grep -vxF -f disabled-patches.txt patches.txt`.

**Rationale:** Plain text over YAML — single-column list, hand-editable, grep-friendly, no parser dependency. Comment support lets users annotate *why* a patch is disabled without losing the line on diff.

### Adopter branch prefix (2026-05-12)

**Human branches:** Configurable. Default = lowercase initials extracted from `git config user.name` (e.g. `James Mensch` → `jm/`). Install.sh prompts with detected default; user accepts or overrides; result written to `~/.jm-workflow/config.toml` under `[branches] human_prefix = "jm/"`.

**Agent branches:** Hardcoded `agent/`. Matches both oneonme (`.claude/rules/agent-conventions.md`) and home-lab conventions; prefix separation enables PR-stream filtering + branch-protection rules per agent vs human work.

**Config file shape:**
```toml
# ~/.jm-workflow/config.toml
[branches]
human_prefix = "jm/"        # set by install.sh, override anytime
agent_prefix = "agent/"     # do not change unless you also retune CI

[defaults]
default_pr_base = "staging" # oneonme convention; "main" for solo repos
```

**Rationale:** Hardcoding `agent/` matches both reference projects today and prevents accidental overlap with human work; making the human prefix configurable lets adopters preserve their existing convention (every team has one). TOML over JSON for human-edit friendliness.

## Migration roadmap (recommended order)

1. **Drift fix** in JM's own repos: drift-test script for `oom-linear-work-ticket` ↔ `jm-linear-work-ticket` (see Phase 1 recon below — chose drift-test over canonical-plus-overlay)
2. **Plugin contents migration** (rules → agents → commands → hooks → patches → skills → templates)
3. **Install layer** (install.sh + doctor.sh + tweakcc-install/reapply + shell-snippets)
4. **Personal templates** (`dot-me/` schemas)
5. **README**
6. **Initial v0.1.0 tag + push to marketplace**

Each phase is a separate session, ideally in a fresh CC at this repo's cwd (per `feedback_session_scope_one_repo.md`).

## Audit sources

All findings captured in this spec derived from 6 parallel audits dispatched 2026-05-12:
- Model-side workflow assets (commands, agents, skills, plugins)
- Hooks, settings, rules
- Personal/identity layer
- External host-side tooling
- Per-project CC overlays
- tweakcc catalog for new patches

Raw audit outputs in conversation transcript; this spec is the synthesized layer.

## Phase 1 recon (2026-05-12)

Performed read-only from oneonme cwd. Real drift between `oom-linear-work-ticket.md` (809 lines) and `jm-linear-work-ticket.md` (882 lines, home-lab):

| Metric | Value |
|---|---|
| Net file delta | 73 lines |
| Line events | +716 / −643 / ~75 modified |
| Section structure | Near-identical (86 vs 89 headers; 3 extra subheaders in home-lab for `## Workflow states`) |
| Drift category — pure substitution | ~80% (`oneonme`↔`home-lab`, `OOM-N`↔`JM-N`, `staging`↔`main`, Linear URL slugs, command name) |
| Drift category — project-specific lists | ~15% (test commands, self-modification file list, project-specific NO list) |
| Drift category — true content forks | ~5% (`## Workflow states` with `In Bot Review` state from JM-94 only in home-lab) |

### Architecture decision: Option 1 (drift-test only)

Three options evaluated:

| Option | Description | Lift | Verdict |
|---|---|---|---|
| 1 | Keep both files, ship drift-test script that strips identifier tokens + flags divergence above threshold | Low | **CHOSEN** |
| 2 | Template + per-project config.yml + render step that emits committed files | High | Reserved for if drift grows past ~20% true-fork |
| 3 | Plugin canonical text + per-project overlay block with import/include semantics | Medium (but unverified — CC slash-command loader may not support `@import` inside `.md`) | Skipped — verification cost high |

Rationale: today's drift is ~80% identifier-swap noise + small true-fork. Option 1 captures visibility without changing how CC loads commands. Per `feedback_session_scope_one_repo.md` blessed "byte-identical mirror specs guarded by drift test" pattern.

### Phase 1 deliverables

- `tools/check-runbook-drift.sh` in jm-workflow plugin — strips `oneonme|home-lab|OOM|JM|staging|main` + Linear URL slugs + command-name tokens, diffs stripped versions, exits non-zero if delta exceeds threshold
- Pre-commit hook installation snippet for each adopter project (`.git/hooks/pre-commit` or pre-commit framework entry)
- CI workflow stub (GitHub Actions) for adopters that run drift-test on PRs touching `*-linear-work-ticket.md`

Phase 1 runs at jm-workflow cwd, not from oneonme or home-lab. Project-side wiring (pre-commit hook installation) runs separately at each project's cwd.

## tweakcc 2.1.139 patch state (2026-05-12)

Verified upgrade path: `claude install 2.1.139 --force` then `tweakcc-pin 2.1.139`. Results:

- **Themes:** 408 colors patched across 6 themes — full restoration ✓
- **Prompts:** 4/6 patched (`communication-style`, `doing-tasks-no-additions`, `tone-concise-output-short`, `agent-prompt-claude-guide-agent`) ✓
- **Prompts lost markers on 2.1.139:** `system-prompt-phase-four-of-plan-mod`, `system-prompt-output-efficiency` — upstream tweakcc patch fix needed

Implication for jm-workflow patch catalog: ship the 4 working patches as Tier 2 default; mark the 2 broken ones as "pending tweakcc upstream fix" with skip-on-marker-miss semantics in the install script. Validates `reference_tweakcc_diagnostics.md` recurring-split pattern (themes survive Bun shape changes, some prompts don't).
