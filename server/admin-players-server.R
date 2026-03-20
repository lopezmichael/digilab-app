# =============================================================================
# Admin: Edit Players Server Logic
# =============================================================================

# =============================================================================
# Suggested Merges: Limitless → Local
# =============================================================================

output$suggested_merges_section <- renderUI({
  rv$refresh_players  # React to data changes
  req(rv$is_admin)

  # Scene admins shouldn't see merge suggestions (too complex for scene-level)
  req(isTRUE(rv$is_superadmin) || isTRUE(rv$admin_user$role == "regional_admin"))

  accessible <- get_admin_accessible_scene_ids(db_pool, rv$admin_user)

  # Build scene filter clause for regional admins
  scene_filter <- ""
  query_params <- list()
  if (!is.null(accessible)) {
    scene_filter <- "
      AND (
        loc.home_scene_id = ANY($1::int[])
        OR EXISTS (
          SELECT 1 FROM results r3
          JOIN tournaments t3 ON r3.tournament_id = t3.tournament_id
          JOIN stores s3 ON t3.store_id = s3.store_id
          WHERE r3.player_id = loc.player_id AND s3.scene_id = ANY($1::int[])
        )
      )
    "
    query_params <- list(as.integer(accessible))
  }

  candidates <- safe_query(db_pool, sprintf("
    SELECT l.player_id as limitless_pid, l.display_name as limitless_name, l.limitless_username,
           loc.player_id as local_pid, loc.display_name as local_name, loc.member_number,
           COALESCE(le.events, 0) as local_events, COALESCE(oe.events, 0) as online_events,
           sc.display_name as local_scene
    FROM players l
    JOIN players loc ON LOWER(l.display_name) = LOWER(loc.display_name)
      AND l.player_id != loc.player_id
    LEFT JOIN (
      SELECT r.player_id, COUNT(DISTINCT r.tournament_id) as events
      FROM results r JOIN tournaments t ON r.tournament_id = t.tournament_id
      JOIN stores s ON t.store_id = s.store_id WHERE s.is_online = FALSE
      GROUP BY r.player_id
    ) le ON loc.player_id = le.player_id
    LEFT JOIN (
      SELECT r.player_id, COUNT(DISTINCT r.tournament_id) as events
      FROM results r JOIN tournaments t ON r.tournament_id = t.tournament_id
      JOIN stores s ON t.store_id = s.store_id WHERE s.is_online = TRUE
      GROUP BY r.player_id
    ) oe ON l.player_id = oe.player_id
    LEFT JOIN scenes sc ON loc.home_scene_id = sc.scene_id
    WHERE l.limitless_username IS NOT NULL AND l.limitless_username != ''
      AND (l.member_number IS NULL OR l.member_number = '')
      AND loc.member_number IS NOT NULL AND loc.member_number != ''
      AND l.is_active IS NOT FALSE AND loc.is_active IS NOT FALSE
      %s
    ORDER BY le.events DESC NULLS LAST
  ", scene_filter), params = if (length(query_params) > 0) query_params else NULL, default = data.frame())

  if (nrow(candidates) == 0) return(NULL)

  cards <- lapply(seq_len(nrow(candidates)), function(i) {
    c <- candidates[i, ]
    div(class = "suggested-merge-card d-flex justify-content-between align-items-center p-3 mb-2 border rounded",
      div(
        div(class = "d-flex align-items-center gap-2",
          bsicons::bs_icon("link-45deg", class = "text-warning"),
          tags$strong(c$limitless_name)
        ),
        div(class = "small text-muted mt-1",
          sprintf("Online (%s events, @%s) → Local (%s events, #%s%s)",
            c$online_events, c$limitless_username, c$local_events, c$member_number,
            if (!is.na(c$local_scene)) paste0(", ", c$local_scene) else "")
        )
      ),
      div(class = "d-flex gap-2",
        actionButton(
          paste0("merge_suggested_", i),
          "Merge", class = "btn-sm btn-outline-success",
          onclick = sprintf("Shiny.setInputValue('suggested_merge_action', {index: %d, source: %d, target: %d, action: 'merge'}, {priority: 'event'})", i, c$limitless_pid, c$local_pid)
        ),
        actionButton(
          paste0("dismiss_suggested_", i),
          "Dismiss", class = "btn-sm btn-outline-secondary",
          onclick = sprintf("Shiny.setInputValue('suggested_merge_action', {index: %d, source: %d, target: %d, action: 'dismiss'}, {priority: 'event'})", i, c$limitless_pid, c$local_pid)
        )
      )
    )
  })

  div(class = "mb-3",
    div(class = "d-flex align-items-center gap-2 mb-2",
      bsicons::bs_icon("lightbulb", class = "text-warning"),
      tags$strong("Suggested Merges"),
      span(class = "badge bg-warning text-dark", nrow(candidates))
    ),
    div(class = "info-hint-box mb-2",
      bsicons::bs_icon("info-circle", class = "info-hint-icon"),
      "These online (Limitless) players match a local player by name. Merging combines their tournament history."
    ),
    div(class = "scroll-fade", style = "max-height: 320px; overflow-y: auto; padding-right: 4px;",
      cards
    )
  )
})

# Handle suggested merge actions
observeEvent(input$suggested_merge_action, {
  info <- input$suggested_merge_action
  req(info$action, info$source, info$target)

  source_id <- as.integer(info$source)
  target_id <- as.integer(info$target)

  if (info$action == "dismiss") {
    notify("Suggestion dismissed. It will reappear on next page load.", type = "message")
    return()
  }

  if (info$action == "merge") {
    tryCatch({
      admin_name <- current_admin_username(rv)

      conflict_count <- with_transaction(db_pool, function(conn) {
        # Check for conflicting results
        conflicts <- DBI::dbGetQuery(conn, "
          SELECT a.tournament_id FROM results a
          JOIN results b ON a.tournament_id = b.tournament_id
          WHERE a.player_id = $1 AND b.player_id = $2
        ", params = list(source_id, target_id))

        if (nrow(conflicts) > 0) {
          DBI::dbExecute(conn, "
            DELETE FROM results WHERE player_id = $1
            AND tournament_id IN (SELECT tournament_id FROM results WHERE player_id = $2)
          ", params = list(source_id, target_id))
        }

        # Move results
        DBI::dbExecute(conn, "UPDATE results SET player_id = $1 WHERE player_id = $2",
                     params = list(target_id, source_id))

        # Move matches
        DBI::dbExecute(conn, "UPDATE matches SET player_id = $1 WHERE player_id = $2",
                     params = list(target_id, source_id))
        DBI::dbExecute(conn, "UPDATE matches SET opponent_id = $1 WHERE opponent_id = $2",
                     params = list(target_id, source_id))

        # Copy limitless_username to target
        DBI::dbExecute(conn, "
          UPDATE players
          SET limitless_username = (SELECT limitless_username FROM players WHERE player_id = $1),
              identity_status = 'verified',
              updated_at = CURRENT_TIMESTAMP, updated_by = $2
          WHERE player_id = $3 AND (limitless_username IS NULL OR limitless_username = '')
        ", params = list(source_id, admin_name, target_id))

        # Transfer member_number: clear from source first to avoid unique constraint
        source_member <- DBI::dbGetQuery(conn, "
          SELECT member_number FROM players WHERE player_id = $1
        ", params = list(source_id))$member_number

        if (length(source_member) > 0 && !is.na(source_member) && nchar(source_member) > 0) {
          DBI::dbExecute(conn, "
            UPDATE players SET member_number = NULL WHERE player_id = $1
          ", params = list(source_id))

          DBI::dbExecute(conn, "
            UPDATE players
            SET member_number = $1,
                identity_status = 'verified',
                updated_at = CURRENT_TIMESTAMP, updated_by = $3
            WHERE player_id = $2 AND (member_number IS NULL OR member_number = '')
          ", params = list(source_member, target_id, admin_name))
        }

        # Promote to verified if target now has any identity fields
        DBI::dbExecute(conn, "
          UPDATE players
          SET identity_status = 'verified', updated_at = CURRENT_TIMESTAMP, updated_by = $2
          WHERE player_id = $1
            AND identity_status != 'verified'
            AND (member_number IS NOT NULL AND member_number != ''
                 OR limitless_username IS NOT NULL AND limitless_username != '')
        ", params = list(target_id, admin_name))

        # Soft-delete source player
        DBI::dbExecute(conn, "
          UPDATE players SET is_active = FALSE, updated_at = CURRENT_TIMESTAMP, updated_by = $2
          WHERE player_id = $1
        ", params = list(source_id, admin_name))

        nrow(conflicts)
      })

      if (conflict_count > 0) {
        notify(
          sprintf("Note: %d conflicting result(s) removed from source player", conflict_count),
          type = "warning", duration = 5
        )
      }

      notify("Players merged successfully!", type = "message")
      rv$refresh_players <- rv$refresh_players + 1

    }, error = function(e) {
      notify(paste("Merge failed:", e$message), type = "error")
    })
  }
})

# =============================================================================
# Player List & Editing
# =============================================================================

# Debounce admin search input (300ms)
player_search_debounced <- reactive(input$player_search) |> debounce(300)

# Player list
output$player_list <- renderReactable({


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
            AND s2.scene_id = (SELECT scene_id FROM scenes WHERE slug = $1)
        )
      "
      query_params <- c(query_params, list(scene))
    }
  }

  # Build search filter
  search_filter <- ""
  if (nchar(search_term) > 0) {
    next_idx <- if (length(query_params) > 0) length(query_params) + 1 else 1
    search_filter <- sprintf(" AND LOWER(p.display_name) LIKE LOWER($%d)", next_idx)
    query_params <- c(query_params, list(paste0("%", search_term, "%")))
  }

  query <- sprintf("
    SELECT p.player_id,
           p.display_name as \"Player Name\",
           prc.competitive_rating,
           COUNT(r.result_id) as \"Results\",
           SUM(CASE WHEN r.placement = 1 THEN 1 ELSE 0 END) as \"Wins\",
           (SELECT STRING_AGG(DISTINCT sc.display_name, ', ' ORDER BY sc.display_name)
            FROM results r2
            JOIN tournaments t2 ON r2.tournament_id = t2.tournament_id
            JOIN stores st2 ON t2.store_id = st2.store_id
            JOIN scenes sc ON st2.scene_id = sc.scene_id
            WHERE r2.player_id = p.player_id) as scenes,
           MAX(t.event_date) as \"Last Event\"
    FROM players p
    LEFT JOIN player_ratings_cache prc ON p.player_id = prc.player_id
    LEFT JOIN results r ON p.player_id = r.player_id
    LEFT JOIN tournaments t ON r.tournament_id = t.tournament_id
    WHERE 1=1 %s %s
    GROUP BY p.player_id, p.display_name, prc.competitive_rating
    ORDER BY p.display_name
  ", scene_filter, search_filter)

  data <- safe_query(db_pool, query, params = if (length(query_params) > 0) query_params else NULL, default = data.frame())

  if (nrow(data) == 0) {
    return(admin_empty_state("No players found", "// add players via tournament entry", "people"))
  }

  reactable(data, compact = TRUE, striped = FALSE,
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
      `Player Name` = colDef(minWidth = 160, style = list(whiteSpace = "normal")),
      competitive_rating = colDef(name = "Rating", width = 75, align = "right",
        cell = function(value) if (is.na(value)) "\u2014" else as.character(value)
      ),
      Results = colDef(width = 70, align = "center"),
      Wins = colDef(show = FALSE),
      scenes = colDef(name = "Scene(s)", minWidth = 100, style = list(whiteSpace = "normal"),
        cell = function(value) if (is.null(value) || is.na(value) || !nzchar(value)) "\u2014" else value
      ),
      `Last Event` = colDef(width = 105)
    )
  )
})

# Handle player selection for editing
observeEvent(input$player_list_clicked, {

  player_id <- input$player_list_clicked$player_id

  if (is.null(player_id)) return()

  # Look up player directly by ID
  player <- safe_query(db_pool, "
    SELECT player_id, display_name, member_number, is_anonymized FROM players WHERE player_id = $1
  ", params = list(as.integer(player_id)), default = data.frame())

  if (nrow(player) == 0) return()

  # Populate form for editing (reset duplicate-name confirmation flag)
  rv$confirm_duplicate_name <- FALSE
  updateTextInput(session, "editing_player_id", value = as.character(player$player_id))
  updateTextInput(session, "player_display_name", value = player$display_name)
  updateTextInput(session, "player_member_number",
                  value = if (!is.na(player$member_number)) player$member_number else "")
  updateCheckboxInput(session, "player_is_anonymized",
                      value = isTRUE(player$is_anonymized))

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

  stats <- safe_query(db_pool, "
    SELECT
      COUNT(DISTINCT r.tournament_id) as tournaments,
      COUNT(r.result_id) as total_results,
      SUM(CASE WHEN r.placement = 1 THEN 1 ELSE 0 END) as wins,
      SUM(r.wins) as match_wins,
      SUM(r.losses) as match_losses
    FROM results r
    WHERE r.player_id = $1
  ", params = list(player_id), default = data.frame(tournaments = 0L, total_results = 0L, wins = 0L, match_wins = 0L, match_losses = 0L))

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
  rv$confirm_duplicate_name <- FALSE
  updateTextInput(session, "editing_player_id", value = "")
  updateTextInput(session, "player_display_name", value = "")
  updateTextInput(session, "player_member_number", value = "")
  updateCheckboxInput(session, "player_is_anonymized", value = FALSE)

  shinyjs::hide("update_player")
  shinyjs::hide("delete_player")
})

# Update player
observeEvent(input$update_player, {
  req(rv$is_admin, db_pool, input$editing_player_id)

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

  # Check for duplicate name (excluding current player) — warn but allow with confirmation
  existing <- safe_query(db_pool, "
    SELECT player_id FROM players
    WHERE LOWER(display_name) = LOWER($1) AND player_id != $2
  ", params = list(new_name, player_id), default = data.frame())

  if (nrow(existing) > 0 && !isTRUE(rv$confirm_duplicate_name)) {
    rv$confirm_duplicate_name <- TRUE
    notify(sprintf("Another player named '%s' already exists. Click Save again to confirm.", new_name), type = "warning")
    return()
  }
  rv$confirm_duplicate_name <- FALSE

  new_member <- trimws(input$player_member_number)
  if (nchar(new_member) == 0) new_member <- NA_character_

  tryCatch({
    updated_slug <- generate_unique_slug(db_pool, new_name, exclude_player_id = player_id)
    safe_execute(db_pool, "
      UPDATE players
      SET display_name = $1, member_number = $2, is_anonymized = $3,
          slug = $4, updated_at = CURRENT_TIMESTAMP, updated_by = $5
      WHERE player_id = $6
    ", params = list(new_name, new_member, isTRUE(input$player_is_anonymized),
                     updated_slug, current_admin_username(rv), player_id))

    notify(sprintf("Updated player: %s", new_name), type = "message")

    # Clear form and reset
    updateTextInput(session, "editing_player_id", value = "")
    updateTextInput(session, "player_display_name", value = "")
    updateTextInput(session, "player_member_number", value = "")
    updateCheckboxInput(session, "player_is_anonymized", value = FALSE)

    shinyjs::hide("update_player")
    shinyjs::hide("delete_player")

    # Trigger refresh of public tables
    rv$refresh_players <- rv$refresh_players + 1

  }, error = function(e) {
    notify(paste("Error:", e$message), type = "error")
  })
})

# Check if player can be deleted (no results)
observe({
  req(input$editing_player_id, db_pool)
  player_id <- as.integer(input$editing_player_id)

  count_df <- safe_query(db_pool, "
    SELECT COUNT(*) as cnt FROM results WHERE player_id = $1
  ", params = list(player_id), default = data.frame(cnt = 0L))
  count <- count_df$cnt

  rv$player_result_count <- count
  rv$can_delete_player <- count == 0
})

# Delete button click - show modal
observeEvent(input$delete_player, {
  req(rv$is_admin, input$editing_player_id)

  player_id <- as.integer(input$editing_player_id)
  player <- safe_query(db_pool, "SELECT display_name FROM players WHERE player_id = $1",
                       params = list(player_id), default = data.frame())

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
              as.integer(rv$player_result_count)),
      type = "error",
      duration = 5
    )
  }
})

# Confirm delete
observeEvent(input$confirm_delete_player, {
  req(rv$is_admin, db_pool, input$editing_player_id)
  player_id <- as.integer(input$editing_player_id)

  # Re-check for referential integrity
  count_df2 <- safe_query(db_pool, "
    SELECT COUNT(*) as cnt FROM results WHERE player_id = $1
  ", params = list(player_id), default = data.frame(cnt = 0L))
  count <- count_df2$cnt

  if (count > 0) {
    removeModal()
    notify(sprintf("Cannot delete: player has %d result(s)", as.integer(count)), type = "error")
    return()
  }

  tryCatch({
    safe_execute(db_pool, "DELETE FROM players WHERE player_id = $1",
              params = list(player_id))
    notify("Player deleted", type = "message")

    removeModal()

    # Clear form
    updateTextInput(session, "editing_player_id", value = "")
    updateTextInput(session, "player_display_name", value = "")

    shinyjs::hide("update_player")
    shinyjs::hide("delete_player")

    # Trigger refresh of public tables
    rv$refresh_players <- rv$refresh_players + 1

  }, error = function(e) {
    notify(paste("Error:", e$message), type = "error")
  })
})

# ---------------------------------------------------------------------------
# Merge Players Feature
# ---------------------------------------------------------------------------

# Show merge modal
observeEvent(input$show_merge_modal, {
  # Fetch player choices scoped to admin's accessible scenes
  accessible <- get_admin_accessible_scene_ids(db_pool, rv$admin_user)
  player_choices <- get_player_choices(db_pool, scene_ids = accessible)

  showModal(modalDialog(
    title = tagList(bsicons::bs_icon("arrow-left-right"), " Merge Players"),
    p("Merge two player records (e.g., fix a typo by combining duplicate entries)."),
    p(class = "text-muted small", "All results from the source player will be moved to the target player, then the source player will be deleted."),
    hr(),
    selectizeInput("merge_source_player", "Source Player (will be deleted)",
                   choices = player_choices,
                   options = list(placeholder = "Select player to merge FROM...")),
    selectizeInput("merge_target_player", "Target Player (will keep)",
                   choices = player_choices,
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

# Note: Merge player dropdowns are populated when modal opens (in show_merge_modal handler)
# No need for a separate observer since choices are fetched fresh each time the modal opens

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

  source_count_df <- safe_query(db_pool, "
    SELECT COUNT(*) as cnt FROM results WHERE player_id = $1
  ", params = list(src), default = data.frame(cnt = 0L))
  source_count <- source_count_df$cnt

  match_count_df <- safe_query(db_pool, "
    SELECT COUNT(*) as cnt FROM matches WHERE player_id = $1 OR opponent_id = $2
  ", params = list(src, src), default = data.frame(cnt = 0L))
  match_count <- match_count_df$cnt

  conflict_count_df <- safe_query(db_pool, "
    SELECT COUNT(*) as cnt
    FROM results r1 INNER JOIN results r2 ON r1.tournament_id = r2.tournament_id
    WHERE r1.player_id = $1 AND r2.player_id = $2
  ", params = list(src, tgt), default = data.frame(cnt = 0L))
  conflict_count <- conflict_count_df$cnt

  tagList(
    div(
      class = "alert alert-warning",
      bsicons::bs_icon("exclamation-triangle"),
      sprintf(" %d result(s) and %d match record(s) will be moved to the target player.",
              as.integer(source_count), as.integer(match_count))
    ),
    if (conflict_count > 0) div(
      class = "alert alert-danger",
      bsicons::bs_icon("x-circle"),
      sprintf(" %d conflicting result(s) found (both players in same tournament). Source results will be dropped.",
              as.integer(conflict_count))
    )
  )
})

# Confirm merge
observeEvent(input$confirm_merge_players, {
  req(rv$is_admin, db_pool)

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
    admin_name <- current_admin_username(rv)

    # Run entire merge in a single transaction so it's all-or-nothing
    conflict_count <- with_transaction(db_pool, function(conn) {

      # Check for conflicting results (both players in same tournament)
      conflicts <- DBI::dbGetQuery(conn, "
        SELECT r1.tournament_id
        FROM results r1
        INNER JOIN results r2 ON r1.tournament_id = r2.tournament_id
        WHERE r1.player_id = $1 AND r2.player_id = $2
      ", params = list(source_id, target_id))

      if (nrow(conflicts) > 0) {
        # Delete source results that conflict (target's result takes priority)
        DBI::dbExecute(conn, "
          DELETE FROM results
          WHERE player_id = $1 AND tournament_id IN (
            SELECT r2.tournament_id FROM results r2 WHERE r2.player_id = $2
          )
        ", params = list(source_id, target_id))
      }

      # Move remaining results from source to target
      DBI::dbExecute(conn, "
        UPDATE results SET player_id = $1 WHERE player_id = $2
      ", params = list(target_id, source_id))

      # Transfer matches (as player)
      DBI::dbExecute(conn, "
        UPDATE matches SET player_id = $1 WHERE player_id = $2
      ", params = list(target_id, source_id))

      # Transfer matches (as opponent)
      DBI::dbExecute(conn, "
        UPDATE matches SET opponent_id = $1 WHERE opponent_id = $2
      ", params = list(target_id, source_id))

      # Copy limitless_username from source to target (if target doesn't have one)
      DBI::dbExecute(conn, "
        UPDATE players
        SET limitless_username = (
          SELECT limitless_username FROM players WHERE player_id = $1
        ), updated_at = CURRENT_TIMESTAMP, updated_by = $3
        WHERE player_id = $2 AND (limitless_username IS NULL OR limitless_username = '')
      ", params = list(source_id, target_id, admin_name))

      # Transfer member_number: clear from source first to avoid unique constraint,
      # then set on target if it doesn't already have one
      source_member <- DBI::dbGetQuery(conn, "
        SELECT member_number FROM players WHERE player_id = $1
      ", params = list(source_id))$member_number

      if (length(source_member) > 0 && !is.na(source_member) && nchar(source_member) > 0) {
        DBI::dbExecute(conn, "
          UPDATE players SET member_number = NULL WHERE player_id = $1
        ", params = list(source_id))

        DBI::dbExecute(conn, "
          UPDATE players
          SET member_number = $1,
              identity_status = 'verified',
              updated_at = CURRENT_TIMESTAMP, updated_by = $3
          WHERE player_id = $2 AND (member_number IS NULL OR member_number = '')
        ", params = list(source_member, target_id, admin_name))
      }

      # Promote to verified if target now has any identity fields
      DBI::dbExecute(conn, "
        UPDATE players
        SET identity_status = 'verified', updated_at = CURRENT_TIMESTAMP, updated_by = $2
        WHERE player_id = $1
          AND identity_status != 'verified'
          AND (member_number IS NOT NULL AND member_number != ''
               OR limitless_username IS NOT NULL AND limitless_username != '')
      ", params = list(target_id, admin_name))

      # Soft-delete source player
      DBI::dbExecute(conn, "
        UPDATE players SET is_active = FALSE, updated_at = CURRENT_TIMESTAMP, updated_by = $2
        WHERE player_id = $1
      ", params = list(source_id, admin_name))

      nrow(conflicts)
    })

    if (conflict_count > 0) {
      notify(
        sprintf("Note: %d conflicting result(s) removed from source player", conflict_count),
        type = "warning", duration = 5
      )
    }

    notify("Players merged successfully", type = "message")

    removeModal()

    # Reset dropdowns
    updateSelectizeInput(session, "merge_source_player", selected = "")
    updateSelectizeInput(session, "merge_target_player", selected = "")

    # Trigger refresh of public tables
    rv$refresh_players <- rv$refresh_players + 1

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
