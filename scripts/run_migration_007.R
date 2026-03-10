# Run migration 007 - Player Identity & Disambiguation
# Two-phase script:
#   Phase 1 (AUDIT): Review existing player data — duplicates, GUEST IDs, cross-scene collisions
#   Phase 2 (MIGRATE): Apply schema changes and backfill
#
# Usage: source("scripts/run_migration_007.R")

library(DBI)
library(RPostgres)
library(dotenv)

load_dot_env()

message("Connecting to database...")
con <- dbConnect(
  Postgres(),
  host = Sys.getenv("NEON_HOST"),
  dbname = Sys.getenv("NEON_DATABASE"),
  user = Sys.getenv("NEON_USER"),
  password = Sys.getenv("NEON_PASSWORD"),
  sslmode = "require"
)

run <- function(desc, sql) {
  tryCatch({
    result <- dbExecute(con, sql)
    message(sprintf("  OK: %s (%s rows affected)", desc, result))
  }, error = function(e) {
    message(sprintf("  ERROR: %s\n         %s", desc, e$message))
  })
}

query <- function(desc, sql) {
  tryCatch({
    result <- dbGetQuery(con, sql)
    message(sprintf("  %s: %s rows", desc, nrow(result)))
    result
  }, error = function(e) {
    message(sprintf("  ERROR: %s\n         %s", desc, e$message))
    data.frame()
  })
}

# =============================================================================
# PHASE 1: AUDIT — Review current player data
# =============================================================================
message("\n========================================")
message("PHASE 1: PLAYER DATA AUDIT")
message("========================================\n")

