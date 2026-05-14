---
description: Run interaction QA on hover/press/focus states for a URL or mobile bundle ID. Captures per-state screenshots and reviews against the project's interaction philosophy.
effort: high
---

Run an interaction QA review on hover, press, and focus states.

## Arguments

- `$ARGUMENTS`: Optional. Accepts:
  - A URL to test: `localhost:8000/admin`
  - A mobile bundle ID: `com.example.app.dev`
  - A focus area hint: `navigation buttons`
  - Empty -> ask what to review

## Platform Detection

- URL pattern (`localhost`, `http://`, `https://`) -> Web (Playwright)
- Bundle ID pattern (`com.*.*.dev`, `com.*.*`) -> Mobile (mobile-mcp)
- If ambiguous, ask the user

## Process

### 1. Detect Platform

Parse `$ARGUMENTS` to determine web vs mobile:

```javascript
const isWeb = /^(https?:\/\/|localhost)/.test(args);
const isMobile = /^com\.[a-z]+\.[a-z]+/.test(args);
```

### 2. Load Philosophy

Look for `.claude/docs/interaction-qa-philosophy.md` in the current project (fall back to `.claude/rules/interaction-qa-philosophy.md`). If not found, tell the user and proceed with generic evaluation. Read the philosophy file — this gets passed to the QA agent.

### 3. Capture Baseline

**Web (Playwright):**
```javascript
await browser_navigate(url);
await browser_take_screenshot({ fullPage: true });  // saves baseline
const snapshot = await browser_snapshot();  // DOM snapshot for element identification
```

**Mobile (mobile-mcp):**
```
mobile_launch_app(bundleId)
mobile_take_screenshot() -> baseline
mobile_list_elements_on_screen() -> element list
```

### 4. Identify Interactive Elements

**Web:** Query for interactive elements:
```javascript
const elements = await page.$$('button, a, input, select, textarea, [role="button"], [tabindex="0"]');
```

**Mobile:** Filter element list for Pressable, TouchableOpacity, Button types.

### 5. Capture State Screenshots

**Web - Hover (for each element):**
```javascript
await element.hover();
await page.screenshot({ path: `/tmp/interaction-qa/hover-${i}.png`, clip: boundingBox });
await page.mouse.move(0, 0); // reset
```

**Web - Press (for each element):**
```javascript
const box = await element.boundingBox();
await page.mouse.move(box.x + box.width/2, box.y + box.height/2);
await page.mouse.down();
await page.screenshot({ path: `/tmp/interaction-qa/press-${i}.png`, clip: boundingBox });
await page.mouse.up();
```

**Web - Focus (for each element):**
```javascript
await element.focus();
await page.screenshot({ path: `/tmp/interaction-qa/focus-${i}.png`, clip: boundingBox });
await element.blur();
```

**Mobile - Press (for each element):**
```
mobile_long_press_on_screen_at_coordinates(x, y)
mobile_take_screenshot() -> press-{i}
// tap elsewhere to release
mobile_click_on_screen_at_coordinates(0, 0)
```

### 6. Dispatch QA Agent

Launch a subagent with `model: sonnet`, `run_in_background: true`:

```
You are an interaction QA reviewer. Evaluate whether interactive states are visible, consistent, and accessible.

## Screenshots

**Baseline:** /tmp/interaction-qa/baseline.png

**Hover states (web only):**
- Element 1: /tmp/interaction-qa/hover-0.png
- Element 2: /tmp/interaction-qa/hover-1.png
...

**Press states:**
- Element 1: /tmp/interaction-qa/press-0.png
...

**Focus states (web only):**
- Element 1: /tmp/interaction-qa/focus-0.png
...

## Philosophy

{INSERT_PHILOSOPHY_CONTENT_HERE}

<!-- When dispatching, replace the placeholder above with the full text content
     of the project's interaction-qa-philosophy.md that you read in Step 2.
     Do NOT pass a file path - the agent cannot read files, only the content you provide. -->

## Review Protocol

For each element, compare state screenshots against baseline:

1. **Hover**: Is there a visible change? Is contrast sufficient? Does it blend into neighbors?
2. **Press**: Is there immediate feedback? Does it feel "pushed"?
3. **Focus**: Is there a visible ring? Does it meet WCAG 2.4.7?

## Output Format

### Interaction QA Report

**Platform:** web / mobile

**Issues:**

1. **[Element] - [State] - [Severity]**
   Issue: [what's wrong]
   Location: [where on screen]

### Summary

[Count by severity. Overall interaction quality assessment.]
```

### 7. Create Gate Marker

After dispatching, create the marker file. The `SESSION_ID` is available as an environment variable in Claude Code sessions (same as used by other stop hooks like visual-qa-stop-gate.sh):

```bash
mkdir -p /tmp/cc-gates/${SESSION_ID}
touch /tmp/cc-gates/${SESSION_ID}/interaction_qa_dispatched
```

Note: If `SESSION_ID` is not set, the gate marker is skipped (stop hook checks for the file's existence, so no marker = gate fires).

### 8. Present Results

When the agent returns:
- **High severity** -> fix immediately
- **Medium severity** -> fix if straightforward
- **Low severity** -> note for user

## Red Flags

| Excuse | Reality |
|--------|---------|
| "The elements work when I click them" | Working != visible feedback. Interaction QA checks perception, not function. |
| "I'll skip hover, this is mostly mobile" | If the URL is web, hover matters. Mobile users aren't your only users. |
| "Focus states are fine, I tested tab" | Did you screenshot them? Tabbing doesn't prove visibility. |
| "The baseline looks good" | Baseline is resting state. Interaction QA is about state *changes*. |
