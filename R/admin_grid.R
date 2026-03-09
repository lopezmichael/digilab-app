# =============================================================================
# Shared Admin Grid Module
# Reusable grid rendering, input sync, and helper functions for both
# Enter Results (admin-results-server.R) and Edit Tournaments grid.
# =============================================================================

# -----------------------------------------------------------------------------
# get_store_scene_id: Get the scene_id for a given store
# Used for scene-scoped player matching
# -----------------------------------------------------------------------------
get_store_scene_id <- function(store_id, con) {
  if (is.null(store_id) || is.na(store_id)) return(NULL)
  result <- safe_query_impl(con, "SELECT scene_id FROM stores WHERE store_id = $1", params = list(store_id), default = data.frame(scene_id = NA))
  if (nrow(result) == 0 || is.na(result$scene_id[1])) return(NULL)
  result$scene_id[1]
}

# -----------------------------------------------------------------------------
# grid_ordinal: Convert number to ordinal (1st, 2nd, 3rd, etc.)
# -----------------------------------------------------------------------------
grid_ordinal <- function(n) {
  suffix <- c("th", "st", "nd", "rd", rep("th", 6))
  if (n %% 100 >= 11 && n %% 100 <= 13) return(paste0(n, "th"))
  paste0(n, suffix[(n %% 10) + 1])
}

# -----------------------------------------------------------------------------
# init_grid_data: Create blank grid data frame for N players
# -----------------------------------------------------------------------------
init_grid_data <- function(player_count) {
  data.frame(
    placement = seq_len(player_count),
    player_name = rep("", player_count),
    member_number = rep("", player_count),
    points = rep(0L, player_count),
    wins = rep(0L, player_count),
    losses = rep(0L, player_count),
    ties = rep(0L, player_count),
    deck_id = rep(NA_integer_, player_count),
    match_status = rep("", player_count),
    matched_player_id = rep(NA_integer_, player_count),
    matched_member_number = rep(NA_character_, player_count),
    result_id = rep(NA_integer_, player_count),
    stringsAsFactors = FALSE
  )
}

