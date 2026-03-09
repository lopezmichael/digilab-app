# =============================================================================
# Database Connection Module
# DigiLab - https://app.digilab.cards/
#
# Uses Neon PostgreSQL via pool + RPostgres.
# Single connection pool shared across the app.
# =============================================================================

library(DBI)
library(pool)
library(RPostgres)

# -----------------------------------------------------------------------------
# Connection Pool
# -----------------------------------------------------------------------------

#' Create database connection pool
#'
#' @description
#' Creates a pool of connections to Neon PostgreSQL.
#' Requires NEON_HOST, NEON_USER, NEON_PASSWORD env vars.
#' NEON_DATABASE defaults to "neondb" if not set.
#'
#' @return pool object
#' @export
create_db_pool <- function() {
  host <- Sys.getenv("NEON_HOST")
  dbname <- Sys.getenv("NEON_DATABASE", "neondb")
  user <- Sys.getenv("NEON_USER")
  password <- Sys.getenv("NEON_PASSWORD")

  if (host == "" || password == "") {
    stop("NEON_HOST and NEON_PASSWORD environment variables are required. See .env.example")
  }

  tryCatch({
    p <- dbPool(
      RPostgres::Postgres(),
      host = host,
      dbname = dbname,
      user = user,
      password = password,
      port = 5432,
      sslmode = "require",
      bigint = "integer",
      minSize = 1,
      maxSize = 5,
      idleTimeout = 600,         # Keep idle connections 10min (Neon auto-suspends at 5min)
      validationInterval = 60    # Check connection health every 60s
    )
    message("Connected to Neon PostgreSQL: ", dbname, " @ ", host)
    p
  }, error = function(e) {
    stop("Database connection failed: ", e$message)
  })
}

#' Close the connection pool
#' @param p pool object
#' @export
close_db_pool <- function(p) {
  if (!is.null(p)) {
    tryCatch({
      poolClose(p)
      message("Database pool closed")
    }, error = function(e) {
      message("Error closing pool: ", e$message)
    })
  }
}

# -----------------------------------------------------------------------------
# Schema Functions
# -----------------------------------------------------------------------------

#' Initialize database schema
#' @param pool pool object
#' @param schema_path Path to SQL schema file
#' @export
init_schema <- function(pool, schema_path = "db/schema.sql") {
  if (!file.exists(schema_path)) {
    stop("Schema file not found: ", schema_path)
  }

  lines <- readLines(schema_path, warn = FALSE)
  lines <- lines[!grepl("^\\s*--", lines)]
  schema_sql <- paste(lines, collapse = "\n")
  statements <- strsplit(schema_sql, ";")[[1]]

  success_count <- 0
  fail_count <- 0

  for (stmt in statements) {
    stmt <- trimws(stmt)
    if (stmt == "" || nchar(stmt) < 5) next

    tryCatch({
      dbExecute(pool, paste0(stmt, ";"))
      success_count <- success_count + 1
    }, error = function(e) {
      if (!grepl("already exists", e$message, ignore.case = TRUE)) {
        fail_count <<- fail_count + 1
        stmt_preview <- substr(gsub("\\s+", " ", stmt), 1, 60)
        warning("FAILED: ", stmt_preview, "...\n  Error: ", e$message)
      }
    })
  }

  message("Schema initialized (", success_count, " statements executed)")
}

#' Verify all required tables exist
#' @param pool pool object
#' @return Logical
#' @export
check_schema <- function(pool) {
  required <- c("stores", "players", "deck_archetypes",
                "archetype_cards", "tournaments", "results")

  existing <- dbListTables(pool)
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
#' @param pool pool object
#' @param sql SQL query string
#' @return Data frame
#' @export
query <- function(pool, sql) {
  dbGetQuery(pool, sql)
}

#' Log a data operation
#' @export
log_operation <- function(pool, source, action, status, records = 0, error = NULL) {
  dbExecute(pool,
    "INSERT INTO ingestion_log (source, action, status, records_affected, error_message)
     VALUES ($1, $2, $3, $4, $5)",
    params = list(source, action, status, records, error))
}
