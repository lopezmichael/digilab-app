# Run migration 009 - Add dual-color support to materialized views
# Adds secondary_color to mv_player_store_stats and winning deck color to mv_tournament_list.
# Usage: source("scripts/run_migration_009.R")

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

message("Running migration 009: Dual-color MV updates\n")

# Read and execute the migration SQL
sql <- readLines("db/migrations/009_mv_dual_color.sql")
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

  # Get a short description from the first comment or first line
  desc <- substr(clean, 1, 60)
  run(desc, stmt)
}

# Verify
message("\nVerification:")
for (v in c("mv_player_store_stats", "mv_tournament_list")) {
  cols <- tryCatch({
    result <- dbGetQuery(con, sprintf(
      "SELECT column_name FROM information_schema.columns
       WHERE table_name = '%s' ORDER BY ordinal_position", v))
    paste(result$column_name, collapse = ", ")
  }, error = function(e) "ERROR")
  count <- tryCatch({
    result <- dbGetQuery(con, sprintf("SELECT COUNT(*) as n FROM %s", v))
    result$n[1]
  }, error = function(e) "ERROR")
  message(sprintf("  %s: %s rows", v, count))
  message(sprintf("    columns: %s", cols))
}

dbDisconnect(con)
message("\nMigration 009 complete. Database connection closed.")
