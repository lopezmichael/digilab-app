# Mobile Views Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add server-side device detection and dedicated mobile view modules for all 5 public pages (Dashboard, Players, Meta, Tournaments, Stores), replacing cramped desktop layouts with mobile-optimized stacked cards, compact maps, and horizontal scroll sections.

**Architecture:** JS sends device info on `shiny:connected`. `rv$is_mobile` reactive drives conditional `renderUI` in each public server module, sourcing either desktop or mobile view files. Server logic (data reactives, click handlers, modals) is shared. New `www/mobile.css` handles mobile-specific component styles.

**Tech Stack:** R Shiny, bslib, JavaScript, CSS, reactable, highcharter, mapgl

**Design doc:** `docs/plans/2026-03-03-mobile-views-design.md`

---

### Task 1: Device Detection — JS + Server Reactive

**Files:**
- Modify: `app.R:468` (inside the existing `tags$script(HTML("..."))` block)
- Modify: `server/shared-server.R:38` (add reactive after Navigation section header)

**Step 1: Add device detection JS to app.R**

In `app.R`, find the `tags$script(HTML("` block that starts around line 468. At the very beginning of the JS string (before the `$(document).on('click', '.nav-link-sidebar'` line), add:

```javascript
      // Device detection - send device info to Shiny on connect
      var _deviceInfo = {
        type: window.innerWidth <= 768 ? 'mobile' : 'desktop',
        width: window.innerWidth,
        touch: 'ontouchstart' in window,
        standalone: window.matchMedia('(display-mode: standalone)').matches
      };
      $(document).on('shiny:connected', function() {
        Shiny.setInputValue('device_info', _deviceInfo);
      });
```

**Step 2: Add `rv$is_mobile` reactive to shared-server.R**

In `server/shared-server.R`, after the `# Navigation` section header (line 38-40), add a new section:

```r
# ---------------------------------------------------------------------------
# Device Detection
# ---------------------------------------------------------------------------

is_mobile <- reactive({
  info <- input$device_info
  if (is.null(info)) return(FALSE)
  info$type == "mobile"
})
```

Note: This is a standalone reactive, NOT on `rv`. Using a plain `reactive()` is simpler and avoids polluting `rv`. All server modules can access it because they're sourced in the same `local = TRUE` environment.

**Step 3: Verify R syntax**

Run: `"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "parse('app.R'); parse('server/shared-server.R'); cat('OK\n')"`

**Step 4: Commit**

```bash
git add app.R server/shared-server.R
git commit -m "feat: add JS device detection and is_mobile reactive"
```

---

### Task 2: Mobile CSS Foundation — www/mobile.css

**Files:**
- Create: `www/mobile.css`
- Modify: `app.R:458` (add conditional stylesheet link in head tags)

**Step 1: Create www/mobile.css**

Create a new file `www/mobile.css` with all shared mobile component styles:

