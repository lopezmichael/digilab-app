# =============================================================================
# Admin: Edit Tournaments Server Logic
# =============================================================================

# Edit grid state
rv$edit_grid_data <- NULL
rv$edit_record_format <- "points"
rv$edit_player_matches <- list()
rv$edit_deleted_result_ids <- c()
rv$edit_grid_tournament_id <- NULL

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
  tournament <- dbGetQuery(db_pool, "
    SELECT t.*, s.name as store_name
    FROM tournaments t
    LEFT JOIN stores s ON t.store_id = s.store_id
    WHERE t.tournament_id = $1
  ", params = list(tournament_id))

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

  data <- dbGetQuery(db_pool, query, params = if (length(query_params) > 0) query_params else NULL)

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
    Rounds = data$rounds,
    Results = data$results_entered,
    stringsAsFactors = FALSE
  )

  # Store tournament_id in a way we can retrieve on click
  reactable(
    display_data,
    selection = "single",
    onClick = JS("function(rowInfo, column) {
      if (rowInfo) {
        Shiny.setInputValue('admin_tournament_list_clicked', {
          tournament_id: rowInfo.row.ID,
          nonce: Math.random()
        }, {priority: 'event'});
      }
    }"),
    highlight = TRUE,
    compact = TRUE,
    pagination = TRUE,
    defaultPageSize = 12,
    columns = list(
      ID = colDef(show = FALSE),
      Store = colDef(minWidth = 150),
      Date = colDef(width = 100),
      Type = colDef(width = 90),
      Format = colDef(minWidth = 100),
      Players = colDef(width = 70, align = "center"),
      Rounds = colDef(width = 65, align = "center"),
      Results = colDef(width = 70, align = "center")
    )
  )
})

