-- =============================================================================
-- Migration 008: v1.7.0 Filter Redesign & Scene Restructure
-- Date: 2026-03-12
-- =============================================================================

-- 1. Add continent column to scenes
ALTER TABLE scenes ADD COLUMN IF NOT EXISTS continent TEXT;

-- 2. Populate continent from country values
UPDATE scenes SET continent = CASE
  WHEN country IN ('United States', 'Canada', 'Mexico') THEN 'north_america'
  WHEN country IN ('Brazil', 'Costa Rica', 'Colombia', 'Argentina', 'Chile', 'Peru') THEN 'south_america'
  WHEN country IN ('Germany', 'Italy', 'France', 'Spain', 'United Kingdom', 'Netherlands', 'Poland', 'Portugal', 'Sweden', 'Norway', 'Denmark', 'Finland', 'Austria', 'Switzerland', 'Belgium', 'Czech Republic', 'Romania', 'Hungary', 'Greece', 'Ireland') THEN 'europe'
  WHEN country IN ('Japan', 'South Korea', 'China', 'Taiwan', 'Philippines', 'Thailand', 'Malaysia', 'Singapore', 'Indonesia', 'India') THEN 'asia'
  WHEN country IN ('Australia', 'New Zealand') THEN 'oceania'
  WHEN country IN ('South Africa', 'Nigeria', 'Kenya', 'Egypt') THEN 'africa'
END
WHERE continent IS NULL AND scene_type IN ('metro', 'country');

-- 3. Create admin_user_scenes junction table
CREATE TABLE IF NOT EXISTS admin_user_scenes (
    user_id INTEGER NOT NULL REFERENCES admin_users(user_id) ON DELETE CASCADE,
    scene_id INTEGER NOT NULL REFERENCES scenes(scene_id) ON DELETE CASCADE,
    is_primary BOOLEAN DEFAULT FALSE,
    assigned_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    assigned_by TEXT,
    PRIMARY KEY (user_id, scene_id)
);

CREATE INDEX IF NOT EXISTS idx_admin_user_scenes_scene ON admin_user_scenes(scene_id);
CREATE INDEX IF NOT EXISTS idx_admin_user_scenes_user ON admin_user_scenes(user_id);

-- 4. Populate junction table from existing 1:1 assignments
INSERT INTO admin_user_scenes (user_id, scene_id, is_primary, assigned_by)
SELECT user_id, scene_id, TRUE, 'migration'
FROM admin_users
WHERE scene_id IS NOT NULL AND is_active = TRUE
ON CONFLICT DO NOTHING;

-- 5. NULL out discord_thread_id on all scenes (deprecated, will be removed in v1.8.0)
UPDATE scenes SET discord_thread_id = NULL;
