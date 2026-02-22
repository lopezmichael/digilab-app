# scripts/batch_test_ocr.R
# Batch OCR testing for multiple screenshots
#
# Usage:
#   source("scripts/batch_test_ocr.R")
#   batch_test()                    # Process all screenshots, call API
#   batch_retest()                  # Re-parse saved OCR text (no API)
#   batch_test_folders()            # Process test folders with expected.csv (calls API)
#   batch_retest_folders()          # Re-parse saved folder data (no API)
#   review_flagged()                # Interactively review flagged items
#
# Folder structure:
#   screenshots/
#   ├── standings/          <- Drop tournament standings screenshots here
#   ├── match_history/      <- Drop match history screenshots here
#   └── results/
#       ├── summary.csv            <- Overview of all results
#       ├── standings_parsed/      <- Individual parsed CSVs
#       ├── match_history_parsed/  <- Individual parsed CSVs
#       ├── ocr_text/              <- Raw OCR text for re-testing
#       └── flagged/               <- Copy of screenshots needing review

library(dotenv)
if (file.exists(".env")) load_dot_env(".env")

source("R/ocr.R")

# Configuration
SCREENSHOTS_DIR <- "screenshots"
STANDINGS_DIR <- file.path(SCREENSHOTS_DIR, "standings")
MATCH_HISTORY_DIR <- file.path(SCREENSHOTS_DIR, "match_history")
RESULTS_DIR <- file.path(SCREENSHOTS_DIR, "results")

# Ensure directories exist
ensure_dirs <- function() {
  dirs <- c(
    STANDINGS_DIR,
    MATCH_HISTORY_DIR,
    file.path(RESULTS_DIR, "standings_parsed"),
    file.path(RESULTS_DIR, "match_history_parsed"),
    file.path(RESULTS_DIR, "ocr_text"),
    file.path(RESULTS_DIR, "flagged")
  )
  for (d in dirs) {
    if (!dir.exists(d)) dir.create(d, recursive = TRUE)
  }
}

#' Get list of image files in a directory
get_images <- function(dir) {
  if (!dir.exists(dir)) return(character(0))
  list.files(dir, pattern = "\\.(png|jpg|jpeg|webp|PNG|JPG|JPEG|WEBP)$", full.names = TRUE)
}

#' Process a single standings screenshot
process_standings <- function(image_path, rounds = 4, verbose = FALSE) {
  filename <- basename(image_path)
  name_base <- tools::file_path_sans_ext(filename)

  result <- list(
    filename = filename,
    type = "standings",
    ocr_success = FALSE,
    players_found = 0,
    warnings = c(),
    ocr_text = NULL,
    parsed_data = NULL
  )

  # Get OCR text
  ocr_result <- tryCatch({
    gcv_detect_text(image_path, verbose = verbose)
  }, error = function(e) {
    result$warnings <<- c(result$warnings, paste("OCR error:", e$message))
    NULL
  })

  # Extract text from structured result (backward compatible with plain string)
  ocr_text <- if (is.list(ocr_result)) ocr_result$text else ocr_result

  if (is.null(ocr_text) || ocr_text == "") {
    result$warnings <- c(result$warnings, "OCR returned no text")
    return(result)
  }

  result$ocr_success <- TRUE
  result$ocr_text <- ocr_text

  # Save OCR text
  ocr_file <- file.path(RESULTS_DIR, "ocr_text", paste0(name_base, "_standings.txt"))
  writeLines(ocr_text, ocr_file)

  # Save annotation data if available
  if (is.list(ocr_result) && !is.null(ocr_result$annotations) && nrow(ocr_result$annotations) > 0) {
    ann_file <- file.path(RESULTS_DIR, "ocr_text", paste0(name_base, "_annotations.rds"))
    saveRDS(ocr_result, ann_file)
  }

  # Parse
  parsed <- tryCatch({
    parse_tournament_standings(ocr_text, total_rounds = rounds, verbose = verbose)
  }, error = function(e) {
    result$warnings <<- c(result$warnings, paste("Parse error:", e$message))
    data.frame()
  })

  result$players_found <- nrow(parsed)
  result$parsed_data <- parsed

  # Check for issues
  if (nrow(parsed) == 0) {
    result$warnings <- c(result$warnings, "No players parsed")
  } else {
    # Check for missing member numbers
    missing_members <- sum(is.na(parsed$member_number) | parsed$member_number == "")
    if (missing_members > 0) {
      result$warnings <- c(result$warnings, paste(missing_members, "players missing member number"))
    }

    # Check for suspiciously low count (might be partial screenshot)
    if (nrow(parsed) < 4) {
      result$warnings <- c(result$warnings, "Low player count - partial screenshot?")
    }

    # Check for placement gaps
    expected_placements <- seq_len(nrow(parsed))
    if (!all(sort(parsed$placement) == expected_placements)) {
      result$warnings <- c(result$warnings, "Placement gaps detected")
    }

    # Save parsed CSV
    csv_file <- file.path(RESULTS_DIR, "standings_parsed", paste0(name_base, ".csv"))
    write.csv(parsed, csv_file, row.names = FALSE)
  }

  result
}

