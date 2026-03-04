# Mobile Navigation, CSS & PWA Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement all 10 fixes from the code review in `docs/digilab-code-review.md` — covering iOS form zoom, responsive layouts, safe area insets, dark mode tab bar, PWA meta tags, and CSS cleanup.

**Architecture:** All changes are CSS/HTML/R-template edits to existing files. No new modules or server logic. The app runs both standalone at `app.digilab.cards` and inside an iframe in `digilab-web` — PWA/viewport fixes only take effect in standalone mode but are harmless in iframe context.

**Tech Stack:** R Shiny (bslib), CSS, JavaScript, PWA manifest

**Source:** All fixes originate from `docs/digilab-code-review.md` (code review by Claude Opus 4.6, verified against current main).

---

### Task 1: iOS Form Zoom Fix (Priority 1)

**Files:**
- Modify: `www/custom.css` — add rule in the mobile UI section (~line 4205 area, after table font rules)

**Step 1: Add 16px font-size rule for mobile inputs**

In `www/custom.css`, find the mobile tables section ending around line 4213. After the `.rt-th` rule block, add:

```css
  /* Prevent iOS Safari auto-zoom on input focus (triggered below 16px) */
  .form-control,
  .form-select,
  select,
  .selectize-input,
  .selectize-input input {
    font-size: 16px !important;
  }
```

This must be inside the existing `@media (max-width: 768px)` block that starts at line 4170.

**Step 2: Verify syntax**

Run: `"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "cat('CSS saved, check manually')"` (CSS has no R syntax check — visual verification needed)

**Step 3: Commit**

```bash
git add www/custom.css
git commit -m "fix: prevent iOS Safari auto-zoom on mobile form inputs"
```

---

### Task 2: Upload Results Responsive Columns (Priority 2)

**Files:**
- Modify: `views/submit-ui.R:67` — change `c(6, 6)` to breakpoints
- Modify: `views/submit-ui.R:78` — change `c(4, 4, 2, 2)` to breakpoints

**Step 1: Fix the store/date row (line 67)**

Change:
```r
col_widths = c(6, 6),
```
To:
```r
col_widths = breakpoints(sm = c(12, 12), md = c(6, 6)),
```

**Step 2: Fix the event details row (line 78)**

Change:
```r
col_widths = c(4, 4, 2, 2),
```
To:
```r
col_widths = breakpoints(sm = c(6, 6, 6, 6), md = c(4, 4, 2, 2)),
```

**Step 3: Check for other fixed col_widths in the same file**

Scan `submit-ui.R` for any other `col_widths = c(...)` without `breakpoints()`. Fix any found.

**Step 4: Verify R syntax**

Run: `"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "parse('views/submit-ui.R')"`

**Step 5: Commit**

```bash
git add views/submit-ui.R
git commit -m "fix: make Upload Results form responsive on mobile"
```

---

### Task 3: Safe Area Insets + viewport-fit (Priority 3)

**Files:**
- Modify: `app.R:431-432` — add viewport-fit meta tag and apple-mobile-web-app-title
- Modify: `www/custom.css:6525-6534` — add safe-area-inset-bottom to tab bar
- Modify: `www/custom.css:4144` — update content padding to include safe area

**Step 1: Add viewport-fit=cover meta tag in app.R**

Find the existing meta tags around line 431. Add a viewport meta tag BEFORE the `mobile-web-app-capable` tag:

```r
tags$meta(name = "viewport",
          content = "width=device-width, initial-scale=1, viewport-fit=cover"),
```

Note: Shiny/bslib may already inject a viewport tag. This will override it. Place it early in the head tags.

**Step 2: Add safe-area-inset-bottom to mobile tab bar CSS**

In `www/custom.css`, modify the `.mobile-tab-bar` rule at line 6534. Change:
```css
    padding: 0.35rem 0;
```
To:
```css
    padding: 0.35rem 0;
    padding-bottom: calc(0.35rem + env(safe-area-inset-bottom));
```

**Step 3: Update content padding-bottom to include safe area**

