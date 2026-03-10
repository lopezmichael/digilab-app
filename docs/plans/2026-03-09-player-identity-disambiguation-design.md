# Player Identity & Disambiguation Design

**Date:** 2026-03-09
**Status:** Draft
**Target Version:** v1.6.0
**Roadmap IDs:** PID1–PID6

---

## Goal

Eliminate silent player mismatches and prevent duplicate player records caused by name collisions across scenes. As DigiLab scales to more scenes, the current name-based matching is increasingly unreliable. This design introduces a verification model where Bandai member numbers are the authoritative identity, and unverified players are safely scoped to their home scene.

---

## Current State

### How `match_player()` Works Today (`R/admin_grid.R:577-627`)

1. **Bandai member number** (if provided) → exact global match → reliable
2. **Display name + scene** (if scene_id provided) → case-insensitive `LIMIT 1` → unreliable
3. **Display name only** (fallback when no scene) → global `LIMIT 1` → very unreliable

### Known Failure Modes

| Scenario | What Happens | Impact |
|----------|-------------|--------|
| Two "Matt"s in same scene, no Bandai ID | `LIMIT 1` picks arbitrarily | Wrong player gets results attributed |
| Player travels to new scene without Bandai ID | No match in new scene → creates duplicate | Split rating history, two records for one person |
| Two players assigned same member_number | No DB constraint prevents this | Corrupted identity — wrong player matched globally |
| Multiple name matches, admin unaware | Silent match to first result | No opportunity to disambiguate |
| GUEST IDs from Bandai TCG+ | Treated as real member numbers | Session-scoped throwaway IDs matched incorrectly |

### Data Sources and Bandai ID Availability

| Source | Has Bandai ID? | Notes |
|--------|---------------|-------|
| OCR screenshot upload | Usually yes | Extracted from standings screenshot; GUEST IDs are fake |
| Bandai TCG+ CSV upload | Usually yes | CSV includes member numbers; GUEST entries are fake |
| Manual admin entry (Enter Results) | Sometimes | Admin may not have the number |
| Public submission | No | No member number field in public flow |
| Limitless sync | N/A | Uses `limitless_username` as identifier (reliable) |

---

## Core Design: Player Verification Model

### New Schema

```sql
-- Player verification status
ALTER TABLE players ADD COLUMN identity_status VARCHAR DEFAULT 'unverified';
-- Values: 'verified' (has real Bandai ID), 'unverified' (name-only, scene-locked)

-- Home scene for unverified player scoping
ALTER TABLE players ADD COLUMN home_scene_id INTEGER REFERENCES scenes(scene_id);

-- Enforce Bandai ID uniqueness (partial index — only non-NULL values)
ALTER TABLE players ADD CONSTRAINT unique_member_number
  UNIQUE (member_number) WHERE member_number IS NOT NULL;

-- Index for verification-aware queries
CREATE INDEX idx_players_identity_status ON players(identity_status);
CREATE INDEX idx_players_home_scene ON players(home_scene_id);
```

### Verification States

| State | Condition | Matching Scope | Behavior |
|-------|-----------|----------------|----------|
| `verified` | Has real Bandai member number | **Global** — matchable across all scenes | Bandai ID is primary key for identity |
| `unverified` | No Bandai ID (or only GUEST ID) | **Scene-locked** — only matchable within `home_scene_id` | Name matching restricted to home scene |

### GUEST ID Handling

GUEST IDs from Bandai TCG+ (`GUEST00001`, etc.) are session-scoped throwaway identifiers:
- **Strip during OCR/CSV parsing** — do not store as `member_number`
- Create player as `unverified`
- Optionally flag in admin UI: "This player registered as GUEST — no real Bandai ID"

Pattern detection: `^GUEST\d+$` → treat as no ID.

---

## Phase 1: Data Model & Matching Logic (PID1–PID3)

### PID1: Schema Migration

Add columns and constraint:

