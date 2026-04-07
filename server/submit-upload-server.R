# =============================================================================
# Submit Results: Upload Server (OCR + CSV)
# Handles Bandai TCG+ screenshot OCR and CSV export parsing
# Extracted from public-submit-server.R, adapted for sr_ prefix
# =============================================================================

# Helper: Parse Bandai TCG+ CSV export into standings data frame
# CSV columns: Ranking, Membership Number, User Name, Win Points, OMW %, OOMW %, Memo, Deck URLs
parse_tcgplus_csv <- function(file_path, total_rounds = 4) {
  # File size check — reject files over 500KB (TCG+ CSVs are tiny)
  file_size <- file.info(file_path)$size
  if (is.na(file_size) || file_size > 500 * 1024) {
    stop("File too large — expected a small Bandai TCG+ CSV export")
  }

  csv <- tryCatch(
    read.csv(file_path, stringsAsFactors = FALSE, strip.white = TRUE, nrows = 300),
    error = function(e) {
      message("[CSV] Parse error: ", e$message)
      return(NULL)
    }
  )

  if (is.null(csv) || nrow(csv) == 0) return(data.frame())

  # Normalize column names (handle spaces, case variations)
  names(csv) <- trimws(names(csv))

  # Map columns — try common naming patterns
  rank_col <- grep("^Ranking$|^Rank$|^Place$", names(csv), ignore.case = TRUE, value = TRUE)[1]
  member_col <- grep("^Membership.Number$|^Member.*Number$|^MemberID$", names(csv), ignore.case = TRUE, value = TRUE)[1]
  name_col <- grep("^User.Name$|^Username$|^Name$|^Player$", names(csv), ignore.case = TRUE, value = TRUE)[1]
  points_col <- grep("^Win.Points$|^Points$|^WinPoints$", names(csv), ignore.case = TRUE, value = TRUE)[1]
  deck_url_col <- grep("^Deck.URLs?$|^DeckURL$|^Deck.Link$", names(csv), ignore.case = TRUE, value = TRUE)[1]
  omw_col <- grep("^OMW[^O]|^OMW$|^Opp\\.Match|^Opp[^.]*Match.*Win", names(csv), ignore.case = TRUE, value = TRUE)[1]
  oomw_col <- grep("^OOMW|^Opp\\.Opp|^Opp.*Opp.*Match.*Win", names(csv), ignore.case = TRUE, value = TRUE)[1]
  memo_col <- grep("^Memo$|^Notes?$", names(csv), ignore.case = TRUE, value = TRUE)[1]

  if (is.na(rank_col) || is.na(name_col)) {
    stop("Not a Bandai TCG+ CSV — missing Ranking or User Name columns")
  }

  # Validate data types — rankings must be numeric integers
  ranks <- suppressWarnings(as.integer(csv[[rank_col]]))
  if (all(is.na(ranks))) {
    stop("Ranking column contains no valid numbers")
  }

  # Validate rankings are sequential and reasonable (1 to N)
  valid_ranks <- ranks[!is.na(ranks)]
  if (min(valid_ranks) != 1 || max(valid_ranks) > 256) {
    stop("Rankings out of expected range (1-256)")
  }

  # Validate points if present — must be non-negative integers
  if (!is.na(points_col)) {
    pts <- suppressWarnings(as.integer(csv[[points_col]]))
    valid_pts <- pts[!is.na(pts)]
    if (length(valid_pts) > 0 && (any(valid_pts < 0) || any(valid_pts > 100))) {
      stop("Win Points out of expected range (0-100)")
    }
  }

  # Build result data frame matching OCR output format
  result <- data.frame(
    placement = as.integer(csv[[rank_col]]),
    username = trimws(as.character(csv[[name_col]])),
    member_number = if (!is.na(member_col)) trimws(as.character(csv[[member_col]])) else NA_character_,
    points = if (!is.na(points_col)) as.integer(csv[[points_col]]) else NA_integer_,
    stringsAsFactors = FALSE
  )

  # Calculate W-L-T from points (3 per win, 1 per tie, 0 per loss)
  result$wins <- ifelse(!is.na(result$points), result$points %/% 3L, NA_integer_)
  remaining <- ifelse(!is.na(result$points), result$points %% 3L, NA_integer_)
  result$ties <- ifelse(!is.na(remaining), remaining, NA_integer_)
  result$losses <- ifelse(!is.na(result$wins) & !is.na(result$ties),
    as.integer(total_rounds) - result$wins - result$ties, NA_integer_)

  # Normalize member numbers to 10-digit zero-padded format
  if (!is.na(member_col)) {
    result$member_number <- vapply(result$member_number, normalize_member_number, character(1), USE.NAMES = FALSE)
  }

  # Extract deck URLs if column exists — validate against allowlist
  if (!is.na(deck_url_col)) {
    raw_urls <- trimws(as.character(csv[[deck_url_col]]))
    result$deck_url <- vapply(raw_urls, function(u) {
      validate_decklist_url(u) %||% NA_character_
    }, character(1), USE.NAMES = FALSE)
  }

  # Extract tiebreaker stats (OMW%, OOMW%) — stored for reference, not displayed
  if (!is.na(omw_col)) {
    raw <- trimws(as.character(csv[[omw_col]]))
    result$omw_pct <- suppressWarnings(as.numeric(sub("%$", "", raw)))
  }
  if (!is.na(oomw_col)) {
    raw <- trimws(as.character(csv[[oomw_col]]))
    result$oomw_pct <- suppressWarnings(as.numeric(sub("%$", "", raw)))
  }

  # Extract memo — may contain deck names in some events
  if (!is.na(memo_col)) {
    result$memo <- trimws(as.character(csv[[memo_col]]))
    result$memo[is.na(result$memo) | result$memo == "" | tolower(result$memo) == "undefined"] <- NA_character_
  }

  message(sprintf("[CSV] Parsed %d players from CSV", nrow(result)))
  result
}

