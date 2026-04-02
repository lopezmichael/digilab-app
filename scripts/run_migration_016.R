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

# Read and execute migration SQL
sql <- readLines("db/migrations/016_leaderboard_cache_columns.sql")
sql_text <- paste(sql, collapse = "\n")

# Split on semicolons and execute each statement
statements <- strsplit(sql_text, ";")[[1]]
statements <- trimws(statements)
statements <- statements[nchar(statements) > 0 & !grepl("^--", statements)]

for (stmt in statements) {
  # Skip pure comment blocks
  clean <- gsub("--[^\n]*", "", stmt)
  clean <- trimws(clean)
  if (nchar(clean) == 0) next

  # Extract a short description from the statement
  desc <- if (grepl("ALTER TABLE", stmt, ignore.case = TRUE)) {
    sub(".*ADD COLUMN IF NOT EXISTS (\\w+).*", "Add column \\1", stmt)
  } else if (grepl("CREATE TABLE", stmt, ignore.case = TRUE)) {
    sub(".*CREATE TABLE IF NOT EXISTS (\\w+).*", "Create table \\1", stmt)
  } else if (grepl("CREATE INDEX", stmt, ignore.case = TRUE)) {
    sub(".*CREATE INDEX IF NOT EXISTS (\\w+).*", "Create index \\1", stmt)
  } else if (grepl("INSERT INTO", stmt, ignore.case = TRUE)) {
    "Seed leaderboard_stats_cache"
  } else {
    substr(clean, 1, 60)
  }

  run(desc, paste0(stmt, ";"))
}

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
