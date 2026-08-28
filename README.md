# claude-code-multimodel-workflow

**v2 — server-enforced merge gates for semi-autonomous repos.** (v1 of this
repo packaged the full Claude Code workflow as a plugin; it survives at the
`plugin-v1-archive` tag. v2 narrows to the piece that proved most worth
sharing: the merge-gate infrastructure.)

Templates for putting the **merge decision on the server** so that humans and
coding agents can share a repo without per-PR human approval — and without
trusting any agent's self-report. Proven on two private instantiations (a
multi-branch product monorepo and a single-account homelab monorepo) before
extraction; the knobs that differed between them are exactly the parameters
these templates expose.

## The problem

Path-filtered CI plus advisory bot reviews is theater the moment an agent (or
a tired human) can merge: any write-permission integration can post a passing
status, a suite that never fired looks the same as a suite that passed, and
local git hooks don't exist on a fresh clone. If agents open PRs, the merge
gate has to be something no PR author — human or agent — can forge or dodge.

## The shape

One **always-run required check** (`merge-gate`) attests that every CI suite
the PR's diff *requires* has succeeded on the head SHA, and a **branch
ruleset** makes that check — bound to the GitHub Actions app — the only thing
standing between green CI and merge. Everything else (bot reviews, coverage
receipts) is deliberately advisory.

```
PR opened ──► suites fire (path-filtered, as usual)
         └──► merge-gate fires (NO path filter — always materializes)
                 │  reads the diff, decides which suites are required,
                 │  polls until each has a successful run for this SHA
                 ▼
          ruleset requires merge-gate (app-bound) ──► merge allowed
```

### The attestation contract

A ruleset closes the forgery class only with **all** of the following;
anything less is theater:

1. Required checks **bound to the GitHub Actions app** (`integration_id`
   15368), so no other integration can post a passing check under the name.
2. **No standing bypass actors** — admins included. Direct pushes,
   force-pushes, and branch deletion blocked on every gated branch.
3. **Approvals 0 by default** — CI green = mergeable. The human-review
   exception is scoped to infra-cost paths (CODEOWNERS where account
   topology allows it, a required guard workflow where it doesn't — see
   `docs/knobs.md`).
4. The gate itself is **fail-closed by construction**: an expected suite with
   no run at the deadline is a failure, an Actions API error retries then
   fails, and a diff too large for the API to enumerate is a failure. A skip
   is only ever derived from the diff not matching a suite's paths — never
   from missing data.
5. **Break-glass is disabling the ruleset itself** — loud, audit-logged, no
   standing hole (`docs/break-glass.md`). Never a bypass actor: agents
   typically run under the same account that would hold the bypass.
6. The ruleset JSON lives **versioned in the consuming repo** and the live
   ruleset is applied from it — policy changes are diffable PRs, never quiet
   UI edits.

### Known limitations — read before trusting the gate

- **The agent-infra-guard keys on branch naming, which is convention, not
  authentication.** In a single-account repo an errant agent that names its
  branch like a human's bypasses the guard entirely. The guard narrows the
  accident surface and makes violations loud; it is not a security boundary
  against an adversarial agent. Closing that residual requires a separate,
  non-admin agent identity (a GitHub App whose PRs are attributable), at
  which point the guard can key on author instead of branch name.
- **The suite map is a mirror, and mirrors drift.** Pattern-width drift
  fails safe (false red); a missing arm or unlisted suite fails silent. The
  pin tests in `docs/setup.md` are the mechanical guard — ship them with the
  gate.
- **Check verdicts are SHA-scoped at GitHub's layer.** A check run attaches
  to a commit, not a PR: two PRs whose heads are the same commit share every
  check verdict — including merge-gate's own. The gate filters suite runs by
  head branch as well as SHA (so it never *builds* its verdict from another
  branch's runs), but no gate logic can stop the ruleset from reading a
  shared SHA's existing green check. Treat a shared-SHA PR pair as the
  anomaly it is (usually a re-cut branch); a fresh commit is the only clean
  slate.
- **Agents holding the repo-admin credential can disable the ruleset.**
  Tampering is loud-and-logged, not impossible, until agents get their own
  non-admin identity.
- **A reviewer bot allowed to request changes re-introduces a blocking gate
  the ruleset can't see.** With a `pull_request` rule active, an outstanding
  CHANGES_REQUESTED review blocks the merge even at approvals 0 — so a bot
  configured to submit change requests (e.g. CodeRabbit's
  `request_changes_workflow: true`) silently overrides the all-advisory
  contract, and every false positive then needs a human dismissal. Configure
  reviewer bots comment-only; this knob lives in the bot's config, not the
  ruleset, which is why nothing here can enforce it.

## What's here

| Path | What it is |
|---|---|
| `rulesets/single-branch.json` | Ruleset template: one deploy branch, guard workflow as the second required check (single-account topology) |
| `rulesets/staging.json` / `rulesets/production.json` | Ruleset template pair: staged bases with a promotion arm (org topology, native code-owner review) |
| `workflows/merge-gate.yml` | The always-run suite-attestation gate (optional promotion + draft arms) |
| `workflows/agent-infra-guard.yml` | `pull_request_target` protected-surface guard — the code-owner-review substitute for single-account repos |
| `workflows/auto-ready.yml` | Auto-ready inversion: flips a green agent draft to ready off `workflow_run` completions |
| `workflows/fast-lane.yml` | Staged-CI fast-lane skeleton (drafts run cheap checks; full suite at the publish flip) |
| `workflows/review-coverage.yml` | Coverage receipts — a neutral, never-gating check run recording who reviewed |
| `docs/repo-contract.md` | The six-item interface a consuming repo must expose |
| `docs/knobs.md` | Every policy knob, its default, and what flipping it costs — including the plan-tier constraints |
| `docs/setup.md` | Instantiation walkthrough: pick knobs → fill templates → bootstrap open PRs → apply → verify |
| `docs/break-glass.md` | The ruleset-disable runbook template |
| `CLAUDE.md.template` | "How work merges here" section for the consuming repo's CLAUDE.md / AGENTS.md |

Templates are complete, working workflows with `TODO(template)` markers at
every per-repo parameter. Structure outside those markers is deliberately
identical to the proven instantiations — resist editing it during
instantiation; divergence is how gates rot.

## Quickstart

1. Read `docs/repo-contract.md` — if your repo can't expose that interface,
   fix that first.
2. Work through `docs/knobs.md` and pick a value for each knob (the defaults
   are the proven ones).
3. Follow `docs/setup.md` — including the **bootstrap runbook** (already-open
   PRs don't have the new checks on their head SHAs; applying the ruleset
   before re-triggering them strands every one at "Expected").
4. Apply the ruleset, verify a direct push is refused, then — and only
   then — remove any local merge-discipline git hooks the server now
   replaces.

## Requirements

- **Public repos:** rulesets on every plan.
- **Private repos:** rulesets need GitHub Pro (personal) / Team (org).
- **Evaluate mode** (dry-run enforcement) is Enterprise-only — on Pro/Team
  the apply is live immediately, which makes it a deliberate human step.
- The auto-ready workflow needs a PAT or GitHub App token
  (`markPullRequestReadyForReview` requires `contents: write` +
  `pull-requests: write`; the default `GITHUB_TOKEN` also can't trigger
  downstream workflows).

## License

MIT
