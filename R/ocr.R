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

#' Parse tournament standings using layout-aware bounding box analysis
#'
#' Uses Google Cloud Vision bounding box coordinates to extract structured
#' player data from Bandai TCG+ standings screenshots. The Bandai TCG+ app
#' has a consistent column layout:
#'   - Ranking: 0-15% of image width
#'   - Username + Member Number: 15-60%
#'   - Win Points: 60-78%
#'   - OMW%: 78%+ (ignored)
#'
#' @param annotations Data frame with columns: text, x_min, y_min, x_max, y_max
#' @param image_width Image width in pixels (for normalization)
#' @param image_height Image height in pixels (for normalization)
#' @param total_rounds Total rounds in tournament (for W-L-T calculation)
#' @param verbose Print debug messages
#' @return Data frame with columns: placement, username, member_number, points, wins, losses, ties
parse_standings_layout <- function(annotations, image_width, image_height,
                                    total_rounds = 4, verbose = TRUE) {

  # --- Empty result template ---
  empty_result <- data.frame(
    placement = integer(),
    username = character(),
    member_number = character(),
    points = integer(),
    wins = integer(),
    losses = integer(),
    ties = integer(),
    stringsAsFactors = FALSE
  )

  if (verbose) message("[LAYOUT] Starting layout-aware parsing...")

  # Validate inputs

  if (is.null(annotations) || nrow(annotations) == 0) {
    if (verbose) message("[LAYOUT] No annotations to parse")
    return(empty_result)
  }

  if (image_width <= 0 || image_height <= 0) {
    if (verbose) message("[LAYOUT] Invalid image dimensions: ", image_width, "x", image_height)
    return(empty_result)
  }

  if (verbose) message("[LAYOUT] ", nrow(annotations), " annotations, image: ",
                        image_width, "x", image_height)

  # --- Step 1: Normalize coordinates to percentages ---
  ann <- annotations
  ann$x_center_pct <- ((ann$x_min + ann$x_max) / 2) / image_width * 100
  ann$y_center_pct <- ((ann$y_min + ann$y_max) / 2) / image_height * 100
  ann$y_min_pct <- ann$y_min / image_height * 100
  ann$y_max_pct <- ann$y_max / image_height * 100
  ann$x_min_pct <- ann$x_min / image_width * 100
  ann$x_max_pct <- ann$x_max / image_width * 100

  if (verbose) {
    message("[LAYOUT] Sample annotations (first 10):")
    for (i in seq_len(min(10, nrow(ann)))) {
      message("[LAYOUT]   '", ann$text[i], "' x_center=", round(ann$x_center_pct[i], 1),
              "% y_center=", round(ann$y_center_pct[i], 1), "%")
    }
  }

  # --- Step 2: Filter top/bottom noise (status bar, nav bar) ---
  n_before <- nrow(ann)
  ann <- ann[ann$y_center_pct > 7 & ann$y_center_pct < 93, ]
  if (verbose) message("[LAYOUT] Filtered top/bottom bars: ", n_before, " -> ", nrow(ann), " annotations")

  if (nrow(ann) == 0) {
    if (verbose) message("[LAYOUT] No annotations left after bar filtering")
    return(empty_result)
  }

  # --- Step 3: Detect header row and column boundaries ---
  header_keywords <- c("ranking", "user", "name", "win", "points", "omw", "gw")

  header_rows <- which(tolower(ann$text) %in% header_keywords)
  ranking_max <- 15
  username_min <- 15
  username_max <- 60
  points_min <- 60
  points_max <- 78

  if (length(header_rows) >= 2) {
    # Find the Y-center of header row (median of header keyword Y-positions)
    header_y_centers <- ann$y_center_pct[header_rows]
    header_y <- median(header_y_centers)

    if (verbose) message("[LAYOUT] Header row detected at y=", round(header_y, 1), "%")

    # Use header X-positions to refine column boundaries
    for (h in header_rows) {
      kw <- tolower(ann$text[h])
      x_center <- ann$x_center_pct[h]
      x_min_h <- ann$x_min_pct[h]
      x_max_h <- ann$x_max_pct[h]

      if (kw == "ranking") {
        ranking_max <- x_max_h + 2
        if (verbose) message("[LAYOUT]   'ranking' at x=", round(x_center, 1),
                              "%, ranking_max=", round(ranking_max, 1), "%")
      } else if (kw %in% c("user", "name")) {
        username_min <- min(username_min, x_min_h - 2)
        if (verbose) message("[LAYOUT]   '", kw, "' at x=", round(x_center, 1),
                              "%, username_min=", round(username_min, 1), "%")
      } else if (kw == "win" || kw == "points") {
        # "Win Points" header marks the points column
        if (kw == "win") {
          points_min <- x_min_h - 2
        }
        if (kw == "points") {
          points_max <- x_max_h + 2
        }
        if (verbose) message("[LAYOUT]   '", kw, "' at x=", round(x_center, 1),
                              "%, points_min=", round(points_min, 1),
                              "%, points_max=", round(points_max, 1), "%")
      } else if (kw == "omw" || kw == "gw") {
        # OMW/GW columns mark the end of points column
        points_max <- min(points_max, x_min_h - 1)
        if (verbose) message("[LAYOUT]   '", kw, "' at x=", round(x_center, 1),
                              "%, adjusted points_max=", round(points_max, 1), "%")
      }
    }

    # Adjust username_max to be just before points_min
    username_max <- points_min

    # Remove header row annotations (within 2% of header Y)
    ann <- ann[abs(ann$y_center_pct - header_y) > 2, ]
    if (verbose) message("[LAYOUT] Removed header row, ", nrow(ann), " annotations remain")
  } else {
    if (verbose) message("[LAYOUT] No header row found (scrolled screenshot?), using defaults")
  }

  if (verbose) {
    message("[LAYOUT] Column boundaries: ranking=[0-", round(ranking_max, 1),
            "%], username=[", round(username_min, 1), "-", round(username_max, 1),
            "%], points=[", round(points_min, 1), "-", round(points_max, 1), "%]")
  }

  if (nrow(ann) == 0) {
    if (verbose) message("[LAYOUT] No annotations left after header removal")
    return(empty_result)
  }

  # --- Step 4: Filter known noise text ---
  noise_patterns <- c(
    "privacy", "policy", "digimon", "card", "game", "home",
    "my", "events", "event", "search", "decks", "others",
    "store", "match", "history", "results",
    "bandai", "obandai", "akiyoshi", "animation", "reserved", "rights",
    "all", "©", "toei",
    # App title and page headers
    "ranking", "cardgame", "ranki", "ng",
    # OCR misreads of CARD/GAME
    "eard", "bamb",
    # Navigation elements
    "+",
    # Copyright/footer fragments
    "co", "ltd", "hongo", "bunkyo-ku", "bunkyo",
    "tokyo", "inc"
  )

  # Also filter the B-star logo variants and copyright-like text
  is_noise <- tolower(ann$text) %in% noise_patterns |
    grepl("^B[\\x{2B50}\\x{2736}\\x{2606}\\x{2605}\\x{2731}⭑✶★☆X]+$", ann$text, perl = TRUE) |
    grepl("^BXXX", ann$text) |
    grepl("^©", ann$text) |
    grepl("^\\.$", ann$text) |  # Standalone periods
    grepl("^[^A-Za-z0-9]$", ann$text)  # Single non-alphanumeric characters (%, <, (, etc.)

  n_before <- nrow(ann)
  ann <- ann[!is_noise, ]
  if (verbose) message("[LAYOUT] Filtered noise text: ", n_before, " -> ", nrow(ann), " annotations")

  if (nrow(ann) == 0) {
    if (verbose) message("[LAYOUT] No annotations left after noise filtering")
    return(empty_result)
  }

  # --- Step 5: Cluster into rows by Y-center ---
  ann <- ann[order(ann$y_center_pct), ]
  row_ids <- integer(nrow(ann))
  current_row <- 1
  row_ids[1] <- 1

  for (i in 2:nrow(ann)) {
    # Gap > 1.5% of image height = new row
    if (ann$y_center_pct[i] - ann$y_center_pct[i - 1] > 1.5) {
      current_row <- current_row + 1
    }
    row_ids[i] <- current_row
  }

  ann$row_id <- row_ids
  n_rows <- max(row_ids)

  if (verbose) message("[LAYOUT] Clustered into ", n_rows, " visual rows")

  # --- Step 6 & 7: For each row, assign text to columns ---
  results <- list()

  for (r in seq_len(n_rows)) {
    row_ann <- ann[ann$row_id == r, ]
    if (nrow(row_ann) == 0) next

    row_y_center <- mean(row_ann$y_center_pct)

    # Classify each annotation by column
    ranking_texts <- row_ann[row_ann$x_center_pct <= ranking_max, , drop = FALSE]
    username_texts <- row_ann[row_ann$x_center_pct > username_min &
                               row_ann$x_center_pct <= username_max, , drop = FALSE]
    points_texts <- row_ann[row_ann$x_center_pct > points_min &
                             row_ann$x_center_pct <= points_max, , drop = FALSE]

    if (verbose && nrow(row_ann) > 0) {
      all_text <- paste(row_ann$text, collapse = " | ")
      message("[LAYOUT] Row ", r, " (y=", round(row_y_center, 1), "%): ", all_text)
    }

    # --- Extract ranking ---
    ranking <- NA_integer_
    if (nrow(ranking_texts) > 0) {
      for (rt in seq_len(nrow(ranking_texts))) {
        cleaned <- gsub("[^0-9]", "", ranking_texts$text[rt])
        if (nchar(cleaned) > 0) {
          val <- suppressWarnings(as.integer(cleaned))
          if (!is.na(val) && val >= 1 && val <= 128) {
            ranking <- val
            break
          }
        }
      }
    }

    # --- Extract username and member number from username column ---
    username <- NA_character_
    member_number <- NA_character_

    if (nrow(username_texts) > 0) {
      # Sort by Y position (username is above member number)
      username_texts <- username_texts[order(username_texts$y_center_pct), ]

      # Separate texts into visual sub-lines within this row
      # Texts within 1% Y of each other are on the same visual line
      sub_lines <- list()
      current_sub <- list(username_texts[1, ])
      if (nrow(username_texts) > 1) {
        for (ut in 2:nrow(username_texts)) {
          if (abs(username_texts$y_center_pct[ut] -
                  username_texts$y_center_pct[ut - 1]) <= 1.0) {
            # Same visual line
            current_sub[[length(current_sub) + 1]] <- username_texts[ut, ]
          } else {
            # New visual line
            sub_lines[[length(sub_lines) + 1]] <- do.call(rbind, current_sub)
            current_sub <- list(username_texts[ut, ])
          }
        }
      }
      sub_lines[[length(sub_lines) + 1]] <- do.call(rbind, current_sub)

      # Process each visual sub-line
      for (sl in seq_along(sub_lines)) {
        sub_line <- sub_lines[[sl]]
        # Sort left to right within the sub-line
        sub_line <- sub_line[order(sub_line$x_center_pct), ]
        line_text <- paste(sub_line$text, collapse = " ")

        # Check for member number patterns
        # 10-digit number
        if (grepl("^\\d{10}$", line_text) || grepl("\\d{10}", line_text)) {
          mem_match <- regmatches(line_text, regexec("(\\d{10})", line_text))[[1]]
          if (length(mem_match) > 1) {
            member_number <- mem_match[2]
            if (verbose) message("[LAYOUT]   Member number (10-digit): ", member_number)
            next
          }
        }

        # GUEST##### pattern
        if (grepl("GUEST\\d{5}", line_text, ignore.case = TRUE)) {
          mem_match <- regmatches(line_text, regexec("(GUEST\\d{5})", line_text, ignore.case = TRUE))[[1]]
          if (length(mem_match) > 1) {
            member_number <- mem_match[2]
            if (verbose) message("[LAYOUT]   Member number (GUEST): ", member_number)
            next
          }
        }

        # "Member Number XXXXXXXXXX" or "Member Number" keyword
        if (grepl("^Member$", line_text, ignore.case = TRUE) ||
            grepl("^Number$", line_text, ignore.case = TRUE) ||
            grepl("^Member\\s+Number", line_text, ignore.case = TRUE)) {
          # Check if the full member number is in this text
          full_match <- regmatches(line_text,
                                    regexec("Member\\s+Number\\s*:?\\s*(\\d{10}|GUEST\\d{5})",
                                            line_text, ignore.case = TRUE))[[1]]
          if (length(full_match) > 1) {
            member_number <- full_match[2]
            if (verbose) message("[LAYOUT]   Member number (labeled): ", member_number)
          }
          next  # Skip "Member" and "Number" keywords as username candidates
        }

        # Skip percentages (OMW%, GW%)
        if (grepl("^\\d{1,3}%$", line_text)) next
        if (grepl("%", line_text)) next

        # Skip individual words that are just "Member" or "Number"
        individual_texts <- sub_line$text
        remaining_parts <- individual_texts[!grepl("^(Member|Number)$", individual_texts, ignore.case = TRUE)]
        if (length(remaining_parts) == 0) next

        # Check each annotation in this sub-line for member numbers individually
        has_member_num <- FALSE
        for (at in seq_len(nrow(sub_line))) {
          ann_text <- sub_line$text[at]
          if (grepl("^\\d{10}$", ann_text)) {
            member_number <- ann_text
            has_member_num <- TRUE
            if (verbose) message("[LAYOUT]   Member number (individual): ", member_number)
          } else if (grepl("^GUEST\\d{5}$", ann_text, ignore.case = TRUE)) {
            member_number <- ann_text
            has_member_num <- TRUE
            if (verbose) message("[LAYOUT]   Member number (GUEST individual): ", member_number)
          }
        }
        if (has_member_num) next

        # This sub-line is a username candidate
        # Build username from remaining parts (excluding member-number annotations)
        username_parts <- c()
        for (at in seq_len(nrow(sub_line))) {
          ann_text <- sub_line$text[at]
          # Skip "Member", "Number" keywords
          if (grepl("^(Member|Number)$", ann_text, ignore.case = TRUE)) next
          # Skip if it's a pure small number that looks like noise
          # BUT keep numbers in the username column (they're usernames like "1596")
          username_parts <- c(username_parts, ann_text)
        }

        if (length(username_parts) > 0 && is.na(username)) {
          username <- paste(username_parts, collapse = " ")
          if (verbose) message("[LAYOUT]   Username: '", username, "'")
        }
      }
    }

    # --- Step 8: Handle member numbers that span the row ---
    # If member number not found in username column, scan all text in the row
    if (is.na(member_number)) {
      for (ri in seq_len(nrow(row_ann))) {
        txt <- row_ann$text[ri]
        if (grepl("^\\d{10}$", txt)) {
          member_number <- txt
          if (verbose) message("[LAYOUT]   Member number (row scan): ", member_number)
          break
        } else if (grepl("^GUEST\\d{5}$", txt, ignore.case = TRUE)) {
          member_number <- txt
          if (verbose) message("[LAYOUT]   Member number (row scan GUEST): ", member_number)
          break
        }
      }
    }

    # --- Extract points ---
    points <- NA_integer_
    max_possible_points <- total_rounds * 3L
    if (nrow(points_texts) > 0) {
      for (pt in seq_len(nrow(points_texts))) {
        raw_text <- points_texts$text[pt]
        # Skip decimal values (OMW% values like "55.5" that leaked into points column)
        if (grepl("\\.", raw_text)) next
        cleaned <- gsub("[^0-9]", "", raw_text)
        if (nchar(cleaned) > 0) {
          val <- suppressWarnings(as.integer(cleaned))
          if (!is.na(val) && val >= 0) {
            # If value exceeds max possible points, try truncating trailing digits
            # (GCV sometimes merges "6" with adjacent "0" from OMW% "60.3%")
            if (val > max_possible_points && nchar(cleaned) > 1) {
              truncated <- suppressWarnings(as.integer(substr(cleaned, 1, nchar(cleaned) - 1)))
              if (!is.na(truncated) && truncated >= 0 && truncated <= max_possible_points) {
                if (verbose) message("[LAYOUT]   Points truncated: ", val, " -> ", truncated)
                val <- truncated
              }
            }
            if (val >= 0 && val <= max_possible_points) {
              points <- val
              if (verbose) message("[LAYOUT]   Points: ", points)
              break
            }
          }
        }
      }
    }

    # --- Step 9: Skip incomplete rows ---
    has_identity <- !is.na(ranking) || !is.na(username)
    has_player_info <- !is.na(member_number) || !is.na(username)

    if (!has_identity || !has_player_info) {
      if (verbose) message("[LAYOUT]   Skipping incomplete row ", r,
                            ": ranking=", ranking, " username=", username,
                            " member=", member_number)
      next
    }

    # Default points to 0 if not found
    if (is.na(points)) points <- 0L

    results[[length(results) + 1]] <- list(
      placement = ranking,
      username = username,
      member_number = member_number,
      points = points,
      y_position = row_y_center
    )

    if (verbose) {
      message("[LAYOUT]   -> Player: rank=", ranking, " user='", username,
              "' member=", member_number, " pts=", points)
    }
  }

  if (verbose) message("[LAYOUT] Extracted ", length(results), " player rows")

  if (length(results) == 0) {
    if (verbose) message("[LAYOUT] No valid player rows found")
    return(empty_result)
  }

  # --- Step 9a: Filter suspicious noise rows ---
  # Remove rows that look like garbled text: 3+ words in username AND no member number
  n_before_noise <- length(results)
  results <- Filter(function(x) {
    if (is.na(x$username)) return(TRUE)
    word_count <- length(strsplit(x$username, "\\s+")[[1]])
    # Keep if has member number, or username is 1-2 words
    !is.na(x$member_number) || word_count <= 2
  }, results)

  if (length(results) < n_before_noise && verbose) {
    message("[LAYOUT] Removed ", n_before_noise - length(results), " suspicious noise rows")
  }

  # --- Build result data frame ---
  result_df <- data.frame(
    placement = sapply(results, function(x) if (is.na(x$placement)) NA_integer_ else as.integer(x$placement)),
    username = sapply(results, function(x) if (is.na(x$username)) NA_character_ else as.character(x$username)),
    member_number = sapply(results, function(x) if (is.na(x$member_number)) NA_character_ else as.character(x$member_number)),
    points = sapply(results, function(x) if (is.na(x$points)) 0L else as.integer(x$points)),
    y_position = sapply(results, function(x) x$y_position),
    stringsAsFactors = FALSE
  )

  # --- Step 9b: Infer missing top ranks (medal icons) ---
  # GCV often fails to detect numbers inside gold/silver/bronze medal icons
  # for ranks 1-3. Infer these from Y-position ordering.
  result_df <- result_df[order(result_df$y_position), ]

  if (any(is.na(result_df$placement))) {
    current_rank <- 1L
    inferred_count <- 0L

    for (i in seq_len(nrow(result_df))) {
      if (is.na(result_df$placement[i])) {
        result_df$placement[i] <- current_rank
        inferred_count <- inferred_count + 1L
        if (verbose) {
          message("[LAYOUT] Inferred rank ", current_rank, " for '",
                  result_df$username[i], "' (y=", round(result_df$y_position[i], 1), "%)")
        }
        current_rank <- current_rank + 1L
      } else {
        # Jump to the next rank after this detected one
        current_rank <- result_df$placement[i] + 1L
      }
    }

    if (inferred_count > 0 && verbose) {
      message("[LAYOUT] Inferred ", inferred_count, " missing placements from Y-position")
    }
  }

  # Remove temporary y_position column
  result_df$y_position <- NULL

  player_count <- nrow(result_df)

  # --- Step 10: Autofill points ---
  autofilled_count <- 0
  for (i in seq_len(player_count)) {
    pl <- result_df$placement[i]
    pts <- result_df$points[i]

    if (!is.na(pl) && should_autofill_points(pl, player_count, pts)) {
      estimated <- estimate_points_for_placement(pl, player_count, total_rounds)
      if (verbose) {
        message("[LAYOUT] Autofill: ", result_df$username[i], " (place ", pl,
                ") points ", pts, " -> ", estimated)
      }
      result_df$points[i] <- estimated
      autofilled_count <- autofilled_count + 1
    }
  }

  if (autofilled_count > 0 && verbose) {
    message("[LAYOUT] Autofilled points for ", autofilled_count, " players")
  }

  # --- Step 11: Calculate W-L-T from points ---
  result_df$wins <- result_df$points %/% 3L
  result_df$ties <- result_df$points %% 3L
  result_df$losses <- pmax(0L, as.integer(total_rounds) - result_df$wins - result_df$ties)

  # --- Step 12: Sort by ranking ---
  # Put rows with NA ranking at the end
  result_df <- result_df[order(result_df$placement, na.last = TRUE), ]
  rownames(result_df) <- NULL

  if (verbose) {
    message("[LAYOUT] Final result: ", nrow(result_df), " players")
    for (i in seq_len(nrow(result_df))) {
      message("[LAYOUT]   #", result_df$placement[i], " ", result_df$username[i],
              " (", result_df$member_number[i], ") ", result_df$points[i], "pts ",
              result_df$wins[i], "-", result_df$losses[i], "-", result_df$ties[i])
    }
  }

  result_df
}

