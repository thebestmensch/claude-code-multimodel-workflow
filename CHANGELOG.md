# Changelog

All notable changes to `jm-workflow` documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/).

## [Unreleased]

### Added
- Repo skeleton: marketplace.json, plugin.json, dir structure
- SPEC.md capturing audit findings + decisions
- README.md, .gitignore
- `/jm-precompact` command — pre-compaction retro that distills lessons + commits memory before `/compact` summarizes the transcript. Reuses `/jm-retro` body §§ 1-6 by reference; skips § 7 "What's Next" because session continues mid-stream.

### Pending (per SPEC.md migration roadmap)
- Canonical-plus-overlay drift fix in JM's own repos
- Plugin contents migration (rules → agents → commands → hooks → patches → skills → templates)
- Install layer (install.sh, doctor.sh, tweakcc-install/reapply, shell-snippets)
- Personal-layer templates (dot-me scaffolds)

## [0.1.0] — TBD

First tagged release. See [SPEC.md](./SPEC.md) for inclusion criteria.
