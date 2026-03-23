# Onboarding Modal Redesign

**Date:** 2026-03-23
**Version target:** v1.9.0
**Branch:** `feature/onboarding-redesign`
**Mockup:** `docs/onboarding-redesign-mockup.html`

## Summary

Replace the current 3-step onboarding modal (Welcome, Pick Your Scene, Join Community) with a new 3-step flow (Pick Your Scene, Find Yourself, Your Scene at a Glance). The redesign removes content that tells without showing (feature list, community links) and replaces it with personalization (player lookup) and live data preview (scene stats).

---

## Current vs New Flow

### Current
```
Step 1: Welcome (Agumon mascot + feature list)
Step 2: Pick Your Scene (map + geolocation)
Step 3: Join Community (Discord/Ko-fi/For Organizers)
```

### New
```
Step 1: Pick Your Scene (promoted from Step 2 — get to value fast)
Step 2: Find Yourself (NEW — player search by name or Bandai ID)
Step 3: Your Scene at a Glance (NEW — live data preview + personal rank)
```

---

## Current Architecture

### Files Involved

| File | Role | Lines of Interest |
|------|------|-------------------|
| `views/onboarding-modal-ui.R` | UI definition, 3-step carousel (239 lines) | Entire file |
| `server/scene-server.R` | Server logic: modal show, carousel nav, map, geolocation | Lines 382-841 |
| `www/scene-selector.js` | Storage, first-visit detection, geolocation, custom message handlers | Lines 243-352 |
| `www/custom.css` | All onboarding styles | Lines 3469-3976 |
| `app.R` | `rv$onboarding_step` init (line 1095), LINKS constant, agumon_svg | Various |

### Current Reactive Values
- `rv$onboarding_step` (integer 1-3)
- `rv$current_scene` — set during scene selection
- `rv$current_continent` — set during scene selection

### Current JS Storage Keys
- `digilab_scene_preference` — scene slug
- `digilab_continent_preference` — continent code
- `digilab_onboarding_complete` — "true" when finished

### Current Custom Messages (JS)
- `saveScenePreference` — saves scene + continent, marks onboarding complete
- `requestGeolocation` — triggers browser geolocation
- `clearOnboarding` — testing utility

### Current Input Handlers
- `input$scene_from_storage` — initial storage read on connect
- `input$geolocation_result` — geolocation callback
- `input$find_my_scene` — geolocation button
- `input$select_scene_from_map` — map popup click
- `input$select_scene_online` — "Online" button
- `input$select_scene_all` — "All Scenes" button
- `input$onboarding_next`, `input$onboarding_next_2` — step forward
- `input$onboarding_back` — step backward
- `input$onboarding_skip` — skip to close
- `input$onboarding_finish` — final button
- `input$onboarding_to_organizers` — link to organizers page

---

## New Step Design

### Step 1: Pick Your Scene (reused from current Step 2)

- **Title:** "Where do you play?"
- **Subtitle:** "Select your local scene to see tournaments, players, and meta data from your area."
- **Content:** Interactive Mapbox map + "Find My Scene" button + "or choose" divider + Online/All Scenes buttons + green confirmation bar + muted note
- **Nav:** "Skip for now" (left ghost), "Next →" (right primary)
- **Reused:** Map output, geolocation handler, scene selection helpers, confirmation bar — all identical to current Step 2
- **Changes:** Step label "STEP 1 OF 3", new title/subtitle, map visible on modal open (needs resize trigger)

### Step 2: Find Yourself (NEW)

- **Title:** "Are you already on DigiLab?"
- **Subtitle:** "Search by player name or Bandai Member ID to link your profile."
- **Content:**
  - Search row: textInput + "Search" button (sr-lookup-row pattern)
  - Hint box: "Your Bandai ID is on your TCG+ app profile" (scanner-pattern)
  - **Found:** Player card with avatar initials, name, W-L record, home scene, rating badge
  - **Not found:** "No worries — play in a tournament..." + up to 3 nearby store cards
- **Nav:** "← Back" (left), "Skip" (center ghost), "Almost Done →" (right primary)

### Step 3: Your Scene at a Glance (NEW)

- **Title:** Dynamic scene name (e.g., "Dallas-Fort Worth") or "All Scenes"
- **Subtitle:** "Here's what's happening in your scene"
- **Content:**
  - 2×2 stats grid: Tournaments (this month), Active Players, Trending Deck, Rising Star
  - Conditional rank banner: "Your rating: {rating} · Rank #{rank} in {scene}" (if player found)
  - Full-width CTA: "Enter DigiLab →"
- **Nav:** "← Back" only (CTA replaces finish button)
- **Empty scene:** "Be the first! No tournaments yet..." with encouragement

