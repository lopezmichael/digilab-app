# =============================================================================
# Admin: Edit Tournaments Server Logic
# =============================================================================

# Edit grid state
rv$edit_grid_data <- NULL
rv$edit_record_format <- "points"
rv$edit_player_matches <- list()
rv$edit_deleted_result_ids <- c()
rv$edit_grid_tournament_id <- NULL
rv$edit_wlt_override <- FALSE

# Update edit form dropdowns when data changes
# Only fires when on admin_tournaments tab (prevents race condition with lazy-loaded UI)
observe({
  rv$current_nav
  req(rv$current_nav == "admin_tournaments")

  rv$format_refresh

  # Check if UI has rendered yet
  if (is.null(input$edit_tournament_date)) {
    # UI not ready yet, retry shortly
    invalidateLater(100)
    return()
  }

  # Capture current selections and choices
  current_store <- isolate(input$edit_tournament_store)
  store_choices <- get_store_choices(db_pool, include_none = TRUE)
  current_format <- isolate(input$edit_tournament_format)
  format_choices <- get_format_choices(db_pool)

  # If store choices came back empty (likely prepared stmt collision), retry
  if (length(store_choices) <= 1) {
    invalidateLater(500)
  }

  updateSelectInput(session, "edit_tournament_store",
                    choices = store_choices,
                    selected = current_store)
  updateSelectInput(session, "edit_tournament_format",
                    choices = format_choices,
                    selected = current_format)
})

