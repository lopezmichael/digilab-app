# =============================================================================
# Shared Results Grid Module
# Reusable grid rendering, input sync, and helper functions for
# Submit Results (all entry methods) and Edit Tournaments grid.
# =============================================================================

# -----------------------------------------------------------------------------
# Slug generation — global scope so both R/ files and server/ files can use them
# (server/ files source with local=TRUE, so functions defined there aren't visible
# to functions defined here in the global environment)
# -----------------------------------------------------------------------------
generate_slug <- function(text) {
  if (is.null(text) || !nzchar(trimws(text))) return(NA_character_)
  text |> trimws() |> tolower() |>
    gsub("[^a-z0-9]+", "-", x = _) |>
    gsub("^-|-$", "", x = _)
}

generate_unique_slug <- function(db_pool, text, exclude_player_id = NULL) {
  base_slug <- generate_slug(text)
  if (is.na(base_slug)) return(NA_character_)

  if (!is.null(exclude_player_id)) {
    existing <- safe_query_impl(db_pool,
      "SELECT COUNT(*) as n FROM players WHERE slug = $1 AND is_active = TRUE AND player_id != $2",
      params = list(base_slug, exclude_player_id), default = data.frame(n = 0))
  } else {
    existing <- safe_query_impl(db_pool,
      "SELECT COUNT(*) as n FROM players WHERE slug = $1 AND is_active = TRUE",
      params = list(base_slug), default = data.frame(n = 0))
  }

  if (existing$n[1] == 0) return(base_slug)

  for (i in 2:100) {
    candidate <- paste0(base_slug, "-", i)
    check <- safe_query_impl(db_pool,
      "SELECT COUNT(*) as n FROM players WHERE slug = $1 AND is_active = TRUE",
      params = list(candidate), default = data.frame(n = 0))
    if (check$n[1] == 0) return(candidate)
  }

  return(paste0(base_slug, "-", as.integer(Sys.time())))
}

# -----------------------------------------------------------------------------
# normalize_member_number: Standardize Bandai TCG+ IDs to 10-digit zero-padded
# Strips #, trims whitespace, left-pads with zeros. Passes through GUEST IDs.
# -----------------------------------------------------------------------------
# Check if a member number is a GUEST ID (e.g., GUEST12345)
is_guest_member <- function(mn) {
  !is.null(mn) && !is.na(mn) && nchar(mn) > 0 && grepl("^GUEST", mn, ignore.case = TRUE)
}

# Known placeholder Bandai member numbers (junk data)
PLACEHOLDER_MEMBER_NUMBERS <- c("0000000000", "0000099999")

# Check if a member number is a placeholder (GUEST ID or known junk)
is_placeholder_member <- function(mn) {
  if (is.null(mn) || is.na(mn)) return(FALSE)
  mn <- trimws(mn)
  if (nchar(mn) == 0) return(FALSE)
  is_guest_member(mn) || mn %in% PLACEHOLDER_MEMBER_NUMBERS
}

# Check if a member number is a real Bandai ID (not empty, not GUEST, not placeholder)
has_real_member_number <- function(mn) {
  !is.null(mn) && !is.na(mn) && nchar(trimws(mn)) > 0 && !is_placeholder_member(mn)
}

# Check if a player name indicates a guest/placeholder (auto-anonymize on creation)
is_guest_name <- function(name) {
  if (is.null(name) || is.na(name)) return(FALSE)
  grepl("^GUEST$", trimws(name), ignore.case = TRUE)
}

# Check if a new player should be auto-anonymized
should_auto_anonymize <- function(name, member_number = NULL) {
  is_guest_name(name) || is_placeholder_member(member_number %||% "")
}