#' Process a single match history screenshot
process_match_history <- function(image_path, verbose = FALSE) {
  filename <- basename(image_path)
  name_base <- tools::file_path_sans_ext(filename)

  result <- list(
    filename = filename,
    type = "match_history",
    ocr_success = FALSE,
    players_found = 0,
    warnings = c(),
    ocr_text = NULL,
    parsed_data = NULL
  )

  # Get OCR text
  ocr_result <- tryCatch({
    gcv_detect_text(image_path, verbose = verbose)
  }, error = function(e) {
    result$warnings <<- c(result$warnings, paste("OCR error:", e$message))
    NULL
  })

  # Extract text from structured result (backward compatible with plain string)
  ocr_text <- if (is.list(ocr_result)) ocr_result$text else ocr_result

  if (is.null(ocr_text) || ocr_text == "") {
    result$warnings <- c(result$warnings, "OCR returned no text")
    return(result)
  }

  result$ocr_success <- TRUE
  result$ocr_text <- ocr_text

  # Save OCR text
  ocr_file <- file.path(RESULTS_DIR, "ocr_text", paste0(name_base, "_match.txt"))
  writeLines(ocr_text, ocr_file)

  # Save annotation data if available
  if (is.list(ocr_result) && !is.null(ocr_result$annotations) && nrow(ocr_result$annotations) > 0) {
    ann_file <- file.path(RESULTS_DIR, "ocr_text", paste0(name_base, "_match_annotations.rds"))
    saveRDS(ocr_result, ann_file)
  }

  # Parse
  parsed <- tryCatch({
    parse_match_history(ocr_text, verbose = verbose)
  }, error = function(e) {
    result$warnings <<- c(result$warnings, paste("Parse error:", e$message))
    data.frame()
  })

  result$players_found <- nrow(parsed)
  result$parsed_data <- parsed

  # Check for issues
  if (nrow(parsed) == 0) {
    result$warnings <- c(result$warnings, "No matches parsed")
  } else {
    # Check for missing data
    missing_results <- sum(parsed$games_won == 0 & parsed$games_lost == 0 & parsed$games_tied == 0)
    if (missing_results > 0) {
      result$warnings <- c(result$warnings, paste(missing_results, "matches missing W-L-T data"))
    }

    # Save parsed CSV
    csv_file <- file.path(RESULTS_DIR, "match_history_parsed", paste0(name_base, ".csv"))
    write.csv(parsed, csv_file, row.names = FALSE)
  }

  result
}

