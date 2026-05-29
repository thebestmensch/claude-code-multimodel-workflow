# Codex Design Brief Template

Skeleton for `codex-design-dispatch.sh` briefs. Copy, fill in the bracketed sections, drop unused ones. The wrapper hardcodes the *envelope* (designer voice, output shape, contrast-verification requirement); the brief carries the *context* (what surface, what vibe, what constraints).

The single biggest waste-of-round risk is a stale premise. A prior round was wasted because the brief described the site as "AstroPaper defaults with light edits" when the repo already had partial paperback alignment. **Every brief must include a "verify current state first, propose only the gaps" clause**: the wrapper enforces this in its envelope, but a precise current-state section in the brief cuts the verification cost in half.

---

## Brief skeleton

```markdown
# Design Recon: [surface] → "[target vibe in one line]"

## Read-only - no file edits, no patches. Recommendations only.

## Current state (verified)

The repo at the current cwd is past pure framework defaults. It has:

- [List 3-6 things that already align with the target vibe: token files, font
  choices, layout patterns, color palette. Quote actual paths/hex where known,
  but tell Codex to verify before proposing changes against them.]

So baseline chrome is already partially aligned. **Do not propose changes to
surfaces that already match the target.** Focus on the gaps.

## Known gaps (from prior recon - verify and build on these)

1. [Gap 1: which file/system, one-line current state, one-line direction.]
2. [Gap 2: ...]
3. [...]

(Skip this section on a fresh recon. Include it on a follow-up dispatch so
Codex doesn't re-discover what you already know: it adds value when there's
a known list to push past.)

## Target vibe

"[One-line vibe summary]"

- **Typography**: [reading face, weight axis, measure, leading, hierarchy approach]
- **Color**: [background tone, ink tone, accent direction: name colors and rough hex territory; let Codex pin the exact values]
- **Spacing**: [density, rhythm, breakpoints]
- **Sophistication**: [classical details: small caps, old-style figures, ligatures, ornaments, hanging punctuation, hairline rules]
- **Warmth / texture**: [paper grain, asymmetry, hand-set feel: what makes it feel "well-loved" not sterile]
- **NOT**: [3-5 anti-references that pull the wrong direction: "not Vercel/Linear", "not Medium default", "not dark-mode first", "not Material grid-perfect"]

## What I want from you

Prioritized design proposal, **not critique**. Per recommendation:

- **Surface**: file or system being changed
- **Current**: quote/describe what's there (verify by reading)
- **Proposal**: concrete, implementable. Named font + source + license; pinned hex + verified WCAG contrast; rem/px values; new class names where structure shifts.
- **Why this serves the vibe**: one sentence

Group by severity: **Cornerstone** (1-3 changes for 80% of the shift) →
**Important** (refinements) → **Polish** (small caps, ligatures, ornaments).

End with a concrete **acceptance test**: 2-3 sentences in the form "after
these changes, a user viewing X should ..."

## Constraints

- [Framework: e.g. "Astro + CSS only" / "RN + StyleSheet" / "Jinja2 + plain CSS"]
- [Font hosting: e.g. "self-host via `@fontsource`, note license" / "system stack only"]
- [Accessibility floor: e.g. "WCAG AA contrast on body text: verify hex pairs mathematically"]
- [Time budget: e.g. "implementable in a weekend by a working engineer": keeps proposals from over-reaching into brand-engagement territory]
- [Existing-baseline respect: "do not undo what's already aligned": pairs with the verified-current-state section]
- [Per-surface special cases: e.g. "for OG image fonts, recommend a self-hosted replacement matching article voice" / "for shared container token, propose a clean container split with new class name"]

## Verification expected before each proposal

- Read the relevant file. Quote current, propose replacement.
- For color recommendations, run WCAG contrast math against the paired background. Cite the ratio.
- For font recommendations, note whether OpenType features (`liga`, `dlig`, `smcp`, `onum`) are present in the chosen `@fontsource` package's variable build.

Begin.
```

---

## When to use which sections

| Recon type | Sections to keep | Sections to drop |
|---|---|---|
| **Fresh surface** (first design pass on a project) | Current state (light), Target vibe, What I want, Constraints, Verification | Known gaps (no prior pass) |
| **Follow-up pass** (round 2 on a surface) | All sections: known gaps gets fully populated from round 1 | None: known gaps is where round-1 findings live |
| **Workspace-overlay vibe** (a project that has a defined palette / brand) | All sections + extend Target vibe with the workspace anchor, e.g. "primary accent `#5B8DB8`, do not propose changes to the established per-app accent" | None |

## Anti-patterns

- **Don't paste a brand brief.** Codex doesn't need marketing copy. The target vibe section is engineering-grade: typography, color, spacing, sophistication, warmth, anti-references. Cut everything else.
- **Don't list every file.** Codex reads the repo from cwd. List 3-6 priority files (most important page, layout, token files) and let it discover the rest.
- **Don't pre-pick fonts.** Naming "we want EB Garamond" cuts off the contrast-math + license-check value. Describe the *category* (reading serif with Garamond/Caslon/Lyon family lineage) and let Codex pin the exact package.
- **Don't ask for one big proposal.** The Cornerstone/Important/Polish tiering is the whole point: keeps the implementation cost realistic, lets you ship the 1-3 highest-leverage changes first.
- **Don't repeat the envelope.** The wrapper handles "read-only", "no patches", "WCAG AA", "named-font / pinned-hex". Don't restate; that's noise.

## Output destination

Briefs go in `<repo>/.claude/scratch/<surface>-design-brief.md`: a durable path so the brief survives session end and can be re-dispatched if the result is mis-shaped. Never `/tmp` (re-dispatch needs the same brief intact).