#' Parse tournament standings with layout-first fallback strategy
#'
#' Tries the layout-aware parser first (uses bounding boxes for accuracy).
#' Falls back to the text-based parser if layout parsing fails.
#'
#' @param ocr_result Result from gcv_detect_text() — either a list or plain text
#' @param total_rounds Total rounds in tournament
#' @param verbose Print debug messages
#' @return Data frame with columns: placement, username, member_number, points, wins, losses, ties
parse_standings <- function(ocr_result, total_rounds = 4, verbose = TRUE) {
  # Handle both new list format and legacy plain text
  if (is.list(ocr_result)) {
    text <- ocr_result$text
    annotations <- ocr_result$annotations
    image_width <- ocr_result$image_width
    image_height <- ocr_result$image_height
  } else {
    text <- ocr_result
    annotations <- NULL
    image_width <- 0
    image_height <- 0
  }

  # Try layout-aware parser first
  if (!is.null(annotations) && nrow(annotations) > 0 && image_width > 0 && image_height > 0) {
    if (verbose) message("[OCR] Trying layout-aware parser...")

    layout_result <- tryCatch({
      parse_standings_layout(annotations, image_width, image_height,
                              total_rounds = total_rounds, verbose = verbose)
    }, error = function(e) {
      if (verbose) message("[OCR] Layout parser error: ", e$message)
      data.frame()
    })

    # Validate: need at least 1 player with ranking, username, and member number
    if (nrow(layout_result) > 0) {
      has_ranking <- any(!is.na(layout_result$placement) & layout_result$placement > 0)
      has_username <- any(!is.na(layout_result$username) & layout_result$username != "")
      has_member <- any(!is.na(layout_result$member_number) & layout_result$member_number != "")

      if (has_ranking && has_username && has_member) {
        if (verbose) message("[OCR] Using layout parser (", nrow(layout_result), " players found)")
        return(layout_result)
      } else {
        if (verbose) message("[OCR] Layout parser returned incomplete data, falling back to text parser")
      }
    } else {
      if (verbose) message("[OCR] Layout parser returned 0 players, falling back to text parser")
    }
  }

  # Fallback to text-based parser
  if (verbose) message("[OCR] Using text-based parser")
  parse_tournament_standings(text, total_rounds = total_rounds, verbose = verbose)
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

    # Check if it looks like a username (allows accented chars, apostrophes, pronouns like "She/Her")
    if (grepl("^\\p{L}[\\p{L}0-9_.' ()/-]*$", line, perl = TRUE) && nchar(line) >= 3) {
      # Additional check: must have at least 3 letters total (Unicode-aware)
      letter_count <- nchar(gsub("[^\\p{L}]", "", line, perl = TRUE))
      if (letter_count >= 3) {
        username_indices <- c(username_indices, i)
        if (verbose) message("[PARSE] Potential username at line ", i, ": '", line, "'")
      }
    } else {
      # Check for combined placement + username format: "10 Sinone", "13 Shaggy"
      # OCR sometimes puts the rank number on the same line as the username
      combined_match <- regmatches(line, regexec("^(\\d{1,2})\\s+(.+)$", line, perl = TRUE))[[1]]
      if (length(combined_match) > 2) {
        potential_username <- combined_match[3]
        if (!grepl("^\\p{L}", potential_username, perl = TRUE)) next
        letter_count <- nchar(gsub("[^\\p{L}]", "", potential_username, perl = TRUE))
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
    combined_match <- regmatches(raw_line, regexec("^(\\d{1,2})\\s+(\\p{L}.*)$", raw_line, perl = TRUE))[[1]]
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
parse_match_history_text <- function(ocr_text, verbose = TRUE) {
  if (verbose) message("[MATCH] Starting to parse match history (text)...")

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
               "username", "win", "omw", "gw", "privacy policy", "results points",
               "aigimon", "cardgame", "tcg", "tcg+")

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

    # Check if it looks like a username (allows accented chars, apostrophes, pronouns like "She/Her")
    if (grepl("^\\p{L}[\\p{L}0-9_.' ()/-]*$", line, perl = TRUE)) {
      # Must have at least 3 letters (Unicode-aware)
      letter_count <- nchar(gsub("[^\\p{L}]", "", line, perl = TRUE))
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

#' Layout-aware match history parser using GCV bounding boxes
#'
#' Parses Bandai TCG+ match history screenshots using word-level bounding box
#' coordinates for column alignment. The match history screen has 4 columns:
#' Round | Opponent (name + member#) | Results (X-X-X) | Points (0/1/3)
#'
#' @param annotations Data frame with columns: text, x_min, y_min, x_max, y_max
#' @param image_width Image width in pixels
#' @param image_height Image height in pixels
#' @param verbose Print debug messages
#' @return List with matches (data frame) and metadata (list)
parse_match_history_layout <- function(annotations, image_width, image_height, verbose = TRUE) {

  empty_result <- data.frame(
    round = integer(),
    opponent_username = character(),
    opponent_member_number = character(),
    games_won = integer(),
    games_lost = integer(),
    games_tied = integer(),
    match_points = integer(),
    match_type = character(),
    stringsAsFactors = FALSE
  )

  if (verbose) message("[MATCH-LAYOUT] Starting layout-aware match history parsing...")

  if (is.null(annotations) || nrow(annotations) == 0) {
    if (verbose) message("[MATCH-LAYOUT] No annotations to parse")
    return(empty_result)
  }

  if (image_width <= 0 || image_height <= 0) {
    if (verbose) message("[MATCH-LAYOUT] Invalid image dimensions: ", image_width, "x", image_height)
    return(empty_result)
  }

  if (verbose) message("[MATCH-LAYOUT] ", nrow(annotations), " annotations, image: ",
                        image_width, "x", image_height)

  # --- Step 1: Normalize coordinates to percentages ---
  ann <- annotations
  ann$x_center_pct <- ((ann$x_min + ann$x_max) / 2) / image_width * 100
  ann$y_center_pct <- ((ann$y_min + ann$y_max) / 2) / image_height * 100
  ann$y_min_pct <- ann$y_min / image_height * 100
  ann$y_max_pct <- ann$y_max / image_height * 100
  ann$x_min_pct <- ann$x_min / image_width * 100
  ann$x_max_pct <- ann$x_max / image_width * 100

  if (verbose) {
    message("[MATCH-LAYOUT] Sample annotations (first 10):")
    for (i in seq_len(min(10, nrow(ann)))) {
      message("[MATCH-LAYOUT]   '", ann$text[i], "' x_center=", round(ann$x_center_pct[i], 1),
              "% y_center=", round(ann$y_center_pct[i], 1), "%")
    }
  }

  # --- Step 2: Filter status bar (y < 5%) and nav bar (y > 92%) ---
  n_before <- nrow(ann)
  ann <- ann[ann$y_center_pct >= 5 & ann$y_center_pct <= 92, ]
  if (verbose) message("[MATCH-LAYOUT] Filtered top/bottom bars: ", n_before, " -> ", nrow(ann))

  if (nrow(ann) == 0) return(empty_result)

  # --- Step 3: Extract metadata from above table (best-effort) ---
  metadata <- list(ranking = NA, total_points = NA, store_name = NA, event_name = NA)

  # --- Step 4: Detect header row from keywords ---
  header_keywords <- c("round", "opponent", "results", "points")
  header_ann <- ann[tolower(ann$text) %in% header_keywords, ]

  # Column boundary defaults (percentage of image width)
  round_max <- 12       # Round column: 0-12%
  opponent_min <- 12    # Opponent: 12-58%
  opponent_max <- 58
  results_min <- 58     # Results: 58-80%
  results_max <- 80
  points_min <- 80      # Points: 80-100%

  header_y <- NA

  if (nrow(header_ann) >= 2) {
    # Header row Y is the median Y of header keywords
    header_y <- median(header_ann$y_center_pct)
    if (verbose) message("[MATCH-LAYOUT] Header row detected at y=", round(header_y, 1), "%")

    # Refine column boundaries from header X-positions
    for (h in seq_len(nrow(header_ann))) {
      kw <- tolower(header_ann$text[h])
      x_center <- header_ann$x_center_pct[h]
      x_min_h <- header_ann$x_min_pct[h]
      x_max_h <- header_ann$x_max_pct[h]

      if (kw == "round") {
        round_max <- x_max_h + 3
        opponent_min <- x_max_h + 1
        if (verbose) message("[MATCH-LAYOUT]   'round' at x=", round(x_center, 1),
                              "%, round_max=", round(round_max, 1), "%")
      } else if (kw == "opponent") {
        opponent_min <- x_min_h - 2
        if (verbose) message("[MATCH-LAYOUT]   'opponent' at x=", round(x_center, 1),
                              "%, opponent_min=", round(opponent_min, 1), "%")
      } else if (kw == "results") {
        results_min <- x_min_h - 2
        opponent_max <- x_min_h - 2
        results_max <- x_max_h + 10
        if (verbose) message("[MATCH-LAYOUT]   'results' at x=", round(x_center, 1),
                              "%, results_min=", round(results_min, 1), "%")
      } else if (kw == "points") {
        points_min <- x_min_h - 2
        results_max <- x_min_h - 2
        if (verbose) message("[MATCH-LAYOUT]   'points' at x=", round(x_center, 1),
                              "%, points_min=", round(points_min, 1), "%")
      }
    }

    # Remove header row and everything above it
    ann <- ann[ann$y_center_pct > header_y + 2, ]
    if (verbose) message("[MATCH-LAYOUT] Removed header and above, ", nrow(ann), " annotations remain")
  } else {
    if (verbose) message("[MATCH-LAYOUT] No header row found (scrolled screenshot?), using defaults")
  }

  if (verbose) {
    message("[MATCH-LAYOUT] Column boundaries: round=[0-", round(round_max, 1),
            "%], opponent=[", round(opponent_min, 1), "-", round(opponent_max, 1),
            "%], results=[", round(results_min, 1), "-", round(results_max, 1),
            "%], points=[", round(points_min, 1), "-100%]")
  }

  if (nrow(ann) == 0) return(empty_result)

  # --- Step 5: Filter known noise text ---
  noise_patterns <- c(
    "privacy", "policy", "digimon", "card", "game", "home",
    "my", "events", "event", "search", "decks", "others",
    "store", "match", "history",
    "bandai", "obandai", "akiyoshi", "animation", "reserved", "rights",
    "all", "\u00a9", "toei",
    "ranking", "cardgame", "ranki", "ng",
    "eard", "bamb",
    "+",
    "co", "ltd", "hongo", "bunkyo-ku", "bunkyo",
    "tokyo", "inc",
    # Match history legend
    "3:", "1:", "0:", "win,", "draw,", "lose",
    "win", "draw", "lose"
  )

  is_noise <- tolower(ann$text) %in% noise_patterns |
    grepl("^B[\\x{2B50}\\x{2736}\\x{2606}\\x{2605}\\x{2731}\u2b51\u2736\u2606\u2605X]+$", ann$text, perl = TRUE) |
    grepl("^BXXX", ann$text) |
    grepl("^\u00a9", ann$text) |
    grepl("^\\.$", ann$text) |
    grepl("^[^A-Za-z0-9]$", ann$text)

  n_before <- nrow(ann)
  ann <- ann[!is_noise, ]
  if (verbose) message("[MATCH-LAYOUT] Filtered noise: ", n_before, " -> ", nrow(ann))

  if (nrow(ann) == 0) return(empty_result)

  # --- Step 6: Cluster into rows by Y-center ---
  ann <- ann[order(ann$y_center_pct), ]
  row_ids <- integer(nrow(ann))
  current_row <- 1
  row_ids[1] <- 1

  if (nrow(ann) > 1) {
    for (i in 2:nrow(ann)) {
      if (ann$y_center_pct[i] - ann$y_center_pct[i - 1] > 1.5) {
        current_row <- current_row + 1
      }
      row_ids[i] <- current_row
    }
  }

  ann$row_id <- row_ids
  n_rows <- max(row_ids)
  if (verbose) message("[MATCH-LAYOUT] Clustered into ", n_rows, " visual rows")

  # --- Step 7: Extract match data from each row ---
  results <- list()

  for (r in seq_len(n_rows)) {
    row_ann <- ann[ann$row_id == r, ]
    if (nrow(row_ann) == 0) next

    row_y_center <- mean(row_ann$y_center_pct)

    # Classify annotations by column
    round_texts <- row_ann[row_ann$x_center_pct <= round_max, , drop = FALSE]
    opponent_texts <- row_ann[row_ann$x_center_pct > opponent_min &
                                row_ann$x_center_pct <= opponent_max, , drop = FALSE]
    results_texts <- row_ann[row_ann$x_center_pct > results_min &
                               row_ann$x_center_pct <= results_max, , drop = FALSE]
    points_texts <- row_ann[row_ann$x_center_pct > points_min, , drop = FALSE]

    if (verbose && nrow(row_ann) > 0) {
      all_text <- paste(row_ann$text, collapse = " | ")
      message("[MATCH-LAYOUT] Row ", r, " (y=", round(row_y_center, 1), "%): ", all_text)
    }

    # --- Extract round number ---
    round_num <- NA_integer_
    if (nrow(round_texts) > 0) {
      for (rt in seq_len(nrow(round_texts))) {
        cleaned <- gsub("[^0-9]", "", round_texts$text[rt])
        if (nchar(cleaned) > 0) {
          val <- suppressWarnings(as.integer(cleaned))
          if (!is.na(val) && val >= 1 && val <= 15) {
            round_num <- val
            break
          }
        }
      }
    }

    # --- Extract opponent username and member number ---
    opponent_username <- NA_character_
    opponent_member <- NA_character_
    match_type <- "normal"

    if (nrow(opponent_texts) > 0) {
      # Sort by Y position (username above member number)
      opponent_texts <- opponent_texts[order(opponent_texts$y_center_pct), ]

      # Separate into visual sub-lines (within 1% Y = same line)
      sub_lines <- list()
      current_sub <- list(opponent_texts[1, ])
      if (nrow(opponent_texts) > 1) {
        for (ot in 2:nrow(opponent_texts)) {
          if (abs(opponent_texts$y_center_pct[ot] -
                  opponent_texts$y_center_pct[ot - 1]) <= 1.0) {
            current_sub[[length(current_sub) + 1]] <- opponent_texts[ot, ]
          } else {
            sub_lines[[length(sub_lines) + 1]] <- do.call(rbind, current_sub)
            current_sub <- list(opponent_texts[ot, ])
          }
        }
      }
      sub_lines[[length(sub_lines) + 1]] <- do.call(rbind, current_sub)

      # Process each sub-line
      for (sl in seq_along(sub_lines)) {
        sub_line <- sub_lines[[sl]]
        sub_line <- sub_line[order(sub_line$x_center_pct), ]
        line_text <- paste(sub_line$text, collapse = " ")

        # Check for "Win by Default" / bye patterns
        # GCV may split "Win" into the round column, leaving "by Default" in opponent
        if (grepl("Win\\s+by\\s+Default", line_text, ignore.case = TRUE) ||
            grepl("^by\\s+Default$", line_text, ignore.case = TRUE) ||
            grepl("^Default$", line_text, ignore.case = TRUE)) {
          match_type <- "default"
          opponent_username <- "Win by Default"
          if (verbose) message("[MATCH-LAYOUT]   Win by Default detected")
          next
        }

        # Check for 10-digit member number
        if (grepl("\\d{10}", line_text)) {
          mem_match <- regmatches(line_text, regexec("(\\d{10})", line_text))[[1]]
          if (length(mem_match) > 1) {
            opponent_member <- mem_match[2]
            if (verbose) message("[MATCH-LAYOUT]   Member number: ", opponent_member)
            next
          }
        }

        # Check for GUEST##### pattern
        if (grepl("GUEST\\d{5}", line_text, ignore.case = TRUE)) {
          mem_match <- regmatches(line_text, regexec("(GUEST\\d{5})", line_text, ignore.case = TRUE))[[1]]
          if (length(mem_match) > 1) {
            opponent_member <- mem_match[2]
            if (verbose) message("[MATCH-LAYOUT]   Member number (GUEST): ", opponent_member)
            next
          }
        }

        # Skip "Member" / "Number" keywords
        if (grepl("^Member$", line_text, ignore.case = TRUE) ||
            grepl("^Number$", line_text, ignore.case = TRUE) ||
            grepl("^Member\\s+Number", line_text, ignore.case = TRUE)) {
          # Try to extract embedded member number
          full_match <- regmatches(line_text,
                                    regexec("Member\\s+Number\\s*:?\\s*(\\d{10}|GUEST\\d{5})",
                                            line_text, ignore.case = TRUE))[[1]]
          if (length(full_match) > 1) {
            opponent_member <- full_match[2]
            if (verbose) message("[MATCH-LAYOUT]   Member number (labeled): ", opponent_member)
          }
          next
        }

        # Check individual annotations for member numbers
        has_member <- FALSE
        for (at in seq_len(nrow(sub_line))) {
          ann_text <- sub_line$text[at]
          if (grepl("^\\d{10}$", ann_text)) {
            opponent_member <- ann_text
            has_member <- TRUE
            if (verbose) message("[MATCH-LAYOUT]   Member number (individual): ", opponent_member)
          } else if (grepl("^GUEST\\d{5}$", ann_text, ignore.case = TRUE)) {
            opponent_member <- ann_text
            has_member <- TRUE
            if (verbose) message("[MATCH-LAYOUT]   Member number (GUEST individual): ", opponent_member)
          }
        }
        if (has_member) next

        # This sub-line is a username candidate
        username_parts <- c()
        for (at in seq_len(nrow(sub_line))) {
          ann_text <- sub_line$text[at]
          if (grepl("^(Member|Number)$", ann_text, ignore.case = TRUE)) next
          username_parts <- c(username_parts, ann_text)
        }

        if (length(username_parts) > 0 && is.na(opponent_username)) {
          opponent_username <- paste(username_parts, collapse = " ")
          if (verbose) message("[MATCH-LAYOUT]   Username: '", opponent_username, "'")
        }
      }
    }

    # Scan all row text for member numbers if not found in opponent column
    if (is.na(opponent_member) && match_type == "normal") {
      for (ri in seq_len(nrow(row_ann))) {
        txt <- row_ann$text[ri]
        if (grepl("^\\d{10}$", txt)) {
          opponent_member <- txt
          if (verbose) message("[MATCH-LAYOUT]   Member number (row scan): ", opponent_member)
          break
        } else if (grepl("^GUEST\\d{5}$", txt, ignore.case = TRUE)) {
          opponent_member <- txt
          if (verbose) message("[MATCH-LAYOUT]   Member number (row scan GUEST): ", opponent_member)
          break
        }
      }
    }

    # --- Extract results (X-X-X) ---
    games_won <- NA_integer_
    games_lost <- NA_integer_
    games_tied <- NA_integer_

    if (nrow(results_texts) > 0) {
      # Try to find X-X-X pattern in combined text or individual annotations
      for (rt in seq_len(nrow(results_texts))) {
        result_match <- regmatches(results_texts$text[rt],
                                     regexec("^(\\d)$", results_texts$text[rt]))[[1]]
        # Individual digits — collect them
      }

      # Try combined text approach first
      results_texts_sorted <- results_texts[order(results_texts$x_center_pct), ]
      combined <- paste(results_texts_sorted$text, collapse = "")
      # Match X-X-X with optional spaces/dashes
      combined_match <- regmatches(combined, regexec("(\\d)\\s*-\\s*(\\d)\\s*-\\s*(\\d)", combined))[[1]]
      if (length(combined_match) > 1) {
        games_won <- as.integer(combined_match[2])
        games_lost <- as.integer(combined_match[3])
        games_tied <- as.integer(combined_match[4])
        if (verbose) message("[MATCH-LAYOUT]   Results: ", games_won, "-", games_lost, "-", games_tied)
      } else {
        # Try individual annotations — OCR might split "2-1-0" into "2-1-0" or "2" "-" "1" "-" "0"
        digits <- c()
        for (rt in seq_len(nrow(results_texts_sorted))) {
          txt <- results_texts_sorted$text[rt]
          # Extract all digits
          d <- regmatches(txt, gregexpr("\\d", txt))[[1]]
          digits <- c(digits, d)
        }
        if (length(digits) >= 3) {
          gw <- as.integer(digits[1])
          gl <- as.integer(digits[2])
          gt <- as.integer(digits[3])
          # Sanity check: game counts should be 0-3 for best-of-5
          if (all(c(gw, gl, gt) <= 3)) {
            games_won <- gw
            games_lost <- gl
            games_tied <- gt
            if (verbose) message("[MATCH-LAYOUT]   Results (digits): ", games_won, "-", games_lost, "-", games_tied)
          } else if (verbose) {
            message("[MATCH-LAYOUT]   Results (digits) rejected — values out of range: ", gw, "-", gl, "-", gt)
          }
        }
      }
    }

    # --- Extract points ---
    match_points <- NA_integer_
    if (nrow(points_texts) > 0) {
      for (pt in seq_len(nrow(points_texts))) {
        cleaned <- gsub("[^0-9]", "", points_texts$text[pt])
        if (nchar(cleaned) > 0) {
          val <- suppressWarnings(as.integer(cleaned))
          if (!is.na(val) && val %in% c(0L, 1L, 3L)) {
            match_points <- val
            if (verbose) message("[MATCH-LAYOUT]   Points: ", match_points)
            break
          }
        }
      }
    }

    # --- Validate: need at least a round or opponent to be a real row ---
    has_round <- !is.na(round_num)
    has_opponent <- !is.na(opponent_username) || match_type == "default"

    if (!has_round && !has_opponent) {
      if (verbose) message("[MATCH-LAYOUT]   Skipping row ", r, ": no round or opponent")
      next
    }

    # Defaults for byes/defaults
    if (match_type == "default") {
      if (is.na(games_won)) games_won <- 0L
      if (is.na(games_lost)) games_lost <- 0L
      if (is.na(games_tied)) games_tied <- 0L
      if (is.na(match_points)) match_points <- 3L  # Default wins give 3 points
    }

    results[[length(results) + 1]] <- data.frame(
      round = if (is.na(round_num)) length(results) + 1L else round_num,
      opponent_username = if (is.na(opponent_username)) "" else opponent_username,
      opponent_member_number = if (is.na(opponent_member)) NA_character_ else opponent_member,
      games_won = if (is.na(games_won)) 0L else games_won,
      games_lost = if (is.na(games_lost)) 0L else games_lost,
      games_tied = if (is.na(games_tied)) 0L else games_tied,
      match_points = if (is.na(match_points)) 0L else match_points,
      match_type = match_type,
      stringsAsFactors = FALSE
    )

    if (verbose) {
      message("[MATCH-LAYOUT]   -> Round ", round_num, ": ",
              if (match_type == "default") "Win by Default" else opponent_username,
              " (", opponent_member, ") ",
              games_won, "-", games_lost, "-", games_tied, " pts=", match_points)
    }
  }

  if (verbose) message("[MATCH-LAYOUT] Extracted ", length(results), " match rows")

  if (length(results) == 0) return(empty_result)

  # Build result data frame
  result_df <- do.call(rbind, results)
  result_df <- result_df[order(result_df$round), ]
  rownames(result_df) <- NULL

  if (verbose) {
    message("[MATCH-LAYOUT] Final: ", nrow(result_df), " matches")
    for (i in seq_len(nrow(result_df))) {
      message("[MATCH-LAYOUT]   R", result_df$round[i], " vs ", result_df$opponent_username[i],
              " (", result_df$opponent_member_number[i], ") ",
              result_df$games_won[i], "-", result_df$games_lost[i], "-", result_df$games_tied[i],
              " pts=", result_df$match_points[i],
              if (result_df$match_type[i] != "normal") paste0(" [", result_df$match_type[i], "]") else "")
    }
  }

  result_df
}

#' Parse match history with layout-first fallback strategy
#'
#' Tries the layout-aware parser first (uses bounding boxes).
#' Falls back to the text-based parser if layout parsing fails.
#' Same pattern as parse_standings().
#'
#' @param ocr_result Result from gcv_detect_text() — either a list or plain text string
#' @param verbose Print debug messages
#' @return Data frame with columns: round, opponent_username, opponent_member_number,
#'         games_won, games_lost, games_tied, match_points, match_type
parse_match_history <- function(ocr_result, verbose = TRUE) {
  # Handle both new list format and legacy plain text
  if (is.list(ocr_result)) {
    text <- ocr_result$text
    annotations <- ocr_result$annotations
    image_width <- ocr_result$image_width
    image_height <- ocr_result$image_height
  } else {
    text <- ocr_result
    annotations <- NULL
    image_width <- 0
    image_height <- 0
  }

  # Try layout-aware parser first
  if (!is.null(annotations) && nrow(annotations) > 0 && image_width > 0 && image_height > 0) {
    if (verbose) message("[OCR] Trying layout-aware match history parser...")

    layout_result <- tryCatch({
      parse_match_history_layout(annotations, image_width, image_height, verbose = verbose)
    }, error = function(e) {
      if (verbose) message("[OCR] Layout match parser error: ", e$message)
      data.frame()
    })

    # Validate: need at least 1 match with opponent or default
    if (nrow(layout_result) > 0) {
      has_opponent <- any(!is.na(layout_result$opponent_username) & layout_result$opponent_username != "")
      has_results <- any(!is.na(layout_result$games_won))

      if (has_opponent && has_results) {
        if (verbose) message("[OCR] Using layout match parser (", nrow(layout_result), " matches found)")
        return(layout_result)
      } else {
        if (verbose) message("[OCR] Layout match parser returned incomplete data, falling back to text parser")
      }
    } else {
      if (verbose) message("[OCR] Layout match parser returned 0 matches, falling back to text parser")
    }
  }

  # Fallback to text-based parser
  if (verbose) message("[OCR] Using text-based match history parser")
  result <- parse_match_history_text(text, verbose = verbose)

  # Add match_type column if missing (text parser doesn't produce it)
  if (nrow(result) > 0 && !"match_type" %in% names(result)) {
    result$match_type <- "normal"
  }

  result
}
