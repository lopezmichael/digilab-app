# scripts/analysis/fix_cross_scene_duplicates.R
# Splits players that were incorrectly merged across scenes
# Run AFTER reviewing detect_cross_scene_duplicates.R output
#
# Usage: source("scripts/analysis/fix_cross_scene_duplicates.R")
# Output: Prints summary for Discord notifications

library(DBI)
library(RPostgres)
library(dotenv)

# -----------------------------------------------------------------------------
# Configuration: Players to split
# Based on analysis from 2026-03-01-cross-scene-duplicates.md
# -----------------------------------------------------------------------------

# Each entry: list(player_id, display_name, minority_scene_id)
# minority_scene_id = the scene whose results will be moved to a NEW player
PLAYERS_TO_SPLIT <- list(
  list(player_id = 14,  display_name = "Matt",      minority_scene_name = "Pennsylvania (NEPA)"),
  list(player_id = 56,  display_name = "Tsukuyomi", minority_scene_name = "Denmark (Copenhagen)"),
  list(player_id = 124, display_name = "Shy Guy",   minority_scene_name = "Ohio (Cincinnati Area)"),
  list(player_id = 147, display_name = "Ace",       minority_scene_name = "Texas (Dallas-Fort Worth)"),
  list(player_id = 713, display_name = "Niko",      minority_scene_name = "New York (NYC)"),
  list(player_id = 736, display_name = "Eric",      minority_scene_name = "Canada (Metro Vancouver)"),
  list(player_id = 795, display_name = "Luiz",      minority_scene_name = "Brazil (São Paulo)")
)

# -----------------------------------------------------------------------------
# Database Connection
# -----------------------------------------------------------------------------

load_dot_env()

db_con <- dbConnect(
  Postgres(),
  host = Sys.getenv("NEON_HOST"),
  dbname = Sys.getenv("NEON_DATABASE"),
  user = Sys.getenv("NEON_USER"),
  password = Sys.getenv("NEON_PASSWORD"),
  sslmode = "require"
)

message("[fix] Connected to database")

# -----------------------------------------------------------------------------
# Get scene IDs for the minority scenes
# -----------------------------------------------------------------------------

get_scene_id <- function(scene_name) {
  result <- dbGetQuery(db_con, "SELECT scene_id FROM scenes WHERE name = $1", params = list(scene_name))
  if (nrow(result) == 0) {
    stop(sprintf("Scene not found: %s", scene_name))
  }
  result$scene_id[1]
}

# -----------------------------------------------------------------------------
# Split a single player
# Returns summary info for Discord notification
# -----------------------------------------------------------------------------

