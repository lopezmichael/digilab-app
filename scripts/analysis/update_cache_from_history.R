# Update player_ratings_cache from player_rating_history table
# and capture comparison snapshot
library(DBI)
library(RPostgres)
library(dotenv)
load_dot_env()

con <- dbConnect(Postgres(),
  host = Sys.getenv("NEON_HOST"),
  dbname = Sys.getenv("NEON_DATABASE"),
  user = Sys.getenv("NEON_USER"),
  password = Sys.getenv("NEON_PASSWORD"),
  sslmode = "require")

message("[update] Connected to database")

# Get final ratings from history (most recent rating_after for each player)
message("[update] Getting final ratings from history...")
new_ratings <- dbGetQuery(con, "
  WITH latest_history AS (
    SELECT DISTINCT ON (h.player_id)
           h.player_id, h.rating_after as competitive_rating, h.events_played
    FROM player_rating_history h
    JOIN tournaments t ON h.tournament_id = t.tournament_id
    ORDER BY h.player_id, t.event_date DESC, t.tournament_id DESC
  )
  SELECT * FROM latest_history
")

message(sprintf("[update] Found %d players with ratings in history", nrow(new_ratings)))

# Get achievement scores
message("[update] Calculating achievement scores...")
source("R/ratings.R")
achievement_scores <- calculate_achievement_scores(con)

# Merge
player_cache <- merge(new_ratings, achievement_scores, by = "player_id", all.x = TRUE)
player_cache$achievement_score[is.na(player_cache$achievement_score)] <- 0

message(sprintf("[update] Merged data: %d players", nrow(player_cache)))

# Update cache
message("[update] Updating player_ratings_cache...")
dbExecute(con, "DELETE FROM player_ratings_cache")
dbExecute(con, sprintf("
  INSERT INTO player_ratings_cache (player_id, competitive_rating, achievement_score, events_played)
  VALUES %s
", paste(sprintf("(%d, %d, %d, %d)",
         player_cache$player_id,
         as.integer(player_cache$competitive_rating),
         as.integer(player_cache$achievement_score),
         as.integer(player_cache$events_played)), collapse = ", ")))

message("[update] Player cache updated!")

# Also update store ratings
message("[update] Updating store_ratings_cache...")
store_ratings <- calculate_store_avg_player_rating(con, player_cache[, c("player_id", "competitive_rating")])
if (nrow(store_ratings) > 0) {
  dbExecute(con, "DELETE FROM store_ratings_cache")
  dbExecute(con, sprintf("
    INSERT INTO store_ratings_cache (store_id, avg_player_rating)
    VALUES %s
  ", paste(sprintf("(%d, %d)", store_ratings$store_id, as.integer(store_ratings$avg_player_rating)), collapse = ", ")))
  message(sprintf("[update] Store cache updated: %d stores", nrow(store_ratings)))
}

dbDisconnect(con)
message("[update] Done!")

# Now capture post-redesign snapshot and compare
message("\n[update] Capturing post-redesign snapshot...")
source("scripts/analysis/rating_comparison.R")
capture_rating_snapshot("post_redesign")

message("\n[update] Running comparison...")
compare_rating_snapshots("pre_redesign", "post_redesign",
                         highlight_players = c("nudes", "photon", "atomshell"))