---

## Implementation Details

### New Reactive Values (add to `app.R:1095`)

| Name | Type | Description |
|------|------|-------------|
| `onboarding_player` | data.frame row or NULL | Player found in Step 2 |
| `onboarding_player_rating` | numeric or NULL | Competitive rating |
| `onboarding_player_rank` | list(rank, total) or NULL | Rank within scene |
| `onboarding_player_record` | data.frame row or NULL | Win/loss record |

### New Inputs

| ID | Type | Purpose |
|----|------|---------|
| `onboarding_player_search` | textInput | Search query |
| `onboarding_player_search_btn` | actionButton | Trigger search |
| `onboarding_skip_2` | actionButton | Skip Step 2 |
| `onboarding_enter` | actionButton | Final CTA |
| `locale_fallback` | custom message result | Browser locale for skip |

### New Outputs

| ID | Type | Purpose |
|----|------|---------|
| `onboarding_player_result` | uiOutput | Step 2 search results |
| `onboarding_scene_title` | textOutput | Step 3 dynamic title |
| `onboarding_stats_grid` | uiOutput | Step 3 stats grid |
| `onboarding_rank_banner` | uiOutput | Step 3 rank (conditional) |

### New Custom Messages

| Name | Direction | Purpose |
|------|-----------|---------|
| `requestLocaleFallback` | Server → JS | Request browser locale |

---

## Server Changes (`server/scene-server.R`)

### Remove
- `onboarding_to_organizers` handler (line 681) — For Organizers link removed
- `onboarding_finish` handler (line 676) — replaced by `onboarding_enter`

### Modify
- **Carousel observer** (lines 585-646): Step 1 triggers map resize (was step 2). Step 3 triggers stats load.
- **Nav button visibility**: New rules for 3 new buttons
- **Skip handler**: Use locale detection → continent fallback instead of defaulting to "all"
- **Map resize**: Fire in `show_onboarding_modal()` with 300ms delay (step 1 visible on open)

### Add: Player Search Handler
Modeled after `submit-match-server.R:182-226`:
1. Try Bandai ID first (if input looks numeric) — query by `member_number`
2. Fall back to name search — exact match first, then `pg_trgm` similarity
3. If found: populate `rv$onboarding_player`, query rating + W-L record + scene rank
4. If not found: set `rv$onboarding_player <- NULL`

### Add: Player Result Renderer (`output$onboarding_player_result`)
- **Found state:** Player card (avatar, name, "Welcome back!", W-L, rating badge, scene)
- **Not found state:** Encouragement message + nearby store cards from `get_nearby_stores_for_onboarding()`

### Add: Nearby Stores Helper
Query stores in selected scene with next scheduled event date. Limit 3. Uses `store_schedules` table for next event calculation.

### Add: Scene Stats Renderer (`output$onboarding_stats_grid`)
Queries for selected scene (last 30 days):
- `COUNT(*)` tournaments
- `COUNT(DISTINCT player_id)` active players
- Most-played deck archetype (excluding UNKNOWN)
- Rising star (most 1st-place finishes)
- Empty scene: show encouraging empty state

### Add: Rank Banner Renderer (`output$onboarding_rank_banner`)
Only shown if `rv$onboarding_player` is not NULL. Shows rating + rank position within scene.

### Add: Locale-to-Continent Mapping
```r
locale_to_continent <- function(lang)
```
Maps `navigator.language` country codes to continent slugs (north_america, south_america, europe, asia, oceania). Used by skip handler.

### Add: Button Handlers
- `onboarding_skip_2` → advance to step 3
- `onboarding_enter` → `select_scene_and_close()`

---

## UI Changes (`views/onboarding-modal-ui.R`)

**Rewrite entire file.** Structure:

1. Progress bar + dot indicators (keep as-is)
2. Step 1: Move current Step 2 content here (map, geolocation, scene buttons)
3. Step 2: New player search (textInput + button + hint + uiOutput)
4. Step 3: New scene stats (dynamic title + uiOutput grid + uiOutput rank + CTA)
5. Nav buttons: Updated for new button set

---

## CSS Changes (`www/custom.css`)

### Keep (lines 3469-3568)
Modal shell, progress bar, dots, step container, step label, title/subtitle, nav buttons

### Remove
- `.onboarding-hero`, `.onboarding-hero-mascot`, `.onboarding-hero-text` (lines 3636-3669)
- `.onboarding-feature-list`, `.onboarding-feature-row`, etc. (lines 3671-3729)
- `.onboarding-link-list`, `.onboarding-link-row`, etc. (lines 3821-3919)

### Keep (map/scene styles, lines 3731-3819)
Map, scene buttons, divider, confirmation — all reused in new Step 1