```css
/* =============================================================================
 * DigiLab Mobile Views
 * Loaded conditionally when is_mobile is TRUE.
 * Companion to custom.css which handles responsive fallbacks via media queries.
 * ============================================================================= */

/* ---------------------------------------------------------------------------
 * Mobile Card List — shared pattern for all table-replacement cards
 * --------------------------------------------------------------------------- */

.mobile-card-list {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
  padding: 0 0.25rem;
}

.mobile-list-card {
  padding: 0.75rem 1rem;
  border: 1px solid rgba(0, 200, 255, 0.1);
  border-radius: 8px;
  background: rgba(255, 255, 255, 0.03);
  cursor: pointer;
  -webkit-tap-highlight-color: rgba(0, 200, 255, 0.1);
  transition: background 0.15s ease;
}

.mobile-list-card:active {
  background: rgba(0, 200, 255, 0.08);
}

[data-bs-theme="dark"] .mobile-list-card {
  border-color: rgba(255, 255, 255, 0.08);
  background: rgba(255, 255, 255, 0.02);
}

[data-bs-theme="dark"] .mobile-list-card:active {
  background: rgba(255, 255, 255, 0.06);
}

/* Card layout helpers */
.mobile-card-row {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
}

.mobile-card-primary {
  font-size: 0.95rem;
  font-weight: 600;
}

.mobile-card-secondary {
  font-size: 0.8rem;
  opacity: 0.7;
  margin-top: 0.15rem;
}

.mobile-card-tertiary {
  font-size: 0.75rem;
  opacity: 0.55;
  margin-top: 0.15rem;
}

.mobile-card-stat {
  font-size: 0.85rem;
  font-weight: 500;
}

.mobile-card-rank {
  font-size: 1.1rem;
  font-weight: 700;
  min-width: 2rem;
  text-align: center;
}

.mobile-card-rank.rank-1 { color: #FFD700; }
.mobile-card-rank.rank-2 { color: #C0C0C0; }
.mobile-card-rank.rank-3 { color: #CD7F32; }

/* ---------------------------------------------------------------------------
 * Horizontal Scroll — rising stars, top decks on dashboard
 * --------------------------------------------------------------------------- */

.mobile-horizontal-scroll {
  display: flex;
  gap: 0.75rem;
  overflow-x: auto;
  scroll-snap-type: x mandatory;
  -webkit-overflow-scrolling: touch;
  padding: 0.5rem 0.25rem;
  /* Hide scrollbar for cleaner look */
  scrollbar-width: none;
  -ms-overflow-style: none;
}

.mobile-horizontal-scroll::-webkit-scrollbar {
  display: none;
}

.mobile-horizontal-scroll > * {
  scroll-snap-align: start;
  flex-shrink: 0;
  width: 280px;
}

/* ---------------------------------------------------------------------------
 * Section Headers — dashboard sections
 * --------------------------------------------------------------------------- */

.mobile-section-header {
  font-size: 0.75rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 0.5px;
  opacity: 0.55;
  padding: 0.75rem 0 0.25rem;
}

/* ---------------------------------------------------------------------------
 * Compact Map — stores page
 * --------------------------------------------------------------------------- */

.mobile-map-compact {
  height: 200px;
  border-radius: 8px;
  overflow: hidden;
  margin-bottom: 0.75rem;
}

.mobile-map-compact .mapboxgl-map,
.mobile-map-compact .maplibregl-map {
  height: 200px !important;
}

/* ---------------------------------------------------------------------------
 * Load More Button
 * --------------------------------------------------------------------------- */

.mobile-load-more {
  width: 100%;
  padding: 0.75rem;
  text-align: center;
  font-size: 0.85rem;
  border: 1px dashed rgba(0, 200, 255, 0.2);
  border-radius: 8px;
  background: transparent;
  color: inherit;
  cursor: pointer;
  margin-top: 0.25rem;
  transition: border-color 0.15s ease;
}

.mobile-load-more:hover,
.mobile-load-more:active {
  border-color: rgba(0, 200, 255, 0.5);
}

/* ---------------------------------------------------------------------------
 * Deck Color Dots
 * --------------------------------------------------------------------------- */

.mobile-deck-dot {
  display: inline-block;
  width: 10px;
  height: 10px;
  border-radius: 50%;
  margin-right: 0.35rem;
  vertical-align: middle;
}

/* ---------------------------------------------------------------------------
 * Mobile Charts — reduced height for dashboard
 * --------------------------------------------------------------------------- */

.mobile-chart-container {
  height: 250px;
  width: 100%;
}

.mobile-chart-container .highcharts-container,
.mobile-chart-container .html-widget {
  height: 250px !important;
}
```

**Step 2: Add conditional stylesheet loading in app.R**

In `app.R`, find the line that loads `custom.css` (around line 458):
```r
tags$link(rel = "stylesheet", type = "text/css", href = "custom.css"),
```

Add after it:
```r
# Mobile-specific styles (loaded for all, scoped by class)
tags$link(rel = "stylesheet", type = "text/css", href = "mobile.css"),
```

Note: We load it unconditionally in the `<head>` (it's a small file and has no effect on desktop since the classes aren't used). This avoids the complexity of injecting CSS from `renderUI`.

**Step 3: Verify CSS has balanced braces**

Run: `python -c "css=open('www/mobile.css').read(); o=css.count('{'); c=css.count('}'); print(f'{o} open, {c} close, {\"OK\" if o==c else \"MISMATCH\"}')"`

**Step 4: Commit**