#' Run batch test on all screenshots (calls API)
#'
#' @param rounds Default rounds for standings parsing
#' @param verbose Print detailed OCR/parse logs
#' @return Summary data frame
batch_test <- function(rounds = 4, verbose = FALSE) {
  ensure_dirs()

  standings_files <- get_images(STANDINGS_DIR)
  match_files <- get_images(MATCH_HISTORY_DIR)

  total <- length(standings_files) + length(match_files)

  if (total == 0) {
    message("No screenshots found!")
    message("  Place standings screenshots in: ", STANDINGS_DIR)
    message("  Place match history screenshots in: ", MATCH_HISTORY_DIR)
    return(invisible(NULL))
  }

  message("\n", strrep("=", 60))
  message("BATCH OCR TESTING")
  message(strrep("=", 60))
  message("Standings screenshots: ", length(standings_files))
  message("Match history screenshots: ", length(match_files))
  message("Total: ", total)
  message(strrep("=", 60), "\n")

  results <- list()
  flagged_files <- c()

  # Process standings
  if (length(standings_files) > 0) {
    message("Processing STANDINGS screenshots...")
    for (i in seq_along(standings_files)) {
      f <- standings_files[i]
      message(sprintf("  [%d/%d] %s", i, length(standings_files), basename(f)))

      res <- process_standings(f, rounds = rounds, verbose = verbose)
      results[[length(results) + 1]] <- res

      if (length(res$warnings) > 0) {
        flagged_files <- c(flagged_files, f)
        message("    ⚠ FLAGGED: ", paste(res$warnings, collapse = "; "))
      } else {
        message("    ✓ ", res$players_found, " players")
      }
    }
  }

  # Process match history
  if (length(match_files) > 0) {
    message("\nProcessing MATCH HISTORY screenshots...")
    for (i in seq_along(match_files)) {
      f <- match_files[i]
      message(sprintf("  [%d/%d] %s", i, length(match_files), basename(f)))

      res <- process_match_history(f, verbose = verbose)
      results[[length(results) + 1]] <- res

      if (length(res$warnings) > 0) {
        flagged_files <- c(flagged_files, f)
        message("    ⚠ FLAGGED: ", paste(res$warnings, collapse = "; "))
      } else {
        message("    ✓ ", res$players_found, " matches")
      }
    }
  }

  # Copy flagged files
  if (length(flagged_files) > 0) {
    flagged_dir <- file.path(RESULTS_DIR, "flagged")
    for (f in flagged_files) {
      file.copy(f, file.path(flagged_dir, basename(f)), overwrite = TRUE)
    }
  }

  # Build summary
  summary_df <- data.frame(
    filename = sapply(results, function(r) r$filename),
    type = sapply(results, function(r) r$type),
    ocr_success = sapply(results, function(r) r$ocr_success),
    items_found = sapply(results, function(r) r$players_found),
    flagged = sapply(results, function(r) length(r$warnings) > 0),
    warnings = sapply(results, function(r) paste(r$warnings, collapse = "; ")),
    stringsAsFactors = FALSE
  )

  # Save summary
  summary_file <- file.path(RESULTS_DIR, "summary.csv")
  write.csv(summary_df, summary_file, row.names = FALSE)

  # Print summary
  message("\n", strrep("=", 60))
  message("SUMMARY")
  message(strrep("=", 60))
  message("Total processed: ", nrow(summary_df))
  message("Successful OCR: ", sum(summary_df$ocr_success))
  message("Flagged for review: ", sum(summary_df$flagged))
  message("\nResults saved to: ", RESULTS_DIR)
  message("  summary.csv - Overview of all results")
  message("  standings_parsed/ - Individual standings CSVs")
  message("  match_history_parsed/ - Individual match history CSVs")
  message("  ocr_text/ - Raw OCR text (for re-testing without API)")
  message("  flagged/ - Copies of screenshots needing review")

  if (sum(summary_df$flagged) > 0) {
    message("\n⚠ FLAGGED FILES:")
    flagged <- summary_df[summary_df$flagged, ]
    for (i in seq_len(nrow(flagged))) {
      message("  ", flagged$filename[i], ": ", flagged$warnings[i])
    }
    message("\nRun review_flagged() to interactively review these.")
  }

  message(strrep("=", 60), "\n")

  invisible(summary_df)
}

