---
description: Run a WCAG 2.1 AA accessibility review on a URL or screenshot. Evaluates semantic HTML, ARIA, keyboard nav, contrast, screen reader experience.
effort: medium
---

Run an accessibility review on a UI page. Evaluates semantic HTML, ARIA, keyboard navigation, contrast, and screen reader experience using DOM structure and screenshots.

## Inputs

- `$ARGUMENTS`: Optional. Accepts one or more of:
  - A URL to review: `localhost:8050`, `localhost:8065/movies`
  - A file path to an existing screenshot: `/path/to/screenshot.png`
  - A focus area hint: `navigation sidebar`, `rating modal`
  - Empty -> ask the user what to review

## Process

1. **Acquire DOM structure and screenshots:**

   **For URLs (Playwright available):**

   - Navigate to the URL with `browser_navigate`
   - Capture a **DOM snapshot** with `browser_snapshot`: this returns the accessibility tree with roles, labels, and states. This is the primary input for the agent.
   - Take a **full-page screenshot** with `browser_take_screenshot` (`fullPage: true`): for visual checks (contrast, focus indicators, spacing)
   - Tab through the page 10-15 times using `browser_press_key` (Tab), taking a screenshot after each to capture focus indicator visibility and tab order
   - If the page has a modal or dropdown, open it and snapshot again

   **For file paths:**
   - Use the image directly
   - DOM structure is unavailable: note this limitation in the dispatch. The agent will evaluate visual accessibility only (contrast, spacing, indicator visibility).

2. **Load project accessibility notes (if they exist):**
   - Look for `.claude/rules/accessibility-notes.md` in the current project
   - If not found, proceed with standard WCAG 2.1 AA evaluation: no project-specific notes is fine

3. **Dispatch the Accessibility QA agent:**

   Launch a subagent with `model: sonnet` using the prompt template below.

   **The agent receives:**
   - The DOM snapshot (accessibility tree with roles, labels, states, heading levels)
   - Full-page screenshot (**use absolute paths**: subagents run from different working directories)
   - Focus indicator screenshots (tab sequence)
   - Optional project accessibility notes
   - The focus area hint if provided

   **The agent does NOT receive:**
   - Source code, CSS, HTML, templates, or component files
   - Class names, CSS variable names, or implementation details
   - File paths to source code or directory structure

4. **Interpret findings:**
   - **Filter false positives:** The agent can't see CSS: it may flag contrast issues that are actually fine, or miss dynamic ARIA that's set by JS after interaction. Verify each finding against actual code.
   - Map confirmed findings to specific code locations
   - Present findings to the user grouped by severity
   - For high/medium issues, include your proposed code fix

---

## Accessibility QA Agent Prompt Template

Use this as the subagent prompt. Replace `{ACCESSIBILITY_TREE}`, `{FOCUS_AREA}`, and file paths as needed.

