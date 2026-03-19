# =============================================================================
# Backfill Store Slugs
# Generates URL-friendly slugs for all stores with NULL slug values,
# then refreshes materialized views so filters work correctly.
# =============================================================================

library(dotenv)
load_dot_env()
library(RPostgres)

# Reuse the same slug generation logic as shared-server.R
generate_slug <- function(text) {
  if (is.null(text) || !nzchar(trimws(text))) return(NA_character_)
  text |> trimws() |> tolower() |>
    gsub("[^a-z0-9]+", "-", x = _) |>
    gsub("^-|-$", "", x = _)
}

con <- dbConnect(Postgres(),
  host = Sys.getenv("NEON_HOST"),
  dbname = Sys.getenv("NEON_DATABASE"),
  user = Sys.getenv("NEON_USER"),
  password = Sys.getenv("NEON_PASSWORD"),
  sslmode = "require")

# Get all stores with NULL slugs
stores <- dbGetQuery(con, "
  SELECT store_id, name, slug FROM stores WHERE slug IS NULL ORDER BY store_id
")
cat(sprintf("Found %d stores with NULL slugs\n", nrow(stores)))

if (nrow(stores) == 0) {
  cat("Nothing to do.\n")
  dbDisconnect(con)
  quit(save = "no")
}

# Get existing slugs to avoid duplicates
existing_slugs <- dbGetQuery(con, "SELECT slug FROM stores WHERE slug IS NOT NULL")$slug

# Generate slugs and handle duplicates
all_slugs <- existing_slugs
updated <- 0
skipped <- 0

for (i in seq_len(nrow(stores))) {
  store_id <- stores$store_id[i]
  name <- stores$name[i]

  base_slug <- generate_slug(name)
  if (is.na(base_slug)) {
    cat(sprintf("  SKIP store_id=%d (empty name)\n", store_id))
    skipped <- skipped + 1
    next
  }

  # Find unique slug
  candidate <- base_slug
  suffix <- 2
  while (candidate %in% all_slugs) {
    candidate <- paste0(base_slug, "-", suffix)
    suffix <- suffix + 1
  }

  # Update the store (use interpolated SQL to avoid prepared statement collisions)
  escaped_slug <- gsub("'", "''", candidate)
  dbExecute(con, sprintf("UPDATE stores SET slug = '%s', updated_at = NOW() WHERE store_id = %d",
                         escaped_slug, store_id))
  all_slugs <- c(all_slugs, candidate)
  updated <- updated + 1

  if (updated %% 50 == 0) cat(sprintf("  Updated %d stores...\n", updated))
}

cat(sprintf("\nDone: %d updated, %d skipped\n", updated, skipped))

# Refresh materialized views
cat("\nRefreshing materialized views...\n")
views <- c("mv_player_store_stats", "mv_archetype_store_stats",
           "mv_tournament_list", "mv_store_summary")
for (v in views) {
  cat(sprintf("  Refreshing %s...\n", v))
  dbExecute(con, sprintf("REFRESH MATERIALIZED VIEW %s", v))
}

cat("All MVs refreshed.\n")

# Verify
remaining <- dbGetQuery(con, "SELECT COUNT(*) as n FROM stores WHERE slug IS NULL AND is_active = TRUE")$n
cat(sprintf("Remaining active stores with NULL slugs: %d\n", remaining))

dbDisconnect(con)
