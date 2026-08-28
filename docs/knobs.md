# Policy knobs

Every parameter the two proven instantiations turned differently — plus the
knobs they kept identical on purpose. Defaults are the proven settings.
Everything NOT listed here is structure: extract it verbatim and resist
"improving" it during instantiation.

## Topology knobs (pick once, they select which templates you use)

| Knob | Options | How to pick |
|---|---|---|
| Gated bases | one deploy branch (`rulesets/single-branch.json`) vs staged bases + promotion arm (`rulesets/staging.json` + `production.json`, merge-gate promotion arm) | Does a merge to the branch deploy directly? One branch → single. Integration branch + separate promotion → staged; the promotion arm makes PRs into the promotion branch a *shape* check (head must be the integration branch itself), and merging a promotion PR stays a human act by policy. |
| Human gate on infra paths | native CODEOWNERS + `require_code_owner_review: true` vs the agent-infra-guard workflow as a second required check | **Account topology decides.** An org with reviewers who are not the PR author → native. A single-account repo (agents push under the owner's account or a PAT of it) → the guard: GitHub forbids authors approving their own PRs, so `require_code_owner_review` would hard-block every infra PR forever. If the guard is chosen it must be its own `pull_request_target` required check — never a step inside a `pull_request` workflow, or the PR it polices can neuter it. Keep CODEOWNERS as a documentation copy and pin the pairing with a test. |
| Staged CI | fast lane on drafts + full suite at publish flip (+ merge-gate draft arm) vs same suites on drafts and ready | Suite cost decides. A 15-minute suite → stage it. Minutes-cheap suites → don't: the draft arm would strand agent drafts unless auto-ready excludes the gate from its verdict, which is complexity you don't need. |
| Ruleset rollout | `evaluate` → observe → `active` vs `active` from the apply | Plan tier decides, not preference: **evaluate mode is Enterprise-only.** On Pro/Team the create call rejects it — the apply IS the go-live, which makes it a deliberate human step. Break-glass (disable → fix → re-enable) is the observation fallback. |

## Value knobs (defaults shown; each is a one-line change)

| Knob | Default | Lives in | Flipping costs |
|---|---|---|---|
| Review enforcement | All-advisory — no bot check is required | Ruleset required checks | Requiring a vendor's check couples merge availability to that vendor's rate limiter, with no bypass that doesn't also weaken the no-bypass-actors rule |
| Required approvals | 0 | Ruleset | Raising it re-inserts a human into every merge — and hard-blocks a single-account repo entirely |
| Strict up-to-date | OFF | Ruleset | ON re-runs full CI on every base movement (merge-queue substitute; enable on evidence of stale-base breakage, not preemptively) |
| Stale-approval dismissal | OFF | Ruleset | Only meaningful where approvals are required |
| Bypass actors | none — admins included | Ruleset | A standing bypass on the owner's account is silently walkable by every agent that authenticates as the owner |
| Suite list + `wants()` path map | per-repo by definition | merge-gate.yml | Pattern-width drift over-expects (false red — safe); a MISSING arm or unlisted new suite under-attests silently — the setup doc's pin tests 1–2 are the mechanical guard, treat them as mandatory |
| Gate deadline | 38 min | merge-gate.yml | Size for the slowest suite's *healthy* ceiling + headroom, not its pathological tail; a passing suite finishing past deadline reds the gate in the safe direction and a re-run recovers |
| Protected-surface list | `.github/**`, task runner, deploy/sync config | guard workflow or CODEOWNERS | A gap is protection that exists on paper only |
| Agent branch pattern | `agent/*` | guard + auto-ready | Convention, not authentication: an errant agent on a human-shaped branch bypasses agent-scoped enforcement; closing that needs a separate non-admin agent identity (GitHub App), not a smarter pattern |
| Concurrent agent PRs | 2–3 in flight | dispatch habit | None — breakable at will; that's the point |

## Plan-tier constraints (verified Aug 2026)

- Rulesets: free on public repos; **private repos need Pro (personal) or
  Team (org)**. On free tier the rulesets endpoint 403s.
- `evaluate` enforcement: **Enterprise-only** everywhere.
- `markPullRequestReadyForReview` (auto-ready's flip): needs `contents:
  write` + `pull-requests: write` on a PAT or App token; the default
  `GITHUB_TOKEN` also can't trigger the downstream workflows the flip is
  supposed to start.
- A GitHub App identity for agents (closing the branch-naming residual and
  keeping ruleset administration admin-only) works on all plans.

## Local-machinery removal (the last knob)

Per-repo, at that repo's cutover, **only after its ruleset is observed
live** — never a big-bang sweep. What the server now owns (pre-push
merge-discipline hooks, local gate sentinels, trust-by-existence markers)
goes; lint-only pre-commit hooks are a feature, not a gate — keep them.
Session-plane safety hooks (anything gating an interactive assistant rather
than merges) are out of scope.
