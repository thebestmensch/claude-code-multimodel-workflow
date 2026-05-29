# claude-code-multimodel-workflow: Package Specification

Durable artifact capturing audit findings + decisions from the planning conversation.
**Read this first** when picking up work on the package in a fresh session.

## Goal

Ship a redistributable Claude Code package that gives less-advanced CC users the dispatch rules, reviewers, and discipline gates shipped here, with an update mechanism for ongoing iteration.

**Scope:** Pure CC-workflow. No terminal stack (no Ghostty, tmux, Visor HUD, starship).

## Audience

Engineers comfortable with Claude Code but not on the cutting edge of plugin/hook/dispatch authoring. They want the discipline patterns shipped here out of the box.

## Three-layer model

| Layer | Distribution | Updates |
|---|---|---|
| **1. Plugin (model-side)** | `claude plugin install` from marketplace | Automatic via `claude plugin update` |
| **2. Install (host-side)** | `git pull` from repo (v0.1.0: docs/templates only; install.sh deferred) | `git pull` |
| **3. Personal (templates)** | Empty scaffolds, teammate fills in | Never auto-updates |

## Tier structure (install-time prompts)

```
Tier 1. Plugin (required)            # commands, agents, hooks, rules, skills
Tier 2. Cross-provider review        # Codex CLI + codex-stop-gate [OPT-IN]
Tier 3. MCP secret management        # op CLI + claude()/codex() zsh wrappers [OPT-IN]
```

Excluded: tweakcc prompt patches (host-side dependency, not redistributable in-plugin), autonomous Linear ticket agent (separate package if ever shipped), terminal stack (Ghostty/tmux/Visor HUD), token-saving proxies (rtk).

## Plugin contents (Layer 1)

### Commands: 9 ship-able

Slice-3 audit reclassified the original 21-ship plan: actual personal `~/.claude/commands/` inventory is 37 files, of which most are tightly coupled to JM's home-lab or OneOnMe stack (Heroku/Django/Maestro/menu_sql/core_appversionconfig/oom-/menu-) and not redistributable.