At line 4144, change:
```css
    padding-bottom: 70px !important;
```
To:
```css
    padding-bottom: calc(70px + env(safe-area-inset-bottom)) !important;
```

**Step 4: Update footer padding to include safe area**

At line 6579, change:
```css
    padding-bottom: 70px;
```
To:
```css
    padding-bottom: calc(70px + env(safe-area-inset-bottom));
```

**Step 5: Verify R syntax**

Run: `"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "parse('app.R')"`

**Step 6: Commit**

```bash
git add app.R www/custom.css
git commit -m "fix: add safe area insets for iPhone X+ PWA mode"
```

---

### Task 4: Dark Mode Tab Bar (Priority 4)

**Files:**
- Modify: `www/custom.css` — add dark theme variant after the tab bar section (~line 6581)

**Step 1: Add dark mode tab bar styles**

After the closing `}` of the mobile tab bar media query (line 6581), add:

```css
/* Dark mode mobile tab bar */
[data-bs-theme="dark"] .mobile-tab-bar {
  background: linear-gradient(135deg, #1A202C 0%, #2D3748 100%);
  border-top-color: rgba(255, 255, 255, 0.1);
}
```

Note: This rule is NOT inside a media query — `display: none` on desktop already hides the tab bar, so this dark variant only matters on mobile where it's visible.

**Step 2: Commit**

```bash
git add www/custom.css
git commit -m "fix: add dark mode variant for mobile tab bar"
```

---

### Task 5: Apple Mobile Web App Title (Priority 5)

**Files:**
- Modify: `app.R:432` — add apple-mobile-web-app-title meta tag

**Step 1: Add meta tag**

After the `apple-mobile-web-app-status-bar-style` line (432), add:

```r
tags$meta(name = "apple-mobile-web-app-title", content = "DigiLab"),
```

**Step 2: Verify R syntax**

Run: `"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "parse('app.R')"`

**Step 3: Commit**

```bash
git add app.R
git commit -m "fix: add apple-mobile-web-app-title for iOS home screen"
```

---

### Task 6: Store Form Padding Fix (Priority 6)

**Files:**
- Modify: `views/admin-stores-ui.R:134-135` — replace hardcoded padding with flexbox

**Step 1: Replace the inline style**

Change:
```r
div(
  style = "padding-top: 32px;",
  actionButton("add_schedule", "Add", class = "btn-outline-primary btn-sm")
)
```
To:
```r
div(
  class = "d-flex align-items-end h-100",
  actionButton("add_schedule", "Add", class = "btn-outline-primary btn-sm")
)
```

**Step 2: Verify R syntax**

Run: `"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "parse('views/admin-stores-ui.R')"`

**Step 3: Commit**

```bash
git add views/admin-stores-ui.R
git commit -m "fix: use flexbox alignment for store schedule Add button"
```

---

### Task 7: Additional PWA Icon Sizes (Priority 7)

**Files:**
- Modify: `www/manifest.json` — add more icon sizes
- Check: `scripts/generate_pwa_icons.py` — verify it can generate the needed sizes
- Generate: new icon files in `www/icons/`

**Step 1: Check existing icon generation script**

Read `scripts/generate_pwa_icons.py` to understand what sizes it supports and what source image it uses.

**Step 2: Generate additional icon sizes**

Run the icon generation script to create sizes: 48, 72, 96, 128, 144, 152, 384. The exact command depends on what the script supports.

**Step 3: Update manifest.json**

Add entries for the new sizes. Also add `categories` and `orientation`:

