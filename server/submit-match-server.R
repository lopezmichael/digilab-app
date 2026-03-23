# =============================================================================
# Submit Results: Match-by-Match Server
# Bandai ID lookup → tournament history → screenshot upload → review → submit
# =============================================================================

# Initialize match history reactive values
rv$sr_match_player <- NULL                # player record from lookup
rv$sr_match_tournaments <- NULL           # tournament history for player
rv$sr_match_selected_tournament <- NULL   # selected tournament record
rv$sr_match_ocr_results <- NULL
rv$sr_match_uploaded_file <- NULL
rv$sr_match_parsed_count <- 0
rv$sr_match_total_rounds <- 0

# Helper: query tournament history with match counts for a player
sr_match_get_tournaments <- function(pool, player_id) {
  safe_query(pool, "
    SELECT r.result_id, r.tournament_id, r.placement, r.player_id,
           t.event_date, t.event_type, t.format, t.rounds,
           s.name as store_name,
           f.display_name as format_name,
           (SELECT COUNT(*) FROM matches m
            WHERE m.tournament_id = r.tournament_id AND m.player_id = r.player_id) as match_count
    FROM results r
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    JOIN stores s ON t.store_id = s.store_id
    LEFT JOIN formats f ON t.format = f.format_id
    WHERE r.player_id = $1
    ORDER BY t.event_date DESC
    LIMIT 50
  ", params = list(player_id), default = data.frame())
}

# =============================================================================
# Bandai ID Lookup
# =============================================================================

observeEvent(input$sr_match_lookup, {
  member_id <- trimws(input$sr_match_member_id)

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
    rv$sr_match_player <- NULL
    rv$sr_match_tournaments <- NULL
    rv$sr_match_selected_tournament <- NULL
    rv$sr_match_ocr_results <- NULL
    return()
  }

  rv$sr_match_player <- player[1, ]

  tournaments <- sr_match_get_tournaments(db_pool, player$player_id[1])

  rv$sr_match_tournaments <- tournaments
  rv$sr_match_selected_tournament <- NULL
  rv$sr_match_ocr_results <- NULL

  notify(sprintf("Found %s — %d tournament%s",
                 player$display_name[1],
                 nrow(tournaments),
                 if (nrow(tournaments) == 1) "" else "s"),
         type = "message")
})

# =============================================================================
# Player Info Display
# =============================================================================

output$sr_match_player_info <- renderUI({
  req(rv$sr_match_player)
  sr_player_found_ui(rv$sr_match_player)
})

# =============================================================================
# Tournament History
# =============================================================================

output$sr_match_tournament_history <- renderUI({
  req(rv$sr_match_tournaments)
  tournaments <- rv$sr_match_tournaments

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
    tags$small(class = "sr-form-hint mb-2", "Select a tournament to add your match history"),
    div(
      class = "sr-tournament-list",
      lapply(seq_len(nrow(tournaments)), function(i) {
        t <- tournaments[i, ]
        has_matches <- !is.na(t$match_count) && t$match_count > 0

        actionLink(
          paste0("sr_match_select_", i),
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
                       if (!is.na(t$rounds)) paste0(" \u2022 ", t$rounds, " rounds") else "")
              )
            ),
            if (has_matches) span(class = "badge bg-success", paste(t$match_count, "matches"))
            else span(class = "badge bg-secondary", "No match data")
          ),
          class = paste0("sr-tournament-item",
                         if (has_matches) " sr-tournament-item--done" else "")
        )
      })
    )
  )
})

# Handle tournament selection from history list
lapply(1:50, function(i) {
  observeEvent(input[[paste0("sr_match_select_", i)]], {
    req(rv$sr_match_tournaments)
    tournaments <- rv$sr_match_tournaments
    if (i > nrow(tournaments)) return()

    rv$sr_match_selected_tournament <- tournaments[i, ]
    rv$sr_match_ocr_results <- NULL
    rv$sr_match_uploaded_file <- NULL
    rv$sr_match_parsed_count <- 0
    rv$sr_match_total_rounds <- 0
  }, ignoreInit = TRUE)
})

# =============================================================================
# Upload Form (shown after tournament selection)
# =============================================================================

