# Roll back: Clear the player_rating_history table
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

count_before <- dbGetQuery(con, "SELECT COUNT(*) as count FROM player_rating_history")$count
message(sprintf("Entries before rollback: %d", as.integer(count_before)))

dbExecute(con, "DELETE FROM player_rating_history")

count_after <- dbGetQuery(con, "SELECT COUNT(*) as count FROM player_rating_history")$count
message(sprintf("Entries after rollback: %d", as.integer(count_after)))

dbDisconnect(con)
message("Rollback complete - history table cleared")
