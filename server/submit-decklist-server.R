# =============================================================================
# Submit Results: Standalone Decklist Submission
# Bandai ID lookup → tournament history → edit own decklist URL
# New flow — no equivalent in old codebase
# =============================================================================

# Initialize standalone decklist reactive values
rv$sr_decklist_standalone_player <- NULL       # player record from lookup
rv$sr_decklist_standalone_tournaments <- NULL   # tournament history for player
rv$sr_decklist_standalone_selected <- NULL      # selected tournament_id
rv$sr_decklist_standalone_results <- NULL       # results for selected tournament

# Handle Bandai ID lookup
observeEvent(input$sr_decklist_lookup, {
  member_id <- trimws(input$sr_decklist_member_id)

  if (is.null(member_id) || nchar(member_id) == 0) {
    notify("Please enter your Bandai Member Number", type = "error")
    return()
  }

  # Normalize to 10-digit zero-padded format
  member_id <- normalize_member_number(member_id)
  if (is.na(member_id) || nchar(member_id) == 0) {
    notify("Invalid member number format", type = "error")
    return()
  }

  # Look up player by member number
  player <- safe_query(db_pool, "
    SELECT player_id, display_name, member_number
    FROM players
    WHERE member_number = $1
  ", params = list(member_id), default = data.frame())

  if (nrow(player) == 0) {
    notify("No player found with that Member Number. You may need to submit tournament results first.", type = "warning")
    rv$sr_decklist_standalone_player <- NULL
    rv$sr_decklist_standalone_tournaments <- NULL
    rv$sr_decklist_standalone_selected <- NULL
    rv$sr_decklist_standalone_results <- NULL
    return()
  }

  rv$sr_decklist_standalone_player <- player[1, ]

  # Get tournament history for this player
  tournaments <- safe_query(db_pool, "
    SELECT r.result_id, r.tournament_id, r.placement,
           t.event_date, t.event_type, t.format,
           s.name as store_name,
           f.display_name as format_name,
           da.archetype_name as deck_name,
           r.decklist_url
    FROM results r
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    JOIN stores s ON t.store_id = s.store_id
    LEFT JOIN formats f ON t.format = f.format_id
    LEFT JOIN deck_archetypes da ON r.archetype_id = da.archetype_id
    WHERE r.player_id = $1
    ORDER BY t.event_date DESC
    LIMIT 50
  ", params = list(player$player_id[1]), default = data.frame())

  rv$sr_decklist_standalone_tournaments <- tournaments
  rv$sr_decklist_standalone_selected <- NULL
  rv$sr_decklist_standalone_results <- NULL

  notify(sprintf("Found %s — %d tournament%s",
                 player$display_name[1],
                 nrow(tournaments),
                 if (nrow(tournaments) == 1) "" else "s"),
         type = "message")
})

# Render player info
output$sr_decklist_player_info <- renderUI({
  req(rv$sr_decklist_standalone_player)
  sr_player_found_ui(rv$sr_decklist_standalone_player)
})

# Render tournament history
output$sr_decklist_tournament_history <- renderUI({
  req(rv$sr_decklist_standalone_tournaments)
  tournaments <- rv$sr_decklist_standalone_tournaments

  if (nrow(tournaments) == 0) {
    return(div(
      class = "alert alert-info mt-3",
      "No tournaments found for this player."
    ))
  }

  div(
    class = "admin-form-section",
    div(class = "admin-form-section-label",
      bsicons::bs_icon("trophy"),
      "Tournament History"
    ),
    tags$small(class = "sr-form-hint mb-2", "Select a tournament to add your decklist URL"),
    div(
      class = "sr-tournament-list",
      lapply(seq_len(nrow(tournaments)), function(i) {
        t <- tournaments[i, ]
        has_url <- !is.na(t$decklist_url) && nchar(trimws(t$decklist_url)) > 0

        actionLink(
          paste0("sr_decklist_select_", i),
          div(
            class = "d-flex justify-content-between align-items-center w-100",
            div(
              div(
                tags$strong(t$store_name),
                tags$span(class = "sr-tournament-date ms-2",
                          format(as.Date(t$event_date), "%b %d, %Y"))
              ),
              div(
                class = "sr-tournament-meta",
                paste0(t$event_type,
                       if (!is.na(t$format_name)) paste0(" \u2022 ", t$format_name) else "",
                       " \u2022 ", grid_ordinal(t$placement), " place",
                       if (!is.na(t$deck_name) && t$deck_name != "UNKNOWN") paste0(" \u2022 ", t$deck_name) else "")
              )
            ),
            if (has_url) span(class = "badge bg-success", "Has decklist")
            else span(class = "badge bg-secondary", "No decklist")
          ),
          class = paste0("sr-tournament-item",
                         if (has_url) " sr-tournament-item--done" else "")
        )
      })
    )
  )
})

# Handle tournament selection from history list
lapply(1:50, function(i) {
  observeEvent(input[[paste0("sr_decklist_select_", i)]], {
    req(rv$sr_decklist_standalone_tournaments)
    tournaments <- rv$sr_decklist_standalone_tournaments
    if (i > nrow(tournaments)) return()

    selected <- tournaments[i, ]
    rv$sr_decklist_standalone_selected <- selected$tournament_id
    rv$sr_decklist_standalone_results <- selected
  }, ignoreInit = TRUE)
})

# Render decklist entry form for selected tournament
output$sr_decklist_entry_form <- renderUI({
  req(rv$sr_decklist_standalone_results)
  selected <- rv$sr_decklist_standalone_results

  div(
    class = "admin-form-section",
    div(class = "admin-form-section-label",
      bsicons::bs_icon("link-45deg"),
      "Enter Decklist URL"
    ),
    div(
      class = "sr-selected-tournament",
      bsicons::bs_icon("trophy-fill", class = "sr-selected-tournament-icon"),
      tags$span(
        strong(selected$store_name), " \u2014 ",
        format(as.Date(selected$event_date), "%b %d, %Y"), " \u2014 ",
        selected$event_type)
    ),
    div(
      class = "sr-lookup-row sr-lookup-row--wide",
      textInput("sr_decklist_standalone_url",
                "Decklist URL",
                value = if (!is.na(selected$decklist_url)) selected$decklist_url else "",
                placeholder = "https://digimoncard.dev/deck/..."),
      actionButton("sr_decklist_standalone_save", "Save",
                   class = "btn-primary",
                   icon = icon("floppy-disk"))
    ),
    tags$small(class = "sr-form-hint",
               "Accepted: digimoncard.dev, digimonmeta.com, digimoncard.io, and other approved deckbuilders")
  )
})

# Handle decklist URL save
observeEvent(input$sr_decklist_standalone_save, {
  req(rv$sr_decklist_standalone_results)
  selected <- rv$sr_decklist_standalone_results

  url <- trimws(input$sr_decklist_standalone_url)

  if (nchar(url) == 0) {
    # Clear existing URL
    tryCatch({
      safe_execute(db_pool, "
        UPDATE results SET decklist_url = NULL WHERE result_id = $1
      ", params = list(selected$result_id))
      notify("Decklist URL cleared.", type = "message")

      # Update local state
      rv$sr_decklist_standalone_results$decklist_url <- NA_character_
      # Refresh tournament list
      if (!is.null(rv$sr_decklist_standalone_tournaments)) {
        idx <- which(rv$sr_decklist_standalone_tournaments$result_id == selected$result_id)
        if (length(idx) > 0) {
          rv$sr_decklist_standalone_tournaments$decklist_url[idx] <- NA_character_
        }
      }
    }, error = function(e) {
      notify(paste("Error clearing URL:", e$message), type = "error")
    })
    return()
  }

  # Validate URL using shared validator (returns validated URL or NULL)
  if (is.null(validate_decklist_url(url))) {
    notify("URL not from an approved deckbuilder site. Accepted: digimoncard.dev, digimonmeta.com, digimoncard.io, etc.",
           type = "error", duration = 8)
    return()
  }

  # Save URL
  tryCatch({
    safe_execute(db_pool, "
      UPDATE results SET decklist_url = $1 WHERE result_id = $2
    ", params = list(url, selected$result_id))
    notify("Decklist URL saved!", type = "message")

    # Update local state
    rv$sr_decklist_standalone_results$decklist_url <- url
    if (!is.null(rv$sr_decklist_standalone_tournaments)) {
      idx <- which(rv$sr_decklist_standalone_tournaments$result_id == selected$result_id)
      if (length(idx) > 0) {
        rv$sr_decklist_standalone_tournaments$decklist_url[idx] <- url
      }
    }
  }, error = function(e) {
    notify(paste("Error saving URL:", e$message), type = "error")
  })
})