# Helper: Complete OCR processing after validation
# Handles rank validation, padding, player matching, and step 2 transition
sr_complete_ocr_processing <- function(combined, total_players, total_rounds, parsed_count) {
  # Rank-based validation against declared player count
  max_rank <- if (nrow(combined) > 0 && any(!is.na(combined$placement))) {
    max(combined$placement, na.rm = TRUE)
  } else {
    0
  }

  if (max_rank > total_players) {
    if (max_rank > parsed_count * 2 && max_rank > parsed_count + 8) {
      message("[SUBMIT] Suspicious max_rank=", max_rank, " with only ", parsed_count,
              " parsed players — ignoring (likely OCR noise)")
    } else {
      message("[SUBMIT] Auto-correcting player count: ", total_players, " -> ", max_rank,
              " (screenshots show rank ", max_rank, ")")
      total_players <- max_rank
    }
  }

  # Enforce exactly total_players rows
  if (nrow(combined) > total_players) {
    combined <- combined[1:total_players, ]
  } else if (nrow(combined) < total_players) {
    existing_ranks <- combined$placement
    for (p in seq_len(total_players)) {
      if (!(p %in% existing_ranks)) {
        blank_row <- data.frame(
          placement = p,
          username = "",
          member_number = "",
          points = 0,
          wins = 0,
          losses = total_rounds,
          ties = 0,
          stringsAsFactors = FALSE
        )
        # Preserve CSV-sourced columns if they exist
        if ("deck_url" %in% names(combined)) blank_row$deck_url <- NA_character_
        if ("omw_pct" %in% names(combined)) blank_row$omw_pct <- NA_real_
        if ("oomw_pct" %in% names(combined)) blank_row$oomw_pct <- NA_real_
        if ("memo" %in% names(combined)) blank_row$memo <- NA_character_
        combined <- rbind(combined, blank_row)
      }
    }
  }

  # Re-sort after adding blank rows
  combined <- combined[order(combined$placement), ]

  # Preserve original ranking before sequential re-assignment
  combined$original_rank <- combined$placement
  combined$placement <- seq_len(nrow(combined))

  # Add deck column
  combined$deck_id <- NA_integer_

  # Pre-match players against database using identity-aware match_player()
  combined$matched_player_id <- NA_integer_
  combined$match_status <- "new"
  combined$matched_player_name <- NA_character_

  # Get scene_id for identity-aware matching
  scene_id <- get_store_scene_id(as.integer(input$sr_store), db_pool)

  for (i in seq_len(nrow(combined))) {
    member_num <- combined$member_number[i]
    username <- combined$username[i]
    if (is.null(username) || is.na(username) || nchar(trimws(username)) == 0) next

    # Strip GUEST IDs and placeholder member numbers before matching
    if (!is.null(member_num) && !is.na(member_num) && is_placeholder_member(member_num)) {
      combined$member_number[i] <- ""
      member_num <- ""
    }

    match_info <- match_player(username, db_pool, member_number = member_num, scene_id = scene_id)

    if (match_info$status == "matched") {
      combined$matched_player_id[i] <- match_info$player_id
      combined$match_status[i] <- "matched"
      player_info <- safe_query(db_pool, "
        SELECT display_name, member_number FROM players WHERE player_id = $1
      ", params = list(match_info$player_id), default = data.frame())
      if (nrow(player_info) > 0) {
        combined$matched_player_name[i] <- player_info$display_name[1]
        if (nchar(member_num) == 0 && !is.na(player_info$member_number[1]) && nchar(player_info$member_number[1]) > 0) {
          combined$member_number[i] <- player_info$member_number[1]
        }
      }
    } else if (match_info$status == "ambiguous") {
      combined$matched_player_id[i] <- match_info$candidates$player_id[1]
      combined$matched_player_name[i] <- match_info$candidates$display_name[1]
      combined$match_status[i] <- "matched"
    } else {
      combined$match_status[i] <- match_info$status
    }
  }

  rv$sr_ocr_results <- combined
  rv$sr_parsed_count <- parsed_count
  rv$sr_total_players <- total_players

  # Cache static values for Step 2 summary bar (avoid re-querying on every render)
  store <- safe_query(db_pool, "SELECT name FROM stores WHERE store_id = $1",
                      params = list(as.integer(input$sr_store)))
  rv$sr_store_name <- if (nrow(store) > 0) store$name[1] else "Not selected"
  fmt <- safe_query(db_pool, "SELECT display_name FROM formats WHERE format_id = $1",
                    params = list(input$sr_format))
  rv$sr_format_name <- if (nrow(fmt) > 0) fmt$display_name[1] else ""
  rv$sr_deck_choices <- build_deck_choices(db_pool)

  # Convert OCR results to shared grid format
  ocr_rows <- which(nchar(trimws(combined$username)) > 0)
  rv$sr_grid_data <- ocr_to_grid_data(combined)
  rv$sr_ocr_row_indices <- ocr_rows

  # Build player matches list for shared grid badges
  matches_list <- list()
  for (i in seq_len(nrow(combined))) {
    username <- combined$username[i]
    if (is.null(username) || is.na(username) || nchar(trimws(username)) == 0) next

    member_num <- combined$member_number[i]

    if (combined$match_status[i] == "matched") {
      matches_list[[as.character(i)]] <- list(
        status = "matched",
        player_id = combined$matched_player_id[i],
        member_number = if (!is.na(member_num)) member_num else ""
      )
    } else if (combined$match_status[i] == "new_similar") {
      re_match <- match_player(username, db_pool, member_number = member_num, scene_id = scene_id)
      matches_list[[as.character(i)]] <- re_match
    } else {
      matches_list[[as.character(i)]] <- list(status = "new")
    }
  }
  rv$sr_player_matches <- matches_list

  # Switch to step 2
  shinyjs::hide("sr_step1")
  shinyjs::show("sr_step2")
  shinyjs::runjs("$('#sr_step1_indicator').removeClass('active').addClass('completed'); $('#sr_step2_indicator').addClass('active');")

  # Show appropriate notification
  if (parsed_count == total_players) {
    notify(paste("All", total_players, "players found"), type = "message")
  } else if (parsed_count < total_players) {
    notify(paste("Parsed", parsed_count, "of", total_players, "players - fill in remaining manually"),
           type = "warning", duration = 8)
  } else {
    notify(paste("Found", parsed_count, "players, showing top", total_players),
           type = "warning", duration = 8)
  }
}

# Preview uploaded files (screenshots or CSV)
output$sr_screenshot_preview <- renderUI({
  req(input$sr_screenshots)

  files <- input$sr_screenshots
  if (is.null(files) || nrow(files) == 0) return(NULL)

  rv$sr_uploaded_files <- files

  div(
    class = "screenshot-thumbnails",
    lapply(seq_len(nrow(files)), function(i) {
      file_path <- files$datapath[i]
      file_ext <- tolower(tools::file_ext(files$name[i]))

      if (file_ext == "csv") {
        csv_data <- tryCatch(read.csv(file_path, stringsAsFactors = FALSE), error = function(e) NULL)
        row_count <- if (!is.null(csv_data)) nrow(csv_data) else "?"

        div(
          class = "screenshot-thumb",
          div(
            style = "width: 100%; height: 100%; display: flex; flex-direction: column; align-items: center; justify-content: center; background: rgba(0, 200, 255, 0.06); border-radius: 4px;",
            bsicons::bs_icon("filetype-csv", size = "2rem", class = "text-primary mb-1"),
            span(class = "small text-muted", sprintf("%s players", row_count))
          ),
          div(
            class = "screenshot-thumb-label",
            span(class = "filename", files$name[i])
          )
        )
      } else {
        mime_type <- switch(file_ext,
          "png" = "image/png",
          "jpg" = "image/jpeg",
          "jpeg" = "image/jpeg",
          "webp" = "image/webp",
          "image/png"
        )

        img_data <- base64enc::base64encode(file_path)
        img_src <- paste0("data:", mime_type, ";base64,", img_data)

        div(
          class = "screenshot-thumb",
          tags$img(src = img_src, alt = files$name[i]),
          div(
            class = "screenshot-thumb-label",
            span(class = "filename", files$name[i])
          )
        )
      }
    })
  )
})

# Process OCR/CSV when Step 1 "Continue" is clicked (upload method only)
observeEvent(input$sr_step1_next, {
  req(rv$sr_active_method == "upload")
  req(rv$sr_uploaded_files)

  files <- rv$sr_uploaded_files
  total_rounds <- input$sr_rounds
  total_players <- input$sr_players

  # Separate CSV files from image files
  file_exts <- tolower(tools::file_ext(files$name))
  csv_indices <- which(file_exts == "csv")
  img_indices <- which(file_exts != "csv")

  # Track upload type for submission_method column (applied at final submit time)
  rv$sr_submission_method <- if (length(img_indices) > 0) "screenshot_ocr" else "csv_upload"

  all_results <- list()
  ocr_errors <- c()
  ocr_texts <- c()

  # Process CSV files first (no OCR needed)
  for (i in csv_indices) {
    file_path <- files$datapath[i]
    file_name <- files$name[i]

    parsed <- tryCatch({
      parse_tcgplus_csv(file_path, total_rounds)
    }, error = function(e) {
      ocr_errors <<- c(ocr_errors, paste(file_name, ":", e$message))
      message("[SUBMIT] CSV parse error for ", file_name, ": ", e$message)
      data.frame()
    })

    if (nrow(parsed) > 0) {
      all_results[[length(all_results) + 1]] <- parsed
      message("[SUBMIT] Parsed ", nrow(parsed), " results from CSV: ", file_name)

      if (nrow(parsed) > total_players) {
        total_players <- nrow(parsed)
        updateNumericInput(session, "sr_players", value = total_players)
      }
    } else {
      ocr_errors <- c(ocr_errors, paste(file_name, ": Could not parse CSV data"))
    }
  }

  # Process image files with OCR
  if (length(img_indices) > 0) {
    showModal(modalDialog(
      div(
        class = "text-center py-4",
        div(class = "processing-spinner mb-3"),
        h5(class = "text-primary", "Processing Screenshots"),
        p(class = "text-muted mb-0", id = "ocr_status_text", "Extracting player data..."),
        tags$small(class = "text-muted", paste(length(img_indices), "file(s) to process"))
      ),
      title = NULL,
      footer = NULL,
      easyClose = FALSE,
      size = "s"
    ))

    for (i in img_indices) {
      file_path <- files$datapath[i]
      file_name <- files$name[i]

      ocr_result <- tryCatch({
        gcv_detect_text(file_path, verbose = TRUE)
      }, error = function(e) {
        ocr_errors <<- c(ocr_errors, paste(file_name, ":", e$message))
        message("[SUBMIT] OCR error for ", file_name, ": ", e$message)
        NULL
      })

      ocr_text <- if (is.list(ocr_result)) ocr_result$text else ocr_result

      if (!is.null(ocr_text) && !is.na(ocr_text) && ocr_text != "") {
        ocr_texts <- c(ocr_texts, ocr_text)

        parsed <- tryCatch({
          parse_standings(ocr_result, total_rounds, verbose = TRUE)
        }, error = function(e) {
          ocr_errors <<- c(ocr_errors, paste("Parse error:", e$message))
          message("[SUBMIT] Parse error: ", e$message)
          data.frame(
            placement = integer(), username = character(),
            member_number = character(), points = integer(),
            wins = integer(), losses = integer(), ties = integer(),
            stringsAsFactors = FALSE
          )
        })

        if (nrow(parsed) > 0) {
          all_results[[length(all_results) + 1]] <- parsed
          message("[SUBMIT] Parsed ", nrow(parsed), " results from ", file_name)
        } else {
          message("[SUBMIT] No results parsed from ", file_name)
        }
      } else {
        message("[SUBMIT] No OCR text returned for ", file_name)
        if (is.null(ocr_text)) {
          ocr_errors <- c(ocr_errors, paste(file_name, ": OCR returned NULL (check API key)"))
        } else {
          ocr_errors <- c(ocr_errors, paste(file_name, ": OCR returned empty text"))
        }
      }
    }

    removeModal()
  }

  if (length(all_results) == 0) {
    message("[SUBMIT] OCR failed - ocr_errors: ", paste(ocr_errors, collapse = "; "))
    message("[SUBMIT] OCR failed - ocr_texts: ", paste(ocr_texts, collapse = "; "))
    error_detail <- if (length(ocr_errors) > 0) {
      paste("\n\nDetails:", paste(ocr_errors, collapse = "\n"))
    } else if (length(ocr_texts) > 0) {
      "\n\nWe extracted text from the image but couldn't identify player data. Make sure the screenshot shows the final standings from the Bandai TCG+ mobile app with placements and usernames visible. Desktop browser screenshots are not currently supported."
    } else {
      "\n\nCould not read the screenshots. Make sure the image is clear and shows the Bandai TCG+ standings screen (mobile app only). Desktop browser screenshots are not currently supported. If this keeps happening, try a different screenshot or contact us."
    }
    notify(
      paste0("Could not extract player data from uploaded files.", error_detail),
      type = "error",
      duration = 10
    )
    return()
  }

  # Combine results — normalize columns across CSV and OCR results before rbind
  all_cols <- unique(unlist(lapply(all_results, names)))
  # Infer column types from existing data frames for proper typed NAs
  col_types <- list()
  for (df in all_results) {
    for (col in names(df)) {
      if (is.null(col_types[[col]])) col_types[[col]] <- class(df[[col]])[1]
    }
  }
  all_results <- lapply(all_results, function(df) {
    for (col in setdiff(all_cols, names(df))) {
      typed_na <- switch(col_types[[col]] %||% "character",
        numeric = NA_real_, integer = NA_integer_, NA_character_)
      df[[col]] <- typed_na
    }
    df[, all_cols, drop = FALSE]
  })
  combined <- do.call(rbind, all_results)

  # Validate combined result has required columns before proceeding
  standings_required_cols <- c("placement", "username", "member_number",
                               "points", "wins", "losses", "ties")
  missing_cols <- setdiff(standings_required_cols, names(combined))
  if (length(missing_cols) > 0) {
    message("[SUBMIT] Combined results missing columns: ", paste(missing_cols, collapse = ", "))
    notify(
      paste0("Could not read the uploaded screenshots. The image may be from a desktop browser ",
             "or an unsupported format.\n\nTip: Use screenshots from the Bandai TCG+ mobile app for best results."),
      type = "error", duration = 10
    )
    return()
  }

  # Smart deduplication for overlapping screenshots
  if (nrow(combined) > 1) {
    original_count <- nrow(combined)

    if (any(!is.na(combined$member_number) & combined$member_number != "")) {
      has_member <- !is.na(combined$member_number) & combined$member_number != ""
      is_guest <- has_member & grepl("^GUEST\\d+$", combined$member_number, ignore.case = TRUE)
      has_real_member <- has_member & !is_guest

      with_real_member <- combined[has_real_member, ]
      with_guest <- combined[is_guest, ]
      without_member <- combined[!has_member, ]

      with_real_member <- with_real_member[!duplicated(with_real_member$member_number), ]

      if (nrow(with_guest) > 0) {
        with_guest$username_lower <- tolower(with_guest$username)
        with_guest <- with_guest[!duplicated(with_guest$username_lower), ]
        with_guest$username_lower <- NULL
      }

      if (nrow(without_member) > 0) {
        without_member$username_lower <- tolower(without_member$username)
        without_member <- without_member[!duplicated(without_member$username_lower), ]
        without_member$username_lower <- NULL
      }

      combined <- rbind(with_real_member, with_guest, without_member)
    } else {
      combined$username_lower <- tolower(combined$username)
      combined <- combined[!duplicated(combined$username_lower), ]
      combined$username_lower <- NULL
    }

    deduped_count <- nrow(combined)
    if (original_count != deduped_count) {
      message("[SUBMIT] Deduplication: ", original_count, " -> ", deduped_count, " players")
    }
  }

  # Sort by placement
  combined <- combined[order(combined$placement), ]

  parsed_count <- nrow(combined)

  # Quality validation: warn if very few players found with no valid member numbers
  has_valid_members <- any(!is.na(combined$member_number) & combined$member_number != "" &
                           !grepl("^GUEST", combined$member_number, ignore.case = TRUE))

  if (parsed_count < ceiling(total_players * 0.5) && !has_valid_members) {
    rv$sr_ocr_pending_combined <- combined
    rv$sr_ocr_pending_total_players <- total_players
    rv$sr_ocr_pending_total_rounds <- total_rounds
    rv$sr_ocr_pending_parsed_count <- parsed_count

    showModal(modalDialog(
      title = tagList(bsicons::bs_icon("exclamation-triangle-fill", class = "text-warning me-2"),
                      "Low Confidence Results"),
      div(
        p(sprintf("Only %d of %d expected players could be read from the screenshot(s).",
                  parsed_count, total_players)),
        p("This might mean:"),
        tags$ul(
          tags$li("The screenshot is from a desktop browser (only mobile app screenshots are supported)"),
          tags$li("The screenshot doesn't show Bandai TCG+ standings"),
          tags$li("The image is too blurry or cropped"),
          tags$li("The standings span multiple pages (upload all screenshots)")
        ),
        p("You can proceed and fill in the rest manually, or go back and try different screenshots.")
      ),
      footer = tagList(
        actionButton("sr_ocr_proceed_anyway", "Proceed Anyway", class = "btn-warning"),
        actionButton("sr_ocr_reupload", "Re-upload Screenshots", class = "btn-primary")
      ),
      easyClose = FALSE
    ))
    return()
  }

  tryCatch(
    sr_complete_ocr_processing(combined, total_players, total_rounds, parsed_count),
    error = function(e) {
      message("[SUBMIT] Error in OCR post-processing: ", conditionMessage(e))
      if (sentry_enabled) tryCatch(sentryR::capture_exception(e, tags = sentry_context_tags()), error = function(se) NULL)
      notify("Something went wrong processing the screenshot data. Please try again or contact us if the problem persists.",
             type = "error", duration = 10)
    }
  )
}, priority = -1)
# priority = -1 ensures this runs AFTER the shared sr_step1_next handler (which returns early for upload)

# Handle "Proceed Anyway" from OCR quality warning
observeEvent(input$sr_ocr_proceed_anyway, {
  removeModal()
  combined <- rv$sr_ocr_pending_combined
  total_players <- rv$sr_ocr_pending_total_players
  total_rounds <- rv$sr_ocr_pending_total_rounds
  parsed_count <- rv$sr_ocr_pending_parsed_count

  rv$sr_ocr_pending_combined <- NULL
  rv$sr_ocr_pending_total_players <- NULL
  rv$sr_ocr_pending_total_rounds <- NULL
  rv$sr_ocr_pending_parsed_count <- NULL

  if (!is.null(combined)) {
    tryCatch(
      sr_complete_ocr_processing(combined, total_players, total_rounds, parsed_count),
      error = function(e) {
        message("[SUBMIT] Error in OCR post-processing: ", conditionMessage(e))
        if (sentry_enabled) tryCatch(sentryR::capture_exception(e, tags = sentry_context_tags()), error = function(se) NULL)
        notify("Something went wrong processing the screenshot data. Please try again or contact us if the problem persists.",
               type = "error", duration = 10)
      }
    )
  }
})

# Handle "Re-upload" from OCR quality warning
observeEvent(input$sr_ocr_reupload, {
  removeModal()
  rv$sr_ocr_pending_combined <- NULL
  rv$sr_ocr_pending_total_players <- NULL
  rv$sr_ocr_pending_total_rounds <- NULL
  rv$sr_ocr_pending_parsed_count <- NULL
})
