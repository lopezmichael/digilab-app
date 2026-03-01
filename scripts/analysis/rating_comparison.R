# scripts/analysis/rating_comparison.R
# Tools for capturing and comparing rating snapshots before/after algorithm changes
#
# Usage:
#   source("scripts/analysis/rating_comparison.R")
#
#   # Before changes: capture current state
#   capture_rating_snapshot("pre_redesign")
#
#   # After changes: capture new state and compare
#   capture_rating_snapshot("post_redesign")
#   compare_rating_snapshots("pre_redesign", "post_redesign")
#
#   # Check specific players
#   compare_rating_snapshots("pre_redesign", "post_redesign",
#                            highlight_players = c("nudes", "photon", "atomshell"))

library(DBI)
library(RPostgres)
library(dotenv)

# -----------------------------------------------------------------------------
# Database Connection
# -----------------------------------------------------------------------------

load_dot_env()

get_db_connection <- function() {
  dbConnect(
    Postgres(),
    host = Sys.getenv("NEON_HOST"),
    dbname = Sys.getenv("NEON_DATABASE"),
    user = Sys.getenv("NEON_USER"),
    password = Sys.getenv("NEON_PASSWORD"),
    sslmode = "require"
  )
}

# -----------------------------------------------------------------------------
# Capture Current Ratings
# -----------------------------------------------------------------------------

#' Capture current rating state to a CSV file
#' @param snapshot_name Name for this snapshot (e.g., "pre_redesign", "post_redesign")
#' @param output_dir Directory to save snapshots (default: scripts/analysis/snapshots)
#' @return Path to the saved file
capture_rating_snapshot <- function(snapshot_name, output_dir = "scripts/analysis/snapshots") {

  # Create output directory if needed
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
  }

  db_con <- get_db_connection()
  on.exit(dbDisconnect(db_con))

  message(sprintf("[snapshot] Capturing ratings snapshot: %s", snapshot_name))

  # Get current ratings with player info
  ratings <- dbGetQuery(db_con, "
    SELECT
      p.player_id,
      p.display_name,
      p.member_number,
      prc.competitive_rating,
      prc.achievement_score,
      prc.events_played,
      RANK() OVER (ORDER BY prc.competitive_rating DESC) as rating_rank
    FROM player_ratings_cache prc
    JOIN players p ON prc.player_id = p.player_id
    ORDER BY prc.competitive_rating DESC
  ")

  message(sprintf("[snapshot] Found %d players with ratings", nrow(ratings)))

  # Add metadata
  ratings$snapshot_name <- snapshot_name
  ratings$snapshot_time <- Sys.time()

  # Save to CSV
  filename <- sprintf("%s/%s_%s.csv",
                      output_dir,
                      snapshot_name,
                      format(Sys.time(), "%Y%m%d_%H%M%S"))
  write.csv(ratings, filename, row.names = FALSE)

  message(sprintf("[snapshot] Saved to: %s", filename))

  # Also save a "latest" version for easy comparison
  latest_filename <- sprintf("%s/%s_latest.csv", output_dir, snapshot_name)
  write.csv(ratings, latest_filename, row.names = FALSE)
  message(sprintf("[snapshot] Latest copy: %s", latest_filename))

  # Print summary stats
  message("\n--- Snapshot Summary ---")
  message(sprintf("Total players: %d", nrow(ratings)))
  message(sprintf("Rating range: %d - %d", min(ratings$competitive_rating), max(ratings$competitive_rating)))
  message(sprintf("Mean rating: %.1f", mean(ratings$competitive_rating)))
  message(sprintf("Median rating: %.1f", median(ratings$competitive_rating)))

  invisible(filename)
}


# -----------------------------------------------------------------------------
# Compare Snapshots
# -----------------------------------------------------------------------------

