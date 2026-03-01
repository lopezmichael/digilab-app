# scripts/analysis/compare_algorithms_readonly.R
# READ-ONLY comparison of old vs new rating algorithms
# Does NOT write anything to the database - only local CSV files
#
# Usage: source("scripts/analysis/compare_algorithms_readonly.R")

library(DBI)
library(RPostgres)
library(dotenv)
load_dot_env()

OUTPUT_DIR <- "scripts/analysis/snapshots"
if (!dir.exists(OUTPUT_DIR)) dir.create(OUTPUT_DIR, recursive = TRUE)

# -----------------------------------------------------------------------------
# Database Connection (READ-ONLY operations only)
# -----------------------------------------------------------------------------

get_db_connection <- function() {
  dbConnect(Postgres(),
    host = Sys.getenv("NEON_HOST"),
    dbname = Sys.getenv("NEON_DATABASE"),
    user = Sys.getenv("NEON_USER"),
    password = Sys.getenv("NEON_PASSWORD"),
    sslmode = "require")
}

# -----------------------------------------------------------------------------
# NEW Algorithm: Single-Pass Chronological (in memory only)
# -----------------------------------------------------------------------------

calculate_ratings_new_algorithm <- function(db_con) {
  message("[new] Loading tournament data...")

  results <- dbGetQuery(db_con, "
    SELECT r.tournament_id, r.player_id, r.placement,
           t.event_date, t.player_count, t.rounds,
           p.display_name
    FROM results r
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    JOIN players p ON r.player_id = p.player_id
    WHERE r.placement IS NOT NULL
      AND t.player_count IS NOT NULL
      AND t.player_count >= 4
    ORDER BY t.event_date ASC, t.tournament_id ASC, r.placement ASC
  ")

  if (nrow(results) == 0) {
    return(data.frame(player_id = integer(), competitive_rating = numeric(), events_played = integer()))
  }

  # Initialize
  all_players <- unique(results$player_id)
  ratings <- setNames(rep(1500, length(all_players)), as.character(all_players))
  events_played <- setNames(rep(0L, length(all_players)), as.character(all_players))

  tournaments <- unique(results[, c("tournament_id", "event_date", "player_count", "rounds")])
  tournaments <- tournaments[order(tournaments$event_date, tournaments$tournament_id), ]

  message(sprintf("[new] Processing %d tournaments, %d players (SINGLE PASS, NO DECAY)",
                  nrow(tournaments), length(all_players)))

  # SINGLE PASS through tournaments
  for (i in 1:nrow(tournaments)) {
    tourney <- tournaments[i, ]
    tourney_results <- results[results$tournament_id == tourney$tournament_id, ]
    tourney_results <- tourney_results[order(tourney_results$placement), ]

    if (nrow(tourney_results) < 2) next

    # Round multiplier
    rounds <- if (is.na(tourney$rounds)) 3 else tourney$rounds
    round_mult <- min(1.0 + (rounds - 3) * 0.1, 1.4)

    # Calculate changes
    player_changes <- list()

    for (j in 1:nrow(tourney_results)) {
      player_id <- as.character(tourney_results$player_id[j])
      placement <- tourney_results$placement[j]
      player_rating <- ratings[player_id]

      k_factor <- if (events_played[player_id] < 5) 48 else 24
      rating_change <- 0

      for (k in 1:nrow(tourney_results)) {
        if (j == k) next

        opponent_id <- as.character(tourney_results$player_id[k])
        opponent_placement <- tourney_results$placement[k]
        opponent_rating <- ratings[opponent_id]

        # FIX: Ties are 0.5, not 0
        actual_result <- if (placement < opponent_placement) 1
                         else if (placement == opponent_placement) 0.5
                         else 0

        expected <- 1 / (1 + 10^((opponent_rating - player_rating) / 400))
        rating_change <- rating_change + k_factor * (actual_result - expected)
      }

      # NO DECAY - just round multiplier
      rating_change <- rating_change * round_mult
      num_opponents <- nrow(tourney_results) - 1
      rating_change <- rating_change / num_opponents

      player_changes[[player_id]] <- rating_change
    }

    # Apply changes
    for (player_id in names(player_changes)) {
      events_played[player_id] <- events_played[player_id] + 1L
      ratings[player_id] <- ratings[player_id] + player_changes[[player_id]]
    }
  }

  message("[new] Calculation complete")

  data.frame(
    player_id = as.integer(names(ratings)),
    competitive_rating = round(as.numeric(ratings), 0),
    events_played = as.integer(events_played),
    stringsAsFactors = FALSE
  )
}

# -----------------------------------------------------------------------------
# OLD Algorithm: Multi-Pass with Decay (from current production)
# -----------------------------------------------------------------------------

calculate_ratings_old_algorithm <- function(db_con) {
  message("[old] Loading tournament data...")

  results <- dbGetQuery(db_con, "
    SELECT r.tournament_id, r.player_id, r.placement,
           t.event_date, t.player_count, t.rounds,
           p.display_name
    FROM results r
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    JOIN players p ON r.player_id = p.player_id
    WHERE r.placement IS NOT NULL
      AND t.player_count IS NOT NULL
      AND t.player_count >= 4
    ORDER BY t.event_date ASC, r.tournament_id, r.placement
  ")

  if (nrow(results) == 0) {
    return(data.frame(player_id = integer(), competitive_rating = numeric()))
  }

  players <- unique(results$player_id)
  ratings <- setNames(rep(1500, length(players)), as.character(players))
  events_played <- setNames(rep(0, length(players)), as.character(players))

  tournaments <- unique(results[, c("tournament_id", "event_date", "player_count", "rounds")])
  tournaments <- tournaments[order(tournaments$event_date), ]

  current_date <- Sys.Date()

  message(sprintf("[old] Processing %d tournaments, %d players (5 PASSES, WITH DECAY)",
                  nrow(tournaments), length(players)))

  # 5 PASSES for "convergence"
  for (pass in 1:5) {
    for (i in 1:nrow(tournaments)) {
      tourney <- tournaments[i, ]
      tourney_results <- results[results$tournament_id == tourney$tournament_id, ]
      tourney_results <- tourney_results[order(tourney_results$placement), ]

      if (nrow(tourney_results) < 2) next

      # Decay based on current date
      months_ago <- as.numeric(difftime(current_date, tourney$event_date, units = "days")) / 30.44
      decay_weight <- 0.5 ^ (months_ago / 4)

      rounds <- if (is.na(tourney$rounds)) 3 else tourney$rounds
      round_mult <- min(1.0 + (rounds - 3) * 0.1, 1.4)

      for (j in 1:nrow(tourney_results)) {
        player_id <- as.character(tourney_results$player_id[j])
        placement <- tourney_results$placement[j]
        player_rating <- ratings[player_id]

        k_factor <- if (events_played[player_id] < 5) 48 else 24
        rating_change <- 0

        for (k in 1:nrow(tourney_results)) {
          if (j == k) next

          opponent_id <- as.character(tourney_results$player_id[k])
          opponent_placement <- tourney_results$placement[k]
          opponent_rating <- ratings[opponent_id]

          # BUG: Ties treated as losses (0 instead of 0.5)
          actual_result <- if (placement < opponent_placement) 1 else 0

          expected <- 1 / (1 + 10^((opponent_rating - player_rating) / 400))
          rating_change <- rating_change + k_factor * (actual_result - expected)
        }

        # Apply decay AND round multiplier
        rating_change <- rating_change * decay_weight * round_mult
        num_opponents <- nrow(tourney_results) - 1
        rating_change <- rating_change / num_opponents

        ratings[player_id] <- ratings[player_id] + rating_change
      }

      # Update events played (only on first pass)
      if (pass == 1) {
        for (pid in tourney_results$player_id) {
          events_played[as.character(pid)] <- events_played[as.character(pid)] + 1
        }
      }
    }
  }

  message("[old] Calculation complete")

  data.frame(
    player_id = as.integer(names(ratings)),
    competitive_rating = round(as.numeric(ratings), 0),
    events_played = as.integer(events_played),
    stringsAsFactors = FALSE
  )
}

# -----------------------------------------------------------------------------
# Run Comparison
# -----------------------------------------------------------------------------

run_comparison <- function(highlight_players = c("nudes", "photon", "atomshell")) {
  db_con <- get_db_connection()
  on.exit(dbDisconnect(db_con))

  message("\n========================================")
  message("ALGORITHM COMPARISON (READ-ONLY)")
  message("========================================\n")

  # Get player names for display
  player_names <- dbGetQuery(db_con, "SELECT player_id, display_name FROM players")

  # Calculate with OLD algorithm
  message("--- Running OLD algorithm ---")
  old_ratings <- calculate_ratings_old_algorithm(db_con)
  old_ratings <- merge(old_ratings, player_names, by = "player_id")

  # Calculate with NEW algorithm
  message("\n--- Running NEW algorithm ---")
  new_ratings <- calculate_ratings_new_algorithm(db_con)
  new_ratings <- merge(new_ratings, player_names, by = "player_id")

  # Compare
  comparison <- merge(
    old_ratings[, c("player_id", "display_name", "competitive_rating", "events_played")],
    new_ratings[, c("player_id", "competitive_rating")],
    by = "player_id",
    suffixes = c("_old", "_new")
  )

  comparison$rating_change <- comparison$competitive_rating_new - comparison$competitive_rating_old
  comparison$rank_old <- rank(-comparison$competitive_rating_old, ties.method = "min")
  comparison$rank_new <- rank(-comparison$competitive_rating_new, ties.method = "min")
  comparison$rank_change <- comparison$rank_old - comparison$rank_new

  # Save to CSV
  timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
  csv_file <- sprintf("%s/algorithm_comparison_%s.csv", OUTPUT_DIR, timestamp)
  write.csv(comparison, csv_file, row.names = FALSE)
  message(sprintf("\n[saved] Full comparison: %s", csv_file))

  # Print summary
  message("\n========================================")
  message("COMPARISON SUMMARY")
  message("========================================")
  message(sprintf("Total players: %d", nrow(comparison)))
  message(sprintf("\nOLD algorithm (5-pass, decay, ties=0):"))
  message(sprintf("  Rating range: %d - %d", min(comparison$competitive_rating_old), max(comparison$competitive_rating_old)))
  message(sprintf("  Mean: %.1f", mean(comparison$competitive_rating_old)))

  message(sprintf("\nNEW algorithm (1-pass, no decay, ties=0.5):"))
  message(sprintf("  Rating range: %d - %d", min(comparison$competitive_rating_new), max(comparison$competitive_rating_new)))
  message(sprintf("  Mean: %.1f", mean(comparison$competitive_rating_new)))

  message(sprintf("\nRating changes (new - old):"))
  message(sprintf("  Mean change: %+.1f", mean(comparison$rating_change)))
  message(sprintf("  Median change: %+.1f", median(comparison$rating_change)))
  message(sprintf("  Max increase: %+d", max(comparison$rating_change)))
  message(sprintf("  Max decrease: %+d", min(comparison$rating_change)))
  message(sprintf("  Std deviation: %.1f", sd(comparison$rating_change)))

  message(sprintf("\nChange distribution:"))
  message(sprintf("  >+100: %d players", sum(comparison$rating_change > 100)))
  message(sprintf("  +50 to +100: %d players", sum(comparison$rating_change >= 50 & comparison$rating_change <= 100)))
  message(sprintf("  +10 to +50: %d players", sum(comparison$rating_change >= 10 & comparison$rating_change < 50)))
  message(sprintf("  -10 to +10: %d players", sum(abs(comparison$rating_change) < 10)))
  message(sprintf("  -50 to -10: %d players", sum(comparison$rating_change <= -10 & comparison$rating_change > -50)))
  message(sprintf("  -100 to -50: %d players", sum(comparison$rating_change <= -50 & comparison$rating_change > -100)))
  message(sprintf("  <-100: %d players", sum(comparison$rating_change < -100)))

  # Top movers
  message("\n----------------------------------------")
  message("TOP 10 BIGGEST RATING INCREASES")
  message("----------------------------------------")
  top_gainers <- head(comparison[order(-comparison$rating_change), ], 10)
  for (i in 1:nrow(top_gainers)) {
    r <- top_gainers[i, ]
    message(sprintf("%2d. %-20s %4d -> %4d (%+4d) | Rank: %d -> %d",
                    i, substr(r$display_name, 1, 20),
                    as.integer(r$competitive_rating_old), as.integer(r$competitive_rating_new),
                    as.integer(r$rating_change),
                    as.integer(r$rank_old), as.integer(r$rank_new)))
  }

  message("\n----------------------------------------")
  message("TOP 10 BIGGEST RATING DECREASES")
  message("----------------------------------------")
  top_losers <- head(comparison[order(comparison$rating_change), ], 10)
  for (i in 1:nrow(top_losers)) {
    r <- top_losers[i, ]
    message(sprintf("%2d. %-20s %4d -> %4d (%+4d) | Rank: %d -> %d",
                    i, substr(r$display_name, 1, 20),
                    as.integer(r$competitive_rating_old), as.integer(r$competitive_rating_new),
                    as.integer(r$rating_change),
                    as.integer(r$rank_old), as.integer(r$rank_new)))
  }

  # Highlighted players
  if (length(highlight_players) > 0) {
    message("\n========================================")
    message("HIGHLIGHTED PLAYERS")
    message("========================================")

    for (name in highlight_players) {
      matches <- comparison[grepl(name, comparison$display_name, ignore.case = TRUE), ]
      if (nrow(matches) == 0) {
        message(sprintf("\n'%s': NOT FOUND", name))
      } else {
        for (j in 1:nrow(matches)) {
          r <- matches[j, ]
          message(sprintf("\n'%s' (player_id: %d, events: %d)",
                          r$display_name, as.integer(r$player_id), as.integer(r$events_played)))
          message(sprintf("  OLD: %d (rank #%d)", as.integer(r$competitive_rating_old), as.integer(r$rank_old)))
          message(sprintf("  NEW: %d (rank #%d)", as.integer(r$competitive_rating_new), as.integer(r$rank_new)))
          message(sprintf("  Change: %+d rating, %+d rank positions",
                          as.integer(r$rating_change), as.integer(r$rank_change)))
        }
      }
    }
  }

  message("\n========================================")
  message("Comparison complete (NO DATABASE CHANGES)")
  message("========================================")

  invisible(comparison)
}

# Run if sourced directly
if (interactive()) {
  message("Read-only comparison tool loaded.")
  message("Run: run_comparison()")
  message("Or:  run_comparison(c('player1', 'player2'))")
}