```bash
git add www/mobile.css app.R
git commit -m "feat: add mobile.css foundation with card and layout styles"
```

---

### Task 3: Convert nav_panel_hidden to uiOutput Wrappers

**Files:**
- Modify: `app.R:863-868` (change 5 `nav_panel_hidden` entries)
- Modify: `server/public-dashboard-server.R` (add `renderUI` for page switching)
- Modify: `server/public-players-server.R` (add `renderUI` for page switching)
- Modify: `server/public-meta-server.R` (add `renderUI` for page switching)
- Modify: `server/public-tournaments-server.R` (add `renderUI` for page switching)
- Modify: `server/public-stores-server.R` (add `renderUI` for page switching)

**Step 1: Change nav_panel_hidden entries in app.R**

Find lines 863-868 in `app.R`:
```r
        nav_panel_hidden(value = "dashboard", dashboard_ui),
        nav_panel_hidden(value = "stores", stores_ui),
        nav_panel_hidden(value = "players", players_ui),
        nav_panel_hidden(value = "meta", meta_ui),
        nav_panel_hidden(value = "tournaments", tournaments_ui),
```

Change to:
```r
        nav_panel_hidden(value = "dashboard", uiOutput("dashboard_page")),
        nav_panel_hidden(value = "stores", uiOutput("stores_page")),
        nav_panel_hidden(value = "players", uiOutput("players_page")),
        nav_panel_hidden(value = "meta", uiOutput("meta_page")),
        nav_panel_hidden(value = "tournaments", uiOutput("tournaments_page")),
```

**Step 2: Add renderUI to public-dashboard-server.R**

At the very TOP of `server/public-dashboard-server.R` (after the file header comment, before any other code), add:

```r
# ---------------------------------------------------------------------------
# Page Rendering (desktop vs mobile)
# ---------------------------------------------------------------------------
output$dashboard_page <- renderUI({
  if (is_mobile()) {
    source("views/mobile-dashboard-ui.R", local = TRUE)$value
  } else {
    dashboard_ui
  }
})
```

Note: `dashboard_ui` is already defined (sourced at app startup from `views/dashboard-ui.R`). For desktop, we just return the pre-built UI object. For mobile, we source the mobile view file. The `$value` extracts the last expression from the sourced file.

**Step 3: Add renderUI to public-players-server.R**

At the top, add:
```r
output$players_page <- renderUI({
  if (is_mobile()) {
    source("views/mobile-players-ui.R", local = TRUE)$value
  } else {
    players_ui
  }
})
```

**Step 4: Add renderUI to public-meta-server.R**

At the top, add:
```r
output$meta_page <- renderUI({
  if (is_mobile()) {
    source("views/mobile-meta-ui.R", local = TRUE)$value
  } else {
    meta_ui
  }
})
```

**Step 5: Add renderUI to public-tournaments-server.R**

At the top, add:
```r
output$tournaments_page <- renderUI({
  if (is_mobile()) {
    source("views/mobile-tournaments-ui.R", local = TRUE)$value
  } else {
    tournaments_ui
  }
})
```

**Step 6: Add renderUI to public-stores-server.R**

At the top, add:
```r
output$stores_page <- renderUI({
  if (is_mobile()) {
    source("views/mobile-stores-ui.R", local = TRUE)$value
  } else {
    stores_ui
  }
})
```

**Step 7: Verify R syntax**

Run: `"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "parse('app.R'); parse('server/public-dashboard-server.R'); parse('server/public-players-server.R'); parse('server/public-meta-server.R'); parse('server/public-tournaments-server.R'); parse('server/public-stores-server.R'); cat('OK\n')"`

Note: The parse will succeed even though `views/mobile-*.R` don't exist yet — they're sourced at runtime, not parse time.

**Step 8: Commit**

```bash
git add app.R server/public-dashboard-server.R server/public-players-server.R server/public-meta-server.R server/public-tournaments-server.R server/public-stores-server.R
git commit -m "feat: convert public pages to conditional uiOutput rendering"
```

---

### Task 4: Mobile Dashboard View

**Files:**
- Create: `views/mobile-dashboard-ui.R`
- Modify: `server/public-dashboard-server.R` (add mobile card renderers)