# Auto-select tournament when navigated from duplicate modal
observe({
  req(rv$navigate_to_tournament_id)

  # Trigger the same logic as clicking a row
  tournament_id <- rv$navigate_to_tournament_id
  rv$navigate_to_tournament_id <- NULL  # Clear to prevent re-triggering

  # Get tournament details
  tournament <- safe_query(db_pool, "
    SELECT t.*, s.name as store_name
    FROM tournaments t
    LEFT JOIN stores s ON t.store_id = s.store_id
    WHERE t.tournament_id = $1
  ", params = list(tournament_id), default = data.frame())

  if (nrow(tournament) == 0) return()

  # Fill form (same as click handler)
  updateTextInput(session, "editing_tournament_id", value = as.character(tournament$tournament_id))
  updateSelectInput(session, "edit_tournament_store", selected = tournament$store_id)
  updateDateInput(session, "edit_tournament_date", value = tournament$event_date)
  updateSelectInput(session, "edit_tournament_type", selected = tournament$event_type)
  updateSelectInput(session, "edit_tournament_format", selected = tournament$format)
  updateNumericInput(session, "edit_tournament_players", value = tournament$player_count)
  updateNumericInput(session, "edit_tournament_rounds", value = tournament$rounds)

  # Show buttons
  shinyjs::show("update_tournament")
  shinyjs::show("delete_tournament")
  shinyjs::show("view_results_btn_container")

  notify(sprintf("Editing: %s - %s", tournament$store_name, tournament$event_date),
                   type = "message", duration = 3)
})

# Debounce admin search input (300ms)
admin_tournament_search_debounced <- reactive(input$admin_tournament_search) |> debounce(300)

# Tournament list table
output$admin_tournament_list <- renderReactable({


  # Trigger refresh
  input$update_tournament
  input$confirm_delete_tournament
  input$admin_tournaments_show_all_scenes

  # Search filter
  search <- admin_tournament_search_debounced() %||% ""
  scene <- rv$current_scene
  show_all <- isTRUE(input$admin_tournaments_show_all_scenes) && isTRUE(rv$is_superadmin)

  # Build scene filter
  scene_filter <- ""
  query_params <- list()
  if (!show_all && !is.null(scene) && scene != "" && scene != "all") {
    if (scene == "online") {
      scene_filter <- "AND s.is_online = TRUE"
    } else {
      scene_filter <- "AND s.scene_id = (SELECT scene_id FROM scenes WHERE slug = $1)"
      query_params <- c(query_params, list(scene))
    }
  }

  # Build query
  query <- sprintf("
    SELECT t.tournament_id,
           s.name as store_name,
           t.event_date,
           t.event_type,
           t.format,
           t.player_count,
           t.rounds,
           COUNT(r.result_id) as results_entered
    FROM tournaments t
    LEFT JOIN stores s ON t.store_id = s.store_id
    LEFT JOIN results r ON t.tournament_id = r.tournament_id
    WHERE 1=1 %s
  ", scene_filter)

  if (nchar(search) > 0) {
    next_idx <- if (length(query_params) > 0) length(query_params) + 1 else 1
    query <- paste0(query, sprintf(" AND LOWER(s.name) LIKE LOWER($%d)", next_idx))
    query_params <- c(query_params, list(paste0("%", search, "%")))
  }

  query <- paste0(query, " GROUP BY t.tournament_id, s.name, t.event_date, t.event_type, t.format, t.player_count, t.rounds
                          ORDER BY t.event_date DESC")

  data <- safe_query(db_pool, query, params = if (length(query_params) > 0) query_params else NULL, default = data.frame())

  if (nrow(data) == 0) {
    return(reactable(data.frame(Message = "No tournaments found")))
  }

  # Prepare display data
  display_data <- data.frame(
    ID = data$tournament_id,
    Store = data$store_name,
    Date = as.character(data$event_date),
    Type = sapply(data$event_type, format_event_type),
    Format = data$format,
    Players = data$player_count,
    Results = data$results_entered,
    stringsAsFactors = FALSE
  )

  # Store tournament_id in a way we can retrieve on click
  reactable(
    display_data,
    selection = "single",
    searchable = TRUE,
    onClick = JS("function(rowInfo, column) {
      if (rowInfo) {
        Shiny.setInputValue('admin_tournament_list_clicked', {
          tournament_id: rowInfo.row.ID,
          nonce: Math.random()
        }, {priority: 'event'});
      }
    }"),
    rowStyle = function(index) {
      if (!is.null(display_data$Results[index]) && display_data$Results[index] == 0) {
        list(background = "rgba(245, 183, 0, 0.15)", borderLeft = "2px solid #F5B700")
      }
    },
    highlight = TRUE,
    compact = TRUE,
    pagination = TRUE,
    defaultPageSize = 12,
    columns = list(
      ID = colDef(show = FALSE),
      Store = colDef(minWidth = 160, style = list(whiteSpace = "normal")),
      Date = colDef(width = 105),
      Type = colDef(width = 95),
      Format = colDef(width = 80),
      Players = colDef(width = 65, align = "center"),
      Results = colDef(width = 65, align = "center",
        cell = function(value) {
          if (value == 0) {
            span(class = "text-muted", "\u2014")
          } else {
            value
          }
        }
      )
    )
  )
})

# Click row to edit
observeEvent(input$admin_tournament_list_clicked, {

  tournament_id <- input$admin_tournament_list_clicked$tournament_id

  if (is.null(tournament_id)) return()

  # Get tournament details
  tournament <- safe_query(db_pool, "
    SELECT t.*, s.name as store_name
    FROM tournaments t
    LEFT JOIN stores s ON t.store_id = s.store_id
    WHERE t.tournament_id = $1
  ", params = list(tournament_id), default = data.frame())

  if (nrow(tournament) == 0) return()

  # Fill form
  updateTextInput(session, "editing_tournament_id", value = as.character(tournament$tournament_id))
  updateSelectInput(session, "edit_tournament_store", selected = tournament$store_id)
  updateDateInput(session, "edit_tournament_date", value = tournament$event_date)
  updateSelectInput(session, "edit_tournament_type", selected = tournament$event_type)
  updateSelectInput(session, "edit_tournament_format", selected = tournament$format)
  updateNumericInput(session, "edit_tournament_players", value = tournament$player_count)
  updateNumericInput(session, "edit_tournament_rounds", value = tournament$rounds)

  # Show buttons
  shinyjs::show("update_tournament")
  shinyjs::show("delete_tournament")

  # Hide edit grid if switching to a different tournament
  shinyjs::hide("edit_results_grid_section")
  shinyjs::show("edit_tournaments_main")
  rv$edit_grid_data <- NULL
  rv$edit_player_matches <- list()
  rv$edit_grid_tournament_id <- NULL
  rv$edit_wlt_override <- FALSE
  shinyjs::runjs("var el = document.getElementById('edit_wlt_override'); if (el) el.checked = false;")

  notify(sprintf("Editing: %s - %s", tournament$store_name, tournament$event_date),
                   type = "message", duration = 2)
})

# Tournament stats info
output$tournament_stats_info <- renderUI({
  req(db_pool, input$editing_tournament_id)

  tid <- as.integer(input$editing_tournament_id)

  # Get results count
  results_count_df <- safe_query(db_pool, "
    SELECT COUNT(*) as cnt FROM results WHERE tournament_id = $1
  ", params = list(tid), default = data.frame(cnt = 0L))
  results_count <- results_count_df$cnt

  # Get winner info
  winner <- safe_query(db_pool, "
    SELECT p.display_name, da.archetype_name
    FROM results r
    JOIN players p ON r.player_id = p.player_id
    LEFT JOIN deck_archetypes da ON r.archetype_id = da.archetype_id
    WHERE r.tournament_id = $1 AND r.placement = 1
  ", params = list(tid), default = data.frame())

  tagList(
    div(
      class = "d-flex gap-4 text-muted small",
      div(bsicons::bs_icon("people-fill"), sprintf(" %d results entered", as.integer(results_count))),
      if (nrow(winner) > 0) {
        div(bsicons::bs_icon("trophy-fill"),
            sprintf(" Winner: %s (%s)", winner$display_name, winner$archetype_name %||% "Unknown deck"))
      }
    )
  )
})

# Update tournament
observeEvent(input$update_tournament, {
  req(rv$is_admin, db_pool, input$editing_tournament_id)

  clear_all_field_errors(session)

  tournament_id <- as.integer(input$editing_tournament_id)
  store_id <- input$edit_tournament_store
  event_date <- input$edit_tournament_date
  event_type <- input$edit_tournament_type
  format <- input$edit_tournament_format
  player_count <- input$edit_tournament_players
  rounds <- input$edit_tournament_rounds

  # Validation
  if (is.null(store_id) || store_id == "") {
    show_field_error(session, "edit_tournament_store")
    notify("Please select a store", type = "error")
    return()
  }

  if (is.null(event_type) || event_type == "") {
    show_field_error(session, "edit_tournament_type")
    notify("Please select an event type", type = "error")
    return()
  }

  tryCatch({
    safe_execute(db_pool, "
      UPDATE tournaments
      SET store_id = $1, event_date = $2, event_type = $3, format = $4,
          player_count = $5, rounds = $6, updated_at = CURRENT_TIMESTAMP, updated_by = $7
      WHERE tournament_id = $8
    ", params = list(as.integer(store_id), event_date, event_type, format,
                     player_count, rounds, current_admin_username(rv), tournament_id))

    notify("Tournament updated", type = "message")

    # Reset form
    reset_tournament_form()

    # Trigger table refresh (admin + public tables)
    rv$tournament_refresh <- (rv$tournament_refresh %||% 0) + 1
    rv$refresh_tournaments <- rv$refresh_tournaments + 1

  }, error = function(e) {
    notify(paste("Error:", e$message), type = "error")
  })
})

# Cancel edit tournament
observeEvent(input$cancel_edit_tournament, {
  reset_tournament_form()
  # Also hide the edit grid if open
  shinyjs::hide("edit_results_grid_section")
  shinyjs::show("edit_tournaments_main")
  rv$edit_grid_data <- NULL
  rv$edit_player_matches <- list()
  rv$edit_deleted_result_ids <- c()
  rv$edit_grid_tournament_id <- NULL
  rv$edit_wlt_override <- FALSE
  shinyjs::runjs("var el = document.getElementById('edit_wlt_override'); if (el) el.checked = false;")
})

# Helper function to reset form
reset_tournament_form <- function() {
  updateTextInput(session, "editing_tournament_id", value = "")
  updateSelectInput(session, "edit_tournament_store", selected = "")
  updateDateInput(session, "edit_tournament_date", value = Sys.Date())
  updateSelectInput(session, "edit_tournament_type", selected = "")
  updateNumericInput(session, "edit_tournament_players", value = 8)
  updateNumericInput(session, "edit_tournament_rounds", value = 3)

  shinyjs::hide("update_tournament")
  shinyjs::hide("delete_tournament")
  shinyjs::hide("view_results_btn_container")
}

# Delete button click - show modal
observeEvent(input$delete_tournament, {
  req(rv$is_admin, input$editing_tournament_id)

  tournament_id <- as.integer(input$editing_tournament_id)

  # Get tournament info and results count
  tournament <- safe_query(db_pool, "
    SELECT t.*, s.name as store_name,
           (SELECT COUNT(*)::int FROM results WHERE tournament_id = t.tournament_id) as results_count
    FROM tournaments t
    LEFT JOIN stores s ON t.store_id = s.store_id
    WHERE t.tournament_id = $1
  ", params = list(tournament_id), default = data.frame())

  showModal(modalDialog(
    title = "Confirm Delete",
    div(
      p(sprintf("Are you sure you want to delete this tournament?")),
      p(tags$strong(sprintf("%s - %s", tournament$store_name, tournament$event_date))),
      if (tournament$results_count > 0) {
        p(class = "text-danger",
          bsicons::bs_icon("exclamation-triangle-fill"),
          sprintf(" This will also delete %d result(s)!", as.integer(tournament$results_count)))
      },
      p(class = "text-muted small", "This action cannot be undone.")
    ),
    footer = tagList(
      actionButton("confirm_delete_tournament", "Delete", class = "btn-danger"),
      modalButton("Cancel")
    ),
    easyClose = TRUE
  ))
})

# Confirm delete tournament
observeEvent(input$confirm_delete_tournament, {
  req(rv$is_admin, db_pool, input$editing_tournament_id)

  tournament_id <- as.integer(input$editing_tournament_id)

  rows <- tryCatch(
    with_transaction(db_pool, function(conn) {
      DBI::dbExecute(conn, "DELETE FROM results WHERE tournament_id = $1", params = list(tournament_id))
      DBI::dbExecute(conn, "DELETE FROM tournaments WHERE tournament_id = $1", params = list(tournament_id))
    }),
    error = function(e) {
      notify(paste("Failed to delete tournament:", e$message), type = "error")
      0L
    }
  )

  if (rows == 0) {
    notify("Failed to delete tournament. Try again.", type = "error")
    return()
  }

  notify("Tournament and results deleted", type = "message")

  # Hide modal, reset form, and hide edit grid
  removeModal()
  reset_tournament_form()
  shinyjs::hide("edit_results_grid_section")
  shinyjs::show("edit_tournaments_main")
  rv$edit_grid_data <- NULL
  rv$edit_player_matches <- list()
  rv$edit_deleted_result_ids <- c()
  rv$edit_grid_tournament_id <- NULL
  rv$edit_wlt_override <- FALSE
  shinyjs::runjs("var el = document.getElementById('edit_wlt_override'); if (el) el.checked = false;")

  # Trigger table refresh (admin + public tables)
  rv$tournament_refresh <- (rv$tournament_refresh %||% 0) + 1
  rv$refresh_tournaments <- rv$refresh_tournaments + 1
  rv$refresh_players <- rv$refresh_players + 1

  defer_ratings_recalc(db_pool, notify)
})

# Show View/Edit Results button when tournament is selected
observeEvent(input$admin_tournament_list_clicked, {
  # Button is shown in the existing click handler, add this line there
  shinyjs::show("view_results_btn_container")
}, priority = -1)  # Run after main handler

# Hide button when form is cancelled/reset
observeEvent(input$cancel_edit_tournament, {
  shinyjs::hide("view_results_btn_container")
}, priority = -1)

# Open edit results grid
observeEvent(input$view_edit_results, {
  req(db_pool, input$editing_tournament_id)

  tournament_id <- as.integer(input$editing_tournament_id)
  rv$edit_grid_tournament_id <- tournament_id

  # Get tournament's expected player count
  tournament_info <- safe_query(db_pool, "SELECT player_count FROM tournaments WHERE tournament_id = $1",
                                params = list(tournament_id), default = data.frame())
  expected_players <- if (nrow(tournament_info) > 0 && !is.na(tournament_info$player_count[1])) {
    tournament_info$player_count[1]
  } else {
    8  # Fallback default
  }

  # Load existing results into grid
  grid <- load_grid_from_results(tournament_id, db_pool)

  # Read stored record_format from tournament (no more inference)
  fmt_row <- safe_query(db_pool, "SELECT record_format FROM tournaments WHERE tournament_id = $1",
                        params = list(tournament_id), default = data.frame())
  rv$edit_record_format <- if (nrow(fmt_row) > 0 && !is.null(fmt_row$record_format)) {
    fmt_row$record_format
  } else {
    "points"  # fallback for pre-migration tournaments
  }

  # Add a couple of blank rows for late additions
  current_count <- nrow(grid)
  pad_count <- max(current_count + 2, expected_players)
  if (current_count < pad_count) {
    extra <- init_grid_data(pad_count - current_count)
    extra$placement <- seq(current_count + 1, pad_count)
    grid <- rbind(grid, extra)
  }

  rv$edit_grid_data <- grid
  rv$edit_deleted_result_ids <- c()

  # Build player matches from loaded data
  rv$edit_player_matches <- list()
  for (i in seq_len(current_count)) {
    if (nchar(trimws(grid$player_name[i])) > 0) {
      rv$edit_player_matches[[as.character(i)]] <- list(
        status = "matched",
        player_id = grid$matched_player_id[i],
        member_number = grid$matched_member_number[i]
      )
    }
  }

  shinyjs::hide("edit_tournaments_main")
  shinyjs::show("edit_results_grid_section")
})

# Edit grid rendering
output$edit_grid_table <- renderUI({
  req(rv$edit_grid_data)

  grid <- rv$edit_grid_data
  record_format <- rv$edit_record_format %||% "points"

  # Check if release event
  is_release <- FALSE
  if (!is.null(rv$edit_grid_tournament_id)) {
    t_info <- safe_query(db_pool, "SELECT event_type FROM tournaments WHERE tournament_id = $1",
                         params = list(rv$edit_grid_tournament_id), default = data.frame())
    if (nrow(t_info) > 0) is_release <- t_info$event_type[1] == "release_event"
  }

  deck_choices <- build_deck_choices(db_pool)

  render_grid_ui(grid, record_format, is_release, deck_choices, rv$edit_player_matches, "edit_",
                 placement_editable = TRUE, show_add_player_btn = TRUE,
                 show_wlt_override = isTRUE(rv$edit_wlt_override))
})

# Edit grid summary bar
output$edit_grid_summary_bar <- renderUI({
  req(db_pool, rv$edit_grid_tournament_id)

  tournament <- safe_query(db_pool, "
    SELECT t.*, s.name as store_name
    FROM tournaments t
    LEFT JOIN stores s ON t.store_id = s.store_id
    WHERE t.tournament_id = $1
  ", params = list(rv$edit_grid_tournament_id), default = data.frame())

  if (nrow(tournament) == 0) return(NULL)

  div(
    class = "tournament-summary-bar mb-3",
    div(class = "summary-detail", bsicons::bs_icon("shop"), tournament$store_name),
    div(class = "summary-detail", bsicons::bs_icon("calendar"), as.character(tournament$event_date)),
    div(class = "summary-detail", bsicons::bs_icon("tag"), tournament$format),
    div(class = "summary-detail", bsicons::bs_icon("people"), paste(tournament$player_count, "players"))
  )
})

# Edit grid format badge
output$edit_record_format_badge <- renderUI({
  format <- rv$edit_record_format %||% "points"
  label <- if (format == "points") "Points mode" else "W-L-T mode"
  span(class = "badge bg-info", label)
})

# Edit grid filled count
output$edit_filled_count <- renderUI({
  req(rv$edit_grid_data)
  grid <- rv$edit_grid_data
  filled <- sum(nchar(trimws(grid$player_name)) > 0)
  total <- nrow(grid)
  span(class = "text-muted small", sprintf("Filled: %d/%d", filled, total))
})

# Cancel edit grid
observeEvent(input$edit_grid_cancel, {
  shinyjs::hide("edit_results_grid_section")
  shinyjs::show("edit_tournaments_main")
  rv$edit_grid_data <- NULL
  rv$edit_player_matches <- list()
  rv$edit_deleted_result_ids <- c()
  rv$edit_grid_tournament_id <- NULL
  rv$edit_wlt_override <- FALSE
  shinyjs::runjs("var el = document.getElementById('edit_wlt_override'); if (el) el.checked = false;")
})

# =============================================================================
# Edit Grid: Interactivity (delete, player matching, paste, deck requests)
# =============================================================================

# Delete row handler
observeEvent(input$edit_delete_row, {
  req(rv$edit_grid_data)
  row_idx <- as.integer(input$edit_delete_row)
  if (is.null(row_idx) || row_idx < 1 || row_idx > nrow(rv$edit_grid_data)) return()

  rv$edit_grid_data <- sync_grid_inputs(input, rv$edit_grid_data, rv$edit_record_format %||% "points", "edit_",
                                       placement_editable = TRUE, wlt_override = isTRUE(rv$edit_wlt_override))
  grid <- rv$edit_grid_data

  # Track deleted result_ids for DB deletion on save
  deleted_result_id <- grid$result_id[row_idx]
  if (!is.na(deleted_result_id)) {
    rv$edit_deleted_result_ids <- c(rv$edit_deleted_result_ids, deleted_result_id)
  }

  # Remove the row
  grid <- grid[-row_idx, ]

  # Append blank row
  blank_row <- data.frame(
    placement = nrow(grid) + 1,
    player_name = "", member_number = "", points = 0L, wins = 0L, losses = 0L, ties = 0L,
    deck_id = NA_integer_, match_status = "", matched_player_id = NA_integer_,
    matched_member_number = NA_character_, result_id = NA_integer_,
    stringsAsFactors = FALSE
  )
  grid <- rbind(grid, blank_row)
  grid$placement <- seq_len(nrow(grid))

  # Shift match indices
  new_matches <- list()
  for (j in seq_len(nrow(grid))) {
    old_idx <- if (j < row_idx) j else j + 1
    if (!is.null(rv$edit_player_matches[[as.character(old_idx)]])) {
      new_matches[[as.character(j)]] <- rv$edit_player_matches[[as.character(old_idx)]]
    }
  }
  rv$edit_player_matches <- new_matches
  rv$edit_grid_data <- grid
  notify(paste0("Row removed. Players renumbered 1-", nrow(grid), "."), type = "message", duration = 3)
})

# Add Player button handler
observeEvent(input$edit_add_player, {
  req(rv$edit_grid_data)

  rv$edit_grid_data <- sync_grid_inputs(input, rv$edit_grid_data, rv$edit_record_format %||% "points", "edit_",
                                       placement_editable = TRUE, wlt_override = isTRUE(rv$edit_wlt_override))

  new_placement <- nrow(rv$edit_grid_data) + 1L
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
  rv$edit_grid_data <- rbind(rv$edit_grid_data, blank_row)
})

# W/L/T override toggle handler
observeEvent(input$edit_wlt_override, {
  rv$edit_wlt_override <- isTRUE(input$edit_wlt_override)
})

# Attach blur handlers for edit grid (player name + placement)
observe({
  req(rv$edit_grid_data)
  shinyjs::runjs("
    $(document).off('blur.editGrid').on('blur.editGrid', 'input[id^=\"edit_player_\"]', function() {
      var id = $(this).attr('id');
      var rowNum = parseInt(id.replace('edit_player_', ''));
      if (!isNaN(rowNum)) {
        Shiny.setInputValue('edit_player_blur', {row: rowNum, name: $(this).val(), ts: Date.now()}, {priority: 'event'});
      }
    });
    $(document).off('blur.editPlacement').on('blur.editPlacement', 'input[id^=\"edit_placement_\"]', function() {
      Shiny.setInputValue('edit_placement_blur', {ts: Date.now()}, {priority: 'event'});
    });
  ")
})

# Placement auto-reorder on blur
observeEvent(input$edit_placement_blur, {
  req(rv$edit_grid_data)

  grid <- sync_grid_inputs(input, rv$edit_grid_data, rv$edit_record_format %||% "points", "edit_",
                           placement_editable = TRUE, wlt_override = isTRUE(rv$edit_wlt_override))
  grid$placement <- validate_placements(grid$placement)

  old_order <- seq_len(nrow(grid))
  new_order <- order(grid$placement)

  if (!identical(old_order, new_order)) {
    grid <- grid[new_order, ]
    rownames(grid) <- NULL

    # Remap edit_player_matches keys to new row positions
    old_matches <- rv$edit_player_matches
    new_matches <- list()
    for (new_idx in seq_along(new_order)) {
      old_idx <- new_order[new_idx]
      key <- as.character(old_idx)
      if (!is.null(old_matches[[key]])) {
        new_matches[[as.character(new_idx)]] <- old_matches[[key]]
      }
    }
    rv$edit_player_matches <- new_matches
  }

  rv$edit_grid_data <- grid
})

observeEvent(input$edit_player_blur, {
  req(db_pool, rv$edit_grid_data)

  info <- input$edit_player_blur
  row_num <- info$row
  name <- trimws(info$name)

  if (is.null(row_num) || is.na(row_num)) return()
  if (row_num < 1 || row_num > nrow(rv$edit_grid_data)) return()

  rv$edit_grid_data <- sync_grid_inputs(input, rv$edit_grid_data, rv$edit_record_format %||% "points", "edit_",
                                       placement_editable = TRUE, wlt_override = isTRUE(rv$edit_wlt_override))

  if (nchar(name) == 0) {
    rv$edit_player_matches[[as.character(row_num)]] <- NULL
    rv$edit_grid_data$match_status[row_num] <- ""
    rv$edit_grid_data$matched_player_id[row_num] <- NA_integer_
    rv$edit_grid_data$matched_member_number[row_num] <- NA_character_
    return()
  }

  member_num <- input[[paste0("edit_member_", row_num)]]
  # Get scene_id from tournament's store for scene-scoped matching
  tournament_store <- safe_query(db_pool, "
    SELECT s.scene_id FROM tournaments t
    JOIN stores s ON t.store_id = s.store_id
    WHERE t.tournament_id = $1
  ", params = list(rv$edit_tournament_id), default = data.frame())
  scene_id <- if (nrow(tournament_store) > 0) tournament_store$scene_id[1] else NULL
  match_info <- match_player(name, db_pool, member_number = member_num, scene_id = scene_id)
  rv$edit_player_matches[[as.character(row_num)]] <- match_info
  rv$edit_grid_data$match_status[row_num] <- match_info$status
  if (match_info$status == "matched") {
    rv$edit_grid_data$matched_player_id[row_num] <- match_info$player_id
    rv$edit_grid_data$matched_member_number[row_num] <- match_info$member_number
  } else if (match_info$status == "ambiguous") {
    rv$edit_grid_data$matched_player_id[row_num] <- match_info$candidates$player_id[1]
    rv$edit_grid_data$matched_member_number[row_num] <- match_info$candidates$member_number[1]
  } else {
    rv$edit_grid_data$matched_player_id[row_num] <- NA_integer_
    rv$edit_grid_data$matched_member_number[row_num] <- NA_character_
  }
})

# =============================================================================
# Edit Grid: Disambiguation Picker Modal
# =============================================================================

observeEvent(input$edit_disambiguate_row, {
  row_num <- input$edit_disambiguate_row
  req(row_num, rv$edit_player_matches)

  match_info <- rv$edit_player_matches[[as.character(row_num)]]
  req(match_info, match_info$status == "ambiguous")

  candidates <- match_info$candidates

  # Enrich candidates with event count and last tournament info
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

  # Build radio buttons for each candidate
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
        tags$input(type = "radio", name = "edit_disambiguate_choice",
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
      rv$edit_grid_data$player_name[row_num])),
    div(id = "edit_disambiguate_choices", candidate_choices),
    hr(),
    div(class = "d-flex align-items-center gap-2",
      tags$input(type = "radio", name = "edit_disambiguate_choice", value = "new", id = "edit_disambiguate_new"),
      tags$label(`for` = "edit_disambiguate_new", "None of these \u2014 create a new player")
    ),
    tags$script(HTML("
      $('#edit_disambiguate_confirm_btn').on('click', function() {
        var selected = $('input[name=edit_disambiguate_choice]:checked').val();
        if (selected) {
          Shiny.setInputValue('edit_disambiguate_confirm', {
            row: ", row_num, ",
            player_id: selected
          }, {priority: 'event'});
        }
      });
    ")),
    footer = tagList(
      modalButton("Cancel"),
      actionButton("edit_disambiguate_confirm_btn", "Confirm", class = "btn-primary")
    )
  ))
})

# Handle edit disambiguation confirmation
observeEvent(input$edit_disambiguate_confirm, {
  info <- input$edit_disambiguate_confirm
  row_num <- info$row
  selected_id <- info$player_id

  req(row_num, selected_id)

  if (selected_id == "new") {
    rv$edit_grid_data$match_status[row_num] <- "new"
    rv$edit_grid_data$matched_player_id[row_num] <- NA_integer_
    rv$edit_grid_data$matched_member_number[row_num] <- NA_character_
    rv$edit_player_matches[[as.character(row_num)]] <- list(status = "new")
  } else {
    pid <- as.integer(selected_id)
    player_info <- safe_query(db_pool, "SELECT member_number FROM players WHERE player_id = $1",
                              params = list(pid), default = data.frame(member_number = NA_character_))
    rv$edit_grid_data$match_status[row_num] <- "matched"
    rv$edit_grid_data$matched_player_id[row_num] <- pid
    rv$edit_grid_data$matched_member_number[row_num] <- player_info$member_number[1]
    rv$edit_player_matches[[as.character(row_num)]] <- list(
      status = "matched",
      player_id = pid,
      member_number = player_info$member_number[1]
    )
  }

  removeModal()
})

# =============================================================================
# Edit Grid: "Did you mean?" Similar Player Modal (PID5)
# =============================================================================

observeEvent(input$edit_similar_player_row, {
  row_num <- input$edit_similar_player_row
  req(row_num, rv$edit_player_matches)

  match_info <- rv$edit_player_matches[[as.character(row_num)]]
  req(match_info, match_info$status == "new_similar")

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
        tags$input(type = "radio", name = "edit_similar_choice",
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

  player_name <- rv$edit_grid_data$player_name[row_num]

  showModal(modalDialog(
    title = tagList(bsicons::bs_icon("person-exclamation"), " Did you mean?"),
    p(class = "text-muted", sprintf(
      "\"%s\" wasn't found, but these similar players exist:", player_name)),
    div(id = "edit_similar_choices", candidate_choices),
    hr(),
    div(class = "d-flex align-items-center gap-2",
      tags$input(type = "radio", name = "edit_similar_choice", value = "new",
                 id = "edit_similar_new", checked = "checked"),
      tags$label(`for` = "edit_similar_new",
        tags$strong(sprintf("Create new player \"%s\"", player_name)))
    ),
    tags$script(HTML("
      $('#edit_similar_confirm_btn').on('click', function() {
        var selected = $('input[name=edit_similar_choice]:checked').val();
        if (selected) {
          Shiny.setInputValue('edit_similar_confirm', {
            row: ", row_num, ",
            player_id: selected
          }, {priority: 'event'});
        }
      });
    ")),
    footer = tagList(
      modalButton("Cancel"),
      actionButton("edit_similar_confirm_btn", "Confirm", class = "btn-primary")
    )
  ))
})

observeEvent(input$edit_similar_confirm, {
  info <- input$edit_similar_confirm
  row_num <- info$row
  selected_id <- info$player_id

  req(row_num, selected_id)

  if (selected_id == "new") {
    rv$edit_grid_data$match_status[row_num] <- "new"
    rv$edit_grid_data$matched_player_id[row_num] <- NA_integer_
    rv$edit_grid_data$matched_member_number[row_num] <- NA_character_
    rv$edit_player_matches[[as.character(row_num)]] <- list(status = "new")
  } else {
    pid <- as.integer(selected_id)
    player_info <- safe_query(db_pool, "SELECT member_number FROM players WHERE player_id = $1",
                              params = list(pid), default = data.frame(member_number = NA_character_))
    rv$edit_grid_data$match_status[row_num] <- "matched"
    rv$edit_grid_data$matched_player_id[row_num] <- pid
    rv$edit_grid_data$matched_member_number[row_num] <- player_info$member_number[1]
    rv$edit_player_matches[[as.character(row_num)]] <- list(
      status = "matched",
      player_id = pid,
      member_number = player_info$member_number[1]
    )
  }

  removeModal()
})

# Paste from spreadsheet modal
observeEvent(input$edit_paste_btn, {
  showModal(modalDialog(
    title = tagList(bsicons::bs_icon("clipboard"), " Paste from Spreadsheet"),
    tagList(
      p(class = "text-muted", "Paste data with one player per line. Columns separated by tabs (from a spreadsheet) or 2+ spaces."),
      p(class = "text-muted small mb-2", "Supported formats:"),
      tags$div(
        class = "bg-body-secondary rounded p-2 mb-3",
        style = "font-family: monospace; font-size: 0.8rem; white-space: pre-line;",
        tags$div(class = "fw-bold mb-1", "Names only:"),
        tags$div(class = "text-muted mb-2", "PlayerOne\nPlayerTwo"),
        tags$div(class = "fw-bold mb-1", "Names + Points:"),
        tags$div(class = "text-muted mb-2", "PlayerOne\t9\nPlayerTwo\t7"),
        tags$div(class = "fw-bold mb-1", "Names + W/L/T:"),
        tags$div(class = "text-muted", "PlayerOne\t3\t0\t0\nPlayerTwo\t2\t1\t1")
      ),
      tags$textarea(id = "edit_paste_data", class = "form-control", rows = "10",
                    placeholder = "Paste data here...")
    ),
    footer = tagList(
      actionButton("edit_paste_apply", "Fill Grid", class = "btn-primary", icon = icon("table")),
      modalButton("Cancel")
    ),
    size = "l",
    easyClose = TRUE
  ))
})

observeEvent(input$edit_paste_apply, {
  req(rv$edit_grid_data)

  paste_text <- input$edit_paste_data
  if (is.null(paste_text) || nchar(trimws(paste_text)) == 0) {
    notify("No data to paste", type = "warning")
    return()
  }

  rv$edit_grid_data <- sync_grid_inputs(input, rv$edit_grid_data, rv$edit_record_format %||% "points", "edit_",
                                       placement_editable = TRUE, wlt_override = isTRUE(rv$edit_wlt_override))
  grid <- rv$edit_grid_data

  all_decks <- safe_query(db_pool, "
    SELECT archetype_id, archetype_name FROM deck_archetypes WHERE is_active = TRUE
  ", default = data.frame())

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

  removeModal()
  notify(sprintf("Filled %d rows from pasted data", fill_count), type = "message")

  # Get scene_id for scene-scoped player matching
  tournament_store <- safe_query(db_pool, "
    SELECT s.scene_id FROM tournaments t
    JOIN stores s ON t.store_id = s.store_id
    WHERE t.tournament_id = $1
  ", params = list(rv$edit_tournament_id), default = data.frame())
  scene_id <- if (nrow(tournament_store) > 0) tournament_store$scene_id[1] else NULL

  for (idx in seq_len(fill_count)) {
    match_info <- match_player(trimws(grid$player_name[idx]), db_pool, member_number = grid$member_number[idx], scene_id = scene_id)
    if (!is.null(match_info)) {
      rv$edit_player_matches[[as.character(idx)]] <- match_info
      grid$match_status[idx] <- match_info$status
      if (match_info$status == "matched") {
        grid$matched_player_id[idx] <- match_info$player_id
        grid$matched_member_number[idx] <- match_info$member_number
      } else if (match_info$status == "ambiguous") {
        grid$matched_player_id[idx] <- match_info$candidates$player_id[1]
        grid$matched_member_number[idx] <- match_info$candidates$member_number[1]
      }
    }
  }
  rv$edit_grid_data <- grid
})

# Deck request handlers for edit grid — created ONCE at init (not inside observe)
lapply(1:128, function(i) {
  observeEvent(input[[paste0("edit_deck_", i)]], {
    if (isTRUE(input[[paste0("edit_deck_", i)]] == "__REQUEST_NEW__")) {
      rv$admin_deck_request_row <- i
      showModal(modalDialog(
        title = tagList(bsicons::bs_icon("collection-fill"), " Request New Deck"),
        textInput("editgrid_deck_request_name", "Deck Name", placeholder = "e.g., Blue Flare"),
        layout_columns(
          col_widths = c(6, 6),
          selectInput("editgrid_deck_request_color", "Primary Color",
                      choices = c("Red", "Blue", "Yellow", "Green", "Purple", "Black", "White"),
                      selectize = FALSE),
          selectInput("editgrid_deck_request_color2", "Secondary Color (optional)",
                      choices = c("None" = "", "Red", "Blue", "Yellow", "Green", "Purple", "Black", "White"),
                      selectize = FALSE)
        ),
        textInput("editgrid_deck_request_card_id", "Card ID (optional)",
                  placeholder = "e.g., BT1-001"),
        footer = tagList(
          modalButton("Cancel"),
          actionButton("edit_deck_request_submit", "Submit Request", class = "btn-primary")
        )
      ))
    }
  }, ignoreInit = TRUE)
})

observeEvent(input$edit_deck_request_submit, {


  deck_name <- trimws(input$editgrid_deck_request_name)
  if (nchar(deck_name) == 0) {
    notify("Please enter a deck name", type = "error")
    return()
  }

  primary_color <- input$editgrid_deck_request_color
  secondary_color <- if (!is.null(input$editgrid_deck_request_color2) && input$editgrid_deck_request_color2 != "") {
    input$editgrid_deck_request_color2
  } else NA_character_

  card_id <- if (!is.null(input$editgrid_deck_request_card_id) && trimws(input$editgrid_deck_request_card_id) != "") {
    trimws(input$editgrid_deck_request_card_id)
  } else NA_character_

  existing <- safe_query(db_pool, "
    SELECT request_id FROM deck_requests
    WHERE LOWER(deck_name) = LOWER($1) AND status = 'pending'
  ", params = list(deck_name), default = data.frame())

  if (nrow(existing) > 0) {
    notify(sprintf("A pending request for '%s' already exists", deck_name), type = "warning")
  } else {
    safe_execute(db_pool, "
      INSERT INTO deck_requests (deck_name, primary_color, secondary_color, display_card_id, status)
      VALUES ($1, $2, $3, $4, 'pending')
    ", params = list(deck_name, primary_color, secondary_color, card_id))

    notify(sprintf("Deck request submitted: %s", deck_name), type = "message")
  }

  removeModal()

  # Force grid re-render
  rv$edit_grid_data <- sync_grid_inputs(input, rv$edit_grid_data, rv$edit_record_format %||% "points", "edit_",
                                       placement_editable = TRUE, wlt_override = isTRUE(rv$edit_wlt_override))
  rv$edit_grid_data <- rv$edit_grid_data
})

# =============================================================================
# Edit Grid: Save Handler (Update/Insert/Delete Diff)
# =============================================================================

observeEvent(input$edit_grid_save, {
  req(rv$is_admin, db_pool, rv$edit_grid_tournament_id)

  rv$edit_grid_data <- sync_grid_inputs(input, rv$edit_grid_data, rv$edit_record_format %||% "points", "edit_",
                                       placement_editable = TRUE, wlt_override = isTRUE(rv$edit_wlt_override))
  grid <- rv$edit_grid_data
  record_format <- rv$edit_record_format %||% "points"
  tournament_id <- rv$edit_grid_tournament_id

  # Get tournament info
  tournament <- safe_query(db_pool, "
    SELECT tournament_id, event_type, rounds FROM tournaments WHERE tournament_id = $1
  ", params = list(tournament_id), default = data.frame())

  if (nrow(tournament) == 0) {
    notify("Tournament not found", type = "error")
    return()
  }

  rounds <- tournament$rounds
  is_release <- tournament$event_type == "release_event"

  # Get UNKNOWN archetype ID
  unknown_row <- safe_query(db_pool, "SELECT archetype_id FROM deck_archetypes WHERE archetype_name = 'UNKNOWN' LIMIT 1", default = data.frame())
  unknown_id <- if (nrow(unknown_row) > 0) unknown_row$archetype_id[1] else NA_integer_

  if (is_release && is.na(unknown_id)) {
    notify("UNKNOWN archetype not found in database", type = "error")
    return()
  }

  # Separate filled vs empty rows (preserve original row index for input lookups)
  grid$row_idx <- seq_len(nrow(grid))
  filled_rows <- grid[nchar(trimws(grid$player_name)) > 0, ]

  if (nrow(filled_rows) == 0) {
    notify("No results to save. Enter at least one player name.", type = "warning")
    return()
  }

  # Block submission if any rows have unresolved ambiguous matches
  ambiguous_rows <- filled_rows[filled_rows$match_status == "ambiguous", ]
  if (nrow(ambiguous_rows) > 0) {
    notify(
      sprintf("Resolve duplicate player names before submitting: %s. Click the warning icon to pick the correct player.",
              paste(unique(ambiguous_rows$player_name), collapse = ", ")),
      type = "error"
    )
    return()
  }

  tryCatch({
    update_count <- 0L
    insert_count <- 0L
    delete_count <- 0L

    # Get scene_id for scene-scoped player matching (before transaction)
    tournament_store <- safe_query(db_pool, "
      SELECT s.scene_id FROM tournaments t
      JOIN stores s ON t.store_id = s.store_id
      WHERE t.tournament_id = $1
    ", params = list(tournament_id), default = data.frame())
    scene_id <- if (nrow(tournament_store) > 0) tournament_store$scene_id[1] else NULL

    # Transaction block: raw DBI calls intentional (retry would break atomicity)
    conn <- pool::localCheckout(db_pool)
    DBI::dbExecute(conn, "BEGIN")

    tryCatch({
      # 1. DELETE: rows that were deleted via X button
      for (rid in rv$edit_deleted_result_ids) {
        DBI::dbExecute(conn, "DELETE FROM results WHERE result_id = $1", params = list(rid))
        delete_count <- delete_count + 1L
      }

      # 2. DELETE: original rows that are now empty (user cleared the name)
      empty_rows <- grid[nchar(trimws(grid$player_name)) == 0 & !is.na(grid$result_id), ]
      for (idx in seq_len(nrow(empty_rows))) {
        DBI::dbExecute(conn, "DELETE FROM results WHERE result_id = $1",
                     params = list(empty_rows$result_id[idx]))
        delete_count <- delete_count + 1L
      }

      # 3. Phase 1: Resolve all players and prepare row data
      resolved_rows <- list()
      for (idx in seq_len(nrow(filled_rows))) {
        row <- filled_rows[idx, ]
        name <- trimws(row$player_name)

        # Resolve player - prioritize existing result's player to preserve data
        player_id <- NULL

        member_num <- normalize_member_number(row$member_number)
        if (is.na(member_num)) member_num <- ""

        if (!is.na(row$result_id)) {
          # Existing result — check if admin changed the player name or Bandai ID
          original <- DBI::dbGetQuery(conn, "
            SELECT r.player_id, p.display_name AS original_name, p.member_number AS original_member
            FROM results r JOIN players p ON r.player_id = p.player_id
            WHERE r.result_id = $1
          ", params = list(row$result_id))

          if (nrow(original) > 0) {
            orig_member <- original$original_member[1]
            if (is.na(orig_member)) orig_member <- ""
            name_unchanged <- tolower(trimws(name)) == tolower(trimws(original$original_name[1]))
            bandai_modified <- has_real_member_number(orig_member) && member_num != orig_member

            if (bandai_modified && isTRUE(rv$is_superadmin)) {
              # Super admin detach: Bandai ID changed or cleared (name may also have changed)
              # Create new player or reassign to existing player with the new Bandai ID
              player_id <- detach_to_player(conn, name, member_num, scene_id, tournament_id,
                                            admin_username = current_admin_username(rv))
              if (is.null(player_id)) {
                DBI::dbExecute(conn, "ROLLBACK")
                notify(sprintf("Cannot reassign — player with Bandai ID %s already has a result in this tournament.", member_num),
                       type = "error", duration = 8)
                return()
              }
            } else if (name_unchanged) {
              # Name unchanged, Bandai ID not changed (or not super admin) — keep existing player
              player_id <- original$player_id[1]
            } else {
              # Name changed — resolve the new name to decide: reassign or rename?
              # Don't pass member_number — match by name only to avoid Bandai ID
              # matching back to the same player
              match_info <- match_player(name, conn, scene_id = scene_id)
              if (match_info$status == "matched" && match_info$player_id != original$player_id[1]) {
                # New name matches a DIFFERENT existing player — reassign result to them
                player_id <- match_info$player_id
              } else if (match_info$status == "ambiguous") {
                # Multiple matches — should be caught by pre-submit block, fallback to first
                player_id <- match_info$candidates$player_id[1]
              } else {
                # No match or matched same player — treat as name correction, rename
                player_id <- original$player_id[1]
                updated_slug <- generate_unique_slug(conn, name, exclude_player_id = player_id)
                DBI::dbExecute(conn, "
                  UPDATE players SET display_name = $1, slug = $2,
                         updated_at = CURRENT_TIMESTAMP, updated_by = $3
                  WHERE player_id = $4
                ", params = list(name, updated_slug, current_admin_username(rv), player_id))
              }
            }
          }
        }

        # New row (no result_id) — use pre-matched player_id or match by name
        if (is.null(player_id)) {
          if (!is.na(row$matched_player_id)) {
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
              player_slug <- generate_unique_slug(conn, name)
              new_player <- DBI::dbGetQuery(conn,
                "INSERT INTO players (display_name, slug, member_number, identity_status, home_scene_id, is_anonymized, updated_by) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING player_id",
                params = list(name, player_slug, clean_member, identity_status, scene_id, auto_anon, current_admin_username(rv)))
              player_id <- new_player$player_id[1]
            }
          }
        }

        # Update member_number if provided and player doesn't have one yet; promote to verified
        if (has_real_member_number(member_num)) {
          DBI::dbExecute(conn, "
            UPDATE players SET member_number = $1, identity_status = 'verified',
                   updated_at = CURRENT_TIMESTAMP, updated_by = $2
            WHERE player_id = $3 AND (member_number IS NULL OR member_number = '')
          ", params = list(member_num, current_admin_username(rv), player_id))
        }

        # Convert record and store points
        wlt_override_active <- isTRUE(rv$edit_wlt_override) && record_format == "points"
        if (wlt_override_active) {
          # Use explicitly entered W/L/T values from override toggle
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
          deck_input <- input[[paste0("edit_deck_", row$row_idx)]]
          if (is.null(deck_input) || nchar(deck_input) == 0 || deck_input == "__REQUEST_NEW__") {
            archetype_id <- unknown_id
          } else if (grepl("^pending_", deck_input)) {
            pending_deck_request_id <- as.integer(sub("^pending_", "", deck_input))
            archetype_id <- unknown_id
          } else {
            archetype_id <- as.integer(deck_input)
          }
        }

        resolved_rows[[idx]] <- list(
          player_id = player_id, player_name = name,
          archetype_id = archetype_id, pending_deck_request_id = pending_deck_request_id,
          placement = row$placement, wins = wins, losses = losses, ties = ties, pts = pts,
          result_id = row$result_id
        )
      }

      # Phase 2: Check for duplicate player_ids before inserting/updating results
      resolved_player_ids <- vapply(resolved_rows, function(r) r$player_id, integer(1))
      dup_ids <- unique(resolved_player_ids[duplicated(resolved_player_ids)])
      if (length(dup_ids) > 0) {
        dup_names <- vapply(dup_ids, function(pid) {
          matches <- which(resolved_player_ids == pid)
          paste(vapply(matches, function(j) resolved_rows[[j]]$player_name, character(1)), collapse = ", ")
        }, character(1))
        DBI::dbExecute(conn, "ROLLBACK")
        notify(
          paste0("Duplicate players detected \u2014 the following rows resolve to the same player: ",
                 paste(dup_names, collapse = "; "),
                 ". Please fix before saving."),
          type = "error", duration = 10
        )
        return()
      }

      # Phase 3: UPDATE or INSERT filled rows
      for (idx in seq_len(length(resolved_rows))) {
        r <- resolved_rows[[idx]]

        if (!is.na(r$result_id)) {
          # UPDATE existing result
          DBI::dbExecute(conn, "
            UPDATE results
            SET player_id = $1, archetype_id = $2, pending_deck_request_id = $3,
                placement = $4, wins = $5, losses = $6, ties = $7, points = $8,
                updated_at = CURRENT_TIMESTAMP
            WHERE result_id = $9
          ", params = list(r$player_id, r$archetype_id, r$pending_deck_request_id,
                           r$placement, r$wins, r$losses, r$ties, r$pts, r$result_id))
          update_count <- update_count + 1L
        } else {
          # INSERT new result
          DBI::dbExecute(conn, "
            INSERT INTO results (tournament_id, player_id, archetype_id,
                                 pending_deck_request_id, placement, wins, losses, ties, points)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
          ", params = list(tournament_id, r$player_id, r$archetype_id,
                           r$pending_deck_request_id, r$placement, r$wins, r$losses, r$ties, r$pts))
          insert_count <- insert_count + 1L
        }
      }

      # Update player count on tournament
      DBI::dbExecute(conn, "
        UPDATE tournaments SET player_count = $1, updated_at = CURRENT_TIMESTAMP, updated_by = $2
        WHERE tournament_id = $3
      ", params = list(nrow(filled_rows), current_admin_username(rv), tournament_id))

      DBI::dbExecute(conn, "COMMIT")
    }, error = function(e) {
      tryCatch(DBI::dbExecute(conn, "ROLLBACK"), error = function(re) NULL)
      stop(e)
    })

    rv$refresh_tournaments <- rv$refresh_tournaments + 1
    rv$refresh_players <- rv$refresh_players + 1

    defer_ratings_recalc(db_pool, notify)

    # Build summary message
    parts <- c()
    if (update_count > 0) parts <- c(parts, sprintf("%d updated", update_count))
    if (insert_count > 0) parts <- c(parts, sprintf("%d added", insert_count))
    if (delete_count > 0) parts <- c(parts, sprintf("%d removed", delete_count))
    msg <- paste("Results saved!", paste(parts, collapse = ", "))

    notify(msg, type = "message", duration = 5)

    # Transition to decklist section
    rv$edit_decklist_results <- load_decklist_results(tournament_id, db_pool)
    rv$edit_decklist_tournament_id <- tournament_id

    shinyjs::hide("edit_results_grid_section")
    shinyjs::show("edit_decklist_section")

    rv$edit_grid_data <- NULL
    rv$edit_player_matches <- list()
    rv$edit_deleted_result_ids <- c()
    rv$edit_grid_tournament_id <- NULL
    rv$edit_wlt_override <- FALSE
    shinyjs::runjs("var el = document.getElementById('edit_wlt_override'); if (el) el.checked = false;")

    # Refresh the tournament list table
    rv$tournament_refresh <- (rv$tournament_refresh %||% 0) + 1

  }, error = function(e) {
    notify(paste("Error saving results:", e$message), type = "error")
  })
})

# =============================================================================
# Edit Decklist Links (after saving results)
# =============================================================================

rv$edit_decklist_results <- NULL
rv$edit_decklist_tournament_id <- NULL

output$edit_decklist_summary_bar <- renderUI({
  req(rv$edit_decklist_tournament_id)
  tournament <- safe_query(db_pool, "
    SELECT t.tournament_id, s.name as store_name, t.event_date, t.event_type, t.format
    FROM tournaments t JOIN stores s ON t.store_id = s.store_id
    WHERE t.tournament_id = $1
  ", params = list(rv$edit_decklist_tournament_id), default = data.frame())
  if (nrow(tournament) == 0) return(NULL)
  t <- tournament[1, ]
  div(class = "alert alert-success d-flex align-items-center gap-2 mb-3",
      bsicons::bs_icon("check-circle-fill"),
      sprintf("Results saved for %s — %s (%s)", t$store_name, t$event_date, t$format))
})

output$edit_decklist_table <- renderUI({
  req(rv$edit_decklist_results)
  render_decklist_entry(rv$edit_decklist_results, "edit_decklist_")
})

save_edit_decklists <- function() {
  req(rv$edit_decklist_results)
  result <- save_decklist_urls(rv$edit_decklist_results, input, "edit_decklist_", db_pool)
  if (result$skipped > 0) {
    notify(sprintf("%d invalid URL%s skipped — only links from approved deckbuilders are accepted.",
                   result$skipped, if (result$skipped == 1) "" else "s"), type = "warning")
  }
  result$saved
}

close_edit_decklist <- function() {
  shinyjs::hide("edit_decklist_section")
  shinyjs::show("edit_tournaments_main")
  rv$edit_decklist_results <- NULL
  rv$edit_decklist_tournament_id <- NULL
}

observeEvent(input$edit_decklist_save, {
  saved <- save_edit_decklists()
  if (saved > 0) {
    notify(sprintf("Saved %d decklist link%s.", saved, if (saved == 1) "" else "s"), type = "message")
  } else {
    notify("No decklist links to save.", type = "warning")
  }
})

observeEvent(input$edit_decklist_done, {
  save_edit_decklists()
  close_edit_decklist()
})

observeEvent(input$edit_decklist_skip, {
  close_edit_decklist()
})

# Scene indicator for admin tournaments page
output$admin_tournaments_scene_indicator <- renderUI({
  scene <- rv$current_scene
  show_all <- isTRUE(input$admin_tournaments_show_all_scenes) && isTRUE(rv$is_superadmin)

  if (show_all || is.null(scene) || scene == "" || scene == "all") {
    return(NULL)
  }

  div(
    class = "badge bg-info mb-2",
    paste("Filtered to:", toupper(scene))
  )
})
