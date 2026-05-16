# jm-workflow

JM's Claude Code workflow as a redistributable package — pre-built dispatch rules, project-aware reviewers, codified discipline patches.

> **Status:** v0.1.0-pre — repo skeleton only. See [SPEC.md](./SPEC.md) for full specification and migration roadmap.

## What this gives you

- **Plugin** — commands, agents, hooks, dispatch rules, skills, project-overlay templates
- **tweakcc patches** — discipline rules baked into CC's system prompt before any CLAUDE.md loads
- **Optional tiers** — Codex cross-provider review, rtk token savings, 1Password MCP integration

## Install (when ready)

```bash
# Add the marketplace
claude plugin marketplace add thebestmensch/jm-workflow

# Install the plugin
claude plugin install jm-workflow

# Run the host-side bootstrap
git clone https://github.com/thebestmensch/jm-workflow.git
cd jm-workflow
./install/install.sh
```

## Update

```bash
# Plugin updates
claude plugin update jm-workflow

# Host-side updates (tweakcc patches, install scripts, shell snippets)
cd jm-workflow
git pull
./install/install.sh --update
```

## Documentation

- [SPEC.md](./SPEC.md) — full specification, three-layer model, tier breakdown, decision log
- [docs/workflow.html](./docs/workflow.html) — visual flowchart of the end-to-end workflow (ticket → retro)
- [CHANGELOG.md](./CHANGELOG.md) — release history

## Not in scope

Terminal stack (Ghostty, tmux, Visor HUD), shell theming, autonomous Linear ticket agent. This is the CC-workflow distribution — not a machine-in-a-box.