**Step 1: Create views/mobile-dashboard-ui.R**

This file must return the mobile dashboard UI as its last expression. It reuses the same output IDs as the desktop view for value boxes and charts (they render into whichever UI is active).

```r
# views/mobile-dashboard-ui.R
# Mobile-optimized dashboard layout

tagList(
  # Title strip with filters (same as desktop - responsive stacking already works)
  div(
    class = "page-title-strip mb-2",
    div(
      class = "title-strip-content",
      div(
        class = "title-strip-context",
        bsicons::bs_icon("grid-3x3-gap", class = "title-strip-icon"),
        tags$span(class = "title-strip-text", uiOutput("dashboard_context_text", inline = TRUE))
      ),
      div(
        class = "title-strip-filters",
        div(class = "title-strip-filter",
            selectInput("dashboard_format", NULL,
                        choices = c("Loading..." = ""),
                        selectize = FALSE,
                        width = "100%"))
      )
    )
  ),

  # Value boxes - 2x2 grid (reuse existing output IDs)
  layout_columns(
    col_widths = c(6, 6, 6, 6),
    value_box(
      title = "Tournaments",
      value = textOutput("total_tournaments_val"),
      showcase = bsicons::bs_icon("trophy"),
      theme = "primary"
    ),
    value_box(
      title = "Players",
      value = textOutput("total_players_val"),
      showcase = bsicons::bs_icon("people"),
      theme = "primary"
    ),
    value_box(
      title = uiOutput("most_popular_deck_val"),
      value = uiOutput("top_deck_meta_share"),
      showcase = uiOutput("top_deck_image"),
      showcase_layout = "left center",
      theme = "primary",
      class = "top-deck-vb"
    ),
    value_box(
      title = uiOutput("hot_deck_name"),
      value = uiOutput("hot_deck_trend"),
      showcase = uiOutput("hot_deck_image"),
      showcase_layout = "left center",
      theme = "primary",
      class = "hot-deck-vb"
    )
  ),

  # Tournament Activity chart
  div(class = "mobile-section-header", "Tournament Activity"),
  div(
    class = "mobile-chart-container",
    highchartOutput("tournaments_trend_chart", height = "250px")
  ),

  # Meta Breakdown chart
  div(class = "mobile-section-header", "Color Distribution"),
  div(
    class = "mobile-chart-container",
    highchartOutput("color_dist_chart", height = "250px")
  ),

  # Rising Stars — horizontal scroll
  div(class = "mobile-section-header", "Rising Stars"),
  uiOutput("mobile_rising_stars"),

  # Top Decks — horizontal scroll
  div(class = "mobile-section-header", "Top Decks"),
  uiOutput("mobile_top_decks")
)
```

**Step 2: Add mobile rising stars renderer to public-dashboard-server.R**

Find the existing `output$rising_stars_cards` renderUI in `public-dashboard-server.R`. After it, add a mobile version that renders cards in a horizontal scroll container. The mobile version should reuse the same data reactive that the desktop rising stars uses.

Search for `rising_stars` in the file to find the data source. It likely queries recent players with biggest rating gains. The mobile renderer wraps each card in `.mobile-horizontal-scroll`:

```r
# Mobile rising stars (horizontal scroll)
output$mobile_rising_stars <- renderUI({
  req(is_mobile())
  # Reuse the same data query as desktop rising stars
  # Find the existing reactive/query and reference it here
  # Each card: player name, rating, trend
  # Wrap in: div(class = "mobile-horizontal-scroll", ...)
})
```

**Important:** The implementer must READ the existing rising stars code in `public-dashboard-server.R` to find the exact data source and replicate the card content. Don't duplicate the query — reference the same reactive.

**Step 3: Add mobile top decks renderer**

Same pattern — find the existing `output$top_decks_with_images` renderUI and create a mobile version:

```r
output$mobile_top_decks <- renderUI({
  req(is_mobile())
  # Reuse same data as desktop top decks
  # Each card: deck name, color dot, meta share, win rate
  # Wrap in: div(class = "mobile-horizontal-scroll", ...)
})
```

**Step 4: Verify R syntax**

Run: `"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "parse('views/mobile-dashboard-ui.R'); parse('server/public-dashboard-server.R'); cat('OK\n')"`