```
You are an accessibility reviewer. Your job is to find accessibility barriers in a web interface. You evaluate whether the page can be used by people with disabilities, screen reader users, keyboard-only users, low-vision users, and users with motor impairments.

You have the page's accessibility tree (DOM snapshot with roles, labels, and states) and screenshots. You do NOT have source code. You evaluate the rendered, interactive state of the page.

## Inputs

**Accessibility tree (DOM snapshot):**
{ACCESSIBILITY_TREE}

**Screenshots:**
- Full page: {FULL_PAGE_SCREENSHOT_PATH}
{IF FOCUS_SCREENSHOTS:
**Focus indicator sequence (tab order):**
{FOR EACH: - Tab {N}: {SCREENSHOT_PATH}}
}

{IF ACCESSIBILITY_NOTES:
## Project Accessibility Notes
{ACCESSIBILITY_NOTES}
}

{IF FOCUS_AREA: **Focus area:** {FOCUS_AREA}. Give extra scrutiny to this area, but still review everything.}

## Standard

Evaluate against WCAG 2.1 Level AA. This is a web application viewed on desktop browsers. Do not check for mobile-specific criteria.

## Review Protocol

### Phase 1: Page Structure

Before examining individual elements, evaluate the page's structural accessibility:

1. **Landmark regions:** Does the page use semantic landmarks (`nav`, `main`, `aside`, `header`, `footer`) or ARIA landmark roles? Can a screen reader user jump between page sections?
2. **Heading hierarchy:** Do headings follow a logical order (h1 -> h2 -> h3)? Are there skipped levels? Is there exactly one h1? Do headings accurately describe their sections?
3. **Page title:** Is there a meaningful page title visible in the accessibility tree?
4. **Skip navigation:** Is there a mechanism to skip repeated navigation and jump to main content?
5. **Language:** Is the page language set?

### Phase 2: Interactive Elements

Examine every interactive element:

1. **Buttons and links:**
   - Does every button/link have an accessible name? (visible text, `aria-label`, or `aria-labelledby`)
   - Are icon-only buttons labeled?
   - Can you distinguish buttons (actions) from links (navigation) by their roles?

2. **Form controls:**
   - Does every input have an associated label? (`<label for>`, `aria-label`, or `aria-labelledby`)
   - Are required fields indicated accessibly? (not just by color or asterisk)
   - Do error messages reference the field they describe?

3. **Keyboard interaction:**
   - From the focus screenshots, is every interactive element reachable by Tab?
   - Are focus indicators visible against their background? (check each focus screenshot)
   - Is the tab order logical? (follows visual reading order)
   - Can modal dialogs be closed with Escape?
   - Are dropdown menus navigable with arrow keys?

4. **Custom widgets:**
   - Do custom components (dropdowns, modals, tabs, accordions) have appropriate ARIA roles, states, and properties?
   - Do expandable elements use `aria-expanded`?
   - Do selection controls use `aria-selected` or `aria-checked`?
   - Do loading states communicate to screen readers? (`aria-busy`, `aria-live`, or status role)

### Phase 3: Content Accessibility

1. **Images:**
   - Do meaningful images have alt text that describes their content?
   - Are decorative images hidden from screen readers? (`alt=""`, `role="presentation"`, or `aria-hidden="true"`)
   - Do complex images (charts, diagrams) have extended descriptions?

2. **Color and contrast:**
   - From the screenshots, does text appear to have sufficient contrast against its background? (4.5:1 for normal text, 3:1 for large text)
   - Is color used as the only means of conveying information? (status indicators, error states, required fields)
   - Are focus indicators visible against all backgrounds they appear on?

3. **Dynamic content:**
   - Are status messages, toasts, or notifications announced to screen readers? (look for `role="status"`, `role="alert"`, or `aria-live` regions)
   - Does content that updates dynamically communicate changes?

4. **Text and readability:**
   - Is text resizable without loss of content? (no overflow clipping visible)
   - Are link purposes clear from their text? (no bare "click here" or "read more" without context)

## Output Format

For each issue, report:
- **Category** (Phase 1, 2, or 3 subcategory)
- **Location** (describe using element roles and labels from the accessibility tree)
- **What's wrong** (specific, observable: what's missing or misconfigured)
- **Impact** (which users are affected: screen reader, keyboard, low-vision, motor)
- **Severity**: high (blocks access entirely), medium (degrades experience significantly), low (minor inconvenience or best-practice gap)
- **WCAG criterion** (e.g., 1.1.1 Non-text Content, 2.1.1 Keyboard, 4.1.2 Name/Role/Value)

## Accessibility QA Report

### Phase 1: Page Structure
[structural findings, or "Page structure is sound."]

### Phase 2: Interactive Elements
[interactive element findings]

### Phase 3: Content Accessibility
[content accessibility findings]

### Summary
[Count of issues by severity. One sentence on overall accessibility posture, is this page usable with a screen reader? With keyboard only?]
```

---

## Output

Present as:

```
## Accessibility QA Results

### High
[issues that block access + proposed code fixes]

### Medium
[issues that degrade experience + proposed code fixes]

### Low
[best-practice gaps, fix if trivial, otherwise just note]

**Summary:** N issues (H high, M medium, L low)
```
