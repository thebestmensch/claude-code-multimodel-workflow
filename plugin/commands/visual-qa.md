---
description: Run visual QA on a URL or screenshot. Two modes — Bug QA (default; broken rendering, anti-patterns) and Polish QA (subjective design quality).
effort: medium
---

Run a visual QA review on a UI screenshot. Two modes:

- **Bug QA** (default): Catch broken rendering, anti-pattern violations, pixel-level defects
- **Polish QA** (`polish`): Evaluate design quality — hierarchy, spacing, color harmony, component distinction

## Inputs

- `$ARGUMENTS`: Optional. Accepts one or more of:
  - `polish` — run Polish QA instead of Bug QA
  - A URL to screenshot: `localhost:8050`, `localhost:8010/books`
  - A file path to an existing screenshot: `/path/to/screenshot.png`
  - A focus area hint: `chart widget`, `checkout screen`
  - A reference image (prefix with `ref:`): `ref:/path/to/figma-mock.png`
  - Empty → ask the user what to review

## Process

0. **Spec compliance check (before screenshots):**

   Before taking screenshots, check if this visual QA is for a feature with a plan/spec:
   - Look for a plan file in `docs/superpowers/plans/` or spec in `docs/superpowers/specs/` that matches the feature being QA'd
   - If found, extract **visual expectations** — what elements should be visible, what text should appear, what indicators/icons should show
   - These become your **spec compliance checklist** for Phase 0 of the review

   **Example extraction from a plan:**
   > "Add checklist-item class with checkbox indicator (☐) on the left of each item"
   
   Becomes spec compliance check:
   > "Each list item should show a ☐ checkbox indicator on the left"

   Pass this checklist to the visual QA agent alongside the screenshots. The agent will verify each item is actually visible — not just that "something works" but that "what the spec says should appear does appear."

1. **Acquire screenshots (two-tier protocol):**

   Full-page screenshots miss pixel-level widget issues. Widget-only screenshots miss composition. You need both.

   **Output directory:** ALL screenshots (and any other scratch artifacts this skill produces) must be written to `.qa/` in the project root, never to the project root itself. Create it first with `mkdir -p .qa` if it doesn't exist. This keeps workspace roots clean — one `rm -rf .qa/` cleans every artifact from a QA session. Workspaces gitignore `.qa/`, so nothing leaks into commits.

   **For URLs (Playwright available):**

   **Tier 1 — Full page:**
   - Navigate to the URL with `browser_navigate`
   - **Scroll-then-settle before capture** — many apps use `loading="lazy"` on below-fold images. Full-page screenshots taken without scrolling catch blank placeholders for those images, producing false "missing image" findings. Use `browser_run_code` to scroll to bottom, wait 500ms for lazy-load network, scroll back to top:
     ```js
     async (page) => {
       await page.evaluate(async () => {
         await new Promise(resolve => {
           let y = 0;
           const timer = setInterval(() => {
             window.scrollTo(0, y);
             y += 500;
             if (y > document.body.scrollHeight) {
               clearInterval(timer);
               window.scrollTo(0, 0);
               setTimeout(resolve, 500);
             }
           }, 100);
         });
       });
     }
     ```
   - Take a **full-page screenshot** with `browser_take_screenshot` (`fullPage: true`) — this is for Phase 1 (composition review)
   - Capture a **DOM snapshot** with `browser_snapshot` — use this to identify significant widgets/sections
   - **Fallback** — if below-fold images still appear blank after scroll-settle, force eager loading before recapturing: `document.querySelectorAll('img[loading="lazy"]').forEach(i => i.loading = 'eager')`, wait for network idle, then screenshot.

   **Tier 2 — Per-widget at 2x CSS zoom:**
   - From the DOM snapshot, identify every distinct widget, card, or section
   - For each widget, use `browser_run_code` to CSS-zoom the element and screenshot it at 2x resolution. This is critical — 1x element screenshots miss 1-5px boundary issues. The technique:
     ```js
     async (page) => {
       // CSS-zoom the widget to 2x for higher pixel detail
       await page.evaluate((selector) => {
         const el = document.querySelector(selector);
         if (el) { el.style.transform = 'scale(2)'; el.style.transformOrigin = 'top left'; }
       }, '.widget-class');
       await page.waitForTimeout(200);
       const el = page.locator('.widget-class');
       const box = await el.boundingBox();
       await page.screenshot({
         path: '.qa/widget-name-2x.png', type: 'png',
         clip: { x: box.x, y: box.y, width: box.width * 2, height: box.height * 2 }
       });
       // Reset
       await page.evaluate((selector) => {
         const el = document.querySelector(selector);
         if (el) { el.style.transform = ''; el.style.transformOrigin = ''; }
       }, '.widget-class');
     }
     ```
   - For interactive widgets, also hover and re-screenshot at 2x
   - For widgets with input fields or complex boundaries, optionally take a 3x zoom of just the input/boundary area
   - Save each with a descriptive filename under `.qa/`: `.qa/widget-<name>-2x.png` (e.g. `.qa/widget-chart-2x.png`).

   **Why 2x CSS zoom:** Testing showed that 1x widget screenshots caught 2 of 5 known issues. 2x CSS-zoomed screenshots caught 4-5 of 5. The 2x zoom renders 1px CSS artifacts as 2px features in the PNG, making hairline gaps, clipped borders, and color mismatches visible to the vision model.

   **Both tiers go to ONE agent call.** The agent does Phase 1 on the full-page shot and Phase 2 on each widget screenshot. This is critical — full-page-only reviews miss pixel-level issues; widget-only reviews miss composition.

   **For file paths:**
   - Use the image directly (the agent will Read it)
   - Per-widget screenshots are not possible — note this limitation in the dispatch. The agent will do its best but pixel-level issues may be missed.

   **For React Native (no Playwright):**
   - Ask the user for a simulator screenshot
   - Per-widget screenshots require the user to crop manually, or skip Tier 2

   If a `ref:` path is provided, pass it as the reference image for comparison.

