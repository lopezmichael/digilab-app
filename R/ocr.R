# R/ocr.R
# Google Cloud Vision OCR integration for screenshot parsing

library(httr2)
library(base64enc)

#' Call Google Cloud Vision API for text detection
#'
#' @param image_data Path to local image file OR raw bytes
#' @param api_key Google Cloud Vision API key
#' @param verbose Print debug messages
#' @return List with text, annotations (data frame), image_width, image_height; or NULL on error
gcv_detect_text <- function(image_data, api_key = Sys.getenv("GOOGLE_CLOUD_VISION_API_KEY"), verbose = TRUE) {
  if (verbose) message("[OCR] Starting text detection...")

  if (is.null(api_key) || api_key == "") {
    warning("GOOGLE_CLOUD_VISION_API_KEY not set")
    if (verbose) message("[OCR] ERROR: API key not set")
    return(NULL)
  }
  if (verbose) message("[OCR] API key found (length: ", nchar(api_key), ")")

  # Handle both file path and raw bytes
  if (is.character(image_data) && file.exists(image_data)) {
    if (verbose) message("[OCR] Reading file: ", image_data)
    image_base64 <- base64encode(image_data)
  } else if (is.raw(image_data)) {
    if (verbose) message("[OCR] Using raw bytes (length: ", length(image_data), ")")
    image_base64 <- base64encode(image_data)
  } else {
    warning("Invalid image_data: must be file path or raw bytes")
    if (verbose) message("[OCR] ERROR: Invalid image_data type: ", class(image_data))
    return(NULL)
  }
  if (verbose) message("[OCR] Base64 encoded (length: ", nchar(image_base64), ")")

  # Build and execute request
  tryCatch({
    if (verbose) message("[OCR] Calling Google Cloud Vision API...")

    response <- request("https://vision.googleapis.com/v1/images:annotate") |>
      req_url_query(key = api_key) |>
      req_body_json(list(
        requests = list(list(
          image = list(content = image_base64),
          features = list(list(type = "DOCUMENT_TEXT_DETECTION"))
        ))
      )) |>
      req_perform() |>
      resp_body_json()

    if (verbose) message("[OCR] API response received")

    # Check for API errors in response
    if (!is.null(response$responses[[1]]$error)) {
      err <- response$responses[[1]]$error
      warning(paste("Vision API error:", err$message))
      if (verbose) message("[OCR] API ERROR: ", err$message)
      return(NULL)
    }

    # Extract full text annotation
    text <- response$responses[[1]]$fullTextAnnotation$text
    if (is.null(text)) {
      warning("No text detected in image")
      if (verbose) message("[OCR] No text detected in image")
      return(list(
        text = "",
        annotations = data.frame(
          text = character(),
          x_min = numeric(),
          y_min = numeric(),
          x_max = numeric(),
          y_max = numeric(),
          stringsAsFactors = FALSE
        ),
        image_width = 0,
        image_height = 0
      ))
    }

    if (verbose) message("[OCR] Text extracted (", nchar(text), " chars)")

    # Extract word-level bounding box annotations from textAnnotations
    text_annotations <- response$responses[[1]]$textAnnotations
    image_width <- 0
    image_height <- 0
    annotations_df <- data.frame(
      text = character(),
      x_min = numeric(),
      y_min = numeric(),
      x_max = numeric(),
      y_max = numeric(),
      stringsAsFactors = FALSE
    )

    if (!is.null(text_annotations) && length(text_annotations) > 0) {
      # First element is the full-page annotation - use its bounding box for image dimensions
      full_page <- text_annotations[[1]]
      if (!is.null(full_page$boundingPoly) && !is.null(full_page$boundingPoly$vertices)) {
        fp_vertices <- full_page$boundingPoly$vertices
        fp_xs <- sapply(fp_vertices, function(v) {
          if (!is.null(v$x)) v$x else 0
        })
        fp_ys <- sapply(fp_vertices, function(v) {
          if (!is.null(v$y)) v$y else 0
        })
        image_width <- max(fp_xs)
        image_height <- max(fp_ys)
      }

      if (verbose) message("[OCR] Image dimensions from annotation: ", image_width, "x", image_height)

      # Elements 2..N are individual word annotations
      if (length(text_annotations) > 1) {
        word_annotations <- text_annotations[2:length(text_annotations)]
        ann_texts <- character(length(word_annotations))
        ann_x_min <- numeric(length(word_annotations))
        ann_y_min <- numeric(length(word_annotations))
        ann_x_max <- numeric(length(word_annotations))
        ann_y_max <- numeric(length(word_annotations))

        for (w in seq_along(word_annotations)) {
          ann <- word_annotations[[w]]
          ann_texts[w] <- if (!is.null(ann$description)) ann$description else ""

          if (!is.null(ann$boundingPoly) && !is.null(ann$boundingPoly$vertices)) {
            vertices <- ann$boundingPoly$vertices
            xs <- sapply(vertices, function(v) {
              if (!is.null(v$x)) v$x else 0
            })
            ys <- sapply(vertices, function(v) {
              if (!is.null(v$y)) v$y else 0
            })
            ann_x_min[w] <- min(xs)
            ann_y_min[w] <- min(ys)
            ann_x_max[w] <- max(xs)
            ann_y_max[w] <- max(ys)
          }
          # else defaults to 0 from numeric() initialization
        }

        annotations_df <- data.frame(
          text = ann_texts,
          x_min = ann_x_min,
          y_min = ann_y_min,
          x_max = ann_x_max,
          y_max = ann_y_max,
          stringsAsFactors = FALSE
        )

        if (verbose) message("[OCR] Extracted ", nrow(annotations_df), " word annotations")
      }
    }

    return(list(
      text = text,
      annotations = annotations_df,
      image_width = image_width,
      image_height = image_height
    ))
  }, error = function(e) {
    warning(paste("OCR API error:", e$message))
    if (verbose) message("[OCR] EXCEPTION: ", e$message)
    return(NULL)
  })
}

