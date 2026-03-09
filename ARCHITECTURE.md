# DigiLab Architecture

Technical reference for the DigiLab codebase. Consult this document before adding new server modules, reactive values, or modifying core patterns.

**Last Updated:** March 2026 (v1.5.0-dev)

> **Note:** Always keep this document in sync with code changes. Update when adding new reactive values, server modules, or patterns.

---

## Table of Contents

1. [Server Module Structure](#server-module-structure)
2. [Mobile Views](#mobile-views)
3. [Reactive Values Reference](#reactive-values-reference)
4. [Navigation Patterns](#navigation-patterns)
5. [Modal Patterns](#modal-patterns)
6. [Database Patterns](#database-patterns)

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

## Mobile Views

### Device Detection (v1.3.0)

JS detects device type on page load and sends to Shiny via `Shiny.setInputValue('device_info', ...)`. The `is_mobile()` reactive in `shared-server.R` drives conditional rendering:

```r
is_mobile <- reactive({
  info <- input$device_info
  if (is.null(info)) return(FALSE)
  info$type == "mobile"
})
```

- **Breakpoint:** 768px (matches CSS mobile threshold)
- **Single detect on load** — no resize listener, no rotation handling
- **Defaults to desktop** if JS hasn't fired

### Conditional Rendering Pattern

Each public page uses `uiOutput` in `app.R` and `renderUI` in its server module to source either the desktop or mobile view:

```r
# In app.R
nav_panel_hidden(value = "overview", uiOutput("dashboard_page"))

# In public-dashboard-server.R
output$dashboard_page <- renderUI({
  if (is_mobile()) {
    source("views/mobile-dashboard-ui.R", local = TRUE)$value
  } else {
    dashboard_ui  # pre-loaded desktop view object
  }
})
```

Server logic (data reactives, click handlers, modals) is shared — both layouts bind to the same output IDs.

### Mobile View Files

```
views/
├── mobile-dashboard-ui.R      # Value boxes, charts, horizontal scroll cards
├── mobile-players-ui.R        # Stacked player cards with load-more
├── mobile-meta-ui.R           # Deck archetype cards with load-more
├── mobile-tournaments-ui.R    # Tournament cards with load-more
├── mobile-stores-ui.R         # Compact 200px map + store cards
```

### Mobile CSS

`www/mobile.css` contains mobile-only component styles (card lists, horizontal scroll, compact map, section headers). Existing `www/custom.css` media queries serve as fallback before JS detection fires.

### Mobile-Aware Charts

Some Highcharts conditionally adjust for mobile:
- `is_mobile()` can be used in `renderHighchart` to hide legends (`enabled = !is_mobile()`), axis titles (`text = if (is_mobile()) "" else "Label"`), or adjust chart heights.

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
| `admin_decklist_results` | data.frame | Results for post-submit decklist entry (Step 3) |
| `admin_decklist_tournament_id` | integer | Tournament ID for decklist entry |

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
| `submit_decklist_results` | data.frame | Results for post-submit decklist entry (Step 3) |
| `submit_decklist_tournament_id` | integer | Tournament ID for decklist entry |

**Edit Tournaments** (prefix: `edit_`, declared in `admin-tournaments-server.R`):

| Name | Type | Description |
|------|------|-------------|
| `edit_grid_data` | data.frame | Grid rows for editing existing results |
| `edit_record_format` | string | "points" or "wlt" (read from DB) |
| `edit_player_matches` | list | Player match status per row |
| `edit_deleted_result_ids` | integer[] | Result IDs marked for DB deletion |
| `edit_grid_tournament_id` | integer | Tournament being edited in grid |
| `edit_decklist_results` | data.frame | Results for post-save decklist entry |
| `edit_decklist_tournament_id` | integer | Tournament ID for decklist entry |

### Refresh Triggers

Pattern: `{scope}_refresh` - increment to trigger reactive invalidation.

| Name | Type | Description |
|------|------|-------------|
| `data_refresh` | integer | Global refresh for all public tables |
| `results_refresh` | integer | Refresh results table in wizard |
| `format_refresh` | integer | Refresh format dropdowns |
| `tournament_refresh` | integer | Refresh tournament tables |
| `schedules_refresh` | integer | Refresh store schedules table in admin |
| `requests_refresh` | integer | Refresh admin notification bar counts |

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

### Page-Load Modal Priority (Welcome → Announcement → Version)

On each page load, **one** modal may appear. Priority order:

1. **Welcome modal** — first-time visitors (no `digilab_onboarding_complete` in storage)
2. **Announcement modal** — latest active, unexpired announcement the user hasn't seen (from `announcements` table)
3. **Version changelog modal** — `APP_VERSION` differs from user's stored `digilab_last_seen_version`

Logic lives in `observeEvent(input$scene_from_storage)` in `server/scene-server.R`. Storage tracking uses the postMessage bridge (`www/scene-selector.js`).

**On minor releases (x.x.X):** No action needed. Patch bumps don't trigger the version modal — only update `APP_VERSION` in `app.R`.

**On feature releases (x.X.0):** Two required steps:

1. **Bump `APP_VERSION`** in `app.R` (line 30)
2. **Update `version_changelog_content()`** in `server/scene-server.R` — replace the items with 3-5 highlights for the new release. Each item is:
   ```r
   div(class = "version-changelog-item",
     bsicons::bs_icon("icon-name", class = "text-color"),
     span("Short description of the feature")
   )
   ```
   Icon classes: `text-warning` (orange), `text-info` (cyan), `text-primary` (blue), `text-success` (green), `text-danger` (red). Browse icons at icons.getbootstrap.com.

**Announcements** (admin-created via Scenes tab) are separate — they can be pushed anytime without a code release for ad-hoc messages like "new scenes added" or "maintenance tonight".

---

## Database Patterns

### Connection Handling

Uses Neon PostgreSQL via the `pool` package. `db_pool` is created once at app startup and shared across all sessions:

```r
# All queries use the shared pool — no manual connect/disconnect
data <- safe_query(db_pool, "SELECT * FROM players WHERE player_id = $1",
                   params = list(player_id), default = data.frame())
```

### Refresh Pattern

When admin makes changes, trigger refresh so public views update:

```r
# After INSERT/UPDATE/DELETE
rv$data_refresh <- (rv$data_refresh %||% 0) + 1

# In public view reactive
reactive({
  rv$data_refresh  # React to changes
  safe_query(db_pool, "...")
})
```

### Parameterized Queries

Always use parameterized queries with `$1, $2, $3` numbered placeholders (RPostgres style):

```r
# Correct
safe_query(db_pool, "SELECT * FROM players WHERE player_id = $1",
           params = list(player_id), default = data.frame())

# WRONG - SQL injection risk
dbGetQuery(db_pool, paste0("SELECT * FROM players WHERE player_id = ", player_id))
```

### safe_query / safe_execute (v0.21.1+, refactored v1.5.0)

**All DB calls** should use wrappers — never raw `dbGetQuery`/`dbExecute` (except inside transaction blocks).

**Two tiers:**
- `safe_query()` / `safe_execute()` — defined in `shared-server.R`, add session-level Sentry context tags. Use in all `server/` files.
- `safe_query_impl()` / `safe_execute_impl()` — defined in `R/safe_db.R`, available globally. Use in `R/` utility files (`ratings.R`, `admin_grid.R`).

Both provide: prepared statement retry logic, Sentry error reporting, slow query logging (>200ms), graceful defaults on error.

```r
# In server/ files (session-scoped Sentry tags)
result <- safe_query(db_pool, "SELECT * FROM players WHERE player_id = $1",
                     params = list(player_id),
                     default = data.frame(player_id = integer()))

rows <- safe_execute(db_pool, "UPDATE players SET name = $1 WHERE player_id = $2",
                     params = list(name, player_id))

# In R/ utility files (global scope, no session tags)
result <- safe_query_impl(db_con, "SELECT * FROM players", default = data.frame())
```

### Transaction Safety (v1.5.0)

Multi-statement operations use `pool::localCheckout()` + BEGIN/COMMIT/ROLLBACK for atomicity. Inside transaction blocks, use raw `DBI::` calls — **not** `safe_query`/`safe_execute` (retry logic would break the transaction by grabbing a different connection).

```r
conn <- pool::localCheckout(db_pool)
# Transaction block: raw DBI calls intentional (retry would break atomicity)
DBI::dbExecute(conn, "BEGIN")
tryCatch({
  DBI::dbExecute(conn, "INSERT INTO tournaments ...", params = list(...))
  DBI::dbExecute(conn, "INSERT INTO results ...", params = list(...))
  DBI::dbExecute(conn, "COMMIT")
}, error = function(e) {
  tryCatch(DBI::dbExecute(conn, "ROLLBACK"), error = function(re) NULL)
  stop(e)  # re-throw to outer handler
})
```

**Transaction locations:** Enter Results submit (`admin-results-server.R`), Edit Tournament save and Delete Tournament (`admin-tournaments-server.R`), Submit Results and Match History submit (`public-submit-server.R`), Materialized view refresh (`shared-server.R`).

Outside of transactions, `safe_execute()` remains the correct choice — it prevents one failed write from crashing the session.

### Deferred Rating Recalculation (v1.5.0)

Rating recalculation is the heaviest operation in the app. All call sites use `later::later()` to defer it so the UI updates immediately:

```r
later::later(function() {
  ratings_ok <- recalculate_ratings_cache(db_pool)
  if (!isTRUE(ratings_ok)) {
    notify("Ratings failed to update.", type = "warning", duration = 8)
  }
}, delay = 0.5)
```

The only exception is the startup check in `shared-server.R` which runs synchronously.

### Lazy-Loaded Admin UI (v1.0+)

Admin views are lazy-loaded via `renderUI()` after login. Any `observe` block in an admin server module that calls `updateSelectInput()` must include `rv$current_nav` as a reactive dependency. Without it, the update fires before the input exists in the DOM and gets silently dropped.

```r
observe({
  rv$current_nav  # Re-fires when user navigates to this tab
  req(rv$db_con, rv$is_admin)
  updateSelectInput(session, "my_dropdown", choices = ...)
})
```

### Materialized Views (v1.5.0+)

All 5 public tabs read from materialized views instead of multi-table JOINs. Views are stored at per-store grain with scene/country/state/online columns for flexible filtering.

| View | Source Tabs | Grain |
|------|------------|-------|
| `mv_player_store_stats` | Players | player + store + format + archetype |
| `mv_archetype_store_stats` | Meta, Dashboard | archetype + store + format + week |
| `mv_tournament_list` | Tournaments, Dashboard | tournament (1 row per tournament) |
| `mv_store_summary` | Stores | store (1 row per active store) |
| `mv_dashboard_counts` | (mostly unused) | scene + format + event_type |

**Refresh:** `refresh_materialized_views(pool)` in `shared-server.R` runs non-concurrent `REFRESH MATERIALIZED VIEW` on all 5 views. Triggered by:
- `rv$data_refresh` observer (fires after any admin mutation)
- `sync_limitless.py` (after online tournament sync)

**Startup guard:** `mv_views_exist(pool)` checks if MVs are available. If not, the app can fall back to direct table queries.

**Query pattern:**
```r
filters <- build_mv_filters(format = input$format, scene = rv$current_scene)
result <- safe_query(db_pool, sprintf("
  SELECT archetype_name, SUM(entries) as total
  FROM mv_archetype_store_stats
  WHERE 1=1 %s
  GROUP BY archetype_name
", filters$sql), params = filters$params)
```

**Important:** Never `SUM()` pre-aggregated `COUNT(DISTINCT)` columns across groups — entities spanning multiple groups get double-counted. Use `COUNT(DISTINCT)` at query time instead, or query from a view with the right grain (e.g., `mv_tournament_list` for tournament/player counts).

### build_mv_filters() Helper (v1.5.0+)

Generates WHERE clauses for flat materialized view queries. Unlike `build_filters_param()`, no table aliases or JOINs are needed because MVs are flat tables with all filter columns inline.

```r
filters <- build_mv_filters(
  format = input$format,           # Format filter value
  event_type = input$event_type,   # Event type filter
  scene = rv$current_scene,        # Scene slug
  community_store = rv$community_store,  # Single-store filter (future)
  search = input$search,           # Text search
  search_column = "display_name",  # Column to search
  start_idx = 1,                   # Starting param index ($1, $2, ...)
  alias = NULL                     # Optional table alias (for CTEs)
)
# Returns: list(sql = "AND format = $1 AND scene_id = ...", params = list(...), next_idx = 3)
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

### Prepared Statement Retry (v0.21.1+)

`safe_query`/`safe_execute` detect stale prepared statement errors from pool connection reuse and retry once with a fresh connection:

```r
# Errors matching these patterns trigger a single retry:
# "prepared statement", "bind message supplies", "needs to be bound",
# "multiple queries.*same column", "invalid input syntax"
```

---

## CSS Architecture

### File Organization

Custom styles are split across two files:
- `www/custom.css` (~3,600 lines) — all desktop and responsive styles, organized into labeled sections
- `www/mobile.css` (~200 lines) — mobile-only component styles (card lists, horizontal scroll, compact map)

`custom.css` sections:

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
| UI views (desktop) | `views/*.R` |
| UI views (mobile) | `views/mobile-*.R` |
| Helper functions | `R/*.R` |
| Database schema | `db/schema.sql` |
| Custom CSS | `www/custom.css` |
| Mobile CSS | `www/mobile.css` |
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
