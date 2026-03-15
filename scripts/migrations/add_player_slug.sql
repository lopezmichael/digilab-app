-- Migration: Add slug column to players table for efficient deep-link lookups
-- Date: 2026-03-15

ALTER TABLE players ADD COLUMN IF NOT EXISTS slug VARCHAR;
CREATE INDEX IF NOT EXISTS idx_players_slug ON players(slug) WHERE is_active = TRUE;

-- Backfill slugs (handle duplicates with row_number suffix)
WITH slugged AS (
  SELECT player_id,
    TRIM(BOTH '-' FROM LOWER(REGEXP_REPLACE(TRIM(display_name), '[^a-zA-Z0-9]+', '-', 'g'))) as base_slug,
    ROW_NUMBER() OVER (PARTITION BY TRIM(BOTH '-' FROM LOWER(REGEXP_REPLACE(TRIM(display_name), '[^a-zA-Z0-9]+', '-', 'g'))) ORDER BY player_id) as rn
  FROM players
  WHERE is_active = TRUE AND slug IS NULL
)
UPDATE players p
SET slug = CASE WHEN s.rn = 1 THEN s.base_slug ELSE s.base_slug || '-' || s.rn END
FROM slugged s
WHERE p.player_id = s.player_id;
