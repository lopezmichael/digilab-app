# Country & State Scene Rows — Implementation Plan

**Date:** 2026-03-30
**Status:** Implemented

## Goal

Add `scene_type = 'country'` and `scene_type = 'state'` rows to the scenes table so the Astro frontend tree selector can offer selectable, linkable, URL-addressable parent nodes above metro scenes.

## Context

- The Astro frontend sends **raw slugs** (`?scene=texas`, `?scene=united-states`), never `country:` / `state:` prefixes
- The Shiny backend uses `country:X` / `state:X` prefix convention internally for its dropdown
- Filter builders (`build_filters_param`, `build_mv_filters`) parse these prefixes to generate SQL
- Country/state scenes aggregate data from child metro scenes — no stores are assigned to them directly

## Changes

### 1. Migration: `db/migrations/009_country_state_scenes.sql`

Insert rows derived from existing metro scene data:

**Country scenes (22 rows):** One per distinct country that has active metro scenes. Slugs like `united-states`, `brazil`, `germany`. No slug collisions with existing metros.

**US state scenes (19 rows):** One per distinct US state_region. Slugs like `texas`, `california`, `florida`. No slug collisions.

**Non-US state scenes (3 rows):** Only where 2+ metros share the same state_region:
- Germany / Lower Saxony → `de-lower-saxony`
- Germany / North Rhine-Westphalia → `de-north-rhine-westphalia`
- Spain / Andalucía → `es-andalucia`

All other non-US state_regions have 1:1 city-state mapping (Berlin=Berlin, Paris=Paris) — skip them since the country → metro jump is sufficient.

**Online scene:** Already exists (scene_id=5). No action.

### 2. Slug Resolution Helper: `resolve_scene_slug()`

Add to `server/shared-server.R` (near the other scene helpers):

```r
resolve_scene_slug <- function(db_pool, slug) {
  if (is.null(slug) || slug == "" || slug == "all" || slug == "online") return(slug)
  if (startsWith(slug, "country:") || startsWith(slug, "state:")) return(slug)

  row <- safe_query(db_pool,
    "SELECT scene_type, country, state_region FROM scenes
     WHERE slug = $1 AND is_active = TRUE LIMIT 1",
    params = list(slug), default = data.frame())

  if (nrow(row) == 0) return(slug)  # unknown slug, pass through

  switch(row$scene_type[1],
    "country" = paste0("country:", row$country[1]),
    "state"   = paste0("state:", row$state_region[1]),
    "online"  = "online",
    slug  # metro — keep raw slug
  )
}
```

This translates incoming slugs to the Shiny-internal prefix format so all downstream code (dropdowns, filter builders) works unchanged.

### 3. Wire Resolution Into Entry Points

**Entry Point A: URL initial load** (`server/url-routing-server.R:87-88`)

```r
# Before:
rv$current_scene <- params$scene

# After:
rv$current_scene <- resolve_scene_slug(db_pool, params$scene)
```

Also update the continent derivation block (lines 91-120) to work off the resolved value, since a slug like `texas` would previously fall into the "regular metro slug" branch.

**Entry Point B: localStorage scene (initial)** (`server/scene-server.R:360`)

```r
# Before:
scene_selected <- apply_slug_redirect(stored$scene)

# After:
scene_selected <- resolve_scene_slug(db_pool, apply_slug_redirect(stored$scene))
```

**Entry Point C: localStorage scene (observer)** (`server/scene-server.R:421`)

```r
# Before:
scene_slug <- apply_slug_redirect(stored$scene)

# After:
scene_slug <- resolve_scene_slug(db_pool, apply_slug_redirect(stored$scene))
```

### 4. Harden Filter Subqueries

Add `AND scene_type = 'metro'` to the `country:` and `state:` subqueries in both filter builders. This makes the intent explicit and prevents accidental data leakage if a store were ever mis-assigned to a country/state scene.

**`server/shared-server.R` — `build_filters_param()`:**

```sql
-- country: filter (line ~1481)
-- Before:
AND s.scene_id IN (SELECT scene_id FROM scenes WHERE country = $N)
-- After:
AND s.scene_id IN (SELECT scene_id FROM scenes WHERE country = $N AND scene_type = 'metro')

-- state: filter (line ~1489)
-- Before:
AND s.scene_id IN (SELECT scene_id FROM scenes WHERE country = 'United States' AND state_region = $N)
-- After:
AND s.scene_id IN (SELECT scene_id FROM scenes WHERE country = 'United States' AND state_region = $N AND scene_type = 'metro')

-- continent filter (line ~1508)
-- Before:
AND s.scene_id IN (SELECT scene_id FROM scenes WHERE continent = $N)
-- After:
AND s.scene_id IN (SELECT scene_id FROM scenes WHERE continent = $N AND scene_type = 'metro')
```

Same three changes in `build_mv_filters()` (lines ~1580, ~1588, ~1606).

### 5. Future: Auto-Create Parent Scenes on Metro Creation

When a new metro scene is created in `admin-scenes-server.R`:
- Check if a country scene exists for the new metro's country. If not, create it.
- Check if a state scene exists for the new metro's state_region (only if 2+ metros now share that state_region). If not, create it.

**Deferred** — document the rule for now, automate later. The admin scenes form can show a warning like "This is the first metro in [country] — a country scene will be created automatically."

## Files Modified

| File | Change |
|------|--------|
| `db/migrations/009_country_state_scenes.sql` | New — INSERT country + state scenes |
| `server/shared-server.R` | Add `resolve_scene_slug()`, harden 6 subqueries |
| `server/url-routing-server.R` | Call `resolve_scene_slug()` on URL scene param |
| `server/scene-server.R` | Call `resolve_scene_slug()` on localStorage scene values |

## Impact Assessment

- **Public dropdowns:** `get_scene_choices()` queries `scene_type IN ('metro', 'country')` but R code (lines 144-146) filters to `scene_type == 'metro'` only. The `country:` and `state:` prefix values are synthesized from metro rows' `country`/`state_region` columns — not from country/state scene rows. New rows are fetched but filtered out. **No changes needed.**
- **Admin dropdowns:** `get_grouped_scene_choices()` filters `scene_type IN ('metro', 'online')` — unaffected
- **Map:** Filters `scene_type = 'metro'` — unaffected
- **Regional admin access:** `get_admin_accessible_scene_ids()` has no scene_type filter, but extra scene_ids are inert (no stores assigned)
- **Admin scenes table:** Shows all scene types — new rows visible (desired)
- **Materialized views:** Keyed on store scene_id — unaffected since no stores point to country/state scenes

## Slug Collision Audit

| Scope | Collisions | Resolution |
|-------|-----------|------------|
| Country slugs vs metro slugs | 0 | None needed |
| US state slugs vs metro slugs | 0 | None needed |
| Non-US state slugs vs metro slugs | 23 | Skip single-metro states; prefix multi-metro state slugs with country code |

## Testing

1. Verify `?scene=dallas-fort-worth` still works (metro slug, unchanged)
2. Verify `?scene=texas` resolves to `state:Texas` and shows all Texas metros' data
3. Verify `?scene=united-states` resolves to `country:United States` and shows all US data
4. Verify `?scene=online` still works
5. Verify `?scene=all` still works
6. Verify scene dropdown still works with internal prefix format
7. Verify admin scenes table shows new rows
8. Verify Astro `/api/scenes` returns new rows (scene_type filtering already in place)
