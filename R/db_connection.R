# =============================================================================
# Database Connection Module
# DigiLab - https://digilab.cards/
#
# Auto-detects environment:
#   - Local Windows dev → uses local DuckDB file
#   - Posit Connect (Linux) → uses MotherDuck cloud
# =============================================================================

library(DBI)
library(duckdb)

# -----------------------------------------------------------------------------
# Main Connection Function - Just use this one
# -----------------------------------------------------------------------------

#' Connect to database (auto-detects environment)
#'
#' @description
#' Automatically chooses the right connection:
#' - On Posit Connect or Linux with MOTHERDUCK_TOKEN set → MotherDuck cloud
#' - Otherwise → Local DuckDB file (data/local.duckdb)
#'
#' @return DBI connection object
#' @export
connect_db <- function() {

 # Check if we should use MotherDuck
  use_motherduck <- can_use_motherduck()

  if (use_motherduck) {
    return(connect_motherduck())
  } else {
    return(connect_local())
  }
}

#' Check if MotherDuck connection is available
#' @return Logical
can_use_motherduck <- function() {
  # Need token
  token <- Sys.getenv("MOTHERDUCK_TOKEN")
  if (token == "") return(FALSE)

  # Check if we're on Linux (Posit Connect) or if extension is available
  is_linux <- Sys.info()["sysname"] == "Linux"

  # On Windows, MotherDuck extension isn't available for R
  is_windows <- Sys.info()["sysname"] == "Windows"
  if (is_windows) {
    message("Note: Using local database (MotherDuck not available on Windows R)")
    return(FALSE)
  }

  return(TRUE)
}

# -----------------------------------------------------------------------------
# Specific Connection Functions (used internally)
# -----------------------------------------------------------------------------

#' Connect to MotherDuck cloud database
#' @return DBI connection object
connect_motherduck <- function() {
  token <- Sys.getenv("MOTHERDUCK_TOKEN")
  db_name <- Sys.getenv("MOTHERDUCK_DATABASE", "digimon_tcg_dfw")

  tryCatch({
    con <- dbConnect(duckdb::duckdb())
    dbExecute(con, "INSTALL motherduck;")
    dbExecute(con, "LOAD motherduck;")
    dbExecute(con, sprintf("SET motherduck_token = '%s';", token))
    dbExecute(con, sprintf("ATTACH 'md:%s';", db_name))
    dbExecute(con, sprintf("USE %s;", db_name))
    message("Connected to MotherDuck: ", db_name)
    return(con)
  }, error = function(e) {
    stop("MotherDuck connection failed: ", e$message)
  })
}

#' Connect to local DuckDB file
#' @param db_path Path to database file
#' @return DBI connection object
connect_local <- function(db_path = "data/local.duckdb") {
  # Ensure data directory exists
  dir.create(dirname(db_path), showWarnings = FALSE, recursive = TRUE)

  tryCatch({
    con <- dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = FALSE)
    message("Connected to local database: ", db_path)
    return(con)
  }, error = function(e) {
    stop("Local connection failed: ", e$message)
  })
}

#' Disconnect from database
#' @param con DBI connection object
#' @export
disconnect <- function(con) {
  if (!is.null(con) && dbIsValid(con)) {
    dbDisconnect(con, shutdown = TRUE)
    message("Disconnected")
  }
}

# -----------------------------------------------------------------------------
# Schema Functions
# -----------------------------------------------------------------------------

#' Initialize database schema
#' @param con DBI connection object
#' @param schema_path Path to SQL schema file
#' @export
init_schema <- function(con, schema_path = "db/schema.sql") {
  if (!file.exists(schema_path)) {
    stop("Schema file not found: ", schema_path)
  }

  # Read file
  lines <- readLines(schema_path, warn = FALSE)

  # Remove comment lines (lines starting with --)
  lines <- lines[!grepl("^\\s*--", lines)]

  # Join and split by semicolon
  schema_sql <- paste(lines, collapse = "\n")
  statements <- strsplit(schema_sql, ";")[[1]]

  success_count <- 0
  fail_count <- 0

  for (stmt in statements) {
    stmt <- trimws(stmt)
    # Skip empty statements
    if (stmt == "" || nchar(stmt) < 5) next

    tryCatch({
      dbExecute(con, paste0(stmt, ";"))
      success_count <- success_count + 1
    }, error = function(e) {
      # Only warn if not "already exists"
      if (!grepl("already exists", e$message, ignore.case = TRUE)) {
        fail_count <<- fail_count + 1
        # Show more context for debugging
        stmt_preview <- substr(gsub("\\s+", " ", stmt), 1, 60)
        warning("FAILED: ", stmt_preview, "...\n  Error: ", e$message)
      }
    })
  }

  message("Schema initialized (", success_count, " statements executed)")
}

#' Verify all required tables exist
#' @param con DBI connection object
#' @return Logical
#' @export
check_schema <- function(con) {
  required <- c("stores", "players", "deck_archetypes",
                "archetype_cards", "tournaments", "results")

  existing <- dbListTables(con)
  missing <- setdiff(required, existing)

  if (length(missing) > 0) {
    warning("Missing tables: ", paste(missing, collapse = ", "))
    return(FALSE)
  }

  message("All tables present: ", paste(required, collapse = ", "))
  return(TRUE)
}

# -----------------------------------------------------------------------------
# Query Helpers
# -----------------------------------------------------------------------------

#' Run a query and return data frame
#' @param con DBI connection
#' @param sql SQL query string
#' @return Data frame
#' @export
query <- function(con, sql) {
  dbGetQuery(con, sql)
}

#' Log a data operation (for tracking imports/changes)
#' @export
log_operation <- function(con, source, action, status, records = 0, error = NULL) {
  sql <- "INSERT INTO ingestion_log (source, action, status, records_affected, error_message)
          VALUES (?, ?, ?, ?, ?)"
  dbExecute(con, sql, params = list(source, action, status, records, error))
}