2. **Load project design philosophy:**
   - Look for `.claude/docs/visual-qa-philosophy.md` in the current project (fall back to `.claude/rules/visual-qa-philosophy.md` for projects that haven't migrated)
   - If not found, tell the user and proceed with generic evaluation (less useful but still catches mechanical issues)
   - Read the philosophy file — this is what gets passed to the QA agent
   - **Also read the project's design system docs for YOUR use** when interpreting findings later — but do NOT pass implementation details (token values, file paths, class names) to the QA agent

3. **Dispatch the Visual QA agent:**

   Launch a subagent with `model: sonnet` using the full prompt template below.

   **The agent receives:**
   - **Spec compliance checklist** (if a plan/spec exists for this feature) — extracted visual expectations to verify
   - **Tier 1:** Full-page screenshot (for composition review)
   - **Tier 2:** Per-widget 2x CSS-zoomed screenshots (for detail/boundary review)
   - **Hover states:** 2x screenshots of interactive widgets with primary element hovered
   - The project's visual QA philosophy (the full content of `visual-qa-philosophy.md`)
   - An optional reference image for comparison
   - The focus area hint if provided

   **The agent does NOT receive:**
   - Source code, CSS, HTML, templates, or component files
   - File paths to source code or directory structure
   - Token variable names, hex values, or spacing values
   - Class names, component names, or implementation details
   - Any context about HOW things are built — only what they should LOOK like

4. **Interpret findings:**
   - **Filter false positives first:** For each finding, verify against actual code before presenting. The QA agent has ~30% false positive rate — it can't see implementation, so it flags things that are actually correct (e.g., "link has no affordance" when the link does use accent color). Read the relevant CSS/template to confirm or dismiss each finding.
   - Map confirmed findings to specific code locations using YOUR knowledge of the codebase
   - Present findings to the user grouped by severity
   - For high/medium issues, include your proposed code fix
   - If the agent found nothing, say so in one line

5. **Learn from misses:**
   - If the user later identifies issues the agent missed, update the project's `visual-qa-philosophy.md` (under `.claude/docs/` or `.claude/rules/`, wherever the project keeps it) — add the missed pattern to the "Known Anti-Patterns" section so it's caught next time

## Red Flags

If you catch yourself thinking any of these, STOP — you're about to skip what catches the bugs.

| Excuse | Reality |
|--------|---------|
| "The behavior works, so it's fine" | Behavior ≠ appearance. Clicking may work but the checkbox icon might not render. Always verify spec says X appears → X actually appears in screenshot. |
| "The full-page screenshot looks fine" | Full-page screenshots miss ~40% of issues. The 2x tier exists because 1px artifacts are invisible at page scale. |
| "I'll skip Tier 2, the page isn't complex" | Simple pages still have widget boundaries, input borders, and corner radii. Tier 2 catches these. |
| "The agent said no issues, so we're good" | The agent has a ~30% false positive rate — and an unknown false negative rate. Filter findings against code, don't just accept the verdict. |
| "I know this code, no need for visual QA" | You wrote it. That's exactly why you can't see the bugs. Fresh eyes — even automated — catch what familiarity hides. |
| "This is a backend change, visual QA doesn't apply" | If the staged files include CSS, templates, or JSX — visual QA applies, regardless of what you think the change is "really about." |
| "There's no plan/spec, so skip Phase 0" | If YOU know what should appear (from the task description), extract those expectations yourself. Phase 0 catches "invisible but important" elements. |

---

## Visual QA Agent Prompt Template

Use this as the subagent prompt. Replace `{PHILOSOPHY}`, `{FOCUS_AREA}`, and file paths as needed.

```
You are a visual QA reviewer. Your job is to find problems in UI screenshots. You are adversarial — you assume problems exist and look for them. If you truly find nothing, say so in one line. Do not compliment the design. Do not soften your findings.

You have NO access to source code. You can only see what's rendered. You cannot and should not rationalize why something looks the way it does — you can only report what you see. You do not know how anything is implemented. You are a fresh pair of eyes.

Read the screenshot file(s). Do NOT read any other files — only the images listed here.

## Screenshots

**Full page (for Phase 1 — composition):**
- {FULL_PAGE_SCREENSHOT_PATH}

**Individual widget screenshots (for Phase 2 — detail pass):**
{FOR EACH WIDGET: - {WIDGET_NAME}: {WIDGET_SCREENSHOT_PATH}}
{IF ANY HOVER SCREENSHOTS:
**Hover-state screenshots (compare against default for contrast):**
{FOR EACH HOVER: - {WIDGET_NAME} (hover): {HOVER_SCREENSHOT_PATH} — compare this against the default widget screenshot above. Does the hover effect have sufficient contrast? Does it blend into adjacent backgrounds?}
}
{IF REFERENCE:
**Reference image:**
- {REFERENCE_PATH} — compare the screenshots against this reference and note deviations.
}

{IF FOCUS_AREA: **Focus area:** {FOCUS_AREA}. Give extra scrutiny to this area, but still review everything.}
{IF ANIMATES: **Animated elements:** {ANIMATION_DESCRIPTION}. Even from a still frame, check whether decorative elements (rings, borders, badges) around animated content appear to be positioned in a way that would track correctly during motion, or whether they look static/disconnected.}

{IF SPEC_CHECKLIST:
## Spec Compliance Checklist

The following visual elements MUST be present according to the feature spec. Verify each one is actually visible in the screenshots:

{SPEC_CHECKLIST}

Phase 0 of your review is to check each item against the screenshots. A missing item is HIGH severity — behavior may work, but if the visual element isn't visible, the feature doesn't match its design.
}

IMPORTANT: You have both full-page and zoomed-in widget screenshots. Use the full page for composition (Phase 1). Use the individual widget screenshots for detail (Phase 2) — these are zoomed in so you can see pixel-level issues like clipped borders, hairline gaps, and subtle color mismatches that are invisible in the full page view.

## Design Philosophy

{PHILOSOPHY — full content of visual-qa-philosophy.md}

## Review Protocol

You MUST follow this three-phase protocol. Do not skip any phase.

### Phase 0 — Spec Compliance (if checklist provided)

{IF SPEC_CHECKLIST:
Before looking for bugs, verify the implementation matches its specification. For each item in the checklist below, confirm it is actually visible in the screenshot:

**Spec Compliance Checklist:**
{SPEC_CHECKLIST}

For each item:
- ✅ **Present** — the element/indicator/text is clearly visible
- ❌ **Missing** — the element should be there but isn't
- ⚠️ **Partial** — something is there but doesn't match the spec (wrong icon, wrong position, etc.)

Report ALL spec compliance findings before moving to Phase 1. A "missing" finding here is HIGH severity — the feature doesn't match its design.
}

### Phase 1 — The Squint Test (Composition)

Before examining any individual element, evaluate the screenshot as a whole composition. Imagine squinting at it — defocusing so you can't read text, only see shapes, colors, and whitespace. Answer:

1. **Visual balance:** Is the visual weight distributed intentionally? Does one area feel heavier or emptier than it should?
2. **Breathing room:** Is the overall density comfortable? Are elements packed too tight, or is there too much empty space?
3. **Color harmony:** Do the colors across the full viewport feel like they belong together? Any element that "pops out" as wrong?
4. **Flow:** Where does your eye go first? Second? Is that the right order for this interface?
5. **Cohesion:** Does this look like one intentional design, or like parts were built separately and placed together?

Report any Phase 1 issues before moving to Phase 2. These are often the most important findings because they reflect composition problems that element-level fixes can't solve.

### Phase 2 — The Detail Pass (Elements)

Now examine individual elements and their relationships. For each category, look for the specific failure patterns listed.

**1. Spacing & Proportion**
- Elements cramped against neighbors with no breathing room
- Elements disproportionately sized relative to their container (too wide, too tall, too small)
- Containers sized to arbitrary percentages that don't match their content
- Equal spacing everywhere when grouped/varied rhythm would feel more natural
- Margins/padding inconsistent between siblings (same type of element, different spacing)

**2. Alignment & Relationships**
- Edges that should align but don't (off by a few pixels)
- Elements that are individually centered but don't form a visual group
- Labels/titles too close to or too far from their associated controls
- Icons vertically misaligned with adjacent text (off by 1-2px)
- Elements that "float" — visually disconnected from the layout they belong to

**3. Hover & Interaction States** (if visible in the screenshot)
- Hover/active background color too similar to an adjacent element's resting background
- State change that blends into the surrounding area instead of standing out
- Focus rings invisible against certain backgrounds
- Selected/active state with insufficient contrast against unselected siblings

**4. Overflow & Clipping — BOUNDARY ZOOM**
Mentally "zoom in" on every edge where one container meets another, where an element meets its parent's boundary, or where two backgrounds meet. These are where the hardest-to-catch bugs hide. Specifically look for:
- Borders, shadows, or rounded corners cut off at container edges — especially bottom-left and bottom-right corners where border-radius meets overflow:hidden
- Content overflowing its container (text, images, decorative elements)
- Unintended gaps — small triangles or strips of a different background color visible between elements that should meet seamlessly. Check every corner.
- Border-radius mismatch between nested elements (outer should equal inner + padding)
- Scrollable areas clipping children's shadows or focus rings
- Input fields whose borders are partially hidden at one or more edges

**5. Color & Contrast**
- Adjacent colors that don't maintain readable contrast
- Backgrounds that bleed through or show unintended transparency
- Shadows that feel too dark, too cool, or inconsistent with others on the page
- Elements using colors that feel "off" from the design language (too cold, too stark, too muted)

**6. Visual Hierarchy**
- Unclear what's primary vs secondary — competing visual weights
- Interactive elements that don't look clickable/tappable
- Section boundaries that are ambiguous — unclear where one group ends and another begins
- Decorative elements (borders, rings, badges) that overpower the content they support

**7. Polish & Pixel Details**
- Stray borders, hairline gaps, or mismatched border radii within a visual group
- Images that don't fit their containers (distorted, awkwardly cropped, wrong aspect ratio)
- Decorative elements (circles, outlines, badges) that don't track with the content they decorate
- Input fields that look different from each other on the same page
- Any element that looks "default" or unstyled compared to its polished neighbors

**8. Consistency**
- Elements of the same type styled differently without apparent reason
- Spacing patterns that change without apparent reason
- Font sizes or weights that seem inconsistent within the same visual context
- Interactive patterns (buttons, links, toggles) that don't look like they belong to the same family

## Output Format

For each issue, report:
- **Category** (Phase 1 or one of the 8 Phase 2 categories)
- **Location** (describe where — use DOM element names if available)
- **What's wrong** (specific, observable — what you SEE, not what you think is happening in code)
- **Severity**: high (broken/ugly/confusing), medium (noticeable polish issue), low (nitpick)
- **Confidence**: high (clearly wrong), medium (likely wrong but could be intentional), low (might be fine, flagging just in case)

## Visual QA Report

### Phase 1 — Composition
[composition-level findings, or "No composition issues."]

### Phase 2 — Details

1. **[Category] — [Severity] — [Confidence]**
   Location: [where]
   Issue: [what's wrong]

2. ...

### Summary
[Count of issues by severity. One sentence overall impression.]
```

---

## Polish QA Agent Prompt Template

Use this when `$ARGUMENTS` contains `polish`. Replace `{PHILOSOPHY}`, `{FOCUS_AREA}`, and file paths as needed. Launch with `model: sonnet` (or `model: opus` for important screens).

```
You are a design polish reviewer. Your job is to evaluate whether a UI is well-designed — not just functional, but thoughtfully crafted. You are not looking for bugs. You are looking for missed opportunities: places where the design could be more intentional, more harmonious, or more effective.

You have NO access to source code. You can only see what's rendered. You evaluate what a discerning designer would notice, not what a QA tester would flag.

Read the screenshot file(s). Do NOT read any other files — only the images listed here.

## Screenshots

**Full page:**
- {FULL_PAGE_SCREENSHOT_PATH}

{IF WIDGET SCREENSHOTS:
**Individual sections (zoomed):**
{FOR EACH WIDGET: - {WIDGET_NAME}: {WIDGET_SCREENSHOT_PATH}}
}
{IF REFERENCE:
**Reference image:**
- {REFERENCE_PATH} — compare against this reference for design intent.
}

{IF FOCUS_AREA: **Focus area:** {FOCUS_AREA}. Give extra scrutiny to this area, but still review everything.}

## Design Philosophy

{PHILOSOPHY — full content of visual-qa-philosophy.md}

## Evaluation Framework

Evaluate the screen against the Design Polish Checklist in the philosophy file. For each dimension:

### 1. Visual Hierarchy
- Does the most important action or content stand out?
- Are primary CTAs visually heavier than secondary content?
- Do elements that behave differently look different? (e.g., action rows vs. list items)

### 2. Spacing and Density
- Does the screen feel relaxed or cramped?
- Do list items have generous vertical padding?
- Are sections clearly separated with breathing room?

### 3. Color Harmony
- Do all colors on screen feel like they belong to the same palette?
- Are there any vivid or saturated colors that clash with the overall tone?
- Do accent colors punctuate without competing?

### 4. Typography Proportion
- Is the text hierarchy clear? Can you identify heading → subheading → body → caption?
- Are any text elements sized inappropriately for their role? (e.g., page subtitle at footnote size)

### 5. Component Distinction
- Do structurally different elements have distinct visual treatments?
- Can you tell at a glance which elements are interactive vs. informational?
- Do navigation actions look different from content items?

### 6. Graceful Degradation
- Are there any blank/empty circles, rectangles, or spaces that suggest missing content?
- Do placeholder states look intentional or broken?

## Output Format

For each recommendation:
- **Dimension** (which of the 6 above)
- **Location** (describe where on screen)
- **Observation** (what you see — specific, not vague)
- **Recommendation** (what would make it better, with rationale)
- **Impact**: significant (meaningfully improves the experience), moderate (noticeable improvement), minor (nice-to-have)

## Design Polish Report

### Significant
[recommendations that meaningfully improve the user experience]

### Moderate
[noticeable improvements worth considering]

### Minor
[nice-to-have refinements]

### What's Working Well
[2-3 things the design does effectively — the agent should acknowledge strengths, not just critique]

### Summary
[One paragraph overall design impression. Is this screen cohesive? Does it feel intentional? What's the single most impactful change?]
```

---

## Mode 2: Alongside UI Work

When this skill is triggered by the `visual-qa-dispatch` rule (mode 2), the protocol is:
- **Bug QA:** Run in background (`run_in_background: true`). Fix high-severity issues immediately, note medium/low for user.
- **Polish QA:** Run in background at milestones only. Present findings as recommendations — user decides what to act on.
- Maximum 2 Bug QA passes per checkpoint. Polish QA runs once per milestone.
- Do not enter an infinite fix-review loop.

## Output

**Bug QA** — present as:

```
## Bug QA Results

### High
[issues + proposed code fixes]

### Medium
[issues + proposed code fixes]

### Low
[issues — fix if trivial, otherwise just note]

**Summary:** N issues (H high, M medium, L low)
```

**Polish QA** — present as:

```
## Design Polish Recommendations

### Significant
[recommendations with rationale]

### Moderate
[recommendations]

### Minor
[nice-to-haves]

**Overall:** [one-sentence design impression]
```
