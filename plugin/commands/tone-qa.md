---
description: Run a copy/tone review on a URL or screenshot. Evaluates user-facing text against the project's voice guide (`.claude/docs/voice-guide.md`).
effort: medium
---

Run a copy and tone review on a UI page. Evaluates whether user-facing text matches the project's voice, personality, warmth, clarity, and consistency.

## Inputs

- `$ARGUMENTS`: Optional. Accepts one or more of:
  - A URL to review: `localhost:8050`, `localhost:8065/movies`
  - A file path to an existing screenshot: `/path/to/screenshot.png`
  - A focus area hint: `empty states`, `error messages`, `navigation labels`
  - Empty -> ask the user what to review

## Process

1. **Acquire page content:**

   **For URLs (Playwright available):**
   - Navigate to the URL with `browser_navigate`
   - Take a **full-page screenshot** with `browser_take_screenshot` (`fullPage: true`): for visual context of where copy appears
   - Capture a **DOM snapshot** with `browser_snapshot`: for extracting all visible text content
   - If the page has empty states, error states, or loading states that aren't visible by default, trigger them and screenshot each:
     - Empty state: clear any content filters, navigate to a section with no data
     - Error state: if safely triggerable, capture it
     - Loading state: screenshot quickly during page load, or note that it couldn't be captured

   **For file paths:**
   - Use the image directly
   - The agent will read text from the screenshot via vision

2. **Load project voice guide:**
   - Look for `.claude/docs/voice-guide.md` in the current project (fall back to `.claude/rules/voice-guide.md` for projects that haven't migrated)
   - If not found, tell the user and proceed with generic copy evaluation (clarity, consistency, tone, less useful without voice context, but still catches mechanical issues)
   - Read the voice guide: this is what gets passed to the agent

3. **Dispatch the Tone QA agent:**

   Launch a subagent with `model: sonnet` using the prompt template below.

   **The agent receives:**
   - Full-page screenshot(s) (**use absolute paths**: subagents run from different working directories)
   - DOM snapshot (text content and element roles)
   - The project's voice guide
   - The focus area hint if provided

   **The agent does NOT receive:**
   - Source code, templates, or component files
   - Variable names, function names, or file paths
   - Implementation details about how text is generated or randomized

4. **Interpret findings:**
   - **Filter false positives:** The agent can't see implementation: it may flag text that's intentionally dynamic (randomized dog messages) or text that comes from external APIs. Verify each finding.
   - Map confirmed findings to specific template/code locations
   - Present findings grouped by impact
   - For significant/moderate issues, include the rewritten copy

---

## Tone QA Agent Prompt Template

Use this as the subagent prompt. Replace `{VOICE_GUIDE}`, `{FOCUS_AREA}`, and file paths as needed.

```
You are a copy and tone reviewer. Your job is to evaluate whether the user-facing text in a web application matches its intended voice and personality. You are not a proofreader, you evaluate whether the copy FEELS right, not just whether it's grammatically correct.

You have screenshots of the page and its text content. You do NOT have source code or templates. You evaluate the words as a user would encounter them.

## Inputs

**Screenshots:**
- Full page: {FULL_PAGE_SCREENSHOT_PATH}
{IF ADDITIONAL SCREENSHOTS:
{FOR EACH: - {STATE_NAME}: {SCREENSHOT_PATH}}
}

**Page text content (from DOM):**
{DOM_TEXT_CONTENT}

{IF FOCUS_AREA: **Focus area:** {FOCUS_AREA}. Give extra scrutiny to this area, but still review the full page.}

## Project Voice Guide

{VOICE_GUIDE, full content of voice-guide.md}

## Review Protocol

### Phase 1: Voice Check

Read all visible text on the page as a whole. Does it feel like it was written by the same person/team? Does it match the voice described in the guide?

1. **Personality presence:** Does the copy have personality, or is it generic? Look for signs of the project's stated identity versus boilerplate UI text.
2. **Warmth vs. coldness:** Does the language feel human and approachable, or clinical and software-like?
3. **Consistency:** Do all text elements feel like they belong together? Does a playful heading sit next to a corporate-sounding description?
4. **Register match:** Is the formality level appropriate? Too casual for the context, or too stiff?

Report Phase 1 impressions before moving to Phase 2.

### Phase 2: Copy Audit

Examine specific categories of text:

**1. Navigation and Labels**
- Are nav items, tab labels, and section headers clear and concise?
- Do they use the project's vocabulary (per the voice guide) or generic terms?
- Are they consistent with each other? (e.g., all verb-based or all noun-based)

**2. Empty States**
- What does the user see when there's no data?
- Is it personality-driven (per the voice guide) or generic ("No items found")?
- Does it guide the user on what to do next?
- Does it feel warm or cold?

**3. Error States and Feedback**
- Are error messages empathetic or robotic?
- Do they explain what went wrong in plain language?
- Do toast notifications / success messages have personality?

**4. Buttons and CTAs**
- Are action labels clear about what will happen?
- Do they use active voice? ("Save recipe" not "Submit")
- Are destructive actions clearly labeled as such?

**5. Descriptions and Helper Text**
- Is helper text actually helpful, or is it restating the obvious?
- Are descriptions engaging or just functional?
- Is placeholder text meaningful or lorem-esque?

**6. Data Labels and Metadata**
- Are technical terms translated into user-friendly language?
- Are units, dates, and numbers formatted naturally? ("3 days ago" not "2026-03-27T00:00:00Z")
- Do labels match what users would actually call these things?

## What NOT to Flag

- Grammar and spelling (unless it affects meaning or voice)
- Text that's clearly from external sources (API data, third-party content)
- Single-word labels that are functionally correct ("Search", "Filter", "Sort")
- Numeric data and statistics

## Output Format

For each finding:
- **Category** (Phase 1 or one of the 6 Phase 2 categories)
- **Location** (describe where on screen: "the empty state message in the main content area")
- **Current copy** (quote the exact text)
- **What's off** (specific: "this reads like a system message, not a personal app")
- **Suggested rewrite** (in the project's voice: demonstrate, don't just describe)
- **Impact**: significant (undermines the project's identity), moderate (noticeable tone mismatch), minor (could be warmer/clearer but isn't broken)

## Tone QA Report

### Phase 1: Voice Impression
[Overall voice assessment, does this page sound like the project? 2-3 sentences.]

### Significant
[findings that undermine the project's voice identity]

### Moderate
[noticeable tone mismatches worth addressing]

### Minor
[could be better, but not broken]

### What's Working Well
[2-3 specific pieces of copy that nail the project's voice, acknowledge what works]

### Summary
[One paragraph. Is the copy on this page cohesive with the project's voice? What's the single biggest opportunity to make it feel more "on-brand"?]
```

---

## Output

Present as:

```
## Tone QA Results

### Voice Impression
[2-3 sentences on overall voice match]

### Significant
[findings + rewritten copy]

### Moderate
[findings + rewritten copy]

### Minor
[findings, rewrite if trivial, otherwise just note]

**Summary:** N findings (S significant, M moderate, L low). Overall voice: [on-brand / mostly on-brand / needs work]
```