# Click row to edit
observeEvent(input$admin_tournament_list_clicked, {

  tournament_id <- input$admin_tournament_list_clicked$tournament_id

  if (is.null(tournament_id)) return()

  # Get tournament details
  tournament <- dbGetQuery(db_pool, "
    SELECT t.*, s.name as store_name
    FROM tournaments t
    LEFT JOIN stores s ON t.store_id = s.store_id
    WHERE t.tournament_id = $1
  ", params = list(tournament_id))

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

  notify(sprintf("Editing: %s - %s", tournament$store_name, tournament$event_date),
                   type = "message", duration = 2)
})

# Tournament stats info
output$tournament_stats_info <- renderUI({
  req(db_pool, input$editing_tournament_id)

  tid <- as.integer(input$editing_tournament_id)

  # Get results count
  results_count <- dbGetQuery(db_pool, "
    SELECT COUNT(*) as cnt FROM results WHERE tournament_id = $1
  ", params = list(tid))$cnt

  # Get winner info
  winner <- dbGetQuery(db_pool, "
    SELECT p.display_name, da.archetype_name
    FROM results r
    JOIN players p ON r.player_id = p.player_id
    LEFT JOIN deck_archetypes da ON r.archetype_id = da.archetype_id
    WHERE r.tournament_id = $1 AND r.placement = 1
  ", params = list(tid))

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
    dbExecute(db_pool, "
      UPDATE tournaments
      SET store_id = $1, event_date = $2, event_type = $3, format = $4,
          player_count = $5, rounds = $6, updated_at = CURRENT_TIMESTAMP
      WHERE tournament_id = $7
    ", params = list(as.integer(store_id), event_date, event_type, format,
                     player_count, rounds, tournament_id))

    notify("Tournament updated", type = "message")

    # Reset form
    reset_tournament_form()

    # Trigger table refresh (admin + public tables)
    rv$tournament_refresh <- (rv$tournament_refresh %||% 0) + 1
    rv$data_refresh <- (rv$data_refresh %||% 0) + 1

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
  tournament <- dbGetQuery(db_pool, "
    SELECT t.*, s.name as store_name,
           (SELECT COUNT(*) FROM results WHERE tournament_id = t.tournament_id) as results_count
    FROM tournaments t
    LEFT JOIN stores s ON t.store_id = s.store_id
    WHERE t.tournament_id = $1
  ", params = list(tournament_id))

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

  # Delete results first, then tournament.
  safe_execute(db_pool, "DELETE FROM results WHERE tournament_id = $1",
               params = list(tournament_id))
  rows <- safe_execute(db_pool, "DELETE FROM tournaments WHERE tournament_id = $1",
                       params = list(tournament_id))

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

  # Trigger table refresh (admin + public tables)
  rv$tournament_refresh <- (rv$tournament_refresh %||% 0) + 1
  rv$data_refresh <- (rv$data_refresh %||% 0) + 1
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

  # Load existing results into grid
  grid <- load_grid_from_results(tournament_id, db_pool)

  # Infer record format: if any row has ties > 0 or wins don't cleanly convert to points, use WLT
  has_ties <- any(grid$ties > 0)
  has_irregular <- any((grid$wins * 3L + grid$ties) != grid$points & nchar(trimws(grid$player_name)) > 0)
  rv$edit_record_format <- if (has_ties || has_irregular) "wlt" else "points"

  # Add blank rows to allow adding more results (pad to at least current count + 4)
  current_count <- nrow(grid)
  pad_count <- max(current_count + 4, 8)
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
    t_info <- dbGetQuery(db_pool, "SELECT event_type FROM tournaments WHERE tournament_id = $1",
                         params = list(rv$edit_grid_tournament_id))
    if (nrow(t_info) > 0) is_release <- t_info$event_type[1] == "release_event"
  }

  deck_choices <- build_deck_choices(db_pool)

  render_grid_ui(grid, record_format, is_release, deck_choices, rv$edit_player_matches, "edit_")
})

# Edit grid summary bar
output$edit_grid_summary_bar <- renderUI({
  req(db_pool, rv$edit_grid_tournament_id)

  tournament <- dbGetQuery(db_pool, "
    SELECT t.*, s.name as store_name
    FROM tournaments t
    LEFT JOIN stores s ON t.store_id = s.store_id
    WHERE t.tournament_id = $1
  ", params = list(rv$edit_grid_tournament_id))

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
})

# =============================================================================
# Edit Grid: Interactivity (delete, player matching, paste, deck requests)
# =============================================================================

# Delete row handler
observeEvent(input$edit_delete_row, {
  req(rv$edit_grid_data)
  row_idx <- as.integer(input$edit_delete_row)
  if (is.null(row_idx) || row_idx < 1 || row_idx > nrow(rv$edit_grid_data)) return()

  rv$edit_grid_data <- sync_grid_inputs(input, rv$edit_grid_data, rv$edit_record_format %||% "points", "edit_")
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

# Attach blur handlers for edit grid
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
  ")
})

observeEvent(input$edit_player_blur, {
  req(db_pool, rv$edit_grid_data)

  info <- input$edit_player_blur
  row_num <- info$row
  name <- trimws(info$name)

  if (is.null(row_num) || is.na(row_num)) return()
  if (row_num < 1 || row_num > nrow(rv$edit_grid_data)) return()

  rv$edit_grid_data <- sync_grid_inputs(input, rv$edit_grid_data, rv$edit_record_format %||% "points", "edit_")

  if (nchar(name) == 0) {
    rv$edit_player_matches[[as.character(row_num)]] <- NULL
    rv$edit_grid_data$match_status[row_num] <- ""
    rv$edit_grid_data$matched_player_id[row_num] <- NA_integer_
    rv$edit_grid_data$matched_member_number[row_num] <- NA_character_
    return()
  }

  member_num <- input[[paste0("edit_member_", row_num)]]
  match_info <- match_player(name, db_pool, member_number = member_num)
  rv$edit_player_matches[[as.character(row_num)]] <- match_info
  rv$edit_grid_data$match_status[row_num] <- match_info$status
  if (match_info$status == "matched") {
    rv$edit_grid_data$matched_player_id[row_num] <- match_info$player_id
    rv$edit_grid_data$matched_member_number[row_num] <- match_info$member_number
  } else {
    rv$edit_grid_data$matched_player_id[row_num] <- NA_integer_
    rv$edit_grid_data$matched_member_number[row_num] <- NA_character_
  }
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

  rv$edit_grid_data <- sync_grid_inputs(input, rv$edit_grid_data, rv$edit_record_format %||% "points", "edit_")
  grid <- rv$edit_grid_data

  all_decks <- dbGetQuery(db_pool, "
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

  removeModal()
  notify(sprintf("Filled %d rows from pasted data", fill_count), type = "message")

  for (idx in seq_len(fill_count)) {
    match_info <- match_player(trimws(grid$player_name[idx]), db_pool, member_number = grid$member_number[idx])
    if (!is.null(match_info)) {
      rv$edit_player_matches[[as.character(idx)]] <- match_info
      grid$match_status[idx] <- match_info$status
      if (match_info$status == "matched") {
        grid$matched_player_id[idx] <- match_info$player_id
        grid$matched_member_number[idx] <- match_info$member_number
      }
    }
  }
  rv$edit_grid_data <- grid
})

# Deck request watcher for edit grid
observe({
  req(rv$edit_grid_data)
  grid <- rv$edit_grid_data

  lapply(seq_len(nrow(grid)), function(i) {
    observeEvent(input[[paste0("edit_deck_", i)]], {
      if (!is.null(input[[paste0("edit_deck_", i)]]) &&
          input[[paste0("edit_deck_", i)]] == "__REQUEST_NEW__") {
        rv$admin_deck_request_row <- i
        showModal(modalDialog(
          title = tagList(bsicons::bs_icon("collection-fill"), " Request New Deck"),
          textInput("editgrid_deck_request_name", "Deck Name", placeholder = "e.g., Blue Flare"),
          layout_columns(
            col_widths = c(6, 6),
            selectInput("editgrid_deck_request_color", "Primary Color",
                        choices = c("Red", "Blue", "Yellow", "Green", "Purple", "Black", "White")),
            selectInput("editgrid_deck_request_color2", "Secondary Color (optional)",
                        choices = c("None" = "", "Red", "Blue", "Yellow", "Green", "Purple", "Black", "White"))
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

  existing <- dbGetQuery(db_pool, "
    SELECT request_id FROM deck_requests
    WHERE LOWER(deck_name) = LOWER($1) AND status = 'pending'
  ", params = list(deck_name))

  if (nrow(existing) > 0) {
    notify(sprintf("A pending request for '%s' already exists", deck_name), type = "warning")
  } else {
    dbExecute(db_pool, "
      INSERT INTO deck_requests (deck_name, primary_color, secondary_color, display_card_id, status)
      VALUES ($1, $2, $3, $4, 'pending')
    ", params = list(deck_name, primary_color, secondary_color, card_id))

    notify(sprintf("Deck request submitted: %s", deck_name), type = "message")
  }

  removeModal()

  # Force grid re-render
  rv$edit_grid_data <- sync_grid_inputs(input, rv$edit_grid_data, rv$edit_record_format %||% "points", "edit_")
  rv$edit_grid_data <- rv$edit_grid_data
})

# =============================================================================
# Edit Grid: Save Handler (Update/Insert/Delete Diff)
# =============================================================================

observeEvent(input$edit_grid_save, {
  req(rv$is_admin, db_pool, rv$edit_grid_tournament_id)

  rv$edit_grid_data <- sync_grid_inputs(input, rv$edit_grid_data, rv$edit_record_format %||% "points", "edit_")
  grid <- rv$edit_grid_data
  record_format <- rv$edit_record_format %||% "points"
  tournament_id <- rv$edit_grid_tournament_id

  # Get tournament info
  tournament <- dbGetQuery(db_pool, "
    SELECT tournament_id, event_type, rounds FROM tournaments WHERE tournament_id = $1
  ", params = list(tournament_id))

  if (nrow(tournament) == 0) {
    notify("Tournament not found", type = "error")
    return()
  }

  rounds <- tournament$rounds
  is_release <- tournament$event_type == "release_event"

  # Get UNKNOWN archetype ID
  unknown_row <- dbGetQuery(db_pool, "SELECT archetype_id FROM deck_archetypes WHERE archetype_name = 'UNKNOWN' LIMIT 1")
  unknown_id <- if (nrow(unknown_row) > 0) unknown_row$archetype_id[1] else NA_integer_

  if (is_release && is.na(unknown_id)) {
    notify("UNKNOWN archetype not found in database", type = "error")
    return()
  }

  # Separate filled vs empty rows
  filled_rows <- grid[nchar(trimws(grid$player_name)) > 0, ]

  if (nrow(filled_rows) == 0) {
    notify("No results to save. Enter at least one player name.", type = "warning")
    return()
  }

  tryCatch({
    update_count <- 0L
    insert_count <- 0L
    delete_count <- 0L

    # 1. DELETE: rows that were deleted via X button
    for (rid in rv$edit_deleted_result_ids) {
      safe_execute(db_pool, "DELETE FROM results WHERE result_id = $1", params = list(rid))
      delete_count <- delete_count + 1L
    }

    # 2. DELETE: original rows that are now empty (user cleared the name)
    empty_rows <- grid[nchar(trimws(grid$player_name)) == 0 & !is.na(grid$result_id), ]
    for (idx in seq_len(nrow(empty_rows))) {
      safe_execute(db_pool, "DELETE FROM results WHERE result_id = $1",
                   params = list(empty_rows$result_id[idx]))
      delete_count <- delete_count + 1L
    }

    # 3. UPDATE or INSERT filled rows
    for (idx in seq_len(nrow(filled_rows))) {
      row <- filled_rows[idx, ]
      name <- trimws(row$player_name)

      # Resolve player - prioritize existing result's player to preserve data
      player_id <- NULL

      # If this is an existing result, get the original player and update their name
      if (!is.na(row$result_id)) {
        original <- dbGetQuery(db_pool, "
          SELECT player_id FROM results WHERE result_id = $1
        ", params = list(row$result_id))
        if (nrow(original) > 0) {
          player_id <- original$player_id[1]
          # Update the player's display_name if it changed
          dbExecute(db_pool, "
            UPDATE players SET display_name = $1 WHERE player_id = $2
          ", params = list(name, player_id))
        }
      }

      # If no existing result, use pre-matched player_id or match by name/member_number
      member_num <- if (!is.na(row$member_number)) trimws(row$member_number) else ""

      if (is.null(player_id)) {
        if (!is.na(row$matched_player_id)) {
          player_id <- row$matched_player_id
        } else {
          match_info <- match_player(name, db_pool, member_number = member_num)
          if (match_info$status == "matched") {
            player_id <- match_info$player_id
          } else {
            new_player <- dbGetQuery(db_pool, "INSERT INTO players (display_name) VALUES ($1) RETURNING player_id",
                         params = list(name))
            player_id <- new_player$player_id[1]
          }
        }
      }

      # Update member_number if provided and player doesn't have one yet
      if (nchar(member_num) > 0) {
        dbExecute(db_pool, "
          UPDATE players SET member_number = $1, updated_at = CURRENT_TIMESTAMP
          WHERE player_id = $2 AND (member_number IS NULL OR member_number = '')
        ", params = list(member_num, player_id))
      }

      # Convert record
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

      # Resolve deck
      pending_deck_request_id <- NA_integer_
      if (is_release) {
        archetype_id <- unknown_id
      } else {
        deck_input <- input[[paste0("edit_deck_", row$placement)]]
        if (is.null(deck_input) || nchar(deck_input) == 0 || deck_input == "__REQUEST_NEW__") {
          archetype_id <- unknown_id
        } else if (grepl("^pending_", deck_input)) {
          pending_deck_request_id <- as.integer(sub("^pending_", "", deck_input))
          archetype_id <- unknown_id
        } else {
          archetype_id <- as.integer(deck_input)
        }
      }

      if (!is.na(row$result_id)) {
        # UPDATE existing result
        safe_execute(db_pool, "
          UPDATE results
          SET player_id = $1, archetype_id = $2, pending_deck_request_id = $3,
              placement = $4, wins = $5, losses = $6, ties = $7,
              updated_at = CURRENT_TIMESTAMP
          WHERE result_id = $8
        ", params = list(player_id, archetype_id, pending_deck_request_id,
                         row$placement, wins, losses, ties, row$result_id))
        update_count <- update_count + 1L
      } else {
        # INSERT new result
        safe_execute(db_pool, "
          INSERT INTO results (tournament_id, player_id, archetype_id,
                               pending_deck_request_id, placement, wins, losses, ties)
          VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        ", params = list(tournament_id, player_id, archetype_id,
                         pending_deck_request_id, row$placement, wins, losses, ties))
        insert_count <- insert_count + 1L
      }
    }

    # Update player count on tournament
    safe_execute(db_pool, "
      UPDATE tournaments SET player_count = $1, updated_at = CURRENT_TIMESTAMP
      WHERE tournament_id = $2
    ", params = list(nrow(filled_rows), tournament_id))

    # Recalculate ratings
    recalculate_ratings_cache(db_pool)
    rv$data_refresh <- (rv$data_refresh %||% 0) + 1

    # Build summary message
    parts <- c()
    if (update_count > 0) parts <- c(parts, sprintf("%d updated", update_count))
    if (insert_count > 0) parts <- c(parts, sprintf("%d added", insert_count))
    if (delete_count > 0) parts <- c(parts, sprintf("%d removed", delete_count))
    msg <- paste("Results saved!", paste(parts, collapse = ", "))

    notify(msg, type = "message", duration = 5)

    # Collapse grid and show main panel
    shinyjs::hide("edit_results_grid_section")
    shinyjs::show("edit_tournaments_main")
    rv$edit_grid_data <- NULL
    rv$edit_player_matches <- list()
    rv$edit_deleted_result_ids <- c()
    rv$edit_grid_tournament_id <- NULL

    # Refresh the tournament list table
    rv$tournament_refresh <- (rv$tournament_refresh %||% 0) + 1

  }, error = function(e) {
    notify(paste("Error saving results:", e$message), type = "error")
  })
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
