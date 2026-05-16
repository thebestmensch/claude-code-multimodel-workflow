# Changelog

All notable changes to `jm-workflow` documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/).

## [Unreleased]

(nothing yet)

## [0.1.0] — 2026-05-16

First tagged release. Pre-OSS soft-launch readiness: the plugin (Layer 1) is shippable as a generic Claude Code package via `claude plugin install jm-workflow`.

### Added
- Repo skeleton: marketplace.json, plugin.json, dir structure
- SPEC.md capturing audit findings + decisions
- README.md, .gitignore, LICENSE (MIT)
- `/jm-precompact` command — pre-compaction retro that distills lessons + commits memory before `/compact` summarizes the transcript. Reuses `/jm-retro` body §§ 1-6 by reference; skips § 7 "What's Next" because session continues mid-stream.
- Plugin contents migration (rules, agents, commands, hooks, skills, templates) — see SPEC.md for the per-tier shipped inventory
- `plugin/tools/check-runbook-drift.sh` with env-var-driven normalization (RUNBOOK_PROJECT_NAMES, RUNBOOK_TICKET_PREFIXES) so adopters can drop the tool into any project
- `plugin/templates/git-hooks/` and `plugin/templates/ci/` adopter snippets
- Requirements section in README documenting Claude Max, optional Codex CLI / openai-codex plugin, optional `op` (1Password CLI), suggested `superpowers` plugin, and brew deps

### Changed
- Strip chezmoi guards from the plugin (JM-202) — jm-workflow no longer presumes chezmoi is installed; dotfile-management is out of plugin scope
- Strip tweakcc drift-warn hook + prompt-patch surface (JM-203) — system-prompt patches require host-side binary patching, which doesn't redistribute cleanly through `claude plugin install`
- Mark optional plugin deps explicit (JM-204) — codex-dispatch / agent-dispatch / code-review-dispatch rules now describe `openai-codex` and `superpowers` as opt-in integrations; `keyword-detector.sh` only suggests `superpowers:systematic-debugging` when the plugin is installed (tolerates both flat and marketplace-nested cache layouts)
- Generalize JM-only repo paths and ticket prefixes (JM-205) — `oneonme` / `home-lab` / `JM-1234` references replaced with env-var-driven placeholders or generic templates; original placeholders kept where they are intentional project identity (e.g. `plugin.json` `thebestmensch/jm-workflow` URLs)

### Removed
- `plugin/hooks/scripts/chezmoi-source-drift-guard.sh`, `chezmoi-force-guard.sh`, `chezmoi-target-edit-warn.sh` and their `hooks.json` registrations (JM-202)
- `plugin/hooks/scripts/tweakcc-drift-warn.sh` and its `hooks.json` registration (JM-203)
- Empty `install/codex/` and `install/shell-snippets/` scaffolding stubs

### Deferred to a future release
- Host-side install layer (`install.sh`, `doctor.sh`, shell-snippets) — adopters set up Codex CLI / `op` / shell wrappers manually for now
- Canonical-plus-overlay drift fix in JM's own repos
- Personal-layer templates (`dot-me/` scaffolds)
