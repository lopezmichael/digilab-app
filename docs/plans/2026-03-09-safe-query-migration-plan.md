# Safe Query Migration Plan

**Date:** 2026-03-09
**Target Version:** v1.5.0
**Status:** In Progress

## Goal

Migrate all remaining raw `dbGetQuery`/`dbExecute` calls in `server/` files to `safe_query`/`safe_execute` wrappers. These wrappers provide:
- Prepared statement retry logic (handles stale pool connections)
- Sentry error reporting (already wired in)
- Graceful fallback to defaults on error

## Scope

**160 raw calls** across 12 files:
- **136 calls** across 10 server/ files — migrate to `safe_query`/`safe_execute` (Batches 1-6)
- **24 calls** across 2 R/ utility files (`ratings.R`, `admin_grid.R`) — requires extracting `safe_query`/`safe_execute` to global scope first (Batch 7)
- **6 calls** across 3 R/ files (`db_connection.R`, `discord_webhook.R`, `digimoncard_api.R`) — skipped; bootstrap/low-frequency code with existing tryCatch blocks

## Transaction Bug Fix

**Found during audit:** `admin-results-server.R` and `admin-tournaments-server.R` do multi-statement operations (tournament + results) without transactions. If a failure occurs mid-loop, the database is left in a partial state. `public-submit-server.R` already handles this correctly with `localCheckout` + BEGIN/COMMIT/ROLLBACK.

### Fix: Add transaction blocks to 3 locations

1. **`admin-results-server.R` — Submit Results (Step 2)**
   - Creates tournament, loops inserting results, then recalculates ratings
   - Wrap tournament creation + results loop in BEGIN/COMMIT
   - Pass checked-out `conn` to `match_player()` (it already accepts a `con` parameter)
   - Convert inner `dbGetQuery`/`dbExecute` to use `conn` (raw DBI, not safe_*)

2. **`admin-tournaments-server.R` — Edit Tournament Save**
   - Deletes removed results, updates existing, inserts new — all in a loop
   - Wrap the entire delete/update/insert block in BEGIN/COMMIT
   - Inner calls already use `safe_execute(db_pool, ...)` — convert to `DBI::dbExecute(conn, ...)`
   - Pass `conn` to `match_player()`

3. **`admin-tournaments-server.R` — Delete Tournament**
   - Deletes results then tournament (2 statements)
   - Wrap in BEGIN/COMMIT for atomicity

### Transaction rules
- Calls INSIDE transaction blocks use raw `DBI::dbGetQuery(conn, ...)`/`DBI::dbExecute(conn, ...)`
- Add comment: `# Transaction block: raw DBI calls intentional (retry would break atomicity)`
- Calls OUTSIDE transaction blocks use `safe_query`/`safe_execute`

## Migration Batches

All batches are independent and can run in parallel.

### Batch 1: `server/admin-decks-server.R` (31 calls)
- Straightforward mechanical migration
- No transactions needed
- Largest file — good parallel candidate

### Batch 2: `server/admin-results-server.R` (20 calls)
- **Also adds transaction block** around Step 2 submit
- Calls outside the transaction → `safe_query`/`safe_execute`
- Calls inside the transaction → raw `DBI::` on checked-out `conn`

### Batch 3: `server/public-submit-server.R` (20 calls, ~10 in existing transactions)
- Existing transaction blocks at lines 1271 and 1899 — leave raw DBI calls as-is
- Migrate ~10 calls outside transactions to `safe_query`/`safe_execute`

### Batch 4: `server/admin-stores-server.R` (14) + `server/admin-formats-server.R` (6)
- Straightforward mechanical migration
- No transactions needed

### Batch 5: `server/admin-tournaments-server.R` (14) + `server/admin-players-server.R` (13)
- **Also adds transaction blocks** for edit-save and delete-tournament
- Edit-save inner calls (currently `safe_execute`) → raw `DBI::dbExecute(conn, ...)`
- Delete tournament (2 calls) → wrap in BEGIN/COMMIT
- admin-players-server.R is straightforward

### Batch 6: `server/shared-server.R` (12) + `server/url-routing-server.R` (5) + `server/scene-server.R` (1)
- shared-server.R line 1677 `refresh_materialized_views` uses localCheckout — leave as-is
- Migrate remaining calls
- url-routing and scene-server are straightforward

### Batch 7: Extract `safe_query`/`safe_execute` to global scope + migrate `R/ratings.R` (17) + `R/admin_grid.R` (7)

**Prerequisite step:** Extract `safe_query`/`safe_execute` from the server function in `shared-server.R` into a new `R/safe_db.R` file that's sourced at app startup (global scope).

**The problem:** `safe_query`/`safe_execute` are currently closures inside the Shiny server function. They capture `sentry_enabled` and `sentry_context_tags()` from the server scope. R/ files are sourced before the server function runs, so they can't call these wrappers.

**The fix:**
1. Create `R/safe_db.R` with `safe_query_impl()` and `safe_execute_impl()` that accept an optional `sentry_tags` parameter (defaulting to `list()`)
2. `sentry_enabled` is already global (defined in `app.R` line ~380) — no change needed
3. In `shared-server.R`, replace the current definitions with thin wrappers that pass `sentry_context_tags()`:
   ```r
   safe_query <- function(pool, query, params = NULL, default = data.frame()) {
     safe_query_impl(pool, query, params, default, sentry_tags = sentry_context_tags())
   }
   safe_execute <- function(pool, query, params = NULL) {
     safe_execute_impl(pool, query, params, sentry_tags = sentry_context_tags())
   }
   ```
4. R/ files call `safe_query_impl()`/`safe_execute_impl()` directly (no session-level Sentry tags, but still get retry logic + Sentry exception capture)

**Then migrate:**
- `R/ratings.R` (17 calls) — Heavy multi-query rating recalculation, called after every tournament submit. Most likely to hit stale prepared statement errors.
- `R/admin_grid.R` (7 calls) — `match_player()` and grid helpers. Note: `match_player()` is also called inside transaction blocks with a checked-out `conn` — those calls stay as raw DBI since `safe_query_impl` retry logic would break the transaction. Only migrate calls that receive `db_pool` (not `conn`).

## Migration Pattern

```r
# BEFORE
result <- dbGetQuery(db_pool, "SELECT ...", params = list(...))

# AFTER — for queries that return data
result <- safe_query(db_pool, "SELECT ...", params = list(...), default = data.frame())

# AFTER — for queries returning specific columns used downstream
result <- safe_query(db_pool, "SELECT name FROM ...",
                     params = list(...),
                     default = data.frame(name = character()))

# BEFORE
dbExecute(db_pool, "UPDATE ...", params = list(...))

# AFTER
safe_execute(db_pool, "UPDATE ...", params = list(...))
```

## Verification

- Grep for remaining `dbGetQuery`/`dbExecute` in `server/` — should be zero outside transaction blocks
- Grep for remaining `dbGetQuery`/`dbExecute` in `R/ratings.R` and `R/admin_grid.R` — should be zero outside transaction-context calls
- `R/safe_db.R` exists and is sourced in `app.R` before other R/ files
- `shared-server.R` wrappers delegate to `safe_query_impl`/`safe_execute_impl`
- App loads without error
- Test Enter Results, Edit Tournament, and Delete Tournament flows
- Test rating recalculation (triggered by any tournament submit)
