# Visual QA During UI Work

When implementing UI changes (CSS, HTML templates, JSX/TSX, React Native styles), run a visual QA review at natural checkpoints, after meaningful visual changes are believed complete, not after every edit.

**Capture limitation up-front.** If the UI is not browser- or simulator-capturable (terminal TUIs, tmux status lines, SwiftUI inspector-only views), state this *before* implementation and agree a capture protocol with the user.

## Agents

Four reviewers, all `sonnet` (Polish QA optionally `opus`) in background:
- **Bug QA** (`/visual-qa`): "is this broken?" Anti-patterns + design rules. Objective.
- **Polish QA** (`/visual-qa polish`): "is this good?" Design Polish Checklist. Subjective.
- **Accessibility QA** (`/accessibility-qa`): "can everyone use this?" WCAG 2.1 AA + ARIA. Objective.
- **Tone QA** (`/tone-qa`): "does this sound like us?" Project voice guide. Subjective.

The skills own evaluation criteria and the philosophy/voice-guide loading.

**Design-stage sibling:** `codex-design-dispatch.md` covers the *pre-implementation* design pass (Codex `task` mode with a thoughtful-designer envelope): named fonts, pinned hex, verified WCAG contrast on the proposal *before* code is written. Visual QA in this file covers *post-implementation* review on rendered pixels. Both fire across one ticket's lifecycle on high-stakes design work.

## When to trigger

**Bug QA, every visual checkpoint:**
- After a round of visual/styling changes render
- After fixing issues from a prior QA pass

**Polish / Accessibility / Tone, milestones only:**
- Before declaring a UI task or full screen done
- When the user asks for a review
- During systematic screen-by-screen review
- NOT after small edits

Pick which milestone reviewers fire by what changed:
- **Accessibility:** interactive elements, forms, navigation, dynamic content
- **Tone:** user-facing text, empty states, error messages, labels

## Dispatch protocol

1. Capture screenshots (the skill handles two-tier full-page + 2x widget zoom).
2. Announce dispatches in one line: "Dispatching Bug QA on the gift detail screen" (and at milestones, list every reviewer firing).
3. Don't make more visual changes while waiting; work on non-visual aspects.
4. Cap at **2 Bug QA passes per checkpoint**. After 2, present remaining findings and move on. No infinite-correction loops.

## How to use results

- **Bug QA / Accessibility QA:** high → fix; medium → fix if straightforward; low → note for user.
- **Polish QA / Tone QA:** present as **recommendations**, grouped by impact; user decides what to act on.

Skills own the full review protocol, info firewall (agents see screenshots + philosophy only, never source), and "learn from misses" follow-up.
