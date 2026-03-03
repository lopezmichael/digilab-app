# Fix is_active NULL players and merge confirmed duplicates
# Run once to fix the data issue caused by is_active = TRUE filtering
# missing players with NULL is_active

dotenv::load_dot_env()
con <- DBI::dbConnect(RPostgres::Postgres(),
  host = Sys.getenv("NEON_HOST"),
  dbname = Sys.getenv("NEON_DATABASE"),
  user = Sys.getenv("NEON_USER"),
  password = Sys.getenv("NEON_PASSWORD"),
  sslmode = "require")

# --- Fix 1: Backfill NULL is_active to TRUE ---
cat("=== Backfilling NULL is_active to TRUE ===\n")
affected <- DBI::dbExecute(con, "UPDATE players SET is_active = TRUE WHERE is_active IS NULL")
cat("Updated", affected, "players\n\n")

# --- Fix 2: Merge confirmed duplicate pairs (same name, same member_number) ---
# These are Kenteiwolf (689 <- 1181) and Stlewis (684 <- 1202)
# Keep the older ID (more history), move results from newer ID

merge_pair <- function(con, keep_id, remove_id, name) {
  cat(sprintf("=== Merging %s: keep ID %d, remove ID %d ===\n", name, keep_id, remove_id))

  # Check results on each
  keep_results <- DBI::dbGetQuery(con, "SELECT COUNT(*)::int as n FROM results WHERE player_id = $1",
                                   params = list(keep_id))
  remove_results <- DBI::dbGetQuery(con, "SELECT COUNT(*)::int as n FROM results WHERE player_id = $1",
                                     params = list(remove_id))
  cat(sprintf("  Keep ID %d has %d results\n", keep_id, as.integer(keep_results$n)))
  cat(sprintf("  Remove ID %d has %d results\n", remove_id, as.integer(remove_results$n)))

  # Move results
  moved <- DBI::dbExecute(con, "UPDATE results SET player_id = $1 WHERE player_id = $2",
                           params = list(keep_id, remove_id))
  cat(sprintf("  Moved %d results\n", moved))

  # Move matches (as player)
  moved_matches <- DBI::dbExecute(con, "UPDATE matches SET player_id = $1 WHERE player_id = $2",
                                   params = list(keep_id, remove_id))
  cat(sprintf("  Moved %d matches (as player)\n", moved_matches))

  # Move matches (as opponent)
  moved_opp <- DBI::dbExecute(con, "UPDATE matches SET opponent_id = $1 WHERE opponent_id = $2",
                                params = list(keep_id, remove_id))
  cat(sprintf("  Moved %d matches (as opponent)\n", moved_opp))

  # Move rating history
  moved_history <- DBI::dbExecute(con, "UPDATE player_rating_history SET player_id = $1 WHERE player_id = $2",
                                   params = list(keep_id, remove_id))
  cat(sprintf("  Moved %d rating history entries\n", moved_history))

  # Move rating cache
  DBI::dbExecute(con, "DELETE FROM player_ratings_cache WHERE player_id = $1",
                  params = list(remove_id))

  # Move rating snapshots
  moved_snapshots <- DBI::dbExecute(con, "UPDATE rating_snapshots SET player_id = $1 WHERE player_id = $2",
                                     params = list(keep_id, remove_id))
  cat(sprintf("  Moved %d rating snapshots\n", moved_snapshots))

  # Soft-delete the duplicate
  DBI::dbExecute(con, "UPDATE players SET is_active = FALSE WHERE player_id = $1",
                  params = list(remove_id))
  cat(sprintf("  Soft-deleted player %d\n\n", remove_id))
}

merge_pair(con, keep_id = 689, remove_id = 1181, name = "Kenteiwolf")
merge_pair(con, keep_id = 684, remove_id = 1202, name = "Stlewis")

# --- Verify ---
cat("=== Verification ===\n")
for (pid in c(689L, 1181L, 684L, 1202L)) {
  info <- DBI::dbGetQuery(con, "
    SELECT p.player_id, p.display_name, p.is_active,
           (SELECT COUNT(*) FROM results WHERE player_id = p.player_id)::int as results
    FROM players p WHERE p.player_id = $1
  ", params = list(pid))
  cat(sprintf("  ID %d | %s | active=%s | results=%d\n",
      info$player_id, info$display_name, info$is_active, as.integer(info$results)))
}

cat("\nNull is_active remaining: ")
remaining <- DBI::dbGetQuery(con, "SELECT COUNT(*)::int as n FROM players WHERE is_active IS NULL")
cat(as.integer(remaining$n), "\n")

DBI::dbDisconnect(con)
cat("\nDone!\n")
