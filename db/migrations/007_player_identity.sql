-- =============================================================================
-- Migration 007: Player Identity & Disambiguation
-- Date: 2026-03-09
-- Description: Adds verification model for player identity. Players with a real
--   Bandai member number are "verified" (globally matchable). Players without
--   are "unverified" (scene-locked to home_scene_id). Adds unique constraint
--   on member_number to prevent duplicate Bandai IDs.
-- Design doc: docs/plans/2026-03-09-player-identity-disambiguation-design.md
-- =============================================================================

-- 1. Add identity_status column (verified = has real Bandai ID, unverified = name-only)
ALTER TABLE players ADD COLUMN IF NOT EXISTS identity_status VARCHAR DEFAULT 'unverified';

-- 2. Add home_scene_id for unverified player scoping
ALTER TABLE players ADD COLUMN IF NOT EXISTS home_scene_id INTEGER REFERENCES scenes(scene_id) ON DELETE SET NULL;

-- 3. Indexes for new columns
CREATE INDEX IF NOT EXISTS idx_players_identity_status ON players(identity_status);
CREATE INDEX IF NOT EXISTS idx_players_home_scene ON players(home_scene_id);
CREATE INDEX IF NOT EXISTS idx_players_member_number ON players(member_number) WHERE member_number IS NOT NULL AND member_number != '';

-- 4. Backfill: players with real member numbers → verified
UPDATE players SET identity_status = 'verified'
WHERE member_number IS NOT NULL
  AND member_number != ''
  AND member_number !~ '^GUEST'
  AND identity_status = 'unverified';

-- 5. Strip GUEST member numbers (they're session-scoped throwaway IDs)
UPDATE players SET member_number = NULL
WHERE member_number ~ '^GUEST';

-- 6. Backfill: infer home_scene_id from most-played scene
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
WHERE p.player_id = sub.player_id AND sub.rn = 1 AND p.home_scene_id IS NULL;

-- 7. Unique constraint on member_number (partial — only non-NULL, non-empty)
-- NOTE: Run the audit script first to resolve any duplicate member_numbers!
ALTER TABLE players ADD CONSTRAINT unique_member_number
  UNIQUE (member_number) WHERE member_number IS NOT NULL AND member_number != '';
