-- Migration 018: Multi-scene player support
-- Players can appear on multiple scene leaderboards (>= 3 events threshold)
-- Home scene derived: physical scene with most events wins over online

-- =============================================================================
-- PLAYER SCENES TABLE (Junction Table)
-- Tracks which scenes a player qualifies for based on tournament participation
-- Recomputed alongside rating refresh
-- =============================================================================
CREATE TABLE IF NOT EXISTS player_scenes (
    player_id    INT NOT NULL REFERENCES players(player_id) ON DELETE CASCADE,
    scene_id     INT NOT NULL REFERENCES scenes(scene_id) ON DELETE CASCADE,
    events_played INT NOT NULL DEFAULT 0,
    is_home      BOOLEAN NOT NULL DEFAULT false,
    PRIMARY KEY (player_id, scene_id)
);

CREATE INDEX IF NOT EXISTS idx_player_scenes_scene ON player_scenes(scene_id);
CREATE INDEX IF NOT EXISTS idx_player_scenes_home ON player_scenes(player_id) WHERE is_home = true;

-- Grant read access to digilab-web readonly role
GRANT SELECT ON player_scenes TO digilab_web_readonly;
