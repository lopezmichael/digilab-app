# scripts/batch_test_ocr.R
# Batch OCR testing for multiple screenshots
#
# Usage:
#   source("scripts/batch_test_ocr.R")
#   batch_test()                    # Process all screenshots, call API
#   batch_retest()                  # Re-parse saved OCR text (no API)
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
  message("  screenshots/match_history/  <- Match history screenshots")
  message("\nCommands:")
  message("  batch_test()      - Process all screenshots (calls API)")
  message("  batch_retest()    - Re-parse saved OCR text (no API)")
  message("  review_flagged()  - Interactively review problem files")
  message(strrep("=", 60), "\n")
}
