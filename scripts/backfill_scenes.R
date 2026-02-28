# scripts/backfill_scenes.R
# One-time script to backfill country and state_region for existing scenes
# via Mapbox reverse geocoding.
#
# Run: "/c/Program Files/R/R-4.5.1/bin/Rscript.exe" scripts/backfill_scenes.R

library(RPostgres)
library(httr2)
library(dotenv)
load_dot_env()

# Standalone reverse geocode (same logic as server/admin-stores-server.R)
reverse_geocode <- function(lat, lng, token) {
  tryCatch({
    url <- sprintf(
      "https://api.mapbox.com/geocoding/v5/mapbox.places/%s,%s.json?access_token=%s&types=region,country",
      lng, lat, token
    )

    resp <- request(url) |>
      req_headers(Referer = "http://localhost:3838/") |>
      req_timeout(10) |>
      req_perform()

    result <- resp_body_json(resp)

    country <- NA_character_
    state_region <- NA_character_

    if (length(result$features) > 0) {
      for (feat in result$features) {
        feat_id <- if (!is.null(feat$id)) feat$id else ""
        if (grepl("^country\\.", feat_id)) {
          country <- feat$text
        } else if (grepl("^region\\.", feat_id)) {
          state_region <- feat$text
        }
      }
    }

    list(country = country, state_region = state_region)
  }, error = function(e) {
    warning(paste("Reverse geocoding error:", e$message))
    list(country = NA_character_, state_region = NA_character_)
  })
}

# Connect
con <- dbConnect(Postgres(),
  host = Sys.getenv("NEON_HOST"),
  dbname = Sys.getenv("NEON_DATABASE"),
  user = Sys.getenv("NEON_USER"),
  password = Sys.getenv("NEON_PASSWORD"))

mapbox_token <- Sys.getenv("MAPBOX_ACCESS_TOKEN")
if (mapbox_token == "") stop("MAPBOX_ACCESS_TOKEN not set in .env")

# Find scenes needing backfill
scenes <- dbGetQuery(con,
  "SELECT scene_id, display_name, latitude, longitude
   FROM scenes
   WHERE latitude IS NOT NULL AND longitude IS NOT NULL
     AND (country IS NULL OR state_region IS NULL)")

cat(sprintf("Found %d scenes to backfill\n", nrow(scenes)))

for (i in seq_len(nrow(scenes))) {
  s <- scenes[i, ]
  cat(sprintf("  [%d/%d] %s ... ", i, nrow(scenes), s$display_name))

  geo <- reverse_geocode(s$latitude, s$longitude, mapbox_token)
  cat(sprintf("%s, %s\n", geo$country, geo$state_region))

  dbExecute(con,
    "UPDATE scenes SET country = $1, state_region = $2 WHERE scene_id = $3",
    params = list(geo$country, geo$state_region, s$scene_id))

  Sys.sleep(0.5)  # Rate limiting
}

dbDisconnect(con)
cat("Done!\n")