**Step 5: Commit**

```bash
git add views/mobile-dashboard-ui.R server/public-dashboard-server.R
git commit -m "feat: add mobile dashboard view with horizontal scroll cards"
```

---

### Task 5: Mobile Players View

**Files:**
- Create: `views/mobile-players-ui.R`
- Modify: `server/public-players-server.R` (add mobile card renderer)

**Step 1: Create views/mobile-players-ui.R**

```r
# views/mobile-players-ui.R
# Mobile-optimized player standings with stacked cards

tagList(
  # Title strip with filters (same structure, responsive stacking works)
  div(
    class = "page-title-strip mb-3",
    div(
      class = "title-strip-content",
      div(
        class = "title-strip-context",
        bsicons::bs_icon("people", class = "title-strip-icon"),
        tags$span(class = "title-strip-text", "Player Standings")
      ),
      div(
        class = "title-strip-filters",
        div(class = "title-strip-filter",
            selectInput("players_format", NULL,
                        choices = c("Loading..." = ""),
                        selectize = FALSE,
                        width = "100%")),
        div(class = "title-strip-filter title-strip-search",
            textInput("players_search", NULL,
                      placeholder = "Search players...",
                      width = "100%")),
        div(class = "title-strip-filter",
            uiOutput("players_min_events_pills"))
      )
    )
  ),

  # Player cards
  uiOutput("mobile_players_cards")
)
```

**Step 2: Add mobile players card renderer to public-players-server.R**

The implementer must READ the existing `output$player_standings` renderReactable to understand the data source. It queries player standings with ratings, records, win rates, main decks, filtered by format/search/min_events.

Add after the existing renderReactable:

```r
# Mobile player cards
mobile_players_limit <- reactiveVal(20)

# Reset limit when filters change
observeEvent(list(input$players_format, input$players_search, input$players_min_events), {
  mobile_players_limit(20)
}, ignoreInit = TRUE)

observeEvent(input$mobile_players_load_more, {
  mobile_players_limit(mobile_players_limit() + 20)
})

output$mobile_players_cards <- renderUI({
  req(is_mobile())

  # Use the same data/query as the reactable version
  # The implementer must find the existing data reactive and reference it
  # data <- [existing_filtered_players_reactive]()

  # n <- min(mobile_players_limit(), nrow(data))
  # show_data <- data[1:n, ]

  # cards <- lapply(seq_len(nrow(show_data)), function(i) {
  #   row <- show_data[i, ]
  #   div(
  #     class = "mobile-list-card",
  #     onclick = sprintf("Shiny.setInputValue('player_clicked', '%s', {priority: 'event'})", row$player_id),
  #     div(class = "mobile-card-row",
  #       span(class = paste("mobile-card-rank", if (i <= 3) paste0("rank-", i) else ""), i),
  #       span(class = "mobile-card-primary", row$player_name),
  #       span(class = "mobile-card-stat", round(row$rating))
  #     ),
  #     div(class = "mobile-card-secondary",
  #       sprintf("%s  %d-%d  .%03d",
  #               if (!is.na(row$trend) && row$trend > 0) "\u25B2" else if (!is.na(row$trend) && row$trend < 0) "\u25BC" else "",
  #               row$wins, row$losses, round(row$win_rate * 1000))
  #     ),
  #     if (!is.na(row$main_deck)) {
  #       div(class = "mobile-card-tertiary", paste("Main Deck:", row$main_deck))
  #     }
  #   )
  # })

  # tagList(
  #   div(class = "mobile-card-list", cards),
  #   if (n < nrow(data)) {
  #     actionButton("mobile_players_load_more",
  #                  sprintf("Load more (%d remaining)", nrow(data) - n),
  #                  class = "mobile-load-more")
  #   }
  # )
})
```

**CRITICAL:** The code above is pseudocode showing the pattern. The implementer MUST:
1. Read the existing `output$player_standings` renderReactable in full
2. Find the exact reactive data source (the query that produces the player standings data)
3. Use the exact column names from that data source (not guessed names)
4. Wire up the same click handler (`input$player_clicked`) that opens the player modal

**Step 3: Verify R syntax**

