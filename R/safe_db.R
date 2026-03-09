# =============================================================================
# safe_db.R — Global safe database wrappers
# =============================================================================
# Extracted from shared-server.R so R/ utility files (ratings.R, admin_grid.R)
# can use the same retry + error handling logic.
#
# The server-scoped wrappers in shared-server.R delegate to these _impl functions
# and add session-level Sentry context tags.
# =============================================================================

#' Helper to detect retryable connection pool / prepared statement errors
#' @param msg Character. Error message string to check
#' @return TRUE if the error is a retryable prepared statement error
is_prepared_stmt_error <- function(msg) {
  grepl("prepared statement", msg, ignore.case = TRUE) ||
  grepl("bind message supplies", msg, ignore.case = TRUE) ||
  grepl("needs to be bound", msg, ignore.case = TRUE) ||
  grepl("multiple queries.*same column", msg, ignore.case = TRUE) ||
  grepl("Query requires \\d+ params", msg, ignore.case = TRUE) ||
  grepl("invalid input syntax", msg, ignore.case = TRUE)
}

#' Safe Database Query (Implementation)
#'
#' Executes a database query with error handling and retry logic for
#' prepared statement collisions. Returns a sensible default instead of
#' crashing the app if the query fails.
#'
#' @param pool Database connection pool or DBI connection
#' @param query Character. SQL query string
#' @param params List or NULL. Parameters for parameterized query (default: NULL)
#' @param default Default value to return on error (default: empty data.frame)
#' @param sentry_tags Named list of Sentry context tags (default: empty list)
#'
#' @return Query result on success, or default value on error
safe_query_impl <- function(pool, query, params = NULL, default = data.frame(), sentry_tags = list()) {
  # Time the query for performance monitoring
  start_time <- proc.time()[["elapsed"]]

  # First attempt
  result <- tryCatch({
    if (!is.null(params) && length(params) > 0) {
      DBI::dbGetQuery(pool, query, params = params)
    } else {
      DBI::dbGetQuery(pool, query)
    }
  }, error = function(e) e)

  # If prepared statement error, retry once (connection pool may have stale state)
  if (inherits(result, "error") && is_prepared_stmt_error(conditionMessage(result))) {
    message("[safe_query] Prepared statement error, retrying: ", conditionMessage(result))
    Sys.sleep(0.1)  # Brief pause before retry
    result <- tryCatch({
      if (!is.null(params) && length(params) > 0) {
        DBI::dbGetQuery(pool, query, params = params)
      } else {
        DBI::dbGetQuery(pool, query)
      }
    }, error = function(e) e)
  }

  # Log slow queries (>200ms)
  elapsed_ms <- (proc.time()[["elapsed"]] - start_time) * 1000
  if (elapsed_ms > 200) {
    query_preview <- substr(gsub("\\s+", " ", trimws(query)), 1, 120)
    rows <- if (is.data.frame(result)) nrow(result) else "?"
    message(sprintf("[SLOW QUERY %.0fms, %s rows] %s", elapsed_ms, rows, query_preview))
  }

  # Handle final result
  if (inherits(result, "error")) {
    query_preview <- substr(gsub("\\s+", " ", query), 1, 500)
    params_preview <- if (!is.null(params)) paste(sapply(params, as.character), collapse = ", ") else "NULL"
    message("[safe_query] Error: ", conditionMessage(result), " | Query: ", query_preview, " | Params: ", params_preview)
    if (exists("sentry_enabled") && isTRUE(sentry_enabled)) {
      tryCatch(
        sentryR::capture_exception(result, tags = c(
          sentry_tags,
          list(query_preview = query_preview, params = params_preview)
        )),
        error = function(se) NULL
      )
    }
    return(default)
  }

  result
}

#' Safe Database Execute (Implementation)
#'
#' Executes a database write operation (INSERT, UPDATE, DELETE) with error
#' handling and retry logic. Returns 0 rows affected instead of crashing on error.
#'
#' @param pool Database connection pool or DBI connection
#' @param query Character. SQL statement string
#' @param params List or NULL. Parameters for parameterized query (default: NULL)
#' @param sentry_tags Named list of Sentry context tags (default: empty list)
#'
#' @return Number of rows affected on success, or 0 on error
safe_execute_impl <- function(pool, query, params = NULL, sentry_tags = list()) {
  # Time the query for performance monitoring
  start_time <- proc.time()[["elapsed"]]

  # First attempt
  result <- tryCatch({
    if (!is.null(params) && length(params) > 0) {
      DBI::dbExecute(pool, query, params = params)
    } else {
      DBI::dbExecute(pool, query)
    }
  }, error = function(e) e)

  # If prepared statement error, retry once (connection pool may have stale state)
  if (inherits(result, "error") && is_prepared_stmt_error(conditionMessage(result))) {
    message("[safe_execute] Prepared statement error, retrying: ", conditionMessage(result))
    Sys.sleep(0.1)  # Brief pause before retry
    result <- tryCatch({
      if (!is.null(params) && length(params) > 0) {
        DBI::dbExecute(pool, query, params = params)
      } else {
        DBI::dbExecute(pool, query)
      }
    }, error = function(e) e)
  }

  # Log slow writes (>200ms)
  elapsed_ms <- (proc.time()[["elapsed"]] - start_time) * 1000
  if (elapsed_ms > 200) {
    query_preview <- substr(gsub("\\s+", " ", trimws(query)), 1, 120)
    message(sprintf("[SLOW EXECUTE %.0fms] %s", elapsed_ms, query_preview))
  }

  # Handle final result
  if (inherits(result, "error")) {
    message("[safe_execute] Error: ", conditionMessage(result))
    message("[safe_execute] Query: ", substr(gsub("\\s+", " ", query), 1, 200))
    if (exists("sentry_enabled") && isTRUE(sentry_enabled)) {
      tryCatch(sentryR::capture_exception(result, tags = sentry_tags), error = function(se) NULL)
    }
    return(0)
  }

  result
}