#' Compare two rating snapshots
#' @param before_name Name of the "before" snapshot
#' @param after_name Name of the "after" snapshot
#' @param highlight_players Vector of player names to highlight (case-insensitive partial match)
#' @param output_dir Directory where snapshots are stored
#' @return Data frame with comparison results
compare_rating_snapshots <- function(before_name, after_name,
                                     highlight_players = NULL,
                                     output_dir = "scripts/analysis/snapshots") {

  # Load snapshots
  before_file <- sprintf("%s/%s_latest.csv", output_dir, before_name)
  after_file <- sprintf("%s/%s_latest.csv", output_dir, after_name)

  if (!file.exists(before_file)) {
    stop(sprintf("Before snapshot not found: %s", before_file))
  }
  if (!file.exists(after_file)) {
    stop(sprintf("After snapshot not found: %s", after_file))
  }

  before <- read.csv(before_file, stringsAsFactors = FALSE)
  after <- read.csv(after_file, stringsAsFactors = FALSE)

  message(sprintf("\n[compare] Comparing '%s' (%d players) vs '%s' (%d players)",
                  before_name, nrow(before), after_name, nrow(after)))

  # Merge on player_id
  comparison <- merge(
    before[, c("player_id", "display_name", "competitive_rating", "achievement_score",
               "events_played", "rating_rank")],
    after[, c("player_id", "competitive_rating", "achievement_score", "rating_rank")],
    by = "player_id",
    suffixes = c("_before", "_after"),
    all = TRUE
  )

  # Calculate changes
  comparison$rating_change <- comparison$competitive_rating_after - comparison$competitive_rating_before
  comparison$rank_change <- comparison$rating_rank_before - comparison$rating_rank_after  # Positive = improved
  comparison$achievement_change <- comparison$achievement_score_after - comparison$achievement_score_before

  # Handle new/removed players
  comparison$status <- "existing"
  comparison$status[is.na(comparison$competitive_rating_before)] <- "new"
  comparison$status[is.na(comparison$competitive_rating_after)] <- "removed"

  # Sort by absolute rating change (biggest movers first)
  comparison <- comparison[order(-abs(comparison$rating_change), na.last = TRUE), ]

  # Print summary
  existing <- comparison[comparison$status == "existing", ]

  message("\n========================================")
  message("RATING COMPARISON SUMMARY")
  message("========================================")
  message(sprintf("\nExisting players: %d", sum(comparison$status == "existing")))
  message(sprintf("New players: %d", sum(comparison$status == "new")))
  message(sprintf("Removed players: %d", sum(comparison$status == "removed")))

  if (nrow(existing) > 0) {
    message(sprintf("\nRating changes (existing players):"))
    message(sprintf("  Mean change: %+.1f", mean(existing$rating_change, na.rm = TRUE)))
    message(sprintf("  Median change: %+.1f", median(existing$rating_change, na.rm = TRUE)))
    message(sprintf("  Max increase: %+d", max(existing$rating_change, na.rm = TRUE)))
    message(sprintf("  Max decrease: %+d", min(existing$rating_change, na.rm = TRUE)))
    message(sprintf("  Std deviation: %.1f", sd(existing$rating_change, na.rm = TRUE)))

    # Distribution of changes
    message(sprintf("\nChange distribution:"))
    message(sprintf("  >+100: %d players", sum(existing$rating_change > 100, na.rm = TRUE)))
    message(sprintf("  +50 to +100: %d players", sum(existing$rating_change >= 50 & existing$rating_change <= 100, na.rm = TRUE)))
    message(sprintf("  +10 to +50: %d players", sum(existing$rating_change >= 10 & existing$rating_change < 50, na.rm = TRUE)))
    message(sprintf("  -10 to +10: %d players", sum(abs(existing$rating_change) < 10, na.rm = TRUE)))
    message(sprintf("  -50 to -10: %d players", sum(existing$rating_change <= -10 & existing$rating_change > -50, na.rm = TRUE)))
    message(sprintf("  -100 to -50: %d players", sum(existing$rating_change <= -50 & existing$rating_change > -100, na.rm = TRUE)))
    message(sprintf("  <-100: %d players", sum(existing$rating_change < -100, na.rm = TRUE)))
  }

  # Top 10 biggest movers
  message("\n----------------------------------------")
  message("TOP 10 BIGGEST RATING INCREASES")
  message("----------------------------------------")
  top_gainers <- head(existing[order(-existing$rating_change), ], 10)
  for (i in 1:nrow(top_gainers)) {
    r <- top_gainers[i, ]
    message(sprintf("%2d. %-20s %4d -> %4d (%+4d) | Rank: %d -> %d",
                    i, r$display_name,
                    as.integer(r$competitive_rating_before), as.integer(r$competitive_rating_after),
                    as.integer(r$rating_change),
                    as.integer(r$rating_rank_before), as.integer(r$rating_rank_after)))
  }

  message("\n----------------------------------------")
  message("TOP 10 BIGGEST RATING DECREASES")
  message("----------------------------------------")
  top_losers <- head(existing[order(existing$rating_change), ], 10)
  for (i in 1:nrow(top_losers)) {
    r <- top_losers[i, ]
    message(sprintf("%2d. %-20s %4d -> %4d (%+4d) | Rank: %d -> %d",
                    i, r$display_name,
                    as.integer(r$competitive_rating_before), as.integer(r$competitive_rating_after),
                    as.integer(r$rating_change),
                    as.integer(r$rating_rank_before), as.integer(r$rating_rank_after)))
  }

  # Highlighted players
  if (!is.null(highlight_players) && length(highlight_players) > 0) {
    message("\n========================================")
    message("HIGHLIGHTED PLAYERS")
    message("========================================")

    for (player_name in highlight_players) {
      # Case-insensitive partial match
      matches <- comparison[grepl(player_name, comparison$display_name, ignore.case = TRUE), ]

      if (nrow(matches) == 0) {
        message(sprintf("\n'%s': NOT FOUND", player_name))
      } else {
        for (j in 1:nrow(matches)) {
          r <- matches[j, ]
          message(sprintf("\n'%s' (player_id: %d)", r$display_name, as.integer(r$player_id)))
          message(sprintf("  Status: %s", r$status))

          if (r$status == "existing") {
            message(sprintf("  Rating: %d -> %d (%+d)",
                            as.integer(r$competitive_rating_before), as.integer(r$competitive_rating_after),
                            as.integer(r$rating_change)))
            message(sprintf("  Rank: %d -> %d (%+d positions)",
                            as.integer(r$rating_rank_before), as.integer(r$rating_rank_after),
                            as.integer(r$rank_change)))
            message(sprintf("  Events: %d", as.integer(r$events_played)))
          } else if (r$status == "new") {
            message(sprintf("  New rating: %d (rank %d)",
                            as.integer(r$competitive_rating_after), as.integer(r$rating_rank_after)))
          } else {
            message(sprintf("  Previous rating: %d (rank %d)",
                            as.integer(r$competitive_rating_before), as.integer(r$rating_rank_before)))
          }
        }
      }
    }
  }

  # Save comparison to file
  comparison_file <- sprintf("%s/comparison_%s_vs_%s_%s.csv",
                             output_dir, before_name, after_name,
                             format(Sys.time(), "%Y%m%d_%H%M%S"))
  write.csv(comparison, comparison_file, row.names = FALSE)
  message(sprintf("\n[compare] Full comparison saved to: %s", comparison_file))

  invisible(comparison)
}


