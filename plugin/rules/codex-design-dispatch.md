# Codex Design Dispatch: Cross-Provider Design Recon at the Proposal Stage

> **Optional integration (opt-in Tier 2).** This rule and its wrapper require the Codex CLI plus the `openai-codex` Claude Code plugin (`claude plugin install codex@openai-codex`), the same opt-in dependency `codex-dispatch.md` frames. The wrapper ships in this plugin at `plugin/tools/codex-design-dispatch.sh`, but it shells out to `codex-companion.mjs` from the `openai-codex` plugin cache. Without Codex installed, this is a no-op design aid: skip it and rely on the Claude design pipeline (`visual-qa-dispatch.md` Polish QA). Unlike the commit-time gate in `codex-dispatch.md`, design recon has **no enforcement hook**, so nothing blocks if Codex is absent.

Codex (GPT-5.x) sits alongside Claude design agents as a **cross-provider second seat at design-proposal time**, the same non-overlap principle that justifies `codex-dispatch.md` at commit-time, applied earlier in the pipeline. Different blind spots, different value.

This rule loads alongside `visual-qa-dispatch.md`, `advisory-agents-dispatch.md`, and `codex-dispatch.md`. The boundary is **stage of the pipeline**, not surface:

- **`codex-dispatch.md`**: *commit-time* on the diff (`review` / `adversarial-review`). Catches regressions in code that already exists.
- **`visual-qa-dispatch.md`**: *after implementation* on rendered pixels (Bug QA / Polish / Accessibility / Tone). Catches "does it render right?"
- **This rule**: *before implementation* on the proposal (Codex `task` mode with designer envelope). Catches "is the design right?"

All three can fire on the same surface across one ticket's lifecycle.

## When to Dispatch

**Fire when ALL:**
- The work is **explicitly design**: new visual surface, redesign, look-and-feel ask. Not "fix the alignment bug." Not "rename this prop."
- The output surface is one of: CSS, HTML templates (Jinja2 / Astro / etc.), JSX/TSX, React Native styles, design tokens.
- A design proposal is genuinely upstream: code hasn't been written yet, or is being rethought.

**Skip when ANY:**
- It's a bug fix on an existing visual surface (visual-qa-dispatch covers post-fix).
- It's a refactor preserving existing design.
- The user has already pinned exact fonts/colors/spacing: no proposal needed.
- The change is mechanical token propagation (e.g. accent recolor across 12 files).

## Announce

One line before invoking. Either form is valid:

- **Default:** `Dispatching Codex design-recon on the [surface]`
- **Skip with reason:** `Skipping Codex design-recon on the [surface] because [specific reason]`

Silent skipping is the failure mode this rule catches.

## How to Dispatch

This plugin ships a wrapper at `plugin/tools/codex-design-dispatch.sh`. It hardcodes the *thoughtful frontend designer* envelope (named-font + pinned-hex + verified-contrast output shape), reads brief from `--brief-file` or stdin, runs `task` mode in the background, and does NOT trigger the commit-time `codex-stop-gate`.

```bash
$HOME/.claude/plugins/cache/claude-code-multimodel-workflow/*/plugin/tools/codex-design-dispatch.sh --brief-file <repo>/.claude/scratch/<surface>-design-brief.md
echo "$BRIEF" | $HOME/.claude/plugins/cache/claude-code-multimodel-workflow/*/plugin/tools/codex-design-dispatch.sh
$HOME/.claude/plugins/cache/claude-code-multimodel-workflow/*/plugin/tools/codex-design-dispatch.sh status [job-id]
$HOME/.claude/plugins/cache/claude-code-multimodel-workflow/*/plugin/tools/codex-design-dispatch.sh result [job-id]
```

Tip: the unquoted `cache/claude-code-multimodel-workflow/*/` glob expands to the installed plugin version. Operators who want a shorter alias can `ln -s` the resolved path to `~/.claude/codex-design-dispatch.sh`.

