-- Migration 016: Pre-compute leaderboard data into player_ratings_cache
-- Eliminates expensive per-request window functions, LATERAL joins, and aggregations
-- by pre-computing stats, ranks, country, and top deck during cache refresh.
--
-- Run via: source("scripts/run_migration_016.R")

-- =============================================================================
-- 1) Add pre-computed columns to player_ratings_cache
-- =============================================================================

-- Global rank (DENSE_RANK by competitive_rating DESC)
ALTER TABLE player_ratings_cache ADD COLUMN IF NOT EXISTS global_rank INT;

-- Match stats (aggregated from results table)
ALTER TABLE player_ratings_cache ADD COLUMN IF NOT EXISTS match_wins INT NOT NULL DEFAULT 0;
ALTER TABLE player_ratings_cache ADD COLUMN IF NOT EXISTS match_losses INT NOT NULL DEFAULT 0;
ALTER TABLE player_ratings_cache ADD COLUMN IF NOT EXISTS match_ties INT NOT NULL DEFAULT 0;
ALTER TABLE player_ratings_cache ADD COLUMN IF NOT EXISTS win_pct NUMERIC;

-- Placement stats
ALTER TABLE player_ratings_cache ADD COLUMN IF NOT EXISTS first_count INT NOT NULL DEFAULT 0;
ALTER TABLE player_ratings_cache ADD COLUMN IF NOT EXISTS top3_count INT NOT NULL DEFAULT 0;

-- Most-played deck archetype
ALTER TABLE player_ratings_cache ADD COLUMN IF NOT EXISTS top_archetype_id INT;

-- Player country (from most-played store's scene, or scene country directly)
ALTER TABLE player_ratings_cache ADD COLUMN IF NOT EXISTS country TEXT;

-- =============================================================================
-- 2) Create leaderboard_stats_cache for aggregate stats (one row)
-- =============================================================================

CREATE TABLE IF NOT EXISTS leaderboard_stats_cache (
    id INT PRIMARY KEY DEFAULT 1 CHECK (id = 1),  -- Enforces single row
    median_rating NUMERIC,
    total_rated_players INT,
    last_computed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Seed the single row
INSERT INTO leaderboard_stats_cache (id, median_rating, total_rated_players)
VALUES (1, 1500, 0)
ON CONFLICT (id) DO NOTHING;

-- =============================================================================
-- 3) Index for scene-filtered rank lookups (optional, supports future scene_rank)
-- =============================================================================
CREATE INDEX IF NOT EXISTS idx_prc_global_rank ON player_ratings_cache (global_rank);
CREATE INDEX IF NOT EXISTS idx_prc_country ON player_ratings_cache (country);