**Ship as-is (6 universal):** `agent-grep`, `code-review` (default range tightened to follow what's staged so a pre-commit review actually covers the committed diff), `accessibility-qa`, `tone-qa`, `visual-qa`, `teams` (`disable-model-invocation: true`; user-invoke only because it spawns coordinated agents across services). All seven model-invocable QA/discovery commands carry a `description:` so Claude can decide to dispatch them.

**Templated (3, `jm-`/coupling stripped):** `commit` (renamed from `jm-commit`; scope examples generalized; toolchain step made stack-neutral; `disable-model-invocation: true` because the workflow performs a `git commit`), `devils-advocate` (renamed from `jm-devils-advocate`; depends on the `devils-advocate` agent shipped in slice 2, adopters install the assembled plugin so the cross-slice dependency is dev-time only), `interaction-qa` (OOM bundle ID example replaced; philosophy lookup switched from `~/.claude/docs/` to project-local `.claude/docs/` with rules fallback)

**Don't ship (28):**
- 14 personal `jm-*`: `jm-account`, `jm-catchup`, `jm-color-options`, `jm-email`, `jm-linear-promote-tbd`, `jm-meta-command`, `jm-meta-generate`, `jm-plugin-audit`, `jm-research`, `jm-research-claude`, `jm-retro`, `jm-spincraft`, `jm-voice`, `jm-watch-pr`
- 1 personal: `me` (shipped via `dot-me` plugin)
- 3 OneOnMe-specific: `oom-linear-promote-tbd`, `oom-teams`, `oom-visual-qa`
- 3 home-lab menu-service: `menu-agent-auth`, `menu-agent-status`, `menu-import`
- 6 OneOnMe stack-coupled: `deploy` (Heroku/Django), `run-e2e` (Maestro), `release-notes` (OOM app stores), `update-app-versions` (OOM Django table), `investor-update` (OOM data sources), `make-tests` (Django-specific patterns)
- 1 deferred to slice 4: `bypass-audit` (depends on `~/.claude/hooks/lib/bypass-digest.py`; ship in hooks slice)

### Agents: 11 ship-able

**Ship as-is (8 universal):** `silent-failure-hunter`, `test-gap-analyzer`, `type-design-analyzer`, `concurrency-auditor`, `api-contract-reviewer`, `sentry-discipline-reviewer`, `devils-advocate`, `research-agent`

**Templated / generalized (3):** `homelab-explorer` → renamed to `repo-explorer` (drop homelab path bake-in, keep concise read-only exploration contract); `n8n-patcher` (drop Unraid / SSH / `/mnt/user` specifics, keep the n8n SQLite three-table mechanics that are the agent's value); `security-reviewer` (drop "homelab running FastAPI services with Google OAuth" project-specific opening line, keep generic OWASP-shaped review focus areas adopters can apply to any stack).

**Don't ship (1):** `n8n-pattern-reviewer` (home-lab hardcoded)

### Hooks: 47 scripts shipped (46 wires)

Slice-4 audit reclassified the original ~38 estimate. Source inventory: 57 hooks + 5 helpers in `~/.claude/hooks/`. Shipped at `plugin/hooks/scripts/`.

**Plugin layout** (matches `dot-me`/`superpowers` precedent):

```
plugin/hooks/
  hooks.json: manifest, mirrors settings.json hook block
  scripts/*.sh: 47 hook scripts
  scripts/_lib/*.sh: 2 internal helpers (pbcopy-bypass, stop-gate-emit)
  scripts/lib/*.sh: 1 helper (augment-edited-files.sh)
  scripts/lib/*.py: 2 helpers (match-git-commit.py, bypass-digest.py)
```

Path rewrite applied two places:
- `hooks.json` references hooks as `${CLAUDE_PLUGIN_ROOT}/hooks/scripts/<name>.sh`: the harness substitutes the plugin root at registration time.
- Internal cross-script refs that were `$HOME/.claude/hooks/lib/...` rewritten to `$(dirname "$0")/lib/...` (relative to the script's own location). 4 sites in `codex-pre-commit-gate.sh` (1 + 2), `codex-stop-gate.sh` (1), `pre-commit-gate.sh` (1).

**Drop (9):** `needs-input-mark.sh` / `needs-input-mark-stop.sh` / `needs-input-clear.sh` (HUD lifecycle), `creative-director-gate.sh` (SpenschSuite globs), `event-emitter.sh` (home-lab tickets infra), `ssh-tower-python3-block.sh` + `agent-worktree-tower-block.sh` (Unraid hostname), `types-drift-guard.sh` (OneOnMe paths), `me-integrity.sh` (already shipped by `dot-me` plugin), `ota-deploy-gate.sh` (mobile-OOM personal).

**Templated for redistribution (7):** `dispatch-tracker.sh` (stripped JM-103 tickets-infra block + OneOnMe-specific lensed-reviewer matchers, kept generic ones: visual-qa, code-review, brainstorm, frontend-design, devils-advocate, sentry-discipline, codex-rescue), `notify.sh` (placeholder sound path), `parallel-cc-worktree-gate.sh` (dropped JM memory file ref), `codex-pre-commit-gate.sh` (dropped JM memory ref), `gh-actions-yaml-lint.sh` (dropped Slack-notifier comment), `backend-verification-gate.sh` (`ssh tower` → `ssh <host>` example), `track-verify-commands.sh` (`ssh tower` → `ssh ` regex token).

**Universal-with-deps** (graceful no-op when tool absent): `codex-*-{cap,gate,tracker}` (4 hooks), `gh-actions-yaml-lint`, `agent-eligible-self-mod-check` (matches `mcp__linear__save_issue` only).

**Wired but not in JM's settings.json (4 added):** `commit-scope-check.sh` (PreToolUse Bash), `commit-gate-cleanup.sh` (PostToolUse Bash), `devils-advocate-plan-gate.sh` (PreToolUse ExitPlanMode), `devils-advocate-plan-cleanup.sh` (PostToolUse ExitPlanMode). Useful patterns for adopters.

### Rules: 7 ship-able

`advisory-agents-dispatch.md`, `agent-dispatch.md`, `code-review-dispatch.md`, `codex-dispatch.md`, `visual-qa-dispatch.md`, and (added v0.3.0) `codex-design-dispatch.md` + `codex-design-brief-template.md` (proposal-time cross-provider design recon; pairs with the `tools/codex-design-dispatch.sh` wrapper).

**Don't ship:** `workspace-layout.md` (jm/oom tmux session names)

**Loading mechanism:** CC's plugin loader does NOT auto-inject markdown from a `rules/` directory the way it does for `skills/` and `agents/`. To make rules active default behavior, claude-code-multimodel-workflow ships a `SessionStart` hook (`plugin/hooks/inject-rules.sh`) declared in `plugin/.claude-plugin/plugin.json` that reads every `${CLAUDE_PLUGIN_ROOT}/rules/*.md` at session start and emits the concatenated content on stdout, which CC captures as additional system context. Pattern adapted from the `caveman` plugin's SessionStart activation hook. Discovered during Phase 2 implementation after Codex flagged that `plugin/rules/` is not a recognized plugin component path; verified against `https://code.claude.com/docs/en/plugins` (component table lists `.claude-plugin/`, `skills/`, `commands/`, `agents/`, `hooks/`, `.mcp.json`, `.lsp.json`, `monitors/`, `bin/`, `settings.json`: no `rules/`).

**Manifest path correction:** The initial Phase 1 skeleton placed the plugin manifest at `plugin/plugin.json`, but per the same docs the manifest must live at `plugin/.claude-plugin/plugin.json` (verified against the layouts of all installed plugins under `~/.claude/plugins/cache/`: caveman, code-simplifier, codex, oneonme-engineering). Phase 2 corrects this, without the move, neither the SessionStart hook nor any other plugin component is loaded.

### Skills: none

- ~~`story` skill (Storybloq)~~: **dropped** 2026-05-14: not used in personal workflow, no value to redistribute. Plugin ships no skills layer.

### Templates: 6 shipped (JM-173 slice 7)

Project-overlay scaffolds in `plugin/templates/`, with `<PROJECT>`/`<USER>` placeholders for adopters to substitute. Phase 1 already shipped `tools/check-runbook-drift.sh` + `templates/git-hooks/` + `templates/ci/` for the linear-* runbook-drift workflow.

| Path | Purpose |
|---|---|
| `CLAUDE.md.tmpl` | Project root scaffold, services table, core flow, conventions, dev env, common commands, external services, Linear pointer, project-memory @-import |
| `project-overlay/.claude/rules/agent-conventions.md` | Branch naming (`<AGENT_BRANCH_PREFIX>` vs `<HUMAN_BRANCH_PREFIX>`), PR base, worktree setup, agent file location, slash-command source-of-truth |
| `project-overlay/.claude/rules/code-review-PROJECT.md.tmpl` | Reviewer table shape, auto-dispatch triggers, ⭐ priority, 2-reviewer cap, CodeRabbit-overlap rule |
| `project-overlay/.claude/agent-profiles/code.yaml.tmpl` | Linear Task Agent execution contract, slash_command + mcp_servers + allowed_tools + output_verifier |
| `project-overlay/.claude/skills/daily-recap/SKILL.md.tmpl` | End-of-day operator recap, git activity + Linear activity + open threads + tomorrow's lead |
| `project-overlay/MEMORY.md.tmpl` | Split-when-bloated meta-index pattern (Project/Feedback/Reference sections; split siblings when MEMORY.md > ~24 KB) |

**Item dropped:** `project-overlay/.claude/commands/linear-{work,new,status}-ticket.md.tmpl` (canonical-plus-overlay): superseded by Phase 1's drift-test architecture decision (Option 1, see Phase 1 recon). Canonical-plus-overlay was rejected in favor of drift-test because today's drift is ~80% identifier-swap noise + small true-fork; drift-test captures visibility without changing CC's command-loader semantics.

**Drift-fix-first principle:** Already satisfied by Phase 1 shipping `check-runbook-drift.sh` + pre-commit hook + CI workflow against JM's own repos.

## Install layer (Layer 2)

v0.1.0 ships **only** the Claude Code plugin (Layer 1) via `claude plugin install`.

The host-side install layer is deferred to a later release. Planned scope when it lands:
- `install.sh`: interactive tier selection covering Codex CLI + auth (Tier 2) and the `op`/MCP shell wrappers (Tier 3).
- `doctor.sh`: health check for plugin installation, Claude Max subscription (`.credentials.json` subscriptionType=max, never `ANTHROPIC_API_KEY`), required brew deps (jq, gh, ripgrep), and optional Codex/op auth state.
- `shell-snippets/claude-codex-wrappers.zsh`: opt-in `claude()` / `codex()` shell functions for cwd-gated MCP env injection so shipped MCPs don't lose secrets when the user `cd`s away from the project root.
- `codex/config.toml.tmpl`: Codex config template with `ignore_default_excludes = true` for MCP env interpolation.

Until then, adopters set up Codex CLI / `op` / shell wrappers manually if they want the opt-in tiers. See **Requirements** in the README for the assumed external tooling.

## Personal layer (Layer 3, templates only)

`personal-template/dot-me/`:

- `identity.yaml.tmpl`: schema only (name / handle / pronouns / blurb / location / knows_about / work / pets / family / inner_circle)
- `preferences.yaml.tmpl`: sections only (tools / aesthetics / media / workflow / notes)
- `voice.md.tmpl`: headings only (Tone & Dimensions / Mechanics / Lexicon / Anti-patterns / Register / Sample Passages)
- `memory/MEMORY.md.tmpl`: split-when-bloated meta-index pattern + "How to add" guide

JM's actual `dot-me` plugin already ships at `~/.me/` with `examples/` and `.claude-plugin/marketplace.json`: this template aligns with that.

## CLAUDE.md handling

JM's `~/.claude/CLAUDE.md` is ~75% transferable principles + ~25% personal wiring.

**Ship:** `Approach`, `Execution`, `Verification`, `Communication`, `Housekeeping` sections.

**Templated:** The 2 `@`-imports:
- `@~/.me/identity.yaml` → optional template stub
- `@~/.claude/projects/-Users-jm/memory/MEMORY.md` → optional empty memory dir

## Update channels

| Layer | Channel | Frequency |
|---|---|---|
| Plugin | `claude plugin update claude-code-multimodel-workflow` | Whenever JM pushes to marketplace repo |
| Install | `git pull` for templates/docs | Tagged releases (semver) |
| Personal | None (teammate's data) | Never |

## Friction calls (resolved)

| Question | Decision | Date |
|---|---|---|
| Codex CLI tier | Opt-in (not default) | 2026-05-12 |
| Autonomous ticket agent | Excluded from package | 2026-05-12 |
| Plugin name | `claude-code-multimodel-workflow` | 2026-05-12 |
| Force old CC version? | No, apply against current CC | 2026-05-12 |
| Interactive install with secret capture? | Component selection yes, secret capture no | 2026-05-12 |
| tweakcc prompt patches | Excluded from plugin scope (JM-203, 2026-05-16) | 2026-05-16 |

## Open questions for future iteration

- Future addendum patches for shell-compat / command-prefix-aliases learnings
- Future: ship a `jm-linear-agent` companion package?

### Resolved during Phase 1

- **Which subagent-prompt files does CC actually inject? (2026-05-12)**: Verified by inspecting the active session's system prompt at claude-code-multimodel-workflow cwd. CC injects **both** `system-prompt-subagent-prompt-writing-examples.md` (the `<example>` blocks using `Agent({description, prompt, subagent_type})`) and `system-prompt-writing-subagent-prompts.md` (the prose "Writing the prompt" section with the smart-colleague metaphor). The sibling `system-prompt-subagent-delegation-examples.md` uses the `${AGENT_TOOL_NAME}({name: ...})` shape with deferred-notification pattern, that's the cloud Managed-Agents mode, NOT injected for standard CLI users. Implication for the patch catalog: target the two CLI-injected files; treat `subagent-delegation-examples.md` as out-of-scope for the standard-CLI tier.

## Resolved design decisions

### Adopter branch prefix (2026-05-12)

**Human branches:** Configurable. Default = lowercase initials extracted from `git config user.name` (e.g. `James Mensch` → `jm/`). Install.sh prompts with detected default; user accepts or overrides; result written to `~/.claude-code-multimodel-workflow/config.toml` under `[branches] human_prefix = "jm/"`.

**Agent branches:** Hardcoded `agent/`. Matches both oneonme (`.claude/rules/agent-conventions.md`) and home-lab conventions; prefix separation enables PR-stream filtering + branch-protection rules per agent vs human work.

**Config file shape:**
```toml
# ~/.claude-code-multimodel-workflow/config.toml
[branches]
human_prefix = "jm/"        # set manually (install.sh deferred), override anytime
agent_prefix = "agent/"     # do not change unless you also retune CI

[defaults]
default_pr_base = "staging" # oneonme convention; "main" for solo repos
```

**Rationale:** Hardcoding `agent/` matches both reference projects today and prevents accidental overlap with human work; making the human prefix configurable lets adopters preserve their existing convention (every team has one). TOML over JSON for human-edit friendliness.

## Migration roadmap (recommended order)

1. **Drift fix** in JM's own repos: drift-test script for `oom-linear-work-ticket` ↔ `jm-linear-work-ticket` (see Phase 1 recon below, chose drift-test over canonical-plus-overlay)
2. **Plugin contents migration** (rules → agents → commands → hooks → skills → templates)
3. **Install layer** (install.sh + doctor.sh + shell-snippets): DEFERRED to post-v0.1.0
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

Raw audit outputs in conversation transcript; this spec is the synthesized layer.

## Phase 1 recon (2026-05-12)

Performed read-only from oneonme cwd. Real drift between `oom-linear-work-ticket.md` (809 lines) and `jm-linear-work-ticket.md` (882 lines, home-lab):

| Metric | Value |
|---|---|
| Net file delta | 73 lines |
| Line events | +716 / −643 / ~75 modified |
| Section structure | Near-identical (86 vs 89 headers; 3 extra subheaders in home-lab for `## Workflow states`) |
| Drift category, pure substitution | ~80% (`oneonme`↔`home-lab`, `OOM-N`↔`JM-N`, `staging`↔`main`, Linear URL slugs, command name) |
| Drift category, project-specific lists | ~15% (test commands, self-modification file list, project-specific NO list) |
| Drift category, true content forks | ~5% (`## Workflow states` with `In Bot Review` state from JM-94 only in home-lab) |

### Architecture decision: Option 1 (drift-test only)

Three options evaluated:

| Option | Description | Lift | Verdict |
|---|---|---|---|
| 1 | Keep both files, ship drift-test script that strips identifier tokens + flags divergence above threshold | Low | **CHOSEN** |
| 2 | Template + per-project config.yml + render step that emits committed files | High | Reserved for if drift grows past ~20% true-fork |
| 3 | Plugin canonical text + per-project overlay block with import/include semantics | Medium (but unverified, CC slash-command loader may not support `@import` inside `.md`) | Skipped, verification cost high |

Rationale: today's drift is ~80% identifier-swap noise + small true-fork. Option 1 captures visibility without changing how CC loads commands. Per `feedback_session_scope_one_repo.md` blessed "byte-identical mirror specs guarded by drift test" pattern.

### Phase 1 deliverables

- `tools/check-runbook-drift.sh` in claude-code-multimodel-workflow plugin: strips `oneonme|home-lab|OOM|JM|staging|main` + Linear URL slugs + command-name tokens, diffs stripped versions, exits non-zero if delta exceeds threshold
- Pre-commit hook installation snippet for each adopter project (`.git/hooks/pre-commit` or pre-commit framework entry)
- CI workflow stub (GitHub Actions) for adopters that run drift-test on PRs touching `*-linear-work-ticket.md`

Phase 1 runs at claude-code-multimodel-workflow cwd, not from oneonme or home-lab. Project-side wiring (pre-commit hook installation) runs separately at each project's cwd.

