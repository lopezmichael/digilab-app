# =============================================================================
# Submit Results: Shared Server Logic
# Card picker, wizard navigation, tournament creation, duplicate detection,
# player matching, deck requests, submission, Step 3 decklists
# =============================================================================

# Load OCR module (needed by upload flow)
source("R/ocr.R")

# Initialize reactive values for the unified submit flow
rv$sr_active_method <- NULL        # "upload", "grid_entry", "match", "decklist"
rv$sr_submission_method <- NULL    # Tracks how data was entered for tournaments.submission_method
rv$sr_active_tournament_id <- NULL
rv$sr_grid_data <- NULL
rv$sr_record_format <- "points"
rv$sr_player_matches <- list()
rv$sr_deck_request_row <- NULL
rv$sr_decklist_results <- NULL
rv$sr_decklist_tournament_id <- NULL
rv$sr_refresh_trigger <- NULL
rv$sr_wlt_override <- FALSE

# Upload-specific
rv$sr_ocr_results <- NULL
rv$sr_uploaded_files <- NULL
rv$sr_parsed_count <- 0
rv$sr_total_players <- 0
rv$sr_ocr_row_indices <- NULL
rv$sr_ocr_pending_combined <- NULL
rv$sr_ocr_pending_total_players <- NULL
rv$sr_ocr_pending_total_rounds <- NULL
rv$sr_ocr_pending_parsed_count <- NULL

# =============================================================================
# Shared UI Helpers
# =============================================================================