# -----------------------------------------------------------------------------
# load_grid_from_results: Load existing tournament results into a grid
# Queries results + players tables. Returns pre-filled grid data frame.
# All loaded rows get match_status = "matched" since they come from known players.
# Points calculated as (wins * 3) + ties.
# -----------------------------------------------------------------------------
load_grid_from_results <- function(tournament_id, con) {
  rows <- safe_query_impl(con, "
    SELECT r.result_id, r.placement, r.player_id, p.display_name,
           r.wins, r.losses, r.ties, r.points, r.archetype_id,
           p.member_number
    FROM results r
    JOIN players p ON r.player_id = p.player_id
    WHERE r.tournament_id = $1
    ORDER BY r.placement ASC
  ", params = list(tournament_id))

  if (nrow(rows) == 0) {
    return(init_grid_data(0))
  }
  data.frame(
    placement = rows$placement,
    player_name = rows$display_name,
    member_number = ifelse(is.na(rows$member_number), "", rows$member_number),
    points = ifelse(!is.na(rows$points), as.integer(rows$points), as.integer((rows$wins * 3L) + rows$ties)),
    wins = as.integer(rows$wins),
    losses = as.integer(rows$losses),
    ties = as.integer(rows$ties),
    deck_id = as.integer(rows$archetype_id),
    match_status = rep("matched", nrow(rows)),
    matched_player_id = as.integer(rows$player_id),
    matched_member_number = as.character(rows$member_number),
    result_id = as.integer(rows$result_id),
    stringsAsFactors = FALSE
  )
}

# -----------------------------------------------------------------------------
# sync_grid_inputs: Read current Shiny input values into the grid data frame
# Returns updated data frame. Does NOT modify any reactive -- caller does that.
# Parameters:
#   input         - Shiny input object
#   grid_data     - Current grid data frame
#   record_format - "points" or "wlt"
#   prefix        - Input ID prefix (e.g., "admin_" or "edit_")
# -----------------------------------------------------------------------------
sync_grid_inputs <- function(input, grid_data, record_format, prefix) {
  if (is.null(grid_data) || nrow(grid_data) == 0) return(grid_data)

  for (i in seq_len(nrow(grid_data))) {
    player_val <- input[[paste0(prefix, "player_", i)]]
    if (!is.null(player_val)) grid_data$player_name[i] <- player_val
    member_val <- input[[paste0(prefix, "member_", i)]]
    if (!is.null(member_val)) grid_data$member_number[i] <- member_val

    if (record_format == "points") {
      pts_val <- input[[paste0(prefix, "pts_", i)]]
      if (!is.null(pts_val) && !is.na(pts_val)) grid_data$points[i] <- as.integer(pts_val)
    } else {
      w_val <- input[[paste0(prefix, "w_", i)]]
      if (!is.null(w_val) && !is.na(w_val)) grid_data$wins[i] <- as.integer(w_val)
      l_val <- input[[paste0(prefix, "l_", i)]]
      if (!is.null(l_val) && !is.na(l_val)) grid_data$losses[i] <- as.integer(l_val)
      t_val <- input[[paste0(prefix, "t_", i)]]
      if (!is.null(t_val) && !is.na(t_val)) grid_data$ties[i] <- as.integer(t_val)
    }

    deck_val <- input[[paste0(prefix, "deck_", i)]]
    if (!is.null(deck_val) && nchar(deck_val) > 0 &&
        deck_val != "__REQUEST_NEW__" && !grepl("^pending_", deck_val)) {
      grid_data$deck_id[i] <- as.integer(deck_val)
    }
  }

  grid_data
}

# -----------------------------------------------------------------------------
# render_grid_ui: Generate the full grid UI (header + data rows)
# Parameters:
#   grid_data       - Grid data frame
#   record_format   - "points" or "wlt"
#   is_release      - TRUE if release event (hides deck column)
#   deck_choices    - Named character vector for deck selectInput
#   player_matches  - Named list of match info per row index
#   prefix          - Input ID prefix (e.g., "admin_" or "edit_")
# Returns: tagList with optional release notice, header row, and data rows
# -----------------------------------------------------------------------------
render_grid_ui <- function(grid_data, record_format, is_release, deck_choices,
                           player_matches, prefix, mode = "entry", ocr_rows = NULL) {
  # Column widths depend on format and release event
  if (is_release) {
    if (record_format == "points") {
      col_widths <- c(1, 1, 6, 2, 2)
    } else {
      col_widths <- c(1, 1, 4, 2, 2, 1, 1)
    }
  } else {
    if (record_format == "points") {
      col_widths <- c(1, 1, 3, 2, 2, 3)
    } else {
      col_widths <- c(1, 1, 2, 2, 1, 1, 1, 3)
    }
  }

  # Header row
  if (is_release) {
    if (record_format == "points") {
      header <- layout_columns(col_widths = col_widths, class = "results-header-row",
                               div(""), div("#"), div("Player"), div("Member #"), div("Pts"))
    } else {
      header <- layout_columns(col_widths = col_widths, class = "results-header-row",
                               div(""), div("#"), div("Player"), div("Member #"), div("W"), div("L"), div("T"))
    }
  } else {
    if (record_format == "points") {
      header <- layout_columns(col_widths = col_widths, class = "results-header-row",
                               div(""), div("#"), div("Player"), div("Member #"), div("Pts"), div("Deck"))
    } else {
      header <- layout_columns(col_widths = col_widths, class = "results-header-row",
                               div(""), div("#"), div("Player"), div("Member #"), div("W"), div("L"), div("T"), div("Deck"))
    }
  }

  # Release event info notice
  release_notice <- if (is_release) {
    div(class = "alert alert-info py-2 px-3 mb-3",
        bsicons::bs_icon("info-circle"),
        " Release event — deck archetype auto-set to UNKNOWN.")
  } else {
    NULL
  }

  # Data rows
  rows <- lapply(seq_len(nrow(grid_data)), function(i) {
    row <- grid_data[i, ]
    place_class <- if (i == 1) "place-1st" else if (i == 2) "place-2nd" else if (i == 3) "place-3rd" else ""

    # Row CSS class — add ocr-populated for review mode
    row_class <- "upload-result-row"
    if (mode == "review" && !is.null(ocr_rows) && i %in% ocr_rows) {
      row_class <- "upload-result-row grid-row ocr-populated"
    } else if (mode == "review") {
      row_class <- "upload-result-row grid-row"
    }

    # Player match badge
    match_info <- player_matches[[as.character(i)]]
    match_badge <- if (!is.null(match_info)) {
      if (match_info$status == "matched") {
        member_text <- if (!is.na(match_info$member_number) && nchar(match_info$member_number) > 0) {
          paste0("#", match_info$member_number)
        } else {
          "(no member #)"
        }
        div(class = "player-match-indicator matched",
            bsicons::bs_icon("check-circle-fill"),
            span(class = "match-label", paste0("Matched ", member_text)))
      } else if (match_info$status == "new") {
        div(class = "player-match-indicator new",
            bsicons::bs_icon("person-plus-fill"),
            span(class = "match-label", "New player"))
      } else {
        NULL
      }
    } else {
      NULL
    }

    # Delete button
    delete_btn <- div(
      class = "upload-result-delete",
      htmltools::tags$button(
        onclick = sprintf("Shiny.setInputValue('%sdelete_row', %d, {priority: 'event'})", prefix, i),
        class = "btn btn-sm btn-outline-danger p-0 result-action-btn",
        title = "Remove row",
        shiny::icon("xmark")
      )
    )

    # Placement column
    placement_col <- div(
      class = "upload-result-placement",
      span(class = paste("placement-badge", place_class), grid_ordinal(row$placement)),
      match_badge
    )

    # Player name input
    player_col <- div(
      textInput(paste0(prefix, "player_", i), NULL, value = row$player_name)
    )

    # Member number input
    member_col <- div(
      textInput(paste0(prefix, "member_", i), NULL,
                value = if (!is.na(row$member_number)) row$member_number else "",
                placeholder = "0000...")
    )

    # Build row based on format and release event
    if (is_release) {
      if (record_format == "points") {
        pts_col <- div(numericInput(paste0(prefix, "pts_", i), NULL, value = row$points, min = 0, max = 99))
        layout_columns(col_widths = col_widths, class = row_class,
                       delete_btn, placement_col, player_col, member_col, pts_col)
      } else {
        w_col <- div(numericInput(paste0(prefix, "w_", i), NULL, value = row$wins, min = 0))
        l_col <- div(numericInput(paste0(prefix, "l_", i), NULL, value = row$losses, min = 0))
        t_col <- div(numericInput(paste0(prefix, "t_", i), NULL, value = row$ties, min = 0))
        layout_columns(col_widths = col_widths, class = row_class,
                       delete_btn, placement_col, player_col, member_col, w_col, l_col, t_col)
      }
    } else {
      current_deck <- if (!is.na(row$deck_id)) as.character(row$deck_id) else ""
      deck_col <- div(
        selectizeInput(paste0(prefix, "deck_", i), NULL,
                       choices = deck_choices, selected = current_deck,
                       options = list(placeholder = "Search deck..."))
      )

      if (record_format == "points") {
        pts_col <- div(numericInput(paste0(prefix, "pts_", i), NULL, value = row$points, min = 0, max = 99))
        layout_columns(col_widths = col_widths, class = row_class,
                       delete_btn, placement_col, player_col, member_col, pts_col, deck_col)
      } else {
        w_col <- div(numericInput(paste0(prefix, "w_", i), NULL, value = row$wins, min = 0))
        l_col <- div(numericInput(paste0(prefix, "l_", i), NULL, value = row$losses, min = 0))
        t_col <- div(numericInput(paste0(prefix, "t_", i), NULL, value = row$ties, min = 0))
        layout_columns(col_widths = col_widths, class = row_class,
                       delete_btn, placement_col, player_col, member_col, w_col, l_col, t_col, deck_col)
      }
    }
  })

  tagList(release_notice, header, rows)
}

# -----------------------------------------------------------------------------
# validate_decklist_url: Sanitize and validate decklist URLs
# Only allows https:// URLs from approved deckbuilder domains.
# Returns trimmed URL or NULL if invalid.
# -----------------------------------------------------------------------------
ALLOWED_DECKLIST_DOMAINS <- c(
  "digimoncard.dev",
  "digimoncard.io",
  "digimoncard.app",
  "digimonmeta.com",
  "digitalgateopen.com",
  "limitlesstcg.com",
  "play.limitlesstcg.com",
  "my.limitlesstcg.com",
  "tcgstacked.com"
)

validate_decklist_url <- function(url) {
  if (is.null(url) || is.na(url)) return(NULL)
  url <- trimws(url)
  if (nchar(url) == 0) return(NULL)
  if (!grepl("^https://", url, ignore.case = TRUE)) return(NULL)
  if (grepl("[<>\\s\"]", url, perl = TRUE)) return(NULL)
  # Extract domain and check against allowlist
  domain <- sub("^https://([^/]+).*$", "\\1", url, ignore.case = TRUE)
  domain <- tolower(sub("^www\\.", "", domain))
  if (!domain %in% ALLOWED_DECKLIST_DOMAINS) return(NULL)
  url
}

# -----------------------------------------------------------------------------
# save_decklist_urls: Shared save logic for decklist URL inputs
# Used by all three entry flows (admin, submit, edit).
# Parameters:
#   results_df - Data frame with result_id column
#   input      - Shiny input object
#   prefix     - Input ID prefix (e.g., "admin_decklist_")
#   db_pool    - Database connection pool
# Returns: number of URLs saved
# -----------------------------------------------------------------------------
save_decklist_urls <- function(results_df, input, prefix, db_pool) {
  saved <- 0L
  skipped <- 0L
  for (i in seq_len(nrow(results_df))) {
    url_raw <- input[[paste0(prefix, i)]]
    if (!is.null(url_raw) && nchar(trimws(url_raw)) > 0) {
      url_val <- validate_decklist_url(url_raw)
      if (!is.null(url_val)) {
        safe_execute(db_pool, "UPDATE results SET decklist_url = $1, updated_at = CURRENT_TIMESTAMP WHERE result_id = $2",
                     params = list(url_val, results_df$result_id[i]))
        saved <- saved + 1L
      } else {
        skipped <- skipped + 1L
      }
    }
  }
  if (skipped > 0) {
    notify(sprintf("%d invalid URL%s skipped — only links from approved deckbuilders are accepted.",
                   skipped, if (skipped == 1) "" else "s"), type = "warning")
  }
  saved
}

# -----------------------------------------------------------------------------
# render_decklist_entry: Post-submission confirmation screen with decklist URL inputs
# Shows submitted results (placement, player, deck, record) with a URL field per row.
# Parameters:
#   results_df  - Data frame with result_id, placement, player_name, deck_name, record
#   prefix      - Input ID prefix (e.g., "admin_decklist_", "submit_decklist_", "edit_decklist_")
# Returns: tagList with header, result rows (read-only + URL input), and action buttons
# -----------------------------------------------------------------------------
render_decklist_entry <- function(results_df, prefix) {
  if (is.null(results_df) || nrow(results_df) == 0) {
    return(div(class = "text-muted text-center py-4", "No results to show."))
  }

  tips <- div(
    class = "alert alert-info d-flex mb-3 py-2",
    bsicons::bs_icon("link-45deg", class = "me-2 flex-shrink-0", size = "1.2em"),
    div(
      div(
        "Paste decklist URLs from supported sites: ",
        tags$strong("digimoncard.io"), ", ",
        tags$strong("digimoncard.dev"), ", ",
        tags$strong("digimoncard.app"), ", ",
        tags$strong("digimonmeta.com"), ", ",
        tags$strong("digitalgateopen.com"), ", ",
        tags$strong("limitlesstcg.com"), ", or ",
        tags$strong("tcgstacked.com"), "."
      ),
      tags$small(
        class = "text-muted",
        "Want to use a different deckbuilder? Let us know in the Discord."
      )
    )
  )

  header <- layout_columns(
    col_widths = c(1, 3, 2, 2, 4),
    class = "results-header-row",
    div("#"), div("Player"), div("Deck"), div("Record"), div("Decklist URL")
  )

  rows <- lapply(seq_len(nrow(results_df)), function(i) {
    row <- results_df[i, ]
    place_class <- if (row$placement == 1) "place-1st" else if (row$placement == 2) "place-2nd" else if (row$placement == 3) "place-3rd" else ""

    layout_columns(
      col_widths = c(1, 3, 2, 2, 4),
      class = "upload-result-row decklist-entry-row",
      div(span(class = paste("placement-badge", place_class), grid_ordinal(row$placement))),
      div(class = "fw-medium", row$player_name),
      div(class = "text-muted small", if (!is.na(row$deck_name) && row$deck_name != "UNKNOWN") row$deck_name else "-"),
      div(class = "text-muted small", row$record),
      div(textInput(paste0(prefix, i), NULL,
                    value = if (!is.na(row$decklist_url)) row$decklist_url else "",
                    placeholder = "https://..."))
    )
  })

  tagList(tips, header, rows)
}

# -----------------------------------------------------------------------------
# parse_paste_data: Parse pasted spreadsheet text into structured row data
# Splits by newlines, then by tabs (fallback: 2+ spaces).
# Supported formats:
#   1 column  - names only
#   2 columns - names + points
#   3 columns - names + points + deck
#   4 columns - names + W/L/T
#   5+ columns - names + W/L/T + deck
# Returns list of lists with name/points/wins/losses/ties/deck_id
# -----------------------------------------------------------------------------
parse_paste_data <- function(text, all_decks) {
  lines <- strsplit(text, "\n")[[1]]
  lines <- lines[nchar(trimws(lines)) > 0]

  if (length(lines) == 0) return(list())

  lapply(lines, function(line) {
    parts <- strsplit(line, "\t")[[1]]
    if (length(parts) == 1) {
      parts <- strsplit(trimws(line), "\\s{2,}")[[1]]
    }
    parts <- trimws(parts)

    name <- parts[1]
    pts <- 0L
    w <- 0L
    l <- 0L
    t_val <- 0L
    deck_name <- ""

    if (length(parts) == 2) {
      # Name + Points
      pts <- suppressWarnings(as.integer(parts[2]))
      if (is.na(pts)) pts <- 0L
    } else if (length(parts) == 3) {
      # Name + Points + Deck
      pts <- suppressWarnings(as.integer(parts[2]))
      if (is.na(pts)) pts <- 0L
      deck_name <- parts[3]
    } else if (length(parts) == 4) {
      # Name + W + L + T
      w <- suppressWarnings(as.integer(parts[2]))
      l <- suppressWarnings(as.integer(parts[3]))
      t_val <- suppressWarnings(as.integer(parts[4]))
      if (is.na(w)) w <- 0L
      if (is.na(l)) l <- 0L
      if (is.na(t_val)) t_val <- 0L
      pts <- w * 3L + t_val
    } else if (length(parts) >= 5) {
      # Name + W + L + T + Deck
      w <- suppressWarnings(as.integer(parts[2]))
      l <- suppressWarnings(as.integer(parts[3]))
      t_val <- suppressWarnings(as.integer(parts[4]))
      if (is.na(w)) w <- 0L
      if (is.na(l)) l <- 0L
      if (is.na(t_val)) t_val <- 0L
      pts <- w * 3L + t_val
      deck_name <- parts[5]
    }

    # Match deck name to archetype (case-insensitive)
    deck_id <- NA_integer_
    if (nchar(deck_name) > 0 && nrow(all_decks) > 0) {
      match_idx <- which(tolower(all_decks$archetype_name) == tolower(deck_name))
      if (length(match_idx) > 0) {
        deck_id <- all_decks$archetype_id[match_idx[1]]
      }
    }

    list(name = name, points = pts, wins = w, losses = l, ties = t_val, deck_id = deck_id)
  })
}

# -----------------------------------------------------------------------------
# build_deck_choices: Build the deck dropdown choices vector
# Returns named character vector: Unknown, Request new, pending requests, active archetypes
# -----------------------------------------------------------------------------
build_deck_choices <- function(con) {
  decks <- safe_query_impl(con, "
    SELECT archetype_id, archetype_name FROM deck_archetypes
    WHERE is_active = TRUE ORDER BY archetype_name
  ")

  pending_requests <- safe_query_impl(con, "
    SELECT request_id, deck_name FROM deck_requests
    WHERE status = 'pending' ORDER BY deck_name
  ")

  deck_choices <- c("Unknown" = "")
  deck_choices <- c(deck_choices, "\U2795 Request new deck..." = "__REQUEST_NEW__")

  if (nrow(pending_requests) > 0) {
    pending_choices <- setNames(
      paste0("pending_", pending_requests$request_id),
      paste0("Pending: ", pending_requests$deck_name)
    )
    deck_choices <- c(deck_choices, pending_choices)
  }

  deck_choices <- c(deck_choices, setNames(as.character(decks$archetype_id), decks$archetype_name))

  deck_choices
}

# -----------------------------------------------------------------------------
# match_player: Match by member_number first (if provided), then by name
# Filters out inactive (soft-deleted) players in both queries.
#
# scene_id: Optional. When provided, name-only matching is scoped to players
#   who have previously competed in this scene. This prevents cross-scene
#   name collisions (e.g., "Matt" in DFW vs "Matt" in Houston).
#   Bandai ID matching remains global (same ID = same player everywhere).
#
# Returns list(status="matched", player_id=X, member_number=Y) or
#         list(status="new")
# -----------------------------------------------------------------------------
match_player <- function(name, con, member_number = NULL, scene_id = NULL) {
  # If member_number provided, try exact member_number match first (global)
  if (!is.null(member_number) && nchar(trimws(member_number)) > 0) {
    member_match <- safe_query_impl(con, "
      SELECT player_id, display_name, member_number
      FROM players WHERE member_number = $1 AND is_active IS NOT FALSE
      LIMIT 1
    ", params = list(trimws(member_number)))

    if (nrow(member_match) > 0) {
      return(list(
        status = "matched",
        player_id = member_match$player_id,
        member_number = member_match$member_number
      ))
    }
  }

  # Fall back to name match
  # If scene_id provided, scope to players who have competed in this scene
  if (!is.null(scene_id)) {
    player <- safe_query_impl(con, "
      SELECT DISTINCT p.player_id, p.display_name, p.member_number
      FROM players p
      JOIN results r ON p.player_id = r.player_id
      JOIN tournaments t ON r.tournament_id = t.tournament_id
      JOIN stores s ON t.store_id = s.store_id
      WHERE LOWER(p.display_name) = LOWER($1)
        AND p.is_active IS NOT FALSE
        AND s.scene_id = $2
      LIMIT 1
    ", params = list(name, scene_id))
  } else {
    # No scene_id - global name match (backward compatible)
    player <- safe_query_impl(con, "
      SELECT player_id, display_name, member_number
      FROM players WHERE LOWER(display_name) = LOWER($1) AND is_active IS NOT FALSE
      LIMIT 1
    ", params = list(name))
  }

  if (nrow(player) > 0) {
    list(
      status = "matched",
      player_id = player$player_id,
      member_number = player$member_number
    )
  } else {
    list(status = "new")
  }
}

# -----------------------------------------------------------------------------
# ocr_to_grid_data: Convert OCR results data frame to shared grid format
# Maps column names: username -> player_name, etc.
# -----------------------------------------------------------------------------
ocr_to_grid_data <- function(ocr_results) {
  data.frame(
    placement = ocr_results$placement,
    player_name = ocr_results$username,
    member_number = ifelse(is.na(ocr_results$member_number), "", ocr_results$member_number),
    points = as.integer(ocr_results$points),
    wins = as.integer(ocr_results$wins),
    losses = as.integer(ocr_results$losses),
    ties = as.integer(ocr_results$ties),
    deck_id = if ("deck_id" %in% names(ocr_results)) ocr_results$deck_id else rep(NA_integer_, nrow(ocr_results)),
    match_status = ocr_results$match_status,
    matched_player_id = ocr_results$matched_player_id,
    matched_member_number = rep(NA_character_, nrow(ocr_results)),
    result_id = rep(NA_integer_, nrow(ocr_results)),
    stringsAsFactors = FALSE
  )
}
