---
effort: medium
---

Drive an open PR to green-merged state by iterating with CodeRabbit (and any other automated reviewers) until all comments are resolved, then merge.

> Usage: `/jm-pr [PR#]`
>
> With a number: target that PR.
> Without: detect the PR for the current branch (`gh pr view --json number`).
>
> **Autonomous mode.** The user is hands-off. You and CR resolve the PR end-to-end: triage comments, fix or push back, push, wait for re-review, repeat until green, then merge. Escalate to the user only when truly blocked (see § 5 cap, § 8 escalation triggers).

## Why this exists

After opening a PR, the loop is: wait for CodeRabbit → triage comments → fix or push back → commit → push → wait for re-review → repeat until clean. This is mechanical but high-touch, and the failure mode is sycophantic acceptance of every CR nit. This command encodes the loop with explicit push-back discipline.

## Scope

- **In scope:** CodeRabbit comments, GitHub Actions check failures, merge conflicts with base (resolve when strategy is unambiguous), merging the PR once green.
- **Out of scope:** Force-pushing to a shared branch, force-pushing to main, approving your own PR via `gh pr review --approve`, deleting the base branch, re-requesting human review.
- **Human review comments** — if a human reviewer left blocking comments, treat them as escalation (see § 8). Don't act on human comments autonomously; only CR is in the autonomous loop.

## Process

### 1. Resolve the target PR

If `$ARGUMENTS` is a number: `gh pr view <N>`.
Otherwise: `gh pr view --json number,headRefName,baseRefName,state,mergeable,statusCheckRollup,reviewDecision`. If no PR exists for the current branch, abort with: "No PR found for this branch. Open one first."

Capture and announce: PR number, branch, base, current state, mergeable status, last commit SHA. This anchors the loop's "since when" boundary for fetching new comments.

### 2. Snapshot the inbox

Before any fixes, enumerate everything blocking merge:

- **CodeRabbit comments:** `gh api repos/{owner}/{repo}/pulls/{N}/comments` — filter for `user.login == "coderabbitai[bot]"` (or `coderabbitai`). Bucket by file + line.
- **Other inline comments:** same endpoint, group by author.
- **Issue-level review comments:** `gh api repos/{owner}/{repo}/issues/{N}/comments` for `user.login == "coderabbitai[bot]"` summary posts (the long "Walkthrough" + "Actionable comments" body).
- **Failing checks:** `gh pr checks <N>` — capture failing runs and follow their logs.
- **Merge state:** if `mergeable == "CONFLICTING"`, attempt resolution autonomously when the strategy is obvious (lockfile regen, generated-file rebase, trivial textual conflicts where one side is clearly stale). Escalate (§ 8) when the conflict touches business logic, schema, or any file where both sides made independent semantic changes.

Filter against the latest push SHA — anything CR posted before the current HEAD that's already addressed by a later commit can be skipped. CR's `resolved` flag on conversations is the authoritative "this is done" marker; respect it.

### 3. Triage each comment

For every unresolved CR (or human) comment, decide one of three dispositions. Write the disposition inline before acting on it — don't silently fix everything.

| Disposition | When | What to do |
|---|---|---|
| **Fix** | Concrete bug, security issue, real correctness problem, or a clear style/lint violation that matches house conventions | Apply the change. Group fixes by file when possible. |
| **Push back** | CR's claim is wrong (false positive on dynamic typing, stylistic preference that contradicts house style, misread of the code), or the suggestion would make the code worse | Reply on the thread with a one-paragraph technical rebuttal — cite the relevant convention, file, or line that supports your reasoning. `gh api -X POST repos/{owner}/{repo}/pulls/{N}/comments/{cid}/replies -f body=...`. Then mark the conversation resolved. Push-back is autonomous — don't ask the user; the rebuttal itself is the audit trail. |
| **Defer** | Real but out of scope for this PR (refactor, follow-up improvement, separate concern) | Reply acknowledging + linking to a tracker issue (Linear, GitHub issue, etc.) created via the appropriate MCP tool. Mark resolved. |

**Sycophancy guardrail.** If you find yourself fixing more than ~80% of CR comments without a single push-back across 2+ rounds, stop and re-read the comments cold. CR's signal is high but not perfect; pure acceptance is the failure mode this command exists to prevent. Validated push-backs are part of the deliverable.

**House style precedence.** Project CLAUDE.md > existing code patterns > CR suggestion. When CR contradicts house style, push back.

### 4. Apply fixes

Group fixes into logical commits (one commit per concern, not one commit per comment). Use Conventional Commits. Don't squash CR fixes into the original feature commit — keep the review history readable.

