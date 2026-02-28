# scripts/migrate_scenes_columns.R
# One-time migration: add discord_thread_id, country, state_region to scenes table

library(RPostgres)
library(dotenv)
load_dot_env()

con <- dbConnect(Postgres(),
  host = Sys.getenv("NEON_HOST"),
  dbname = Sys.getenv("NEON_DATABASE"),
  user = Sys.getenv("NEON_USER"),
  password = Sys.getenv("NEON_PASSWORD"))

# Check current columns
cols <- dbGetQuery(con, "SELECT column_name FROM information_schema.columns WHERE table_name = 'scenes' ORDER BY ordinal_position")
cat("Current columns:", paste(cols$column_name, collapse = ", "), "\n")

# Add columns if they don't exist
if (!"discord_thread_id" %in% cols$column_name) {
  dbExecute(con, "ALTER TABLE scenes ADD COLUMN discord_thread_id TEXT")
  cat("Added: discord_thread_id\n")
} else {
  cat("Already exists: discord_thread_id\n")
}

if (!"country" %in% cols$column_name) {
  dbExecute(con, "ALTER TABLE scenes ADD COLUMN country TEXT")
  cat("Added: country\n")
} else {
  cat("Already exists: country\n")
}

if (!"state_region" %in% cols$column_name) {
  dbExecute(con, "ALTER TABLE scenes ADD COLUMN state_region TEXT")
  cat("Added: state_region\n")
} else {
  cat("Already exists: state_region\n")
}

# Verify
cols_after <- dbGetQuery(con, "SELECT column_name FROM information_schema.columns WHERE table_name = 'scenes' ORDER BY ordinal_position")
cat("\nColumns after migration:", paste(cols_after$column_name, collapse = ", "), "\n")

dbDisconnect(con)
cat("Done!\n")