```sql
-- Migration: 006_player_identity.sql

-- 1. Add identity_status column
ALTER TABLE players ADD COLUMN IF NOT EXISTS identity_status VARCHAR DEFAULT 'unverified';

-- 2. Add home_scene_id column
ALTER TABLE players ADD COLUMN IF NOT EXISTS home_scene_id INTEGER REFERENCES scenes(scene_id);

-- 3. Backfill: players with member_number → verified
UPDATE players SET identity_status = 'verified'
WHERE member_number IS NOT NULL AND member_number != '' AND member_number !~ '^GUEST';

-- 4. Backfill: infer home_scene_id from most-played scene
UPDATE players p SET home_scene_id = sub.scene_id
FROM (
  SELECT r.player_id, s.scene_id, COUNT(*) as cnt,
         ROW_NUMBER() OVER (PARTITION BY r.player_id ORDER BY COUNT(*) DESC) as rn
  FROM results r
  JOIN tournaments t ON r.tournament_id = t.tournament_id
  JOIN stores s ON t.store_id = s.store_id
  WHERE s.scene_id IS NOT NULL
  GROUP BY r.player_id, s.scene_id
) sub
WHERE p.player_id = sub.player_id AND sub.rn = 1;

-- 5. Strip GUEST member numbers
UPDATE players SET member_number = NULL
WHERE member_number ~ '^GUEST';

-- 6. Unique constraint on member_number (partial — NULL allowed)
-- Check for existing duplicates first, resolve manually before applying
ALTER TABLE players ADD CONSTRAINT unique_member_number
  UNIQUE (member_number) WHERE member_number IS NOT NULL AND member_number != '';
```

**Pre-migration step:** Query for duplicate member_numbers and resolve manually:

```sql
SELECT member_number, COUNT(*), array_agg(player_id), array_agg(display_name)
FROM players
WHERE member_number IS NOT NULL AND member_number != ''
GROUP BY member_number HAVING COUNT(*) > 1;
```

### PID2: Redesigned `match_player()` Function

New matching cascade in `R/admin_grid.R`:

```r
match_player <- function(name, con, member_number = NULL, scene_id = NULL) {
  # Step 1: Bandai ID match (global, definitive)
  if (!is.null(member_number) && nchar(trimws(member_number)) > 0) {
    mn <- trimws(member_number)
    # Skip GUEST IDs
    if (!grepl("^GUEST", mn, ignore.case = TRUE)) {
      member_match <- safe_query_impl(con, "
        SELECT player_id, display_name, member_number, identity_status
        FROM players WHERE member_number = $1 AND is_active IS NOT FALSE
        LIMIT 1
      ", params = list(mn))

      if (nrow(member_match) > 0) {
        return(list(
          status = "matched",
          player_id = member_match$player_id,
          member_number = member_match$member_number
        ))
      }
    }
  }

  # Step 2: Name match — scene-scoped (verified players who've competed here
  #          + unverified players whose home_scene matches)
  if (!is.null(scene_id)) {
    candidates <- safe_query_impl(con, "
      SELECT DISTINCT p.player_id, p.display_name, p.member_number,
             p.identity_status, p.home_scene_id
      FROM players p
      LEFT JOIN results r ON p.player_id = r.player_id
      LEFT JOIN tournaments t ON r.tournament_id = t.tournament_id
      LEFT JOIN stores s ON t.store_id = s.store_id
      WHERE LOWER(p.display_name) = LOWER($1)
        AND p.is_active IS NOT FALSE
        AND (
          -- Verified players who've competed in this scene
          (p.identity_status = 'verified' AND s.scene_id = $2)
          OR
          -- Unverified players whose home scene is this scene
          (p.identity_status = 'unverified' AND p.home_scene_id = $2)
        )
    ", params = list(name, scene_id))
  } else {
    # No scene context — only match verified players globally
    candidates <- safe_query_impl(con, "
      SELECT player_id, display_name, member_number,
             identity_status, home_scene_id
      FROM players
      WHERE LOWER(display_name) = LOWER($1)
        AND is_active IS NOT FALSE
        AND identity_status = 'verified'
    ", params = list(name))
  }

  if (nrow(candidates) == 1) {
    return(list(
      status = "matched",
      player_id = candidates$player_id,
      member_number = candidates$member_number
    ))
  } else if (nrow(candidates) > 1) {
    return(list(
      status = "ambiguous",
      candidates = candidates
    ))
  }

  # Step 3: No match — new player
  list(status = "new")
}
```

