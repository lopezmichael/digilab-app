# scripts/backfill_player_scenes.R
# One-time backfill: populate player_scenes table and sync home_scene_id
#
# Usage: Rscript scripts/backfill_player_scenes.R
# Requires: .env with NEON_* credentials

library(dotenv)
load_dot_env()

source("R/db_connection.R")
source("R/safe_db.R")
source("R/ratings.R")

db_pool <- create_db_pool()
on.exit(pool::poolClose(db_pool))

message("=== Backfilling player_scenes ===")

n <- refresh_player_scenes(db_pool, threshold = 3)
message(sprintf("Created %d player-scene associations", n))

# Verification: show players with multiple scene associations
multi_scene <- safe_query_impl(db_pool, "
  SELECT p.display_name, COUNT(*) AS scene_count,
         string_agg(sc.name, ', ' ORDER BY ps.is_home DESC, ps.events_played DESC) AS scenes
  FROM player_scenes ps
  JOIN players p USING (player_id)
  JOIN scenes sc USING (scene_id)
  GROUP BY p.display_name
  HAVING COUNT(*) > 1
  ORDER BY COUNT(*) DESC
  LIMIT 20
")

if (nrow(multi_scene) > 0) {
  message(sprintf("\n=== Players on multiple scene leaderboards (%d total) ===", nrow(multi_scene)))
  for (i in seq_len(nrow(multi_scene))) {
    message(sprintf("  %s (%d scenes): %s",
                    multi_scene$display_name[i],
                    multi_scene$scene_count[i],
                    multi_scene$scenes[i]))
  }
} else {
  message("\nNo players qualified for multiple scenes (threshold = 3)")
}

# Summary stats
stats <- safe_query_impl(db_pool, "
  SELECT
    (SELECT COUNT(*) FROM player_scenes) AS total_associations,
    (SELECT COUNT(DISTINCT player_id) FROM player_scenes) AS players_with_scenes,
    (SELECT COUNT(DISTINCT player_id) FROM player_scenes WHERE is_home = true) AS players_with_home,
    (SELECT COUNT(*) FROM players WHERE home_scene_id IS NOT NULL) AS players_home_scene_set
")

message(sprintf("\n=== Summary ==="))
message(sprintf("  Total associations: %d", stats$total_associations))
message(sprintf("  Players with scenes: %d", stats$players_with_scenes))
message(sprintf("  Players with home scene (player_scenes): %d", stats$players_with_home))
message(sprintf("  Players with home_scene_id set: %d", stats$players_home_scene_set))

message("\nDone!")