output$sr_match_upload_form <- renderUI({
  req(rv$sr_match_selected_tournament)
  selected <- rv$sr_match_selected_tournament

  div(
    class = "admin-form-section",

    # Tournament context banner
    div(
      class = "sr-selected-tournament",
      bsicons::bs_icon("trophy-fill", class = "sr-selected-tournament-icon"),
      tags$span(
        strong(selected$store_name), " \u2014 ",
        format(as.Date(selected$event_date), "%b %d, %Y"), " \u2014 ",
        selected$event_type,
        if (!is.na(selected$rounds)) paste0(" \u2014 ", selected$rounds, " rounds") else "")
    ),

    # Screenshot upload
    div(class = "admin-form-section-label",
      bsicons::bs_icon("camera"),
      "Match History Screenshot"
    ),
    div(
      class = "d-flex align-items-start gap-3",
      div(
        class = "upload-dropzone flex-shrink-0",
        fileInput("sr_match_screenshots", NULL,
                  multiple = FALSE,
                  accept = c("image/png", "image/jpeg", "image/jpg", "image/webp",
                             ".png", ".jpg", ".jpeg", ".webp"),
                  placeholder = "No file selected",
                  buttonLabel = tags$span(bsicons::bs_icon("cloud-upload"), " Browse"))
      ),
      div(
        class = "upload-tips",
        tags$small(class = "sr-form-hint",
          bsicons::bs_icon("info-circle", class = "me-1"),
          "Screenshot from Bandai TCG+ match history screen")
      )
    ),

    # Image thumbnail preview
    uiOutput("sr_match_screenshot_preview"),

    # Process button
    div(
      class = "admin-form-actions justify-content-end mt-3",
      actionButton("sr_match_process_ocr", "Process Screenshot",
                   class = "btn-primary",
                   icon = icon("magic"))
    )
  )
})

# =============================================================================
# Screenshot Preview
# =============================================================================

output$sr_match_screenshot_preview <- renderUI({
  req(input$sr_match_screenshots)

  file <- input$sr_match_screenshots
  if (is.null(file)) return(NULL)

  rv$sr_match_uploaded_file <- file

  file_ext <- tolower(tools::file_ext(file$name))
  mime_type <- switch(file_ext,
    "png" = "image/png",
    "jpg" = "image/jpeg",
    "jpeg" = "image/jpeg",
    "webp" = "image/webp",
    "image/png"
  )

  img_data <- base64enc::base64encode(file$datapath)
  img_src <- paste0("data:", mime_type, ";base64,", img_data)

  div(
    class = "screenshot-thumbnails",
    div(
      class = "screenshot-thumb",
      tags$img(src = img_src, alt = file$name),
      div(
        class = "screenshot-thumb-label",
        span(class = "filename", file$name)
      )
    )
  )
})

# =============================================================================
# Process Match History OCR
# =============================================================================

observeEvent(input$sr_match_process_ocr, {
  req(rv$sr_match_uploaded_file)
  req(rv$sr_match_selected_tournament)

  selected <- rv$sr_match_selected_tournament

  # Get round count from the selected tournament
  total_rounds <- if (!is.na(selected$rounds)) {
    as.integer(selected$rounds)
  } else {
    4L
  }

  file <- rv$sr_match_uploaded_file

  # Show processing modal
  showModal(modalDialog(
    div(
      class = "text-center py-4",
      div(class = "processing-spinner mb-3"),
      h5(class = "text-primary", "Processing Screenshot"),
      p(class = "text-muted mb-0", "Extracting match data...")
    ),
    title = NULL,
    footer = NULL,
    easyClose = FALSE,
    size = "s"
  ))

  message("[MATCH SUBMIT] Processing file: ", file$name)
  message("[MATCH SUBMIT] File path: ", file$datapath)

  # Call OCR
  ocr_result <- tryCatch({
    gcv_detect_text(file$datapath, verbose = TRUE)
  }, error = function(e) {
    message("[MATCH SUBMIT] OCR error: ", e$message)
    NULL
  })

  ocr_text <- if (is.list(ocr_result)) ocr_result$text else ocr_result

  if (is.null(ocr_text) || ocr_text == "") {
    removeModal()
    notify("Could not read the screenshot. Make sure the image is clear and shows the match history screen.", type = "error")
    return()
  }

  message("[MATCH SUBMIT] OCR text length: ", nchar(ocr_text))

  # Parse match history
  parsed <- tryCatch({
    parse_match_history(ocr_text, verbose = TRUE)
  }, error = function(e) {
    message("[MATCH SUBMIT] Parse error: ", e$message)
    data.frame()
  })

  removeModal()

  parsed_count <- nrow(parsed)

  # Ensure we have exactly total_rounds rows
  if (parsed_count < total_rounds) {
    existing_rounds <- if (parsed_count > 0) parsed$round else integer()
    for (r in seq_len(total_rounds)) {
      if (!(r %in% existing_rounds)) {
        blank_row <- data.frame(
          round = r,
          opponent_username = "",
          opponent_member_number = "",
          games_won = 0,
          games_lost = 0,
          games_tied = 0,
          match_points = 0,
          stringsAsFactors = FALSE
        )
        parsed <- rbind(parsed, blank_row)
      }
    }
    parsed <- parsed[order(parsed$round), ]
  } else if (parsed_count > total_rounds) {
    parsed <- parsed[parsed$round <= total_rounds, ]
  }

  # Store results and counts
  rv$sr_match_ocr_results <- parsed
  rv$sr_match_parsed_count <- parsed_count
  rv$sr_match_total_rounds <- total_rounds

  # Show appropriate notification
  if (parsed_count == 0) {
    notify(paste("No matches found - fill in all", total_rounds, "rounds manually"),
           type = "warning", duration = 8)
  } else if (parsed_count == total_rounds) {
    notify(paste("All", total_rounds, "rounds found"), type = "message")
  } else if (parsed_count < total_rounds) {
    notify(paste("Parsed", parsed_count, "of", total_rounds, "rounds - fill in remaining manually"),
           type = "warning", duration = 8)
  } else {
    notify(paste("Found", parsed_count, "rounds, showing", total_rounds),
           type = "warning", duration = 8)
  }
})

