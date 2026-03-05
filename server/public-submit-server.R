# server/public-submit-server.R
# Public Upload Results server logic

# Load OCR module
source("R/ocr.R")

# Initialize submit-related reactive values
rv$submit_ocr_results <- NULL
rv$submit_uploaded_files <- NULL
rv$submit_parsed_count <- 0
rv$submit_total_players <- 0
rv$deck_request_row <- NULL
rv$submit_refresh_trigger <- NULL
rv$ocr_pending_combined <- NULL
rv$ocr_pending_total_players <- NULL
rv$ocr_pending_total_rounds <- NULL
rv$ocr_pending_parsed_count <- NULL
rv$submit_grid_data <- NULL
rv$submit_player_matches <- list()
rv$submit_ocr_row_indices <- NULL

# Populate store dropdown
observe({

  stores <- safe_query(db_pool, "
    SELECT store_id, name FROM stores
    WHERE is_active = TRUE
    ORDER BY name
  ")
  choices <- setNames(stores$store_id, stores$name)
  updateSelectInput(session, "submit_store",
                    choices = c("Select store..." = "", choices))
})

# Populate format dropdown - sorted by release_date DESC (most recent first)
observe({

  formats <- safe_query(db_pool, "
    SELECT format_id, display_name FROM formats
    WHERE is_active = TRUE
    ORDER BY release_date DESC, sort_order ASC
  ")
  choices <- setNames(formats$format_id, formats$display_name)
  updateSelectInput(session, "submit_format",
                    choices = c("Select format..." = "", choices))
})

# Check for existing tournament when store and date are selected
output$submit_duplicate_warning <- renderUI({

  req(input$submit_store, input$submit_store != "")
  req(input$submit_date, !is.na(input$submit_date))

  # Check for existing tournaments on this store/date
  existing <- safe_query(db_pool, "
    SELECT t.tournament_id, t.event_type, t.player_count, s.name as store_name
    FROM tournaments t
    JOIN stores s ON t.store_id = s.store_id
    WHERE t.store_id = $1 AND t.event_date = $2
  ", params = list(as.integer(input$submit_store), as.character(input$submit_date)))

  if (nrow(existing) == 0) {
    return(NULL)
  }

  # Show warning with details about existing tournament(s)
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

# Preview uploaded files (screenshots or CSV)
output$submit_screenshot_preview <- renderUI({
  req(input$submit_screenshots)

  files <- input$submit_screenshots

  if (is.null(files) || nrow(files) == 0) return(NULL)

  # Store file info for later
  rv$submit_uploaded_files <- files

  # Create thumbnails/previews
  div(
    class = "screenshot-thumbnails",
    lapply(seq_len(nrow(files)), function(i) {
      file_path <- files$datapath[i]
      file_ext <- tolower(tools::file_ext(files$name[i]))

      if (file_ext == "csv") {
        # CSV preview: show row count
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
        # Image thumbnail
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

  # Clean member numbers (remove leading zeros display issues)
  if (!is.na(member_col)) {
    result$member_number <- gsub("^0+", "", result$member_number)
    result$member_number <- ifelse(result$member_number == "", NA_character_, result$member_number)
  }

  message(sprintf("[CSV] Parsed %d players from CSV", nrow(result)))
  result
}

# Helper: Complete OCR processing after validation
# Handles rank validation, padding, player matching, and step 2 transition
complete_ocr_processing <- function(combined, total_players, total_rounds, parsed_count) {
  # Rank-based validation against declared player count
  max_rank <- if (nrow(combined) > 0 && any(!is.na(combined$placement))) {
    max(combined$placement, na.rm = TRUE)
  } else {
    0
  }

  if (max_rank > total_players) {
    # Sanity check: if max_rank is wildly larger than actual parsed rows,
    # the parser likely misread a number (e.g., "96" from username "Legobuilder96")
    if (max_rank > parsed_count * 2 && max_rank > parsed_count + 8) {
      message("[SUBMIT] Suspicious max_rank=", max_rank, " with only ", parsed_count,
              " parsed players — ignoring (likely OCR noise)")
    } else {
      # Screenshots show more players than declared — auto-correct upward
      message("[SUBMIT] Auto-correcting player count: ", total_players, " -> ", max_rank,
              " (screenshots show rank ", max_rank, ")")
      total_players <- max_rank
    }
  }

  # Enforce exactly total_players rows
  if (nrow(combined) > total_players) {
    # Truncate to declared count (keep top N after sort by placement)
    combined <- combined[1:total_players, ]
  } else if (nrow(combined) < total_players) {
    # Pad with blank rows for missing ranks
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
        combined <- rbind(combined, blank_row)
      }
    }
  }

  # Re-sort after adding blank rows
  combined <- combined[order(combined$placement), ]

  # Preserve original ranking before sequential re-assignment
  combined$original_rank <- combined$placement

  # Re-assign placements sequentially (1 to N) for the review UI
  combined$placement <- seq_len(nrow(combined))

  # Add deck column
  combined$deck_id <- NA_integer_

  # Pre-match players against database
  combined$matched_player_id <- NA_integer_
  combined$match_status <- "new"  # "matched", "possible", "new"
  combined$matched_player_name <- NA_character_

  for (i in seq_len(nrow(combined))) {
      member_num <- combined$member_number[i]
      username <- combined$username[i]

      # Check if this is a GUEST ID (not a real member number - used for manually added players)
      is_guest_id <- !is.null(member_num) && !is.na(member_num) &&
                     grepl("^GUEST\\d+$", member_num, ignore.case = TRUE)

      # First try to match by member number (skip if GUEST ID - those aren't real)
      if (!is_guest_id && !is.null(member_num) && !is.na(member_num) && nchar(member_num) > 0) {
        player_by_member <- safe_query(db_pool, "
          SELECT player_id, display_name FROM players
          WHERE member_number = $1
          LIMIT 1
        ", params = list(member_num))

        if (nrow(player_by_member) > 0) {
          combined$matched_player_id[i] <- player_by_member$player_id[1]
          combined$matched_player_name[i] <- player_by_member$display_name[1]
          combined$match_status[i] <- "matched"
          next
        }
      }

      # GUEST IDs aren't real member numbers — try to find this player by username
      if (is_guest_id) {
        combined$member_number[i] <- ""

        # Look up by username to find their real member number
        if (!is.null(username) && !is.na(username) && nchar(username) > 0) {
          guest_lookup <- safe_query(db_pool, "
            SELECT player_id, display_name, member_number FROM players
            WHERE LOWER(display_name) = LOWER($1)
            LIMIT 1
          ", params = list(username))

          if (nrow(guest_lookup) > 0) {
            combined$matched_player_id[i] <- guest_lookup$player_id[1]
            combined$matched_player_name[i] <- guest_lookup$display_name[1]

            # If the DB has their real member number, pre-fill it
            if (!is.na(guest_lookup$member_number[1]) && nchar(guest_lookup$member_number[1]) > 0) {
              combined$member_number[i] <- guest_lookup$member_number[1]
              combined$match_status[i] <- "matched"
              message("[SUBMIT] GUEST '", username, "' matched to player with member number: ", guest_lookup$member_number[1])
            } else {
              combined$match_status[i] <- "matched"
              message("[SUBMIT] GUEST '", username, "' matched to existing player (no member number)")
            }
            next
          }
        }
      }

      # Try to match by username
      if (!is.null(username) && !is.na(username) && nchar(username) > 0) {
        player_by_name <- safe_query(db_pool, "
          SELECT player_id, display_name, member_number FROM players
          WHERE LOWER(display_name) = LOWER($1)
          LIMIT 1
        ", params = list(username))

        if (nrow(player_by_name) > 0) {
          combined$matched_player_id[i] <- player_by_name$player_id[1]
          combined$matched_player_name[i] <- player_by_name$display_name[1]
          combined$match_status[i] <- "possible"
        }
      }
    }

  rv$submit_ocr_results <- combined
  rv$submit_parsed_count <- parsed_count
  rv$submit_total_players <- total_players

  # Convert OCR results to shared grid format
  ocr_rows <- which(nchar(trimws(combined$username)) > 0)
  rv$submit_grid_data <- ocr_to_grid_data(combined)
  rv$submit_ocr_row_indices <- ocr_rows

  # Build player matches list for shared grid badges
  matches_list <- list()
  for (i in seq_len(nrow(combined))) {
    if (combined$match_status[i] %in% c("matched", "possible")) {
      matches_list[[as.character(i)]] <- list(
        status = "matched",
        player_id = combined$matched_player_id[i],
        member_number = if (!is.na(combined$member_number[i])) combined$member_number[i] else ""
      )
    } else if (nchar(trimws(combined$username[i])) > 0) {
      matches_list[[as.character(i)]] <- list(status = "new")
    }
  }
  rv$submit_player_matches <- matches_list

  # Switch to step 2
  shinyjs::hide("submit_wizard_step1")
  shinyjs::show("submit_wizard_step2")
  shinyjs::removeClass("submit_step1_indicator", "active")
  shinyjs::addClass("submit_step2_indicator", "active")

  # Show appropriate notification based on parsed vs expected
  if (parsed_count == total_players) {
    notify(
      paste("All", total_players, "players found"),
      type = "message"
    )
  } else if (parsed_count < total_players) {
    notify(
      paste("Parsed", parsed_count, "of", total_players, "players - fill in remaining manually"),
      type = "warning",
      duration = 8
    )
  } else {
    notify(
      paste("Found", parsed_count, "players, showing top", total_players),
      type = "warning",
      duration = 8
    )
  }
}

# Process OCR when button clicked
observeEvent(input$submit_process_ocr, {
  req(rv$submit_uploaded_files)

  files <- rv$submit_uploaded_files
  total_rounds <- input$submit_rounds
  total_players <- input$submit_players

  # Validate required fields first
  if (is.null(input$submit_store) || input$submit_store == "") {
    notify("Please select a store", type = "error")
    return()
  }
  if (is.na(input$submit_date)) {
    notify("Please select a date", type = "error")
    return()
  }
  if (is.null(input$submit_event_type) || input$submit_event_type == "") {
    notify("Please select an event type", type = "error")
    return()
  }
  if (is.null(input$submit_format) || input$submit_format == "") {
    notify("Please select a format", type = "error")
    return()
  }
  if (is.null(total_players) || total_players < 2) {
    notify("Please enter the total number of players", type = "error")
    return()
  }

  # Separate CSV files from image files
  file_exts <- tolower(tools::file_ext(files$name))
  csv_indices <- which(file_exts == "csv")
  img_indices <- which(file_exts != "csv")

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

      # Auto-update player count from CSV if it has more players
      if (nrow(parsed) > total_players) {
        total_players <- nrow(parsed)
        updateNumericInput(session, "submit_players", value = total_players)
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

      # Call OCR
      ocr_result <- tryCatch({
        gcv_detect_text(file_path, verbose = TRUE)
      }, error = function(e) {
        ocr_errors <<- c(ocr_errors, paste(file_name, ":", e$message))
        message("[SUBMIT] OCR error for ", file_name, ": ", e$message)
        NULL
      })

      # Extract text from structured result (backward compatible with plain string)
      ocr_text <- if (is.list(ocr_result)) ocr_result$text else ocr_result

      if (!is.null(ocr_text) && !is.na(ocr_text) && ocr_text != "") {
        ocr_texts <- c(ocr_texts, ocr_text)

        # Parse results (layout-first with text fallback)
        parsed <- tryCatch({
          parse_standings(ocr_result, total_rounds, verbose = TRUE)
        }, error = function(e) {
          ocr_errors <<- c(ocr_errors, paste("Parse error:", e$message))
          message("[SUBMIT] Parse error: ", e$message)
          data.frame()
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
      "\n\nWe extracted text from the image but couldn't identify player data. Make sure the screenshot shows the final standings with placements and usernames visible."
    } else {
      "\n\nCould not read the screenshots. Make sure the image is clear and shows the Bandai TCG+ standings screen. If this keeps happening, try a different screenshot or contact us."
    }
    notify(
      paste0("Could not extract player data from uploaded files.", error_detail),
      type = "error",
      duration = 10
    )
    return()
  }

  # Combine results from all screenshots
  combined <- do.call(rbind, all_results)

  # Smart deduplication for overlapping screenshots
  if (nrow(combined) > 1) {
    original_count <- nrow(combined)

    if (any(!is.na(combined$member_number) & combined$member_number != "")) {
      has_member <- !is.na(combined$member_number) & combined$member_number != ""

      # Separate GUEST IDs from real member numbers
      is_guest <- has_member & grepl("^GUEST\\d+$", combined$member_number, ignore.case = TRUE)
      has_real_member <- has_member & !is_guest

      with_real_member <- combined[has_real_member, ]
      with_guest <- combined[is_guest, ]
      without_member <- combined[!has_member, ]

      # Dedup real member numbers
      with_real_member <- with_real_member[!duplicated(with_real_member$member_number), ]

      # Dedup GUEST players by username (case-insensitive) since they share GUEST99999
      if (nrow(with_guest) > 0) {
        with_guest$username_lower <- tolower(with_guest$username)
        with_guest <- with_guest[!duplicated(with_guest$username_lower), ]
        with_guest$username_lower <- NULL
      }

      # Dedup no-member players by username
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

  # Sort by placement (contains real ranking numbers from layout parser)
  combined <- combined[order(combined$placement), ]

  # Track how many were parsed from OCR
  parsed_count <- nrow(combined)

  # Quality validation: warn if very few players found with no valid member numbers
  has_valid_members <- any(!is.na(combined$member_number) & combined$member_number != "" &
                           !grepl("^GUEST", combined$member_number, ignore.case = TRUE))

  if (parsed_count < ceiling(total_players * 0.5) && !has_valid_members) {
    # Store state for "proceed anyway" handler
    rv$ocr_pending_combined <- combined
    rv$ocr_pending_total_players <- total_players
    rv$ocr_pending_total_rounds <- total_rounds
    rv$ocr_pending_parsed_count <- parsed_count

    showModal(modalDialog(
      title = tagList(bsicons::bs_icon("exclamation-triangle-fill", class = "text-warning me-2"),
                      "Low Confidence Results"),
      div(
        p(sprintf("Only %d of %d expected players could be read from the screenshot(s).",
                  parsed_count, total_players)),
        p("This might mean:"),
        tags$ul(
          tags$li("The screenshot doesn't show Bandai TCG+ standings"),
          tags$li("The image is too blurry or cropped"),
          tags$li("The standings span multiple pages (upload all screenshots)")
        ),
        p("You can proceed and fill in the rest manually, or go back and try different screenshots.")
      ),
      footer = tagList(
        actionButton("ocr_proceed_anyway", "Proceed Anyway", class = "btn-warning"),
        actionButton("ocr_reupload", "Re-upload Screenshots", class = "btn-primary")
      ),
      easyClose = FALSE
    ))
    return()
  }

  complete_ocr_processing(combined, total_players, total_rounds, parsed_count)
})

# Back button - return to step 1
observeEvent(input$submit_back, {
  shinyjs::hide("submit_wizard_step2")
  shinyjs::show("submit_wizard_step1")
  shinyjs::removeClass("submit_step2_indicator", "active")
  shinyjs::addClass("submit_step1_indicator", "active")
})

# Handle "Proceed Anyway" from OCR quality warning
observeEvent(input$ocr_proceed_anyway, {
  removeModal()
  combined <- rv$ocr_pending_combined
  total_players <- rv$ocr_pending_total_players
  total_rounds <- rv$ocr_pending_total_rounds
  parsed_count <- rv$ocr_pending_parsed_count

  # Clear pending state
  rv$ocr_pending_combined <- NULL
  rv$ocr_pending_total_players <- NULL
  rv$ocr_pending_total_rounds <- NULL
  rv$ocr_pending_parsed_count <- NULL

  if (!is.null(combined)) {
    complete_ocr_processing(combined, total_players, total_rounds, parsed_count)
  }
})

# Handle "Re-upload" from OCR quality warning
observeEvent(input$ocr_reupload, {
  removeModal()
  rv$ocr_pending_combined <- NULL
  rv$ocr_pending_total_players <- NULL
  rv$ocr_pending_total_rounds <- NULL
  rv$ocr_pending_parsed_count <- NULL
  # User stays on step 1 - they can upload new screenshots
})

# Render summary banner
output$submit_summary_banner <- renderUI({
  req(rv$submit_ocr_results)

  # Get store name
  store_name <- "Not selected"
  if (!is.null(input$submit_store) && input$submit_store != "") {
    store <- safe_query(db_pool, "SELECT name FROM stores WHERE store_id = $1",
                        params = list(as.integer(input$submit_store)))
    if (nrow(store) > 0) store_name <- store$name[1]
  }

  # Parsing status
  parsed_count <- rv$submit_parsed_count
  total_players <- rv$submit_total_players
  parsing_status <- if (parsed_count == total_players) {
    div(class = "summary-item text-success",
        bsicons::bs_icon("check-circle-fill"),
        span(paste("All", total_players, "players found")))
  } else {
    div(class = "summary-item text-warning",
        bsicons::bs_icon("exclamation-triangle-fill"),
        span(paste("Parsed", parsed_count, "of", total_players, "players")))
  }

  # Get format display name
  format_name <- ""
  if (!is.null(input$submit_format) && input$submit_format != "") {
    fmt <- safe_query(db_pool, "SELECT display_name FROM formats WHERE format_id = $1",
                      params = list(input$submit_format))
    if (nrow(fmt) > 0) format_name <- fmt$display_name[1]
  }

  div(
    class = "tournament-summary-bar mb-3",
    div(
      class = "summary-bar-content",
      div(class = "summary-item",
          bsicons::bs_icon("shop"),
          span(store_name)),
      div(class = "summary-item",
          bsicons::bs_icon("calendar"),
          span(format(input$submit_date, "%b %d, %Y"))),
      div(class = "summary-item",
          bsicons::bs_icon("controller"),
          span(input$submit_event_type)),
      div(class = "summary-item",
          bsicons::bs_icon("tag"),
          span(format_name)),
      div(class = "summary-item",
          bsicons::bs_icon("people"),
          span(total_players, " players")),
      div(class = "summary-item",
          bsicons::bs_icon("flag"),
          span(input$submit_rounds, " rounds")),
      parsing_status
    )
  )
})

# Render match summary badges
output$submit_match_summary <- renderUI({
  req(rv$submit_ocr_results)

  results <- rv$submit_ocr_results

  matched_count <- sum(results$match_status == "matched", na.rm = TRUE)
  possible_count <- sum(results$match_status == "possible", na.rm = TRUE)
  new_count <- sum(results$match_status == "new", na.rm = TRUE)

  div(
    class = "match-summary-badges d-flex gap-2 mb-3",
    div(
      class = "match-badge match-badge--matched",
      bsicons::bs_icon("check-circle-fill"),
      span(class = "badge-count", matched_count),
      span(class = "badge-label", "Matched")
    ),
    div(
      class = "match-badge match-badge--possible",
      bsicons::bs_icon("question-circle-fill"),
      span(class = "badge-count", possible_count),
      span(class = "badge-label", "Possible")
    ),
    div(
      class = "match-badge match-badge--new",
      bsicons::bs_icon("person-plus-fill"),
      span(class = "badge-count", new_count),
      span(class = "badge-label", "New")
    )
  )
})

# Handle delete row in upload results review
observeEvent(input$submit_delete_row, {
  req(rv$submit_grid_data)

  row_idx <- as.integer(input$submit_delete_row)
  total_players <- rv$submit_total_players

  if (is.null(row_idx) || row_idx < 1 || row_idx > nrow(rv$submit_grid_data)) return()

  # Sync current inputs
  rv$submit_grid_data <- sync_grid_inputs(input, rv$submit_grid_data, "points", "submit_")
  grid <- rv$submit_grid_data

  grid <- grid[-row_idx, ]

  if (nrow(grid) < total_players) {
    blank_row <- data.frame(
      placement = nrow(grid) + 1,
      player_name = "", member_number = "",
      points = 0L, wins = 0L, losses = 0L, ties = 0L,
      deck_id = NA_integer_, match_status = "new",
      matched_player_id = NA_integer_,
      matched_member_number = NA_character_,
      result_id = NA_integer_,
      stringsAsFactors = FALSE
    )
    grid <- rbind(grid, blank_row)
  }

  grid$placement <- seq_len(nrow(grid))

  # Shift player matches
  new_matches <- list()
  for (j in seq_len(nrow(grid))) {
    old_idx <- if (j < row_idx) j else j + 1
    if (!is.null(rv$submit_player_matches[[as.character(old_idx)]])) {
      new_matches[[as.character(j)]] <- rv$submit_player_matches[[as.character(old_idx)]]
    }
  }
  rv$submit_player_matches <- new_matches

  # Update OCR row indices (shift down after deleted row)
  if (!is.null(rv$submit_ocr_row_indices)) {
    rv$submit_ocr_row_indices <- setdiff(
      ifelse(rv$submit_ocr_row_indices > row_idx,
             rv$submit_ocr_row_indices - 1,
             rv$submit_ocr_row_indices),
      row_idx
    )
  }

  rv$submit_grid_data <- grid

  # Also update OCR results for submission handler
  rv$submit_ocr_results <- rv$submit_ocr_results[-row_idx, ]
  if (nrow(rv$submit_ocr_results) > 0) {
    rv$submit_ocr_results$placement <- seq_len(nrow(rv$submit_ocr_results))
  }

  notify(paste0("Row removed. Players renumbered 1-", nrow(grid), "."), type = "message", duration = 3)
})

# Render results table using shared grid module
output$submit_results_table <- renderUI({
  req(rv$submit_grid_data)

  # Re-render when deck requests change
  rv$submit_refresh_trigger

  grid <- rv$submit_grid_data
  deck_choices <- build_deck_choices(db_pool)

  render_grid_ui(
    grid_data = grid,
    record_format = "points",
    is_release = FALSE,
    deck_choices = deck_choices,
    player_matches = rv$submit_player_matches,
    prefix = "submit_",
    mode = "review",
    ocr_rows = rv$submit_ocr_row_indices
  )
})

output$submit_filled_count <- renderUI({
  req(rv$submit_grid_data)
  grid <- rv$submit_grid_data
  filled <- sum(nchar(trimws(grid$player_name)) > 0)
  total <- nrow(grid)
  span(class = "text-muted small", sprintf("Filled: %d/%d", filled, total))
})


# =============================================================================
# Submit Grid: Paste from Spreadsheet
# =============================================================================

# =============================================================================
# Submit Grid: Player Matching (blur-based)
# =============================================================================

# Attach blur handlers for submit grid player matching
observe({
  req(rv$submit_grid_data)
  shinyjs::runjs("
    $(document).off('blur.submitGrid').on('blur.submitGrid', 'input[id^=\"submit_player_\"]', function() {
      var id = $(this).attr('id');
      var rowNum = parseInt(id.replace('submit_player_', ''));
      if (!isNaN(rowNum)) {
        Shiny.setInputValue('submit_player_blur', {row: rowNum, name: $(this).val(), ts: Date.now()}, {priority: 'event'});
      }
    });
  ")
})

observeEvent(input$submit_player_blur, {
  req(db_pool, rv$submit_grid_data)

  info <- input$submit_player_blur
  row_num <- info$row
  name <- trimws(info$name)

  if (is.null(row_num) || is.na(row_num)) return()
  if (row_num < 1 || row_num > nrow(rv$submit_grid_data)) return()

  # Sync all inputs before modifying reactive
  rv$submit_grid_data <- sync_grid_inputs(input, rv$submit_grid_data, "points", "submit_")

  if (nchar(name) == 0) {
    rv$submit_player_matches[[as.character(row_num)]] <- NULL
    rv$submit_grid_data$match_status[row_num] <- ""
    rv$submit_grid_data$matched_player_id[row_num] <- NA_integer_
    rv$submit_grid_data$matched_member_number[row_num] <- NA_character_
    return()
  }

  scene_id <- get_store_scene_id(as.integer(input$submit_store), db_pool)
  match_info <- match_player(name, db_pool, scene_id = scene_id)
  rv$submit_player_matches[[as.character(row_num)]] <- match_info
  rv$submit_grid_data$match_status[row_num] <- match_info$status
  if (match_info$status == "matched") {
    rv$submit_grid_data$matched_player_id[row_num] <- match_info$player_id
    rv$submit_grid_data$matched_member_number[row_num] <- match_info$member_number
  } else {
    rv$submit_grid_data$matched_player_id[row_num] <- NA_integer_
    rv$submit_grid_data$matched_member_number[row_num] <- NA_character_
  }
})


# Track which row triggered the deck request modal
rv$deck_request_row <- NULL

# Handle deck dropdown selections - detect "Request new deck" option
observe({
  req(rv$submit_grid_data)
  grid <- rv$submit_grid_data

  lapply(seq_len(nrow(grid)), function(i) {
    observeEvent(input[[paste0("submit_deck_", i)]], {
      if (isTRUE(input[[paste0("submit_deck_", i)]] == "__REQUEST_NEW__")) {
        rv$deck_request_row <- i
        showModal(modalDialog(
          title = "Request New Deck",
          div(
            class = "deck-request-form",
            textInput("deck_request_name", "Deck Name", placeholder = "e.g., Blue Flare"),
            uiOutput("deck_request_suggestions"),
            layout_columns(
              col_widths = c(6, 6),
              class = "deck-request-colors",
              selectInput("deck_request_color", "Primary Color",
                          choices = c("Select..." = "",
                                      "Red" = "Red", "Blue" = "Blue",
                                      "Yellow" = "Yellow", "Green" = "Green",
                                      "Purple" = "Purple", "Black" = "Black",
                                      "White" = "White"),
                          selectize = FALSE),
              selectInput("deck_request_color2", "Secondary Color (optional)",
                          choices = c("None" = "",
                                      "Red" = "Red", "Blue" = "Blue",
                                      "Yellow" = "Yellow", "Green" = "Green",
                                      "Purple" = "Purple", "Black" = "Black",
                                      "White" = "White"),
                          selectize = FALSE)
            ),
            textInput("deck_request_card_id", "Card ID (optional)",
                      placeholder = "e.g., BT12-031")
          ),
          footer = tagList(
            modalButton("Cancel"),
            actionButton("deck_request_submit", "Submit Request", class = "btn-primary")
          ),
          size = "m",
          easyClose = TRUE
        ))
        # Reset dropdown to Unknown while modal is open
        updateSelectizeInput(session, paste0("submit_deck_", i), selected = "")
      }
    }, ignoreInit = TRUE)
  })
})

# Debounced deck name input for suggestions (300ms delay)
deck_request_name_debounced <- reactive({
  input$deck_request_name
}) |> debounce(300)

# Deck request suggestions - find similar existing decks
output$deck_request_suggestions <- renderUI({
  deck_name <- deck_request_name_debounced()
  if (is.null(deck_name) || nchar(trimws(deck_name)) < 3) {
    return(NULL)
  }

  deck_name <- trimws(deck_name)

  # Search for similar deck names using multiple strategies:
  # 1. Exact partial match (ILIKE %name%)
  # 2. Word-based matching (any word from input matches any word in deck name)
  words <- unlist(strsplit(tolower(deck_name), "\\s+"))
  words <- words[nchar(words) >= 3]  # Only words with 3+ chars

  # Build search patterns
  like_pattern <- paste0("%", deck_name, "%")

  # Query for similar decks

  similar <- safe_query(db_pool, "
    SELECT DISTINCT archetype_name, primary_color, secondary_color
    FROM deck_archetypes
    WHERE is_active = TRUE
      AND (
        LOWER(archetype_name) LIKE LOWER($1)
        OR LOWER($2) LIKE '%' || LOWER(archetype_name) || '%'
      )
    ORDER BY archetype_name
    LIMIT 5
  ", params = list(like_pattern, deck_name), default = data.frame())

  # Also search by individual words if we have any
  if (length(words) > 0 && nrow(similar) < 5) {
    word_patterns <- paste0("%", words, "%")
    for (wp in word_patterns) {
      word_matches <- safe_query(db_pool, "
        SELECT DISTINCT archetype_name, primary_color, secondary_color
        FROM deck_archetypes
        WHERE is_active = TRUE
          AND LOWER(archetype_name) LIKE LOWER($1)
          AND archetype_name NOT IN (SELECT archetype_name FROM deck_archetypes WHERE LOWER(archetype_name) LIKE LOWER($2))
        ORDER BY archetype_name
        LIMIT 3
      ", params = list(wp, like_pattern), default = data.frame())

      if (nrow(word_matches) > 0) {
        similar <- rbind(similar, word_matches)
        similar <- similar[!duplicated(similar$archetype_name), ]
      }
      if (nrow(similar) >= 5) break
    }
  }

  if (nrow(similar) == 0) {
    return(NULL)
  }

  # Build suggestion list
  suggestion_items <- lapply(seq_len(nrow(similar)), function(i) {
    deck <- similar[i, ]
    color_text <- if (!is.na(deck$secondary_color) && deck$secondary_color != "") {
      paste0(deck$primary_color, "/", deck$secondary_color)
    } else {
      deck$primary_color
    }
    tags$li(
      tags$strong(deck$archetype_name),
      tags$span(class = "text-muted ms-2", paste0("(", color_text, ")"))
    )
  })

  div(
    class = "info-hint-box mt-2 mb-3",
    style = "padding: 0.625rem 0.875rem;",
    div(
      class = "d-flex align-items-start",
      bsicons::bs_icon("lightbulb", class = "info-hint-icon me-2 mt-1"),
      div(
        tags$strong("Similar decks found:"),
        tags$ul(class = "mb-0 ps-3 mt-1", style = "font-size: 0.875rem;", suggestion_items),
        tags$small(class = "text-muted d-block mt-1",
                   "Check if one of these matches before requesting.")
      )
    )
  )
})

# Handle deck request form submission
observeEvent(input$deck_request_submit, {


  # Validate required fields
  if (is.null(input$deck_request_name) || trimws(input$deck_request_name) == "") {
    notify("Please enter a deck name", type = "error")
    return()
  }
  if (is.null(input$deck_request_color) || input$deck_request_color == "") {
    notify("Please select a primary color", type = "error")
    return()
  }

  deck_name <- trimws(input$deck_request_name)
  primary_color <- input$deck_request_color
  secondary_color <- if (!is.null(input$deck_request_color2) && input$deck_request_color2 != "") {
    input$deck_request_color2
  } else {
    NA_character_
  }
  card_id <- if (!is.null(input$deck_request_card_id) && trimws(input$deck_request_card_id) != "") {
    trimws(input$deck_request_card_id)
  } else {
    NA_character_
  }

  # Check if deck with this name already exists
  existing <- safe_query(db_pool, "
    SELECT archetype_id FROM deck_archetypes
    WHERE LOWER(archetype_name) = LOWER($1)
  ", params = list(deck_name), default = data.frame())

  if (nrow(existing) > 0) {
    notify(paste0("A deck named '", deck_name, "' already exists. Please select it from the dropdown."), type = "warning")
    removeModal()
    return()
  }

  # Check if there's already a pending request with this name
  pending <- safe_query(db_pool, "
    SELECT request_id FROM deck_requests
    WHERE LOWER(deck_name) = LOWER($1) AND status = 'pending'
  ", params = list(deck_name), default = data.frame())

  if (nrow(pending) > 0) {
    notify(paste0("A request for '", deck_name, "' is already pending. You can select it from the dropdown."), type = "warning")
    removeModal()
    return()
  }

  # Insert the deck request
  request_result <- safe_query(db_pool, "
    INSERT INTO deck_requests (deck_name, primary_color, secondary_color, display_card_id, status)
    VALUES ($1, $2, $3, $4, 'pending')
    RETURNING request_id
  ", params = list(deck_name, primary_color, secondary_color, card_id), default = data.frame())
  request_id <- if (nrow(request_result) > 0) request_result$request_id[1] else NA_integer_

  # Close modal FIRST to prevent UI lockout, then trigger async dropdown refresh

  removeModal()

  notify(
    paste0("Deck request submitted: '", deck_name, "'. An admin will review it shortly."),
    type = "message"
  )

  # Store request info for async update, then trigger refresh

  rv$new_deck_request_id <- request_id
  rv$deck_choices_refresh <- Sys.time()
})

# Async handler to update deck dropdowns after a new deck request
# This runs separately from the modal submission to prevent UI lockout
observeEvent(rv$deck_choices_refresh, {
  req(rv$submit_grid_data, rv$new_deck_request_id)

  # Build updated deck choices with the new pending request
  decks <- safe_query(db_pool, "
    SELECT archetype_id, archetype_name FROM deck_archetypes
    WHERE is_active = TRUE
    ORDER BY archetype_name
  ", default = data.frame())
  pending_requests <- safe_query(db_pool, "
    SELECT request_id, deck_name FROM deck_requests
    WHERE status = 'pending'
    ORDER BY deck_name
  ", default = data.frame())

  updated_choices <- c("Unknown" = "")
  updated_choices <- c(updated_choices, "\U2795 Request new deck..." = "__REQUEST_NEW__")
  if (nrow(pending_requests) > 0) {
    pending_choices <- setNames(
      paste0("pending_", pending_requests$request_id),
      paste0("Pending: ", pending_requests$deck_name)
    )
    updated_choices <- c(updated_choices, pending_choices)
  }
  updated_choices <- c(updated_choices, setNames(as.character(decks$archetype_id), decks$archetype_name))

  # Update all deck dropdowns with new choices, preserving existing selections
  grid <- rv$submit_grid_data
  request_id <- rv$new_deck_request_id
  request_row <- rv$deck_request_row

  for (i in seq_len(nrow(grid))) {
    current_selection <- input[[paste0("submit_deck_", i)]]
    # For the row that triggered the request, select the new pending deck
    new_selection <- if (!is.null(request_row) && i == request_row) {
      paste0("pending_", request_id)
    } else if (!is.null(current_selection) && current_selection != "__REQUEST_NEW__") {
      current_selection
    } else {
      ""
    }
    updateSelectizeInput(session, paste0("submit_deck_", i),
                         choices = updated_choices,
                         selected = new_selection)
  }

  # Clear the request info
  rv$new_deck_request_id <- NULL
}, ignoreInit = TRUE)

# Handle final submission
observeEvent(input$submit_tournament, {
  req(rv$submit_ocr_results)


  # Validate confirmation checkbox
  if (!isTRUE(input$submit_confirm)) {
    notify("Please confirm the data is accurate before submitting.", type = "warning")
    return()
  }

  # Validate required fields
  if (is.null(input$submit_store) || input$submit_store == "") {
    notify("Please select a store", type = "error")
    return()
  }
  if (is.na(input$submit_date)) {
    notify("Please select a date", type = "error")
    return()
  }
  if (is.null(input$submit_event_type) || input$submit_event_type == "") {
    notify("Please select an event type", type = "error")
    return()
  }
  if (is.null(input$submit_format) || input$submit_format == "") {
    notify("Please select a format", type = "error")
    return()
  }

  results <- rv$submit_ocr_results

  # Sync grid inputs back to OCR results for submission
  if (!is.null(rv$submit_grid_data)) {
    rv$submit_grid_data <- sync_grid_inputs(input, rv$submit_grid_data, "points", "submit_")
    grid <- rv$submit_grid_data
    for (i in seq_len(min(nrow(grid), nrow(results)))) {
      results$username[i] <- grid$player_name[i]
      results$member_number[i] <- grid$member_number[i]
      results$points[i] <- grid$points[i]
      results$matched_player_id[i] <- grid$matched_player_id[i]
      results$match_status[i] <- grid$match_status[i]
    }
    rv$submit_ocr_results <- results
    results <- rv$submit_ocr_results
  }

  # Filter out blank rows before submission
  results <- results[!is.na(results$username) & trimws(results$username) != "", ]

  if (nrow(results) == 0) {
    notify("No results to submit — all rows are blank.", type = "warning")
    return()
  }

  # Check for duplicate tournament
  existing <- safe_query(db_pool, "
    SELECT tournament_id FROM tournaments
    WHERE store_id = $1 AND event_date = $2 AND event_type = $3
  ", params = list(
    as.integer(input$submit_store),
    as.character(input$submit_date),
    input$submit_event_type
  ), default = data.frame())

  if (nrow(existing) > 0) {
    notify("A tournament with this store, date, and event type already exists.",
                     type = "error")
    return()
  }

  tryCatch({
    # Check out a dedicated connection for the transaction
    conn <- pool::localCheckout(db_pool)

    # Begin transaction for atomic tournament + results insert
    DBI::dbExecute(conn, "BEGIN")

    # Create tournament (PostgreSQL auto-generates tournament_id)
    tourney_result <- DBI::dbGetQuery(conn, "
      INSERT INTO tournaments (store_id, event_date, event_type, format, player_count, rounds)
      VALUES ($1, $2, $3, $4, $5, $6)
      RETURNING tournament_id
    ", params = list(
      as.integer(input$submit_store),
      as.character(input$submit_date),
      input$submit_event_type,
      input$submit_format,
      nrow(results),
      input$submit_rounds
    ))
    tournament_id <- tourney_result$tournament_id[1]
    total_rounds <- input$submit_rounds

    # Insert each result
    for (i in seq_len(nrow(results))) {
      row <- results[i, ]

      # Get values from synced results (grid sync already applied above)
      username <- if (!is.null(row$username) && row$username != "") row$username else ""
      member_number <- if (!is.na(row$member_number) && trimws(row$member_number) != "") {
        trimws(row$member_number)
      } else {
        NA_character_
      }

      points <- if (!is.na(row$points)) as.integer(row$points) else 0L
      wins <- points %/% 3
      ties <- points %% 3
      losses <- max(0, total_rounds - wins - ties)

      deck_input <- input[[paste0("submit_deck_", i)]]
      deck_id <- NA_integer_
      pending_deck_request_id <- NA_integer_

      if (!is.null(deck_input) && deck_input != "" && deck_input != "__REQUEST_NEW__") {
        # Check if this is a pending deck request selection
        if (grepl("^pending_", deck_input)) {
          # Extract the request_id from "pending_123" format
          pending_deck_request_id <- as.integer(sub("^pending_", "", deck_input))
          # Use UNKNOWN archetype for now
        } else {
          # Regular deck selection
          deck_id <- as.integer(deck_input)
        }
      }

      # Determine player_id
      player_id <- NULL

      if (!is.na(row$matched_player_id) && row$match_status %in% c("matched", "possible")) {
        player_id <- row$matched_player_id
        if (!is.na(member_number)) {
          DBI::dbExecute(conn, "
            UPDATE players SET member_number = $1
            WHERE player_id = $2 AND member_number IS NULL
          ", params = list(member_number, player_id))
        }
      } else {
        player <- DBI::dbGetQuery(conn, "
          SELECT player_id FROM players
          WHERE (member_number IS NOT NULL AND member_number = $1) OR LOWER(display_name) = LOWER($2)
          LIMIT 1
        ", params = list(member_number, username))

        if (nrow(player) == 0) {
          # Create new player (PostgreSQL auto-generates player_id)
          new_player <- DBI::dbGetQuery(conn, "
            INSERT INTO players (display_name, member_number)
            VALUES ($1, $2)
            RETURNING player_id
          ", params = list(username, member_number))
          player_id <- new_player$player_id[1]
        } else {
          player_id <- player$player_id[1]
          if (!is.na(member_number)) {
            DBI::dbExecute(conn, "
              UPDATE players SET member_number = $1
              WHERE player_id = $2 AND member_number IS NULL
            ", params = list(member_number, player_id))
          }
        }
      }

      # Get UNKNOWN archetype_id if no deck selected
      if (is.na(deck_id)) {
        unknown <- DBI::dbGetQuery(conn, "SELECT archetype_id FROM deck_archetypes WHERE archetype_name = 'UNKNOWN'")
        deck_id <- if (nrow(unknown) > 0) unknown$archetype_id[1] else NA_integer_
      }

      # Insert result (PostgreSQL auto-generates result_id)
      DBI::dbExecute(conn, "
        INSERT INTO results (tournament_id, player_id, archetype_id, pending_deck_request_id, placement, wins, losses, ties)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      ", params = list(
        tournament_id, player_id, deck_id, pending_deck_request_id,
        row$placement, wins, losses, ties
      ))
    }

    # Commit transaction
    DBI::dbExecute(conn, "COMMIT")

    # Trigger refresh
    rv$data_refresh <- (rv$data_refresh %||% 0) + 1
    rv$results_refresh <- (rv$results_refresh %||% 0) + 1

    # Reset form
    rv$submit_ocr_results <- NULL
    rv$submit_uploaded_files <- NULL
    rv$submit_parsed_count <- 0
    rv$submit_total_players <- 0
    rv$submit_grid_data <- NULL
    rv$submit_player_matches <- list()
    rv$submit_ocr_row_indices <- NULL

    # Switch back to step 1
    shinyjs::hide("submit_wizard_step2")
    shinyjs::show("submit_wizard_step1")
    shinyjs::removeClass("submit_step2_indicator", "active")
    shinyjs::addClass("submit_step1_indicator", "active")

    # Clear inputs
    updateSelectInput(session, "submit_store", selected = "")
    updateDateInput(session, "submit_date", value = NA)
    updateSelectInput(session, "submit_event_type", selected = "")
    updateSelectInput(session, "submit_format", selected = "")
    updateNumericInput(session, "submit_players", value = 8)
    updateCheckboxInput(session, "submit_confirm", value = FALSE)
    shinyjs::reset("submit_screenshots")

    notify(
      paste("Tournament submitted successfully!", nrow(results), "results recorded."),
      type = "message"
    )

    # Navigate to tournaments page
    nav_select("main_content", "tournaments")
    rv$current_nav <- "tournaments"
    session$sendCustomMessage("updateSidebarNav", "nav_tournaments")

  }, error = function(e) {
    tryCatch(DBI::dbExecute(conn, "ROLLBACK"), error = function(re) NULL)
    message("[SUBMIT] Transaction error: ", conditionMessage(e))
    if (sentry_enabled) {
      tryCatch(
        sentryR::capture_exception(e, tags = sentry_context_tags()),
        error = function(se) NULL
      )
    }
    notify(paste("Error submitting tournament:", e$message), type = "error")
  })
})

# Request new store - reuse the shared modal function
observeEvent(input$submit_request_store, {
  show_store_request_modal()
})

# =============================================================================
# MATCH HISTORY TAB
# =============================================================================

# Initialize match history reactive values
rv$match_ocr_results <- NULL
rv$match_uploaded_file <- NULL
rv$match_parsed_count <- 0
rv$match_total_rounds <- 0

# Populate store dropdown for match history
observe({

  stores <- safe_query(db_pool, "
    SELECT store_id, name FROM stores
    WHERE is_active = TRUE
    ORDER BY name
  ")
  if (nrow(stores) > 0 && !is.null(stores$store_id)) {
    choices <- setNames(stores$store_id, stores$name)
    updateSelectInput(session, "match_store",
                      choices = c("All stores" = "", choices))
  }
})

# Populate tournament dropdown based on store selection
observe({


  # Use parameterized query for store filter
  has_store_filter <- !is.null(input$match_store) && input$match_store != ""

  if (has_store_filter) {
    tournaments <- safe_query(db_pool, "
      SELECT t.tournament_id, t.event_date, t.event_type, s.name as store_name
      FROM tournaments t
      JOIN stores s ON t.store_id = s.store_id
      WHERE t.store_id = $1
      ORDER BY t.event_date DESC
      LIMIT 50
    ", params = list(as.integer(input$match_store)))
  } else {
    tournaments <- safe_query(db_pool, "
      SELECT t.tournament_id, t.event_date, t.event_type, s.name as store_name
      FROM tournaments t
      JOIN stores s ON t.store_id = s.store_id
      ORDER BY t.event_date DESC
      LIMIT 50
    ")
  }

  if (nrow(tournaments) > 0 && !is.null(tournaments$tournament_id)) {
    labels <- paste0(tournaments$store_name, " - ",
                     format(as.Date(tournaments$event_date), "%b %d, %Y"),
                     " (", tournaments$event_type, ")")
    choices <- setNames(tournaments$tournament_id, labels)
    updateSelectInput(session, "match_tournament",
                      choices = c("Select a tournament..." = "", choices))
  } else {
    updateSelectInput(session, "match_tournament",
                      choices = c("No tournaments found" = ""))
  }
})

# Show tournament info when selected
output$match_tournament_info <- renderUI({
  req(input$match_tournament)
  req(input$match_tournament != "")


  tournament <- safe_query(db_pool, "
    SELECT t.*, s.name as store_name
    FROM tournaments t
    JOIN stores s ON t.store_id = s.store_id
    WHERE t.tournament_id = $1
  ", params = list(as.integer(input$match_tournament)))

  if (nrow(tournament) == 0) return(NULL)

  t <- tournament[1, ]
  div(
    class = "mt-2 p-2 rounded",
    style = "background: rgba(15, 76, 129, 0.1);",
    tags$small(
      strong(t$store_name), " | ",
      format(as.Date(t$event_date), "%B %d, %Y"), " | ",
      t$event_type, " | ",
      t$player_count, " players | ",
      t$rounds, " rounds"
    )
  )
})

# Preview uploaded match history screenshot
output$match_screenshot_preview <- renderUI({
  req(input$match_screenshots)

  file <- input$match_screenshots
  if (is.null(file)) return(NULL)

  rv$match_uploaded_file <- file

  # Read file and encode as base64 for inline display
  file_ext <- tolower(tools::file_ext(file$name))
  mime_type <- switch(file_ext,
    "png" = "image/png",
    "jpg" = "image/jpeg",
    "jpeg" = "image/jpeg",
    "webp" = "image/webp",
    "image/png"
  )

  # Encode image as base64
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

# Process match history OCR
observeEvent(input$match_process_ocr, {
  req(rv$match_uploaded_file)

  # Validate required fields
  if (is.null(input$match_tournament) || input$match_tournament == "") {
    notify("Please select a tournament", type = "error")
    return()
  }

  if (is.null(input$match_player_username) || trimws(input$match_player_username) == "") {
    notify("Please enter your username", type = "error")
    shinyjs::removeClass("match_username_hint", "d-none")
    return()
  } else {
    shinyjs::addClass("match_username_hint", "d-none")
  }

  if (is.null(input$match_player_member) || trimws(input$match_player_member) == "") {
    notify("Please enter your member number", type = "error")
    shinyjs::removeClass("match_member_hint", "d-none")
    return()
  } else {
    shinyjs::addClass("match_member_hint", "d-none")
  }

  # Get the round count from the selected tournament
  tournament <- safe_query(db_pool, "
    SELECT rounds FROM tournaments WHERE tournament_id = $1
  ", params = list(as.integer(input$match_tournament)))

  total_rounds <- if (nrow(tournament) > 0 && !is.na(tournament$rounds[1])) {
    tournament$rounds[1]
  } else {
    4  # Default if not found
  }

  file <- rv$match_uploaded_file

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

  # Extract text from structured result (backward compatible with plain string)
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

  # Track how many rounds were parsed
  parsed_count <- nrow(parsed)

  # Ensure we have exactly total_rounds rows
  if (parsed_count < total_rounds) {
    # Create blank rows for missing rounds
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
    # Sort by round
    parsed <- parsed[order(parsed$round), ]
  } else if (parsed_count > total_rounds) {
    # More rounds than expected - truncate
    parsed <- parsed[parsed$round <= total_rounds, ]
  }

  # Store results and counts
  rv$match_ocr_results <- parsed
  rv$match_parsed_count <- parsed_count
  rv$match_total_rounds <- total_rounds

  # Show appropriate notification
  if (parsed_count == 0) {
    notify(
      paste("No matches found - fill in all", total_rounds, "rounds manually"),
      type = "warning",
      duration = 8
    )
  } else if (parsed_count == total_rounds) {
    notify(paste("All", total_rounds, "rounds found"), type = "message")
  } else if (parsed_count < total_rounds) {
    notify(
      paste("Parsed", parsed_count, "of", total_rounds, "rounds - fill in remaining manually"),
      type = "warning",
      duration = 8
    )
  } else {
    notify(
      paste("Found", parsed_count, "rounds, showing", total_rounds),
      type = "warning",
      duration = 8
    )
  }
})

# Render match history preview table with editable fields
output$match_results_preview <- renderUI({
  req(rv$match_ocr_results)

  results <- rv$match_ocr_results
  parsed_count <- rv$match_parsed_count
  total_rounds <- rv$match_total_rounds

  # Create status badge
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
      # Instructions
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
          # Round number (read-only display)
          div(
            span(class = "placement-badge", row$round)
          ),
          # Opponent username (editable)
          div(
            textInput(paste0("match_opponent_", i), NULL,
                      value = row$opponent_username)
          ),
          # Opponent member number (editable)
          div(
            textInput(paste0("match_member_", i), NULL,
                      value = if (!is.na(row$opponent_member_number)) row$opponent_member_number else "",
                      placeholder = "0000...")
          ),
          # Games W-L-T (editable as text to allow "2-0-0" format)
          div(
            textInput(paste0("match_games_", i), NULL,
                      value = paste0(row$games_won, "-", row$games_lost, "-", row$games_tied),
                      placeholder = "W-L-T")
          ),
          # Match points (editable)
          div(
            numericInput(paste0("match_points_", i), NULL,
                         value = as.integer(row$match_points),
                         min = 0, max = 9)
          )
        )
      })
    )
  )
})

# Match history submit button
output$match_final_button <- renderUI({
  req(rv$match_ocr_results)

  div(
    class = "mt-3 d-flex justify-content-end gap-2",
    actionButton("match_cancel", "Cancel", class = "btn-outline-secondary"),
    actionButton("match_submit", "Submit Match History",
                 class = "btn-primary", icon = icon("check"))
  )
})

# Handle match history submission
observeEvent(input$match_submit, {
  req(rv$match_ocr_results)

  req(input$match_tournament)

  if (is.null(input$match_player_username) || trimws(input$match_player_username) == "") {
    notify("Please enter your username", type = "error")
    return()
  }

  if (is.null(input$match_player_member) || trimws(input$match_player_member) == "") {
    notify("Please enter your member number", type = "error")
    return()
  }

  results <- rv$match_ocr_results
  tournament_id <- as.integer(input$match_tournament)
  submitter_username <- trimws(input$match_player_username)
  submitter_member <- trimws(input$match_player_member)

  tryCatch({
    # Check out a dedicated connection for the transaction
    conn <- pool::localCheckout(db_pool)

    # Begin transaction for atomic match history insert
    DBI::dbExecute(conn, "BEGIN")

    # Find or create submitting player
    player <- DBI::dbGetQuery(conn, "
      SELECT player_id FROM players
      WHERE (member_number IS NOT NULL AND member_number = $1) OR LOWER(display_name) = LOWER($2)
      LIMIT 1
    ", params = list(submitter_member, submitter_username))

    if (nrow(player) == 0) {
      new_player <- DBI::dbGetQuery(conn, "
        INSERT INTO players (display_name, member_number)
        VALUES ($1, $2)
        RETURNING player_id
      ", params = list(submitter_username, submitter_member))
      player_id <- new_player$player_id[1]
    } else {
      player_id <- player$player_id[1]
      DBI::dbExecute(conn, "
        UPDATE players SET member_number = $1
        WHERE player_id = $2 AND member_number IS NULL
      ", params = list(submitter_member, player_id))
    }

    # Insert each match - read from editable inputs
    matches_inserted <- 0
    for (i in seq_len(nrow(results))) {
      row <- results[i, ]

      # Get edited values from inputs
      opponent_username <- input[[paste0("match_opponent_", i)]]
      if (is.null(opponent_username) || opponent_username == "") opponent_username <- row$opponent_username

      opponent_member_input <- input[[paste0("match_member_", i)]]
      opponent_member <- if (!is.null(opponent_member_input) && trimws(opponent_member_input) != "") {
        trimws(opponent_member_input)
      } else {
        NA_character_
      }

      # Parse games W-L-T from input
      games_input <- input[[paste0("match_games_", i)]]
      games_won <- row$games_won
      games_lost <- row$games_lost
      games_tied <- row$games_tied
      if (!is.null(games_input) && grepl("^\\d+-\\d+-\\d+$", games_input)) {
        parts <- strsplit(games_input, "-")[[1]]
        games_won <- as.integer(parts[1])
        games_lost <- as.integer(parts[2])
        games_tied <- as.integer(parts[3])
      }

      # Get match points from input
      match_points_input <- input[[paste0("match_points_", i)]]
      match_points <- if (!is.null(match_points_input) && !is.na(match_points_input)) {
        as.integer(match_points_input)
      } else {
        as.integer(row$match_points)
      }

      opponent <- DBI::dbGetQuery(conn, "
        SELECT player_id FROM players
        WHERE (member_number IS NOT NULL AND member_number = $1) OR LOWER(display_name) = LOWER($2)
        LIMIT 1
      ", params = list(opponent_member, opponent_username))

      if (nrow(opponent) == 0) {
        new_opponent <- DBI::dbGetQuery(conn, "
          INSERT INTO players (display_name, member_number)
          VALUES ($1, $2)
          RETURNING player_id
        ", params = list(opponent_username, opponent_member))
        opponent_id <- new_opponent$player_id[1]
      } else {
        opponent_id <- opponent$player_id[1]
        if (!is.na(opponent_member)) {
          DBI::dbExecute(conn, "
            UPDATE players SET member_number = $1
            WHERE player_id = $2 AND member_number IS NULL
          ", params = list(opponent_member, opponent_id))
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

    # Commit transaction
    DBI::dbExecute(conn, "COMMIT")

    # Clear form
    rv$match_ocr_results <- NULL
    rv$match_uploaded_file <- NULL
    rv$match_parsed_count <- 0
    rv$match_total_rounds <- 0
    updateSelectInput(session, "match_tournament", selected = "")
    updateTextInput(session, "match_player_username", value = "")
    updateTextInput(session, "match_player_member", value = "")
    shinyjs::reset("match_screenshots")

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
observeEvent(input$match_cancel, {
  rv$match_ocr_results <- NULL
  rv$match_uploaded_file <- NULL
  rv$match_parsed_count <- 0
  rv$match_total_rounds <- 0
  shinyjs::reset("match_screenshots")
})
