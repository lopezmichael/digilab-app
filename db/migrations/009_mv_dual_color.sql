-- Migration 009: Add secondary_color to mv_player_store_stats and
--                winning deck color to mv_tournament_list
-- Supports dual-color deck badges across all public views.
--
-- Run via: source("scripts/run_migration_009.R")

-- =============================================================================
-- 1) Recreate mv_player_store_stats with secondary_color
-- =============================================================================
DROP MATERIALIZED VIEW IF EXISTS mv_player_store_stats CASCADE;

CREATE MATERIALIZED VIEW mv_player_store_stats AS
SELECT
  p.player_id,
  p.display_name,
  p.is_anonymized,
  s.store_id,
  s.slug,
  s.scene_id,
  s.is_online,
  sc.country,
  sc.state_region,
  t.format,
  r.archetype_id,
  da.archetype_name,
  da.primary_color,
  da.secondary_color,
  COUNT(DISTINCT r.tournament_id) as events,
  SUM(r.wins) as wins,
  SUM(r.losses) as losses,
  SUM(r.ties) as ties,
  COUNT(CASE WHEN r.placement = 1 THEN 1 END) as firsts,
  COUNT(CASE WHEN r.placement <= 3 THEN 1 END) as top3s,
  COUNT(*) as times_played
FROM players p
JOIN results r ON p.player_id = r.player_id
JOIN tournaments t ON r.tournament_id = t.tournament_id
JOIN stores s ON t.store_id = s.store_id
JOIN scenes sc ON s.scene_id = sc.scene_id
LEFT JOIN deck_archetypes da ON r.archetype_id = da.archetype_id
GROUP BY p.player_id, p.display_name, p.is_anonymized, s.store_id, s.slug, s.scene_id, s.is_online,
         sc.country, sc.state_region, t.format,
         r.archetype_id, da.archetype_name, da.primary_color, da.secondary_color;

CREATE UNIQUE INDEX ON mv_player_store_stats
  (player_id, store_id, COALESCE(format, '__null__'), COALESCE(archetype_id, -1));

CREATE INDEX idx_mv_player_scene ON mv_player_store_stats (scene_id);
CREATE INDEX idx_mv_player_format ON mv_player_store_stats (format);
CREATE INDEX idx_mv_player_online ON mv_player_store_stats (is_online) WHERE is_online = TRUE;

-- =============================================================================
-- 2) Recreate mv_tournament_list with winning deck color
-- =============================================================================
DROP MATERIALIZED VIEW IF EXISTS mv_tournament_list CASCADE;

CREATE MATERIALIZED VIEW mv_tournament_list AS
SELECT
  t.tournament_id,
  t.event_date,
  t.event_type,
  t.format,
  t.player_count,
  t.rounds,
  s.store_id,
  s.name as store_name,
  s.slug,
  s.scene_id,
  s.is_online,
  sc.country,
  sc.state_region,
  sc.scene_type,
  CASE WHEN p.is_anonymized THEN 'Anonymous' ELSE p.display_name END as winner_name,
  da.archetype_name as winning_deck,
  da.primary_color as winning_deck_color,
  da.secondary_color as winning_deck_secondary_color
FROM tournaments t
JOIN stores s ON t.store_id = s.store_id
JOIN scenes sc ON s.scene_id = sc.scene_id
LEFT JOIN LATERAL (
  SELECT r2.player_id, r2.archetype_id
  FROM results r2
  WHERE r2.tournament_id = t.tournament_id AND r2.placement = 1
  ORDER BY r2.result_id LIMIT 1
) r ON true
LEFT JOIN players p ON r.player_id = p.player_id
LEFT JOIN deck_archetypes da ON r.archetype_id = da.archetype_id;

CREATE UNIQUE INDEX ON mv_tournament_list (tournament_id);

CREATE INDEX idx_mv_tourn_scene ON mv_tournament_list (scene_id);
CREATE INDEX idx_mv_tourn_format ON mv_tournament_list (format);
CREATE INDEX idx_mv_tourn_date ON mv_tournament_list (event_date DESC);
CREATE INDEX idx_mv_tourn_online ON mv_tournament_list (is_online) WHERE is_online = TRUE;
