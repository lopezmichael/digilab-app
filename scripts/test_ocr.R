# scripts/test_ocr.R
# Interactive OCR testing without running Shiny app
#
# Usage from R console:
#   source("scripts/test_ocr.R")
#   test_image("path/to/screenshot.png")
#   test_parse(ocr_text, rounds = 4)
#
# Or from terminal:
#   Rscript scripts/test_ocr.R path/to/screenshot.png

library(dotenv)
if (file.exists(".env")) load_dot_env(".env")

source("R/ocr.R")

# Store last OCR text globally for easy re-testing
.last_ocr_text <- NULL
.last_ocr_type <- NULL  # "standings" or "match_history"

#' Format results as they appear in the Submit Results UI preview
#'
#' @param results Data frame from parse_tournament_standings()
#' @return Formatted data frame matching UI display
format_ui_preview <- function(results) {
  if (is.null(results) || nrow(results) == 0) {
    return(data.frame())
  }

  data.frame(
    `#` = results$placement,
    Player = results$username,
    `Member#` = sapply(results$member_number, function(m) {
      if (!is.null(m) && !is.na(m) && nchar(m) >= 4) {
        paste0("...", substr(m, nchar(m) - 3, nchar(m)))
      } else {
        "-"
      }
    }),
    Points = results$points,
    `W-L-T` = paste0(results$wins, "-", results$losses, "-", results$ties),
    Deck = "[UNKNOWN]",
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}

#' Test OCR on an image file (calls Google Cloud Vision API)
#'
#' @param image_path Path to screenshot image
#' @param rounds Total rounds in tournament (for W-L-T calculation)
#' @param verbose Print debug messages
#' @return Parsed results data frame
test_image <- function(image_path, rounds = 4, verbose = TRUE) {
  if (!file.exists(image_path)) {
    stop("File not found: ", image_path)
  }

  message("\n", strrep("=", 60))
  message("Testing OCR on: ", image_path)
  message(strrep("=", 60), "\n")

  # Step 1: Get raw OCR text
  ocr_result <- gcv_detect_text(image_path, verbose = verbose)

  if (is.null(ocr_result)) {
    message("\nOCR failed - check API key and image")
    return(NULL)
  }

  # Extract text from structured result (backward compatible with plain string)
  ocr_text <- if (is.list(ocr_result)) ocr_result$text else ocr_result

  # Save globally for easy re-testing
  assign(".last_ocr_text", ocr_text, envir = globalenv())
  assign(".last_ocr_result", ocr_result, envir = globalenv())

  # Show annotation count
  if (is.list(ocr_result) && !is.null(ocr_result$annotations) && nrow(ocr_result$annotations) > 0) {
    message("\nAnnotations: ", nrow(ocr_result$annotations), " words")
    message("Image dimensions: ", ocr_result$image_width, "x", ocr_result$image_height)
  }

  # Save raw OCR text for debugging
  message("\n", strrep("-", 60))
  message("RAW OCR TEXT:")
  message(strrep("-", 60))
  cat(ocr_text)
  message("\n")

  # Step 2: Parse the text
  message(strrep("-", 60))
  message("PARSING RESULTS:")
  message(strrep("-", 60), "\n")

  results <- parse_standings(ocr_result, total_rounds = rounds, verbose = verbose)

  # Step 3: Show raw parsed data
  message("\n", strrep("-", 60))
  message("RAW PARSED DATA (", nrow(results), " players):")
  message(strrep("-", 60))
  if (nrow(results) > 0) {
    print(results)
  } else {
    message("No results parsed!")
  }

  # Step 4: Show UI preview format
  message("\n", strrep("=", 60))
  message("UI PREVIEW (as shown in Submit Results):")
  message(strrep("=", 60))
  if (nrow(results) > 0) {
    ui_preview <- format_ui_preview(results)
    print(ui_preview, row.names = FALSE)
  } else {
    message("No results to display")
  }

  # Save OCR text to file for re-testing
  temp_file <- file.path(dirname(image_path), paste0("ocr_", tools::file_path_sans_ext(basename(image_path)), ".txt"))
  writeLines(ocr_text, temp_file)
  message("\n", strrep("-", 60))
  message("OCR text saved to: ", temp_file)
  message("\nTo re-test parsing without API call:")
  message("  test_parse(.last_ocr_text)")
  message("  # or")
  message("  test_parse_file('", temp_file, "')")

  invisible(results)
}

#' Test just the parser on raw OCR text (no API call)
#'
#' @param ocr_text Raw OCR text string
#' @param rounds Total rounds in tournament
#' @param verbose Print debug messages
#' @return Parsed results data frame
test_parse <- function(ocr_text, rounds = 4, verbose = TRUE) {
  message("\n", strrep("=", 60))
  message("Testing parser on provided text")
  message(strrep("=", 60), "\n")

  results <- parse_tournament_standings(ocr_text, total_rounds = rounds, verbose = verbose)

  # Show raw parsed data
  message("\n", strrep("-", 60))
  message("RAW PARSED DATA (", nrow(results), " players):")
  message(strrep("-", 60))
  if (nrow(results) > 0) {
    print(results)
  } else {
    message("No results parsed!")
  }

  # Show UI preview format
  message("\n", strrep("=", 60))
  message("UI PREVIEW (as shown in Submit Results):")
  message(strrep("=", 60))
  if (nrow(results) > 0) {
    ui_preview <- format_ui_preview(results)
    print(ui_preview, row.names = FALSE)
  } else {
    message("No results to display")
  }

  invisible(results)
}

#' Test parser from a saved OCR text file
#'
#' @param file_path Path to saved OCR text file
#' @param rounds Total rounds in tournament
#' @param verbose Print debug messages
#' @return Parsed results data frame
test_parse_file <- function(file_path, rounds = 4, verbose = TRUE) {
  if (!file.exists(file_path)) {
    stop("File not found: ", file_path)
  }
  ocr_text <- paste(readLines(file_path, warn = FALSE), collapse = "\n")
  test_parse(ocr_text, rounds = rounds, verbose = verbose)
}

#' Quick test with sample OCR text
test_sample <- function() {
  sample_text <- "Ranking
User Name
Win
OMW
GW
Points
1
TestPlayer
12
50%
60%
Member Number 0000123456
2
AnotherUser
9
45%
55%
Member Number 0000789012"

  message("Testing with sample OCR text...")
  test_parse(sample_text, rounds = 4)
}

#' Re-test last OCR text (convenience function)
retest <- function(rounds = 4, verbose = TRUE) {
  if (is.null(.last_ocr_text)) {
    stop("No previous OCR text. Run test_image() first.")
  }
  if (!is.null(.last_ocr_type) && .last_ocr_type == "match_history") {
    test_parse_matches(.last_ocr_text, verbose = verbose)
  } else {
    # Use orchestrator if full result available, otherwise text parser
    if (exists(".last_ocr_result", envir = globalenv())) {
      ocr_result <- get(".last_ocr_result", envir = globalenv())
      result <- parse_standings(ocr_result, total_rounds = rounds, verbose = verbose)
    } else {
      result <- parse_tournament_standings(.last_ocr_text, total_rounds = rounds, verbose = verbose)
    }

    # Show raw parsed data
    message("\n", strrep("-", 60))
    message("RAW PARSED DATA (", nrow(result), " players):")
    message(strrep("-", 60))
    if (nrow(result) > 0) {
      print(result)
    } else {
      message("No results parsed!")
    }

    # Show UI preview format
    message("\n", strrep("=", 60))
    message("UI PREVIEW (as shown in Submit Results):")
    message(strrep("=", 60))
    if (nrow(result) > 0) {
      ui_preview <- format_ui_preview(result)
      print(ui_preview, row.names = FALSE)
    } else {
      message("No results to display")
    }

    invisible(result)
  }
}

#' Compare layout vs text parser on last OCR result
#'
#' Shows side-by-side output from both parsers for debugging.
#' Run test_image() first to populate the saved OCR result.
#'
#' @param rounds Total rounds
#' @param verbose Print debug messages
test_compare <- function(rounds = 4, verbose = TRUE) {
  if (!exists(".last_ocr_result", envir = globalenv())) {
    message("No saved OCR result. Run test_image() first.")
    return(invisible(NULL))
  }

  ocr_result <- get(".last_ocr_result", envir = globalenv())
  if (is.null(ocr_result)) {
    message("Saved OCR result is NULL. Run test_image() first.")
    return(invisible(NULL))
  }

  ocr_text <- if (is.list(ocr_result)) ocr_result$text else ocr_result

  message("\n", strrep("=", 60))
  message("LAYOUT PARSER:")
  message(strrep("=", 60))

  if (is.list(ocr_result) && !is.null(ocr_result$annotations) && nrow(ocr_result$annotations) > 0) {
    layout_result <- tryCatch({
      parse_standings_layout(
        ocr_result$annotations, ocr_result$image_width, ocr_result$image_height,
        total_rounds = rounds, verbose = verbose
      )
    }, error = function(e) {
      message("Layout parser error: ", e$message)
      data.frame()
    })

    if (nrow(layout_result) > 0) {
      message("\n", nrow(layout_result), " players found:")
      print(format_ui_preview(layout_result))
    } else {
      message("No results from layout parser")
    }
  } else {
    message("No annotation data available")
  }

  message("\n", strrep("=", 60))
  message("TEXT PARSER:")
  message(strrep("=", 60))

  text_result <- tryCatch({
    parse_tournament_standings(ocr_text, total_rounds = rounds, verbose = verbose)
  }, error = function(e) {
    message("Text parser error: ", e$message)
    data.frame()
  })

  if (nrow(text_result) > 0) {
    message("\n", nrow(text_result), " players found:")
    print(format_ui_preview(text_result))
  } else {
    message("No results from text parser")
  }

  invisible(list(layout = if (exists("layout_result", inherits = FALSE)) layout_result else NULL,
                 text = text_result))
}

# =============================================================================
# MATCH HISTORY TESTING
# =============================================================================

#' Format match history results as they would appear in UI
#'
#' @param results Data frame from parse_match_history()
#' @return Formatted data frame
format_match_history_preview <- function(results) {
  if (is.null(results) || nrow(results) == 0) {
    return(data.frame())
  }

  data.frame(
    Round = results$round,
    Opponent = results$opponent_username,
    `Member#` = sapply(results$opponent_member_number, function(m) {
      if (!is.null(m) && !is.na(m) && nchar(m) >= 4) {
        paste0("...", substr(m, nchar(m) - 3, nchar(m)))
      } else {
        "-"
      }
    }),
    Result = paste0(results$games_won, "-", results$games_lost, "-", results$games_tied),
    Points = results$match_points,
    Outcome = ifelse(results$match_points == 3, "WIN",
                     ifelse(results$match_points == 1, "DRAW", "LOSS")),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
}

#' Test OCR on a match history screenshot (calls API)
#'
#' @param image_path Path to screenshot image
#' @param verbose Print debug messages
#' @return Parsed results data frame
test_match_history <- function(image_path, verbose = TRUE) {
  if (!file.exists(image_path)) {
    stop("File not found: ", image_path)
  }

  message("\n", strrep("=", 60))
  message("Testing MATCH HISTORY OCR on: ", image_path)
  message(strrep("=", 60), "\n")

  # Step 1: Get raw OCR text
  ocr_result <- gcv_detect_text(image_path, verbose = verbose)

  if (is.null(ocr_result)) {
    message("\nOCR failed - check API key and image")
    return(NULL)
  }

  # Extract text from structured result (backward compatible with plain string)
  ocr_text <- if (is.list(ocr_result)) ocr_result$text else ocr_result

  # Save globally for easy re-testing
  assign(".last_ocr_text", ocr_text, envir = globalenv())
  assign(".last_ocr_result", ocr_result, envir = globalenv())
  assign(".last_ocr_type", "match_history", envir = globalenv())

  # Save raw OCR text for debugging
  message("\n", strrep("-", 60))
  message("RAW OCR TEXT:")
  message(strrep("-", 60))
  cat(ocr_text)
  message("\n")

  # Step 2: Parse the text
  message(strrep("-", 60))
  message("PARSING MATCH HISTORY:")
  message(strrep("-", 60), "\n")

  results <- parse_match_history(ocr_text, verbose = verbose)

  # Step 3: Show raw parsed data
  message("\n", strrep("-", 60))
  message("RAW PARSED DATA (", nrow(results), " rounds):")
  message(strrep("-", 60))
  if (nrow(results) > 0) {
    print(results)
  } else {
    message("No results parsed!")
  }

  # Step 4: Show UI preview format
  message("\n", strrep("=", 60))
  message("UI PREVIEW (Match History):")
  message(strrep("=", 60))
  if (nrow(results) > 0) {
    ui_preview <- format_match_history_preview(results)
    print(ui_preview, row.names = FALSE)
  } else {
    message("No results to display")
  }

  # Save OCR text to file
  temp_file <- file.path(dirname(image_path), paste0("ocr_match_", tools::file_path_sans_ext(basename(image_path)), ".txt"))
  writeLines(ocr_text, temp_file)
  message("\n", strrep("-", 60))
  message("OCR text saved to: ", temp_file)
  message("\nTo re-test parsing without API call:")
  message("  test_parse_matches(.last_ocr_text)")

  invisible(results)
}

#' Test just the match history parser on raw OCR text (no API call)
#'
#' @param ocr_text Raw OCR text string
#' @param verbose Print debug messages
#' @return Parsed results data frame
test_parse_matches <- function(ocr_text, verbose = TRUE) {
  message("\n", strrep("=", 60))
  message("Testing MATCH HISTORY parser")
  message(strrep("=", 60), "\n")

  results <- parse_match_history(ocr_text, verbose = verbose)

  # Show raw parsed data
  message("\n", strrep("-", 60))
  message("RAW PARSED DATA (", nrow(results), " rounds):")
  message(strrep("-", 60))
  if (nrow(results) > 0) {
    print(results)
  } else {
    message("No results parsed!")
  }

  # Show UI preview format
  message("\n", strrep("=", 60))
  message("UI PREVIEW (Match History):")
  message(strrep("=", 60))
  if (nrow(results) > 0) {
    ui_preview <- format_match_history_preview(results)
    print(ui_preview, row.names = FALSE)
  } else {
    message("No results to display")
  }

  invisible(results)
}

# If run from command line with image path argument
if (!interactive()) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) >= 1) {
    rounds <- if (length(args) >= 2) as.integer(args[2]) else 4
    test_image(args[1], rounds = rounds)
  } else {
    message("Usage: Rscript scripts/test_ocr.R <image_path> [rounds]")
    message("\nOr in R console:")
    message("  source('scripts/test_ocr.R')")
    message("  test_image('path/to/screenshot.png')")
    message("  test_parse(ocr_text)")
    message("  test_sample()  # quick test with fake data")
  }
} else {
  # Print usage when sourced in interactive mode
  message("\n", strrep("=", 60))
  message("OCR Test Script Loaded")
  message(strrep("=", 60))
  message("\nTOURNAMENT STANDINGS:")
  message("  test_image(path)      - Full OCR flow (calls API)")
  message("  test_parse(text)      - Test parser only (no API)")
  message("  test_parse_file(path) - Test parser from saved file")
  message("  test_sample()         - Quick test with fake data")
  message("\nMATCH HISTORY:")
  message("  test_match_history(path)  - Full OCR flow (calls API)")
  message("  test_parse_matches(text)  - Test parser only (no API)")
  message("\nCOMMON:")
  message("  retest()              - Re-run parser on last OCR text")
  message("  test_compare()        - Compare layout vs text parser")
  message("\nWorkflow:")
  message("  1. test_image('screenshot.png')  # or test_match_history()")
  message("  2. Edit R/ocr.R parser logic")
  message("  3. source('R/ocr.R'); retest()   # re-test without API")
  message("  4. Repeat steps 2-3 until happy")
  message(strrep("=", 60), "\n")
}
