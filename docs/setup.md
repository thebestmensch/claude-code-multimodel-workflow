# Setup — instantiating the kit on a repo

Order matters. The expensive mistakes in this walkthrough were all made so
you don't have to: applying the ruleset before bootstrapping open PRs strands
them; skipping the canary means the first real enforcement test is a real PR;
trusting the file without the probe push means "protected" is a belief.

## 0. Preconditions

- The repo satisfies `repo-contract.md` (or you're fixing that as you go).
- Plan tier supports rulesets on this repo (`docs/knobs.md`).
- You've picked every knob in `docs/knobs.md`.

## 1. Instantiate the templates

Copy the chosen templates into the repo:

- `workflows/merge-gate.yml` → `.github/workflows/merge-gate.yml`
- single-account: `workflows/agent-infra-guard.yml` → `.github/workflows/`
- agents opening draft PRs: `workflows/auto-ready.yml` → `.github/workflows/`
- staged CI: `workflows/fast-lane.yml` → `.github/workflows/` and add the
  mirror `if: github.event.pull_request.draft == false` to **every job** of
  the full-suite workflow (one unguarded job flips the draft-era run's
  conclusion from `skipped` to `success`, which the gate reads as a verdict)
- optional: `workflows/review-coverage.yml` → `.github/workflows/`
- ruleset JSON(s) → `.github/rulesets/` (keep them there forever — they ARE
  the policy; strip the `_template`/`_todo` keys)
- `CLAUDE.md.template` section → the repo's CLAUDE.md / AGENTS.md

Resolve every `TODO(template)` marker. The one that deserves real care is
merge-gate's `wants()` map: one case arm per suite, mirroring that suite's
`paths:` filter, each suite's own workflow file included in its arm.

**Pin the invariants with tests.** Pins 1–2 are not optional polish: they are
the only mechanical guard against the one drift direction the gate cannot
catch itself (a missing `wants()` arm or unlisted new suite silently
under-attests — the gate reads "not required" and passes). If the repo truly
has no test infrastructure, reviewing the SUITES/wants() mirror becomes a
required step of every PR that touches any workflow. The full set, in order
of value:

1. merge-gate has NO path filter, and every `pull_request` workflow is either
   in SUITES or in a documented not-gated set (derive from the tree — check
   both `.yml` and `.yaml`, normalize string/list/dict trigger forms).
2. Every SUITES entry has a `wants()` arm.
3. auto-ready's `workflows:` list == every workflow that registers PR check
   runs (`pull_request` OR `pull_request_target` triggers), derived, not
   hand-listed.
4. The ruleset's required context(s) == the corresponding job name(s) (two
   in the single-account topology, one in the staged topology), each bound
   to integration 15368.
5. Guard patterns == CODEOWNERS paths (compare as sets, not substrings).
6. The changed-file collector reads `.previous_filename` and fails closed at
   the 3000-file cap (pin the exact strings — a comment mentioning them must
   not satisfy the test).

## 2. Merge the workflows (nothing is enforced yet)

Land the workflows + ruleset JSON through your normal PR flow. The gate will
start running on PRs and validating itself — a good shakeout window: check
its log names exactly the suites you'd expect for each diff.

## 3. Bootstrap open PRs — BEFORE the apply

A newly-added check exists only for PRs whose head was pushed after the
workflow reached the default branch. Every PR already open at apply time has
NEITHER required context on its current head SHA — the ruleset would hold
them all at "Expected" forever, and a draft-parked agent PR gets no later
wakeup to recover. So:

1. Enumerate: `gh pr list --state open`.
2. Re-trigger each: push any commit (an empty commit via `git commit-tree`
   works without a checkout), or close/reopen — but prefer the empty commit
   for PRs wired to a tracker, where close fires completion automation.
3. Verify both contexts present and completed on every open PR's head:
   `gh pr checks <N>`.
   - A PR that gets neither: check `mergeable` — a CONFLICTING PR gets no
     `pull_request` workflows at all (GitHub can't build the merge commit).
     That's safe to leave: it can't merge under any policy, and the resolving
     rebase push materializes both contexts.
4. **Canary the guard** (single-account topology): open a throwaway PR from
   an agent-pattern branch touching a protected path; confirm the guard goes
   red naming the violation; close it and delete the branch.

## 4. Apply the ruleset

The apply is the go-live (no evaluate mode outside Enterprise) — a
deliberate human step, not a PR side effect:

```bash
gh api repos/<owner>/<repo>/rulesets --input .github/rulesets/<file>.json
```

This is a POST and not idempotent — running it twice creates a duplicate
ruleset under the same name. If a ruleset of this name already exists, use
the update form below instead.

Update later (policy change via PR first, then):

```bash
gh api repos/<owner>/<repo>/rulesets --jq '.[] | {id, name, enforcement}'
gh api -X PUT repos/<owner>/<repo>/rulesets/<ID> --input .github/rulesets/<file>.json
```

## 5. Verify enforcement — don't trust the apply

1. Read it back: enforcement `active`, both contexts, integration 15368, no
   bypass actors.
2. **Probe push:** push an empty commit directly to the gated branch and
   watch it be refused (`GH013 … Changes must be made through a pull
   request`). If it lands instead, you've just made a no-op commit and
   learned something important — investigate before anything else merges.

## 6. Only now: remove local merge-discipline hooks

Whatever local machinery the server replaced — pre-push gate hooks, local
merge sentinels — goes in a follow-up PR. Lint-only pre-commit hooks stay.
Keep the removal per-repo and after observation, never a sweep across repos
that haven't cut over.

## Operating notes

- **File/live lockstep:** every live-ruleset change gets mirrored to the JSON
  in the same sitting. Drift between them is the failure this layout exists
  to prevent.
- **Break-glass:** `docs/break-glass.md`. Never merge past a red gate by
  editing the required-check list — that's a policy change, and it goes
  through a PR.
- **Base-retarget edge:** a PR retargeted onto the gated branch starts with
  neither check (the workflows trigger on opened/synchronize/reopened, not
  `edited`) and sits at "Expected" until its next push. Fail-closed and
  self-explanatory; not worth widening the trigger types.