Brief skeleton: `codex-design-brief-template.md` (ships alongside this rule). The template enforces "verify current state first" so a stale premise doesn't burn a round.

**Brief storage:** durable path. `<repo>/.claude/scratch/<surface>-design-brief.md`. Never `/tmp`: round-1 results frequently mis-shape and re-dispatch needs the same brief intact (the round-2 envelope fix should keep the brief unchanged).

## Why a Separate Wrapper from `codex-plan-critique.sh`

Same `task` mode. Same model. Same input file. *Opposite* output shape, purely because of the envelope. `codex-plan-critique.sh` hardcodes "You are an adversarial plan reviewer. Critique this for missing cases...", produces prioritized critique. The design-dispatch wrapper hardcodes "You are a thoughtful frontend designer. Propose concrete implementable changes...", produces named fonts, pinned hex, verified contrast.

Validated on a personal-site footer recon. Round 1 dispatched a design brief through `codex-plan-critique.sh`: Codex critiqued the brief itself (correctly per the envelope), returned 5 latent gaps as prioritized critique. Useful recon, wrong shape. Round 2 used a designer envelope: returned EB Garamond + `#7a3f2f` oxblood at verified 6.86:1 contrast + 68ch reading container + ❦ ornaments.

New use case = new wrapper. The wrapper ecosystem is sparse by design: the envelope shape determines output shape; bypassing it for a one-off works, but if the use case repeats, file a wrapper.

## Sibling: `/visual-qa polish` (Claude Polish QA)

Claude `/visual-qa polish` and Codex design-recon are complementary, not redundant:

| | Reads | Catches |
|---|---|---|
| `/visual-qa polish` | Rendered screenshots + project philosophy | Pixel-level polish: spacing rhythm, hover states, visual hierarchy, weight contrast against the rendered output |
| Codex design-recon | Source code + design brief | Named-font research, package-license verification, OpenType feature coverage in specific `@fontsource` builds, mathematical WCAG contrast verification, structural CSS / container splits, implementation-cost realism |

Both at design-stage if the surface is high-stakes: dispatch Codex on the proposal, ship the Cornerstone tier, then run `/visual-qa polish` on the rendered result.

## Cap and Discipline

- **One Codex design dispatch per surface per session.** Same cap shape as `advisory-agents-dispatch.md`'s plan critique. The brief is the unit, not the dispatch: iterating the brief and re-dispatching is loop-drain.
- **Background only** unless the brief is truly tiny (≤1 file, ≤5 lines of recon expected).
- **Present findings, never auto-act.** Mirror the Polish QA pattern: show what Codex proposed, group by Cornerstone / Important / Polish, let the user decide what to fold in.
- **Don't conflate with diff-time.** Codex design-recon runs at proposal time, separate budget from `codex-dispatch.md`'s diff-time cap. Subsequent implementation still needs `codex-dispatch.sh adversarial-review` (or a written diff-gate bypass) before commit.

## Results Handling

- **Cornerstone** → fold into the implementation plan. These are the 1-3 highest-leverage changes; usually worth all of them.
- **Important** → user decision. Often worth shipping in the same PR; sometimes worth a follow-up.
- **Polish** → defer unless trivial. Small caps, ornaments, hover refinements, second-PR territory.
- **Concrete acceptance test** → use as the success criterion for the implementation work. "After these changes, a user viewing X should..." becomes the verification rubric.

If you disagree with a Codex proposal, push back with reasoning. Codex's value is cross-provider non-overlap signal; that doesn't make every finding correct.

## Boundary

This rule covers **proposal-time cross-provider design recon**. It does not cover:

- Post-implementation pixel review → `visual-qa-dispatch.md`
- Voice / tone on user-facing copy → `visual-qa-dispatch.md` (Tone QA) + project voice guides
- Adversarial plan critique (non-design proposals) → `advisory-agents-dispatch.md` + `codex-plan-critique.sh`
- Commit-time diff review → `codex-dispatch.md`

Codex sits alongside, not on top of, the existing design pipeline.
