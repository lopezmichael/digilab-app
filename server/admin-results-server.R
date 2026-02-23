# =============================================================================
# Admin: Tournament Entry & Results Server Logic
# =============================================================================

# Grid data for bulk entry
rv$admin_grid_data <- NULL
rv$admin_record_format <- "points"
rv$admin_player_matches <- list()
rv$admin_deck_request_row <- NULL

# Wizard step management
observe({
  if (rv$wizard_step == 1) {
    shinyjs::show("wizard_step1")
    shinyjs::hide("wizard_step2")
    shinyjs::runjs("$('#step1_indicator').addClass('active').removeClass('completed'); $('#step2_indicator').removeClass('active');")
  } else {
    shinyjs::hide("wizard_step1")
    shinyjs::show("wizard_step2")
    shinyjs::runjs("$('#step2_indicator').addClass('active'); $('#step1_indicator').removeClass('active').addClass('completed');")

    # Hide deck selector for release events (sealed packs, no archetype)
    is_release <- !is.null(input$tournament_type) && input$tournament_type == "release_event"
    if (is_release) {
      shinyjs::hide("deck_selection_section")
      shinyjs::show("release_event_deck_notice")
    } else {
      shinyjs::show("deck_selection_section")
      shinyjs::hide("release_event_deck_notice")
    }
  }
})

