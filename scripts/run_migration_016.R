# Run migration 016 - Leaderboard cache columns
# Adds pre-computed stats, rank, country, and top deck to player_ratings_cache.
# Creates leaderboard_stats_cache table for aggregate stats.
# Usage: source("scripts/run_migration_016.R")

library(DBI)
library(RPostgres)
library(dotenv)

load_dot_env()

message("Connecting to database...")

con <- dbConnect(
  Postgres(),
  host = Sys.getenv("NEON_HOST"),
  dbname = Sys.getenv("NEON_DATABASE"),
  user = Sys.getenv("NEON_USER"),
  password = Sys.getenv("NEON_PASSWORD"),
  sslmode = "require"
)

run <- function(desc, sql) {
  tryCatch({
    dbExecute(con, sql)
    message(sprintf("  OK: %s", desc))
  }, error = function(e) {
    message(sprintf("  ERROR: %s\n         %s", desc, e$message))
  })
}

message("\n=== Migration 016: Leaderboard Cache Columns ===\n")

# Execute each statement individually for clear error reporting
run("Add column global_rank",
    "ALTER TABLE player_ratings_cache ADD COLUMN IF NOT EXISTS global_rank INT")
run("Add column match_wins",
    "ALTER TABLE player_ratings_cache ADD COLUMN IF NOT EXISTS match_wins INT NOT NULL DEFAULT 0")
run("Add column match_losses",
    "ALTER TABLE player_ratings_cache ADD COLUMN IF NOT EXISTS match_losses INT NOT NULL DEFAULT 0")
run("Add column match_ties",
    "ALTER TABLE player_ratings_cache ADD COLUMN IF NOT EXISTS match_ties INT NOT NULL DEFAULT 0")
run("Add column win_pct",
    "ALTER TABLE player_ratings_cache ADD COLUMN IF NOT EXISTS win_pct NUMERIC")
run("Add column first_count",
    "ALTER TABLE player_ratings_cache ADD COLUMN IF NOT EXISTS first_count INT NOT NULL DEFAULT 0")
run("Add column top3_count",
    "ALTER TABLE player_ratings_cache ADD COLUMN IF NOT EXISTS top3_count INT NOT NULL DEFAULT 0")
run("Add column top_archetype_id",
    "ALTER TABLE player_ratings_cache ADD COLUMN IF NOT EXISTS top_archetype_id INT")
run("Add column country",
    "ALTER TABLE player_ratings_cache ADD COLUMN IF NOT EXISTS country TEXT")

run("Create leaderboard_stats_cache table",
    "CREATE TABLE IF NOT EXISTS leaderboard_stats_cache (
       id INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),
       median_rating NUMERIC,
       total_rated_players INT,
       last_computed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
     )")

run("Seed leaderboard_stats_cache",
    "INSERT INTO leaderboard_stats_cache (id, median_rating, total_rated_players)
     VALUES (1, 1500, 0)
     ON CONFLICT (id) DO NOTHING")

run("Create index idx_prc_global_rank",
    "CREATE INDEX IF NOT EXISTS idx_prc_global_rank ON player_ratings_cache (global_rank)")
run("Create index idx_prc_country",
    "CREATE INDEX IF NOT EXISTS idx_prc_country ON player_ratings_cache (country)")

message("\n=== Migration 016 complete ===")

# Trigger a full cache rebuild to populate the new columns
message("\nRebuilding ratings cache with new columns...")
source("R/safe_db.R")
source("R/ratings.R")
result <- recalculate_ratings_cache(con)
if (result) {
  message("Cache rebuild successful!")
} else {
  message("Cache rebuild failed - check errors above")
}

dbDisconnect(con)
message("Done.")
