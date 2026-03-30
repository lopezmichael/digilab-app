-- =============================================================================
-- Migration 009: Country & State Scene Rows
-- Date: 2026-03-30
-- Adds scene_type = 'country' and 'state' rows so the Astro frontend tree
-- selector can offer selectable, linkable parent nodes above metro scenes.
-- =============================================================================

-- 1. Country scenes — one per distinct country with active metro scenes
--    Slugs derived from country name; continent inherited from metros.
--    ON CONFLICT (slug) DO NOTHING guards against re-runs and collisions.
INSERT INTO scenes (name, slug, display_name, scene_type, country, continent, is_active)
SELECT DISTINCT ON (country)
  country,
  LOWER(REGEXP_REPLACE(TRIM(country), '[^a-zA-Z0-9]+', '-', 'g')),
  country,
  'country',
  country,
  continent,
  TRUE
FROM scenes
WHERE scene_type = 'metro' AND is_active = TRUE AND country IS NOT NULL
ORDER BY country, continent
ON CONFLICT (slug) DO NOTHING;

-- 2. US state scenes — one per distinct state_region in United States
INSERT INTO scenes (name, slug, display_name, scene_type, country, state_region, continent, is_active)
SELECT DISTINCT
  state_region,
  LOWER(REGEXP_REPLACE(TRIM(state_region), '[^a-zA-Z0-9]+', '-', 'g')),
  state_region,
  'state',
  'United States',
  state_region,
  'north_america',
  TRUE
FROM scenes
WHERE scene_type = 'metro' AND is_active = TRUE
  AND country = 'United States' AND state_region IS NOT NULL
ON CONFLICT (slug) DO NOTHING;

-- 3. Non-US state scenes — only where 2+ metros share the same state_region.
--    Prefixed with country code to avoid slug collisions with metro scenes
--    (e.g., "Berlin" the city vs "Berlin" the state → "de-berlin").
INSERT INTO scenes (name, slug, display_name, scene_type, country, state_region, continent, is_active)
SELECT
  sr.state_region,
  sr.prefixed_slug,
  sr.state_region,
  'state',
  sr.country,
  sr.state_region,
  sr.continent,
  TRUE
FROM (
  SELECT DISTINCT ON (country, state_region)
    country,
    state_region,
    continent,
    CASE country
      WHEN 'Germany' THEN 'de-'
      WHEN 'Spain' THEN 'es-'
      WHEN 'United Kingdom' THEN 'uk-'
      WHEN 'Australia' THEN 'au-'
      WHEN 'Brazil' THEN 'br-'
      WHEN 'France' THEN 'fr-'
      WHEN 'Italy' THEN 'it-'
      WHEN 'Portugal' THEN 'pt-'
      WHEN 'Canada' THEN 'ca-'
      WHEN 'Mexico' THEN 'mx-'
      ELSE LOWER(SUBSTR(country, 1, 2)) || '-'
    END || LOWER(REGEXP_REPLACE(TRANSLATE(TRIM(state_region),
      'ÁÉÍÓÚáéíóúÀÈÌÒÙàèìòùÂÊÎÔÛâêîôûÄËÏÖÜäëïöüÃÑÕãñõÇç',
      'AEIOUaeiouAEIOUaeiouAEIOUaeiouAEIOUaeiouANOanocc'),
      '[^a-zA-Z0-9]+', '-', 'g')) AS prefixed_slug
  FROM scenes
  WHERE scene_type = 'metro' AND is_active = TRUE
    AND country != 'United States' AND state_region IS NOT NULL
    AND (country, state_region) IN (
      SELECT country, state_region
      FROM scenes
      WHERE scene_type = 'metro' AND is_active = TRUE
        AND country != 'United States' AND state_region IS NOT NULL
      GROUP BY country, state_region
      HAVING COUNT(*) >= 2
    )
  ORDER BY country, state_region, continent
) sr
ON CONFLICT (slug) DO NOTHING;

-- 4. Verify online scene exists (should already be scene_id=5)
INSERT INTO scenes (name, slug, display_name, scene_type, is_active)
SELECT 'online', 'online', 'Online / Webcam', 'online', TRUE
WHERE NOT EXISTS (SELECT 1 FROM scenes WHERE scene_type = 'online' AND is_active = TRUE);
