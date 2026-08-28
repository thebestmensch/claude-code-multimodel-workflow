# The repo contract

What any repo must expose for this workflow to run on it. This six-item list
is the interface; the templates in this kit are one implementation of the
machinery behind it. Per-repo prose (the CLAUDE.md section, the knob values)
is written at that repo's cutover — never in advance.

1. **Fast-lane commands and the full-suite command.** A cheap lint /
   typecheck / scoped-test invocation an agent can run in minutes, and the
   authoritative full suite CI runs. Without the split, staged CI has nothing
   to stage (that's fine — it's a knob — but then draft pushes pay full-suite
   cost).

2. **Env-sync recipe.** A committed secret-reference template (e.g. `op://`
   references into the repo's **own** vault) plus an idempotent sync command
   on a service-account plane. Rotation = rotate in the store + re-run.
   Secrets never live in the repo; identifiers may. Agent lanes must never
   receive a metered API key that silently re-routes subscription-seat work
   to per-token billing — make the sync drop such keys on the floor.

3. **Protected infra-cost paths.** The repo's equivalents of "what decides
   what merges and what deploys": workflow files, deploy config (Procfile,
   wrangler.toml, compose files), the task runner, sync maps. Enforced via
   CODEOWNERS + `require_code_owner_review` (org topology) or the
   agent-infra-guard workflow (single-account topology) — `docs/knobs.md`.

4. **An in-repo home for the ruleset JSON** (this kit's `rulesets/` layout)
   plus a pointer to the policy-knobs table. The live ruleset is applied FROM
   the file; a policy change is a PR, then a re-apply. Never hand-edit the
   ruleset in the UI without mirroring the change — the diffable history is
   the point.

5. **A "how work merges here" section** in the repo's CLAUDE.md / AGENTS.md:
   required vs advisory checks, auto-merge/auto-ready behavior, and where the
   break-glass runbook lives. `CLAUDE.md.template` is the skeleton.

6. **The dispatch convention.** Concurrent agent PRs capped by habit, not
   machinery — 2–3 delegated tickets in flight. The binding constraint is
   human attention (QA batch size, conflict surface), not cost; a mechanical
   cap would just get worked around.
