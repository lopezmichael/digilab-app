# DigiLab Architecture

Technical reference for the DigiLab codebase. Consult this document before adding new server modules, reactive values, or modifying core patterns.

**Last Updated:** February 2026 (v1.0.0)

> **Note:** Always keep this document in sync with code changes. Update when adding new reactive values, server modules, or patterns.

---

## Table of Contents

1. [Server Module Structure](#server-module-structure)
2. [Reactive Values Reference](#reactive-values-reference)
3. [Navigation Patterns](#navigation-patterns)
4. [Modal Patterns](#modal-patterns)
5. [Database Patterns](#database-patterns)

---

## Server Module Structure

### Overview

The application uses a modular server architecture. All server logic is extracted from `app.R` into separate files in `server/`.

```
server/
├── shared-server.R            # Database, navigation, auth helpers
├── public-dashboard-server.R  # Dashboard/Overview tab (889 lines)
├── public-stores-server.R     # Stores tab with map (851 lines)
├── public-players-server.R    # Players tab (364 lines)
├── public-meta-server.R       # Meta analysis tab (305 lines)
├── public-tournaments-server.R # Tournaments tab (237 lines)
├── admin-results-server.R     # Tournament entry wizard
├── admin-tournaments-server.R # Tournament management
├── admin-decks-server.R       # Deck archetype CRUD
├── admin-stores-server.R      # Store management
├── admin-players-server.R     # Player management
└── admin-formats-server.R     # Format management
```

### Naming Convention

| Prefix | Purpose | Example |
|--------|---------|---------|
| `public-*` | Public-facing tabs (no auth required) | `public-players-server.R` |
| `admin-*` | Admin tabs (requires `rv$is_admin` or `rv$is_superadmin`) | `admin-decks-server.R` |
| `shared-*` | Shared utilities used by multiple modules | `shared-server.R` |

### Lazy Admin Loading

Admin modules use a two-stage lazy loading pattern to reduce startup overhead for non-admin sessions:

1. **UI stage:** Admin view files (`views/admin-*.R`) are NOT sourced at app startup. Instead, `nav_panel_hidden` panels contain `uiOutput()` placeholders.
2. **Server stage:** When `rv$is_admin` becomes TRUE, an `observeEvent` sources both the admin view files and server modules, then renders the UI into the placeholders via `renderUI()`.

```r
# In app.R UI definition — lightweight placeholders
nav_panel_hidden(value = "admin_results", uiOutput("admin_results_ui")),

# In app.R server — lazy-loaded on auth
observeEvent(rv$is_admin, {
  if (rv$is_admin && !admin_modules_loaded()) {
    source("views/admin-results-ui.R", local = TRUE)   # defines admin_results_ui
    output$admin_results_ui <- renderUI(admin_results_ui)
    source("server/admin-results-server.R", local = TRUE)
    # ... repeat for all 8 admin modules
    admin_modules_loaded(TRUE)
  }
}, ignoreInit = TRUE)
```

This means ~99% of sessions (non-admin visitors) skip all admin UI construction and server module registration.

### Adding a New Server Module

1. Create file: `server/{prefix}-{name}-server.R`
2. For **public** modules: Add `source()` call in `app.R` (after reactive values, before UI render)
3. For **admin** modules: Add `source()` inside the `observeEvent(rv$is_admin, ...)` block, along with the corresponding view source and `renderUI`
4. Module has access to `input`, `output`, `session`, `rv` via `local = TRUE`

```r
# In app.R — public module
source("server/public-newfeature-server.R", local = TRUE)
```

### What Goes Where

| Content | Location |
|---------|----------|
| Reactive values initialization | `app.R` |
| Database connection setup | `server/shared-server.R` |
| Navigation observers | `server/shared-server.R` |
| Auth logic | `server/shared-server.R` |
| Tab-specific outputs/observers | `server/{prefix}-{tab}-server.R` |
| Helper functions (pure) | `R/*.R` |
| UI definitions | `views/*-ui.R` |

---

## Reactive Values Reference

All reactive values are initialized in `app.R`. **Never create new reactive values ad-hoc in server files** - always add them to the initialization block.

### Core

| Name | Type | Description |
|------|------|-------------|
| `db_con` | connection | DuckDB database connection |
| `is_admin` | logical | Whether user is authenticated as admin or superadmin |
| `is_superadmin` | logical | Whether user is authenticated as superadmin (Edit Stores, Edit Formats) |

### Navigation & Scene

| Name | Type | Description |
|------|------|-------------|
| `current_nav` | character | Current active tab ID |
| `current_scene` | character | Selected scene slug ("all", "dfw", "online", etc.) |
| `navigate_to_tournament_id` | integer | Tournament ID for cross-tab navigation |

### Modal State

Pattern: `selected_{entity}_id` for single selection, `selected_{entity}_ids` for multiple.

| Name | Type | Description |
|------|------|-------------|
| `selected_store_id` | integer | Store ID for detail modal |
| `selected_online_store_id` | integer | Online store ID for detail modal |
| `selected_player_id` | integer | Player ID for profile modal |
| `selected_archetype_id` | integer | Archetype ID for deck modal |
| `selected_tournament_id` | integer | Tournament ID for detail modal |
| `selected_store_ids` | integer[] | Store IDs from map region filter |
| `modal_store_coords` | list | Store coordinates for modal mini map (lat, lng, name) |

### Onboarding State

| Name | Type | Description |
|------|------|-------------|
| `onboarding_step` | integer | Current step in onboarding carousel (1-3) |

### Form/Wizard State

| Name | Type | Description |
|------|------|-------------|
| `wizard_step` | integer | Current step in result entry wizard (1=Details, 2=Results) |
| `active_tournament_id` | integer | Tournament being edited in wizard |
| `current_results` | data.frame | Results being entered in wizard |
| `duplicate_tournament` | data.frame | Tournament info for duplicate flow |
| `editing_store` | list | Store being edited (edit mode) |
| `editing_archetype` | list | Archetype being edited (edit mode) |
| `card_search_results` | data.frame | Card search results for deck management |
| `card_search_page` | integer | Current page in card search pagination |
| `schedule_to_delete_id` | integer | Schedule ID pending delete confirmation |

### Admin Grid State

Declared at top of respective server files. All three grids use shared functions from `R/admin_grid.R`.

**Enter Results** (prefix: `admin_`, declared in `admin-results-server.R`):

| Name | Type | Description |
|------|------|-------------|
| `admin_grid_data` | data.frame | Grid rows for bulk result entry |
| `admin_record_format` | string | "points" or "wlt" |
| `admin_player_matches` | list | Player match status per row |
| `admin_deck_request_row` | integer | Row requesting a new deck |

**Upload Results** (prefix: `submit_`, declared in `public-submit-server.R`):

| Name | Type | Description |
|------|------|-------------|
| `submit_grid_data` | data.frame | Grid rows for OCR review/edit |
| `submit_player_matches` | list | Player match status per row |
| `submit_ocr_row_indices` | integer[] | Row indices populated by OCR (for review mode CSS) |
| `submit_ocr_results` | data.frame | Raw OCR results (synced from grid on submit) |
| `submit_refresh_trigger` | integer | Refresh trigger for submit grid re-render |
| `ocr_pending_combined` | data.frame | Pending OCR results awaiting quality confirmation |
| `ocr_pending_total_players` | integer | Pending player count for quality check |
| `ocr_pending_total_rounds` | integer | Pending round count for quality check |
| `ocr_pending_parsed_count` | integer | Parsed player count for quality check |

**Edit Tournaments** (prefix: `edit_`, declared in `admin-tournaments-server.R`):

| Name | Type | Description |
|------|------|-------------|
| `edit_grid_data` | data.frame | Grid rows for editing existing results |
| `edit_record_format` | string | "points" or "wlt" (inferred from data) |
| `edit_player_matches` | list | Player match status per row |
| `edit_deleted_result_ids` | integer[] | Result IDs marked for DB deletion |
| `edit_grid_tournament_id` | integer | Tournament being edited in grid |

### Refresh Triggers

Pattern: `{scope}_refresh` - increment to trigger reactive invalidation.

| Name | Type | Description |
|------|------|-------------|
| `data_refresh` | integer | Global refresh for all public tables |
| `results_refresh` | integer | Refresh results table in wizard |
| `format_refresh` | integer | Refresh format dropdowns |
| `tournament_refresh` | integer | Refresh tournament tables |
| `schedules_refresh` | integer | Refresh store schedules table in admin |

**Usage:**
```r
# Trigger refresh
rv$data_refresh <- (rv$data_refresh %||% 0) + 1

# React to refresh
observe({
  rv$data_refresh  # Dependency
  # ... refresh logic
})
```

### Delete Permission State

Pattern: `can_delete_{entity}` (logical) + `{entity}_{related}_count` (integer).

| Name | Type | Description |
|------|------|-------------|
| `can_delete_store` | logical | Whether store can be deleted |
| `can_delete_format` | logical | Whether format can be deleted |
| `can_delete_player` | logical | Whether player can be deleted |
| `can_delete_archetype` | logical | Whether archetype can be deleted |
| `store_tournament_count` | integer | Tournaments referencing store |
| `format_tournament_count` | integer | Tournaments using format |
| `player_result_count` | integer | Results for player |
| `archetype_result_count` | integer | Results using archetype |

### Adding New Reactive Values

1. **Choose the right category** from the list above
2. **Follow naming conventions:**
   - Modal state: `selected_{entity}_id`
   - Refresh triggers: `{scope}_refresh`
   - Delete permission: `can_delete_{entity}` + `{entity}_{related}_count`
3. **Add to `app.R`** in the appropriate section with a comment
4. **Update this document** with the new value

---

## Navigation Patterns

### Tab Navigation (Correct Pattern)

Always use all three steps to ensure sidebar stays in sync:

```r
# 1. Switch the tab content
nav_select("main_content", "target_tab")

# 2. Update reactive state
rv$current_nav <- "target_tab"

# 3. Sync sidebar highlight
session$sendCustomMessage("updateSidebarNav", "nav_target_tab")
```

### Tab IDs

| Tab | Content ID | Sidebar Nav ID |
|-----|------------|----------------|
| Dashboard | `dashboard` | `nav_dashboard` |
| Stores | `stores` | `nav_stores` |
| Players | `players` | `nav_players` |
| Meta | `meta` | `nav_meta` |
| Tournaments | `tournaments` | `nav_tournaments` |
| Admin: Add Results | `admin_results` | `nav_admin_results` |
| Admin: Tournaments | `admin_tournaments` | `nav_admin_tournaments` |
| Admin: Decks | `admin_decks` | `nav_admin_decks` |
| Admin: Stores | `admin_stores` | `nav_admin_stores` |
| Admin: Formats | `admin_formats` | `nav_admin_formats` |
| Admin: Players | `admin_players` | `nav_admin_players` |

---

## Modal Patterns

All modals use Shiny's native `showModal(modalDialog())` / `removeModal()` pattern. There are no static Bootstrap modals in the codebase.

### Standard Modal

```r
showModal(modalDialog(
  title = "Modal Title",
  # ... content
  footer = tagList(
    modalButton("Cancel"),
    actionButton("confirm_btn", "Confirm")
  ),
  size = "l",       # "s", default, "l", or "xl"
  easyClose = TRUE  # Click outside to close
))

# Hide modal
removeModal()
```

### Modal Size Convention

| Modal Type | Size |
|------------|------|
| Detail/Profile (player, deck, store, tournament) | `size = "l"` |
| Confirmation (delete, merge) | Default (no size param) |
| Forms/Editors (results editor, paste spreadsheet) | `size = "l"` |
| Processing spinners | `size = "s"` |

### Nested Modal Pattern (Results Editor)

Shiny only supports one modal at a time — `showModal()` replaces the current modal. For the tournament results editor (which has edit/delete sub-modals):

```r
# Helper function to re-show the results editor
show_results_editor <- function() {
  showModal(modalDialog(
    # ... results table + add form
    size = "l"
  ))
}

# When editing a result: replace results modal with edit modal
showModal(modalDialog(title = "Edit Result", ...))

# After save/cancel: re-show the results editor
show_results_editor()
```

### Modal Data Flow

1. User clicks row → handler sets `rv$selected_{entity}_id`
2. Observer watches `rv$selected_{entity}_id` → fetches data → shows modal
3. Modal actions use the ID from `rv$selected_{entity}_id`
4. On close, optionally clear `rv$selected_{entity}_id`

---

## Database Patterns

### Connection Handling

Connection is established in `shared-server.R` and stored in `rv$db_con`:

```r
# Check connection before use
req(rv$db_con)
if (!dbIsValid(rv$db_con)) return(NULL)

# Use connection
data <- dbGetQuery(rv$db_con, "SELECT * FROM table")
```

### Refresh Pattern

When admin makes changes, trigger refresh so public views update:

```r
# After INSERT/UPDATE/DELETE
rv$data_refresh <- (rv$data_refresh %||% 0) + 1

# In public view reactive
reactive({
  rv$data_refresh  # React to changes
  req(rv$db_con)
  dbGetQuery(rv$db_con, "...")
})
```

### Parameterized Queries

Always use parameterized queries to prevent SQL injection:

```r
# Correct
dbGetQuery(rv$db_con, "SELECT * FROM players WHERE player_id = ?",
           params = list(player_id))

# Also correct (named)
dbGetQuery(rv$db_con, "SELECT * FROM players WHERE player_id = $1",
           params = list(player_id))

# WRONG - SQL injection risk
dbGetQuery(rv$db_con, paste0("SELECT * FROM players WHERE player_id = ", player_id))
```

### safe_query() Wrapper (v0.21.1+)

All public queries should use the `safe_query()` wrapper for graceful error handling:

```r
# In shared-server.R
safe_query <- function(con, query, params = NULL, default = NULL) {
  tryCatch({
    if (is.null(params) || length(params) == 0) {
      dbGetQuery(con, query)
    } else {
      dbGetQuery(con, query, params = params)
    }
  }, error = function(e) {
    message("Database query error: ", e$message)
    default
  })
}

# Usage
result <- safe_query(rv$db_con, "SELECT * FROM players WHERE id = ?",
                     params = list(player_id),
                     default = data.frame())
```

### Transaction Safety (v1.0+)

Inside explicit `BEGIN TRANSACTION` / `COMMIT` blocks, use `DBI::dbExecute()` directly — **not** `safe_execute()`. The `safe_execute()` wrapper swallows errors (returns 0), which prevents DuckDB from rolling back the aborted transaction. All subsequent statements fail silently.

```r
tryCatch({
  dbExecute(rv$db_con, "BEGIN TRANSACTION")

  # Use DBI::dbExecute() for writes inside transactions
  DBI::dbExecute(rv$db_con, "INSERT INTO ...", params = list(...))
  DBI::dbExecute(rv$db_con, "UPDATE ...", params = list(...))

  # safe_query() is fine for SELECT (read-only, no rollback concern)
  player <- safe_query(rv$db_con, "SELECT ...", params = list(...))

  dbExecute(rv$db_con, "COMMIT")
}, error = function(e) {
  tryCatch(dbExecute(rv$db_con, "ROLLBACK"), error = function(re) NULL)
  if (sentry_enabled) {
    tryCatch(sentryR::capture_exception(e, tags = sentry_context_tags()), error = function(se) NULL)
  }
  notify(paste("Error:", e$message), type = "error")
})
```

Outside of transactions, `safe_execute()` remains the correct choice — it prevents one failed write from crashing the session.

### Lazy-Loaded Admin UI (v1.0+)

Admin views are lazy-loaded via `renderUI()` after login. Any `observe` block in an admin server module that calls `updateSelectInput()` must include `rv$current_nav` as a reactive dependency. Without it, the update fires before the input exists in the DOM and gets silently dropped.

```r
observe({
  rv$current_nav  # Re-fires when user navigates to this tab
  req(rv$db_con, rv$is_admin)
  updateSelectInput(session, "my_dropdown", choices = ...)
})
```

### build_filters_param() Helper (v0.21.1+)

Use `build_filters_param()` for consistent parameterized WHERE clause construction:

```r
# Build filters with SQL injection prevention
filters <- build_filters_param(
  table_alias = "t",
  format = input$format_filter,        # Format dropdown value
  event_type = input$event_type,       # Event type dropdown
  search = input$search_text,          # Text search
  search_column = "name",              # Column to search
  scene = rv$current_scene,            # Scene filter (v0.23+)
  store_alias = "s"                    # Required for scene filtering
)

# Use in query
query <- sprintf("
  SELECT * FROM tournaments t
  JOIN stores s ON t.store_id = s.store_id
  WHERE 1=1 %s
", filters$sql)

result <- safe_query(rv$db_con, query, params = filters$params, default = data.frame())
```

**Parameters:**
| Parameter | Description |
|-----------|-------------|
| `table_alias` | Alias for main table (e.g., "t" for tournaments) |
| `format` | Format filter value (e.g., "BT19") |
| `event_type` | Event type filter (e.g., "locals") |
| `search` | Text search value |
| `search_column` | Column to search in (e.g., "name", "display_name") |
| `scene` | Scene slug for filtering (e.g., "dfw", "online", "all") |
| `store_alias` | Alias for stores table (required for scene filtering) |

**Returns:** `list(sql = "AND ... AND ...", params = list(...))`

### Batch Dashboard Reactives (v0.23+)

Dashboard queries are consolidated into batch reactives to reduce database calls:

```r
# In public-dashboard-server.R
deck_analytics <- reactive({
  # Single query for all deck data: entries, wins, meta share, colors
  # Replaces 5+ separate queries
}) |> bindCache(input$dashboard_format, input$dashboard_event_type, rv$current_scene, rv$data_refresh)

core_metrics <- reactive({
  # Tournament + player counts in one query
}) |> bindCache(input$dashboard_format, input$dashboard_event_type, rv$current_scene, rv$data_refresh)
```

Downstream outputs read from these batch reactives instead of running their own queries.

### Output Caching (bindCache)

All major public tab outputs use `bindCache()` to avoid redundant computation across sessions:

| Tab | Outputs Cached | Cache Keys |
|-----|---------------|------------|
| Dashboard | 14 outputs (charts, tables, value boxes) | format, event_type, scene, community, dark_mode, data_refresh |
| Players | `player_standings` | format, search, min_events, scene, community, data_refresh |
| Meta | `archetype_stats` | format, search, min_entries, scene, community, data_refresh |
| Tournaments | `tournament_history` | format, event_type, search, scene, community, data_refresh |
| Stores | `store_list`, `stores_cards_content`, `online_stores_section`, `stores_map` | scene, community, dark_mode (map only), data_refresh |

**Key pattern:** Always include `rv$data_refresh` as a cache key — this reactive value increments whenever admin operations modify data, busting the cache. Include `input$dark_mode` for any output that renders differently in light/dark mode (charts, maps).

### Community vs Format Filters (v0.23+)

Dashboard has two filter modes:
- **Format filters** (`build_dashboard_filters`): format + event_type + scene — used for Top Decks, Meta Diversity, Conversion, Color Distribution, Meta Share
- **Community filters** (`build_community_filters`): scene-only — used for Rising Stars, Player Attendance, Player Growth, Recent Tournaments, Top Players

### Rating Snapshots (v0.23+)

Historical format ratings are frozen as snapshots at era boundaries:

```r
# R/ratings.R — key functions
calculate_competitive_ratings(db_con, format_filter = NULL, date_cutoff = NULL)
generate_format_snapshot(db_con, format_id, end_date)
backfill_rating_snapshots(db_con)
```

- `rating_snapshots` table stores per-player ratings frozen at the end of each format era
- Players tab checks if selected format is historical via `get_latest_format_id()` reactive
- If historical and snapshots exist, shows snapshot ratings; otherwise falls back to live cache

### Pill Toggle Component (v0.23+)

Custom JS/CSS pill toggle for filter controls (no shinyWidgets dependency):

```r
# UI (in views/*.R)
div(
  class = "pill-toggle",
  `data-input-id` = "players_min_events",
  tags$button("All", class = "pill-option", `data-value` = "0"),
  tags$button("5+", class = "pill-option active", `data-value` = "5"),
  tags$button("10+", class = "pill-option", `data-value` = "10")
)

# Server reset
session$sendCustomMessage("resetPillToggle", list(inputId = "players_min_events", value = "5"))
```

JS in `www/pill-toggle.js` handles click events and `Shiny.setInputValue()`.

### Auto-Reconnection (v0.23+)

`safe_query()` now detects stale connections and auto-reconnects:

```r
safe_query <- function(con, query, ...) {
  # If connection invalid, reconnect via connect_db()
  # Updates rv$db_con and retries the query
}
```

---

## CSS Architecture

### File Organization

All custom styles are in `www/custom.css` (~3,500 lines), organized into clearly labeled sections:

```
/* =============================================================================
   SECTION NAME
   ============================================================================= */
```

**Major Sections:**
| Section | Purpose |
|---------|---------|
| APP HEADER | Top header bar with logo, title, BETA badge |
| SIDEBAR NAVIGATION | Left nav menu styling |
| DASHBOARD TITLE STRIP | Filter controls row on dashboard |
| PAGE TITLE STRIPS | Filter controls for other pages |
| VALUE BOXES | Digital-themed stat boxes |
| CARDS / FEATURE CARDS | Card container styling |
| TABLES | Reactable table overrides |
| MODAL STAT BOXES | Stats display in modals |
| PLACEMENT COLORS | Gold/silver/bronze for 1st/2nd/3rd |
| DECK COLOR UTILITIES | Color badges for deck types |
| ADMIN DECK MANAGEMENT | Card search grid, preview containers |
| MOBILE UI IMPROVEMENTS | Responsive breakpoints |
| APP-WIDE LOADING SCREEN | "Opening Digital Gate..." overlay |
| DIGITAL EMPTY STATES | Scanner aesthetic for empty data |

### Naming Conventions

**Component-based naming:**
```css
/* Component */
.card-search-grid { }
.card-search-item { }
.card-search-thumbnail { }

/* State modifiers with -- */
.store-filter-badge--success { }
.store-filter-badge--info { }

/* Utility classes */
.clickable-row { cursor: pointer; }
.help-icon { cursor: help; }
.map-container-flush { padding: 0; }
```

**Color classes for decks:**
```css
.deck-badge-red { }
.deck-badge-blue { }
.deck-badge-yellow { }
.deck-badge-green { }
.deck-badge-black { }
.deck-badge-purple { }
.deck-badge-white { }
```

### When to Use CSS Classes vs Inline Styles

**Use CSS classes for:**
- Reusable styles (buttons, badges, containers)
- Complex styles (multiple properties)
- Responsive styles (media queries needed)
- Themed elements (colors, shadows, animations)

**Keep inline styles for:**
- JavaScript-toggled visibility (`style = if (condition) "" else "display: none;"`)
- Dynamic values from R (`style = sprintf("background-color: %s;", color)`)
- One-off positioning tweaks

**Examples in R code:**
```r
# Good - use CSS class
div(class = "clickable-row", ...)
tags$img(class = "deck-modal-image", src = url)

# Acceptable - dynamic/conditional inline
div(style = if (show) "" else "display: none;", ...)
span(style = sprintf("color: %s;", deck_color), deck_name)
```

### Adding New Styles

1. Find the appropriate section in `www/custom.css`
2. Add styles with clear comments if non-obvious
3. Use existing naming patterns (component-based, `--` for modifiers)
4. Test in both light and dark mode
5. Test on mobile viewport

---

## Quick Reference

### File Locations

| What | Where |
|------|-------|
| Main app entry | `app.R` |
| Server modules | `server/*.R` |
| UI views | `views/*.R` |
| Helper functions | `R/*.R` |
| Database schema | `db/schema.sql` |
| Custom CSS | `www/custom.css` |
| Brand config | `_brand.yml` |

### Common Patterns Cheatsheet

```r
# Navigation
nav_select("main_content", "tab_id")
rv$current_nav <- "tab_id"
session$sendCustomMessage("updateSidebarNav", "nav_tab_id")

# Trigger refresh
rv$data_refresh <- (rv$data_refresh %||% 0) + 1

# Show modal
showModal(modalDialog(title = "Title", ..., footer = modalButton("Close")))

# Check admin (Enter Results, Edit Tournaments, Edit Players, Edit Decks)
req(rv$is_admin)

# Check superadmin (Edit Stores, Edit Formats)
req(rv$is_superadmin)

# Check DB connection
req(rv$db_con)
if (!dbIsValid(rv$db_con)) return(NULL)
```
