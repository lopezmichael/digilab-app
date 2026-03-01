# scripts/analysis/run_rating_rebuild.R
# Runs full rating rebuild with new single-pass algorithm
# and captures post-redesign snapshot for comparison
#
# Usage: source("scripts/analysis/run_rating_rebuild.R")

library(DBI)
library(RPostgres)
library(dotenv)

load_dot_env()

# Source the ratings module
source("R/ratings.R")

message("\n========================================")
message("Rating System Rebuild (Single-Pass)")
message("========================================\n")

# Connect to database
db_con <- dbConnect(
  Postgres(),
  host = Sys.getenv("NEON_HOST"),
  dbname = Sys.getenv("NEON_DATABASE"),
  user = Sys.getenv("NEON_USER"),
  password = Sys.getenv("NEON_PASSWORD"),
  sslmode = "require"
)

message("[rebuild] Connected to database\n")

# Run full rebuild with new algorithm
message("[rebuild] Running full rebuild with single-pass algorithm...")
start_time <- Sys.time()

result <- recalculate_ratings_cache(db_con, from_date = NULL, use_legacy = FALSE)

end_time <- Sys.time()
elapsed <- round(as.numeric(difftime(end_time, start_time, units = "secs")), 2)

if (result) {
  message(sprintf("\n[rebuild] Rebuild complete in %.2f seconds", elapsed))
} else {
  message("\n[rebuild] ERROR: Rebuild failed!")
}

# Disconnect
dbDisconnect(db_con)
message("[rebuild] Database connection closed\n")

# Capture post-redesign snapshot
message("[rebuild] Capturing post-redesign snapshot...\n")
source("scripts/analysis/rating_comparison.R")
capture_rating_snapshot("post_redesign")

# Run comparison
message("\n[rebuild] Running comparison...\n")
compare_rating_snapshots("pre_redesign", "post_redesign",
                         highlight_players = c("nudes", "photon", "atomshell"))

message("\n========================================")
message("Rebuild Complete!")
message("========================================")
