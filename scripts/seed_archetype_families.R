# Seed script: Create initial archetype families and assign existing archetypes
# Usage: source("scripts/seed_archetype_families.R")
#
# This script:
# 1. Inserts archetype_families rows
# 2. Updates deck_archetypes.family_id for each member
# 3. Refreshes both MVs that include family_id

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

# --- Family definitions ---
# Each entry: list(name, slug, primary_color, secondary_color, member_ids)
families <- list(
  list("Time Strangers",  "time-strangers",   "White",  NULL,     c(35, 43, 33, 46, 73, 146, 44)),
  list("Mastemon",        "mastemon",          "Yellow", "Purple", c(65, 2, 173)),
  list("Koji Hybrid",     "koji-hybrid",       "Blue",   NULL,     c(24, 232)),
  list("Takuya Hybrid",   "takuya-hybrid",     "Red",    NULL,     c(79, 185)),
  list("Imperialdramon",  "imperialdramon",    "Blue",   "Green",  c(8, 148, 234, 231)),
  list("Aquatic",         "aquatic",           "Blue",   NULL,     c(75, 144, 193)),
  list("DM",              "dm",                "White",  NULL,     c(82, 52, 83, 84, 85, 66, 69)),
  list("Justimon",        "justimon",          "Black",  NULL,     c(51, 181, 222, 203)),
  list("Puppets",         "puppets",           "Yellow", NULL,     c(60, 38, 175)),
  list("Beelzemon",       "beelzemon",         "Purple", NULL,     c(6, 207)),
  list("Belphemon",       "belphemon",         "Purple", NULL,     c(16, 184)),
  list("Gallantmon",      "gallantmon",        "Red",    "Purple", c(5, 198, 223)),
  list("Omnimon",         "omnimon",           "Red",    "Blue",   c(20, 74, 214, 58, 136, 229, 208)),
  list("Cyber Sleuth",    "cyber-sleuth",      "White",  NULL,     c(71, 195, 96, 186)),
  list("Guil Slop",       "guil-slop",         "Red",    NULL,     c(202, 204, 143)),
  list("Myotismon",       "myotismon",         "Purple", NULL,     c(121, 201, 206)),
  list("Blackwargreymon", "blackwargreymon",   "Black",  NULL,     c(93, 94)),
  list("Lilithmon",       "lilithmon",         "Purple", NULL,     c(67, 220)),
  list("Bond",            "bond",              "Red",    "Blue",   c(109, 108)),
  list("Appmon",          "appmon",            "Red",    NULL,     c(172, 147, 140, 57, 138)),
  list("Royal Knights",   "royal-knights",     "White",  NULL,     c(4, 215)),
  list("Shinegreymon",    "shinegreymon",      "Yellow", "Red",    c(131, 235))
)

message(sprintf("\nSeeding %d archetype families...\n", length(families)))

total_assigned <- 0

for (fam in families) {
  fname <- fam[[1]]
  fslug <- fam[[2]]
  fprimary <- fam[[3]]
  fsecondary <- fam[[4]]
  member_ids <- fam[[5]]

  # Insert family, get back the ID
  result <- tryCatch({
    if (is.null(fsecondary)) {
      dbGetQuery(con, "
        INSERT INTO archetype_families (family_name, slug, primary_color, updated_by)
        VALUES ($1, $2, $3, 'seed_script')
        RETURNING family_id
      ", params = list(fname, fslug, fprimary))
    } else {
      dbGetQuery(con, "
        INSERT INTO archetype_families (family_name, slug, primary_color, secondary_color, updated_by)
        VALUES ($1, $2, $3, $4, 'seed_script')
        RETURNING family_id
      ", params = list(fname, fslug, fprimary, fsecondary))
    }
  }, error = function(e) {
    message(sprintf("  ERROR inserting family '%s': %s", fname, e$message))
    NULL
  })

  if (is.null(result)) next

  family_id <- result$family_id

  # Assign members
  for (aid in member_ids) {
    tryCatch({
      dbExecute(con, "
        UPDATE deck_archetypes SET family_id = $1, updated_by = 'seed_script', updated_at = NOW()
        WHERE archetype_id = $2
      ", params = list(family_id, aid))
    }, error = function(e) {
      message(sprintf("  ERROR assigning archetype %d to '%s': %s", aid, fname, e$message))
    })
  }

  total_assigned <- total_assigned + length(member_ids)
  message(sprintf("  OK: %s (family_id=%d) — %d members", fname, family_id, length(member_ids)))
}

message(sprintf("\nAssigned %d archetypes across %d families.", total_assigned, length(families)))

# --- Refresh MVs ---
message("\nRefreshing materialized views...")

tryCatch({
  dbExecute(con, "REFRESH MATERIALIZED VIEW CONCURRENTLY mv_archetype_store_stats")
  message("  OK: mv_archetype_store_stats")
}, error = function(e) {
  message(sprintf("  ERROR: mv_archetype_store_stats — %s", e$message))
})

tryCatch({
  dbExecute(con, "REFRESH MATERIALIZED VIEW CONCURRENTLY mv_archetype_matchups")
  message("  OK: mv_archetype_matchups")
}, error = function(e) {
  message(sprintf("  ERROR: mv_archetype_matchups — %s", e$message))
})

message("\nDone.")
dbDisconnect(con)