# -----------------------------------------------------------------------------
# Quick Lookup Functions
# -----------------------------------------------------------------------------

#' Look up specific players in the current ratings
#' @param player_names Vector of player names to look up (partial match)
lookup_players <- function(player_names) {
  db_con <- get_db_connection()
  on.exit(dbDisconnect(db_con))

  ratings <- dbGetQuery(db_con, "
    SELECT
      p.player_id,
      p.display_name,
      p.member_number,
      prc.competitive_rating,
      prc.achievement_score,
      prc.events_played,
      RANK() OVER (ORDER BY prc.competitive_rating DESC) as rating_rank
    FROM player_ratings_cache prc
    JOIN players p ON prc.player_id = p.player_id
    ORDER BY prc.competitive_rating DESC
  ")

  message("\n========================================")
  message("PLAYER LOOKUP")
  message("========================================")

  for (player_name in player_names) {
    matches <- ratings[grepl(player_name, ratings$display_name, ignore.case = TRUE), ]

    if (nrow(matches) == 0) {
      message(sprintf("\n'%s': NOT FOUND", player_name))
    } else {
      for (i in 1:nrow(matches)) {
        r <- matches[i, ]
        message(sprintf("\n'%s' (player_id: %d)", r$display_name, as.integer(r$player_id)))
        message(sprintf("  Rating: %d (rank #%d)", as.integer(r$competitive_rating), as.integer(r$rating_rank)))
        message(sprintf("  Achievement: %d", as.integer(r$achievement_score)))
        message(sprintf("  Events: %d", as.integer(r$events_played)))
        if (!is.na(r$member_number)) {
          message(sprintf("  Bandai ID: %s", r$member_number))
        }
      }
    }
  }

  invisible(ratings)
}


# -----------------------------------------------------------------------------
# Main: If run directly, capture a snapshot
# -----------------------------------------------------------------------------

if (interactive()) {
  message("Rating Comparison Tool loaded.")
  message("")
  message("Available functions:")
  message("  capture_rating_snapshot('snapshot_name')  - Save current ratings")
  message("  compare_rating_snapshots('before', 'after', highlight_players = c('name1', 'name2'))")
  message("  lookup_players(c('nudes', 'photon', 'atomshell'))")
  message("")
  message("Example workflow:")
  message("  1. capture_rating_snapshot('pre_redesign')")
  message("  2. [Make algorithm changes]")
  message("  3. capture_rating_snapshot('post_redesign')")
  message("  4. compare_rating_snapshots('pre_redesign', 'post_redesign', ")
  message("       highlight_players = c('nudes', 'photon', 'atomshell'))")
}
