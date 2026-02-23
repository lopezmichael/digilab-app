# Performance Optimizations Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce per-session overhead by lazy-loading admin UI and caching public tab outputs.

**Architecture:** Two independent changes: (1) Replace static admin `nav_panel_hidden` content with `uiOutput()` placeholders rendered server-side after auth, and (2) append `|> bindCache(...)` to 7 public tab outputs following the same pattern used on the Dashboard tab.

**Tech Stack:** R Shiny, bslib `nav_panel_hidden`, `bindCache()`

---

### Task 1: Lazy Admin UI — Replace static admin view sources with uiOutput placeholders

**Files:**
- Modify: `app.R:380-387` (remove admin view sources from UI section)
- Modify: `app.R:833-840` (replace admin_*_ui variables with uiOutput placeholders)
- Modify: `app.R:1028-1040` (add admin UI rendering alongside server module loading)

**Step 1: Remove admin view source calls from UI section**

In `app.R`, lines 380-387, remove these 8 lines:

```r
# REMOVE these lines:
source("views/admin-results-ui.R", local = TRUE)
source("views/admin-tournaments-ui.R", local = TRUE)
source("views/admin-decks-ui.R", local = TRUE)
source("views/admin-stores-ui.R", local = TRUE)
source("views/admin-formats-ui.R", local = TRUE)
source("views/admin-players-ui.R", local = TRUE)
source("views/admin-users-ui.R", local = TRUE)
source("views/admin-scenes-ui.R", local = TRUE)
```

**Step 2: Replace admin nav panels with uiOutput placeholders**

In `app.R`, lines 833-840, replace the admin UI variable references with `uiOutput()` calls:

```r
# BEFORE:
nav_panel_hidden(value = "admin_results", admin_results_ui),
nav_panel_hidden(value = "admin_tournaments", admin_tournaments_ui),
nav_panel_hidden(value = "admin_decks", admin_decks_ui),
nav_panel_hidden(value = "admin_stores", admin_stores_ui),
nav_panel_hidden(value = "admin_formats", admin_formats_ui),
nav_panel_hidden(value = "admin_players", admin_players_ui),
nav_panel_hidden(value = "admin_users", admin_users_ui),
nav_panel_hidden(value = "admin_scenes", admin_scenes_ui),

# AFTER:
nav_panel_hidden(value = "admin_results", uiOutput("admin_results_ui")),
nav_panel_hidden(value = "admin_tournaments", uiOutput("admin_tournaments_ui")),
nav_panel_hidden(value = "admin_decks", uiOutput("admin_decks_ui")),
nav_panel_hidden(value = "admin_stores", uiOutput("admin_stores_ui")),
nav_panel_hidden(value = "admin_formats", uiOutput("admin_formats_ui")),
nav_panel_hidden(value = "admin_players", uiOutput("admin_players_ui")),
nav_panel_hidden(value = "admin_users", uiOutput("admin_users_ui")),
nav_panel_hidden(value = "admin_scenes", uiOutput("admin_scenes_ui")),
```

**Step 3: Add admin UI rendering in the lazy-load observer**

In `app.R`, inside the existing `observeEvent(rv$is_admin, { ... })` block (line 1028), add `source()` calls for admin views AND `renderUI` calls for each placeholder. The view files define variables like `admin_results_ui` which the `renderUI` outputs then reference:

```r
observeEvent(rv$is_admin, {
  if (rv$is_admin && !admin_modules_loaded()) {
    # Source admin UI views (defines admin_*_ui variables)
    source("views/admin-results-ui.R", local = TRUE)
    source("views/admin-tournaments-ui.R", local = TRUE)
    source("views/admin-decks-ui.R", local = TRUE)
    source("views/admin-stores-ui.R", local = TRUE)
    source("views/admin-formats-ui.R", local = TRUE)
    source("views/admin-players-ui.R", local = TRUE)
    source("views/admin-users-ui.R", local = TRUE)
    source("views/admin-scenes-ui.R", local = TRUE)

    # Render admin UI into placeholders
    output$admin_results_ui <- renderUI(admin_results_ui)
    output$admin_tournaments_ui <- renderUI(admin_tournaments_ui)
    output$admin_decks_ui <- renderUI(admin_decks_ui)
    output$admin_stores_ui <- renderUI(admin_stores_ui)
    output$admin_formats_ui <- renderUI(admin_formats_ui)
    output$admin_players_ui <- renderUI(admin_players_ui)
    output$admin_users_ui <- renderUI(admin_users_ui)
    output$admin_scenes_ui <- renderUI(admin_scenes_ui)

    # Source admin server modules
    source("server/admin-results-server.R", local = TRUE)
    source("server/admin-tournaments-server.R", local = TRUE)
    source("server/admin-decks-server.R", local = TRUE)
    source("server/admin-stores-server.R", local = TRUE)
    source("server/admin-formats-server.R", local = TRUE)
    source("server/admin-players-server.R", local = TRUE)
    source("server/admin-users-server.R", local = TRUE)
    source("server/admin-scenes-server.R", local = TRUE)
    admin_modules_loaded(TRUE)
  }
}, ignoreInit = TRUE)
```

**Step 4: Commit**