#' Check if a string looks like status bar noise (time, battery, signal)
#'
#' Used during USERNAME detection phase to skip status bar lines.
#' Note: This does NOT filter numbers during the forward-scan phase (after finding usernames)
#' because the forward-scan is position-based and won't reach status bar lines.
#'
#' @param text String to check
#' @return TRUE if it looks like status bar noise
is_status_bar_noise <- function(text) {
 # Time patterns: 12:17, 9:45 AM, 14:30
  if (grepl("^\\d{1,2}:\\d{2}", text)) return(TRUE)

  # Battery percentages with % symbol
  if (grepl("^\\d{1,3}%$", text)) return(TRUE)

  # Signal indicators that OCR might pick up
  if (grepl("^[.oO]{2,5}$", text)) return(TRUE)  # Signal dots
  if (grepl("^LTE$|^5G$|^4G$|^WiFi$", text, ignore.case = TRUE)) return(TRUE)

  # Common status bar text
  if (grepl("^AM$|^PM$", text)) return(TRUE)

  FALSE
}

#' Check if a string looks like a store/business name
#'
#' @param text String to check
#' @return TRUE if it looks like a store name
is_store_name <- function(text) {
  # Common store name patterns
  store_keywords <- c("games", "cards", "hobby", "collectibles", "comics",
                      "gaming", "tcg", "shop", "store", "arena", "lounge",
                      "cafe", "bar", "grill", "pizza", "coffee")

  text_lower <- tolower(text)

  # Check for store keywords
  for (keyword in store_keywords) {
    if (grepl(keyword, text_lower)) return(TRUE)
  }

  # Multi-word names with "The" or ending in common suffixes
 if (grepl("^The\\s+", text, ignore.case = TRUE)) return(TRUE)
  if (grepl("'s$", text)) return(TRUE)  # "Tony's", "Joe's"

  FALSE
}

#' Check if a string looks like event/tournament metadata
#'
#' @param text String to check
#' @return TRUE if it looks like event metadata
is_event_metadata <- function(text) {
  # Bracketed date ranges: [Jan-Mar 2026]
 if (grepl("^\\[.*\\]", text)) return(TRUE)

  # Event type keywords
  if (grepl("tournament|event|championship|regional|locals|cup", text, ignore.case = TRUE)) return(TRUE)

  # Date patterns
  if (grepl("\\d{4}", text) && grepl("jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec", text, ignore.case = TRUE)) return(TRUE)

  FALSE
}

