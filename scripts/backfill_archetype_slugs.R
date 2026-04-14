# Backfill NULL slugs in deck_archetypes table
# Uses the same generate_slug() logic from R/admin_grid.R
#
# Usage: Rscript scripts/backfill_archetype_slugs.R

library(DBI)
library(RPostgres)
dotenv::load_dot_env()

generate_slug <- function(text) {
  if (is.null(text) || !nzchar(trimws(text))) return(NA_character_)
  text |> trimws() |> tolower() |>
    gsub("[^a-z0-9]+", "-", x = _) |>
    gsub("^-|-$", "", x = _)
}

con <- dbConnect(Postgres(),
  host     = Sys.getenv("NEON_HOST"),
  dbname   = Sys.getenv("NEON_DATABASE"),
  user     = Sys.getenv("NEON_USER"),
  password = Sys.getenv("NEON_PASSWORD"),
  sslmode  = "require"
)
on.exit(dbDisconnect(con))

# Find all archetypes with NULL slug
missing <- dbGetQuery(con, "SELECT archetype_id, archetype_name FROM deck_archetypes WHERE slug IS NULL")

if (nrow(missing) == 0) {
  message("No archetypes with NULL slug found.")
} else {
  message(sprintf("Found %d archetypes with NULL slug:", nrow(missing)))

  # Pre-fetch all existing slugs to check uniqueness in memory
  existing_slugs <- dbGetQuery(con, "SELECT slug FROM deck_archetypes WHERE slug IS NOT NULL")$slug

  updates <- data.frame(id = integer(), slug = character(), stringsAsFactors = FALSE)

  for (i in seq_len(nrow(missing))) {
    id   <- missing$archetype_id[i]
    name <- missing$archetype_name[i]
    slug <- generate_slug(name)

    # Check uniqueness against existing + already-assigned slugs
    all_slugs <- c(existing_slugs, updates$slug)
    if (slug %in% all_slugs) {
      for (j in 2:100) {
        candidate <- paste0(slug, "-", j)
        if (!(candidate %in% all_slugs)) { slug <- candidate; break }
      }
    }

    updates <- rbind(updates, data.frame(id = id, slug = slug, stringsAsFactors = FALSE))
    message(sprintf("  %s -> %s", name, slug))
  }

  # Apply all updates
  rs <- dbSendStatement(con, "UPDATE deck_archetypes SET slug = $1 WHERE archetype_id = $2")
  for (i in seq_len(nrow(updates))) {
    dbBind(rs, list(updates$slug[i], updates$id[i]))
  }
  dbClearResult(rs)

  message(sprintf("Done. Updated %d archetypes.", nrow(updates)))
}
