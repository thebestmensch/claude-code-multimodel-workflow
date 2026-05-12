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
- `system-prompt-subagent-delegation-examples` — verify which of two near-duplicate files CC actually injects first
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

### Commands — 21 ship-able

**Ship as-is (5):** `agent-grep`, `code-review`, `accessibility-qa`, `tone-qa`, `visual-qa`

**Templated (16, `jm-` prefix stripped):** `account`, `catchup`, `color-options`, `commit`, `devils-advocate`, `meta-command`, `meta-generate`, `plugin-audit`, `research`, `research-claude`, `spincraft`, `watch-pr`, `bypass-audit`, `interaction-qa`, `teams`, (1 reserved)

**Don't ship (4 personal):** `jm-email`, `jm-retro`, `jm-voice`, `me` (already shipped via `dot-me` plugin)

### Agents — 11 ship-able

**Ship as-is (9 universal):** `silent-failure-hunter`, `test-gap-analyzer`, `type-design-analyzer`, `concurrency-auditor`, `api-contract-reviewer`, `sentry-discipline-reviewer`, `security-reviewer`, `devils-advocate`, `research-agent`

**Templated (2):** `homelab-explorer` (rename, generalize), `n8n-patcher`

**Don't ship (1):** `n8n-pattern-reviewer` (home-lab hardcoded)

### Hooks — ~38 ship-able

Bucket counts from audit:
- **Universal (~42):** session-init, all gate hooks (bypass-pattern-warn, pre-commit-gate, codex-*-gate, visual-qa-stop-gate, mobile-pattern-stop-gate, interaction-qa-stop-gate, devils-advocate-plan-gate, sdd-review-gate, schedule-wakeup-loop-gate, parallel-cc-worktree-gate, commit-on-drifted-branch-guard, commit-scope-check, git-push-bundled-commits-guard, backend-verification-gate), all trackers, all dispatch-trackers, cache-warmth-tracker/cache-cold-warn, lib/match-git-commit.py, lib/augment-edited-files.sh, _lib/stop-gate-emit.sh, _lib/pbcopy-bypass.sh, notify.sh (macOS-gated)
- **Universal-with-deps (~12):** chezmoi-*-guard (chezmoi-presence-gated), codex-*-cap/gate/tracker (codex-presence-gated), tweakcc-drift-warn (tweakcc-presence-gated), gh-actions-yaml-lint, me-integrity (only fires if `~/.me/` present), agent-eligible-self-mod-check
- **Personal/cut:** `needs-input-mark*.sh` (HUD), `creative-director-gate.sh` (home-lab globs), `event-emitter.sh` (tickets infra), `ssh-tower-python3-block.sh` (hostname), `types-drift-guard.sh` (oneonme paths)

**Path rewrite:** All absolute `/Users/jm/.claude/hooks/...` paths in `settings.json` references → `$HOME`-relative.

### Rules — 5 ship-able

`advisory-agents-dispatch.md`, `agent-dispatch.md`, `code-review-dispatch.md`, `codex-dispatch.md`, `visual-qa-dispatch.md`

**Don't ship:** `workspace-layout.md` (jm/oom tmux session names)

### Skills

- `story` skill (Storybloq) — ship as-is, clean

### Templates (in `plugin/templates/`)

Project-overlay scaffolds with `<PROJECT>`/`<USER>` placeholders:

- `CLAUDE.md.tmpl` — project root scaffold (header / services table / core flow / conventions / dev env / common commands / project memory pointer)
- `project-overlay/.claude/rules/agent-conventions.md` — branch naming (agent/ vs jm/), PR base, worktree path
- `project-overlay/.claude/rules/code-review-PROJECT.md.tmpl` — reviewer table shape
- `project-overlay/.claude/agent-profiles/code.yaml.tmpl` — agent execution contract
- `project-overlay/.claude/commands/linear-{work,new,status}-ticket.md.tmpl` — **canonical-plus-overlay** to fix the ~800-line drift currently in oneonme/home-lab
- `project-overlay/.claude/skills/daily-recap/SKILL.md.tmpl`
- `project-overlay/MEMORY.md.tmpl` — split-when-bloated meta-index pattern

**Drift-fix-first principle:** Apply canonical-plus-overlay to JM's own repos *before* shipping the pattern, otherwise teammates inherit the problem.

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

- Per-prompt opt-out config (`~/.jm-workflow/disabled-patches.txt`)
- Verify which of two near-duplicate subagent-prompt files CC actually injects (`subagent-delegation-examples` vs `subagent-prompt-writing-examples`)
- Future addendum patches for shell-compat / command-prefix-aliases learnings
- Future: ship a `jm-linear-agent` companion package?
- Default branch name for teammate adoption: `agent/` vs `<initials>/`?

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