#' Compare parsed standings against expected ground truth
#'
#' @param parsed Data frame with parsed results (placement, username, member_number, points)
#' @param expected Data frame from expected.csv (rank, username, member_number, points)
#' @return List with comparison metrics
compare_to_expected <- function(parsed, expected) {
  n_expected <- nrow(expected)
  rank_correct <- 0
  username_correct <- 0
  member_correct <- 0
  points_correct <- 0

  details <- list()

  for (i in seq_len(n_expected)) {
    exp_row <- expected[i, ]
    exp_rank <- exp_row$rank

    # Find matching rank in parsed results
    match_idx <- which(parsed$placement == exp_rank)

    if (length(match_idx) == 0) {
      details[[i]] <- list(rank = exp_rank, found = FALSE)
      next
    }

    # If multiple rows share the same rank, try to find the best match
    parsed_match <- parsed[match_idx, , drop = FALSE]

    # Score each candidate
    best_score <- -1
    best_row <- parsed_match[1, ]
    for (j in seq_len(nrow(parsed_match))) {
      row <- parsed_match[j, ]
      score <- 0
      if (tolower(trimws(row$username)) == tolower(trimws(exp_row$username))) score <- score + 1
      # Strip leading zeros for member number comparison
      parsed_mem <- gsub("^0+", "", tolower(trimws(row$member_number)))
      exp_mem <- gsub("^0+", "", tolower(trimws(exp_row$member_number)))
      if (parsed_mem == exp_mem) score <- score + 1
      if (score > best_score) {
        best_score <- score
        best_row <- row
      }
    }

    rank_correct <- rank_correct + 1

    u_match <- tolower(trimws(best_row$username)) == tolower(trimws(exp_row$username))
    if (u_match) username_correct <- username_correct + 1

    parsed_mem <- gsub("^0+", "", tolower(trimws(best_row$member_number)))
    exp_mem <- gsub("^0+", "", tolower(trimws(exp_row$member_number)))
    m_match <- parsed_mem == exp_mem
    if (m_match) member_correct <- member_correct + 1

    p_match <- as.integer(best_row$points) == as.integer(exp_row$points)
    if (!is.na(p_match) && p_match) points_correct <- points_correct + 1

    details[[i]] <- list(
      rank = exp_rank,
      found = TRUE,
      username_match = u_match,
      member_match = m_match,
      points_match = p_match,
      expected_username = exp_row$username,
      parsed_username = best_row$username,
      expected_member = exp_row$member_number,
      parsed_member = best_row$member_number,
      expected_points = exp_row$points,
      parsed_points = best_row$points
    )
  }

  total_checks <- 4 * n_expected
  total_correct <- rank_correct + username_correct + member_correct + points_correct
  accuracy <- if (total_checks > 0) (total_correct / total_checks) * 100 else 0

  list(
    n_expected = n_expected,
    n_parsed = nrow(parsed),
    rank_correct = rank_correct,
    username_correct = username_correct,
    member_correct = member_correct,
    points_correct = points_correct,
    total_correct = total_correct,
    total_checks = total_checks,
    accuracy = accuracy,
    details = details
  )
}

#' Merge parsed standings from multiple screenshots
#'
#' Combines results, deduplicates by member_number (GUEST by username), sorts by placement.
#'
#' @param all_parsed List of data frames from individual screenshots
#' @return Single merged data frame
merge_parsed_standings <- function(all_parsed) {
  merged <- do.call(rbind, all_parsed)
  if (is.null(merged) || nrow(merged) == 0) return(merged)

  # Dedup: for non-GUEST players, keep first occurrence by member_number
  # For GUEST players, dedup by username
  is_guest <- grepl("^GUEST", merged$member_number, ignore.case = TRUE) |
              is.na(merged$member_number) | merged$member_number == ""

  non_guest <- merged[!is_guest, ]
  guest <- merged[is_guest, ]

  if (nrow(non_guest) > 0) {
    non_guest <- non_guest[!duplicated(non_guest$member_number), ]
  }
  if (nrow(guest) > 0) {
    guest <- guest[!duplicated(tolower(guest$username)), ]
  }

  result <- rbind(non_guest, guest)
  result <- result[order(result$placement), ]
  rownames(result) <- NULL
  result
}

