# Code Review Dispatch

**CodeRabbit reviews PRs externally** — it covers general code quality, security, and the territory of the universal supplementary agents (silent-failure, type-design, api-contract, concurrency, test-gap, sentry-discipline) at merge time. In-session auto-dispatch is reserved for **project-specific reviewers** that catch footguns CodeRabbit can't.

**Always announce.** One line — which reviewers fire, or that you're skipping and why. Silent skipping is the failure mode this rule catches.

## When to Auto-Dispatch

**Mandatory auto-dispatch (pre-commit) — project-specific reviewers only:**
- After completing a feature or bug fix (before commit)
- Before merge to main
- After each task in subagent-driven development

The auto-firing reviewers come from the workspace's `code-review-*.md` overlay (e.g., your project's `code-review-<project>.md`). The base lensed review and the universal supplementary agents do **not** auto-fire — CodeRabbit owns that turf at PR time.

**Non-code feature work** (runbook updates, slash-command rewrites, design-doc implementations): invoke the `superpowers:requesting-code-review` skill, which dispatches `Task (general-purpose)` with the reviewer persona/checklist from `superpowers:requesting-code-review/code-reviewer.md`. Pass the spec/plan as context. Skip outright only for trivial doc edits. (The legacy `superpowers:code-reviewer` named agent was removed in superpowers v5.1.0.)

## Explicit `/code-review` (opt-in)

When you want pre-PR coverage of the territory CodeRabbit also reviews — sanity-check before push, or unsure if CR will catch a subtle case:

```
Skill("code-review")                     # auto-detects lenses, runs base review
Skill("code-review", args="security")    # force a lens
```

The `/code-review` skill runs the base review and lens detection. Universal supplementary agents may fire alongside it when their triggers match.

## Universal Supplementary Agents (opt-in only)

These do NOT auto-fire pre-commit. They run only when `/code-review` is invoked explicitly (the skill owns the trigger table and dispatch rules) or when you decide a change warrants pre-PR coverage beyond what auto-dispatch ran. Available types: `silent-failure-hunter`, `type-design-analyzer`, `concurrency-auditor`, `api-contract-reviewer`, `test-gap-analyzer`, `sentry-discipline-reviewer`.

## Dispatch pattern (auto and opt-in)

Each reviewer gets the same diff scope, derived from when the dispatch fires:

- **Pre-commit (auto-dispatch)** — work is in the working tree (and possibly the staged index) but not yet committed. Scope reviewers to `git diff` + `git diff --cached` (and any untracked files you added). Do NOT use a `BASE_SHA..HEAD_SHA` range here — it will be empty or stale.
- **Post-commit / pre-push / pre-merge** — work is on a branch above the merge base. Scope reviewers to `git diff {BASE_SHA}..{HEAD_SHA}` where `BASE_SHA` is the merge base with the target branch.

Use `model="sonnet"`, `run_in_background=true`.

**Cap at 2 auto-dispatched reviewers per commit.** When more project-specific reviewers trigger, prioritize the highest-stakes ones (workspace overlay declares which). When `/code-review` is explicit, the cap is 3 (base review + 2 supplementary).

## How to Use Results

- Critical -> fix immediately
- Important -> fix before commit/merge
- Minor -> note for user, fix if trivial
- Lens-tagged findings (`[security]`, `[data-integrity]`) often highest-value

If a reviewer flags something you disagree with, push back with technical reasoning — don't blindly implement.

## Boundary

Code-level only. Visual/a11y/tone -> `visual-qa-dispatch.md`. Plans/designs -> `advisory-agents-dispatch.md`. PR-time generic review -> CodeRabbit.