# -----------------------------------------------------------------------------
# detach_to_player: Create or find a player for a super admin detach operation
# Used when a super admin changes a Bandai ID (with or without a name change)
# to split a result away from the original player.
# Returns player_id on success, or NULL if the target player is already in the
# tournament (caller must ROLLBACK and notify).
# -----------------------------------------------------------------------------
detach_to_player <- function(conn, name, member_num, scene_id, tournament_id, admin_username = "unknown") {
  if (has_real_member_number(member_num)) {
    # Bandai ID changed to a different value — check if a player with that ID exists
    existing_player <- DBI::dbGetQuery(conn, "
      SELECT player_id FROM players WHERE member_number = $1 AND is_active = TRUE
    ", params = list(member_num))
    if (nrow(existing_player) > 0) {
      # Check if that player already has a result in this tournament
      already_in <- DBI::dbGetQuery(conn, "
        SELECT result_id FROM results
        WHERE tournament_id = $1 AND player_id = $2
      ", params = list(tournament_id, existing_player$player_id[1]))
      if (nrow(already_in) > 0) return(NULL)
      return(existing_player$player_id[1])
    }
    # Create new verified player with the new Bandai ID
    auto_anon <- should_auto_anonymize(name, member_num)
    player_slug <- generate_unique_slug(conn, name)
    new_player <- DBI::dbGetQuery(conn,
      "INSERT INTO players (display_name, slug, member_number, identity_status, home_scene_id, is_anonymized, updated_by)
       VALUES ($1, $2, $3, 'verified', $4, $5, $6) RETURNING player_id",
      params = list(name, player_slug, member_num, scene_id, auto_anon, admin_username))
    return(new_player$player_id[1])
  } else {
    # Bandai ID cleared — create new unverified, scene-locked player
    auto_anon <- should_auto_anonymize(name, NULL)
    player_slug <- generate_unique_slug(conn, name)
    new_player <- DBI::dbGetQuery(conn,
      "INSERT INTO players (display_name, slug, member_number, identity_status, home_scene_id, is_anonymized, updated_by)
       VALUES ($1, $2, NULL, 'unverified', $3, $4, $5) RETURNING player_id",
      params = list(name, player_slug, scene_id, auto_anon, admin_username))
    return(new_player$player_id[1])
  }
}

# Get the scene_id for a tournament's store
get_tournament_scene_id <- function(pool_or_conn, tournament_id) {
  result <- tryCatch(
    DBI::dbGetQuery(pool_or_conn, "
      SELECT s.scene_id FROM tournaments t
      JOIN stores s ON t.store_id = s.store_id
      WHERE t.tournament_id = $1
    ", params = list(tournament_id)),
    error = function(e) data.frame()
  )
  if (nrow(result) > 0) result$scene_id[1] else NULL
}

normalize_member_number <- function(mn) {
  if (is.null(mn) || is.na(mn)) return(NA_character_)
  mn <- trimws(mn)
  mn <- sub("^#", "", mn)
  mn <- trimws(mn)
  if (nchar(mn) == 0) return(NA_character_)
  if (grepl("^GUEST", mn, ignore.case = TRUE)) return(mn)
  # Strip non-digit characters
  mn <- gsub("[^0-9]", "", mn)
  if (nchar(mn) == 0) return(NA_character_)
  # Don't truncate IDs already longer than 10 digits
  if (nchar(mn) >= 10) return(mn)
  # Left-pad to 10 digits
  paste0(strrep("0", 10 - nchar(mn)), mn)
}

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
# validate_placements: Validate and auto-adjust tied placements
# Accepts a vector of placement values (e.g., [1, 2, 2, 3])
# and adjusts downstream (e.g., [1, 2, 2, 4]) so ties skip the next rank.
# Returns the corrected placement vector.
# -----------------------------------------------------------------------------
validate_placements <- function(placements) {
  if (length(placements) == 0) return(integer(0))
  placements <- as.integer(placements)
  # Sort and track which positions had which values
  sorted <- sort(placements)
  result <- integer(length(sorted))
  next_rank <- 1L
  i <- 1L
  while (i <= length(sorted)) {
    # Count how many share this placement
    tied <- sum(sorted == sorted[i])
    for (j in seq_len(tied)) {
      result[i + j - 1L] <- next_rank
    }
    next_rank <- next_rank + tied
    i <- i + tied
  }
  # Map back to original order
  order_idx <- order(placements)
  out <- integer(length(placements))
  out[order_idx] <- result
  out
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
#   input              - Shiny input object
#   grid_data          - Current grid data frame
#   record_format      - "points" or "wlt"
#   prefix             - Input ID prefix (e.g., "admin_" or "edit_" or "sr_")
#   placement_editable - When TRUE, read placement from numericInput (default FALSE)
#   wlt_override       - When TRUE, read W/L/T columns even in points mode (default FALSE)
# -----------------------------------------------------------------------------
sync_grid_inputs <- function(input, grid_data, record_format, prefix,
                             placement_editable = FALSE, wlt_override = FALSE) {
  if (is.null(grid_data) || nrow(grid_data) == 0) return(grid_data)

  for (i in seq_len(nrow(grid_data))) {
    # Editable placement
    if (placement_editable) {
      place_val <- input[[paste0(prefix, "placement_", i)]]
      if (!is.null(place_val) && !is.na(place_val)) grid_data$placement[i] <- as.integer(place_val)
    }

    player_val <- input[[paste0(prefix, "player_", i)]]
    if (!is.null(player_val)) grid_data$player_name[i] <- player_val
    member_val <- input[[paste0(prefix, "member_", i)]]
    if (!is.null(member_val)) grid_data$member_number[i] <- member_val

    if (record_format == "points" && !wlt_override) {
      pts_val <- input[[paste0(prefix, "pts_", i)]]
      if (!is.null(pts_val) && !is.na(pts_val)) grid_data$points[i] <- as.integer(pts_val)
    } else if (record_format == "points" && wlt_override) {
      # W/L/T override in points mode: read both points and W/L/T
      pts_val <- input[[paste0(prefix, "pts_", i)]]
      if (!is.null(pts_val) && !is.na(pts_val)) grid_data$points[i] <- as.integer(pts_val)
      w_val <- input[[paste0(prefix, "w_", i)]]
      if (!is.null(w_val) && !is.na(w_val)) grid_data$wins[i] <- as.integer(w_val)
      l_val <- input[[paste0(prefix, "l_", i)]]
      if (!is.null(l_val) && !is.na(l_val)) grid_data$losses[i] <- as.integer(l_val)
      t_val <- input[[paste0(prefix, "t_", i)]]
      if (!is.null(t_val) && !is.na(t_val)) grid_data$ties[i] <- as.integer(t_val)
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
#   grid_data            - Grid data frame
#   record_format        - "points" or "wlt"
#   is_release           - TRUE if release event (hides deck column)
#   deck_choices         - Named character vector for deck selectInput
#   player_matches       - Named list of match info per row index
#   prefix               - Input ID prefix (e.g., "admin_" or "edit_" or "sr_")
#   mode                 - "entry" (default) or "review" (OCR review styling)
#   ocr_rows             - Integer vector of OCR-populated row indices (review mode)
#   placement_editable   - When TRUE, render numericInput for placement (default FALSE)
#   show_add_player_btn  - When TRUE, append "Add Player" button row (default FALSE)
#   show_wlt_override    - When TRUE + points mode, show W/L/T columns alongside Points (default FALSE)
# Returns: tagList with optional release notice, header row, data rows, optional add button
# -----------------------------------------------------------------------------
render_grid_ui <- function(grid_data, record_format, is_release, deck_choices,
                           player_matches, prefix, mode = "entry", ocr_rows = NULL,
                           placement_editable = FALSE, show_add_player_btn = FALSE,
                           show_wlt_override = FALSE) {
  # Determine effective display mode: show_wlt_override adds W/L/T columns in points mode
  show_wlt <- record_format == "wlt" || show_wlt_override

  # Column widths depend on format, release event, and W/L/T override
  if (is_release) {
    if (!show_wlt) {
      col_widths <- c(1, 1, 6, 2, 2)
    } else if (record_format == "points" && show_wlt_override) {
      col_widths <- c(1, 1, 3, 2, 1, 1, 1, 1)  # +Pts +W +L +T
    } else {
      col_widths <- c(1, 1, 4, 2, 2, 1, 1)
    }
  } else {
    if (!show_wlt) {
      col_widths <- c(1, 1, 3, 2, 2, 3)
    } else if (record_format == "points" && show_wlt_override) {
      col_widths <- c(1, 1, 2, 2, 1, 1, 1, 1, 2)  # +Pts +W +L +T +Deck
    } else {
      col_widths <- c(1, 1, 2, 2, 1, 1, 1, 3)
    }
  }

  # Header row
  if (is_release) {
    if (!show_wlt) {
      header <- layout_columns(col_widths = col_widths, class = "results-header-row",
                               div(""), div("#"), div("Player"), div("Member #"), div("Pts"))
    } else if (record_format == "points" && show_wlt_override) {
      header <- layout_columns(col_widths = col_widths, class = "results-header-row",
                               div(""), div("#"), div("Player"), div("Member #"), div("Pts"), div("W"), div("L"), div("T"))
    } else {
      header <- layout_columns(col_widths = col_widths, class = "results-header-row",
                               div(""), div("#"), div("Player"), div("Member #"), div("W"), div("L"), div("T"))
    }
  } else {
    if (!show_wlt) {
      header <- layout_columns(col_widths = col_widths, class = "results-header-row",
                               div(""), div("#"), div("Player"), div("Member #"), div("Pts"), div("Deck"))
    } else if (record_format == "points" && show_wlt_override) {
      header <- layout_columns(col_widths = col_widths, class = "results-header-row",
                               div(""), div("#"), div("Player"), div("Member #"), div("Pts"), div("W"), div("L"), div("T"), div("Deck"))
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
      } else if (match_info$status == "ambiguous") {
        n_candidates <- if (!is.null(match_info$candidates)) nrow(match_info$candidates) else 0
        div(class = "player-match-indicator ambiguous",
            style = "cursor: pointer;",
            onclick = sprintf("Shiny.setInputValue('%sdisambiguate_row', %d, {priority: 'event'})", prefix, i),
            bsicons::bs_icon("exclamation-triangle-fill"),
            span(class = "match-label", paste0(n_candidates, " matches — pick one")))
      } else if (match_info$status == "new_similar") {
        n_similar <- if (!is.null(match_info$candidates)) nrow(match_info$candidates) else 0
        div(class = "player-match-indicator new-similar",
            style = "cursor: pointer;",
            onclick = sprintf("Shiny.setInputValue('%ssimilar_player_row', %d, {priority: 'event'})", prefix, i),
            bsicons::bs_icon("person-exclamation"),
            span(class = "match-label", paste0("New — ", n_similar, " similar")))
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

    # Placement column — editable numericInput or static badge
    placement_col <- if (placement_editable) {
      div(
        class = "upload-result-placement",
        numericInput(paste0(prefix, "placement_", i), NULL,
                     value = row$placement, min = 1, max = 999, width = "60px"),
        match_badge
      )
    } else {
      div(
        class = "upload-result-placement",
        span(class = paste("placement-badge", place_class), grid_ordinal(row$placement)),
        match_badge
      )
    }

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

    # Build row based on format, release event, and W/L/T override
    w_col <- div(numericInput(paste0(prefix, "w_", i), NULL, value = row$wins, min = 0))
    l_col <- div(numericInput(paste0(prefix, "l_", i), NULL, value = row$losses, min = 0))
    t_col <- div(numericInput(paste0(prefix, "t_", i), NULL, value = row$ties, min = 0))
    pts_col <- div(numericInput(paste0(prefix, "pts_", i), NULL, value = row$points, min = 0, max = 99))

    if (is_release) {
      if (!show_wlt) {
        layout_columns(col_widths = col_widths, class = row_class,
                       delete_btn, placement_col, player_col, member_col, pts_col)
      } else if (record_format == "points" && show_wlt_override) {
        layout_columns(col_widths = col_widths, class = row_class,
                       delete_btn, placement_col, player_col, member_col, pts_col, w_col, l_col, t_col)
      } else {
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

      if (!show_wlt) {
        layout_columns(col_widths = col_widths, class = row_class,
                       delete_btn, placement_col, player_col, member_col, pts_col, deck_col)
      } else if (record_format == "points" && show_wlt_override) {
        layout_columns(col_widths = col_widths, class = row_class,
                       delete_btn, placement_col, player_col, member_col, pts_col, w_col, l_col, t_col, deck_col)
      } else {
        layout_columns(col_widths = col_widths, class = row_class,
                       delete_btn, placement_col, player_col, member_col, w_col, l_col, t_col, deck_col)
      }
    }
  })

  # Optional "Add Player" button row
  add_btn <- if (show_add_player_btn) {
    div(
      class = "upload-result-row add-player-row text-center mt-2",
      htmltools::tags$button(
        onclick = sprintf("Shiny.setInputValue('%sadd_player', Date.now(), {priority: 'event'})", prefix),
        class = "btn btn-sm btn-outline-primary",
        shiny::icon("plus"), " Add Player"
      )
    )
  } else {
    NULL
  }

  tagList(release_notice, header, rows, add_btn)
}

# -----------------------------------------------------------------------------
# defer_ratings_recalc: Recalculate ratings in the background
# Defers via later::later() so UI transitions aren't blocked.
# notify must be available in caller scope (Shiny server context).
# -----------------------------------------------------------------------------
defer_ratings_recalc <- function(db_pool, notify_fn = NULL) {
  later::later(function() {
    ratings_ok <- recalculate_ratings_cache(db_pool)
    if (!isTRUE(ratings_ok) && is.function(notify_fn)) {
      notify_fn("Ratings failed to update. They will refresh on next app restart.",
                type = "warning", duration = 8)
    }
  }, delay = 0.5)
}

# -----------------------------------------------------------------------------
# load_decklist_results: Query submitted results for decklist entry (Step 3)
# Returns data frame with result_id, placement, player_name, deck_name,
# record, decklist_url — sorted by placement.
# -----------------------------------------------------------------------------
load_decklist_results <- function(tournament_id, db_pool) {
  safe_query_impl(db_pool, "
    SELECT r.result_id, r.placement, p.display_name as player_name,
           COALESCE(da.archetype_name, 'UNKNOWN') as deck_name,
           CONCAT(r.wins, '-', r.losses, '-', r.ties) as record,
           r.decklist_url
    FROM results r
    JOIN players p ON r.player_id = p.player_id
    LEFT JOIN deck_archetypes da ON r.archetype_id = da.archetype_id
    WHERE r.tournament_id = $1
    ORDER BY r.placement ASC
  ", params = list(tournament_id), default = data.frame())
}

# -----------------------------------------------------------------------------
# decklist_link_icon: Render a validated decklist URL as a clickable icon
# Returns an <a> tag with a list icon, or NULL if URL is invalid/missing.
# -----------------------------------------------------------------------------
decklist_link_icon <- function(url) {
  dl_url <- validate_decklist_url(url)
  if (!is.null(dl_url)) {
    tags$a(
      href = dl_url,
      target = "_blank",
      rel = "noopener noreferrer",
      title = "View decklist",
      class = "text-primary",
      bsicons::bs_icon("list-ul")
    )
  }
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
# Returns: list(saved = count, skipped = count) — callers handle notifications
# -----------------------------------------------------------------------------
save_decklist_urls <- function(results_df, input, prefix, db_pool) {
  saved <- 0L
  skipped <- 0L
  for (i in seq_len(nrow(results_df))) {
    url_raw <- input[[paste0(prefix, i)]]
    if (!is.null(url_raw) && nchar(trimws(url_raw)) > 0) {
      url_val <- validate_decklist_url(url_raw)
      if (!is.null(url_val)) {
        safe_execute_impl(db_pool, "UPDATE results SET decklist_url = $1, updated_at = CURRENT_TIMESTAMP WHERE result_id = $2",
                     params = list(url_val, results_df$result_id[i]))
        saved <- saved + 1L
      } else {
        skipped <- skipped + 1L
      }
    }
  }
  list(saved = saved, skipped = skipped)
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
        {
          # Generate domain list from ALLOWED_DECKLIST_DOMAINS constant
          # Deduplicate subdomains (play.limitlesstcg.com → limitlesstcg.com)
          display_domains <- unique(sub("^[^.]+\\.", "", ALLOWED_DECKLIST_DOMAINS))
          display_domains <- display_domains[display_domains %in% ALLOWED_DECKLIST_DOMAINS]
          n <- length(display_domains)
          do.call(tagList, c(
            lapply(seq_len(n - 1), function(i) tagList(tags$strong(display_domains[i]), ", ")),
            list(tagList("or ", tags$strong(display_domains[n]), "."))
          ))
        }
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
#   3 columns - names + points + deck   (or Name + MemberID + Points if col2 is 10-digit)
#   4 columns - names + W/L/T           (or Name + MemberID + W/L/T if col2 is 10-digit — NOT USED, falls through to 4-col WLT)
#   5+ columns - names + W/L/T + deck   (or Name + MemberID + W/L/T if col2 is 10-digit)
# Header row detection: skips first row if it matches known headers.
# Returns list of lists with name/member_number/points/wins/losses/ties/deck_id
# -----------------------------------------------------------------------------
PASTE_HEADER_PATTERNS <- c("name", "player", "username", "points", "wins", "losses",
                            "ties", "deck", "member", "ranking", "rank", "place", "w", "l", "t")

parse_paste_data <- function(text, all_decks) {
  lines <- strsplit(text, "\n")[[1]]
  lines <- lines[nchar(trimws(lines)) > 0]

  if (length(lines) == 0) return(list())

  # Header row detection: skip first row if all parts match known headers
  first_parts <- strsplit(lines[1], "\t")[[1]]
  if (length(first_parts) == 1) first_parts <- strsplit(trimws(lines[1]), "\\s{2,}")[[1]]
  first_parts_lower <- tolower(trimws(first_parts))
  if (length(first_parts_lower) > 0 && all(first_parts_lower %in% PASTE_HEADER_PATTERNS)) {
    lines <- lines[-1]
  }

  if (length(lines) == 0) return(list())

  # Helper: detect if a value looks like a 10-digit member number
  is_member_id <- function(val) {
    grepl("^\\d{10,}$", val)
  }

  lapply(lines, function(line) {
    parts <- strsplit(line, "\t")[[1]]
    if (length(parts) == 1) {
      parts <- strsplit(trimws(line), "\\s{2,}")[[1]]
    }
    parts <- trimws(parts)

    name <- parts[1]
    member_number <- NA_character_
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
      # Check if col2 is a member ID: Name + MemberID + Points
      if (is_member_id(parts[2])) {
        member_number <- normalize_member_number(parts[2])
        pts <- suppressWarnings(as.integer(parts[3]))
        if (is.na(pts)) pts <- 0L
      } else {
        # Name + Points + Deck
        pts <- suppressWarnings(as.integer(parts[2]))
        if (is.na(pts)) pts <- 0L
        deck_name <- parts[3]
      }
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
      # Check if col2 is a member ID: Name + MemberID + W/L/T (+ optional Deck)
      if (is_member_id(parts[2])) {
        member_number <- normalize_member_number(parts[2])
        w <- suppressWarnings(as.integer(parts[3]))
        l <- suppressWarnings(as.integer(parts[4]))
        t_val <- suppressWarnings(as.integer(parts[5]))
        if (is.na(w)) w <- 0L
        if (is.na(l)) l <- 0L
        if (is.na(t_val)) t_val <- 0L
        pts <- w * 3L + t_val
        if (length(parts) >= 6) deck_name <- parts[6]
      } else {
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
    }

    # Match deck name to archetype (case-insensitive)
    deck_id <- NA_integer_
    if (nchar(deck_name) > 0 && nrow(all_decks) > 0) {
      match_idx <- which(tolower(all_decks$archetype_name) == tolower(deck_name))
      if (length(match_idx) > 0) {
        deck_id <- all_decks$archetype_id[match_idx[1]]
      }
    }

    list(name = name, member_number = member_number, points = pts,
         wins = w, losses = l, ties = t_val, deck_id = deck_id)
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
# match_player: Identity-aware player matching with disambiguation.
#
# Matching cascade:
#   1. Bandai member number (global, definitive) — skip GUEST IDs
#   2. Name match (scene-scoped):
#      a. Verified players who've competed in this scene
#      b. Unverified players whose home_scene matches
#   3. If multiple candidates → return "ambiguous" with candidate list
#   4. No match → return "new"
#
# Returns:
#   list(status="matched", player_id=X, member_number=Y)
#   list(status="ambiguous", candidates=data.frame(...))
#   list(status="new")
# -----------------------------------------------------------------------------
match_player <- function(name, con, member_number = NULL, scene_id = NULL) {
  # Step 1: Bandai ID match (global, definitive) — skip GUEST/placeholder IDs
  if (!is.null(member_number) && !is.na(member_number) && nchar(trimws(member_number)) > 0) {
    mn <- normalize_member_number(member_number)
    if (!is.na(mn) && has_real_member_number(mn)) {
      member_match <- safe_query_impl(con, "
        SELECT player_id, display_name, member_number
        FROM players WHERE member_number = $1 AND is_active IS NOT FALSE
        LIMIT 1
      ", params = list(mn))

      if (nrow(member_match) > 0) {
        return(list(
          status = "matched",
          player_id = member_match$player_id,
          member_number = member_match$member_number
        ))
      }
    }
  }

  # Step 2: Name match — identity-status-aware
  if (!is.null(scene_id)) {
    # Scene-scoped: players homed here OR verified players who've competed here
    candidates <- safe_query_impl(con, "
      SELECT DISTINCT p.player_id, p.display_name, p.member_number,
             p.identity_status, p.home_scene_id
      FROM players p
      LEFT JOIN results r ON p.player_id = r.player_id
      LEFT JOIN tournaments t ON r.tournament_id = t.tournament_id
      LEFT JOIN stores s ON t.store_id = s.store_id
      WHERE LOWER(p.display_name) = LOWER($1)
        AND p.is_active IS NOT FALSE
        AND (
          p.home_scene_id = $2
          OR
          (p.identity_status = 'verified' AND s.scene_id = $2)
        )
    ", params = list(name, scene_id))
  } else {
    # No scene context — only match verified players globally
    candidates <- safe_query_impl(con, "
      SELECT player_id, display_name, member_number,
             identity_status, home_scene_id
      FROM players
      WHERE LOWER(display_name) = LOWER($1)
        AND is_active IS NOT FALSE
        AND identity_status = 'verified'
    ", params = list(name))
  }

  if (nrow(candidates) == 1) {
    return(list(
      status = "matched",
      player_id = candidates$player_id[1],
      member_number = candidates$member_number[1]
    ))
  } else if (nrow(candidates) > 1) {
    return(list(
      status = "ambiguous",
      candidates = candidates
    ))
  }

  # Step 3: No exact match — check for fuzzy name matches (pg_trgm)
  if (nchar(trimws(name)) >= 3) {
    fuzzy <- safe_query_impl(con, "
      SELECT p.player_id, p.display_name, p.member_number,
             p.identity_status, p.home_scene_id,
             similarity(LOWER(p.display_name), LOWER($1)) AS sim
      FROM players p
      WHERE similarity(LOWER(p.display_name), LOWER($1)) > 0.4
        AND p.is_active IS NOT FALSE
      ORDER BY sim DESC
      LIMIT 5
    ", params = list(name))

    if (nrow(fuzzy) > 0) {
      return(list(
        status = "new_similar",
        candidates = fuzzy
      ))
    }
  }

  list(status = "new")
}

# -----------------------------------------------------------------------------
# ocr_to_grid_data: Convert OCR results data frame to shared grid format
# Maps column names: username -> player_name, etc.
# -----------------------------------------------------------------------------
ocr_to_grid_data <- function(ocr_results) {
  n <- nrow(ocr_results)
  data.frame(
    placement = ocr_results$placement,
    player_name = ocr_results$username,
    member_number = ifelse(is.na(ocr_results$member_number), "", ocr_results$member_number),
    points = as.integer(ocr_results$points),
    wins = as.integer(ocr_results$wins),
    losses = as.integer(ocr_results$losses),
    ties = as.integer(ocr_results$ties),
    deck_id = if ("deck_id" %in% names(ocr_results)) ocr_results$deck_id else rep(NA_integer_, n),
    match_status = ocr_results$match_status,
    matched_player_id = ocr_results$matched_player_id,
    matched_member_number = rep(NA_character_, n),
    result_id = rep(NA_integer_, n),
    deck_url = if ("deck_url" %in% names(ocr_results)) ocr_results$deck_url else rep(NA_character_, n),
    omw_pct = if ("omw_pct" %in% names(ocr_results)) ocr_results$omw_pct else rep(NA_real_, n),
    oomw_pct = if ("oomw_pct" %in% names(ocr_results)) ocr_results$oomw_pct else rep(NA_real_, n),
    memo = if ("memo" %in% names(ocr_results)) ocr_results$memo else rep(NA_character_, n),
    stringsAsFactors = FALSE
  )
}