# =============================================================================
# Match History Preview (editable table)
# =============================================================================

output$sr_match_results_preview <- renderUI({
  req(rv$sr_match_ocr_results)

  results <- rv$sr_match_ocr_results
  parsed_count <- rv$sr_match_parsed_count
  total_rounds <- rv$sr_match_total_rounds

  status_badge <- if (parsed_count == total_rounds) {
    span(class = "badge bg-success", paste("All", total_rounds, "rounds found"))
  } else {
    span(class = "badge bg-warning text-dark", paste("Parsed", parsed_count, "of", total_rounds, "rounds"))
  }

  card(
    class = "mt-3",
    card_header(
      class = "d-flex justify-content-between align-items-center",
      span("Review & Edit Match History"),
      status_badge
    ),
    card_body(
      div(
        class = "alert alert-info d-flex mb-3",
        bsicons::bs_icon("pencil-square", class = "me-2 flex-shrink-0"),
        tags$small("Review and edit the extracted data. Correct any OCR errors before submitting.",
                   if (parsed_count < total_rounds) " Fill in missing rounds manually." else "")
      ),

      # Header row
      layout_columns(
        col_widths = c(1, 4, 3, 2, 2),
        class = "results-header-row",
        div("Rd"),
        div("Opponent"),
        div("Member #"),
        div("W-L-T"),
        div("Pts")
      ),

      # Editable rows
      lapply(seq_len(nrow(results)), function(i) {
        row <- results[i, ]

        layout_columns(
          col_widths = c(1, 4, 3, 2, 2),
          class = "upload-result-row",
          div(span(class = "placement-badge", row$round)),
          div(textInput(paste0("sr_match_opponent_", i), NULL,
                        value = row$opponent_username)),
          div(textInput(paste0("sr_match_member_", i), NULL,
                        value = if (!is.na(row$opponent_member_number)) row$opponent_member_number else "",
                        placeholder = "0000...")),
          div(textInput(paste0("sr_match_games_", i), NULL,
                        value = paste0(row$games_won, "-", row$games_lost, "-", row$games_tied),
                        placeholder = "W-L-T")),
          div(numericInput(paste0("sr_match_points_", i), NULL,
                           value = as.integer(row$match_points),
                           min = 0, max = 9))
        )
      })
    )
  )
})

# =============================================================================
# Submit Button
# =============================================================================

output$sr_match_final_button <- renderUI({
  req(rv$sr_match_ocr_results)

  div(
    class = "mt-3 d-flex justify-content-end gap-2",
    actionButton("sr_match_cancel", "Cancel", class = "btn-outline-secondary"),
    actionButton("sr_match_submit", "Submit Match History",
                 class = "btn-primary", icon = icon("check"))
  )
})

# =============================================================================
# Handle Match History Submission
# =============================================================================