#' Process all test folders in screenshots/standings/ (calls API)
#'
#' Each subfolder represents one tournament. Folder names encode metadata:
#' Xplayers_Yrounds_Zscreenshots[_notes]
#'
#' If an expected.csv exists, results are compared to ground truth.
#'
#' @param verbose Print detailed OCR/parse logs
#' @return Summary data frame (invisible)
batch_test_folders <- function(verbose = FALSE) {
  ensure_dirs()

  # Find all subdirectories in standings folder
  all_items <- list.dirs(STANDINGS_DIR, recursive = FALSE, full.names = TRUE)
  folders <- all_items[file.info(all_items)$isdir]

  if (length(folders) == 0) {
    message("No test folders found in ", STANDINGS_DIR)
    message("Create subfolders with format: Xplayers_Yrounds_Zscreenshots")
    return(invisible(NULL))
  }

  message("\n", strrep("=", 60))
  message("BATCH FOLDER TEST (calling API)")
  message(strrep("=", 60))
  message("Test folders found: ", length(folders))
  message(strrep("=", 60), "\n")

  folder_results <- list()

  for (folder in folders) {
    folder_name <- basename(folder)
    images <- get_images(folder)

    if (length(images) == 0) {
      message("[", folder_name, "] No images found, skipping")
      next
    }

    # Parse folder name for metadata
    parts <- strsplit(folder_name, "_")[[1]]
    total_players <- as.integer(gsub("[^0-9]", "", parts[1]))
    total_rounds <- as.integer(gsub("[^0-9]", "", parts[2]))

    message("\n[", folder_name, "] ",
            length(images), " image(s), ",
            total_players, " expected players, ",
            total_rounds, " rounds")

    # Process each image
    all_parsed <- list()
    for (img in images) {
      img_name <- tools::file_path_sans_ext(basename(img))

      ocr_result <- tryCatch({
        gcv_detect_text(img, verbose = verbose)
      }, error = function(e) {
        message("  OCR error on ", basename(img), ": ", e$message)
        NULL
      })

      if (is.null(ocr_result)) next

      # Save annotations as .rds
      ann_file <- file.path(RESULTS_DIR, "ocr_text",
                            paste0(folder_name, "_", img_name, "_annotations.rds"))
      saveRDS(ocr_result, ann_file)

      # Save OCR text
      ocr_text <- if (is.list(ocr_result)) ocr_result$text else ocr_result
      txt_file <- file.path(RESULTS_DIR, "ocr_text",
                            paste0(folder_name, "_", img_name, ".txt"))
      writeLines(ocr_text, txt_file)

      # Parse using orchestrator
      parsed <- tryCatch({
        parse_standings(ocr_result, total_rounds = total_rounds, verbose = verbose)
      }, error = function(e) {
        message("  Parse error on ", basename(img), ": ", e$message)
        data.frame()
      })

      if (nrow(parsed) > 0) {
        all_parsed[[length(all_parsed) + 1]] <- parsed
        message("  ", basename(img), ": ", nrow(parsed), " players")
      } else {
        message("  ", basename(img), ": 0 players")
      }
    }

    # Merge results from multiple screenshots
    if (length(all_parsed) > 0) {
      merged <- merge_parsed_standings(all_parsed)
    } else {
      merged <- data.frame(
        placement = integer(), username = character(),
        member_number = character(), points = integer(),
        wins = integer(), losses = integer(), ties = integer(),
        stringsAsFactors = FALSE
      )
    }

    # Save merged CSV
    csv_file <- file.path(RESULTS_DIR, "standings_parsed", paste0(folder_name, ".csv"))
    if (nrow(merged) > 0) write.csv(merged, csv_file, row.names = FALSE)

    # Compare against expected.csv if it exists
    expected_file <- file.path(folder, "expected.csv")
    comparison <- NULL
    if (file.exists(expected_file)) {
      expected <- read.csv(expected_file, stringsAsFactors = FALSE)
      comparison <- compare_to_expected(merged, expected)

      message("  Accuracy: ", sprintf("%.1f%%", comparison$accuracy),
              " (", comparison$total_correct, "/", comparison$total_checks, ")")
      message("    Rank: ", comparison$rank_correct, "/", comparison$n_expected,
              "  Username: ", comparison$username_correct, "/", comparison$n_expected,
              "  Member#: ", comparison$member_correct, "/", comparison$n_expected,
              "  Points: ", comparison$points_correct, "/", comparison$n_expected)
    } else {
      message("  No expected.csv - skipping comparison")
    }

    folder_results[[folder_name]] <- list(
      folder = folder_name,
      n_images = length(images),
      expected_players = total_players,
      total_rounds = total_rounds,
      n_parsed = nrow(merged),
      comparison = comparison,
      merged = merged
    )
  }

  # Print overall summary
  message("\n", strrep("=", 60))
  message("OVERALL SUMMARY")
  message(strrep("=", 60))

  total_checks <- 0
  total_correct <- 0
  folders_with_expected <- 0

  for (fr in folder_results) {
    status <- if (!is.null(fr$comparison)) {
      folders_with_expected <- folders_with_expected + 1
      total_checks <- total_checks + fr$comparison$total_checks
      total_correct <- total_correct + fr$comparison$total_correct
      sprintf("%.1f%% accuracy", fr$comparison$accuracy)
    } else {
      "no ground truth"
    }
    message(sprintf("  %-50s %s (%d players)", fr$folder, status, fr$n_parsed))
  }

  if (total_checks > 0) {
    overall_accuracy <- (total_correct / total_checks) * 100
    message(sprintf("\nOverall accuracy: %.1f%% (%d/%d) across %d folder(s)",
                    overall_accuracy, total_correct, total_checks, folders_with_expected))
  }

  message(strrep("=", 60), "\n")

  invisible(folder_results)
}

