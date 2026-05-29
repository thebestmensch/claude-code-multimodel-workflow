---
description: Commit staged changes using Conventional Commits format. Verifies pre-commit reviews fired on the diff being committed.
disable-model-invocation: true
effort: low
---

Commit all staged changes using the Conventional Commits specification.

## Pre-Commit Review Gate

Before running the commit process, verify mandatory reviews actually covered the diff being committed (not a different diff):

1. **Compute the staged file list:**
   ```bash
   git diff --cached --name-only | sort
   ```

2. **Code review identity check:**
   - Find the most recent `/lens-review` (or code-reviewer agent) output in this conversation.
   - Read its `Range:` and `Files reviewed:` lines.
   - The review MUST have been run against `staged` scope (or against an explicit range that matches the staged file list).
   - The `Files reviewed:` list MUST equal the staged file list from step 1 (sorted comparison).
   - If NO review fired, OR `Range:` was `last-commit`/`worktree` while staging is non-empty, OR the file lists differ → STOP, dispatch `/lens-review` (it now defaults to staged when staged is non-empty), then re-run this gate.

3. **Visual QA:** If the staged changes include CSS, HTML templates, JSX/TSX, or any visual/UI files, apply the same identity check against the most recent `/visual-qa` output. The reviewed surface must correspond to the staged UI files.

**If either required review was NOT dispatched:**
- Stop. Do NOT proceed with the commit.
- Tell the user which review(s) were skipped and offer to dispatch them now.
- Only proceed after reviews complete OR the user explicitly says to skip (e.g., "commit without review", "skip review").

**When to skip the gate (no review needed):**
- Changes are docs-only (`.md`, `.txt`, comments)
- Changes are config/CI-only (`.yml`, `.toml`, `.json`, `justfile`)
- Changes are test-only (no production code modified)
- User explicitly requested a no-review commit

## Red Flags

If you catch yourself thinking any of these, STOP. You're rationalizing past the gate.

| Excuse | Reality |
|--------|---------|
| "I already looked at the diff, that counts as a review" | Your own eyes on your own changes are not a code review. You wrote the bug; you can't see it. |
| "It's a small change, no review needed" | Small changes cause outages too. The gate exists because humans are bad at judging what's "small enough." |
| "I'll get a review after the commit" | Post-commit reviews don't block the merge. The gate is pre-commit for a reason. |
| "The linter passed, so it's fine" | Linters catch syntax. Reviews catch logic, security, and design. Different layers. |
| "The user is in a hurry" | The user is always in a hurry. That's when reviews matter most. |

## Process

1. Run `git status` and `git diff --cached` to understand what's staged
2. Verify no debugging code, console logs, or temporary files are included
3. Run lint and typecheck for the current repo using whichever toolchain it provides (e.g., `bun run lint`, `npm run lint`, `cargo clippy`, `ruff check`, `make lint`). If either fails, fix the issues before proceeding; do not commit broken code
4. Generate a commit message following the format below
5. Execute the commit
6. Display the commit hash and summary

## Conventional Commits Format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Types

- `feat`: New feature for the user
- `fix`: Bug fix for the user
- `docs`: Documentation changes
- `style`: Formatting, no code change
- `refactor`: Code change that neither fixes a bug nor adds a feature
- `perf`: Performance improvement
- `test`: Adding or updating tests
- `build`: Changes to build system or dependencies
- `ci`: Changes to CI configuration
- `chore`: Other changes that don't modify src or test files
- `revert`: Reverts a previous commit

### Rules

- Description: imperative mood, lowercase, no trailing period
- Breaking changes: add `!` after type/scope and include `BREAKING CHANGE:` footer
- Do not commit if there are no staged changes
- Do not commit if linter errors or test failures exist
- Scope should reflect the module or feature area in the codebase (e.g., `auth`, `api`, `cli`, `ui`)

### Examples

```
feat(parser): add support for nested config blocks
fix(auth): correct token expiry comparison
refactor(cli): extract argument validation into helper
```

With body:

```
feat(auth): add JWT token refresh endpoint

Implements automatic token refresh to reduce login frequency.
Tokens are refreshed 5 minutes before expiration.
```
