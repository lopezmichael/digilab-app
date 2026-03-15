-- Migration 005: Materialized Views for Performance
-- Creates 5 materialized views that pre-compute expensive JOINs.
-- All views include store_id, scene_id, country, state_region, is_online
-- to support filtering at any geographic level (scene, country, store, global).
--
-- Run via: source("scripts/run_migration_005.R")

-- =============================================================================
-- Drop existing regular views that will be replaced
-- =============================================================================
DROP VIEW IF EXISTS player_standings CASCADE;
DROP VIEW IF EXISTS archetype_meta CASCADE;
DROP VIEW IF EXISTS store_activity CASCADE;

-- =============================================================================
-- View 1: mv_player_store_stats
-- Grain: (player_id, store_id, format, archetype_id)
-- Used by: Players tab (standings + main deck), Dashboard (rising stars)
-- =============================================================================
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

-- Additional indexes for common filter patterns
CREATE INDEX idx_mv_player_scene ON mv_player_store_stats (scene_id);
CREATE INDEX idx_mv_player_format ON mv_player_store_stats (format);
CREATE INDEX idx_mv_player_online ON mv_player_store_stats (is_online) WHERE is_online = TRUE;

-- =============================================================================
-- View 2: mv_archetype_store_stats
-- Grain: (archetype_id, store_id, format, event_type, week_start)
-- Used by: Meta tab, Dashboard (deck analytics, meta share timeline, charts)
-- =============================================================================
CREATE MATERIALIZED VIEW mv_archetype_store_stats AS
SELECT
  da.archetype_id,
  da.archetype_name,
  da.primary_color,
  da.secondary_color,
  da.display_card_id,
  da.is_multi_color,
  s.store_id,
  s.slug,
  s.scene_id,
  s.is_online,
  sc.country,
  sc.state_region,
  t.format,
  t.event_type,
  date_trunc('week', t.event_date)::date as week_start,
  COUNT(r.result_id) as entries,
  COUNT(CASE WHEN r.placement = 1 THEN 1 END) as firsts,
  COUNT(CASE WHEN r.placement <= 3 THEN 1 END) as top3s,
  SUM(r.wins) as total_wins,
  SUM(r.losses) as total_losses,
  COUNT(DISTINCT r.player_id) as pilots,
  COUNT(DISTINCT r.tournament_id) as tournaments
FROM deck_archetypes da
JOIN results r ON da.archetype_id = r.archetype_id
JOIN tournaments t ON r.tournament_id = t.tournament_id
JOIN stores s ON t.store_id = s.store_id
JOIN scenes sc ON s.scene_id = sc.scene_id
WHERE da.is_active = TRUE AND da.archetype_name != 'UNKNOWN'
GROUP BY da.archetype_id, da.archetype_name, da.primary_color, da.secondary_color,
         da.display_card_id, da.is_multi_color,
         s.store_id, s.slug, s.scene_id, s.is_online, sc.country, sc.state_region,
         t.format, t.event_type, date_trunc('week', t.event_date);

CREATE UNIQUE INDEX ON mv_archetype_store_stats
  (archetype_id, store_id, COALESCE(format, '__null__'), event_type, week_start);

CREATE INDEX idx_mv_arch_scene ON mv_archetype_store_stats (scene_id);
CREATE INDEX idx_mv_arch_format ON mv_archetype_store_stats (format);
CREATE INDEX idx_mv_arch_online ON mv_archetype_store_stats (is_online) WHERE is_online = TRUE;

-- =============================================================================
-- View 3: mv_tournament_list
-- Grain: (tournament_id)
-- Used by: Tournaments tab, Dashboard (recent tournaments)
-- =============================================================================
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

-- =============================================================================
-- View 4: mv_store_summary
-- Grain: (store_id)
-- Used by: Stores tab (listing, map), Dashboard (store count)
-- =============================================================================
CREATE MATERIALIZED VIEW mv_store_summary AS
SELECT
  s.store_id,
  s.name,
  s.slug,
  s.address,
  s.city,
  s.state,
  s.zip_code,
  s.latitude,
  s.longitude,
  s.website,
  s.country,
  s.is_online,
  s.scene_id,
  sc.country as scene_country,
  sc.state_region,
  COUNT(DISTINCT t.tournament_id) as tournament_count,
  COUNT(DISTINCT r.player_id) as unique_players,
  COALESCE(ROUND(AVG(t.player_count), 1), 0) as avg_players,
  MAX(t.event_date) as last_event
FROM stores s
JOIN scenes sc ON s.scene_id = sc.scene_id
LEFT JOIN tournaments t ON s.store_id = t.store_id
LEFT JOIN results r ON t.tournament_id = r.tournament_id
WHERE s.is_active = TRUE
GROUP BY s.store_id, s.name, s.slug, s.address, s.city, s.state, s.zip_code,
         s.latitude, s.longitude, s.website, s.country, s.is_online,
         s.scene_id, sc.country, sc.state_region;

CREATE UNIQUE INDEX ON mv_store_summary (store_id);

CREATE INDEX idx_mv_store_scene ON mv_store_summary (scene_id);
CREATE INDEX idx_mv_store_online ON mv_store_summary (is_online) WHERE is_online = TRUE;

-- =============================================================================
-- View 5: mv_dashboard_counts
-- Grain: (scene_id, format, event_type, is_online)
-- Used by: Dashboard value boxes (tournament count, player count, etc.)
-- =============================================================================
CREATE MATERIALIZED VIEW mv_dashboard_counts AS
SELECT
  s.scene_id,
  sc.country,
  sc.state_region,
  s.is_online,
  t.format,
  t.event_type,
  COUNT(DISTINCT t.tournament_id) as tournament_count,
  COUNT(DISTINCT r.player_id) as player_count,
  COUNT(DISTINCT s.store_id) as store_count
FROM tournaments t
JOIN stores s ON t.store_id = s.store_id
JOIN scenes sc ON s.scene_id = sc.scene_id
LEFT JOIN results r ON t.tournament_id = r.tournament_id
GROUP BY s.scene_id, sc.country, sc.state_region, s.is_online,
         t.format, t.event_type;

CREATE UNIQUE INDEX ON mv_dashboard_counts
  (scene_id, COALESCE(format, '__null__'), event_type, is_online);

CREATE INDEX idx_mv_dash_scene ON mv_dashboard_counts (scene_id);
