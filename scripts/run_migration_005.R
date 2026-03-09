# Run migration 005 - Materialized Views
# Creates 5 materialized views for pre-computed aggregations.
# Usage: source("scripts/run_migration_005.R")

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

# Read migration SQL
sql <- readLines("db/migrations/005_materialized_views.sql")
sql_text <- paste(sql, collapse = "\n")

# Split by semicolons and execute each statement
statements <- strsplit(sql_text, ";")[[1]]
statements <- trimws(statements)
statements <- statements[nchar(statements) > 0 & !grepl("^--", statements)]

# Filter out comment-only blocks
statements <- Filter(function(s) {
  lines <- strsplit(s, "\n")[[1]]
  lines <- trimws(lines)
  lines <- lines[nchar(lines) > 0]
  any(!grepl("^--", lines))
}, statements)

message(sprintf("Running migration 005: %d statements...\n", length(statements)))

for (i in seq_along(statements)) {
  stmt <- paste0(trimws(statements[i]), ";")
  # Extract first meaningful line for display
  lines <- strsplit(stmt, "\n")[[1]]
  first_line <- trimws(lines[!grepl("^--", trimws(lines)) & nchar(trimws(lines)) > 0][1])
  first_line <- substr(first_line, 1, 80)

  tryCatch({
    dbExecute(con, stmt)
    message(sprintf("  [%d/%d] OK: %s", i, length(statements), first_line))
  }, error = function(e) {
    message(sprintf("  [%d/%d] ERROR: %s\n         %s", i, length(statements), first_line, e$message))
  })
}

# Verify all views exist
views <- c("mv_player_store_stats", "mv_archetype_store_stats",
           "mv_tournament_list", "mv_store_summary", "mv_dashboard_counts")

message("\nVerification:")
for (v in views) {
  count <- tryCatch({
    result <- dbGetQuery(con, sprintf("SELECT COUNT(*) as n FROM %s", v))
    result$n[1]
  }, error = function(e) "MISSING")
  message(sprintf("  %s: %s rows", v, count))
}

dbDisconnect(con)
message("\nMigration 005 complete. Database connection closed.")