Run: `"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "parse('views/mobile-players-ui.R'); parse('server/public-players-server.R'); cat('OK\n')"`

**Step 4: Commit**

```bash
git add views/mobile-players-ui.R server/public-players-server.R
git commit -m "feat: add mobile players view with stacked cards"
```

---

### Task 6: Mobile Meta View

**Files:**
- Create: `views/mobile-meta-ui.R`
- Modify: `server/public-meta-server.R` (add mobile card renderer)

**Step 1: Create views/mobile-meta-ui.R**

Same pattern as players. Title strip with filters + `uiOutput("mobile_meta_cards")`.

The filter strip must include: format selector, search input, min entries pills (find exact input IDs from existing `views/meta-ui.R`).

**Step 2: Add mobile meta card renderer to public-meta-server.R**

Same pattern as Task 5. The implementer must:
1. Read the existing `output$archetype_stats` renderReactable
2. Find the data source (archetype entries, win rates, meta share, colors)
3. Create cards with: color dot, deck name, entry count, meta %, win %, top placements
4. Wire up `input$archetype_clicked` for the deck detail modal
5. Add load-more pagination

Card layout:
```
┌─────────────────────────┐
│ [dot] Imperialdramon    │
│ 14 entries · 18.2% meta │
│ 64.3% win · 3 tops      │
└─────────────────────────┘
```

**Step 3: Verify and commit**

```bash
git add views/mobile-meta-ui.R server/public-meta-server.R
git commit -m "feat: add mobile meta view with deck archetype cards"
```

---

### Task 7: Mobile Tournaments View

**Files:**
- Create: `views/mobile-tournaments-ui.R`
- Modify: `server/public-tournaments-server.R` (add mobile card renderer)

**Step 1: Create views/mobile-tournaments-ui.R**

Title strip with filters + `uiOutput("mobile_tournaments_cards")`.

The filter strip must include: format selector, event type selector, search input (find exact input IDs from existing `views/tournaments-ui.R`).

**Step 2: Add mobile tournaments card renderer**

Same pattern. The implementer must:
1. Read `output$tournament_history` renderReactable
2. Find the data source (tournaments with date, store, players, winner, winning deck)
3. Create cards with: date, store name, player count + winner
4. Wire up `input$tournament_clicked` for tournament detail modal
5. Add load-more pagination

Card layout:
```
┌─────────────────────────┐
│ Mar 1, 2026             │
│ Common Ground Games      │
│ 16 players · Winner: Fox │
└─────────────────────────┘
```

**Step 3: Verify and commit**

```bash
git add views/mobile-tournaments-ui.R server/public-tournaments-server.R
git commit -m "feat: add mobile tournaments view with stacked cards"
```

---

### Task 8: Mobile Stores View

**Files:**
- Create: `views/mobile-stores-ui.R`
- Modify: `server/public-stores-server.R` (add mobile card renderer + compact map)

**Step 1: Create views/mobile-stores-ui.R**

```r
# views/mobile-stores-ui.R
# Mobile-optimized stores page with compact map and store cards

tagList(
  # Title strip with filters
  div(
    class = "page-title-strip mb-3",
    div(
      class = "title-strip-content",
      div(
        class = "title-strip-context",
        bsicons::bs_icon("geo-alt", class = "title-strip-icon"),
        tags$span(class = "title-strip-text", "Location Scanner")
      ),
      div(
        class = "title-strip-filters",
        div(class = "title-strip-filter title-strip-search",
            textInput("stores_search", NULL,
                      placeholder = "Search stores...",
                      width = "100%"))
      )
    )
  ),

  # Compact map (200px)
  div(
    class = "mobile-map-compact",
    mapgl::mapboxglOutput("mobile_stores_map", height = "200px")
  ),

  # Store cards
  uiOutput("mobile_stores_cards")
)
```

**Step 2: Add mobile stores map renderer**

The implementer must:
1. Read the existing `output$stores_map` renderMapboxgl in `public-stores-server.R`
2. Create a `output$mobile_stores_map` that renders the same map data but at 200px height
3. Reuse the same store coordinate data and map markers/clustering
4. Keep the same popup click behavior

**Step 3: Add mobile stores card renderer**