#' Estimate points for a placement in a Swiss tournament
#'
#' Used to autofill missing/zero points when OCR fails to extract them.
#' Swiss tournaments typically have predictable point distributions:
#' - Win = 3 points, Draw = 1 point, Loss = 0 points
#' - Top players cluster at high point totals
#' - Only bottom ~20-25% should legitimately have 0 points
#'
#' @param placement Player's final placement (1 = first)
#' @param player_count Total players in tournament
#' @param rounds Number of rounds played
#' @return Estimated points (multiple of 3)
estimate_points_for_placement <- function(placement, player_count, rounds) {
  max_points <- 3 * rounds

  if (player_count <= 1) return(max_points)

  # Calculate percentile (0 = 1st place, 1 = last place)
  percentile <- (placement - 1) / (player_count - 1)

  # In Swiss, point distribution follows a pattern where:
 # - Top ~12% are typically undefeated or 1 loss
  # - Middle clusters around 50% win rate
  # - Bottom 20-25% may have 0-1 wins
  #
  # Estimate wins using a curve that reflects typical Swiss distribution
  # The 0.6 exponent creates a distribution where more players have
  # higher point totals (realistic for Swiss where draws are rare)
  estimated_wins <- round(rounds * (1 - percentile^0.6))

  # Convert to points (3 per win), clamped to valid range
  estimated_points <- estimated_wins * 3
  max(0, min(max_points, estimated_points))
}

#' Check if a player's points should be autofilled
#'
#' Returns TRUE if the player has 0/NA points but shouldn't based on placement.
#' Players in the bottom ~25% of standings may legitimately have 0 points.
#'
#' @param placement Player's final placement
#' @param player_count Total players in tournament
#' @param points Current points value (may be 0 or NA)
#' @return TRUE if points should be autofilled
should_autofill_points <- function(placement, player_count, points) {
  # Only autofill if points is 0 or NA
 if (!is.na(points) && points > 0) return(FALSE)

  # Players in bottom 25% may legitimately have 0 points
  percentile <- placement / player_count
  if (percentile > 0.75) return(FALSE)

  # For small tournaments, be more conservative
  # (last 2 players in an 8-player tournament is 25%)
  if (player_count <= 8 && placement >= player_count - 1) return(FALSE)

  TRUE
}

