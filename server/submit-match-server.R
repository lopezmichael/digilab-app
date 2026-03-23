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
rv$sr_match_candidates <- list()          # match_player() candidates keyed by row

# =============================================================================
# Auto-Fill Helpers (Layers 1-3)
# =============================================================================

# Layer 1: Match opponents against tournament participants
# Returns parsed_matches with added columns: opponent_player_id, match_status, autofill_source
sr_autofill_from_participants <- function(parsed_matches, tournament_id, pool) {
  participants <- safe_query(pool, "
    SELECT p.player_id, p.display_name, p.member_number
    FROM results r
    JOIN players p ON r.player_id = p.player_id
    WHERE r.tournament_id = $1
  ", params = list(tournament_id), default = data.frame())

  # Initialize new columns
  parsed_matches$opponent_player_id <- NA_integer_
  parsed_matches$match_status <- ""
  parsed_matches$autofill_source <- ""

  if (nrow(participants) == 0) return(parsed_matches)

  for (i in seq_len(nrow(parsed_matches))) {
    opp_name <- parsed_matches$opponent_username[i]
    opp_member <- parsed_matches$opponent_member_number[i]
    if (nchar(opp_name) == 0 && (is.na(opp_member) || nchar(opp_member) == 0)) next

    # Priority 1: Exact member number match
    if (!is.na(opp_member) && nchar(opp_member) > 0 && !grepl("^GUEST", opp_member, ignore.case = TRUE)) {
      norm_member <- normalize_member_number(opp_member)
      if (!is.na(norm_member) && nchar(norm_member) > 0) {
        idx <- which(!is.na(participants$member_number) & participants$member_number == norm_member)
        if (length(idx) == 1) {
          parsed_matches$opponent_player_id[i] <- participants$player_id[idx]
          parsed_matches$match_status[i] <- "matched"
          parsed_matches$autofill_source[i] <- "participant_member"
          # Also fill member number from DB in case OCR was partial
          parsed_matches$opponent_member_number[i] <- participants$member_number[idx]
          next
        }
      }
    }

    # Priority 2: Exact name match (case-insensitive)
    if (nchar(opp_name) > 0) {
      name_matches <- which(tolower(participants$display_name) == tolower(opp_name))
      if (length(name_matches) == 1) {
        parsed_matches$opponent_player_id[i] <- participants$player_id[name_matches]
        parsed_matches$match_status[i] <- "matched"
        parsed_matches$autofill_source[i] <- "participant_name"
        if (!is.na(participants$member_number[name_matches]) && nchar(participants$member_number[name_matches]) > 0) {
          parsed_matches$opponent_member_number[i] <- participants$member_number[name_matches]
        }
        next
      } else if (length(name_matches) > 1) {
        parsed_matches$match_status[i] <- "ambiguous"
        next
      }
    }

    # Priority 3: Fuzzy name match against participants (local, no DB call)
    if (nchar(opp_name) >= 3) {
      sims <- stringdist::stringsim(tolower(opp_name), tolower(participants$display_name), method = "jw")
      best_idx <- which.max(sims)
      if (length(best_idx) > 0 && sims[best_idx] > 0.85) {
        parsed_matches$opponent_player_id[i] <- participants$player_id[best_idx]
        parsed_matches$match_status[i] <- "matched"
        parsed_matches$autofill_source[i] <- "participant_fuzzy"
        parsed_matches$opponent_username[i] <- participants$display_name[best_idx]  # correct OCR name
        if (!is.na(participants$member_number[best_idx]) && nchar(participants$member_number[best_idx]) > 0) {
          parsed_matches$opponent_member_number[i] <- participants$member_number[best_idx]
        }
        next
      }
    }
  }

  parsed_matches
}

# Layer 2: Pre-fill scores from other players' prior match submissions
sr_autofill_from_prior_matches <- function(parsed_matches, tournament_id, player_id, pool) {
  # Only query for rows with matched opponents
  matched_opp_ids <- unique(na.omit(parsed_matches$opponent_player_id))
  if (length(matched_opp_ids) == 0) return(parsed_matches)

  # Batch query: all matches in this tournament where any matched opponent submitted against our player
  prior <- safe_query(pool, "
    SELECT m.round_number, m.player_id AS opponent_id,
           m.games_won, m.games_lost, m.games_tied, m.match_points
    FROM matches m
    WHERE m.tournament_id = $1
      AND m.opponent_id = $2
  ", params = list(tournament_id, player_id), default = data.frame())

  if (nrow(prior) == 0) return(parsed_matches)

  for (i in seq_len(nrow(parsed_matches))) {
    opp_id <- parsed_matches$opponent_player_id[i]
    if (is.na(opp_id)) next

    # Find this opponent's submission for this round
    round_match <- prior[prior$round_number == parsed_matches$round[i] & prior$opponent_id == opp_id, ]
    if (nrow(round_match) == 0) next

    # Flip W/L — their wins are our losses
    parsed_matches$games_won[i] <- round_match$games_lost[1]
    parsed_matches$games_lost[i] <- round_match$games_won[1]
    parsed_matches$games_tied[i] <- round_match$games_tied[1]

    # Derive match points from our perspective
    our_won <- round_match$games_lost[1]
    our_lost <- round_match$games_won[1]
    parsed_matches$match_points[i] <- if (our_won > our_lost) 3L else if (our_won < our_lost) 0L else 1L

    parsed_matches$autofill_source[i] <- paste0(parsed_matches$autofill_source[i], "+prior_match")
  }

  parsed_matches
}

# Layer 3: Run match_player() for unresolved opponents (full DB scope)
sr_enrich_with_match_player <- function(parsed_matches, tournament_id, pool, candidates_out) {
  # Get scene_id for scoped matching
  scene_info <- safe_query(pool, "
    SELECT s.scene_id FROM tournaments t
    JOIN stores s ON t.store_id = s.store_id
    WHERE t.tournament_id = $1
  ", params = list(tournament_id), default = data.frame())
  scene_id <- if (nrow(scene_info) > 0) scene_info$scene_id[1] else NULL

  for (i in seq_len(nrow(parsed_matches))) {
    # Skip already matched rows
    if (!is.na(parsed_matches$opponent_player_id[i])) next

    name <- parsed_matches$opponent_username[i]
    member <- parsed_matches$opponent_member_number[i]
    if (nchar(name) == 0) next

    clean_member <- NULL
    if (!is.na(member) && nchar(member) > 0 && !grepl("^GUEST", member, ignore.case = TRUE)) {
      clean_member <- normalize_member_number(member)
    }

    info <- match_player(name, pool, member_number = clean_member, scene_id = scene_id)
    parsed_matches$match_status[i] <- info$status

    if (info$status == "matched") {
      parsed_matches$opponent_player_id[i] <- info$player_id
      if (!is.null(info$member_number) && !is.na(info$member_number) && nchar(info$member_number) > 0) {
        parsed_matches$opponent_member_number[i] <- info$member_number
      }
      parsed_matches$autofill_source[i] <- "match_player"
    } else if (info$status %in% c("ambiguous", "new_similar")) {
      candidates_out[[as.character(i)]] <- info$candidates
    }
  }

  list(parsed = parsed_matches, candidates = candidates_out)
}

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

  # ==========================================================================
  # Auto-fill: Layers 1-3
  # ==========================================================================
  tournament_id <- as.integer(selected$tournament_id)
  player_id <- as.integer(rv$sr_match_player$player_id)

  # Layer 1: Match opponents against tournament participants
  parsed <- sr_autofill_from_participants(parsed, tournament_id, db_pool)

  # Layer 2: Pre-fill scores from prior match submissions
  parsed <- sr_autofill_from_prior_matches(parsed, tournament_id, player_id, db_pool)

  # Layer 3: Run match_player() for unresolved opponents
  candidates <- list()
  result <- sr_enrich_with_match_player(parsed, tournament_id, db_pool, candidates)
  parsed <- result$parsed
  candidates <- result$candidates

  # Count auto-fill stats for notification
  matched_count <- sum(parsed$match_status == "matched", na.rm = TRUE)
  autofilled_scores <- sum(grepl("prior_match", parsed$autofill_source, fixed = TRUE), na.rm = TRUE)

  # Store results and counts
  rv$sr_match_ocr_results <- parsed
  rv$sr_match_parsed_count <- parsed_count
  rv$sr_match_total_rounds <- total_rounds
  rv$sr_match_candidates <- candidates

  # Show appropriate notification
  if (parsed_count == 0) {
    notify(paste("No matches found - fill in all", total_rounds, "rounds manually"),
           type = "warning", duration = 8)
  } else {
    parts <- c()
    if (parsed_count == total_rounds) {
      parts <- c(parts, paste("All", total_rounds, "rounds found"))
    } else {
      parts <- c(parts, paste("Parsed", parsed_count, "of", total_rounds, "rounds"))
    }
    if (matched_count > 0) {
      parts <- c(parts, paste(matched_count, "opponents matched"))
    }
    if (autofilled_scores > 0) {
      parts <- c(parts, paste(autofilled_scores, "scores pre-filled"))
    }
    msg_type <- if (parsed_count == total_rounds && matched_count > 0) "message" else "warning"
    notify(paste(parts, collapse = " — "), type = msg_type, duration = 8)
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

  # Count auto-fill stats for summary
  matched_count <- sum(results$match_status == "matched", na.rm = TRUE)
  autofilled_count <- sum(grepl("prior_match", results$autofill_source, fixed = TRUE), na.rm = TRUE)

  # Build autofill badge
  autofill_badge <- if (matched_count > 0) {
    span(class = "badge bg-info ms-2",
         paste(matched_count, "matched",
               if (autofilled_count > 0) paste0("/ ", autofilled_count, " pre-filled") else ""))
  }

  card(
    class = "mt-3",
    card_header(
      class = "d-flex justify-content-between align-items-center",
      div(span("Review & Edit Match History"), autofill_badge),
      status_badge
    ),
    card_body(
      div(
        class = "alert alert-info d-flex mb-3",
        bsicons::bs_icon("pencil-square", class = "me-2 flex-shrink-0"),
        tags$small("Review and edit the extracted data. Correct any OCR errors before submitting.",
                   if (parsed_count < total_rounds) " Fill in missing rounds manually." else "",
                   if (matched_count > 0) " Opponents with green indicators were matched to known players." else "")
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
        status <- if ("match_status" %in% names(row)) row$match_status else ""

        # Build match indicator
        indicator <- if (!is.null(status) && nchar(status) > 0) {
          if (status == "matched") {
            div(class = "player-match-indicator matched",
                bsicons::bs_icon("check-circle-fill"),
                span(class = "match-label", "Matched"))
          } else if (status == "ambiguous") {
            div(class = "player-match-indicator ambiguous",
                style = "cursor: pointer;",
                onclick = sprintf("Shiny.setInputValue('sr_match_resolve_row', %d, {priority: 'event'})", i),
                bsicons::bs_icon("exclamation-triangle-fill"),
                span(class = "match-label", "Ambiguous"))
          } else if (status == "new_similar") {
            div(class = "player-match-indicator new-similar",
                style = "cursor: pointer;",
                onclick = sprintf("Shiny.setInputValue('sr_match_resolve_row', %d, {priority: 'event'})", i),
                bsicons::bs_icon("person-exclamation"),
                span(class = "match-label", "Similar"))
          } else if (status == "new") {
            div(class = "player-match-indicator new",
                bsicons::bs_icon("person-plus-fill"),
                span(class = "match-label", "New"))
          }
        }

        layout_columns(
          col_widths = c(1, 4, 3, 2, 2),
          class = paste0("upload-result-row",
                         if (!is.null(status) && status == "matched") " sr-row-matched" else ""),
          div(span(class = "placement-badge", row$round)),
          div(
            textInput(paste0("sr_match_opponent_", i), NULL,
                      value = row$opponent_username),
            indicator
          ),
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

      # Use pre-matched player ID from auto-fill if available
      pre_matched_id <- if ("opponent_player_id" %in% names(row) && !is.na(row$opponent_player_id)) {
        as.integer(row$opponent_player_id)
      } else {
        NULL
      }

      if (!is.null(pre_matched_id)) {
        opponent_id <- pre_matched_id
        # Still update member number if we have a real one
        if (opp_has_real_id) {
          DBI::dbExecute(conn, "
            UPDATE players SET member_number = $1, identity_status = 'verified'
            WHERE player_id = $2 AND (member_number IS NULL OR member_number = '')
          ", params = list(clean_opp_member, opponent_id))
        }
      } else {
        # Fallback: run match_player() at submission time
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
  rv$sr_match_candidates <- list()
})

# =============================================================================
# Ambiguous/Similar Player Resolution Modal
# =============================================================================

observeEvent(input$sr_match_resolve_row, {
  row_num <- input$sr_match_resolve_row
  req(rv$sr_match_ocr_results)
  req(rv$sr_match_candidates)

  candidates <- rv$sr_match_candidates[[as.character(row_num)]]
  if (is.null(candidates) || nrow(candidates) == 0) return()

  row <- rv$sr_match_ocr_results[row_num, ]
  status <- row$match_status

  # Build candidate list for modal
  candidate_buttons <- lapply(seq_len(nrow(candidates)), function(j) {
    c <- candidates[j, ]
    member_text <- if (!is.na(c$member_number) && nchar(c$member_number) > 0) {
      paste0("#", c$member_number)
    } else {
      "no member #"
    }

    actionButton(
      paste0("sr_match_pick_", row_num, "_", j),
      div(
        class = "d-flex justify-content-between align-items-center w-100",
        div(
          tags$strong(c$display_name),
          tags$span(class = "text-muted ms-2 small", member_text)
        ),
        if ("sim" %in% names(c)) {
          span(class = "badge bg-info", paste0(round(c$sim * 100), "% similar"))
        }
      ),
      class = "list-group-item list-group-item-action mb-1",
      style = "text-align: left;"
    )
  })

  # Add "Create New Player" option
  new_btn <- actionButton(
    paste0("sr_match_pick_", row_num, "_new"),
    div(
      class = "d-flex align-items-center gap-2",
      bsicons::bs_icon("person-plus-fill"),
      "Create new player"
    ),
    class = "list-group-item list-group-item-action mb-1",
    style = "text-align: left;"
  )

  showModal(modalDialog(
    title = paste0("Resolve: ", row$opponent_username, " (Round ", row$round, ")"),
    div(
      class = "list-group",
      if (status == "ambiguous") {
        tags$p(class = "text-muted small mb-2",
               "Multiple players match this name. Select the correct one:")
      } else {
        tags$p(class = "text-muted small mb-2",
               "No exact match found. These players have similar names:")
      },
      candidate_buttons,
      tags$hr(),
      new_btn
    ),
    footer = modalButton("Cancel"),
    easyClose = TRUE,
    size = "m"
  ))
})

# Handle candidate selection from resolution modal
# Pre-register observers for up to 15 rounds x 5 candidates each
lapply(1:15, function(row_num) {
  # Candidate pick buttons (up to 5 candidates per row)
  lapply(1:5, function(j) {
    btn_id <- paste0("sr_match_pick_", row_num, "_", j)
    observeEvent(input[[btn_id]], {
      req(rv$sr_match_ocr_results)
      candidates <- rv$sr_match_candidates[[as.character(row_num)]]
      if (is.null(candidates) || j > nrow(candidates)) return()

      c <- candidates[j, ]
      rv$sr_match_ocr_results$opponent_player_id[row_num] <- c$player_id
      rv$sr_match_ocr_results$match_status[row_num] <- "matched"
      rv$sr_match_ocr_results$opponent_username[row_num] <- c$display_name
      if (!is.na(c$member_number) && nchar(c$member_number) > 0) {
        rv$sr_match_ocr_results$opponent_member_number[row_num] <- c$member_number
      }
      rv$sr_match_candidates[[as.character(row_num)]] <- NULL
      removeModal()
    }, ignoreInit = TRUE)
  })

  # "Create new" button
  new_btn_id <- paste0("sr_match_pick_", row_num, "_new")
  observeEvent(input[[new_btn_id]], {
    req(rv$sr_match_ocr_results)
    rv$sr_match_ocr_results$match_status[row_num] <- "new"
    rv$sr_match_ocr_results$opponent_player_id[row_num] <- NA_integer_
    rv$sr_match_candidates[[as.character(row_num)]] <- NULL
    removeModal()
  }, ignoreInit = TRUE)
})