Each commit must pass the same review gates the original work passed:
- If a `codex-stop-gate` or equivalent adversarial-review gate is configured for this project, it applies on every commit. Don't bypass without a written reason.
- Local lints/tests run before push. If the project has a pre-push hook, let it run.

**Never `--no-verify` to silence a failing hook.** If a hook blocks the push, the hook is reporting a real problem — fix it or escalate (§ 8).

### 5. Push and wait

`git push`. Then poll:

```bash
gh pr checks <N> --watch  # blocks until checks finish
```

Once checks settle, wait for CR to re-review. CR's typical latency is 1-3 minutes after the push completes; the new comments appear under a fresh review. Re-run § 2 with the new HEAD SHA as the boundary.

Cap at **5 rounds** of push-back-and-forth. After 5, if it's still not green, escalate to the user (see § 8). 5 rounds without convergence almost always means: contentious design choice, missing context CR doesn't have, or a scope issue the PR shouldn't be solving in one shot.

This prevents infinite-loop drain on a genuinely contentious PR.

### 6. Verify clean state

The PR is mergeable when ALL of:

- `gh pr checks <N>` — all required checks green
- `gh pr view <N> --json mergeable` — `MERGEABLE`
- `gh pr view <N> --json reviewDecision` — `APPROVED`, or `null` (no human review required by branch protection). If `REVIEW_REQUIRED` and a human reviewer hasn't approved yet, escalate (§ 8); do NOT self-approve or merge.
- All CR conversations resolved or have a reasoned reply + closed thread
- No new CR comments since the last push

Run those checks explicitly. Don't infer from "looks fine."

### 7. Merge

Detect the project's merge strategy and run the merge:

```bash
# Detect: gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed
gh pr merge <N> --<strategy> --delete-branch
```

Strategy precedence: project CLAUDE.md > repo settings (prefer the most restrictive allowed: squash > rebase > merge) > squash as default. `--delete-branch` cleans up the remote branch after merge; local cleanup happens in `/jm-wrap`.

After merge, verify:

```bash
gh pr view <N> --json state,mergedAt,mergeCommit  # state should be MERGED
```

### 8. Escalation triggers

Stop the loop and ask the user when ANY:

- **5-round cap** reached without convergence (§ 5)
- **Human reviewer left blocking comments** — surface them verbatim, don't paraphrase or auto-act
- **Branch protection requires approval** and no human has approved (don't self-approve)
- **Ambiguous merge conflict** the strategy isn't obvious for (§ 2)
- **Pre-push hook fails for a reason you can't fix** (CI infra issue, missing secret, environment problem)
- **CR keeps regenerating the same finding after a push-back** — third repeat means CR genuinely disagrees and the call is yours, not mine
- **Push-back reply gets a reasoned counter-argument from a human** — human enters the loop, autonomy exits
- **A finding crosses out of scope into a multi-PR-sized concern** (architectural change, schema migration, security-sensitive refactor)

Escalation format: state which trigger fired, what's been done so far, what the remaining options are, and what you'd recommend. Don't make the user dig.

### 9. Report

After merge (or escalation), final message in chat:

```
PR #<N> merged via <strategy>   ← (or "escalated: <trigger>")

Rounds: <X>
Fixed: <count> comments across <files>
Pushed back: <count> (with one-line summary of each)
Deferred: <count> → tracker: <ticket IDs>
Merge commit: <SHA>             ← (omit if escalated)
Remote branch: deleted          ← (omit if escalated)
```

## Guardrails

Autonomous mode is broad permission to act, not a license to skip review or take risky shortcuts. The user is hands-off on routine decisions; these are the lines that still hold:

- **Never force-push.** No exceptions in this command. If the situation seems to require it, escalate.
- **Never close the PR** or modify its title/description. The PR identity is the user's.
- **Never approve your own PR** programmatically. Self-approval defeats the point of review gates even when allowed.
- **Never self-merge when human review is required.** If branch protection sets `REVIEW_REQUIRED`, the merge waits for a human approval — escalate per § 8.
- **Surface human review comments verbatim.** Humans aren't in the autonomous loop — escalate, don't auto-respond.
- **Respect adversarial-review gates** on every push. CR loops are exactly the moment where bypassed review compounds — small fixes are deceptively easy to ship without adversarial coverage.
- **Merge only via the project's allowed strategy.** Detect from `gh repo view`, don't assume.
- **`--delete-branch` is fine on merge** (remote branch only). Local cleanup is `/jm-wrap`'s job.

## Boundary

This command handles **post-open through merge** PR lifecycle. For pre-open PR creation, use `gh pr create` directly. For post-merge cleanup (local branch deletion, worktree cleanup, deferred-ticket handling), use `/jm-wrap`.