#' Re-run parsing on saved annotation data for test folders (no API calls)
#'
#' Uses saved .rds files from previous batch_test_folders() runs.
#'
#' @param verbose Print detailed parse logs
#' @return Summary data frame (invisible)
batch_retest_folders <- function(verbose = TRUE) {
  ensure_dirs()

  # Find all subdirectories in standings folder
  all_items <- list.dirs(STANDINGS_DIR, recursive = FALSE, full.names = TRUE)
  folders <- all_items[file.info(all_items)$isdir]

  if (length(folders) == 0) {
    message("No test folders found in ", STANDINGS_DIR)
    return(invisible(NULL))
  }

  message("\n", strrep("=", 60))
  message("BATCH FOLDER RE-TEST (using saved annotations)")
  message(strrep("=", 60))
  message("Test folders found: ", length(folders))
  message(strrep("=", 60), "\n")

  folder_results <- list()

  for (folder in folders) {
    folder_name <- basename(folder)

    # Parse folder name for metadata
    parts <- strsplit(folder_name, "_")[[1]]
    total_players <- as.integer(gsub("[^0-9]", "", parts[1]))
    total_rounds <- as.integer(gsub("[^0-9]", "", parts[2]))

    # Find saved .rds files for this folder
    ocr_dir <- file.path(RESULTS_DIR, "ocr_text")
    rds_pattern <- paste0("^", gsub("([\\[\\]\\(\\)\\.])", "\\\\\\1", folder_name), "_.*_annotations\\.rds$")
    rds_files <- list.files(ocr_dir, pattern = rds_pattern, full.names = TRUE)

    if (length(rds_files) == 0) {
      message("[", folder_name, "] No saved .rds files found, skipping")
      next
    }

    message("\n[", folder_name, "] ",
            length(rds_files), " saved file(s), ",
            total_players, " expected players, ",
            total_rounds, " rounds")

    # Process each saved result
    all_parsed <- list()
    for (rds_file in rds_files) {
      ocr_result <- tryCatch({
        readRDS(rds_file)
      }, error = function(e) {
        message("  Error loading ", basename(rds_file), ": ", e$message)
        NULL
      })

      if (is.null(ocr_result)) next

      # Parse using orchestrator
      parsed <- tryCatch({
        parse_standings(ocr_result, total_rounds = total_rounds, verbose = verbose)
      }, error = function(e) {
        message("  Parse error on ", basename(rds_file), ": ", e$message)
        data.frame()
      })

      if (nrow(parsed) > 0) {
        all_parsed[[length(all_parsed) + 1]] <- parsed
        message("  ", basename(rds_file), ": ", nrow(parsed), " players")
      } else {
        message("  ", basename(rds_file), ": 0 players")
      }
    }

    # Merge results from multiple screenshots
    if (length(all_parsed) > 0) {
      merged <- merge_parsed_standings(all_parsed)
    } else {
      merged <- data.frame(
        placement = integer(), username = character(),
        member_number = character(), points = integer(),
        wins = integer(), losses = integer(), ties = integer(),
        stringsAsFactors = FALSE
      )
    }

    # Save merged CSV
    csv_file <- file.path(RESULTS_DIR, "standings_parsed", paste0(folder_name, ".csv"))
    if (nrow(merged) > 0) write.csv(merged, csv_file, row.names = FALSE)

    # Compare against expected.csv if it exists
    expected_file <- file.path(folder, "expected.csv")
    comparison <- NULL
    if (file.exists(expected_file)) {
      expected <- read.csv(expected_file, stringsAsFactors = FALSE)
      comparison <- compare_to_expected(merged, expected)

      message("  Accuracy: ", sprintf("%.1f%%", comparison$accuracy),
              " (", comparison$total_correct, "/", comparison$total_checks, ")")
      message("    Rank: ", comparison$rank_correct, "/", comparison$n_expected,
              "  Username: ", comparison$username_correct, "/", comparison$n_expected,
              "  Member#: ", comparison$member_correct, "/", comparison$n_expected,
              "  Points: ", comparison$points_correct, "/", comparison$n_expected)
    } else {
      message("  No expected.csv - skipping comparison")
    }

    folder_results[[folder_name]] <- list(
      folder = folder_name,
      n_rds = length(rds_files),
      expected_players = total_players,
      total_rounds = total_rounds,
      n_parsed = nrow(merged),
      comparison = comparison,
      merged = merged
    )
  }

  # Print overall summary
  message("\n", strrep("=", 60))
  message("OVERALL SUMMARY")
  message(strrep("=", 60))

  total_checks <- 0
  total_correct <- 0
  folders_with_expected <- 0

  for (fr in folder_results) {
    status <- if (!is.null(fr$comparison)) {
      folders_with_expected <- folders_with_expected + 1
      total_checks <- total_checks + fr$comparison$total_checks
      total_correct <- total_correct + fr$comparison$total_correct
      sprintf("%.1f%% accuracy", fr$comparison$accuracy)
    } else {
      "no ground truth"
    }
    message(sprintf("  %-50s %s (%d players)", fr$folder, status, fr$n_parsed))
  }

  if (total_checks > 0) {
    overall_accuracy <- (total_correct / total_checks) * 100
    message(sprintf("\nOverall accuracy: %.1f%% (%d/%d) across %d folder(s)",
                    overall_accuracy, total_correct, total_checks, folders_with_expected))
  }

  message(strrep("=", 60), "\n")

  invisible(folder_results)
}