```bash
git add app.R
git commit -m "perf: lazy-load admin UI views behind authentication gate"
```

---

### Task 2: bindCache — Players tab

**Files:**
- Modify: `server/public-players-server.R:91` (add bindCache after renderReactable closing)

**Step 1: Add bindCache to player_standings**

At line 272, after the closing `})` of `output$player_standings <- renderReactable({`, pipe to `bindCache()`. Include all filter inputs that affect the output:

```r
# Line 272 BEFORE:
})

# Line 272 AFTER:
}) |> bindCache(
  input$players_format,
  players_search_debounced(),
  input$players_min_events,
  rv$current_scene,
  rv$community_filter,
  rv$data_refresh
)
```

Note: `players_search_debounced()` is included — unique searches create new cache entries, but repeated views of the same search (across sessions or back-navigation) will be cached. The scene/format keys are the high-value hits.

**Step 2: Commit**

```bash
git add server/public-players-server.R
git commit -m "perf: add bindCache to Players tab standings table"
```

---

### Task 3: bindCache — Meta tab

**Files:**
- Modify: `server/public-meta-server.R:16` (add bindCache after renderReactable closing)

**Step 1: Add bindCache to archetype_stats**

At line 109, after the closing `})` of `output$archetype_stats <- renderReactable({`, pipe to `bindCache()`:

```r
# Line 109 BEFORE:
})

# Line 109 AFTER:
}) |> bindCache(
  input$meta_format,
  meta_search_debounced(),
  input$meta_min_entries,
  rv$current_scene,
  rv$community_filter,
  rv$data_refresh
)
```

**Step 2: Commit**

```bash
git add server/public-meta-server.R
git commit -m "perf: add bindCache to Meta tab archetype stats table"
```

---

### Task 4: bindCache — Tournaments tab

**Files:**
- Modify: `server/public-tournaments-server.R:17` (add bindCache after renderReactable closing)

**Step 1: Add bindCache to tournament_history**

At line 121, after the closing `})` of `output$tournament_history <- renderReactable({`, pipe to `bindCache()`:

```r
# Line 121 BEFORE:
})

# Line 121 AFTER:
}) |> bindCache(
  input$tournaments_format,
  input$tournaments_event_type,
  tournaments_search_debounced(),
  rv$current_scene,
  rv$community_filter,
  rv$data_refresh
)
```

**Step 2: Commit**

```bash
git add server/public-tournaments-server.R
git commit -m "perf: add bindCache to Tournaments tab history table"
```

---

### Task 5: bindCache — Stores tab (4 outputs)

**Files:**
- Modify: `server/public-stores-server.R:218` (store_list)
- Modify: `server/public-stores-server.R:291` (stores_cards_content)
- Modify: `server/public-stores-server.R:759` (online_stores_section)
- Modify: `server/public-stores-server.R:970` (stores_map)

**Step 1: Add bindCache to store_list**

At line 288, after the closing `})` of `output$store_list <- renderReactable({`:

```r
}) |> bindCache(rv$current_scene, rv$community_filter, rv$data_refresh)
```

**Step 2: Add bindCache to stores_cards_content**

At line 324, after the closing `})` of `output$stores_cards_content <- renderUI({`:

```r
}) |> bindCache(rv$current_scene, rv$community_filter, rv$data_refresh)
```

**Step 3: Add bindCache to online_stores_section**

At line ~820 (after the closing `})` of `output$online_stores_section <- renderUI({`):

```r
}) |> bindCache(rv$current_scene, rv$data_refresh)
```

Note: no `rv$community_filter` — this output only shows when scene is "all" and doesn't filter by community.

**Step 4: Add bindCache to stores_map**

At the closing `})` of `output$stores_map <- renderMapboxgl({`:

```r
}) |> bindCache(rv$current_scene, rv$community_filter, input$dark_mode, rv$data_refresh)
```

Note: includes `input$dark_mode` since the map uses a digital theme that may vary.

**Step 5: Commit**

```bash
git add server/public-stores-server.R
git commit -m "perf: add bindCache to Stores tab (table, cards, online section, map)"
```

---

### Task 6: Verify app loads and all tabs work

**Step 1: Run syntax check**

```bash
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "tryCatch(source('app.R'), error = function(e) cat('ERROR:', e$message, '\n'))"
```

**Step 2: Manual verification**

Ask the user to run `shiny::runApp()` and verify:
1. Dashboard loads normally
2. Players tab loads and search/filters work
3. Meta tab loads with deck stats
4. Tournaments tab loads with history
5. Stores tab loads — table view, cards view, map, online section
6. Admin login works and admin tabs appear
7. All admin tabs render correctly after login

**Step 3: Final commit (if any fixes needed)**

---

### Task 7: Update profiling report and docs

**Files:**
- Modify: `docs/profiling-report.md` (mark optimizations as implemented)
- Modify: `ARCHITECTURE.md` (document lazy admin UI pattern and bindCache additions)

**Step 1: Update profiling report**

Add a section noting which optimizations were implemented and their expected impact.

**Step 2: Commit**

```bash
git add docs/profiling-report.md ARCHITECTURE.md
git commit -m "docs: update profiling report and architecture for performance optimizations"
```