### Add
- `.onboarding-search-row` — flex row for search input + button
- `.onboarding-hint-box` — cyan left-border hint
- `.onboarding-player-card` — found player display
- `.onboarding-player-avatar` — gradient circle with initials
- `.onboarding-rating-badge` — orange pill with rating
- `.onboarding-store-card` — nearby store in not-found state
- `.onboarding-stats-grid` — 2×2 CSS grid
- `.onboarding-stat-card` — individual stat with icon + value + label
- `.stat-icon-cal/ppl/fire/star` — icon background colors
- `.onboarding-rank-banner` — gradient banner with rating + rank
- `.onboarding-cta-btn` — large gradient CTA
- `.onboarding-empty-scene` — empty state styling

---

## JS Changes (`www/scene-selector.js`)

Minimal — add one custom message handler (~5 lines):

```javascript
Shiny.addCustomMessageHandler('requestLocaleFallback', function(message) {
  var lang = navigator.language || navigator.userLanguage || 'en-US';
  Shiny.setInputValue('locale_fallback', {
    language: lang,
    timestamp: Date.now()
  }, {priority: 'event'});
});
```

No changes to storage keys, postMessage bridge, or DigilabStorage.

---

## Implementation Order

1. **UI skeleton** — Rewrite `onboarding-modal-ui.R` with new structure, stub uiOutputs
2. **Step 1 migration** — Move map from Step 2 to Step 1, fix resize trigger
3. **CSS cleanup** — Remove old styles, add new Step 2/3 styles from mockup
4. **Step 2: Player search** — Search handler, result renderer, stores helper, new reactive values
5. **Step 3: Scene stats** — Stats grid, rank banner, CTA, empty state
6. **Skip behavior** — Locale detection JS, continent mapping, updated skip handler
7. **Nav button logic** — Update carousel observer, add new button handlers
8. **Edge cases + polish** — Empty scenes, mobile, returning users
9. **Docs** — ARCHITECTURE.md, CHANGELOG, dev_log

---

## What Gets Removed

| Content | Location | Action |
|---------|----------|--------|
| Step 1: Welcome (Agumon + feature list) | `onboarding-modal-ui.R` lines 23-77 | Delete |
| Step 3: Community (Discord/Ko-fi) | `onboarding-modal-ui.R` lines 143-201 | Delete |
| `onboarding_to_organizers` handler | `scene-server.R` line 681 | Delete |
| `onboarding_finish` handler | `scene-server.R` line 676 | Replace with `onboarding_enter` |
| CSS: hero, feature list, link list | `custom.css` lines 3636-3729, 3821-3919 | Delete |

LINKS constant and `agumon_svg` stay — used elsewhere in the app.

---

## Edge Cases

| Scenario | Behavior |
|----------|----------|
| Empty scene (no data) | Step 3 shows "Be the first!" empty state |
| Player not found | Step 2 shows stores. Step 3 hides rank banner |
| No stores in scene | Not-found state omits store cards |
| Geolocation denied | Warning toast, user picks manually |
| Returning user | Modal doesn't show (`needsOnboarding = false`) |
| Scene changed after Step 2 | Player search results stay. Step 3 re-queries for new scene. |
| Skip from Step 1 | Locale → continent fallback. Never empty "All Scenes" if detectable |
| Map not rendering | Fire resize in `show_onboarding_modal()` with 300ms delay |
| Multiple search results | Take best match (exact name > trigram). Keep simple for v1 |

---

## Verification Checklist

- [ ] Step 1: Map renders on modal open (no blank map)
- [ ] Step 1: Geolocation works + shows confirmation
- [ ] Step 1: Map markers, Online, All Scenes buttons work
- [ ] Step 1: "Skip" detects locale and sets continent
- [ ] Step 2: Search by exact name works
- [ ] Step 2: Search by Bandai ID (with/without #) works
- [ ] Step 2: Fuzzy name search returns reasonable results
- [ ] Step 2: Found state shows player card with rating/record
- [ ] Step 2: Not-found state shows stores
- [ ] Step 2: "Skip" advances to Step 3 without player
- [ ] Step 3: Scene title updates dynamically
- [ ] Step 3: Stats show correct data for selected scene
- [ ] Step 3: Rank banner shown only when player found
- [ ] Step 3: Empty scene shows encouraging state
- [ ] Step 3: "Enter DigiLab" closes modal + sets scene
- [ ] Progress bar fills 33%/66%/100%
- [ ] Dot indicators active/completed/upcoming
- [ ] Light + dark mode correct
- [ ] Mobile layout (375px)
- [ ] Returning users don't see modal
- [ ] "Welcome Guide" link re-opens redesigned modal
- [ ] No console errors