# --- 1a. Basic stats ---
message("--- Player Overview ---")
total_players <- query("Total active players", "
  SELECT COUNT(*) as n FROM players WHERE is_active IS NOT FALSE
")
has_member_num <- query("Players with member_number", "
  SELECT COUNT(*) as n FROM players
  WHERE member_number IS NOT NULL AND member_number != ''
    AND is_active IS NOT FALSE
")
has_guest_id <- query("Players with GUEST IDs", "
  SELECT COUNT(*) as n FROM players
  WHERE member_number ~ '^GUEST'
    AND is_active IS NOT FALSE
")
has_limitless <- query("Players with limitless_username", "
  SELECT COUNT(*) as n FROM players
  WHERE limitless_username IS NOT NULL AND limitless_username != ''
    AND is_active IS NOT FALSE
")
no_identifier <- query("Players with NO identifier (no member#, no limitless)", "
  SELECT COUNT(*) as n FROM players
  WHERE (member_number IS NULL OR member_number = '' OR member_number ~ '^GUEST')
    AND (limitless_username IS NULL OR limitless_username = '')
    AND is_active IS NOT FALSE
")

message(sprintf("\n  Summary: %s total | %s with Bandai ID | %s GUEST | %s Limitless | %s no identifier\n",
  as.integer(total_players$n), as.integer(has_member_num$n), as.integer(has_guest_id$n),
  as.integer(has_limitless$n), as.integer(no_identifier$n)))

# --- 1b. Duplicate member numbers (BLOCKING — must resolve before unique constraint) ---
message("--- Duplicate Member Numbers (MUST RESOLVE) ---")
dup_members <- query("Duplicate member_numbers", "
  SELECT member_number, COUNT(*) as count,
         array_agg(player_id ORDER BY player_id) as player_ids,
         array_agg(display_name ORDER BY player_id) as names
  FROM players
  WHERE member_number IS NOT NULL AND member_number != ''
    AND member_number !~ '^GUEST'
    AND is_active IS NOT FALSE
  GROUP BY member_number
  HAVING COUNT(*) > 1
  ORDER BY COUNT(*) DESC
")
if (nrow(dup_members) > 0) {
  message("\n  *** DUPLICATE BANDAI IDS FOUND — Must merge or fix before migration ***")
  for (i in seq_len(nrow(dup_members))) {
    message(sprintf("  Member #%s: %s (player_ids: %s)",
      dup_members$member_number[i], dup_members$names[i], dup_members$player_ids[i]))
  }
  message("")
} else {
  message("  None found — safe to apply unique constraint\n")
}

# --- 1c. GUEST member numbers ---
message("--- GUEST Member Numbers (will be stripped) ---")
guest_players <- query("Players with GUEST IDs", "
  SELECT player_id, display_name, member_number
  FROM players
  WHERE member_number ~ '^GUEST'
    AND is_active IS NOT FALSE
  ORDER BY player_id
  LIMIT 20
")
if (nrow(guest_players) > 0) {
  for (i in seq_len(nrow(guest_players))) {
    message(sprintf("  [%s] %s — %s",
      guest_players$player_id[i], guest_players$display_name[i], guest_players$member_number[i]))
  }
  if (has_guest_id$n > 20) message(sprintf("  ... and %s more", has_guest_id$n - 20))
  message("")
}

# --- 1d. Cross-scene name collisions (same name, different scenes) ---
message("--- Cross-Scene Name Collisions (potential duplicates) ---")
cross_scene <- query("Names appearing in multiple scenes", "
  WITH player_scenes AS (
    SELECT p.player_id, p.display_name, p.member_number,
           s.scene_id, sc.display_name as scene_name,
           COUNT(DISTINCT t.tournament_id) as events,
           s.is_online
    FROM players p
    JOIN results r ON p.player_id = r.player_id
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    JOIN stores s ON t.store_id = s.store_id
    JOIN scenes sc ON s.scene_id = sc.scene_id
    WHERE p.is_active IS NOT FALSE
    GROUP BY p.player_id, p.display_name, p.member_number,
             s.scene_id, sc.display_name, s.is_online
  )
  SELECT a.display_name,
         a.player_id as player_id_1, a.scene_name as scene_1, a.events as events_1,
         a.member_number as member_1,
         b.player_id as player_id_2, b.scene_name as scene_2, b.events as events_2,
         b.member_number as member_2
  FROM player_scenes a
  JOIN player_scenes b ON LOWER(a.display_name) = LOWER(b.display_name)
    AND a.player_id < b.player_id
    AND a.scene_id != b.scene_id
  ORDER BY a.display_name, a.player_id
")
if (nrow(cross_scene) > 0) {
  message(sprintf("\n  Found %s cross-scene name collision pairs:", nrow(cross_scene)))
  for (i in seq_len(min(nrow(cross_scene), 30))) {
    r <- cross_scene[i, ]
    m1 <- if (!is.na(r$member_1) && nchar(r$member_1) > 0) r$member_1 else "NO ID"
    m2 <- if (!is.na(r$member_2) && nchar(r$member_2) > 0) r$member_2 else "NO ID"
    message(sprintf("  \"%s\": [%s] %s (%s events, %s) vs [%s] %s (%s events, %s)",
      r$display_name,
      r$player_id_1, r$scene_1, r$events_1, m1,
      r$player_id_2, r$scene_2, r$events_2, m2))
  }
  if (nrow(cross_scene) > 30) message(sprintf("  ... and %s more pairs", nrow(cross_scene) - 30))
} else {
  message("  No cross-scene name collisions found")
}

# --- 1e. Same name within same scene (different player_ids) ---
message("\n--- Same-Scene Name Collisions (highest risk) ---")
same_scene <- query("Same name, same scene, different player_ids", "
  WITH player_scenes AS (
    SELECT p.player_id, p.display_name, p.member_number,
           s.scene_id, sc.display_name as scene_name,
           COUNT(DISTINCT t.tournament_id) as events
    FROM players p
    JOIN results r ON p.player_id = r.player_id
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    JOIN stores s ON t.store_id = s.store_id
    JOIN scenes sc ON s.scene_id = sc.scene_id
    WHERE p.is_active IS NOT FALSE
    GROUP BY p.player_id, p.display_name, p.member_number,
             s.scene_id, sc.display_name
  )
  SELECT a.display_name, a.scene_name,
         a.player_id as pid_1, a.events as events_1, a.member_number as member_1,
         b.player_id as pid_2, b.events as events_2, b.member_number as member_2
  FROM player_scenes a
  JOIN player_scenes b ON LOWER(a.display_name) = LOWER(b.display_name)
    AND a.player_id < b.player_id
    AND a.scene_id = b.scene_id
  ORDER BY a.scene_name, a.display_name
")
if (nrow(same_scene) > 0) {
  message(sprintf("\n  Found %s same-scene collision pairs (may need merge):", nrow(same_scene)))
  for (i in seq_len(min(nrow(same_scene), 30))) {
    r <- same_scene[i, ]
    m1 <- if (!is.na(r$member_1) && nchar(r$member_1) > 0) r$member_1 else "NO ID"
    m2 <- if (!is.na(r$member_2) && nchar(r$member_2) > 0) r$member_2 else "NO ID"
    message(sprintf("  [%s] \"%s\": pid %s (%s events, %s) vs pid %s (%s events, %s)",
      r$scene_name, r$display_name,
      r$pid_1, r$events_1, m1,
      r$pid_2, r$events_2, m2))
  }
  if (nrow(same_scene) > 30) message(sprintf("  ... and %s more pairs", nrow(same_scene) - 30))
} else {
  message("  No same-scene name collisions found")
}

# --- 1f. Online tournament overlap (players in both online + local scenes) ---
message("\n--- Online + Local Overlap (likely same player) ---")
online_local <- query("Players in both online and local scenes", "
  WITH player_online AS (
    SELECT DISTINCT p.player_id, p.display_name, p.member_number
    FROM players p
    JOIN results r ON p.player_id = r.player_id
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    JOIN stores s ON t.store_id = s.store_id
    WHERE s.is_online = TRUE AND p.is_active IS NOT FALSE
  ),
  player_local AS (
    SELECT DISTINCT p.player_id, p.display_name, p.member_number
    FROM players p
    JOIN results r ON p.player_id = r.player_id
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    JOIN stores s ON t.store_id = s.store_id
    WHERE s.is_online = FALSE AND p.is_active IS NOT FALSE
  )
  SELECT o.player_id as online_pid, o.display_name as online_name, o.member_number as online_member,
         l.player_id as local_pid, l.display_name as local_name, l.member_number as local_member
  FROM player_online o
  JOIN player_local l ON LOWER(o.display_name) = LOWER(l.display_name)
    AND o.player_id != l.player_id
  ORDER BY o.display_name
")
if (nrow(online_local) > 0) {
  message(sprintf("\n  Found %s online/local pairs with same name but different player_ids:", nrow(online_local)))
  for (i in seq_len(min(nrow(online_local), 30))) {
    r <- online_local[i, ]
    om <- if (!is.na(r$online_member) && nchar(r$online_member) > 0) r$online_member else "NO ID"
    lm <- if (!is.na(r$local_member) && nchar(r$local_member) > 0) r$local_member else "NO ID"
    message(sprintf("  \"%s\": online pid %s (%s) vs local pid %s (%s)",
      r$online_name, r$online_pid, om, r$local_pid, lm))
  }
  if (nrow(online_local) > 30) message(sprintf("  ... and %s more pairs", nrow(online_local) - 30))
} else {
  message("  No online/local name overlaps found")
}

# =============================================================================
# PHASE 1 SUMMARY
# =============================================================================
message("\n========================================")
message("AUDIT SUMMARY")
message("========================================")
blocking <- nrow(dup_members) > 0
message(sprintf("  Duplicate member numbers (BLOCKING): %s", as.integer(nrow(dup_members))))
message(sprintf("  GUEST IDs to strip: %s", as.integer(has_guest_id$n)))
message(sprintf("  Cross-scene collisions: %s pairs", nrow(cross_scene)))
message(sprintf("  Same-scene collisions: %s pairs", nrow(same_scene)))
message(sprintf("  Online/local overlaps: %s pairs", nrow(online_local)))

if (blocking) {
  message("\n  *** BLOCKING ISSUES: Resolve duplicate member numbers before running Phase 2 ***")
  message("  Use the admin Players tab to merge duplicate players, or run manual SQL fixes.")
  message("  Then re-run this script.\n")
}

# =============================================================================
# PHASE 2: MIGRATION — Apply schema changes
# =============================================================================
# Prompt for confirmation before proceeding
if (blocking) {
  message("Skipping Phase 2 due to blocking issues.\n")
  dbDisconnect(con)
  stop("Resolve blocking issues and re-run.")
}

message("\n========================================")
message("PHASE 2: APPLYING MIGRATION")
message("========================================\n")

proceed <- readline("Proceed with migration? (yes/no): ")
if (tolower(trimws(proceed)) != "yes") {
  message("Migration cancelled.")
  dbDisconnect(con)
  stop("Migration cancelled by user.")
}

# Read and execute migration SQL
message("\nApplying migration 007: Player Identity\n")

run("Add identity_status column",
  "ALTER TABLE players ADD COLUMN IF NOT EXISTS identity_status VARCHAR DEFAULT 'unverified'")

run("Add home_scene_id column",
  "ALTER TABLE players ADD COLUMN IF NOT EXISTS home_scene_id INTEGER REFERENCES scenes(scene_id) ON DELETE SET NULL")

run("Index on identity_status",
  "CREATE INDEX IF NOT EXISTS idx_players_identity_status ON players(identity_status)")

run("Index on home_scene_id",
  "CREATE INDEX IF NOT EXISTS idx_players_home_scene ON players(home_scene_id)")

run("Index on member_number (partial)",
  "CREATE INDEX IF NOT EXISTS idx_players_member_number ON players(member_number) WHERE member_number IS NOT NULL AND member_number != ''")

run("Backfill: verified players (real Bandai IDs)", "
  UPDATE players SET identity_status = 'verified'
  WHERE member_number IS NOT NULL
    AND member_number != ''
    AND member_number !~ '^GUEST'
    AND identity_status = 'unverified'
")

run("Strip GUEST member numbers", "
  UPDATE players SET member_number = NULL
  WHERE member_number ~ '^GUEST'
")

run("Backfill: infer home_scene_id from most-played scene", "
  UPDATE players p SET home_scene_id = sub.scene_id
  FROM (
    SELECT r.player_id, s.scene_id,
           ROW_NUMBER() OVER (PARTITION BY r.player_id ORDER BY COUNT(*) DESC) as rn
    FROM results r
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    JOIN stores s ON t.store_id = s.store_id
    WHERE s.scene_id IS NOT NULL
    GROUP BY r.player_id, s.scene_id
  ) sub
  WHERE p.player_id = sub.player_id AND sub.rn = 1 AND p.home_scene_id IS NULL
")

# Limitless-synced players with limitless_username → verified
run("Backfill: Limitless players → verified", "
  UPDATE players SET identity_status = 'verified'
  WHERE limitless_username IS NOT NULL AND limitless_username != ''
    AND identity_status = 'unverified'
")

run("Clear member_number from inactive duplicates", "
  UPDATE players SET member_number = NULL
  WHERE is_active = FALSE
    AND member_number IS NOT NULL AND member_number != ''
    AND member_number IN (
      SELECT member_number FROM players
      WHERE member_number IS NOT NULL AND member_number != ''
      GROUP BY member_number HAVING COUNT(*) > 1
    )
")

run("Unique index on member_number (partial)", "
  CREATE UNIQUE INDEX IF NOT EXISTS idx_players_unique_member_number
  ON players (member_number) WHERE member_number IS NOT NULL AND member_number != ''
")

# =============================================================================
# VERIFICATION
# =============================================================================
message("\n--- Verification ---")
query("Verified players", "SELECT COUNT(*) as n FROM players WHERE identity_status = 'verified' AND is_active IS NOT FALSE")
query("Unverified players", "SELECT COUNT(*) as n FROM players WHERE identity_status = 'unverified' AND is_active IS NOT FALSE")
query("Players with home_scene_id", "SELECT COUNT(*) as n FROM players WHERE home_scene_id IS NOT NULL AND is_active IS NOT FALSE")
query("Players still with GUEST member_number", "SELECT COUNT(*) as n FROM players WHERE member_number ~ '^GUEST'")

# Check constraint exists
constraint_check <- query("Unique constraint check", "
  SELECT constraint_name FROM information_schema.table_constraints
  WHERE table_name = 'players' AND constraint_name = 'unique_member_number'
")
if (nrow(constraint_check) > 0) {
  message("  Unique member_number constraint: ACTIVE")
} else {
  message("  WARNING: Unique member_number constraint NOT found")
}

dbDisconnect(con)
message("\nMigration 007 complete. Database connection closed.")
