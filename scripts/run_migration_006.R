# Run migration 006 - Record Format & Points Columns
# Adds record_format to tournaments and points to results.
# Usage: source("scripts/run_migration_006.R")

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

message("Running migration 006: Record Format & Points\n")

run("Add record_format to tournaments",
    "ALTER TABLE tournaments ADD COLUMN IF NOT EXISTS record_format TEXT DEFAULT 'points'")

run("Add points to results",
    "ALTER TABLE results ADD COLUMN IF NOT EXISTS points INTEGER")

run("Backfill points for existing results",
    "UPDATE results SET points = (wins * 3) + ties WHERE points IS NULL")

# Verify
message("\nVerification:")
fmt_count <- dbGetQuery(con, "SELECT COUNT(*)::int as n FROM tournaments WHERE record_format IS NOT NULL")
message(sprintf("  Tournaments with record_format: %d", fmt_count$n))
pts_count <- dbGetQuery(con, "SELECT COUNT(*)::int as n FROM results WHERE points IS NOT NULL")
message(sprintf("  Results with points: %d", pts_count$n))
null_count <- dbGetQuery(con, "SELECT COUNT(*)::int as n FROM results WHERE points IS NULL")
message(sprintf("  Results still missing points: %d", null_count$n))

dbDisconnect(con)
message("\nMigration 006 complete. Database connection closed.")
