# Playground Prompt — Live Website Revision Annotator

Copy everything below the line and paste it into Claude Code.

---

```
/playground Create a "Live Website Revision Annotator" — a visual annotation tool that loads your dev server in an iframe (same-origin), inspects React fiber internals to identify source components and file locations, uses three AI agents (categorizer, code analyst, fix suggester) as client-side heuristic functions, and generates revision prompts with file:line references. Two interaction modes: SELECT (click elements) and DRAW (drag rectangles). No screenshots — this works on the live DOM.

## File Placement

The file MUST be saved as `public/annotator.html` so it is served at `/annotator.html` by Vite's dev server. This is required because the iframe loads `src="/"` (the dev site), and cross-frame DOM access (reading React fibers, querying elements) only works under same-origin policy. Placing it in `public/` ensures the annotator and the iframe target share the same origin.

## Layout

```
┌──────────────────────────────────────────────────────────────┐
│  Website Revision Annotator   [SELECT] [DRAW]  [ /________ ][Go]  3 annotations   [Reload Site] [Screenshot ▾]  │  ← top bar
├────────────┬─────────────────────────────────────────────────┤
│            │                                                 │
│  [Delete]  │         ┌─────────────────────┐                │
│  [Clear]   │         │                     │                │
│            │         │   <iframe src="/">   │                │
│  ┌──────┐  │         │    (live website)    │                │
│  │ #1   │  │         │                     │                │
│  │ card │  │         └─────────────────────┘                │
│  └──────┘  │         <canvas> overlay on top                │
│  ┌──────┐  │         + hover tooltip                        │
│  │ #2   │  │                                                 │
│  │ card │  │                                                 │
│  └──────┘  │                                                 │
│            │                                                 │
│  300px     │              flexible center                    │
├────────────┴───────────────────────────────────── drag ──────┤
│  Generated Revision Prompt                        [Copy]     │  ← bottom panel
│  (220px, resizable 80-500px)                                 │
└──────────────────────────────────────────────────────────────┘
```

- **Top bar**: Title + [SELECT] [DRAW] mode toggle buttons + URL path input with "Go" button (navigate iframe to entered path; Enter key also triggers navigation) + annotation count badge + "Reload Site" button + "Screenshot" split button (green, with dropdown for "Save as PNG" and "Copy to clipboard")
- **Left panel** (300px fixed): toolbar row (Delete Selected, Clear All with confirmation modal) + scrollable annotation cards
- **Center panel** (flexible): `<iframe src="/">` filling the space, with a transparent `<canvas>` overlay positioned absolutely on top, plus a floating hover tooltip
- **Bottom panel** (220px default, resizable via drag handle from 80px to 500px): generated prompt output (monospace, pre-wrap) + Copy button

## Live Site Loading

- The iframe initially loads `src="/"` — the Vite dev server root
- The URL path input in the top bar allows changing the iframe path (sets `iframe.src` to the entered value, e.g. `/projects`)
- Navigating to a new path re-shows the loading spinner and clears hover state (same behavior as Reload)
- Annotations are cleared on page change since element positions won't match the new page
- Show a loading spinner overlay (centered in the iframe container) that hides on the iframe `load` event
- "Reload Site" button resets the iframe src to the current path, re-shows the loading spinner, clears hover state
- There is NO image upload — this tool works on live DOM, not screenshots

## Screenshot Capture

A green split button in the top bar provides screenshot functionality with two options via a dropdown menu:

- **Save as PNG**: Captures the iframe content + annotation overlay, downloads as `annotator-screenshot-YYYY-MM-DDTHH-MM-SS.png`
- **Copy to clipboard**: Captures the same composite image and copies it to the system clipboard using `navigator.clipboard.write()` with `ClipboardItem`. If clipboard write fails (browser restrictions), falls back to opening the image in a new tab.

**How it works:**
- Serializes the iframe's DOM (same-origin access) and its stylesheets into an SVG `<foreignObject>`
- Renders the SVG to an offscreen canvas at the iframe container's dimensions
- Draws the annotation overlay canvas on top to include all rectangles/highlights
- Converts the composited canvas to a PNG blob for save or clipboard
- Button flashes green with feedback text ("Saved!", "Copied!", or "Failed") for 1.5s after action

**Visual:** Green split button (`#238636` background) — main button triggers save, dropdown arrow reveals a menu with both options. Dropdown has dark panel background with hover states matching the app theme.

