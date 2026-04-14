# Multi-Scene Player Support

**Date:** 2026-04-06
**Status:** Design
**Scope:** digilab-app (schema + computation) + digilab-web (queries + display)

## Problem

Players currently have a single `home_scene_id` on the `players` table. A player who competes in both Dallas Fort-Worth locals and online events only appears on one scene's leaderboard — whichever their `home_scene_id` points to. Their stats include all tournaments regardless, but leaderboard visibility is single-scene.

The FAQ says "You appear on any leaderboard where you've competed" but the implementation doesn't match.

## Design Decisions

1. **Players get scene rankings on all scenes they're regulars of** (not just one)
2. **Tamer profile page shows only the home scene rank** in the hero section
3. **Threshold: 3 tournaments minimum** to qualify for a scene's leaderboard
4. **Online is a mode, not a home** — physical scenes take priority for home scene derivation

## Home Scene Derivation Logic

```
1. If player has ANY physical scene with >= 3 events:
   -> home_scene = physical scene with most events
   -> Tie-break: most recent event wins

2. If player ONLY has online events (>= 3):
   -> home_scene = online scene

3. Online never overrides a qualifying physical scene
```

Rationale: A player with 5 Dallas events and 15 online events thinks of themselves as a Dallas player. Online supplements local play for most players.

## Schema Change (digilab-app)

### New table: `player_scenes`

```sql
CREATE TABLE player_scenes (
  player_id    INT NOT NULL REFERENCES players(player_id),
  scene_id     INT NOT NULL REFERENCES scenes(scene_id),
  events_played INT NOT NULL DEFAULT 0,
  is_home      BOOLEAN NOT NULL DEFAULT false,
  PRIMARY KEY (player_id, scene_id)
);

CREATE INDEX idx_player_scenes_scene ON player_scenes(scene_id);
CREATE INDEX idx_player_scenes_home ON player_scenes(player_id) WHERE is_home = true;
```

### Computation (run alongside rating refresh)

```sql
-- 1. Derive player-scene associations from results
WITH player_scene_events AS (
  SELECT
    r.player_id,
    st.scene_id,
    COUNT(DISTINCT r.tournament_id) AS events_played,
    MAX(t.event_date) AS last_event,
    bool_or(st.is_online) AS is_online_scene
  FROM results r
  JOIN tournaments t USING (tournament_id)
  JOIN stores st ON st.store_id = t.store_id
  WHERE st.scene_id IS NOT NULL
  GROUP BY r.player_id, st.scene_id
  HAVING COUNT(DISTINCT r.tournament_id) >= 3  -- threshold
)
-- 2. Upsert into player_scenes
INSERT INTO player_scenes (player_id, scene_id, events_played, is_home)
SELECT
  player_id,
  scene_id,
  events_played,
  -- Home scene logic: physical scene with most events wins
  -- Online only becomes home if no physical scene qualifies
  ROW_NUMBER() OVER (
    PARTITION BY player_id
    ORDER BY
      is_online_scene ASC,          -- physical first
      events_played DESC,           -- most events
      last_event DESC               -- most recent tie-break
  ) = 1 AS is_home
FROM player_scene_events
ON CONFLICT (player_id, scene_id) DO UPDATE SET
  events_played = EXCLUDED.events_played,
  is_home = EXCLUDED.is_home;

-- 3. Sync home_scene_id on players table (denormalized cache)
UPDATE players p
SET home_scene_id = ps.scene_id
FROM player_scenes ps
WHERE ps.player_id = p.player_id AND ps.is_home = true;

-- 4. Clear home_scene_id for players with no qualifying scenes
UPDATE players p
SET home_scene_id = NULL
WHERE NOT EXISTS (
  SELECT 1 FROM player_scenes ps
  WHERE ps.player_id = p.player_id AND ps.is_home = true
);
```

### Keep `home_scene_id` as denormalized cache

`players.home_scene_id` stays as a fast-path field synced from `player_scenes WHERE is_home = true`. This avoids touching the many display-only queries that just need a player's primary scene.

## digilab-web Changes

### Critical: Leaderboard queries (`leaderboard-queries.ts`)

**Scene rank CTE** — currently partitions by `home_scene_id`:
```sql
-- BEFORE
DENSE_RANK() OVER (
  PARTITION BY p2.home_scene_id
  ORDER BY r2.competitive_rating DESC
) AS scene_rank

-- AFTER
DENSE_RANK() OVER (
  PARTITION BY ps2.scene_id
  ORDER BY r2.competitive_rating DESC
) AS scene_rank
FROM players p2
JOIN player_ratings_cache r2 USING (player_id)
JOIN player_scenes ps2 USING (player_id)
```