output$active_tournament_info <- renderText({
  if (is.null(rv$active_tournament_id)) {
    return("No active tournament. Create one to start entering results.")
  }

  if (is.null(rv$db_con) || !dbIsValid(rv$db_con)) return("Database not connected")

  info <- dbGetQuery(rv$db_con, "
    SELECT t.tournament_id, s.name as store_name, t.event_date, t.event_type, t.format, t.player_count
    FROM tournaments t
    JOIN stores s ON t.store_id = s.store_id
    WHERE t.tournament_id = ?
  ", params = list(rv$active_tournament_id))

  if (nrow(info) == 0) return("Tournament not found")

  format_display <- if (!is.null(info$format) && !is.na(info$format)) paste0(" [", info$format, "]") else ""
  sprintf("Tournament #%d\n%s\n%s (%s)%s\nExpected players: %d",
          info$tournament_id, info$store_name, info$event_date, info$event_type, format_display, info$player_count)
})

# Create tournament
observeEvent(input$create_tournament, {
  clear_all_field_errors(session)
  req(rv$is_admin, rv$db_con)

  store_id <- input$tournament_store
  event_date <- as.character(input$tournament_date)
  event_type <- input$tournament_type
  format <- input$tournament_format
  player_count <- input$tournament_players
  rounds <- input$tournament_rounds

  # Validation
  if (is.null(store_id) || nchar(trimws(store_id)) == 0) {
    show_field_error(session, "tournament_store")
    notify("Please select a store", type = "error")
    return()
  }

  store_id <- as.integer(store_id)
  if (is.na(store_id)) {
    show_field_error(session, "tournament_store")
    notify("Invalid store selection", type = "error")
    return()
  }

  # Date validation
  if (is.null(input$tournament_date) || is.na(input$tournament_date)) {
    show_field_error(session, "tournament_date")
    notify("Please select a tournament date", type = "error")
    return()
  }

  if (is.null(player_count) || is.na(player_count) || player_count < 2) {
    show_field_error(session, "tournament_players")
    notify("Player count must be at least 2", type = "error")
    return()
  }

  if (is.null(rounds) || is.na(rounds) || rounds < 1) {
    show_field_error(session, "tournament_rounds")
    notify("Rounds must be at least 1", type = "error")
    return()
  }

  # Event type validation
  if (is.null(event_type) || nchar(trimws(event_type)) == 0) {
    show_field_error(session, "tournament_type")
    notify("Please select an event type", type = "error")
    return()
  }

  # Format validation
  if (is.null(format) || nchar(trimws(format)) == 0) {
    show_field_error(session, "tournament_format")
    notify("Please select a format", type = "error")
    return()
  }

  # Check for duplicate tournament (same store and date)
  existing <- dbGetQuery(rv$db_con, "
    SELECT t.tournament_id, t.player_count, t.event_type,
           (SELECT COUNT(*) FROM results WHERE tournament_id = t.tournament_id) as result_count,
           s.name as store_name
    FROM tournaments t
    JOIN stores s ON t.store_id = s.store_id
    WHERE t.store_id = ? AND t.event_date = ?
  ", params = list(store_id, event_date))

  if (nrow(existing) > 0) {
    # Store for modal handlers
    rv$duplicate_tournament <- existing[1, ]

    output$duplicate_tournament_message <- renderUI({
      div(
        p(sprintf("A tournament at %s on %s already exists:",
                  existing$store_name[1], format(as.Date(event_date), "%B %d, %Y"))),
        tags$ul(
          tags$li(sprintf("%d players expected", existing$player_count[1])),
          tags$li(sprintf("%d results entered", existing$result_count[1])),
          tags$li(sprintf("Event type: %s", existing$event_type[1]))
        ),
        p("What would you like to do?")
      )
    })

    # Show modal and return (don't create)
    showModal(modalDialog(
      title = "Possible Duplicate Tournament",
      uiOutput("duplicate_tournament_message"),
      footer = tagList(
        actionButton("edit_existing_tournament", "View/Edit Existing", class = "btn-outline-primary"),
        actionButton("create_anyway", "Create Anyway", class = "btn-warning"),
        modalButton("Cancel")
      ),
      easyClose = TRUE
    ))
    return()
  }

  tryCatch({
    # Get next ID
    max_id <- dbGetQuery(rv$db_con, "SELECT COALESCE(MAX(tournament_id), 0) as max_id FROM tournaments")$max_id
    new_id <- max_id + 1

    dbExecute(rv$db_con, "
      INSERT INTO tournaments (tournament_id, store_id, event_date, event_type, format, player_count, rounds)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    ", params = list(new_id, store_id, event_date, event_type, format, player_count, rounds))

    rv$active_tournament_id <- new_id
    rv$current_results <- data.frame()

    notify("Tournament created!", type = "message")
    rv$wizard_step <- 2
    rv$admin_record_format <- input$admin_record_format %||% "points"
    rv$admin_grid_data <- init_grid_data(player_count)
    rv$admin_player_matches <- list()

  }, error = function(e) {
    notify(paste("Error:", e$message), type = "error")
  })
})

# Clear tournament - show modal with options
observeEvent(input$clear_tournament, {
  req(rv$active_tournament_id)

  # Count current results for this tournament
  result_count <- 0
  if (!is.null(rv$db_con)) {
    result_count <- dbGetQuery(rv$db_con,
      "SELECT COUNT(*) as cnt FROM results WHERE tournament_id = ?",
      params = list(rv$active_tournament_id))$cnt
  }

  output$start_over_message <- renderUI({
    if (result_count > 0) {
      p(class = "text-muted", sprintf("This tournament has %d result(s) entered.", result_count))
    } else {
      p(class = "text-muted", "This tournament has no results entered yet.")
    }
  })

  output$delete_tournament_warning <- renderUI({
    tags$small(class = "text-danger text-center",
      if (result_count > 0) {
        sprintf("Permanently delete this tournament and all %d result(s).", result_count)
      } else {
        "Permanently delete this tournament."
      }
    )
  })

  showModal(modalDialog(
    title = "Start Over?",
    tagList(
      p("What would you like to do?"),
      uiOutput("start_over_message")
    ),
    footer = tagList(
      div(
        class = "d-flex flex-column gap-2 align-items-stretch w-100",
        actionButton("clear_results_only", "Clear Results",
                     class = "btn-warning w-100",
                     icon = icon("eraser")),
        tags$small(class = "text-muted text-center", "Remove entered results but keep the tournament for re-entry."),
        actionButton("delete_tournament_confirm", "Delete Tournament",
                     class = "btn-danger w-100",
                     icon = icon("trash")),
        uiOutput("delete_tournament_warning"),
        modalButton("Cancel")
      )
    ),
    easyClose = TRUE
  ))
})

# Clear results only - keep tournament, remove results
observeEvent(input$clear_results_only, {
  req(rv$active_tournament_id, rv$db_con)

  tryCatch({
    dbExecute(rv$db_con,
      "DELETE FROM results WHERE tournament_id = ?",
      params = list(rv$active_tournament_id))

    rv$current_results <- data.frame()
    # Re-initialize grid with blank rows
    player_count <- dbGetQuery(rv$db_con, "SELECT player_count FROM tournaments WHERE tournament_id = ?",
                               params = list(rv$active_tournament_id))$player_count
    rv$admin_grid_data <- init_grid_data(player_count)
    rv$admin_player_matches <- list()
    rv$results_refresh <- (rv$results_refresh %||% 0) + 1

    # Recalculate ratings cache
    recalculate_ratings_cache(rv$db_con)
    rv$data_refresh <- (rv$data_refresh %||% 0) + 1

    removeModal()
    notify("Results cleared. Tournament kept for re-entry.", type = "message")

  }, error = function(e) {
    notify(paste("Error:", e$message), type = "error")
  })
})

# Delete tournament and all results
observeEvent(input$delete_tournament_confirm, {
  req(rv$active_tournament_id, rv$db_con)

  tryCatch({
    # Delete results first (child records)
    dbExecute(rv$db_con,
      "DELETE FROM results WHERE tournament_id = ?",
      params = list(rv$active_tournament_id))

    # Delete tournament (parent record)
    dbExecute(rv$db_con,
      "DELETE FROM tournaments WHERE tournament_id = ?",
      params = list(rv$active_tournament_id))

    # Reset state
    rv$active_tournament_id <- NULL
    rv$current_results <- data.frame()
    rv$admin_grid_data <- NULL
    rv$admin_player_matches <- list()
    rv$wizard_step <- 1

    removeModal()
    notify("Tournament deleted.", type = "message")

    # Recalculate ratings cache
    recalculate_ratings_cache(rv$db_con)

    # Trigger refresh of public tables
    rv$data_refresh <- (rv$data_refresh %||% 0) + 1

  }, error = function(e) {
    notify(paste("Error:", e$message), type = "error")
  })
})

# Hide date required hint when date is selected
observeEvent(input$tournament_date, {
  # Check if date is valid (not null, has length > 0, and not NA)
  date_valid <- !is.null(input$tournament_date) &&
                length(input$tournament_date) > 0 &&
                !anyNA(input$tournament_date)

  if (date_valid) {
    shinyjs::hide("date_required_hint")
    shinyjs::runjs("$('#tournament_date').closest('.date-required').removeClass('date-required');")
  } else {
    shinyjs::show("date_required_hint")
    shinyjs::runjs("$('#tournament_date').closest('.shiny-date-input').addClass('date-required');")
  }
}, ignoreNULL = FALSE)

# Wizard back button
observeEvent(input$wizard_back, {
  rv$wizard_step <- 1
})

# Handle "View/Edit Existing" button from duplicate modal
observeEvent(input$edit_existing_tournament, {
  req(rv$duplicate_tournament)
  removeModal()

  # Store the tournament ID so Edit Tournaments can select it
  rv$navigate_to_tournament_id <- rv$duplicate_tournament$tournament_id

  # Navigate to Edit Tournaments tab
  nav_select("main_content", "admin_tournaments")
  rv$current_nav <- "admin_tournaments"
  session$sendCustomMessage("updateSidebarNav", "nav_admin_tournaments")
})

# Handle "Create Anyway" button from duplicate modal
observeEvent(input$create_anyway, {
  removeModal()

  # Get form values again
  store_id <- as.integer(input$tournament_store)
  event_date <- as.character(input$tournament_date)
  event_type <- input$tournament_type
  format <- input$tournament_format
  player_count <- input$tournament_players
  rounds <- input$tournament_rounds

  tryCatch({
    max_id <- dbGetQuery(rv$db_con, "SELECT COALESCE(MAX(tournament_id), 0) as max_id FROM tournaments")$max_id
    new_id <- max_id + 1

    dbExecute(rv$db_con, "
      INSERT INTO tournaments (tournament_id, store_id, event_date, event_type, format, player_count, rounds)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    ", params = list(new_id, store_id, event_date, event_type, format, player_count, rounds))

    rv$active_tournament_id <- new_id
    rv$current_results <- data.frame()
    rv$duplicate_tournament <- NULL

    notify("Tournament created!", type = "message")
    rv$wizard_step <- 2
    rv$admin_record_format <- input$admin_record_format %||% "points"
    rv$admin_grid_data <- init_grid_data(player_count)
    rv$admin_player_matches <- list()

  }, error = function(e) {
    notify(paste("Error:", e$message), type = "error")
  })
})

# Tournament summary bar for wizard step 2
output$tournament_summary_bar <- renderUI({
  req(rv$active_tournament_id, rv$db_con)

  info <- dbGetQuery(rv$db_con, "
    SELECT s.name as store_name, t.event_date, t.event_type, t.format, t.player_count
    FROM tournaments t
    JOIN stores s ON t.store_id = s.store_id
    WHERE t.tournament_id = ?
  ", params = list(rv$active_tournament_id))

  if (nrow(info) == 0) return(NULL)

  div(
    class = "tournament-summary-bar",
    span(class = "summary-icon", bsicons::bs_icon("geo-alt-fill")),
    span(class = "summary-item", info$store_name),
    span(class = "summary-divider", "|"),
    span(class = "summary-item", format(as.Date(info$event_date), "%b %d, %Y")),
    span(class = "summary-divider", "|"),
    span(class = "summary-item", info$event_type),
    if (!is.null(info$format) && !is.na(info$format) && nchar(info$format) > 0) tagList(
      span(class = "summary-divider", "|"),
      span(class = "summary-item", info$format)
    ),
    span(class = "summary-divider", "|"),
    span(class = "summary-item", sprintf("%d players", info$player_count))
  )
})

# =============================================================================
# Admin Grid: Helper Functions
# =============================================================================

output$admin_record_format_badge <- renderUI({
  format <- rv$admin_record_format %||% "points"
  label <- if (format == "points") "Points mode" else "W-L-T mode"
  span(class = "badge bg-info", label)
})

output$admin_filled_count <- renderUI({
  req(rv$admin_grid_data)
  grid <- rv$admin_grid_data
  filled <- sum(nchar(trimws(grid$player_name)) > 0)
  total <- nrow(grid)
  span(class = "text-muted small", sprintf("Filled: %d/%d", filled, total))
})

# =============================================================================
# Admin Grid: Table Rendering
# =============================================================================

output$admin_grid_table <- renderUI({
  req(rv$admin_grid_data)

  grid <- rv$admin_grid_data
  record_format <- rv$admin_record_format %||% "points"

  # Check if release event
  is_release <- FALSE
  if (!is.null(rv$active_tournament_id) && !is.null(rv$db_con) && dbIsValid(rv$db_con)) {
    t_info <- dbGetQuery(rv$db_con, "SELECT event_type FROM tournaments WHERE tournament_id = ?",
                         params = list(rv$active_tournament_id))
    if (nrow(t_info) > 0) is_release <- t_info$event_type[1] == "release_event"
  }

  deck_choices <- build_deck_choices(rv$db_con)
  render_grid_ui(grid, record_format, is_release, deck_choices, rv$admin_player_matches, "admin_")
})

# =============================================================================
# Admin Grid: Input Sync & Row Management
# =============================================================================

observeEvent(input$admin_delete_row, {
  req(rv$admin_grid_data)
  row_idx <- as.integer(input$admin_delete_row)
  if (is.null(row_idx) || row_idx < 1 || row_idx > nrow(rv$admin_grid_data)) return()

  rv$admin_grid_data <- sync_grid_inputs(input, rv$admin_grid_data, rv$admin_record_format %||% "points", "admin_")
  grid <- rv$admin_grid_data

  # Remove the row
  grid <- grid[-row_idx, ]

  # Append blank row to maintain count
  blank_row <- data.frame(
    placement = nrow(grid) + 1,
    player_name = "",
    member_number = "",
    points = 0L, wins = 0L, losses = 0L, ties = 0L,
    deck_id = NA_integer_,
    match_status = "",
    matched_player_id = NA_integer_,
    matched_member_number = NA_character_,
    result_id = NA_integer_,
    stringsAsFactors = FALSE
  )
  grid <- rbind(grid, blank_row)

  # Renumber placements
  grid$placement <- seq_len(nrow(grid))

  # Update match list (shift indices)
  new_matches <- list()
  for (j in seq_len(nrow(grid))) {
    old_idx <- if (j < row_idx) j else j + 1
    if (!is.null(rv$admin_player_matches[[as.character(old_idx)]])) {
      new_matches[[as.character(j)]] <- rv$admin_player_matches[[as.character(old_idx)]]
    }
  }
  rv$admin_player_matches <- new_matches
  rv$admin_grid_data <- grid
  notify(paste0("Row removed. Players renumbered 1-", nrow(grid), "."), type = "message", duration = 3)
})

# =============================================================================
# Admin Grid: Player Matching
# =============================================================================

# Attach blur handlers via delegated event (runs when wizard step 2 shows)
observe({
  req(rv$wizard_step == 2)
  shinyjs::runjs("
    $(document).off('blur.adminGrid').on('blur.adminGrid', 'input[id^=\"admin_player_\"]', function() {
      var id = $(this).attr('id');
      var rowNum = parseInt(id.replace('admin_player_', ''));
      if (!isNaN(rowNum)) {
        Shiny.setInputValue('admin_player_blur', {row: rowNum, name: $(this).val(), ts: Date.now()}, {priority: 'event'});
      }
    });
  ")
})

observeEvent(input$admin_player_blur, {
  req(rv$db_con, rv$admin_grid_data)

  info <- input$admin_player_blur
  row_num <- info$row
  name <- trimws(info$name)

  if (is.null(row_num) || is.na(row_num)) return()
  if (row_num < 1 || row_num > nrow(rv$admin_grid_data)) return()

  # Sync all inputs before modifying reactive (re-render preserves all typed values)
  rv$admin_grid_data <- sync_grid_inputs(input, rv$admin_grid_data, rv$admin_record_format %||% "points", "admin_")

  if (nchar(name) == 0) {
    rv$admin_player_matches[[as.character(row_num)]] <- NULL
    rv$admin_grid_data$match_status[row_num] <- ""
    rv$admin_grid_data$matched_player_id[row_num] <- NA_integer_
    rv$admin_grid_data$matched_member_number[row_num] <- NA_character_
    return()
  }

  match_info <- match_player(name, rv$db_con)
  rv$admin_player_matches[[as.character(row_num)]] <- match_info
  rv$admin_grid_data$match_status[row_num] <- match_info$status
  if (match_info$status == "matched") {
    rv$admin_grid_data$matched_player_id[row_num] <- match_info$player_id
    rv$admin_grid_data$matched_member_number[row_num] <- match_info$member_number
  } else {
    rv$admin_grid_data$matched_player_id[row_num] <- NA_integer_
    rv$admin_grid_data$matched_member_number[row_num] <- NA_character_
  }
})

# =============================================================================
# Admin Grid: Paste from Spreadsheet
# =============================================================================

observeEvent(input$admin_paste_btn, {
  showModal(modalDialog(
    title = tagList(bsicons::bs_icon("clipboard"), " Paste from Spreadsheet"),
    tagList(
      p(class = "text-muted", "Paste data with one player per line. Columns separated by tabs (from a spreadsheet) or 2+ spaces."),
      p(class = "text-muted small mb-2", "Supported formats:"),
      tags$div(
        class = "bg-body-secondary rounded p-2 mb-3",
        style = "font-family: monospace; font-size: 0.8rem; white-space: pre-line;",
        tags$div(class = "fw-bold mb-1", "Names only:"),
        tags$div(class = "text-muted mb-2", "PlayerOne\nPlayerTwo\nPlayerThree"),
        tags$div(class = "fw-bold mb-1", "Names + Points:"),
        tags$div(class = "text-muted mb-2", "PlayerOne\t9\nPlayerTwo\t7\nPlayerThree\t6"),
        tags$div(class = "fw-bold mb-1", "Names + Points + Deck:"),
        tags$div(class = "text-muted mb-2", "PlayerOne\t9\tBlue Flare\nPlayerTwo\t7\tRed Hybrid\nPlayerThree\t6\tUNKNOWN"),
        tags$div(class = "fw-bold mb-1", "Names + W/L/T:"),
        tags$div(class = "text-muted mb-2", "PlayerOne\t3\t0\t0\nPlayerTwo\t2\t1\t1\nPlayerThree\t2\t2\t0"),
        tags$div(class = "fw-bold mb-1", "Names + W/L/T + Deck:"),
        tags$div(class = "text-muted", "PlayerOne\t3\t0\t0\tBlue Flare\nPlayerTwo\t2\t1\t1\tRed Hybrid")
      ),
      p(class = "text-muted small", "Deck names must match existing archetypes exactly (case-insensitive). Unrecognized decks default to Unknown."),
      tags$textarea(id = "paste_data", class = "form-control", rows = "10",
                    placeholder = "Paste data here...")
    ),
    footer = tagList(
      actionButton("paste_apply", "Fill Grid", class = "btn-primary", icon = icon("table")),
      modalButton("Cancel")
    ),
    size = "l",
    easyClose = TRUE
  ))
})

observeEvent(input$paste_apply, {
  req(rv$admin_grid_data)

  paste_text <- input$paste_data
  if (is.null(paste_text) || nchar(trimws(paste_text)) == 0) {
    notify("No data to paste", type = "warning")
    return()
  }

  rv$admin_grid_data <- sync_grid_inputs(input, rv$admin_grid_data, rv$admin_record_format %||% "points", "admin_")
  grid <- rv$admin_grid_data

  # Parse pasted data using shared helper
  all_decks <- dbGetQuery(rv$db_con, "
    SELECT archetype_id, archetype_name FROM deck_archetypes WHERE is_active = TRUE
  ")
  parsed <- parse_paste_data(paste_text, all_decks)

  if (length(parsed) == 0) {
    notify("No valid lines found", type = "warning")
    return()
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
    fill_count <- fill_count + 1L
  }

  # Close modal and clear textarea
  removeModal()
  notify(sprintf("Filled %d rows from pasted data", fill_count), type = "message")

  # Trigger player match lookup for all filled rows
  for (idx in seq_len(fill_count)) {
    name <- trimws(grid$player_name[idx])
    if (nchar(name) == 0) next

    match_info <- match_player(name, rv$db_con)
    rv$admin_player_matches[[as.character(idx)]] <- match_info
    grid$match_status[idx] <- match_info$status
    if (match_info$status == "matched") {
      grid$matched_player_id[idx] <- match_info$player_id
      grid$matched_member_number[idx] <- match_info$member_number
    } else {
      grid$matched_player_id[idx] <- NA_integer_
      grid$matched_member_number[idx] <- NA_character_
    }
  }
  rv$admin_grid_data <- grid
})

# =============================================================================
# Admin Grid: Deck Request
# =============================================================================

observe({
  req(rv$admin_grid_data)
  grid <- rv$admin_grid_data

  lapply(seq_len(nrow(grid)), function(i) {
    observeEvent(input[[paste0("admin_deck_", i)]], {
      if (!is.null(input[[paste0("admin_deck_", i)]]) &&
          input[[paste0("admin_deck_", i)]] == "__REQUEST_NEW__") {
        rv$admin_deck_request_row <- i
        showModal(modalDialog(
          title = tagList(bsicons::bs_icon("collection-fill"), " Request New Deck"),
          textInput("admin_deck_request_name", "Deck Name", placeholder = "e.g., Blue Flare"),
          layout_columns(
            col_widths = c(6, 6),
            selectInput("admin_deck_request_color", "Primary Color",
                        choices = c("Red", "Blue", "Yellow", "Green", "Purple", "Black", "White")),
            selectInput("admin_deck_request_color2", "Secondary Color (optional)",
                        choices = c("None" = "", "Red", "Blue", "Yellow", "Green", "Purple", "Black", "White"))
          ),
          textInput("admin_deck_request_card_id", "Card ID (optional)",
                    placeholder = "e.g., BT1-001"),
          footer = tagList(
            modalButton("Cancel"),
            actionButton("admin_deck_request_submit", "Submit Request", class = "btn-primary")
          )
        ))
      }
    }, ignoreInit = TRUE)
  })
})

observeEvent(input$admin_deck_request_submit, {
  req(rv$db_con)

  deck_name <- trimws(input$admin_deck_request_name)
  if (nchar(deck_name) == 0) {
    notify("Please enter a deck name", type = "error")
    return()
  }

  primary_color <- input$admin_deck_request_color
  secondary_color <- if (!is.null(input$admin_deck_request_color2) && input$admin_deck_request_color2 != "") {
    input$admin_deck_request_color2
  } else NA_character_

  card_id <- if (!is.null(input$admin_deck_request_card_id) && trimws(input$admin_deck_request_card_id) != "") {
    trimws(input$admin_deck_request_card_id)
  } else NA_character_

  # Check for existing pending request
  existing <- dbGetQuery(rv$db_con, "
    SELECT request_id FROM deck_requests
    WHERE LOWER(deck_name) = LOWER(?) AND status = 'pending'
  ", params = list(deck_name))

  if (nrow(existing) > 0) {
    notify(sprintf("A pending request for '%s' already exists", deck_name), type = "warning")
  } else {
    max_id <- dbGetQuery(rv$db_con, "SELECT COALESCE(MAX(request_id), 0) as max_id FROM deck_requests")$max_id
    new_id <- max_id + 1

    dbExecute(rv$db_con, "
      INSERT INTO deck_requests (request_id, deck_name, primary_color, secondary_color, display_card_id, status)
      VALUES (?, ?, ?, ?, ?, 'pending')
    ", params = list(new_id, deck_name, primary_color, secondary_color, card_id))

    notify(sprintf("Deck request submitted: %s", deck_name), type = "message")
  }

  removeModal()

  # Force grid re-render to update deck dropdowns
  rv$admin_grid_data <- sync_grid_inputs(input, rv$admin_grid_data, rv$admin_record_format %||% "points", "admin_")
})

# =============================================================================
# Admin Grid: Submit Results
# =============================================================================

observeEvent(input$admin_submit_results, {
  req(rv$is_admin, rv$db_con, rv$active_tournament_id)

  rv$admin_grid_data <- sync_grid_inputs(input, rv$admin_grid_data, rv$admin_record_format %||% "points", "admin_")
  grid <- rv$admin_grid_data
  record_format <- rv$admin_record_format %||% "points"

  # Get tournament info
  tournament <- dbGetQuery(rv$db_con, "
    SELECT tournament_id, event_type, rounds FROM tournaments WHERE tournament_id = ?
  ", params = list(rv$active_tournament_id))

  if (nrow(tournament) == 0) {
    notify("Tournament not found", type = "error")
    return()
  }

  rounds <- tournament$rounds
  is_release <- tournament$event_type == "release_event"

  # Filter to rows with player names
  filled_rows <- grid[nchar(trimws(grid$player_name)) > 0, ]

  if (nrow(filled_rows) == 0) {
    notify("No results to submit. Enter at least one player name.", type = "warning")
    return()
  }

  # Get UNKNOWN archetype ID for release events or fallback
  unknown_row <- dbGetQuery(rv$db_con, "SELECT archetype_id FROM deck_archetypes WHERE archetype_name = 'UNKNOWN' LIMIT 1")
  unknown_id <- if (nrow(unknown_row) > 0) unknown_row$archetype_id[1] else NA_integer_

  if (is_release && is.na(unknown_id)) {
    notify("UNKNOWN archetype not found in database", type = "error")
    return()
  }

  tryCatch({
    result_count <- 0L
    max_result_id <- dbGetQuery(rv$db_con, "SELECT COALESCE(MAX(result_id), 0) as max_id FROM results")$max_id

    for (idx in seq_len(nrow(filled_rows))) {
      row <- filled_rows[idx, ]
      name <- trimws(row$player_name)

      # 1. Resolve player
      player <- dbGetQuery(rv$db_con, "
        SELECT player_id FROM players WHERE LOWER(display_name) = LOWER(?) LIMIT 1
      ", params = list(name))

      if (nrow(player) > 0) {
        player_id <- player$player_id
      } else {
        max_pid <- dbGetQuery(rv$db_con, "SELECT COALESCE(MAX(player_id), 0) as max_id FROM players")$max_id
        player_id <- max_pid + 1
        dbExecute(rv$db_con, "INSERT INTO players (player_id, display_name) VALUES (?, ?)",
                  params = list(player_id, name))
      }

      # 2. Convert record
      if (record_format == "points") {
        pts <- row$points
        wins <- pts %/% 3L
        ties <- pts %% 3L
        losses <- max(0L, rounds - wins - ties)
      } else {
        wins <- row$wins
        losses <- row$losses
        ties <- row$ties
      }

      # 3. Resolve deck
      pending_deck_request_id <- NA_integer_
      if (is_release) {
        archetype_id <- unknown_id
      } else {
        deck_input <- input[[paste0("admin_deck_", row$placement)]]

        if (is.null(deck_input) || nchar(deck_input) == 0 || deck_input == "__REQUEST_NEW__") {
          archetype_id <- unknown_id
        } else if (grepl("^pending_", deck_input)) {
          pending_deck_request_id <- as.integer(sub("^pending_", "", deck_input))
          archetype_id <- unknown_id
        } else {
          archetype_id <- as.integer(deck_input)
        }
      }

      # 4. Insert result
      max_result_id <- max_result_id + 1
      dbExecute(rv$db_con, "
        INSERT INTO results (result_id, tournament_id, player_id, archetype_id, pending_deck_request_id,
                             placement, wins, losses, ties)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ", params = list(max_result_id, rv$active_tournament_id, player_id, archetype_id,
                       pending_deck_request_id, row$placement, wins, losses, ties))

      result_count <- result_count + 1L
    }

    # Recalculate ratings
    recalculate_ratings_cache(rv$db_con)
    rv$data_refresh <- (rv$data_refresh %||% 0) + 1

    notify(sprintf("Tournament submitted! %d results recorded.", result_count),
                     type = "message", duration = 5)

    # Reset to Step 1
    rv$active_tournament_id <- NULL
    rv$wizard_step <- 1
    rv$current_results <- data.frame()
    rv$admin_grid_data <- NULL
    rv$admin_player_matches <- list()

    # Clear Step 1 form fields
    updateSelectInput(session, "tournament_store", selected = "")
    updateDateInput(session, "tournament_date", value = NA)
    updateSelectInput(session, "tournament_type", selected = "")
    updateSelectInput(session, "tournament_format", selected = "")
    updateNumericInput(session, "tournament_players", value = 8)
    updateNumericInput(session, "tournament_rounds", value = 3)
    updateRadioButtons(session, "admin_record_format", selected = "points")

  }, error = function(e) {
    notify(paste("Error submitting results:", e$message), type = "error")
  })
})