## React Fiber Inspection

This is the core engine that makes the annotator useful. It extracts React component names and source file locations from any DOM element in the iframe.

**Finding the fiber:**
- Access the iframe's DOM via `siteIframe.contentDocument`
- For any DOM element, find its React fiber: `Object.keys(element).find(k => k.startsWith('__reactFiber$'))`
- Fallback for older React: check for `__reactInternalInstance$` prefix

**Walking the fiber tree:**
- From the fiber node, walk upward via `fiber.return`
- At each fiber, check `fiber.type` — if it's a function or object, read `fiber.type.name` or `fiber.type.displayName`
- Skip anonymous components and names starting with `_`

**Extracting source info:**
- Check `fiber._debugSource` on each fiber node (only available in dev mode with React SWC plugin)
- Read `fiber._debugSource.fileName` and `fiber._debugSource.lineNumber`
- Skip files containing `node_modules` in the path
- Clean the file path: strip everything before `/src/` so you get `src/components/portfolio/HeroCard.tsx`

**Building the component chain:**
- Collect all named components while walking up the fiber tree into an array
- Reverse it to get top-down order: `App > Index > HeroCard`

**Collecting CSS info:**
- Read `element.className` (only if it's a string, not an SVG AnimatedString)
- Read `element.tagName.toLowerCase()`

**Helper function — `getBestComponentInfo(element)`:**
- Try the element itself first, then walk up DOM parents via `element.parentElement`
- Return the first component info that has a `_debugSource` with a file path
- If no component with source is found, return the first named component
- Last resort: return basic info (tag name, CSS classes) from the original element

## Two Interaction Modes

### SELECT Mode (default)

- Overlay canvas has `pointer-events: none` — mouse events pass through to the iframe
- Attach `mousemove`, `click`, `mouseleave` listeners directly to `iframe.contentDocument` (possible because same-origin)
- **On hover (mousemove):**
  - Track `state.hoveredElement` to avoid redundant work
  - Draw a blue dashed outline (`#58a6ff`, 2px, dash pattern [4,3]) on the overlay canvas at the element's bounding rect
  - Fill the rect with `rgba(88,166,255,0.08)` for subtle highlight
  - Show a floating tooltip near the element with: component name (blue, bold), file:line (green), tag name (gray), truncated CSS classes (gray, dot-separated)
  - Keep tooltip within container bounds
- **On click:**
  - `e.preventDefault()` + `e.stopPropagation()` to prevent navigation
  - Call `getBestComponentInfo(element)` to extract fiber data
  - Get element's `getBoundingClientRect()` for position/size
  - Run the **Categorizer Agent** to auto-assign a category
  - Create an annotation object and add it to `state.annotations`
  - Select the new annotation and focus its comment textarea

### DRAW Mode

- Overlay canvas has `pointer-events: auto` and `cursor: crosshair`
- Hide hover tooltip and clear hovered element when entering draw mode
- **Mousedown** on canvas: record `state.drawStart` coordinates, set `state.drawing = true`
- **Mousemove** while drawing: update `state.drawCurrent`, render a dashed rectangle preview on the overlay
- **Mouseup**: finalize the rectangle
  - Ignore if width or height < 10px (accidental click)
  - Query `iframe.contentDocument.querySelectorAll('*')` and check each element's `getBoundingClientRect()` for intersection with the drawn rectangle
  - Deduplicate by component name using a `Map` — only keep one entry per unique component
  - Pick the best component: prefer ones with `_debugSource` file info, then pick the most specific (shortest component chain)
  - Run the **Categorizer Agent** on the best component
  - Create annotation and select it

## AI Agent System

Three agents implemented as **client-side heuristic functions** (no API calls). Each appears as a section in the annotation card.

### Categorizer Agent

Runs **automatically** when an annotation is created. Sets the category dropdown without user intervention.

**Input:** element tag name, CSS classes, component name, component chain

**Logic — rule-based first, then contextual:**

1. Tag-based rules:
   - `h1`-`h6`, `p`, `span`, `label` → Typography
   - `button`, `a`, `input`, `select`, `textarea`, `form` → UX/Interaction
   - `img`, `svg`, `video`, `picture` → Content

2. Contextual CSS class analysis (if no tag match):
   - Classes containing `flex`, `grid`, `col`, `row`, `container`, `wrapper` → Layout
   - Classes containing `gap`, `padding`, `margin`, `space`, `px-`, `py-`, `mx-`, `my-`, `p-`, `m-` → Spacing
   - Classes containing `bg-`, `text-[color]`, `border-[color]`, `shadow`, `opacity`, `gradient` → Color/Style
   - Classes containing `text-[size]`, `font-`, `leading-`, `tracking-`, `uppercase`, `italic` → Typography

3. Default fallback → Layout

**Output:** Sets the category dropdown value automatically

**Visual:** Small "AI" pill badge (accent-colored background, tiny text) next to the auto-selected category in the card header

### Code Analyst Agent

Triggered by an **"Analyze Code" button** in the annotation card.

**Input:** component name, file path, line number, CSS classes, component chain

**Logic:** Builds a summary string describing what the component likely does:
- Start with the component name and its position in the tree (e.g., "top-level" if chain length ≤ 2, "nested" otherwise)
- Include the file path and line number
- Describe layout patterns from CSS classes (e.g., "using flex column layout", "with grid display", "styled as a card")
- Mention key visual traits (e.g., "with rounded corners", "using gradient background")

**Output:** A 1-2 sentence description shown in a collapsible "Code Analysis" section with a gray background. Example: `"HeroCard is a top-level portfolio component at src/components/portfolio/HeroCard.tsx:7 using bento-card layout with flex column."`

**Visual:** Collapsible section with gray background, revealed when the "Analyze Code" button is clicked

### Fix Suggester Agent

Triggered by a **"Suggest Fix" button** — only enabled when the comment textarea has content.

**Input:** component name, file path, CSS classes, user's comment text, desired result text (if provided)

**Logic:** Generates a concrete suggestion string:
- Parse the comment for keywords (e.g., "larger" → suggest increasing text size class, "spacing" → suggest padding/margin changes, "color" → suggest color class changes)
- Reference the specific file and line number
- Suggest specific Tailwind class changes when possible (e.g., "change `text-2xl` to `text-5xl font-bold`")
- If a desired result is provided, incorporate it into the suggestion

**Output:** Shown in a teal-bordered highlighted box below the comment

**Visual:** Collapsible "Suggested Fix" section with teal/accent border, only shown after clicking the button

## Annotation Cards

Each card in the left panel contains (top to bottom):

1. **Header row:** `#N` number (bold, bright) + category color dot (8px circle) + "AI" pill badge (if auto-categorized) + delete `×` button (right-aligned)

2. **Code info block** (monospace font, dark background `var(--bg)`, 1px border, rounded):
   - Component name in blue/accent color, bold: `<ComponentName>`
   - File path in green: `src/path/file.tsx:lineNumber`
   - CSS classes in gray, truncated at 60 characters with `...`
   - Component chain in small gray text: `App > Page > Component`

3. **Category dropdown:** 8 options — Layout, Spacing, Color/Style, Typography, Content, Bug/Broken, UX/Interaction, Accessibility. Changing updates the rectangle color on the overlay instantly.

4. **Priority chips** (3 buttons in a row):
   - Critical (red when active)
   - Important (amber when active) — default
   - Nice to have (gray when active)

5. **Comment textarea** (3 rows): placeholder "Describe what needs to change..."

6. **"Analyze Code" button** → expands a collapsible gray-background section showing the Code Analyst agent's output

7. **"Suggest Fix" button** (disabled until comment is non-empty) → expands a collapsible teal-bordered section showing the Fix Suggester agent's output

8. **"Add desired result..." toggle** → reveals a textarea (2 rows) for describing the desired outcome

Clicking a card selects its annotation and highlights the corresponding rectangle on the overlay. When a new annotation is created, its card appears and the comment textarea auto-focuses.

## Prompt Output

Generated in the bottom panel. Format:

```
**Website Revision Instructions**

I've identified N areas that need changes. Each includes source component and file reference.

**Critical Priority:**

1. **[Category] ComponentName**
   File: `src/path/file.tsx:line`
   CSS: `class1 class2 class3`
   Component path: App > Page > Component
   Change: user's comment text
   Desired: user's desired result text
   Suggested fix: AI-generated fix suggestion

**Important Priority:**

2. **[Category] ComponentName**
   File: `src/path/file.tsx:line`
   ...

**Nice to Have:**

3. ...

Please make these changes. Use the file references to locate exact source code.
```

Rules:
- Group annotations by priority (Critical first, then Important, then Nice to have)
- Within each group, order by annotation number
- Include `[Category]` tag and component name in the title
- Include `File:` with backtick-wrapped path only if file info exists
- Include CSS classes (truncated at 80 chars)
- Include component chain if it has more than one entry
- Include "Suggested fix:" line only if the Fix Suggester agent has been run for that annotation
- Only include annotations that have a non-empty comment
- If no annotations have comments, show placeholder: "Select elements or draw rectangles on your live site, then add comments to generate revision instructions with file:line references."

## State Object

```javascript
const state = {
  mode: 'select',       // 'select' | 'draw'
  annotations: [],       // array of annotation objects (see below)
  selectedId: null,      // currently selected annotation id
  nextId: 1,             // auto-incrementing counter
  drawing: false,        // true while drag-drawing a rectangle
  drawStart: null,       // { x, y } start point of current draw
  drawCurrent: null,     // { x, y } current point during draw
  hoveredElement: null,  // DOM element currently hovered in select mode
  iframeReady: false,    // true after iframe load event fires
  currentPath: '/'       // currently loaded iframe path
};

// Each annotation object:
// {
//   id, x, y, width, height,
//   category,          // one of 8 category strings
//   priority,          // 'Critical' | 'Important' | 'Nice to have'
//   comment,           // user's change description
//   desiredResult,     // optional desired outcome
//   componentName,     // React component name from fiber
//   fileName,          // cleaned source file path (src/...)
//   lineNumber,        // source line number
//   chain,             // component chain array ['App', 'Page', 'Component']
//   cssClasses,        // element's CSS class string
//   tagName,           // element tag name (lowercase)
//   source,            // 'select' | 'draw'
//   analysis,          // Code Analyst agent output (string or null)
//   suggestion         // Fix Suggester agent output (string or null)
// }
```

## Style

Dark theme with CSS custom properties:

```
--bg: #0d1117          (page background)
--panel: #161b22       (panel backgrounds)
--border: #30363d      (borders)
--text: #c9d1d9        (default text)
--text-muted: #8b949e  (secondary text)
--text-bright: #f0f6fc (bright/heading text)
--accent: #58a6ff      (interactive elements, links, hover outlines)
--card-bg: #1c2128     (card backgrounds)
--hover: #21262d       (hover states)
```

Category colors (used for rectangle borders, card dots, and color-coding):
- Layout: `#3b82f6` (blue)
- Spacing: `#8b5cf6` (purple)
- Color/Style: `#f97316` (orange)
- Typography: `#14b8a6` (teal)
- Content: `#22c55e` (green)
- Bug/Broken: `#ef4444` (red)
- UX/Interaction: `#ec4899` (pink)
- Accessibility: `#f59e0b` (amber)

Priority colors: Critical `#ef4444`, Important `#f59e0b`, Nice to have `#6b7280`

Additional style details:
- Code info blocks: monospace font (`SF Mono`, `Cascadia Code`, `Fira Code`), darker background than cards
- AI badges: small pill shape, accent background, tiny "AI" text in dark color
- Suggested fix section: teal/accent-colored left border or outline
- Code analysis section: gray background, slightly recessed
- Rounded corners on cards (8px), buttons (5-6px)
- Smooth transitions on hover (0.15s)
- Canvas cursor: default in select mode (pointer-events: none), crosshair in draw mode
- Selected rectangle: dashed border animation (dash pattern [8,4])
- Scrollbar styling: thin (6px), matching border color
- Confirm modal for "Clear All": dark overlay with centered box

## Key Implementation Notes

- File MUST go in `public/` folder for same-origin iframe access — this is critical
- Use `ResizeObserver` on the iframe container to keep the canvas overlay sized correctly
- Resizable bottom panel: drag handle element between center and bottom panels, mousedown/mousemove/mouseup on document, clamp height 80-500px
- **No external dependencies** — everything is inline HTML/CSS/JS in a single file
- Works specifically with React + Vite + SWC plugin (`@vitejs/plugin-react-swc`) in dev mode, which provides `_debugSource` on fiber nodes
- All AI agents are pure JavaScript heuristic functions — no fetch calls, no API keys
- Rectangle coordinates: SELECT mode stores positions relative to iframe content viewport, DRAW mode stores positions relative to the overlay canvas. Account for this offset (`iframeRect - containerRect`) when rendering.
- The overlay canvas must match the iframe container dimensions (not the iframe content dimensions)
- Use `capture: true` on iframe document event listeners to intercept events before the app handles them
```