Note: Players now appear in multiple partitions (one per qualified scene). The leaderboard query already filters to the requested scene, so the output shape doesn't change — each player still appears once per leaderboard view, just with their rank relative to that specific scene's pool.

**Scene filter conditions** (9 occurrences) — swap `home_scene_id` for junction table:
```sql
-- BEFORE
AND p.home_scene_id = ${sceneId}

-- AFTER (metro scene, filterMode=1)
AND EXISTS (
  SELECT 1 FROM player_scenes ps
  WHERE ps.player_id = p.player_id AND ps.scene_id = ${sceneId}
)
```

State/country/continent filters stay the same — they cascade from `home_scene_id` which is still the denormalized primary scene.

**Online filter** (filterMode=5) — cleaner with junction table:
```sql
-- BEFORE
AND EXISTS (SELECT 1 FROM stores WHERE stores.store_id = p.home_store_id AND stores.is_online = true)

-- AFTER
AND EXISTS (
  SELECT 1 FROM player_scenes ps
  JOIN scenes sc ON sc.scene_id = ps.scene_id
  WHERE ps.player_id = p.player_id AND sc.scene_type = 'online'
)
```

### Critical: Homepage scene player lists (`queries.ts`)

```sql
-- BEFORE
WHERE p.home_scene_id = ${scene.scene_id}

-- AFTER
WHERE EXISTS (
  SELECT 1 FROM player_scenes ps
  WHERE ps.player_id = p.player_id AND ps.scene_id = ${scene.scene_id}
)
```

### Medium: Store player origins (`store-queries.ts:514`)

Currently groups by `p.home_scene_id`. Could use `player_scenes` for multi-scene, but home_scene_id is fine here — it shows where players "come from" (home), not every scene they've played.

**Decision: No change needed.** Keep using `home_scene_id` for origin display.

### No changes needed (use denormalized `home_scene_id`)

These areas display a player's primary scene and don't need multi-scene awareness:

| Area | File | Why no change |
|------|------|---------------|
| Search results | `api/search.ts` | Shows primary scene context |
| Tamer hero section | `tamer/[slug].astro` | Shows home scene name + rank |
| Tamer OG image | `og/tamer/[slug].png.ts` | Shows home scene chip |
| Report modal context | `tamer/[slug].astro` | Routes to home scene admin |
| JSON-LD schema | `tamer/[slug].astro` | `homeLocation` = primary scene |
| Globe Trotter badge | `badges.ts` | Already uses `scenes_visited` (derived from results) |
| `scenes_visited` stat | `tamer-queries.ts` | Already derived from results join path |

### DB role permissions (digilab-web)

`digilab_web_readonly` needs SELECT on `player_scenes`:
```sql
GRANT SELECT ON player_scenes TO digilab_web_readonly;
```

## Migration Order

### Phase 1: digilab-app (schema + computation)
1. Create `player_scenes` table with indexes
2. Add computation query to rating refresh pipeline
3. Run initial backfill
4. Verify: spot-check players who compete in multiple scenes
5. Grant SELECT to `digilab_web_readonly`

### Phase 2: digilab-web (leaderboard + homepage)
1. Update `leaderboard-queries.ts` — scene rank CTE + all 9 filter conditions
2. Update `queries.ts` — homepage scene player lists
3. Update CLAUDE.md schema docs with new table
4. Test: player appears on multiple scene leaderboards
5. Test: home scene rank unchanged on tamer page
6. Test: search, OG images, badges unaffected

### Phase 3: Polish
1. Consider showing "Ranked in X scenes" on tamer page
2. Consider scene rank list in tamer profile (expandable, below hero)
3. Update FAQ to accurately reflect the (now real) multi-scene behavior

## Edge Cases

- **Player moves cities:** Natural — events accumulate at new location, old scene ages out if below threshold after future data window changes
- **Store changes scenes:** Recompute handles it on next refresh
- **Player has exactly 3 events in 5 scenes:** All 5 appear. This is fine — it means they're genuinely active across scenes
- **New player (<3 events anywhere):** No scene associations yet. `home_scene_id` is NULL. They appear on global leaderboard only (same as today)
- **Threshold tuning:** 3 is a starting point. Can adjust later without schema changes — just update the HAVING clause