### PID3: Player Creation with Verification

When creating a new player:

```r
# In admin-results-server.R and public-submit-server.R
create_player <- function(con, name, member_number = NULL, scene_id = NULL) {
  # Determine identity status
  has_real_id <- !is.null(member_number) &&
                 nchar(trimws(member_number)) > 0 &&
                 !grepl("^GUEST", member_number, ignore.case = TRUE)

  identity_status <- if (has_real_id) "verified" else "unverified"
  clean_member_num <- if (has_real_id) trimws(member_number) else NULL

  result <- safe_query_impl(con, "
    INSERT INTO players (display_name, member_number, identity_status, home_scene_id)
    VALUES ($1, $2, $3, $4)
    RETURNING player_id
  ", params = list(name, clean_member_num, identity_status, scene_id))

  result$player_id
}
```

### Promotion: Unverified → Verified

When a Bandai ID is later provided for an existing unverified player:

```r
promote_player <- function(con, player_id, member_number) {
  # Check if this Bandai ID already belongs to someone else
  existing <- safe_query_impl(con, "
    SELECT player_id, display_name FROM players
    WHERE member_number = $1 AND player_id != $2 AND is_active IS NOT FALSE
  ", params = list(member_number, player_id))

  if (nrow(existing) > 0) {
    # Bandai ID already belongs to another player — flag for merge review
    return(list(
      status = "conflict",
      existing_player_id = existing$player_id,
      existing_name = existing$display_name
    ))
  }

  safe_execute_impl(con, "
    UPDATE players
    SET member_number = $1, identity_status = 'verified', updated_at = NOW()
    WHERE player_id = $2
  ", params = list(member_number, player_id))

  list(status = "promoted")
}
```

---

## Phase 2: Admin UX (PID4–PID5)

### PID4: Disambiguation UI in Admin Grid

When `match_player()` returns `status = "ambiguous"`, the grid cell shows a yellow warning indicator instead of the green checkmark.

**Disambiguation picker modal:**
- Shows all candidates with identifying details:
  - Display name
  - Member number (if any)
  - Home scene
  - Last tournament date + store
  - Events played / current rating
- Admin selects the correct player, or confirms "This is a new player"
- Selected player ID is stored in the grid's `matched_player_id`

**Grid status indicators:**
| Status | Icon | Color | Meaning |
|--------|------|-------|---------|
| `matched` | Checkmark | Green | Unique match found |
| `ambiguous` | Warning triangle | Yellow | Multiple matches — click to disambiguate |
| `new` | Plus | Blue | No match — will create new player |
| `conflict` | X | Red | Bandai ID conflict — needs resolution |

### PID5: Duplicate Detection on New Player Creation

Before creating a new player, check for fuzzy matches using `pg_trgm` (already enabled):

```sql
SELECT player_id, display_name, member_number, identity_status,
       similarity(display_name, $1) as sim
FROM players
WHERE similarity(display_name, $1) > 0.4
  AND is_active IS NOT FALSE
ORDER BY sim DESC
LIMIT 5
```

If fuzzy matches found, show a "Did you mean?" prompt before creating:
- "A similar player exists: **Matthew Smith** (DFW, 12 events). Create a new player anyway?"
- This catches "Matt Smith" vs "Matthew Smith" and typo scenarios

### PID5b: Suggested Merges (Limitless → Local)

Surface auto-detected merge candidates in the admin Players tab. A Limitless-only player
(has `limitless_username`, no `member_number`) that exact-name-matches a verified local player
is a strong merge candidate.

**Query:**
```sql
SELECT l.player_id as limitless_pid, l.display_name, l.limitless_username,
       loc.player_id as local_pid, loc.member_number
FROM players l
JOIN players loc ON LOWER(l.display_name) = LOWER(loc.display_name)
  AND l.player_id != loc.player_id
WHERE l.limitless_username IS NOT NULL AND l.limitless_username != ''
  AND (l.member_number IS NULL OR l.member_number = '')
  AND loc.member_number IS NOT NULL AND loc.member_number != ''
  AND l.is_active IS NOT FALSE AND loc.is_active IS NOT FALSE
```