The implementer must:
1. Read the existing store list/schedule views to find the data source
2. Create cards with: store name, schedule (day + frequency + time), city, event count + rating
3. Wire up clicks — tapping a card should:
   a. Set `input$store_clicked` to open the store detail modal
   b. Optionally pan the map to that store's location
4. Add load-more pagination

Card layout:
```
┌─────────────────────────┐
│ Common Ground Games      │
│ Fri · Weekly · 6pm       │
│ Dallas, TX               │
│ 12 events · ★ 1423       │
└─────────────────────────┘
```

**Step 4: Handle map-to-card interaction**

When a map pin is clicked, scroll to and briefly highlight the corresponding store card. This requires:
- Adding a `data-store-id` attribute to each card
- A JS handler that listens for the map popup click and scrolls to the matching card

This is nice-to-have — implement if straightforward, skip if complex.

**Step 5: Verify and commit**

```bash
git add views/mobile-stores-ui.R server/public-stores-server.R
git commit -m "feat: add mobile stores view with compact map and store cards"
```

---

### Task 9: Integration Testing + Polish

**Files:**
- Possibly modify: any file from Tasks 1-8 that needs fixes

**Step 1: Verify all R files parse**

```bash
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "
  files <- c('app.R',
             'server/shared-server.R',
             'server/public-dashboard-server.R',
             'server/public-players-server.R',
             'server/public-meta-server.R',
             'server/public-tournaments-server.R',
             'server/public-stores-server.R',
             'views/mobile-dashboard-ui.R',
             'views/mobile-players-ui.R',
             'views/mobile-meta-ui.R',
             'views/mobile-tournaments-ui.R',
             'views/mobile-stores-ui.R')
  for (f in files) { parse(f); cat(f, 'OK\n') }
"
```

**Step 2: Verify mobile.css brace balance**

```bash
python -c "css=open('www/mobile.css').read(); o=css.count('{'); c=css.count('}'); print(f'{o} open, {c} close, {\"OK\" if o==c else \"MISMATCH\"}')"
```

**Step 3: Check git status and review all changes**

```bash
git diff --stat main..HEAD
git log --oneline main..HEAD
```

**Step 4: Ask user to test**

The implementer should ask the user to:
1. Run `shiny::runApp()` locally
2. Open browser dev tools → toggle mobile device mode (375px width)
3. Verify each page shows the mobile card layout
4. Verify desktop (>768px) still shows the original table layout
5. Check dark mode on mobile
6. Test clicking cards to open modals

**Step 5: Fix any issues found during testing**

Address whatever the user reports.

**Step 6: Commit any fixes**

```bash
git add -A
git commit -m "fix: address mobile view integration issues"
```

---

### Task 10: Documentation + Branch Completion

**Files:**
- Modify: `ARCHITECTURE.md` (add mobile views section)
- Modify: `CLAUDE.md` (update project structure)
- Modify: `CHANGELOG.md` (add entry)

**Step 1: Update ARCHITECTURE.md**

Add a new section documenting:
- The `is_mobile` reactive and how it works
- The conditional rendering pattern (uiOutput in nav_panel_hidden)
- The mobile view file naming convention (`views/mobile-*.R`)
- The mobile CSS file (`www/mobile.css`)

**Step 2: Update CLAUDE.md project structure**

Add the new files to the project structure listing:
```
├── views/
│   ├── mobile-dashboard-ui.R    # Mobile dashboard view
│   ├── mobile-players-ui.R      # Mobile players view
│   ├── mobile-meta-ui.R         # Mobile meta view
│   ├── mobile-tournaments-ui.R  # Mobile tournaments view
│   ├── mobile-stores-ui.R       # Mobile stores view
│   ├── submit-ui.R              # Upload Results (was missing from listing)
```

Also add `www/mobile.css` to the structure.

**Step 3: Update CHANGELOG.md**

Add entry for the mobile views feature under the next version.

**Step 4: Commit docs**

```bash
git add ARCHITECTURE.md CLAUDE.md CHANGELOG.md
git commit -m "docs: add mobile views to architecture docs and changelog"
```

**Step 5: Use finishing-a-development-branch skill**

Follow `superpowers:finishing-a-development-branch` to create PR or merge.