observeEvent(input$sr_match_submit, {
  req(rv$sr_match_ocr_results)
  req(rv$sr_match_player)
  req(rv$sr_match_selected_tournament)

  results <- rv$sr_match_ocr_results
  player <- rv$sr_match_player
  selected <- rv$sr_match_selected_tournament
  tournament_id <- as.integer(selected$tournament_id)
  player_id <- as.integer(player$player_id)

  tryCatch({
    conn <- pool::localCheckout(db_pool)
    DBI::dbExecute(conn, "BEGIN")

    # Get scene_id for the tournament's store
    match_scene <- DBI::dbGetQuery(conn, "
      SELECT s.scene_id FROM tournaments t JOIN stores s ON t.store_id = s.store_id
      WHERE t.tournament_id = $1
    ", params = list(tournament_id))
    match_scene_id <- if (nrow(match_scene) > 0) match_scene$scene_id[1] else NULL

    # Insert each match - read from editable inputs
    matches_inserted <- 0
    for (i in seq_len(nrow(results))) {
      row <- results[i, ]

      opponent_username <- input[[paste0("sr_match_opponent_", i)]]
      if (is.null(opponent_username) || opponent_username == "") opponent_username <- row$opponent_username

      opponent_member_input <- input[[paste0("sr_match_member_", i)]]
      opponent_member <- normalize_member_number(opponent_member_input)

      # Parse games W-L-T from input
      games_input <- input[[paste0("sr_match_games_", i)]]
      games_won <- row$games_won
      games_lost <- row$games_lost
      games_tied <- row$games_tied
      if (!is.null(games_input) && grepl("^\\d+-\\d+-\\d+$", games_input)) {
        parts <- strsplit(games_input, "-")[[1]]
        games_won <- as.integer(parts[1])
        games_lost <- as.integer(parts[2])
        games_tied <- as.integer(parts[3])
      }

      match_points_input <- input[[paste0("sr_match_points_", i)]]
      match_points <- if (!is.null(match_points_input) && !is.na(match_points_input)) {
        as.integer(match_points_input)
      } else {
        as.integer(row$match_points)
      }

      opp_has_real_id <- !is.na(opponent_member) && nchar(opponent_member) > 0 &&
                         !grepl("^GUEST", opponent_member, ignore.case = TRUE)
      clean_opp_member <- if (opp_has_real_id) opponent_member else NA_character_

      opp_match_info <- match_player(opponent_username, conn, member_number = clean_opp_member, scene_id = match_scene_id)
      if (opp_match_info$status == "matched" || opp_match_info$status == "ambiguous") {
        opponent_id <- if (opp_match_info$status == "matched") opp_match_info$player_id else opp_match_info$candidates$player_id[1]
        if (opp_has_real_id) {
          DBI::dbExecute(conn, "
            UPDATE players SET member_number = $1, identity_status = 'verified'
            WHERE player_id = $2 AND (member_number IS NULL OR member_number = '')
          ", params = list(clean_opp_member, opponent_id))
        }
      } else {
        opp_identity <- if (opp_has_real_id) "verified" else "unverified"
        opp_slug <- generate_unique_slug(db_pool, opponent_username)
        new_opponent <- DBI::dbGetQuery(conn, "
          INSERT INTO players (display_name, slug, member_number, identity_status, home_scene_id)
          VALUES ($1, $2, $3, $4, $5)
          RETURNING player_id
        ", params = list(opponent_username, opp_slug, clean_opp_member, opp_identity, match_scene_id))
        opponent_id <- new_opponent$player_id[1]
      }

      tryCatch({
        DBI::dbExecute(conn, "
          INSERT INTO matches (tournament_id, round_number, player_id, opponent_id, games_won, games_lost, games_tied, match_points)
          VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
        ", params = list(
          tournament_id,
          as.integer(row$round),
          player_id,
          opponent_id,
          games_won,
          games_lost,
          games_tied,
          match_points
        ))
        matches_inserted <- matches_inserted + 1
      }, error = function(e) {
        message("[MATCH SUBMIT] Skipping duplicate match round ", row$round)
      })
    }

    DBI::dbExecute(conn, "COMMIT")

    # Clear form state
    rv$sr_match_ocr_results <- NULL
    rv$sr_match_uploaded_file <- NULL
    rv$sr_match_parsed_count <- 0
    rv$sr_match_total_rounds <- 0
    rv$sr_match_selected_tournament <- NULL

    # Refresh tournament list to show updated match counts
    if (!is.null(rv$sr_match_player)) {
      rv$sr_match_tournaments <- sr_match_get_tournaments(db_pool, rv$sr_match_player$player_id)
    }

    notify(
      paste("Match history submitted!", matches_inserted, "matches recorded."),
      type = "message"
    )

  }, error = function(e) {
    tryCatch(DBI::dbExecute(conn, "ROLLBACK"), error = function(re) NULL)
    notify(paste("Error submitting match history:", e$message), type = "error")
  })
})

# Handle match history cancel
observeEvent(input$sr_match_cancel, {
  rv$sr_match_ocr_results <- NULL
  rv$sr_match_uploaded_file <- NULL
  rv$sr_match_parsed_count <- 0
  rv$sr_match_total_rounds <- 0
  rv$sr_match_selected_tournament <- NULL
})