**UI:** Card-based suggestions in the Players tab (similar to deck_requests pattern):
- "**Klammeh** (Online, 1 event) may be the same as **Klammeh** (DFW, 13 events, #0000262582)"
- Buttons: **Merge** (combines into local player, copies limitless_username) / **Dismiss**
- Dismissed suggestions stored so they don't reappear

**Why not auto-merge:** Even with zero ambiguity today, common names like "Chris" could
match wrong as the player pool grows. The cost of a wrong merge (combined rating histories,
hard to undo) exceeds the cost of an admin clicking Merge. Volume is tiny (~1-2/month).

---

## Phase 3: Data Quality Tools (PID6)

### PID6: Unverified Player Report for Scene Admins

New section in the admin Players tab showing unverified players in the admin's scene:

- Table of unverified players with columns: Name, Events Played, Last Event, Home Scene
- Action: "Add Bandai ID" button opens inline editor → promotes to verified
- Helps scene admins proactively collect Bandai IDs at events

---

## Implementation Order

| Phase | ID | Description | Effort | Risk |
|-------|-----|-------------|--------|------|
| 1 | PID1 | Schema migration + backfill | Small | Low (additive columns, partial index) |
| 1 | PID2 | Redesigned match_player() | Medium | Medium (core matching logic change) |
| 1 | PID3 | Player creation with verification | Small | Low |
| 2 | PID4 | Disambiguation UI | Medium | Low (UI only, no data model change) |
| 2 | PID5 | Fuzzy duplicate detection | Small | Low |
| 2 | PID5b | Suggested Limitless→Local merges | Small | Low |
| 3 | PID6 | Unverified player report | Small | Low |

**Recommended approach:** Ship Phase 1 first as a data integrity improvement (no UI changes needed). Phase 2 adds the admin UX. Phase 3 is a quality-of-life tool.

---

## Impact on Other Flows

### OCR Upload / CSV Upload
- Already have Bandai IDs in most cases — verified path
- GUEST IDs stripped, player created as unverified
- No UX change needed; matching logic improvement is transparent

### Limitless Sync (`sync_limitless.py`)
- Uses `limitless_username` as identifier — unaffected
- Players created by Limitless sync should be `verified` (username is a reliable identifier)
- Consider: add `identity_status = 'verified'` to Limitless-created players

### Public Submission
- Currently has no member number field — always creates unverified players
- Future enhancement: add optional member number field to public submission form

### Player Merge (admin-players-server.R)
- When merging, if target is unverified and source has a Bandai ID, promote target to verified
- Existing merge logic already handles member_number transfer — just add identity_status update

---

## Scene Hierarchy Independence

This design is **hierarchy-agnostic**. The `home_scene_id` points to a specific scene record regardless of how scenes are organized (flat list, metro→state→country, continent→country→metro, etc.).

If scenes are restructured in the future:
- `home_scene_id` references migrate with the scene records (standard FK behavior)
- If a scene is split (e.g., "DFW" → "Dallas" + "Fort Worth"), unverified players need re-scoping — a one-time data migration, not an architectural change

---

## Open Questions

1. **Should we require Bandai ID for admin entry?** Could enforce "member number required unless marked as guest." This would accelerate verification coverage but adds friction for admins.

2. **Limitless players identity_status:** Should Limitless-synced players be `verified` since `limitless_username` is reliable? Or introduce a third status like `identified` for non-Bandai but still reliable identifiers?

3. **Cross-scene unverified matching:** Currently, an unverified player traveling to a new scene creates a duplicate. Is this acceptable (merge later when ID surfaces), or should we show "Similar unverified players in other scenes" as a hint?

---

## References

- Current match_player: `R/admin_grid.R:577-627`
- Player merge logic: `server/admin-players-server.R:345-519`
- Limitless sync player resolution: `scripts/sync_limitless.py:269-305`
- OCR member number extraction: `R/ocr.R:566-660`
- Parking lot item: `ROADMAP.md:PD1`