#' Re-run parsing on saved OCR text (no API calls)
#'
#' @param rounds Default rounds for standings parsing
#' @param verbose Print detailed parse logs
#' @return Summary data frame
batch_retest <- function(rounds = 4, verbose = TRUE) {
  ensure_dirs()

  ocr_dir <- file.path(RESULTS_DIR, "ocr_text")
  ocr_files <- list.files(ocr_dir, pattern = "\\.txt$", full.names = TRUE)

  if (length(ocr_files) == 0) {
    message("No saved OCR text found. Run batch_test() first.")
    return(invisible(NULL))
  }

  message("\n", strrep("=", 60))
  message("BATCH RE-TEST (using saved OCR text)")
  message(strrep("=", 60))
  message("OCR files found: ", length(ocr_files))
  message(strrep("=", 60), "\n")

  results <- list()

  for (f in ocr_files) {
    filename <- basename(f)
    name_base <- tools::file_path_sans_ext(filename)

    # Determine type from filename suffix
    is_standings <- grepl("_standings$", name_base)
    is_match <- grepl("_match$", name_base)

    if (!is_standings && !is_match) {
      message("  Skipping unknown type: ", filename)
      next
    }

    type <- if (is_standings) "standings" else "match_history"
    message(sprintf("  [%s] %s", type, filename))

    ocr_text <- paste(readLines(f, warn = FALSE), collapse = "\n")

    if (is_standings) {
      parsed <- parse_tournament_standings(ocr_text, total_rounds = rounds, verbose = verbose)
      items <- nrow(parsed)

      # Save updated parsed CSV
      csv_name <- gsub("_standings$", "", name_base)
      csv_file <- file.path(RESULTS_DIR, "standings_parsed", paste0(csv_name, ".csv"))
      if (nrow(parsed) > 0) write.csv(parsed, csv_file, row.names = FALSE)

    } else {
      parsed <- parse_match_history(ocr_text, verbose = verbose)
      items <- nrow(parsed)

      # Save updated parsed CSV
      csv_name <- gsub("_match$", "", name_base)
      csv_file <- file.path(RESULTS_DIR, "match_history_parsed", paste0(csv_name, ".csv"))
      if (nrow(parsed) > 0) write.csv(parsed, csv_file, row.names = FALSE)
    }

    message("    -> ", items, " items parsed")

    results[[length(results) + 1]] <- list(
      filename = filename,
      type = type,
      items = items,
      data = parsed
    )
  }

  message("\n", strrep("=", 60))
  message("Re-test complete. Check updated CSVs in results/ folders.")
  message(strrep("=", 60), "\n")

  invisible(results)
}