# Render a "Player Found" info banner (used by match-by-match and decklist flows)
sr_player_found_ui <- function(player) {
  # Optionally look up home scene name
  scene_label <- NULL
  if (!is.null(player$player_id)) {
    scene_info <- tryCatch(
      safe_query(db_pool, "
        SELECT s.name FROM scenes s
        JOIN players p ON p.home_scene_id = s.scene_id
        WHERE p.player_id = $1
      ", params = list(player$player_id), default = data.frame()),
      error = function(e) data.frame()
    )
    if (nrow(scene_info) > 0 && !is.na(scene_info$name[1])) {
      scene_label <- scene_info$name[1]
    }
  }

  div(
    class = "admin-form-section",
    div(class = "admin-form-section-label",
      bsicons::bs_icon("person-check-fill"),
      "Player Found"
    ),
    div(
      class = "sr-player-found",
      bsicons::bs_icon("check-circle-fill", class = "sr-player-found-icon"),
      div(
        tags$strong(player$display_name),
        tags$span(class = "sr-player-found-id", paste0("#", player$member_number)),
        if (!is.null(scene_label)) tags$span(class = "sr-player-found-scene", scene_label)
      )
    )
  )
}

# =============================================================================
# Card Picker Click Handlers
# =============================================================================

observeEvent(input$sr_card_upload, {
  rv$sr_active_method <- "upload"
  shinyjs::hide("sr_method_picker")
  shinyjs::show("sr_wizard")
  shinyjs::show("sr_upload_section")
})

observeEvent(input$sr_card_grid_entry, {
  req(rv$is_admin)
  rv$sr_active_method <- "grid_entry"
  rv$sr_submission_method <- "manual_grid"
  shinyjs::hide("sr_method_picker")
  shinyjs::show("sr_wizard")
  shinyjs::hide("sr_upload_section")
})

observeEvent(input$sr_card_match, {
  rv$sr_active_method <- "match"
  shinyjs::hide("sr_method_picker")
  shinyjs::show("sr_match_section")
})

observeEvent(input$sr_card_decklist, {
  rv$sr_active_method <- "decklist"
  shinyjs::hide("sr_method_picker")
  shinyjs::show("sr_decklist_standalone")
})

# =============================================================================
# Back to Picker
# =============================================================================

sr_back_to_picker <- function() {
  shinyjs::hide("sr_wizard")
  shinyjs::hide("sr_match_section")
  shinyjs::hide("sr_decklist_standalone")
  shinyjs::show("sr_method_picker")

  # Reset wizard state
  shinyjs::show("sr_step1")
  shinyjs::hide("sr_step2")
  shinyjs::hide("sr_step3")
  shinyjs::hide("sr_upload_section")
  shinyjs::runjs("$('#sr_step1_indicator').addClass('active').removeClass('completed'); $('#sr_step2_indicator').removeClass('active completed'); $('#sr_step3_indicator').removeClass('active completed');")

  rv$sr_active_method <- NULL
  rv$sr_active_tournament_id <- NULL
  rv$sr_submission_method <- NULL
  rv$sr_grid_data <- NULL
  rv$sr_player_matches <- list()
  rv$sr_ocr_results <- NULL
  rv$sr_uploaded_files <- NULL
  rv$sr_ocr_row_indices <- NULL
  rv$sr_wlt_override <- FALSE
  rv$sr_duplicate_tournament <- NULL

  # Clear Step 3 / decklist state
  rv$sr_decklist_results <- NULL
  rv$sr_decklist_tournament_id <- NULL

  # Clear match-by-match state
  rv$sr_match_player <- NULL
  rv$sr_match_tournaments <- NULL
  rv$sr_match_selected_tournament <- NULL
  rv$sr_match_ocr_results <- NULL
  rv$sr_match_uploaded_file <- NULL
  rv$sr_match_parsed_count <- 0
  rv$sr_match_total_rounds <- 0
  rv$sr_match_candidates <- list()

  # Clear standalone decklist state
  rv$sr_decklist_standalone_player <- NULL
  rv$sr_decklist_standalone_tournaments <- NULL
  rv$sr_decklist_standalone_selected <- NULL
  rv$sr_decklist_standalone_results <- NULL
}

observeEvent(input$sr_back_to_picker, { sr_back_to_picker() })
observeEvent(input$sr_match_back_to_picker, {
  # Reset match wizard steps to initial state
  shinyjs::show("sr_match_step1")
  shinyjs::hide("sr_match_step2")
  shinyjs::runjs("$('#sr_match_step1_indicator').addClass('active').removeClass('completed'); $('#sr_match_step2_indicator').removeClass('active completed');")
  sr_back_to_picker()
})
observeEvent(input$sr_decklist_back_to_picker, { sr_back_to_picker() })

# =============================================================================
# Step 1: Dropdown Population
# =============================================================================

# Populate scene dropdown
observe({
  req("submit_results" %in% visited_tabs())

  choices <- get_grouped_scene_choices(db_pool, key_by = "id", include_online = FALSE)
  if (length(choices) == 0) { invalidateLater(500); return() }

  choices[["Online / Webcam"]] <- "online"

  current <- rv$current_scene
  selected <- ""
  if (!is.null(current) && current != "all") {
    scene_row <- safe_query(db_pool, "SELECT scene_id FROM scenes WHERE slug = $1",
                            params = list(current), default = data.frame())
    all_vals <- unlist(choices)
    if (nrow(scene_row) > 0 && as.character(scene_row$scene_id[1]) %in% all_vals) {
      selected <- as.character(scene_row$scene_id[1])
    } else if (current == "online") {
      selected <- "online"
    }
  }

  updateSelectInput(session, "sr_scene",
                    choices = c("Select scene..." = "", choices),
                    selected = selected)
})

# Populate store dropdown filtered by scene
observeEvent(input$sr_scene, {
  scene_val <- input$sr_scene
  if (is.null(scene_val) || scene_val == "") {
    updateSelectInput(session, "sr_store",
                      choices = c("Select scene first..." = ""))
    return()
  }

  if (scene_val == "online") {
    stores <- safe_query(db_pool, "
      SELECT store_id, name FROM stores
      WHERE is_active = TRUE AND is_online = TRUE
      ORDER BY name
    ", default = data.frame())
  } else {
    stores <- safe_query(db_pool, "
      SELECT store_id, name FROM stores
      WHERE is_active = TRUE AND scene_id = $1
      ORDER BY name
    ", params = list(as.integer(scene_val)), default = data.frame())
  }

  choices <- if (nrow(stores) > 0) setNames(stores$store_id, stores$name) else character()
  updateSelectInput(session, "sr_store",
                    choices = c("Select store..." = "", choices))
})

# Populate format dropdown
observe({
  req("submit_results" %in% visited_tabs())

  formats <- safe_query(db_pool, "
    SELECT format_id, display_name FROM formats
    WHERE is_active = TRUE
    ORDER BY release_date DESC, sort_order ASC
  ")
  if (nrow(formats) == 0) { invalidateLater(500); return() }
  choices <- setNames(formats$format_id, formats$display_name)
  updateSelectInput(session, "sr_format",
                    choices = c("Select format..." = "", choices))
})

# Hide date required hint when date is selected
observeEvent(input$sr_date, {
  date_valid <- !is.null(input$sr_date) && length(input$sr_date) > 0 && !anyNA(input$sr_date)
  if (date_valid) {
    shinyjs::hide("sr_date_required_hint")
    shinyjs::runjs("$('#sr_date').closest('.date-required').removeClass('date-required');")
  } else {
    shinyjs::show("sr_date_required_hint")
    shinyjs::runjs("$('#sr_date').closest('.shiny-date-input').addClass('date-required');")
  }
}, ignoreNULL = FALSE)

# Store request
observeEvent(input$sr_request_store, {
  show_store_request_modal()
})

# =============================================================================
# Step 1: Duplicate Tournament Detection
# =============================================================================

output$sr_duplicate_warning <- renderUI({
  req(input$sr_store, input$sr_store != "")
  req(input$sr_date, !is.na(input$sr_date))

  existing <- safe_query(db_pool, "
    SELECT t.tournament_id, t.event_type, t.player_count, s.name as store_name
    FROM tournaments t
    JOIN stores s ON t.store_id = s.store_id
    WHERE t.store_id = $1 AND t.event_date = $2
  ", params = list(as.integer(input$sr_store), as.character(input$sr_date)))

  if (nrow(existing) == 0) return(NULL)

  div(
    class = "alert alert-warning d-flex align-items-start gap-2 mt-2",
    bsicons::bs_icon("exclamation-triangle-fill", class = "flex-shrink-0 mt-1"),
    div(
      tags$strong("Tournament already exists for this store and date:"),
      tags$ul(
        class = "mb-0 mt-1",
        lapply(seq_len(nrow(existing)), function(i) {
          t <- existing[i, ]
          tags$li(sprintf("%s - %s (%d players)",
                          t$event_type, t$store_name, t$player_count))
        })
      ),
      tags$small(class = "text-muted d-block mt-1",
                 "If you're submitting a different event type (e.g., Local vs Regional), you can proceed.")
    )
  )
})

# =============================================================================
# Step 1 → Step 2 Transition
# =============================================================================

observeEvent(input$sr_step1_next, {
  # Validate required fields
  if (is.null(input$sr_store) || input$sr_store == "") {
    notify("Please select a store", type = "error"); return()
  }
  if (is.null(input$sr_date) || is.na(input$sr_date)) {
    notify("Please select a date", type = "error"); return()
  }
  if (is.null(input$sr_event_type) || input$sr_event_type == "") {
    notify("Please select an event type", type = "error"); return()
  }
  if (is.null(input$sr_format) || input$sr_format == "") {
    notify("Please select a format", type = "error"); return()
  }
  player_count <- as.integer(input$sr_players %||% 8)
  if (is.null(player_count) || is.na(player_count) || player_count < 2) {
    notify("Player count must be at least 2", type = "error"); return()
  }

  method <- rv$sr_active_method %||% "unknown"
  record_fmt <- if (isTRUE(rv$is_admin)) (input$sr_record_format %||% "points") else "points"
  rv$sr_record_format <- record_fmt

  if (method == "upload") {
    # Upload: process files (handled in submit-upload-server.R)
    # The upload server observes sr_step1_next and handles OCR/CSV processing
    return()
  }

  # For grid entry: create tournament and show grid
  # Check for exact duplicate (same store + date + event_type)
  existing <- safe_query(db_pool, "
    SELECT t.tournament_id, t.player_count, t.event_type,
           (SELECT COUNT(*) FROM results WHERE tournament_id = t.tournament_id) as result_count,
           s.name as store_name
    FROM tournaments t
    JOIN stores s ON t.store_id = s.store_id
    WHERE t.store_id = $1 AND t.event_date = $2 AND t.event_type = $3
  ", params = list(as.integer(input$sr_store), as.character(input$sr_date), input$sr_event_type),
  default = data.frame())

  if (nrow(existing) > 0) {
    rv$sr_duplicate_tournament <- existing[1, ]

    output$sr_duplicate_message <- renderUI({
      div(
        p(sprintf("A %s tournament at %s on %s already exists:",
                  existing$event_type[1], existing$store_name[1],
                  format(as.Date(as.character(input$sr_date)), "%B %d, %Y"))),
        tags$ul(
          tags$li(sprintf("%d players expected", existing$player_count[1])),
          tags$li(sprintf("%d results entered", as.integer(existing$result_count[1])))
        ),
        p("What would you like to do?")
      )
    })

    footer_btns <- if (isTRUE(rv$is_admin)) {
      tagList(
        actionButton("sr_edit_existing", "View/Edit Existing", class = "btn-outline-primary"),
        actionButton("sr_create_anyway", "Create Anyway", class = "btn-warning"),
        modalButton("Cancel")
      )
    } else {
      tagList(
        actionButton("sr_view_existing", "View Results", class = "btn-outline-primary"),
        modalButton("Cancel")
      )
    }

    showModal(modalDialog(
      title = "Possible Duplicate Tournament",
      uiOutput("sr_duplicate_message"),
      footer = footer_btns,
      easyClose = TRUE
    ))
    return()
  }

  sr_create_tournament_and_show_grid()
})

# Handle duplicate modal buttons
observeEvent(input$sr_edit_existing, {
  req(rv$sr_duplicate_tournament)
  removeModal()
  rv$navigate_to_tournament_id <- rv$sr_duplicate_tournament$tournament_id
  nav_select("main_content", "admin_tournaments")
  rv$current_nav <- "admin_tournaments"
  session$sendCustomMessage("updateSidebarNav", "nav_admin_tournaments")
})

observeEvent(input$sr_view_existing, {
  req(rv$sr_duplicate_tournament)
  removeModal()
  nav_select("main_content", "tournaments")
  rv$current_nav <- "tournaments"
  session$sendCustomMessage("updateSidebarNav", "nav_tournaments")
})

observeEvent(input$sr_create_anyway, {
  removeModal()
  rv$sr_duplicate_tournament <- NULL
  sr_create_tournament_and_show_grid()
})

# =============================================================================
# Tournament Creation & Grid Init
# =============================================================================

sr_create_tournament_and_show_grid <- function() {
  store_id <- as.integer(input$sr_store)
  if (is.na(store_id)) { notify("Invalid store selection", type = "error"); return() }
  event_date <- as.character(input$sr_date)
  event_type <- input$sr_event_type
  format_val <- input$sr_format
  player_count <- as.integer(input$sr_players %||% 8)
  rounds <- as.integer(input$sr_rounds %||% 4)
  record_fmt <- rv$sr_record_format

  submit_by_grid <- if (isTRUE(rv$is_admin)) current_admin_username(rv) else "public_submit"
  tryCatch({
    result <- safe_query(db_pool, "
      INSERT INTO tournaments (store_id, event_date, event_type, format, player_count, rounds, record_format, updated_by)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      RETURNING tournament_id
    ", params = list(store_id, event_date, event_type, format_val, player_count, rounds, record_fmt, submit_by_grid),
    default = data.frame(tournament_id = integer(0)))
    new_id <- result$tournament_id[1]

    rv$sr_active_tournament_id <- new_id
    rv$sr_grid_data <- init_grid_data(player_count)
    rv$sr_player_matches <- list()

    # Cache static values for Step 2 summary bar (avoid re-querying on every render)
    store <- safe_query(db_pool, "SELECT name FROM stores WHERE store_id = $1",
                        params = list(store_id))
    rv$sr_store_name <- if (nrow(store) > 0) store$name[1] else "Not selected"
    fmt <- safe_query(db_pool, "SELECT display_name FROM formats WHERE format_id = $1",
                      params = list(format_val))
    rv$sr_format_name <- if (nrow(fmt) > 0) fmt$display_name[1] else ""
    rv$sr_deck_choices <- build_deck_choices(db_pool)

    notify("Tournament created!", type = "message")

    # Show Step 2
    shinyjs::hide("sr_step1")
    shinyjs::show("sr_step2")
    shinyjs::runjs("$('#sr_step1_indicator').removeClass('active').addClass('completed'); $('#sr_step2_indicator').addClass('active');")

  }, error = function(e) {
    if (sentry_enabled) tryCatch(sentryR::capture_exception(e, tags = sentry_context_tags()), error = function(se) NULL)
    notify(paste("Error:", e$message), type = "error")
  })
}

# =============================================================================
# Step 2: Grid Rendering
# =============================================================================

output$sr_step2_content <- renderUI({
  req(rv$sr_grid_data)
  rv$sr_refresh_trigger  # Re-render when deck choices change

  grid <- rv$sr_grid_data
  record_format <- rv$sr_record_format %||% "points"
  is_admin <- isTRUE(rv$is_admin)

  # Check if release event
  is_release <- !is.null(input$sr_event_type) && input$sr_event_type == "release_event"

  # Use cached values (set when entering Step 2) — avoid re-querying on every render
  deck_choices <- rv$sr_deck_choices %||% build_deck_choices(db_pool)
  store_name <- rv$sr_store_name %||% "Not selected"
  format_name <- rv$sr_format_name %||% ""

  summary_bar <- div(
    class = "tournament-summary-bar mb-3",
    div(
      class = "summary-bar-content",
      div(class = "summary-item", bsicons::bs_icon("shop"), span(store_name)),
      div(class = "summary-item", bsicons::bs_icon("calendar"),
          span(format(input$sr_date, "%b %d, %Y"))),
      div(class = "summary-item", bsicons::bs_icon("controller"), span(input$sr_event_type)),
      div(class = "summary-item", bsicons::bs_icon("tag"), span(format_name)),
      div(class = "summary-item", bsicons::bs_icon("people"), span(nrow(grid), " players")),
      div(class = "summary-item", bsicons::bs_icon("flag"), span(input$sr_rounds, " rounds"))
    )
  )

  # OCR summary badges (upload mode)
  match_summary <- NULL
  if (identical(rv$sr_active_method, "upload") && !is.null(rv$sr_ocr_results)) {
    results <- rv$sr_ocr_results
    matched_count <- sum(results$match_status == "matched", na.rm = TRUE)
    similar_count <- sum(results$match_status == "new_similar", na.rm = TRUE)
    new_count <- sum(results$match_status == "new", na.rm = TRUE)

    match_summary <- div(
      class = "match-summary-badges d-flex gap-2 mb-3",
      div(class = "match-badge match-badge--matched",
          bsicons::bs_icon("check-circle-fill"), span(class = "badge-count", matched_count), span(class = "badge-label", "Matched")),
      if (similar_count > 0) div(class = "match-badge match-badge--possible",
          bsicons::bs_icon("person-exclamation"), span(class = "badge-count", similar_count), span(class = "badge-label", "Similar")),
      div(class = "match-badge match-badge--new",
          bsicons::bs_icon("person-plus-fill"), span(class = "badge-count", new_count), span(class = "badge-label", "New"))
    )
  }

  # Instructions
  instructions <- div(
    class = "alert alert-primary d-flex mb-3",
    bsicons::bs_icon("pencil-square", class = "me-2 flex-shrink-0", size = "1.2em"),
    div(
      tags$strong("Review and edit the results"),
      tags$br(),
      tags$small("Check that player names and points are correct. ",
                 "Select a deck archetype for each player if known (optional). ",
                 "Click ", bsicons::bs_icon("x-circle"), " to remove a row.")
    )
  )

  # Player matching explanation
  match_info_text <- div(
    class = "text-muted small mb-3",
    bsicons::bs_icon("people", class = "me-1"),
    "Players are matched by member number first, then by username. ",
    tags$strong("Matched"), " = existing player. ",
    tags$strong("New"), " = will be created on submit."
  )

  # Record format badge
  format_label <- if (record_format == "points") "Points mode" else "W-L-T mode"
  filled <- sum(nchar(trimws(grid$player_name)) > 0)
  total <- nrow(grid)

  # W/L/T override toggle (admin only, points mode only)
  wlt_toggle <- NULL
  if (is_admin && record_format == "points") {
    wlt_toggle <- div(
      class = "form-check form-switch d-inline-block ms-3",
      tags$input(type = "checkbox", class = "form-check-input", id = "sr_wlt_override_toggle",
                 checked = if (isTRUE(rv$sr_wlt_override)) "checked" else NULL,
                 onchange = "Shiny.setInputValue('sr_wlt_override_toggle', this.checked, {priority: 'event'})"),
      tags$label(class = "form-check-label small", `for` = "sr_wlt_override_toggle", "Show W/L/T")
    )
  }

  # Grid card
  grid_card <- card(
    class = "mt-3",
    card_header(
      class = "d-flex justify-content-between align-items-center",
      div(
        class = "d-flex align-items-center gap-2",
        span("Player Results"),
        span(class = "badge bg-info", format_label),
        wlt_toggle
      ),
      div(
        class = "d-flex align-items-center gap-2",
        span(class = "text-muted small", sprintf("Filled: %d/%d", filled, total)),
        if (is_admin) actionButton("sr_paste_btn", "Paste from Spreadsheet",
                                    class = "btn-sm btn-outline-primary",
                                    icon = icon("clipboard")) else NULL
      )
    ),
    card_body(
      render_grid_ui(grid, record_format, is_release, deck_choices,
                     rv$sr_player_matches, "sr_",
                     mode = if (identical(rv$sr_active_method, "upload")) "review" else "entry",
                     ocr_rows = rv$sr_ocr_row_indices,
                     placement_editable = TRUE,
                     show_add_player_btn = TRUE,
                     show_wlt_override = isTRUE(rv$sr_wlt_override) && is_admin)
    )
  )

  # Confirmation checkbox (upload/public flow)
  confirm_section <- if (identical(rv$sr_active_method, "upload")) {
    div(
      class = "mt-3",
      checkboxInput("sr_confirm", "I confirm this data is accurate", value = FALSE)
    )
  } else NULL

  # Navigation buttons
  nav_buttons <- div(
    class = "d-flex justify-content-between mt-3",
    div(
      class = "d-flex gap-2",
      actionButton("sr_wizard_back", "Back to Details", class = "btn-secondary",
                   icon = icon("arrow-left")),
      if (!is.null(rv$sr_active_tournament_id) && isTRUE(rv$is_admin))
        actionButton("sr_clear_tournament", "Start Over", class = "btn-outline-warning",
                     icon = icon("rotate-left"))
      else NULL
    ),
    actionButton("sr_submit_results", "Submit Results", class = "btn-primary btn-lg",
                 icon = icon("check"))
  )

  tagList(summary_bar, match_summary, instructions, match_info_text, grid_card, confirm_section, nav_buttons)
})

# =============================================================================
# Step 2: Wizard Back
# =============================================================================

observeEvent(input$sr_wizard_back, {
  shinyjs::hide("sr_step2")
  shinyjs::show("sr_step1")
  shinyjs::runjs("$('#sr_step2_indicator').removeClass('active'); $('#sr_step1_indicator').addClass('active').removeClass('completed');")

  # Show upload section if in upload mode
  if (identical(rv$sr_active_method, "upload")) {
    shinyjs::show("sr_upload_section")
  }
})

# W/L/T override toggle
observeEvent(input$sr_wlt_override_toggle, {
  rv$sr_wlt_override <- isTRUE(input$sr_wlt_override_toggle)
  # Grid will re-render via sr_step2_content since rv$sr_wlt_override changed
})

# =============================================================================
# Grid Event Handlers (delegated, bound once)
# =============================================================================

# Bind delegated JS handlers once — these use $(document).on() so they
# automatically apply to dynamically rendered grid inputs.
# Placement uses 'blur' (not 'change') so users can finish typing before sort.
observeEvent(TRUE, once = TRUE, {
  shinyjs::runjs("
    $(document).on('blur', 'input[id^=\"sr_placement_\"]', function() {
      Shiny.setInputValue('sr_placement_blur', {ts: Date.now()}, {priority: 'event'});
    });
    $(document).on('blur', 'input[id^=\"sr_player_\"]', function() {
      var id = $(this).attr('id');
      var rowNum = parseInt(id.replace('sr_player_', ''));
      if (!isNaN(rowNum)) {
        Shiny.setInputValue('sr_player_blur', {row: rowNum, name: $(this).val(), ts: Date.now()}, {priority: 'event'});
      }
    });
  ")
})

# =============================================================================
# Placement Auto-Reorder (blur-based)
# =============================================================================

observeEvent(input$sr_placement_blur, {
  req(rv$sr_grid_data)

  # Sync all input values into the data frame (placement, name, points, deck, etc.)
  grid <- sync_grid_inputs(input, rv$sr_grid_data, rv$sr_record_format %||% "points", "sr_",
                           placement_editable = TRUE, wlt_override = isTRUE(rv$sr_wlt_override))
  grid$placement <- validate_placements(grid$placement)

  # Track original row indices before sort so we can remap player_matches keys
  old_order <- seq_len(nrow(grid))
  new_order <- order(grid$placement)

  # Only re-sort if order actually changed

  if (!identical(old_order, new_order)) {
    grid <- grid[new_order, ]
    rownames(grid) <- NULL

    # Remap sr_player_matches keys to new row positions
    old_matches <- rv$sr_player_matches
    new_matches <- list()
    for (new_idx in seq_along(new_order)) {
      old_idx <- new_order[new_idx]
      key <- as.character(old_idx)
      if (!is.null(old_matches[[key]])) {
        new_matches[[as.character(new_idx)]] <- old_matches[[key]]
      }
    }
    rv$sr_player_matches <- new_matches
  }

  rv$sr_grid_data <- grid
})

# =============================================================================
# Player Matching (blur-based, shared across all grid methods)
# =============================================================================

observeEvent(input$sr_player_blur, {
  req(db_pool, rv$sr_grid_data)

  info <- input$sr_player_blur
  row_num <- info$row
  name <- trimws(info$name)

  if (is.null(row_num) || is.na(row_num)) return()
  if (row_num < 1 || row_num > nrow(rv$sr_grid_data)) return()

  rv$sr_grid_data <- sync_grid_inputs(input, rv$sr_grid_data, rv$sr_record_format %||% "points", "sr_",
                                       placement_editable = TRUE, wlt_override = isTRUE(rv$sr_wlt_override))

  if (nchar(name) == 0) {
    rv$sr_player_matches[[as.character(row_num)]] <- NULL
    rv$sr_grid_data$match_status[row_num] <- ""
    rv$sr_grid_data$matched_player_id[row_num] <- NA_integer_
    rv$sr_grid_data$matched_member_number[row_num] <- NA_character_
    return()
  }

  member_num <- input[[paste0("sr_member_", row_num)]]
  scene_id <- get_store_scene_id(as.integer(input$sr_store), db_pool)
  match_info <- match_player(name, db_pool, member_number = member_num, scene_id = scene_id)
  rv$sr_player_matches[[as.character(row_num)]] <- match_info
  rv$sr_grid_data$match_status[row_num] <- match_info$status

  if (match_info$status == "matched") {
    rv$sr_grid_data$matched_player_id[row_num] <- match_info$player_id
    rv$sr_grid_data$matched_member_number[row_num] <- match_info$member_number
  } else if (match_info$status == "ambiguous") {
    if (isTRUE(rv$is_admin)) {
      # Admin: keep ambiguous status, show disambiguation badge
      rv$sr_grid_data$matched_player_id[row_num] <- match_info$candidates$player_id[1]
      rv$sr_grid_data$matched_member_number[row_num] <- match_info$candidates$member_number[1]
    } else {
      # Public: auto-select first candidate
      rv$sr_grid_data$match_status[row_num] <- "matched"
      rv$sr_grid_data$matched_player_id[row_num] <- match_info$candidates$player_id[1]
      rv$sr_grid_data$matched_member_number[row_num] <- match_info$candidates$member_number[1]
      rv$sr_player_matches[[as.character(row_num)]] <- list(
        status = "matched",
        player_id = match_info$candidates$player_id[1],
        member_number = match_info$candidates$member_number[1]
      )
    }
  } else {
    rv$sr_grid_data$matched_player_id[row_num] <- NA_integer_
    rv$sr_grid_data$matched_member_number[row_num] <- NA_character_
  }
})

# =============================================================================
# Disambiguation Picker Modal (admin only)
# =============================================================================

observeEvent(input$sr_disambiguate_row, {
  row_num <- input$sr_disambiguate_row
  req(row_num, rv$sr_player_matches)

  match_info <- rv$sr_player_matches[[as.character(row_num)]]
  req(match_info, match_info$status == "ambiguous")

  candidates <- match_info$candidates

  enriched <- safe_query(db_pool, "
    SELECT p.player_id, p.display_name, p.member_number, p.identity_status,
           sc.display_name as home_scene_name,
           COUNT(DISTINCT r.tournament_id) as events_played,
           MAX(t.event_date) as last_event,
           prc.competitive_rating as rating
    FROM players p
    LEFT JOIN scenes sc ON p.home_scene_id = sc.scene_id
    LEFT JOIN results r ON p.player_id = r.player_id
    LEFT JOIN tournaments t ON r.tournament_id = t.tournament_id
    LEFT JOIN player_ratings_cache prc ON p.player_id = prc.player_id
    WHERE p.player_id = ANY($1::int[])
    GROUP BY p.player_id, p.display_name, p.member_number, p.identity_status,
             sc.display_name, prc.competitive_rating
    ORDER BY COUNT(DISTINCT r.tournament_id) DESC
  ", params = list(paste0("{", paste(candidates$player_id, collapse = ","), "}")),
  default = candidates)

  candidate_choices <- lapply(seq_len(nrow(enriched)), function(i) {
    c <- enriched[i, ]
    member_text <- if (!is.na(c$member_number) && nchar(c$member_number) > 0) paste0(" \u2014 #", c$member_number) else ""
    scene_text <- if (!is.null(c$home_scene_name) && !is.na(c$home_scene_name)) paste0(" \u2014 ", c$home_scene_name) else ""
    events_text <- if (!is.null(c$events_played) && !is.na(c$events_played)) paste0(c$events_played, " events") else "0 events"
    rating_text <- if (!is.null(c$rating) && !is.na(c$rating)) paste0("Rating: ", c$rating) else ""
    last_text <- if (!is.null(c$last_event) && !is.na(c$last_event)) paste0("Last: ", c$last_event) else ""

    div(class = "disambiguate-candidate",
      tags$label(class = "d-flex align-items-start gap-2 p-2 rounded border mb-2",
        style = "cursor: pointer;",
        tags$input(type = "radio", name = "sr_disambiguate_choice",
                   value = as.character(c$player_id), class = "mt-1"),
        div(
          div(tags$strong(c$display_name), span(class = "text-muted small", member_text)),
          div(class = "small text-muted",
            paste(c(events_text, rating_text, last_text, scene_text), collapse = " | ")
          )
        )
      )
    )
  })

  showModal(modalDialog(
    title = tagList(bsicons::bs_icon("people-fill"), " Select Player"),
    p(class = "text-muted", sprintf("Multiple players match \"%s\". Select the correct one:",
      rv$sr_grid_data$player_name[row_num])),
    div(id = "sr_disambiguate_choices", candidate_choices),
    hr(),
    div(class = "d-flex align-items-center gap-2",
      tags$input(type = "radio", name = "sr_disambiguate_choice", value = "new", id = "sr_disambiguate_new"),
      tags$label(`for` = "sr_disambiguate_new", "None of these \u2014 create a new player")
    ),
    tags$script(HTML("
      $('#sr_disambiguate_confirm_btn').on('click', function() {
        var selected = $('input[name=sr_disambiguate_choice]:checked').val();
        if (selected) {
          Shiny.setInputValue('sr_disambiguate_confirm', {
            row: ", row_num, ",
            player_id: selected
          }, {priority: 'event'});
        }
      });
    ")),
    footer = tagList(
      modalButton("Cancel"),
      actionButton("sr_disambiguate_confirm_btn", "Confirm", class = "btn-primary")
    )
  ))
})

observeEvent(input$sr_disambiguate_confirm, {
  info <- input$sr_disambiguate_confirm
  row_num <- info$row
  selected_id <- info$player_id
  req(row_num, selected_id)

  if (selected_id == "new") {
    rv$sr_grid_data$match_status[row_num] <- "new"
    rv$sr_grid_data$matched_player_id[row_num] <- NA_integer_
    rv$sr_grid_data$matched_member_number[row_num] <- NA_character_
    rv$sr_player_matches[[as.character(row_num)]] <- list(status = "new")
  } else {
    pid <- as.integer(selected_id)
    player_info <- safe_query(db_pool, "SELECT member_number FROM players WHERE player_id = $1",
                              params = list(pid), default = data.frame(member_number = NA_character_))
    rv$sr_grid_data$match_status[row_num] <- "matched"
    rv$sr_grid_data$matched_player_id[row_num] <- pid
    rv$sr_grid_data$matched_member_number[row_num] <- player_info$member_number[1]
    rv$sr_player_matches[[as.character(row_num)]] <- list(
      status = "matched", player_id = pid, member_number = player_info$member_number[1]
    )
  }
  removeModal()
})

# =============================================================================
# "Did you mean?" Similar Player Modal
# =============================================================================

observeEvent(input$sr_similar_player_row, {
  row_num <- input$sr_similar_player_row
  req(row_num, rv$sr_player_matches)

  match_info <- rv$sr_player_matches[[as.character(row_num)]]
  req(match_info, match_info$status == "new_similar")

  candidates <- match_info$candidates

  enriched <- safe_query(db_pool, "
    SELECT p.player_id, p.display_name, p.member_number, p.identity_status,
           sc.display_name as home_scene_name,
           COUNT(DISTINCT r.tournament_id) as events_played,
           prc.competitive_rating as rating
    FROM players p
    LEFT JOIN scenes sc ON p.home_scene_id = sc.scene_id
    LEFT JOIN results r ON p.player_id = r.player_id
    LEFT JOIN player_ratings_cache prc ON p.player_id = prc.player_id
    WHERE p.player_id = ANY($1::int[])
    GROUP BY p.player_id, p.display_name, p.member_number, p.identity_status,
             sc.display_name, prc.competitive_rating
    ORDER BY COUNT(DISTINCT r.tournament_id) DESC
  ", params = list(paste0("{", paste(candidates$player_id, collapse = ","), "}")),
  default = candidates)

  sim_lookup <- setNames(candidates$sim, as.character(candidates$player_id))

  candidate_choices <- lapply(seq_len(nrow(enriched)), function(i) {
    c <- enriched[i, ]
    sim_pct <- round((sim_lookup[[as.character(c$player_id)]] %||% 0) * 100)
    member_text <- if (!is.na(c$member_number) && nchar(c$member_number) > 0) paste0(" \u2014 #", c$member_number) else ""
    scene_text <- if (!is.null(c$home_scene_name) && !is.na(c$home_scene_name)) paste0(" \u2014 ", c$home_scene_name) else ""
    events_text <- if (!is.null(c$events_played) && !is.na(c$events_played)) paste0(c$events_played, " events") else "0 events"
    rating_text <- if (!is.null(c$rating) && !is.na(c$rating)) paste0("Rating: ", c$rating) else ""

    div(class = "disambiguate-candidate",
      tags$label(class = "d-flex align-items-start gap-2 p-2 rounded border mb-2",
        style = "cursor: pointer;",
        tags$input(type = "radio", name = "sr_similar_choice",
                   value = as.character(c$player_id), class = "mt-1"),
        div(
          div(tags$strong(c$display_name),
              span(class = "badge bg-secondary ms-2", paste0(sim_pct, "% match")),
              span(class = "text-muted small", member_text)),
          div(class = "small text-muted",
            paste(c(events_text, rating_text, scene_text), collapse = " | ")
          )
        )
      )
    )
  })

  player_name <- rv$sr_grid_data$player_name[row_num]

  showModal(modalDialog(
    title = tagList(bsicons::bs_icon("person-exclamation"), " Did you mean?"),
    p(class = "text-muted", sprintf("\"%s\" wasn't found, but these similar players exist:", player_name)),
    div(id = "sr_similar_choices", candidate_choices),
    hr(),
    div(class = "d-flex align-items-center gap-2",
      tags$input(type = "radio", name = "sr_similar_choice", value = "new",
                 id = "sr_similar_new", checked = "checked"),
      tags$label(`for` = "sr_similar_new",
        tags$strong(sprintf("Create new player \"%s\"", player_name)))
    ),
    tags$script(HTML("
      $('#sr_similar_confirm_btn').on('click', function() {
        var selected = $('input[name=sr_similar_choice]:checked').val();
        if (selected) {
          Shiny.setInputValue('sr_similar_confirm', {
            row: ", row_num, ",
            player_id: selected
          }, {priority: 'event'});
        }
      });
    ")),
    footer = tagList(
      modalButton("Cancel"),
      actionButton("sr_similar_confirm_btn", "Confirm", class = "btn-primary")
    )
  ))
})

observeEvent(input$sr_similar_confirm, {
  info <- input$sr_similar_confirm
  row_num <- info$row
  selected_id <- info$player_id
  req(row_num, selected_id)

  if (selected_id == "new") {
    rv$sr_grid_data$match_status[row_num] <- "new"
    rv$sr_grid_data$matched_player_id[row_num] <- NA_integer_
    rv$sr_grid_data$matched_member_number[row_num] <- NA_character_
    rv$sr_player_matches[[as.character(row_num)]] <- list(status = "new")
  } else {
    pid <- as.integer(selected_id)
    player_info <- safe_query(db_pool, "SELECT member_number FROM players WHERE player_id = $1",
                              params = list(pid), default = data.frame(member_number = NA_character_))
    rv$sr_grid_data$match_status[row_num] <- "matched"
    rv$sr_grid_data$matched_player_id[row_num] <- pid
    rv$sr_grid_data$matched_member_number[row_num] <- player_info$member_number[1]
    rv$sr_player_matches[[as.character(row_num)]] <- list(
      status = "matched", player_id = pid, member_number = player_info$member_number[1]
    )
  }
  removeModal()
})

# =============================================================================
# Delete Row
# =============================================================================

observeEvent(input$sr_delete_row, {
  req(rv$sr_grid_data)

  row_idx <- as.integer(input$sr_delete_row)
  if (is.null(row_idx) || row_idx < 1 || row_idx > nrow(rv$sr_grid_data)) return()

  rv$sr_grid_data <- sync_grid_inputs(input, rv$sr_grid_data, rv$sr_record_format %||% "points", "sr_",
                                       placement_editable = TRUE, wlt_override = isTRUE(rv$sr_wlt_override))
  grid <- rv$sr_grid_data
  grid <- grid[-row_idx, ]

  if (nrow(grid) > 0) {
    grid$placement <- seq_len(nrow(grid))
  }

  # Shift player matches
  new_matches <- list()
  for (j in seq_len(nrow(grid))) {
    old_idx <- if (j < row_idx) j else j + 1
    if (!is.null(rv$sr_player_matches[[as.character(old_idx)]])) {
      new_matches[[as.character(j)]] <- rv$sr_player_matches[[as.character(old_idx)]]
    }
  }
  rv$sr_player_matches <- new_matches

  # Update OCR row indices
  if (!is.null(rv$sr_ocr_row_indices)) {
    rv$sr_ocr_row_indices <- setdiff(
      ifelse(rv$sr_ocr_row_indices > row_idx,
             rv$sr_ocr_row_indices - 1,
             rv$sr_ocr_row_indices),
      row_idx
    )
  }

  rv$sr_grid_data <- grid

  # Also update OCR results if they exist
  if (!is.null(rv$sr_ocr_results) && row_idx <= nrow(rv$sr_ocr_results)) {
    rv$sr_ocr_results <- rv$sr_ocr_results[-row_idx, ]
    if (nrow(rv$sr_ocr_results) > 0) {
      rv$sr_ocr_results$placement <- seq_len(nrow(rv$sr_ocr_results))
    }
  }

  notify(paste0("Row removed. Players renumbered 1-", nrow(grid), "."), type = "message", duration = 3)
})

# =============================================================================
# Add Player
# =============================================================================

observeEvent(input$sr_add_player, {
  req(rv$sr_grid_data)

  rv$sr_grid_data <- sync_grid_inputs(input, rv$sr_grid_data, rv$sr_record_format %||% "points", "sr_",
                                       placement_editable = TRUE, wlt_override = isTRUE(rv$sr_wlt_override))

  new_placement <- nrow(rv$sr_grid_data) + 1L
  blank_row <- data.frame(
    placement = new_placement,
    player_name = "", member_number = "",
    points = 0L, wins = 0L, losses = 0L, ties = 0L,
    deck_id = NA_integer_, match_status = "",
    matched_player_id = NA_integer_,
    matched_member_number = NA_character_,
    result_id = NA_integer_,
    stringsAsFactors = FALSE
  )
  # Add optional CSV-sourced columns if grid has them (from OCR/CSV upload)
  for (col in c("deck_url", "memo")) {
    if (col %in% names(rv$sr_grid_data)) blank_row[[col]] <- NA_character_
  }
  for (col in c("omw_pct", "oomw_pct")) {
    if (col %in% names(rv$sr_grid_data)) blank_row[[col]] <- NA_real_
  }
  rv$sr_grid_data <- rbind(rv$sr_grid_data, blank_row)
})

# =============================================================================
# Deck Request (shared across all grid methods)
# =============================================================================

lapply(1:128, function(i) {
  observeEvent(input[[paste0("sr_deck_", i)]], {
    if (isTRUE(input[[paste0("sr_deck_", i)]] == "__REQUEST_NEW__")) {
      rv$sr_deck_request_row <- i
      showModal(modalDialog(
        title = "Request New Deck",
        div(
          class = "deck-request-form",
          textInput("sr_deck_request_name", "Deck Name", placeholder = "e.g., Blue Flare"),
          uiOutput("sr_deck_request_suggestions"),
          layout_columns(
            col_widths = c(6, 6),
            class = "deck-request-colors",
            selectInput("sr_deck_request_color", "Primary Color",
                        choices = c("Select..." = "",
                                    "Red" = "Red", "Blue" = "Blue",
                                    "Yellow" = "Yellow", "Green" = "Green",
                                    "Purple" = "Purple", "Black" = "Black",
                                    "White" = "White"),
                        selectize = FALSE),
            selectInput("sr_deck_request_color2", "Secondary Color (optional)",
                        choices = c("None" = "",
                                    "Red" = "Red", "Blue" = "Blue",
                                    "Yellow" = "Yellow", "Green" = "Green",
                                    "Purple" = "Purple", "Black" = "Black",
                                    "White" = "White"),
                        selectize = FALSE)
          ),
          textInput("sr_deck_request_card_id", "Card ID (optional)",
                    placeholder = "e.g., BT12-031")
        ),
        footer = tagList(
          modalButton("Cancel"),
          actionButton("sr_deck_request_submit", "Submit Request", class = "btn-primary")
        ),
        size = "m",
        easyClose = TRUE
      ))
      updateSelectizeInput(session, paste0("sr_deck_", i), selected = "")
    }
  }, ignoreInit = TRUE)
})

sr_deck_request_name_debounced <- reactive({
  input$sr_deck_request_name
}) |> debounce(300)

output$sr_deck_request_suggestions <- renderUI({
  deck_name <- sr_deck_request_name_debounced()
  if (is.null(deck_name) || nchar(trimws(deck_name)) < 3) return(NULL)

  deck_name <- trimws(deck_name)
  words <- unlist(strsplit(tolower(deck_name), "\\s+"))
  words <- words[nchar(words) >= 3]
  like_pattern <- paste0("%", deck_name, "%")

  similar <- safe_query(db_pool, "
    SELECT DISTINCT archetype_name, primary_color, secondary_color
    FROM deck_archetypes
    WHERE is_active = TRUE
      AND (LOWER(archetype_name) LIKE LOWER($1) OR LOWER($2) LIKE '%' || LOWER(archetype_name) || '%')
    ORDER BY archetype_name LIMIT 5
  ", params = list(like_pattern, deck_name), default = data.frame())

  if (length(words) > 0 && nrow(similar) < 5) {
    for (wp in paste0("%", words, "%")) {
      word_matches <- safe_query(db_pool, "
        SELECT DISTINCT archetype_name, primary_color, secondary_color
        FROM deck_archetypes
        WHERE is_active = TRUE AND LOWER(archetype_name) LIKE LOWER($1)
          AND archetype_name NOT IN (SELECT archetype_name FROM deck_archetypes WHERE LOWER(archetype_name) LIKE LOWER($2))
        ORDER BY archetype_name LIMIT 3
      ", params = list(wp, like_pattern), default = data.frame())
      if (nrow(word_matches) > 0) {
        similar <- rbind(similar, word_matches)
        similar <- similar[!duplicated(similar$archetype_name), ]
      }
      if (nrow(similar) >= 5) break
    }
  }

  if (nrow(similar) == 0) return(NULL)

  suggestion_items <- lapply(seq_len(nrow(similar)), function(i) {
    deck <- similar[i, ]
    color_text <- if (!is.na(deck$secondary_color) && deck$secondary_color != "") {
      paste0(deck$primary_color, "/", deck$secondary_color)
    } else deck$primary_color
    tags$li(tags$strong(deck$archetype_name),
            tags$span(class = "text-muted ms-2", paste0("(", color_text, ")")))
  })

  div(class = "info-hint-box mt-2 mb-3", style = "padding: 0.625rem 0.875rem;",
    div(class = "d-flex align-items-start",
      bsicons::bs_icon("lightbulb", class = "info-hint-icon me-2 mt-1"),
      div(tags$strong("Similar decks found:"),
          tags$ul(class = "mb-0 ps-3 mt-1", style = "font-size: 0.875rem;", suggestion_items),
          tags$small(class = "text-muted d-block mt-1", "Check if one of these matches before requesting."))))
})

observeEvent(input$sr_deck_request_submit, {
  if (is.null(input$sr_deck_request_name) || trimws(input$sr_deck_request_name) == "") {
    notify("Please enter a deck name", type = "error"); return()
  }
  if (is.null(input$sr_deck_request_color) || input$sr_deck_request_color == "") {
    notify("Please select a primary color", type = "error"); return()
  }

  deck_name <- trimws(input$sr_deck_request_name)
  primary_color <- input$sr_deck_request_color
  secondary_color <- if (!is.null(input$sr_deck_request_color2) && input$sr_deck_request_color2 != "") input$sr_deck_request_color2 else NA_character_
  card_id <- if (!is.null(input$sr_deck_request_card_id) && trimws(input$sr_deck_request_card_id) != "") trimws(input$sr_deck_request_card_id) else NA_character_

  existing <- safe_query(db_pool, "SELECT archetype_id FROM deck_archetypes WHERE LOWER(archetype_name) = LOWER($1)",
                         params = list(deck_name), default = data.frame())
  if (nrow(existing) > 0) {
    notify(paste0("A deck named '", deck_name, "' already exists."), type = "warning"); removeModal(); return()
  }

  pending <- safe_query(db_pool, "SELECT request_id FROM deck_requests WHERE LOWER(deck_name) = LOWER($1) AND status = 'pending'",
                        params = list(deck_name), default = data.frame())
  if (nrow(pending) > 0) {
    notify(paste0("A request for '", deck_name, "' is already pending."), type = "warning"); removeModal(); return()
  }

  request_result <- safe_query(db_pool, "
    INSERT INTO deck_requests (deck_name, primary_color, secondary_color, display_card_id, status)
    VALUES ($1, $2, $3, $4, 'pending') RETURNING request_id
  ", params = list(deck_name, primary_color, secondary_color, card_id), default = data.frame())
  request_id <- if (nrow(request_result) > 0) request_result$request_id[1] else NA_integer_

  removeModal()
  notify(paste0("Deck request submitted: '", deck_name, "'."), type = "message")

  rv$sr_new_deck_request_id <- request_id
  rv$sr_deck_choices_refresh <- Sys.time()
})

# Async deck dropdown refresh
observeEvent(rv$sr_deck_choices_refresh, {
  req(rv$sr_grid_data, rv$sr_new_deck_request_id)

  updated_choices <- build_deck_choices(db_pool)
  rv$sr_deck_choices <- updated_choices  # Update cache

  grid <- rv$sr_grid_data
  request_id <- rv$sr_new_deck_request_id
  request_row <- rv$sr_deck_request_row

  for (i in seq_len(nrow(grid))) {
    current_selection <- input[[paste0("sr_deck_", i)]]
    new_selection <- if (!is.null(request_row) && i == request_row) {
      paste0("pending_", request_id)
    } else if (!is.null(current_selection) && current_selection != "__REQUEST_NEW__") {
      current_selection
    } else ""
    updateSelectizeInput(session, paste0("sr_deck_", i),
                         choices = updated_choices, selected = new_selection)
  }

  rv$sr_new_deck_request_id <- NULL
}, ignoreInit = TRUE)

# =============================================================================
# Clear/Delete Tournament (admin only)
# =============================================================================

observeEvent(input$sr_clear_tournament, {
  req(rv$sr_active_tournament_id, rv$is_admin)

  result_count <- safe_query(db_pool,
    "SELECT COUNT(*) as cnt FROM results WHERE tournament_id = $1",
    params = list(rv$sr_active_tournament_id), default = data.frame(cnt = 0L))$cnt

  showModal(modalDialog(
    title = "Start Over?",
    tagList(
      p("What would you like to do?"),
      if (result_count > 0) p(class = "text-muted", sprintf("This tournament has %d result(s) entered.", as.integer(result_count)))
      else p(class = "text-muted", "This tournament has no results entered yet.")
    ),
    footer = tagList(
      div(class = "d-flex flex-column gap-2 align-items-stretch w-100",
        actionButton("sr_clear_results_only", "Clear Results", class = "btn-warning w-100", icon = icon("eraser")),
        tags$small(class = "text-muted text-center", "Remove entered results but keep the tournament for re-entry."),
        actionButton("sr_delete_tournament_confirm", "Delete Tournament", class = "btn-danger w-100", icon = icon("trash")),
        tags$small(class = "text-danger text-center",
          if (result_count > 0) sprintf("Permanently delete this tournament and all %d result(s).", as.integer(result_count))
          else "Permanently delete this tournament."),
        modalButton("Cancel")
      )
    ),
    easyClose = TRUE
  ))
})

observeEvent(input$sr_clear_results_only, {
  req(rv$is_admin, rv$sr_active_tournament_id, db_pool)
  tryCatch({
    safe_execute(db_pool, "DELETE FROM results WHERE tournament_id = $1",
                 params = list(rv$sr_active_tournament_id))
    player_count <- safe_query(db_pool, "SELECT player_count FROM tournaments WHERE tournament_id = $1",
                                params = list(rv$sr_active_tournament_id), default = data.frame(player_count = 8L))$player_count
    rv$sr_grid_data <- init_grid_data(player_count)
    rv$sr_player_matches <- list()
    rv$refresh_tournaments <- rv$refresh_tournaments + 1
    rv$refresh_players <- rv$refresh_players + 1
    removeModal()
    notify("Results cleared.", type = "message")
    defer_ratings_recalc(db_pool, notify)
  }, error = function(e) {
    if (sentry_enabled) tryCatch(sentryR::capture_exception(e, tags = sentry_context_tags()), error = function(se) NULL)
    notify(paste("Error:", e$message), type = "error")
  })
})

observeEvent(input$sr_delete_tournament_confirm, {
  req(rv$is_admin, rv$sr_active_tournament_id, db_pool)
  tryCatch({
    safe_execute(db_pool, "DELETE FROM results WHERE tournament_id = $1", params = list(rv$sr_active_tournament_id))
    safe_execute(db_pool, "DELETE FROM tournaments WHERE tournament_id = $1", params = list(rv$sr_active_tournament_id))
    rv$sr_active_tournament_id <- NULL
    rv$sr_grid_data <- NULL
    rv$sr_player_matches <- list()
    removeModal()
    notify("Tournament deleted.", type = "message")
    rv$refresh_tournaments <- rv$refresh_tournaments + 1
    rv$refresh_players <- rv$refresh_players + 1
    defer_ratings_recalc(db_pool, notify)
    # Go back to step 1
    shinyjs::hide("sr_step2")
    shinyjs::show("sr_step1")
    shinyjs::runjs("$('#sr_step2_indicator').removeClass('active'); $('#sr_step1_indicator').addClass('active').removeClass('completed');")
  }, error = function(e) {
    if (sentry_enabled) tryCatch(sentryR::capture_exception(e, tags = sentry_context_tags()), error = function(se) NULL)
    notify(paste("Error:", e$message), type = "error")
  })
})

# =============================================================================
# Submit Results (unified transaction)
# =============================================================================

observeEvent(input$sr_submit_results, {
  req(rv$sr_grid_data)

  # Confirmation check for upload mode
  if (identical(rv$sr_active_method, "upload") && !isTRUE(input$sr_confirm)) {
    notify("Please confirm the data is accurate before submitting.", type = "warning")
    return()
  }

  # Sync grid inputs
  rv$sr_grid_data <- sync_grid_inputs(input, rv$sr_grid_data, rv$sr_record_format %||% "points", "sr_",
                                       placement_editable = TRUE, wlt_override = isTRUE(rv$sr_wlt_override))
  grid <- rv$sr_grid_data
  record_format <- rv$sr_record_format %||% "points"

  # Validate and adjust placements
  grid$placement <- validate_placements(grid$placement)
  # Sort by placement
  grid <- grid[order(grid$placement), ]
  rv$sr_grid_data <- grid

  # Filter to rows with player names
  grid$row_idx <- seq_len(nrow(grid))
  filled_rows <- grid[nchar(trimws(grid$player_name)) > 0, ]

  if (nrow(filled_rows) == 0) {
    notify("No results to submit. Enter at least one player name.", type = "warning")
    return()
  }

  # Block if any ambiguous
  ambiguous_rows <- filled_rows[filled_rows$match_status == "ambiguous", ]
  if (nrow(ambiguous_rows) > 0) {
    notify(sprintf("Resolve duplicate player names before submitting: %s",
                   paste(unique(ambiguous_rows$player_name), collapse = ", ")),
           type = "error")
    return()
  }

  # For upload flow without pre-created tournament: create it now
  if (is.null(rv$sr_active_tournament_id)) {
    store_id <- as.integer(input$sr_store)
    if (is.na(store_id)) { notify("Invalid store selection", type = "error"); return() }
    event_date <- as.character(input$sr_date)
    event_type <- input$sr_event_type
    format_val <- input$sr_format
    rounds <- as.integer(input$sr_rounds %||% 4)

    # Exact duplicate check
    existing <- safe_query(db_pool, "
      SELECT tournament_id FROM tournaments
      WHERE store_id = $1 AND event_date = $2 AND event_type = $3
    ", params = list(store_id, event_date, event_type), default = data.frame())

    if (nrow(existing) > 0) {
      notify("A tournament with this store, date, and event type already exists.", type = "error")
      return()
    }
  }

  rounds <- input$sr_rounds %||% 4
  is_release <- !is.null(input$sr_event_type) && input$sr_event_type == "release_event"

  unknown_row <- safe_query(db_pool, "SELECT archetype_id FROM deck_archetypes WHERE archetype_name = 'UNKNOWN' LIMIT 1",
                            default = data.frame(archetype_id = integer(0)))
  unknown_id <- if (nrow(unknown_row) > 0) unknown_row$archetype_id[1] else NA_integer_

  tryCatch({
    conn <- pool::localCheckout(db_pool)
    DBI::dbExecute(conn, "BEGIN")

    tryCatch({
      # Create tournament if needed (upload flow) or update existing (grid flow)
      tournament_id <- rv$sr_active_tournament_id
      submit_by <- if (isTRUE(rv$is_admin)) current_admin_username(rv) else "public_submit"
      submission_method <- rv$sr_submission_method
      if (is.null(tournament_id)) {
        tourney_result <- DBI::dbGetQuery(conn, "
          INSERT INTO tournaments (store_id, event_date, event_type, format, player_count, rounds, record_format, updated_by, submission_method)
          VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
          RETURNING tournament_id
        ", params = list(
          as.integer(input$sr_store), as.character(input$sr_date), input$sr_event_type,
          input$sr_format, nrow(filled_rows), rounds, record_format, submit_by, submission_method
        ))
        tournament_id <- tourney_result$tournament_id[1]
        rv$sr_active_tournament_id <- tournament_id
      } else if (!is.null(submission_method)) {
        # Grid flow: tournament was created earlier, set submission_method now at final submit
        DBI::dbExecute(conn, "UPDATE tournaments SET submission_method = $1 WHERE tournament_id = $2",
                       params = list(submission_method, tournament_id))
      }

      # Get scene_id
      tournament_store <- DBI::dbGetQuery(conn, "
        SELECT s.scene_id FROM tournaments t JOIN stores s ON t.store_id = s.store_id
        WHERE t.tournament_id = $1
      ", params = list(tournament_id))
      scene_id <- if (nrow(tournament_store) > 0) tournament_store$scene_id[1] else NA_integer_

      # Phase 1: Resolve all players
      resolved_rows <- list()
      for (idx in seq_len(nrow(filled_rows))) {
        row <- filled_rows[idx, ]
        name <- trimws(row$player_name)
        member_num <- normalize_member_number(row$member_number)
        if (is.na(member_num)) member_num <- ""

        # Resolve player_id
        if (!is.na(row$matched_player_id) && row$match_status == "matched") {
          player_id <- row$matched_player_id
        } else {
          match_info <- match_player(name, conn, member_number = member_num, scene_id = scene_id)
          if (match_info$status == "matched" || match_info$status == "ambiguous") {
            player_id <- if (match_info$status == "matched") match_info$player_id else match_info$candidates$player_id[1]
          } else {
            has_real_id <- has_real_member_number(member_num)
            identity_status <- if (has_real_id) "verified" else "unverified"
            clean_member <- if (has_real_id) member_num else NA_character_
            auto_anon <- should_auto_anonymize(name, member_num)
            # If member_number is real, try to find existing player first to avoid duplicate key
            if (has_real_id) {
              existing <- DBI::dbGetQuery(conn,
                "SELECT player_id FROM players WHERE member_number = $1 LIMIT 1",
                params = list(clean_member))
              if (nrow(existing) > 0) {
                player_id <- existing$player_id[1]
              } else {
                player_slug <- generate_unique_slug(conn, name)
                new_player <- DBI::dbGetQuery(conn,
                  "INSERT INTO players (display_name, slug, member_number, identity_status, home_scene_id, is_anonymized, updated_by) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING player_id",
                  params = list(name, player_slug, clean_member, identity_status, scene_id, auto_anon, submit_by))
                player_id <- new_player$player_id[1]
              }
            } else {
              player_slug <- generate_unique_slug(conn, name)
              new_player <- DBI::dbGetQuery(conn,
                "INSERT INTO players (display_name, slug, member_number, identity_status, home_scene_id, is_anonymized, updated_by) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING player_id",
                params = list(name, player_slug, clean_member, identity_status, scene_id, auto_anon, submit_by))
              player_id <- new_player$player_id[1]
            }
          }
        }

        # Update member number if needed
        if (has_real_member_number(member_num)) {
          updated_by <- if (isTRUE(rv$is_admin)) current_admin_username(rv) else "public_submit"
          DBI::dbExecute(conn, "
            UPDATE players SET member_number = $1, identity_status = 'verified',
                   updated_at = CURRENT_TIMESTAMP, updated_by = $2
            WHERE player_id = $3 AND (member_number IS NULL OR member_number = '')
          ", params = list(member_num, updated_by, player_id))
        }

        # Convert record
        wlt_override_active <- isTRUE(rv$sr_wlt_override) && record_format == "points"
        if (wlt_override_active) {
          # Use explicitly entered W/L/T values
          wins <- row$wins
          losses <- row$losses
          ties <- row$ties
          pts <- as.integer((wins * 3L) + ties)
        } else if (record_format == "points") {
          pts <- row$points
          wins <- pts %/% 3L
          ties <- pts %% 3L
          losses <- max(0L, rounds - wins - ties)
        } else {
          wins <- row$wins
          losses <- row$losses
          ties <- row$ties
          pts <- as.integer((wins * 3L) + ties)
        }

        # Resolve deck
        pending_deck_request_id <- NA_integer_
        if (is_release) {
          archetype_id <- unknown_id
        } else {
          deck_input <- input[[paste0("sr_deck_", row$row_idx)]]
          if (is.null(deck_input) || nchar(deck_input) == 0 || deck_input == "__REQUEST_NEW__") {
            archetype_id <- unknown_id
          } else if (grepl("^pending_", deck_input)) {
            pending_deck_request_id <- as.integer(sub("^pending_", "", deck_input))
            archetype_id <- unknown_id
          } else {
            archetype_id <- as.integer(deck_input)
          }
        }

        # Carry CSV-sourced fields through for INSERT (deck_url, tiebreakers, memo)
        deck_url <- if ("deck_url" %in% names(row) && !is.na(row$deck_url)) validate_decklist_url(row$deck_url) %||% NA_character_ else NA_character_
        omw_pct <- if ("omw_pct" %in% names(row) && !is.na(row$omw_pct)) row$omw_pct else NA_real_
        oomw_pct <- if ("oomw_pct" %in% names(row) && !is.na(row$oomw_pct)) row$oomw_pct else NA_real_
        memo <- if ("memo" %in% names(row) && !is.na(row$memo)) row$memo else NA_character_

        resolved_rows[[idx]] <- list(
          player_id = player_id, player_name = name,
          archetype_id = archetype_id, pending_deck_request_id = pending_deck_request_id,
          placement = row$placement, wins = wins, losses = losses, ties = ties, pts = pts,
          deck_url = deck_url, omw_pct = omw_pct, oomw_pct = oomw_pct, memo = memo
        )
      }

      # Phase 2: Check duplicate player_ids
      resolved_player_ids <- vapply(resolved_rows, function(r) r$player_id, integer(1))
      dup_ids <- unique(resolved_player_ids[duplicated(resolved_player_ids)])
      if (length(dup_ids) > 0) {
        dup_names <- vapply(dup_ids, function(pid) {
          matches <- which(resolved_player_ids == pid)
          paste(vapply(matches, function(j) resolved_rows[[j]]$player_name, character(1)), collapse = ", ")
        }, character(1))
        DBI::dbExecute(conn, "ROLLBACK")
        notify(paste0("Duplicate players detected: ", paste(dup_names, collapse = "; ")),
               type = "error", duration = 10)
        return()
      }

      # Phase 3: Insert results
      for (idx in seq_len(length(resolved_rows))) {
        r <- resolved_rows[[idx]]
        DBI::dbExecute(conn, "
          INSERT INTO results (tournament_id, player_id, archetype_id, pending_deck_request_id,
                               placement, wins, losses, ties, points,
                               decklist_url, omw_pct, oomw_pct, memo)
          VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
        ", params = list(tournament_id, r$player_id, r$archetype_id,
                         r$pending_deck_request_id, r$placement, r$wins, r$losses, r$ties, r$pts,
                         r$deck_url, r$omw_pct, r$oomw_pct, r$memo))
      }

      DBI::dbExecute(conn, "COMMIT")
    }, error = function(e) {
      tryCatch(DBI::dbExecute(conn, "ROLLBACK"), error = function(re) NULL)
      stop(e)
    })

    rv$refresh_tournaments <- rv$refresh_tournaments + 1
    rv$refresh_players <- rv$refresh_players + 1
    rv$results_refresh <- (rv$results_refresh %||% 0) + 1

    notify(sprintf("Tournament submitted! %d results recorded.", nrow(filled_rows)), type = "message")
    defer_ratings_recalc(db_pool, notify)

    # Load results for Step 3 (decklists)
    rv$sr_decklist_results <- load_decklist_results(tournament_id, db_pool)
    rv$sr_decklist_tournament_id <- tournament_id

    # Move to Step 3
    shinyjs::hide("sr_step2")
    shinyjs::show("sr_step3")
    shinyjs::runjs("$('#sr_step2_indicator').removeClass('active').addClass('completed'); $('#sr_step3_indicator').addClass('active');")

  }, error = function(e) {
    message("[SR SUBMIT] Transaction error: ", conditionMessage(e))
    if (sentry_enabled) tryCatch(sentryR::capture_exception(e, tags = sentry_context_tags()), error = function(se) NULL)
    notify(paste("Error submitting results:", e$message), type = "error")
  })
})

# =============================================================================
# Step 3: Decklists
# =============================================================================

output$sr_decklist_summary_bar <- renderUI({
  req(rv$sr_decklist_tournament_id)
  tournament <- safe_query(db_pool, "
    SELECT t.tournament_id, s.name as store_name, t.event_date, t.event_type, t.format
    FROM tournaments t JOIN stores s ON t.store_id = s.store_id
    WHERE t.tournament_id = $1
  ", params = list(rv$sr_decklist_tournament_id), default = data.frame())
  if (nrow(tournament) == 0) return(NULL)
  t <- tournament[1, ]
  div(class = "alert alert-success d-flex align-items-center gap-2 mb-3",
      bsicons::bs_icon("check-circle-fill"),
      sprintf("Results submitted for %s — %s (%s)", t$store_name, t$event_date, t$format))
})

output$sr_decklist_table <- renderUI({
  req(rv$sr_decklist_results)
  render_decklist_entry(rv$sr_decklist_results, "sr_decklist_")
})

sr_save_decklists <- function() {
  req(rv$sr_decklist_results)
  result <- save_decklist_urls(rv$sr_decklist_results, input, "sr_decklist_", db_pool)
  if (result$skipped > 0) {
    notify(sprintf("%d invalid URL%s skipped.", result$skipped, if (result$skipped == 1) "" else "s"), type = "warning")
  }
  result$saved
}

sr_reset_wizard <- function() {
  # Delegate all state + visibility resets to sr_back_to_picker
  sr_back_to_picker()

  # Additionally clear form inputs (sr_back_to_picker doesn't do this)
  updateSelectInput(session, "sr_store", selected = "")
  updateDateInput(session, "sr_date", value = NA)
  updateSelectInput(session, "sr_event_type", selected = "")
  updateSelectInput(session, "sr_format", selected = "")
  updateNumericInput(session, "sr_players", value = 8)
  updateNumericInput(session, "sr_rounds", value = 4)
  if (isTRUE(rv$is_admin)) {
    updateRadioButtons(session, "sr_record_format", selected = "points")
  }
}

observeEvent(input$sr_save_decklists, {
  saved <- sr_save_decklists()
  if (saved > 0) notify(sprintf("Saved %d decklist link%s.", saved, if (saved == 1) "" else "s"), type = "message")
  else notify("No decklist links to save.", type = "warning")
})

observeEvent(input$sr_done_decklists, {
  sr_save_decklists()
  sr_reset_wizard()
})

observeEvent(input$sr_skip_decklists, {
  notify("Tournament submitted successfully!", type = "message")
  sr_reset_wizard()
})

# =============================================================================
# Paste from Spreadsheet (shared helper, called by paste card or paste button)
# =============================================================================

sr_show_paste_modal <- function() {
  showModal(modalDialog(
    title = tagList(bsicons::bs_icon("clipboard"), " Paste from Spreadsheet"),
    tagList(
      p(class = "text-muted", "Paste data with one player per line. Columns separated by tabs or 2+ spaces."),
      p(class = "text-muted small mb-2", "Supported formats:"),
      tags$div(
        class = "bg-body-secondary rounded p-2 mb-3",
        style = "font-family: monospace; font-size: 0.8rem; white-space: pre-line;",
        tags$div(class = "fw-bold mb-1", "Names only:"),
        tags$div(class = "text-muted mb-2", "PlayerOne\nPlayerTwo"),
        tags$div(class = "fw-bold mb-1", "Names + Points:"),
        tags$div(class = "text-muted mb-2", "PlayerOne\t9\nPlayerTwo\t7"),
        tags$div(class = "fw-bold mb-1", "Names + MemberID + Points:"),
        tags$div(class = "text-muted mb-2", "PlayerOne\t0000123456\t9\nPlayerTwo\t0000789012\t7"),
        tags$div(class = "fw-bold mb-1", "Names + W/L/T:"),
        tags$div(class = "text-muted mb-2", "PlayerOne\t3\t0\t0\nPlayerTwo\t2\t1\t1"),
        tags$div(class = "fw-bold mb-1", "Names + W/L/T + Deck:"),
        tags$div(class = "text-muted", "PlayerOne\t3\t0\t0\tBlue Flare")
      ),
      p(class = "text-muted small", "Header rows are auto-detected and skipped. Deck names must match existing archetypes (case-insensitive)."),
      tags$textarea(id = "sr_paste_data", class = "form-control", rows = "10",
                    placeholder = "Paste data here...")
    ),
    footer = tagList(
      actionButton("sr_paste_apply", "Fill Grid", class = "btn-primary", icon = icon("table")),
      modalButton("Cancel")
    ),
    size = "l",
    easyClose = TRUE
  ))
}

observeEvent(input$sr_paste_btn, {
  sr_show_paste_modal()
})

observeEvent(input$sr_paste_apply, {
  req(rv$sr_grid_data)

  paste_text <- input$sr_paste_data
  if (is.null(paste_text) || nchar(trimws(paste_text)) == 0) {
    notify("No data to paste", type = "warning"); return()
  }

  rv$sr_grid_data <- sync_grid_inputs(input, rv$sr_grid_data, rv$sr_record_format %||% "points", "sr_",
                                       placement_editable = TRUE, wlt_override = isTRUE(rv$sr_wlt_override))
  grid <- rv$sr_grid_data

  all_decks <- safe_query(db_pool, "
    SELECT archetype_id, archetype_name FROM deck_archetypes WHERE is_active = TRUE
  ", default = data.frame(archetype_id = integer(0), archetype_name = character(0)))
  parsed <- parse_paste_data(paste_text, all_decks)

  if (length(parsed) == 0) {
    notify("No valid lines found", type = "warning"); return()
  }

  # Expand grid if paste has more rows
  while (length(parsed) > nrow(grid)) {
    blank_row <- data.frame(
      placement = nrow(grid) + 1L, player_name = "", member_number = "",
      points = 0L, wins = 0L, losses = 0L, ties = 0L,
      deck_id = NA_integer_, match_status = "",
      matched_player_id = NA_integer_, matched_member_number = NA_character_,
      result_id = NA_integer_, stringsAsFactors = FALSE
    )
    for (col in c("deck_url", "memo")) {
      if (col %in% names(grid)) blank_row[[col]] <- NA_character_
    }
    for (col in c("omw_pct", "oomw_pct")) {
      if (col %in% names(grid)) blank_row[[col]] <- NA_real_
    }
    grid <- rbind(grid, blank_row)
  }

  fill_count <- 0L
  for (idx in seq_along(parsed)) {
    if (idx > nrow(grid)) break
    p <- parsed[[idx]]
    grid$player_name[idx] <- p$name
    grid$points[idx] <- p$points
    grid$wins[idx] <- p$wins
    grid$losses[idx] <- p$losses
    grid$ties[idx] <- p$ties
    if (!is.na(p$deck_id)) grid$deck_id[idx] <- p$deck_id
    if (!is.null(p$member_number) && !is.na(p$member_number)) grid$member_number[idx] <- p$member_number
    fill_count <- fill_count + 1L
  }

  removeModal()
  notify(sprintf("Filled %d rows from pasted data", fill_count), type = "message")

  # Run player matching
  scene_id <- get_store_scene_id(as.integer(input$sr_store), db_pool)
  for (idx in seq_len(fill_count)) {
    name <- trimws(grid$player_name[idx])
    if (nchar(name) == 0) next

    match_info <- match_player(name, db_pool, member_number = grid$member_number[idx], scene_id = scene_id)
    rv$sr_player_matches[[as.character(idx)]] <- match_info
    grid$match_status[idx] <- match_info$status
    if (match_info$status == "matched") {
      grid$matched_player_id[idx] <- match_info$player_id
      grid$matched_member_number[idx] <- match_info$member_number
    } else if (match_info$status == "ambiguous") {
      grid$matched_player_id[idx] <- match_info$candidates$player_id[1]
      grid$matched_member_number[idx] <- match_info$candidates$member_number[1]
    } else {
      grid$matched_player_id[idx] <- NA_integer_
      grid$matched_member_number[idx] <- NA_character_
    }
  }
  rv$sr_grid_data <- grid

  # Track that paste was used (applied at final submit time)
  rv$sr_submission_method <- "paste_grid"
})