```json
{
  "name": "DigiLab - Digimon TCG Locals Tracker",
  "short_name": "DigiLab",
  "description": "Track player performance, deck meta, and tournament results for your local Digimon TCG community",
  "start_url": "/",
  "display": "standalone",
  "background_color": "#1a1a2e",
  "theme_color": "#1a1a2e",
  "categories": ["games", "entertainment"],
  "orientation": "portrait",
  "icons": [
    { "src": "icons/icon-48.png", "sizes": "48x48", "type": "image/png" },
    { "src": "icons/icon-72.png", "sizes": "72x72", "type": "image/png" },
    { "src": "icons/icon-96.png", "sizes": "96x96", "type": "image/png" },
    { "src": "icons/icon-128.png", "sizes": "128x128", "type": "image/png" },
    { "src": "icons/icon-144.png", "sizes": "144x144", "type": "image/png" },
    { "src": "icons/icon-152.png", "sizes": "152x152", "type": "image/png" },
    { "src": "icons/icon-192.png", "sizes": "192x192", "type": "image/png" },
    { "src": "icons/icon-384.png", "sizes": "384x384", "type": "image/png" },
    { "src": "icons/icon-512.png", "sizes": "512x512", "type": "image/png" },
    { "src": "icons/icon-maskable-192.png", "sizes": "192x192", "type": "image/png", "purpose": "maskable" },
    { "src": "icons/icon-maskable-512.png", "sizes": "512x512", "type": "image/png", "purpose": "maskable" }
  ]
}
```

**Step 4: Commit**

```bash
git add www/manifest.json www/icons/ scripts/generate_pwa_icons.py
git commit -m "feat: add additional PWA icon sizes for broader device support"
```

---

### Task 8: Scrollbar Selector Scope (Priority 9)

**Files:**
- Modify: `www/custom.css:51-58` — change `*` selector to `body`

**Step 1: Scope scrollbar styles to body**

Change lines 51-58 from:
```css
* {
  scrollbar-width: thin;
  scrollbar-color: rgba(0, 200, 255, 0.5) rgba(15, 76, 129, 0.1);
}

[data-bs-theme="dark"] * {
  scrollbar-color: rgba(0, 200, 255, 0.4) rgba(0, 200, 255, 0.05);
```
To:
```css
body {
  scrollbar-width: thin;
  scrollbar-color: rgba(0, 200, 255, 0.5) rgba(15, 76, 129, 0.1);
}

[data-bs-theme="dark"] body {
  scrollbar-color: rgba(0, 200, 255, 0.4) rgba(0, 200, 255, 0.05);
```

Firefox inherits `scrollbar-color` from parents, so `body` covers all scrollable children.

**Step 2: Commit**

```bash
git add www/custom.css
git commit -m "refactor: scope scrollbar styles from * to body selector"
```

---

### Task 9: CSS Media Query Index Comment (Priority 10)

**Files:**
- Modify: `www/custom.css` — add index comment near top of file

**Step 1: Scan for all @media blocks and their line numbers**

Search `www/custom.css` for all `@media` occurrences and note line numbers + purpose.

**Step 2: Add mobile override index comment**

After the file header comment (around line 5), add:

```css
/* MOBILE OVERRIDE INDEX:
 * Line numbers approximate — search for the section header if moved.
 *
 * @319:  Header mobile (max-width: 576px)
 * @638:  Content padding mobile (max-width: 576px)
 * @952+: Dashboard charts mobile (max-width: 768px)
 * @4126: Mobile UI section start (max-width: 768px)
 * @4149: Mobile value boxes
 * @4170: Mobile table column hiding
 * @6523: Mobile bottom tab bar
 *
 * Total @media blocks: ~39
 */
```

Note: Exact line numbers should be verified at implementation time since prior tasks may shift lines.

**Step 3: Commit**

```bash
git add www/custom.css
git commit -m "docs: add mobile override index comment to custom.css"
```

---

### Task 10: Final Verification & Branch Completion

**Step 1: Verify R syntax on all modified R files**

```bash
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "parse('app.R'); parse('views/submit-ui.R'); parse('views/admin-stores-ui.R'); cat('All files parse OK\n')"
```

**Step 2: Verify CSS has no obvious errors**

Spot-check that all `{` have matching `}`, no dangling rules from edits.

**Step 3: Review all changes**

```bash
git diff --stat
git log --oneline main..HEAD
```

**Step 4: Use finishing-a-development-branch skill**

Follow `superpowers:finishing-a-development-branch` to create PR or merge.
