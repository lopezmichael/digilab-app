# =============================================================================
# Admin: Edit Players Server Logic
# =============================================================================

# Debounce admin search input (300ms)
player_search_debounced <- reactive(input$player_search) |> debounce(300)

# Player list
output$player_list <- renderReactable({
  if (is.null(rv$db_con) || !dbIsValid(rv$db_con)) return(NULL)

  # Refresh triggers
  input$update_player
  input$confirm_delete_player
  input$confirm_merge_players
  input$admin_players_show_all_scenes

  search_term <- player_search_debounced() %||% ""
  scene <- rv$current_scene
  show_all <- isTRUE(input$admin_players_show_all_scenes) && isTRUE(rv$is_superadmin)

  # Build scene filter for players (players who have competed in scene)
  scene_filter <- ""
  query_params <- list()
  if (!show_all && !is.null(scene) && scene != "" && scene != "all") {
    if (scene == "online") {
      scene_filter <- "
        AND EXISTS (
          SELECT 1 FROM results r2
          JOIN tournaments t2 ON r2.tournament_id = t2.tournament_id
          JOIN stores s2 ON t2.store_id = s2.store_id
          WHERE r2.player_id = p.player_id AND s2.is_online = TRUE
        )
      "
    } else {
      scene_filter <- "
        AND EXISTS (
          SELECT 1 FROM results r2
          JOIN tournaments t2 ON r2.tournament_id = t2.tournament_id
          JOIN stores s2 ON t2.store_id = s2.store_id
          WHERE r2.player_id = p.player_id
            AND s2.scene_id = (SELECT scene_id FROM scenes WHERE slug = ?)
        )
      "
      query_params <- c(query_params, list(scene))
    }
  }

  # Build search filter
  search_filter <- ""
  if (nchar(search_term) > 0) {
    search_filter <- " AND LOWER(p.display_name) LIKE LOWER(?)"
    query_params <- c(query_params, list(paste0("%", search_term, "%")))
  }

  query <- sprintf("
    SELECT p.player_id,
           p.display_name as 'Player Name',
           COUNT(r.result_id) as 'Results',
           SUM(CASE WHEN r.placement = 1 THEN 1 ELSE 0 END) as 'Wins',
           MAX(t.event_date) as 'Last Event'
    FROM players p
    LEFT JOIN results r ON p.player_id = r.player_id
    LEFT JOIN tournaments t ON r.tournament_id = t.tournament_id
    WHERE 1=1 %s %s
    GROUP BY p.player_id, p.display_name
    ORDER BY p.display_name
  ", scene_filter, search_filter)

  data <- dbGetQuery(rv$db_con, query, params = query_params)

  if (nrow(data) == 0) {
    return(admin_empty_state("No players found", "// add players via tournament entry", "people"))
  }

  reactable(data, compact = TRUE, striped = TRUE,
    highlight = TRUE,
    onClick = JS("function(rowInfo, column) {
      if (rowInfo) {
        Shiny.setInputValue('player_list_clicked', {
          player_id: rowInfo.row['player_id'],
          nonce: Math.random()
        }, {priority: 'event'});
      }
    }"),
    rowStyle = list(cursor = "pointer"),
    defaultPageSize = 20,
    showPageSizeOptions = TRUE,
    pageSizeOptions = c(10, 20, 50, 100),
    columns = list(
      player_id = colDef(show = FALSE),
      `Player Name` = colDef(minWidth = 150),
      Results = colDef(width = 80),
      Wins = colDef(width = 60),
      `Last Event` = colDef(width = 100)
    )
  )
})

# Handle player selection for editing
observeEvent(input$player_list_clicked, {
  req(rv$db_con)
  player_id <- input$player_list_clicked$player_id

  if (is.null(player_id)) return()

  # Look up player directly by ID
  player <- dbGetQuery(rv$db_con, "
    SELECT player_id, display_name FROM players WHERE player_id = ?
  ", params = list(as.integer(player_id)))

  if (nrow(player) == 0) return()

  # Populate form for editing
  updateTextInput(session, "editing_player_id", value = as.character(player$player_id))
  updateTextInput(session, "player_display_name", value = player$display_name)

  # Show buttons
  shinyjs::show("update_player")
  shinyjs::show("delete_player")

  notify(sprintf("Editing: %s", player$display_name), type = "message", duration = 2)
})

# Player stats info
output$player_stats_info <- renderUI({
  if (is.null(input$editing_player_id) || input$editing_player_id == "") {
    return(div(class = "text-muted", "Select a player to view their stats."))
  }

  player_id <- as.integer(input$editing_player_id)

  stats <- dbGetQuery(rv$db_con, "
    SELECT
      COUNT(DISTINCT r.tournament_id) as tournaments,
      COUNT(r.result_id) as total_results,
      SUM(CASE WHEN r.placement = 1 THEN 1 ELSE 0 END) as wins,
      SUM(r.wins) as match_wins,
      SUM(r.losses) as match_losses
    FROM results r
    WHERE r.player_id = ?
  ", params = list(player_id))

  if (stats$total_results == 0) {
    return(div(
      class = "alert alert-info",
      bsicons::bs_icon("info-circle"), " This player has no tournament results.",
      div(class = "small mt-2", "Players with no results can be safely deleted.")
    ))
  }

  div(
    class = "digital-stat-box p-3",
    div(class = "d-flex justify-content-around text-center",
        div(
          div(class = "stat-value", stats$tournaments),
          div(class = "stat-label small text-muted", "Events")
        ),
        div(
          div(class = "stat-value", stats$wins),
          div(class = "stat-label small text-muted", "1st Places")
        ),
        div(
          div(class = "stat-value", paste0(stats$match_wins, "-", stats$match_losses)),
          div(class = "stat-label small text-muted", "Match Record")
        )
    )
  )
})

# Cancel edit
observeEvent(input$cancel_edit_player, {
  updateTextInput(session, "editing_player_id", value = "")
  updateTextInput(session, "player_display_name", value = "")

  shinyjs::hide("update_player")
  shinyjs::hide("delete_player")
})

# Update player
observeEvent(input$update_player, {
  req(rv$is_admin, rv$db_con, input$editing_player_id)

  clear_all_field_errors(session)

  player_id <- as.integer(input$editing_player_id)
  new_name <- trimws(input$player_display_name)

  if (nchar(new_name) == 0) {
    show_field_error(session, "player_display_name")
    notify("Please enter a player name", type = "error")
    return()
  }

  if (nchar(new_name) < 2) {
    show_field_error(session, "player_display_name")
    notify("Player name must be at least 2 characters", type = "error")
    return()
  }

  # Check for duplicate name (excluding current player)
  existing <- dbGetQuery(rv$db_con, "
    SELECT player_id FROM players
    WHERE LOWER(display_name) = LOWER(?) AND player_id != ?
  ", params = list(new_name, player_id))

  if (nrow(existing) > 0) {
    notify(sprintf("A player named '%s' already exists", new_name), type = "error")
    return()
  }

  tryCatch({
    dbExecute(rv$db_con, "
      UPDATE players
      SET display_name = ?, updated_at = CURRENT_TIMESTAMP
      WHERE player_id = ?
    ", params = list(new_name, player_id))

    notify(sprintf("Updated player: %s", new_name), type = "message")

    # Clear form and reset
    updateTextInput(session, "editing_player_id", value = "")
    updateTextInput(session, "player_display_name", value = "")

    shinyjs::hide("update_player")
    shinyjs::hide("delete_player")

    # Trigger refresh of public tables
    rv$data_refresh <- (rv$data_refresh %||% 0) + 1

  }, error = function(e) {
    notify(paste("Error:", e$message), type = "error")
  })
})

# Check if player can be deleted (no results)
observe({
  req(input$editing_player_id, rv$db_con)
  player_id <- as.integer(input$editing_player_id)

  count <- dbGetQuery(rv$db_con, "
    SELECT COUNT(*) as cnt FROM results WHERE player_id = ?
  ", params = list(player_id))$cnt

  rv$player_result_count <- count
  rv$can_delete_player <- count == 0
})

# Delete button click - show modal
observeEvent(input$delete_player, {
  req(rv$is_admin, input$editing_player_id)

  player_id <- as.integer(input$editing_player_id)
  player <- dbGetQuery(rv$db_con, "SELECT display_name FROM players WHERE player_id = ?",
                       params = list(player_id))

  if (rv$can_delete_player) {
    showModal(modalDialog(
      title = "Confirm Delete",
      div(
        p(sprintf("Are you sure you want to delete '%s'?", player$display_name)),
        p(class = "text-danger", "This action cannot be undone.")
      ),
      footer = tagList(
        actionButton("confirm_delete_player", "Delete", class = "btn-danger"),
        modalButton("Cancel")
      ),
      easyClose = TRUE
    ))
  } else {
    notify(
      sprintf("Cannot delete: player has %d result(s). Use 'Merge Players' to combine with another player.",
              rv$player_result_count),
      type = "error",
      duration = 5
    )
  }
})

# Confirm delete
observeEvent(input$confirm_delete_player, {
  req(rv$is_admin, rv$db_con, input$editing_player_id)
  player_id <- as.integer(input$editing_player_id)

  # Re-check for referential integrity
  count <- dbGetQuery(rv$db_con, "
    SELECT COUNT(*) as cnt FROM results WHERE player_id = ?
  ", params = list(player_id))$cnt

  if (count > 0) {
    removeModal()
    notify(sprintf("Cannot delete: player has %d result(s)", count), type = "error")
    return()
  }

  tryCatch({
    dbExecute(rv$db_con, "DELETE FROM players WHERE player_id = ?",
              params = list(player_id))
    notify("Player deleted", type = "message")

    removeModal()

    # Clear form
    updateTextInput(session, "editing_player_id", value = "")
    updateTextInput(session, "player_display_name", value = "")

    shinyjs::hide("update_player")
    shinyjs::hide("delete_player")

    # Trigger refresh of public tables
    rv$data_refresh <- (rv$data_refresh %||% 0) + 1

  }, error = function(e) {
    notify(paste("Error:", e$message), type = "error")
  })
})

# ---------------------------------------------------------------------------
# Merge Players Feature
# ---------------------------------------------------------------------------

# Show merge modal
observeEvent(input$show_merge_modal, {
  showModal(modalDialog(
    title = tagList(bsicons::bs_icon("arrow-left-right"), " Merge Players"),
    p("Merge two player records (e.g., fix a typo by combining duplicate entries)."),
    p(class = "text-muted small", "All results from the source player will be moved to the target player, then the source player will be deleted."),
    hr(),
    selectizeInput("merge_source_player", "Source Player (will be deleted)",
                   choices = NULL,
                   options = list(placeholder = "Select player to merge FROM...")),
    selectizeInput("merge_target_player", "Target Player (will keep)",
                   choices = NULL,
                   options = list(placeholder = "Select player to merge INTO...")),
    uiOutput("merge_preview"),
    footer = tagList(
      actionButton("confirm_merge_players", "Merge Players", class = "btn-warning"),
      modalButton("Cancel")
    ),
    size = "m",
    easyClose = TRUE
  ))
})

# Update merge dropdowns when they're shown
# Re-fires on tab navigation (ensures UI exists after lazy-load)
observe({
  rv$current_nav
  req(rv$db_con, rv$is_admin)
  choices <- get_player_choices(rv$db_con)
  updateSelectizeInput(session, "merge_source_player", choices = choices)
  updateSelectizeInput(session, "merge_target_player", choices = choices)
})

# Merge preview
output$merge_preview <- renderUI({
  source_id <- input$merge_source_player
  target_id <- input$merge_target_player

  if (is.null(source_id) || source_id == "" || is.null(target_id) || target_id == "") {
    return(NULL)
  }

  if (source_id == target_id) {
    return(div(class = "alert alert-danger", "Source and target players cannot be the same."))
  }

  src <- as.integer(source_id)
  tgt <- as.integer(target_id)

  source_count <- dbGetQuery(rv$db_con, "
    SELECT COUNT(*) as cnt FROM results WHERE player_id = ?
  ", params = list(src))$cnt

  match_count <- dbGetQuery(rv$db_con, "
    SELECT COUNT(*) as cnt FROM matches WHERE player_id = ? OR opponent_id = ?
  ", params = list(src, src))$cnt

  conflict_count <- dbGetQuery(rv$db_con, "
    SELECT COUNT(*) as cnt
    FROM results r1 INNER JOIN results r2 ON r1.tournament_id = r2.tournament_id
    WHERE r1.player_id = ? AND r2.player_id = ?
  ", params = list(src, tgt))$cnt

  tagList(
    div(
      class = "alert alert-warning",
      bsicons::bs_icon("exclamation-triangle"),
      sprintf(" %d result(s) and %d match record(s) will be moved to the target player.",
              source_count, match_count)
    ),
    if (conflict_count > 0) div(
      class = "alert alert-danger",
      bsicons::bs_icon("x-circle"),
      sprintf(" %d conflicting result(s) found (both players in same tournament). Source results will be dropped.",
              conflict_count)
    )
  )
})

# Confirm merge
observeEvent(input$confirm_merge_players, {
  req(rv$is_admin, rv$db_con)

  clear_all_field_errors(session)

  source_id <- as.integer(input$merge_source_player)
  target_id <- as.integer(input$merge_target_player)

  if (is.na(source_id) || is.na(target_id)) {
    show_field_error(session, "merge_source_player")
    show_field_error(session, "merge_target_player")
    notify("Please select both source and target players", type = "error")
    return()
  }

  if (source_id == target_id) {
    notify("Source and target players cannot be the same", type = "error")
    return()
  }

  tryCatch({
    # Check for conflicting results (both players in same tournament)
    conflicts <- dbGetQuery(rv$db_con, "
      SELECT r1.tournament_id
      FROM results r1
      INNER JOIN results r2 ON r1.tournament_id = r2.tournament_id
      WHERE r1.player_id = ? AND r2.player_id = ?
    ", params = list(source_id, target_id))

    if (nrow(conflicts) > 0) {
      # Delete source results that conflict (target's result takes priority)
      dbExecute(rv$db_con, "
        DELETE FROM results
        WHERE player_id = ? AND tournament_id IN (
          SELECT r2.tournament_id FROM results r2 WHERE r2.player_id = ?
        )
      ", params = list(source_id, target_id))
      notify(
        sprintf("Note: %d conflicting result(s) removed from source player", nrow(conflicts)),
        type = "warning", duration = 5
      )
    }

    # Move remaining results from source to target
    dbExecute(rv$db_con, "
      UPDATE results SET player_id = ? WHERE player_id = ?
    ", params = list(target_id, source_id))

    # Transfer matches (as player)
    dbExecute(rv$db_con, "
      UPDATE matches SET player_id = ? WHERE player_id = ?
    ", params = list(target_id, source_id))

    # Transfer matches (as opponent)
    dbExecute(rv$db_con, "
      UPDATE matches SET opponent_id = ? WHERE opponent_id = ?
    ", params = list(target_id, source_id))

    # Copy limitless_username from source to target (if target doesn't have one)
    dbExecute(rv$db_con, "
      UPDATE players
      SET limitless_username = (
        SELECT limitless_username FROM players WHERE player_id = ?
      )
      WHERE player_id = ? AND (limitless_username IS NULL OR limitless_username = '')
    ", params = list(source_id, target_id))

    # Delete source player
    dbExecute(rv$db_con, "DELETE FROM players WHERE player_id = ?",
              params = list(source_id))

    notify("Players merged successfully", type = "message")

    removeModal()

    # Reset dropdowns
    updateSelectizeInput(session, "merge_source_player", selected = "")
    updateSelectizeInput(session, "merge_target_player", selected = "")

    # Trigger refresh of public tables
    rv$data_refresh <- (rv$data_refresh %||% 0) + 1

  }, error = function(e) {
    notify(paste("Error:", e$message), type = "error")
  })
})

# Scene indicator for admin players page
output$admin_players_scene_indicator <- renderUI({
  scene <- rv$current_scene
  show_all <- isTRUE(input$admin_players_show_all_scenes) && isTRUE(rv$is_superadmin)

  if (show_all || is.null(scene) || scene == "" || scene == "all") {
    return(NULL)
  }

  div(
    class = "badge bg-info mb-2",
    paste("Filtered to:", toupper(scene))
  )
})
