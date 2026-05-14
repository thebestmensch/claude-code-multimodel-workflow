---
description: Run a lensed code review on the diff currently being committed (working tree + staged by default; explicit range optional). Detects applicable review lenses from changed files.
effort: medium
---

Run a lensed code review on recent changes. Automatically detects which review lenses apply based on changed files, then dispatches a code reviewer with those lenses as additional focus areas.

## Inputs

- `$ARGUMENTS`: Optional. Accepts one or more of:
  - A git range: `HEAD~3..HEAD`, `abc123..def456`
  - `--cached` or `--staged` — force review of staged-only diff
  - `--worktree` — force review of unstaged + staged working-tree diff
  - A lens name to force: `security`, `performance`, `data-integrity`, `migration`
  - `all` — force all lenses regardless of file triggers
  - Empty → **default selection rule** below

## Default Selection Rule

The default range MUST match what is about to be committed, so a `/code-review` immediately before `/commit` actually reviews the diff that will be committed:

1. If `git diff --cached` is non-empty → review staged diff (`git diff --cached`).
2. Else if `git diff` is non-empty → review unstaged working-tree diff (`git diff`).
3. Else → review the most recent commit (`HEAD~1..HEAD`).

Always announce the selected range in the output (e.g. `Range: staged diff (5 files)` or `Range: HEAD~1..HEAD`). The `/commit` gate uses this announcement to verify the review covered the right diff.

## Process

1. **Determine the diff range:**
   ```bash
   if [ -n "$EXPLICIT_RANGE" ]; then
     # User passed a range — use it
     RANGE="$EXPLICIT_RANGE"; SCOPE="explicit"
   elif ! git diff --cached --quiet; then
     RANGE="--cached"; SCOPE="staged"
   elif ! git diff --quiet; then
     RANGE=""; SCOPE="worktree"   # `git diff` with no args = unstaged
   else
     BASE_SHA=$(git rev-parse HEAD~1)
     HEAD_SHA=$(git rev-parse HEAD)
     RANGE="$BASE_SHA..$HEAD_SHA"; SCOPE="last-commit"
   fi

   git diff --stat $RANGE
   git diff --name-only $RANGE
   ```

   Record `SCOPE` and the file list — `/commit` will check that the most recent code review's `SCOPE` matches the staged diff's file list.

2. **Detect applicable lenses:**

   Read all `.md` files in `.claude/docs/review-lenses/` in the current project (fall back to `.claude/rules/review-lenses/` for projects that haven't migrated). Each lens config has a `## Triggers` section listing file path patterns.

   Match the changed files (`git diff --name-only`) against each lens's trigger patterns. A lens activates if ANY changed file matches ANY of its triggers.

   If `$ARGUMENTS` contains a lens name, force-activate that lens regardless of triggers.
   If `$ARGUMENTS` contains `all`, activate all lenses.

   If no lenses match, still run the base code review without lenses — the review is still valuable.

3. **Build the review prompt:**

   Start with the base code review template (below), then append each activated lens's review criteria as an additional section.

4. **Dispatch the code review agent:**

   Launch a subagent with `model: sonnet` using the built prompt.

   The agent receives:
   - The git diff range to review
   - The base code review checklist
   - All activated lens criteria (appended as additional focus areas)
   - The project's CLAUDE.md for general context

   The agent has access to: Read, Grep, Glob, Bash (for git commands)

5. **Present findings:**
   - Group by severity: Critical → Important → Minor
   - For each finding, include file:line reference
   - If a finding comes from a specific lens, tag it: `[security]`, `[performance]`, etc.
   - Include the merge readiness verdict

---

## Base Code Review Template

```
You are a code reviewer. Review the changes in the given git range for production readiness.

## Diff Scope

**Scope:** {SCOPE}  (one of: `staged`, `worktree`, `last-commit`, `explicit`)
**Range argument:** `{RANGE}`  (e.g. `--cached`, `""` for unstaged, `HEAD~1..HEAD`)

Run these commands to see the changes:
```bash
git diff --stat {RANGE}
git diff {RANGE}
```

Read the CLAUDE.md file for project context and conventions.

## Base Review Checklist

**Code Quality:**
- Clean separation of concerns?
- Proper error handling for the context? (external APIs need it, internal calls usually don't)
- Edge cases handled?
- No unnecessary abstractions or premature generalization?

**Architecture:**
- Follows existing patterns in the codebase?
- No unintended side effects on other services?
- Database access follows the project's async patterns?

**Testing:**
- Tests cover the new behavior?
- Tests assert on stable structure, not on volatile or randomized content?
- Sync vs async mocking matches the code under test?

**Production Readiness:**
- Health/readiness signals still pass?
- No secrets in source code?
- No breaking changes to APIs used by other services?

{LENS_SECTIONS}

## Output Format

### Strengths
[What's well done — be specific, cite file:line]

### Issues

#### Critical (Must Fix)
[Bugs, security issues, data loss risks, broken functionality]
{Tag each with lens if applicable: [security], [data-integrity], etc.}

#### Important (Should Fix)
[Architecture problems, missing edge cases, test gaps]

#### Minor (Nice to Have)
[Style, optimization, documentation]

**For each issue:**
- File:line reference
- What's wrong
- Why it matters
- How to fix

### Assessment

**Ready to merge?** [Yes / No / With fixes]
**Active lenses:** [{list of lenses that were applied}]
**Reasoning:** [1-2 sentences]
```

---

## Output

Present as:

```
## Code Review Results

**Range:** `{SCOPE}` — `{RANGE}` ({N} files changed)
**Files reviewed:** {comma-separated file list — `/commit` checks this matches the staged diff}
**Lenses:** {list of activated lenses, or "base only"}

### Strengths
[what's well done]

### Critical
[must-fix issues + how to fix]

### Important
[should-fix issues + how to fix]

### Minor
[nice-to-haves]

**Verdict:** [Ready / With fixes / Not ready]
```