#' Interactively review flagged screenshots
review_flagged <- function() {
  flagged_dir <- file.path(RESULTS_DIR, "flagged")
  flagged_files <- get_images(flagged_dir)

  if (length(flagged_files) == 0) {
    message("No flagged files to review!")
    return(invisible(NULL))
  }

  # Load summary for warnings
  summary_file <- file.path(RESULTS_DIR, "summary.csv")
  if (file.exists(summary_file)) {
    summary_df <- read.csv(summary_file, stringsAsFactors = FALSE)
  } else {
    summary_df <- NULL
  }

  message("\n", strrep("=", 60))
  message("REVIEWING FLAGGED SCREENSHOTS")
  message(strrep("=", 60))
  message("Files to review: ", length(flagged_files))
  message("Commands: [n]ext, [p]rev, [s]how ocr, [r]eparse, [q]uit")
  message(strrep("=", 60), "\n")

  idx <- 1
  while (idx >= 1 && idx <= length(flagged_files)) {
    f <- flagged_files[idx]
    filename <- basename(f)
    name_base <- tools::file_path_sans_ext(filename)

    # Get warning from summary
    warning_msg <- ""
    if (!is.null(summary_df)) {
      row <- summary_df[summary_df$filename == filename, ]
      if (nrow(row) > 0) warning_msg <- row$warnings[1]
    }

    message("\n[", idx, "/", length(flagged_files), "] ", filename)
    message("Warning: ", warning_msg)

    # Find OCR text file
    ocr_file_standings <- file.path(RESULTS_DIR, "ocr_text", paste0(name_base, "_standings.txt"))
    ocr_file_match <- file.path(RESULTS_DIR, "ocr_text", paste0(name_base, "_match.txt"))
    ocr_file <- if (file.exists(ocr_file_standings)) ocr_file_standings else ocr_file_match

    cmd <- readline("Command ([n]ext/[p]rev/[s]how/[r]eparse/[q]uit): ")

    if (cmd == "q" || cmd == "quit") {
      break
    } else if (cmd == "n" || cmd == "next" || cmd == "") {
      idx <- idx + 1
    } else if (cmd == "p" || cmd == "prev") {
      idx <- max(1, idx - 1)
    } else if (cmd == "s" || cmd == "show") {
      if (file.exists(ocr_file)) {
        ocr_text <- paste(readLines(ocr_file, warn = FALSE), collapse = "\n")
        message("\n--- OCR TEXT ---")
        cat(ocr_text)
        message("\n--- END OCR ---\n")
      } else {
        message("OCR text file not found")
      }
    } else if (cmd == "r" || cmd == "reparse") {
      if (file.exists(ocr_file)) {
        ocr_text <- paste(readLines(ocr_file, warn = FALSE), collapse = "\n")
        if (grepl("_standings", ocr_file)) {
          message("\nRe-parsing as STANDINGS...")
          parsed <- parse_tournament_standings(ocr_text, verbose = TRUE)
        } else {
          message("\nRe-parsing as MATCH HISTORY...")
          parsed <- parse_match_history(ocr_text, verbose = TRUE)
        }
        message("\nParsed ", nrow(parsed), " items:")
        print(parsed)
      } else {
        message("OCR text file not found")
      }
    }
  }

  message("\nReview complete.")
}

# Print usage when sourced
if (interactive()) {
  message("\n", strrep("=", 60))
  message("Batch OCR Test Script Loaded")
  message(strrep("=", 60))
  message("\nFolder structure:")
  message("  screenshots/standings/      <- Tournament standings screenshots")
  message("  screenshots/standings/*/    <- Test folders with expected.csv")
  message("  screenshots/match_history/  <- Match history screenshots")
  message("\nCommands:")
  message("  batch_test()           - Process all screenshots (calls API)")
  message("  batch_retest()         - Re-parse saved OCR text (no API)")
  message("  batch_test_folders()   - Process all test folders (calls API)")
  message("  batch_retest_folders() - Re-parse saved data (no API)")
  message("  review_flagged()       - Interactively review problem files")
  message(strrep("=", 60), "\n")
}
