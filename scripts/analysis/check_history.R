# Check rating history table
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

# Check history table
count <- dbGetQuery(con, "SELECT COUNT(*) as count FROM player_rating_history")
message("Rating history entries: ", count$count)

# Sample some history - biggest rating changes
message("\nBiggest rating changes:")
sample <- dbGetQuery(con, "
  SELECT h.player_id, p.display_name, h.rating_before, h.rating_after, h.rating_change, h.events_played
  FROM player_rating_history h
  JOIN players p ON h.player_id = p.player_id
  ORDER BY ABS(h.rating_change) DESC
  LIMIT 15
")
print(sample)

# Check a specific player's history
message("\nNudes rating history:")
nudes <- dbGetQuery(con, "
  SELECT h.player_id, t.event_date, h.rating_before, h.rating_after, h.rating_change, h.events_played
  FROM player_rating_history h
  JOIN tournaments t ON h.tournament_id = t.tournament_id
  WHERE h.player_id = 15
  ORDER BY t.event_date
")
print(nudes)

dbDisconnect(con)