#' Parse tournament standings from OCR text
#'
#' Extracts player data from Bandai TCG+ tournament rankings screenshot.
#' OCR typically returns each table cell as a separate line.
#'
#' @param ocr_text Raw text from gcv_detect_text()
#' @param total_rounds Total rounds in tournament (for calculating losses)
#' @param verbose Print debug messages
#' @return Data frame with columns: placement, username, member_number, points, wins, losses, ties
parse_tournament_standings <- function(ocr_text, total_rounds = 4, verbose = TRUE) {
  if (verbose) message("[PARSE] Starting to parse tournament standings...")

  if (is.null(ocr_text) || ocr_text == "") {
    if (verbose) message("[PARSE] No OCR text to parse")
    return(data.frame(
      placement = integer(),
      username = character(),
      member_number = character(),
      points = integer(),
      wins = integer(),
      losses = integer(),
      ties = integer()
    ))
  }

  if (verbose) message("[PARSE] OCR text length: ", nchar(ocr_text))

  lines <- strsplit(ocr_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[lines != ""]

  if (verbose) message("[PARSE] Found ", length(lines), " non-empty lines")

  # Print first few lines for debugging
  if (verbose && length(lines) > 0) {
    message("[PARSE] First 20 lines:")
    for (i in seq_len(min(20, length(lines)))) {
      message("[PARSE]   ", i, ": '", lines[i], "'")
    }
  }

  results <- list()

  # Header words and noise to skip
  headers <- c("ranking", "ranki", "user name", "username", "win", "omw", "gw",
               "points", "digimon", "card game", "home", "my events", "event search",
               "decks", "others", "ng", "privacy policy", "o o o", "store events",
               "match history", "results", "opponent", "round")

  # Find potential usernames: alphabetic text that's not a header or percentage
  # Usernames in Bandai TCG+ are typically alphanumeric, starting with letter
  username_indices <- c()
  for (i in seq_along(lines)) {
    line <- lines[i]
    line_lower <- tolower(line)

    # Skip if it's a header or noise
    if (line_lower %in% headers) next

    # Skip "Member Number" lines - these are NOT usernames!
    if (grepl("^Member\\s*Number", line, ignore.case = TRUE)) next

    # Skip if contains percentage
    if (grepl("%", line)) next

    # Skip if it's just numbers or time format
    if (grepl("^[\\d\\.:\\-]+$", line)) next

    # Skip very short lines (likely OCR artifacts) - but allow 3+ char usernames
    if (nchar(line) < 3) next

    # Skip common OCR noise patterns - but allow combined "10 Sinone" format
    # where a placement number precedes the username
    if (grepl("^[^A-Za-z0-9]", line)) next
    if (grepl("^\\d", line) && !grepl("^\\d{1,2}\\s+[A-Za-z]", line)) next
    if (grepl("^B⭑", line)) next  # App logo

    # NEW: Skip status bar noise (time, battery, signal)
    if (is_status_bar_noise(line)) {
      if (verbose) message("[PARSE] Skipping status bar noise: '", line, "'")
      next
    }

    # NEW: Skip store/business names
    if (is_store_name(line)) {
      if (verbose) message("[PARSE] Skipping store name: '", line, "'")
      next
    }

    # NEW: Skip event metadata
    if (is_event_metadata(line)) {
      if (verbose) message("[PARSE] Skipping event metadata: '", line, "'")
      next
    }

    # Check if it looks like a username (starts with letter, allows alphanumeric, underscore, space, apostrophe)
    if (grepl("^[A-Za-z][A-Za-z0-9_.' ]*$", line) && nchar(line) >= 3) {
      # Additional check: must have at least 3 letters total to avoid noise
      letter_count <- nchar(gsub("[^A-Za-z]", "", line))
      if (letter_count >= 3) {
        username_indices <- c(username_indices, i)
        if (verbose) message("[PARSE] Potential username at line ", i, ": '", line, "'")
      }
    } else {
      # Check for combined placement + username format: "10 Sinone", "13 Shaggy"
      # OCR sometimes puts the rank number on the same line as the username
      combined_match <- regmatches(line, regexec("^(\\d{1,2})\\s+([A-Za-z][A-Za-z0-9_. ]*)$", line))[[1]]
      if (length(combined_match) > 2) {
        potential_username <- combined_match[3]
        letter_count <- nchar(gsub("[^A-Za-z]", "", potential_username))
        if (letter_count >= 3) {
          username_indices <- c(username_indices, i)
          if (verbose) message("[PARSE] Potential combined placement+username at line ", i, ": '", line, "'")
        }
      }
    }
  }

  if (verbose) message("[PARSE] Found ", length(username_indices), " potential usernames")

  # Track expected placement (for sequential assignment)
  next_expected_placement <- 1

  # For each username, look FORWARD for member number and numbers for placement/points
  # Also look BACKWARD for placement number that might precede the username
  for (j in seq_along(username_indices)) {
    idx <- username_indices[j]
    raw_line <- lines[idx]

    # Check if this is a combined "placement username" format (e.g., "10 Sinone")
    combined_match <- regmatches(raw_line, regexec("^(\\d{1,2})\\s+([A-Za-z][A-Za-z0-9_. ]*)$", raw_line))[[1]]
    if (length(combined_match) > 2) {
      placement_from_combined <- as.integer(combined_match[2])
      username <- combined_match[3]
      if (verbose) message("[PARSE] Split combined line: placement=", placement_from_combined, ", username='", username, "'")
    } else {
      placement_from_combined <- NA
      username <- raw_line
    }

    # Search BACKWARD up to 2 lines for placement number
    # Only accept if it's immediately before username and looks like a ranking (1-32)
    placement_from_backward <- NA
    if (idx > 1) {
      prev_line <- lines[idx - 1]
      # Only accept standalone 1-2 digit numbers in valid placement range
      # Exclude numbers that look like percentages or other data (33+)
      if (grepl("^\\d{1,2}$", prev_line)) {
        val <- as.integer(prev_line)
        # More restrictive: only 1-32 and should be close to expected placement
        if (val >= 1 && val <= 32 && abs(val - next_expected_placement) <= 5) {
          placement_from_backward <- val
        }
      }
    }

    # Search forward up to 12 lines for member number
    # (increased from 8 to handle noise like headers between username and data)
    search_end <- min(length(lines), idx + 12)

    member_num <- NA
    placement <- NA
    points <- NA
    member_num_idx <- NA

    # Collect all numbers between username and member number
    numbers_before_member <- c()
    numbers_after_member <- c()

    for (k in (idx + 1):search_end) {
      line <- lines[k]

      # Check for member number - supports both 10-digit format and GUEST##### format
      # Standard format: Member Number: 0000123456
      # Guest format: Member Number: GUEST99999 (manually added players without Bandai TCG+ accounts)
      member_match <- regmatches(line, regexec("Member\\s*Number\\s*:?\\s*(\\d{10}|GUEST\\d{5})", line, ignore.case = TRUE))[[1]]
      if (length(member_match) > 1 && is.na(member_num)) {
        member_num <- member_match[2]
        member_num_idx <- k
        next  # Continue scanning for numbers AFTER member number
      }

      # Check for standalone member number (without label)
      # Supports: 10-digit numbers OR GUEST##### format
      if ((grepl("^\\d{10}$", line) || grepl("^GUEST\\d{5}$", line, ignore.case = TRUE)) && is.na(member_num)) {
        member_num <- line
        member_num_idx <- k
        next  # Continue scanning for numbers AFTER member number
      }

      # Stop if we hit another username (but not Member Number lines)
      if (k %in% username_indices && k != idx) break

      # Collect standalone numbers (potential placement or points)
      # Now handles large tournaments (64, 128+ players)
      if (grepl("^\\d{1,3}$", line)) {
        # Skip numbers with leading zeros (OCR artifacts like '00', '01', '001')
        # Exception: standalone '0' is valid (0 points)
        if (grepl("^0\\d", line)) {
          if (verbose) message("[PARSE] Skipping leading-zero number: '", line, "'")
          next
        }
        val <- as.integer(line)
        # Only filter obvious non-data: values over 200 (no tournament that large)
        if (val <= 200) {
          if (is.na(member_num)) {
            numbers_before_member <- c(numbers_before_member, val)
          } else {
            numbers_after_member <- c(numbers_after_member, val)
            # Only collect first 2 numbers after member (points and maybe OMW-related)
            if (length(numbers_after_member) >= 2) break
          }
        }
      }
    }

    # Combine numbers found (before takes precedence for placement, after for points)
    numbers_found <- numbers_before_member

    # Interpret the numbers found
    # OCR Pattern varies:
    #   Pattern A: username -> placement -> points -> percentages -> member number
    #   Pattern B: username -> member number -> points -> percentages
    # So we check numbers_before_member first, then numbers_after_member

    if (length(numbers_found) >= 2) {
      # Found multiple numbers before member number
      # First number might be placement (1-64 range), second might be points (0-15 range)
      potential_placement <- numbers_found[1]
      potential_points <- numbers_found[2]

      # Validate placement: should be 1-64 AND close to expected (within 5)
      # This filters out percentages like "50" or "83" that aren't placements
      if (potential_placement >= 1 && potential_placement <= 64 &&
          abs(potential_placement - next_expected_placement) <= 5) {
        placement <- potential_placement
        points <- potential_points
      } else if (potential_placement <= 15) {
        # First number looks like points, not placement (small value)
        points <- potential_placement
      } else {
        # First number is noise (e.g., percentage), use second as points
        points <- potential_points
      }
    } else if (length(numbers_found) == 1) {
      # Single number before member - is it placement or points?
      val <- numbers_found[1]
      # Heuristic: Points are typically 0-15 (5 rounds * 3 max)
      # If the value is in typical points range, prefer treating as points
      # Placements will be assigned sequentially anyway
      if (val <= 15) {
        # Likely points - common values: 0, 3, 6, 9, 12, 15
        points <- val
      } else if (val >= 1 && val <= 64 && abs(val - next_expected_placement) <= 2) {
        # Larger number close to expected placement - treat as placement
        placement <- val
      } else {
        # Default to points for small-ish values, otherwise ignore (noise)
        if (val <= 20) points <- val
      }
    }

    # If we didn't find points before member number, check after
    if (is.na(points) && length(numbers_after_member) > 0) {
      # First number after member number is likely points
      potential_points <- numbers_after_member[1]
      # Points should be 0-15 for typical tournament (up to 5 rounds * 3 points)
      if (potential_points <= 15) {
        points <- potential_points
        if (verbose) message("[PARSE] Found points AFTER member number: ", points)
      }
    }

    # If no placement found from forward scan, try backward scan result
    if (is.na(placement) && !is.na(placement_from_backward)) {
      placement <- placement_from_backward
      if (verbose) message("[PARSE] Found placement from backward scan: ", placement)
    }

    # If still no placement found, use expected placement
    if (is.na(placement)) {
      placement <- next_expected_placement
    }

    if (verbose) {
      message("[PARSE] Player ", j, ": username='", username, "', placement=", placement,
              ", points=", points, ", member=", member_num)
    }

    # Only add if we found a member number (confirms this is a real player row)
    if (!is.na(member_num)) {
      # Default points to 0 if not found
      if (is.na(points)) points <- 0

      # Validate points - should be 0-15 for typical tournament (up to 5 rounds * 3 points)
      if (points > 15) {
        if (verbose) message("[PARSE] Warning: points=", points, " seems high, might be misread")
      }

      # Calculate W-L-T from points
      wins <- points %/% 3
      remaining <- points %% 3
      ties <- remaining
      losses <- max(0, total_rounds - wins - ties)

      results[[length(results) + 1]] <- data.frame(
        placement = placement,
        username = username,
        member_number = member_num,
        points = points,
        wins = wins,
        losses = losses,
        ties = ties,
        stringsAsFactors = FALSE
      )

      # Update expected placement for next player
      next_expected_placement <- placement + 1
    }
  }

  if (verbose) message("[PARSE] Parsed ", length(results), " player results")

  if (length(results) == 0) {
    if (verbose) message("[PARSE] No results extracted - patterns may not match OCR output")
    return(data.frame(
      placement = integer(),
      username = character(),
      member_number = character(),
      points = integer(),
      wins = integer(),
      losses = integer(),
      ties = integer()
    ))
  }

  # Combine results into dataframe
  result_df <- do.call(rbind, results)
  player_count <- nrow(result_df)

  # Autofill missing/zero points for players who shouldn't have 0
  autofilled_count <- 0
  for (i in seq_len(player_count)) {
    if (should_autofill_points(result_df$placement[i], player_count, result_df$points[i])) {
      estimated <- estimate_points_for_placement(result_df$placement[i], player_count, total_rounds)
      if (verbose) {
        message("[PARSE] Autofill: ", result_df$username[i], " (place ", result_df$placement[i],
                ") points 0 -> ", estimated)
      }
      result_df$points[i] <- estimated
      # Recalculate W-L-T from new points
      result_df$wins[i] <- estimated %/% 3
      remaining <- estimated %% 3
      result_df$ties[i] <- remaining
      result_df$losses[i] <- max(0, total_rounds - result_df$wins[i] - result_df$ties[i])
      autofilled_count <- autofilled_count + 1
    }
  }

  if (autofilled_count > 0 && verbose) {
    message("[PARSE] Autofilled points for ", autofilled_count, " players")
  }

  result_df
}

#' Parse match history from OCR text
#'
#' Extracts round-by-round match data from Bandai TCG+ match history screenshot.
#' OCR format (each on separate lines):
#'   Opponent username
#'   Round number (1-digit)
#'   Results (X-X-X format)
#'   Points (0, 1, or 3)
#'   Member Number: XXXXXXXXXX
#'
#' @param ocr_text Raw text from gcv_detect_text()
#' @param verbose Print debug messages
#' @return Data frame with columns: round, opponent_username, opponent_member_number,
#'         games_won, games_lost, games_tied, match_points
parse_match_history <- function(ocr_text, verbose = TRUE) {
  if (verbose) message("[MATCH] Starting to parse match history...")

  if (is.null(ocr_text) || ocr_text == "") {
    if (verbose) message("[MATCH] No OCR text to parse")
    return(data.frame(
      round = integer(),
      opponent_username = character(),
      opponent_member_number = character(),
      games_won = integer(),
      games_lost = integer(),
      games_tied = integer(),
      match_points = integer()
    ))
  }

  if (verbose) message("[MATCH] OCR text length: ", nchar(ocr_text))

  lines <- strsplit(ocr_text, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[lines != ""]

  if (verbose) message("[MATCH] Found ", length(lines), " non-empty lines")

  # Print all lines for debugging
  if (verbose && length(lines) > 0) {
    message("[MATCH] All lines:")
    for (i in seq_len(length(lines))) {
      message("[MATCH]   ", i, ": '", lines[i], "'")
    }
  }

  results <- list()

  # Headers and noise to skip when looking for usernames
  headers <- c("round", "opponent", "results", "points", "ranking", "match history",
               "store events", "home", "my events", "event search", "decks", "others",
               "3: win, 1: draw, 0: lose", "digimon", "card game", "g", "user name",
               "username", "win", "omw", "gw", "privacy policy", "results points")

  # Strategy: Find potential usernames, then scan FORWARD for round, results, points, member number
  # This matches the OCR output order we observed

  username_indices <- c()
  for (i in seq_along(lines)) {
    line <- lines[i]
    line_lower <- tolower(line)

    # Skip headers
    if (line_lower %in% headers) next

    # Skip if contains special patterns
    if (grepl("Member\\s*Number", line, ignore.case = TRUE)) next
    if (grepl("^\\d{1,2}$", line)) next  # Pure numbers (round, points)
    if (grepl("^\\d+-\\d+-\\d+$", line)) next  # Results pattern
    if (grepl("%", line)) next
    if (grepl("\\[", line)) next  # Event names in brackets
    if (grepl("☐", line)) next  # Checkbox characters
    if (grepl("^B⭑", line)) next  # App logo
    if (nchar(line) < 3) next

    # Skip status bar noise (time, battery, signal)
    if (is_status_bar_noise(line)) {
      if (verbose) message("[MATCH] Skipping status bar noise: '", line, "'")
      next
    }

    # Skip store/business names
    if (is_store_name(line)) {
      if (verbose) message("[MATCH] Skipping store name: '", line, "'")
      next
    }

    # Skip event metadata
    if (is_event_metadata(line)) {
      if (verbose) message("[MATCH] Skipping event metadata: '", line, "'")
      next
    }

    # Check if it looks like a username (allows apostrophes for names like "Dragoon's Ghost")
    if (grepl("^[A-Za-z][A-Za-z0-9_.' ]*$", line)) {
      # Must have at least 3 letters
      letter_count <- nchar(gsub("[^A-Za-z]", "", line))
      if (letter_count >= 3) {
        username_indices <- c(username_indices, i)
        if (verbose) message("[MATCH] Potential opponent at line ", i, ": '", line, "'")
      }
    }
  }

  if (verbose) message("[MATCH] Found ", length(username_indices), " potential opponents")

  # For each username, scan forward for: round, results, points, member number
  # Note: OCR order varies - sometimes member number comes before results, sometimes after
  for (idx in username_indices) {
    opponent <- lines[idx]

    # Search forward up to 15 lines for match data
    # (increased from 10 to handle noise like headers between username and member number)
    search_end <- min(length(lines), idx + 15)

    round_num <- NA
    games_won <- NA
    games_lost <- NA
    games_tied <- NA
    match_points <- NA
    member_num <- NA

    prev_line <- ""
    for (j in (idx + 1):search_end) {
      check_line <- lines[j]

      # Stop if we hit another username (next opponent)
      if (j %in% username_indices) break

      # Check for round number (single digit 1-9)
      # Skip if previous line was "Points" or "Ranking" - those are header values, not round numbers
      # Also skip if we already have results - round comes BEFORE results, not after
      prev_lower <- tolower(prev_line)
      is_after_header <- prev_lower %in% c("points", "ranking", "results")
      if (grepl("^[1-9]$", check_line) && is.na(round_num) && !is_after_header && is.na(games_won)) {
        round_num <- as.integer(check_line)
        if (verbose) message("[MATCH]   Round: ", round_num)
        prev_line <- check_line
        next
      }

      # Check for results pattern (X-X-X)
      result_match <- regmatches(check_line, regexec("^(\\d)\\s*-\\s*(\\d)\\s*-\\s*(\\d)$", check_line))[[1]]
      if (length(result_match) > 1 && is.na(games_won)) {
        games_won <- as.integer(result_match[2])
        games_lost <- as.integer(result_match[3])
        games_tied <- as.integer(result_match[4])
        if (verbose) message("[MATCH]   Results: ", games_won, "-", games_lost, "-", games_tied)
        prev_line <- check_line
        next
      }

      # Check for points (0, 1, or 3) - must come after results
      if (grepl("^[013]$", check_line) && !is.na(games_won) && is.na(match_points)) {
        match_points <- as.integer(check_line)
        if (verbose) message("[MATCH]   Points: ", match_points)
        prev_line <- check_line
        next
      }

      # Check for member number (may have results on same line)
      # Accept 8-10 digit member numbers (OCR sometimes truncates) OR GUEST##### format
      # Pattern: "Member Number: 00000091 2-1-0 3" (member + results + points on same line)
      # Guest format: "Member Number: GUEST99999" (manually added players)
      member_match <- regmatches(check_line, regexec("Member\\s*Number\\s*:?\\s*(\\d{8,10}|GUEST\\d{5})", check_line, ignore.case = TRUE))[[1]]
      if (length(member_match) > 1 && is.na(member_num)) {
        member_num <- member_match[2]
        if (verbose) message("[MATCH]   Member: ", member_num)
        prev_line <- check_line

        # Check if there's more on the same line (results and/or points)
        # Remove the member number part to get the remainder
        rest_of_line <- sub("Member\\s*Number\\s*:?\\s*(\\d{8,10}|GUEST\\d{5})\\s*", "", check_line, ignore.case = TRUE)
        if (nchar(rest_of_line) > 0) {
          if (verbose) message("[MATCH]   Same line remainder: '", rest_of_line, "'")

          # Try to extract results (X-X-X) from remainder
          inline_result <- regmatches(rest_of_line, regexec("(\\d)\\s*-\\s*(\\d)\\s*-\\s*(\\d)", rest_of_line))[[1]]
          if (length(inline_result) > 1 && is.na(games_won)) {
            games_won <- as.integer(inline_result[2])
            games_lost <- as.integer(inline_result[3])
            games_tied <- as.integer(inline_result[4])
            if (verbose) message("[MATCH]   Inline results: ", games_won, "-", games_lost, "-", games_tied)
          }

          # Try to extract points (0, 1, or 3) from remainder - look for standalone digit
          inline_points <- regmatches(rest_of_line, regexec("\\s([013])\\s*$", rest_of_line))[[1]]
          if (length(inline_points) > 1 && is.na(match_points)) {
            match_points <- as.integer(inline_points[2])
            if (verbose) message("[MATCH]   Inline points: ", match_points)
          }
        }

        prev_line <- check_line
        next  # Continue scanning - more data might come after
      }

      prev_line <- check_line
    }

    # Only add if we found a member number (confirms this is a real match row)
    if (!is.na(member_num)) {
      results[[length(results) + 1]] <- data.frame(
        round = if (is.na(round_num)) length(results) + 1 else round_num,
        opponent_username = opponent,
        opponent_member_number = member_num,
        games_won = if (is.na(games_won)) 0 else games_won,
        games_lost = if (is.na(games_lost)) 0 else games_lost,
        games_tied = if (is.na(games_tied)) 0 else games_tied,
        match_points = if (is.na(match_points)) 0 else match_points,
        stringsAsFactors = FALSE
      )
      if (verbose) message("[MATCH] Added match #", length(results), ": ", opponent, " (Round ", round_num, ")")
    }
  }

  if (verbose) message("[MATCH] Parsed ", length(results), " match results")

  if (length(results) == 0) {
    if (verbose) message("[MATCH] No results extracted - patterns may not match OCR output")
    return(data.frame(
      round = integer(),
      opponent_username = character(),
      opponent_member_number = character(),
      games_won = integer(),
      games_lost = integer(),
      games_tied = integer(),
      match_points = integer()
    ))
  }

  # Sort by round number
  result_df <- do.call(rbind, results)
  result_df <- result_df[order(result_df$round), ]
  rownames(result_df) <- NULL

  result_df
}