split_player <- function(player_id, display_name, minority_scene_name) {
  message(sprintf("\n[fix] Processing: %s (player_id: %d)", display_name, player_id))

  # Get minority scene ID
  minority_scene_id <- get_scene_id(minority_scene_name)
  message(sprintf("[fix]   Minority scene: %s (scene_id: %d)", minority_scene_name, minority_scene_id))

  # Get original player info
  original <- dbGetQuery(db_con, "
    SELECT player_id, display_name, member_number, limitless_username
    FROM players WHERE player_id = $1
  ", params = list(player_id))

  if (nrow(original) == 0) {
    message(sprintf("[fix]   ERROR: Player %d not found", player_id))
    return(NULL)
  }

  original_bandai <- original$member_number[1]
  message(sprintf("[fix]   Original Bandai ID: %s", ifelse(is.na(original_bandai), "None", original_bandai)))

  # Find results to move (results at stores in minority scene)
  results_to_move <- dbGetQuery(db_con, "
    SELECT r.result_id, r.tournament_id, t.event_date, s.name as store_name, sc.name as scene_name
    FROM results r
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    JOIN stores s ON t.store_id = s.store_id
    JOIN scenes sc ON s.scene_id = sc.scene_id
    WHERE r.player_id = $1 AND s.scene_id = $2
    ORDER BY t.event_date
  ", params = list(player_id, minority_scene_id))

  if (nrow(results_to_move) == 0) {
    message(sprintf("[fix]   No results found in minority scene - skipping"))
    return(NULL)
  }

  message(sprintf("[fix]   Found %d results to move", nrow(results_to_move)))

  # Get majority scene info for summary
  majority_info <- dbGetQuery(db_con, "
    SELECT DISTINCT sc.name as scene_name, COUNT(*) as result_count
    FROM results r
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    JOIN stores s ON t.store_id = s.store_id
    JOIN scenes sc ON s.scene_id = sc.scene_id
    WHERE r.player_id = $1 AND s.scene_id != $2
    GROUP BY sc.name
  ", params = list(player_id, minority_scene_id))

  majority_scene_name <- majority_info$scene_name[1]
  majority_result_count <- sum(majority_info$result_count)

  # Begin transaction
  dbBegin(db_con)

  tryCatch({
    # 1. Create new player for minority scene
    new_player <- dbGetQuery(db_con, "
      INSERT INTO players (display_name, is_active)
      VALUES ($1, TRUE)
      RETURNING player_id
    ", params = list(display_name))

    new_player_id <- new_player$player_id[1]
    message(sprintf("[fix]   Created new player_id: %d", new_player_id))

    # 2. Move results to new player
    result_ids <- results_to_move$result_id
    dbExecute(db_con, sprintf("
      UPDATE results SET player_id = $1
      WHERE result_id IN (%s)
    ", paste(result_ids, collapse = ",")), params = list(new_player_id))
    message(sprintf("[fix]   Moved %d results to new player", length(result_ids)))

    # 3. Clear Bandai ID from BOTH players
    dbExecute(db_con, "UPDATE players SET member_number = NULL WHERE player_id = $1", params = list(player_id))
    message(sprintf("[fix]   Cleared Bandai ID from original player (id: %d)", player_id))

    # New player was created without member_number, so already NULL

    dbCommit(db_con)
    message(sprintf("[fix]   Transaction committed successfully"))

    # Return summary for Discord
    list(
      original_player_id = player_id,
      new_player_id = new_player_id,
      display_name = display_name,
      original_bandai = original_bandai,
      majority_scene = majority_scene_name,
      majority_results = majority_result_count,
      minority_scene = minority_scene_name,
      minority_results = nrow(results_to_move),
      stores_affected = unique(results_to_move$store_name)
    )

  }, error = function(e) {
    dbRollback(db_con)
    message(sprintf("[fix]   ERROR: %s", e$message))
    message("[fix]   Transaction rolled back")
    NULL
  })
}

# -----------------------------------------------------------------------------
# Main: Process all players
# -----------------------------------------------------------------------------

message("\n========================================")
message("Cross-Scene Player Split Fix")
message("========================================")
message(sprintf("Players to process: %d", length(PLAYERS_TO_SPLIT)))

results <- list()

for (p in PLAYERS_TO_SPLIT) {
  result <- split_player(p$player_id, p$display_name, p$minority_scene_name)
  if (!is.null(result)) {
    results <- c(results, list(result))
  }
}

# -----------------------------------------------------------------------------
# Generate Discord Summary
# -----------------------------------------------------------------------------

message("\n========================================")
message("DISCORD NOTIFICATION SUMMARY")
message("========================================")
message("\nCopy the sections below to post in respective scene Discord threads:\n")

# Group by minority scene (the scene that needs notification)
scenes_affected <- unique(sapply(results, function(r) r$minority_scene))

for (scene in scenes_affected) {
  scene_results <- Filter(function(r) r$minority_scene == scene, results)

  message(sprintf("\n--- %s ---\n", scene))
  message("**Player Data Cleanup Notice**\n")
  message("The following player(s) were split due to name collision with players in other regions:\n")

  for (r in scene_results) {
    message(sprintf("- **%s** - %d result(s) at: %s",
                    r$display_name,
                    r$minority_results,
                    paste(r$stores_affected, collapse = ", ")))
  }

  message("\nTheir Bandai ID has been cleared. Please re-verify their member number on their next tournament entry.")
  message("")
}

# Also notify majority scenes
majority_scenes <- unique(sapply(results, function(r) r$majority_scene))

for (scene in majority_scenes) {
  scene_results <- Filter(function(r) r$majority_scene == scene, results)

  message(sprintf("\n--- %s ---\n", scene))
  message("**Player Data Cleanup Notice**\n")
  message("The following player(s) had their Bandai ID cleared due to a name collision fix:\n")

  for (r in scene_results) {
    message(sprintf("- **%s** (player_id: %d) - Please re-verify their member number on their next tournament entry.",
                    r$display_name,
                    r$original_player_id))
  }
  message("")
}

message("\n========================================")
message("Fix complete!")
message(sprintf("Split %d players successfully.", length(results)))
message("========================================\n")

# Clean up database connection
dbDisconnect(db_con)
message("[fix] Database connection closed")
