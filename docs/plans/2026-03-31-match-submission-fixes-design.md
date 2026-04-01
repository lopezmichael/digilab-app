# Match-by-Match Submission Fixes & UI Improvements

**Date:** 2026-03-31
**Status:** Plan
**Files:** `scripts/sync_limitless.py`, `server/submit-match-server.R`, `db/schema.sql`

## Problem

The Limitless sync script inserts matches with explicit `match_id` values computed via `MAX(match_id) + 1`, which does not advance PostgreSQL's IDENTITY sequence. When OCR-submitted matches later rely on the sequence (no explicit `match_id`), they collide on the primary key. The error handler on line 944 catches ALL `unique|duplicate` errors — including `matches_pkey` collisions — as if they were duplicate match submissions, silently skipping valid data.

## Three Workstreams

---

### Workstream 1: Permanent Sync Fix (`sync_limitless.py`)

**Goal:** Stop explicit `match_id` assignment; let PostgreSQL's IDENTITY sequence handle it.

#### Steps

1. **Remove `MAX(match_id) + 1` pattern** (lines 642-645 and 1041-1044). Remove the `match_id` column from both INSERT statements. Let IDENTITY generate it.

   Before (two locations):
   ```python
   cursor.execute("SELECT COALESCE(MAX(match_id), 0) + 1 FROM matches")
   next_match_id = cursor.fetchone()[0]
   # ... INSERT INTO matches (match_id, tournament_id, ...) VALUES (%s, ...)
   ```

   After:
   ```python
   # No match_id fetch needed — IDENTITY handles it
   cursor.execute("""
       INSERT INTO matches
           (tournament_id, round_number, player_id, opponent_id,
            games_won, games_lost, games_tied, match_points, match_type, source, submitted_at)
       VALUES (%s, %s, %s, %s, 0, 0, 0, %s, 'normal', 'limitless', CURRENT_TIMESTAMP)
   """, (tournament_id, round_number, player1_id, player2_id, p1_points))
   ```

2. **Reset sequence after existing data** — one-time fix for databases that already have the gap. Add to the script's startup or as a `--fix-sequences` flag:
   ```sql
   SELECT setval(pg_get_serial_sequence('matches', 'match_id'),
                  COALESCE((SELECT MAX(match_id) FROM matches), 0));
   ```

3. **Audit other tables for the same pattern.** The sync script does NOT use explicit IDs for `players`, `tournaments`, or `results` (all use `RETURNING player_id` / let IDENTITY work). Only `matches` has this problem. Confirm by searching for `MAX(` in the script — should only appear in the match insertion blocks.

4. **Add the sequence reset as a safety net** at the end of `sync_tournament_data()` and `repair_tournament()`, after all match inserts complete:
   ```python
   cursor.execute("""
       SELECT setval(pg_get_serial_sequence('matches', 'match_id'),
                      COALESCE((SELECT MAX(match_id) FROM matches), 0))
   """)
   ```

---

### Workstream 2: Defensive Error Handling (`submit-match-server.R`)

**Goal:** Distinguish primary key collisions (bug) from legitimate duplicate constraint violations (user re-submitting). Use upsert to handle re-submissions gracefully.

#### Step 1: Replace INSERT with upsert for player's own match rows

Line 885-901 — change the plain INSERT to `ON CONFLICT ... DO UPDATE`:

```r
DBI::dbExecute(conn, "
  INSERT INTO matches (tournament_id, round_number, player_id, opponent_id,
                       games_won, games_lost, games_tied, match_points,
                       match_type, source)
  VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
  ON CONFLICT (tournament_id, round_number, player_id)
  DO UPDATE SET
    opponent_id = EXCLUDED.opponent_id,
    games_won = EXCLUDED.games_won,
    games_lost = EXCLUDED.games_lost,
    games_tied = EXCLUDED.games_tied,
    match_points = EXCLUDED.match_points,
    match_type = EXCLUDED.match_type,
    source = EXCLUDED.source,
    submitted_at = CURRENT_TIMESTAMP
", params = list(...))
```

This means the player's own submission always wins — it overwrites any existing mirror row from an opponent's prior submission.

#### Step 2: Replace INSERT with `ON CONFLICT DO NOTHING` for mirror rows

Lines 913-929 — change to:

```r
DBI::dbExecute(conn, "
  INSERT INTO matches (tournament_id, round_number, player_id, opponent_id,
                       games_won, games_lost, games_tied, match_points,
                       match_type, source)
  VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
  ON CONFLICT (tournament_id, round_number, player_id) DO NOTHING
", params = list(...))
```

Mirror rows never overwrite existing data — if the opponent already submitted their own perspective, it takes priority.

#### Step 3: Track upsert counts for the toast message

Use `RETURNING` or check affected rows to distinguish new inserts from updates:

```r
# For player rows: use dbGetQuery with RETURNING to detect insert vs update
result <- DBI::dbGetQuery(conn, "
  INSERT INTO matches (...) VALUES (...)
  ON CONFLICT (tournament_id, round_number, player_id)
  DO UPDATE SET ... , submitted_at = CURRENT_TIMESTAMP
  RETURNING match_id,
    (xmax = 0) AS was_inserted  -- xmax=0 means fresh insert, >0 means update
", params = list(...))

if (nrow(result) > 0) {
  if (result$was_inserted[1]) matches_new <- matches_new + 1
  else matches_updated <- matches_updated + 1
}
```

Note: The `xmax = 0` trick is PostgreSQL-specific. Alternative: track per-round whether a row existed before the upsert with a pre-check query. Simpler approach: just count total rows processed and note that upserts can't fail on the unique constraint.

#### Step 4: Remove the savepoint/rollback pattern for player rows

With upsert, the player row insert can't fail on duplicates, so the savepoint pattern (lines 882-949) simplifies. Keep savepoints only for unexpected errors (network, constraint violations on other columns).

#### Step 5: Narrow the mirror row error handler

Line 934 — if keeping any error handler for mirrors, match the specific constraint:

```r
if (!grepl("matches_tournament_id_round_number_player_id_key", me$message, ignore.case = TRUE)) {
  message("[MATCH SUBMIT] Mirror row error (non-duplicate): ", me$message)
  # Report to Sentry
}
```

But with `ON CONFLICT DO NOTHING`, this handler should rarely fire. Keep it for safety.

#### Step 6: Remove the outer error handler's `unique|duplicate` catch-all

Line 944 — with upserts, this code path should never be hit for expected duplicates. Change to re-throw all errors:

```r
}, error = function(e) {
  tryCatch(DBI::dbExecute(conn, sprintf("ROLLBACK TO SAVEPOINT match_%d", i)),
           error = function(re) NULL)
  stop(e)  # All errors are unexpected now — let the outer handler ROLLBACK
})
```

---

### Workstream 3: UI Improvements (`submit-match-server.R`)

#### 3A: Tournament List Badges with Completeness

**Enhance `sr_match_get_tournaments()`** to return self-submitted vs mirror-sourced counts:

```sql
SELECT r.result_id, r.tournament_id, r.placement, r.player_id,
       t.event_date, t.event_type, t.format, t.rounds,
       s.name as store_name,
       f.display_name as format_name,
       -- Total matches for this player in this tournament
       (SELECT COUNT(*) FROM matches m
        WHERE m.tournament_id = r.tournament_id AND m.player_id = r.player_id) as match_count,
       -- Self-submitted matches (source = 'ocr' or 'manual', player submitted their own)
       (SELECT COUNT(*) FROM matches m
        WHERE m.tournament_id = r.tournament_id AND m.player_id = r.player_id
        AND m.source IN ('ocr', 'manual')) as self_match_count,
       -- Mirror-sourced matches (source = 'ocr' but created as mirror from opponent)
       (SELECT COUNT(*) FROM matches m
        WHERE m.tournament_id = r.tournament_id AND m.player_id = r.player_id
        AND m.source = 'ocr'
        AND m.opponent_id IN (
          SELECT m2.player_id FROM matches m2
          WHERE m2.tournament_id = r.tournament_id AND m2.opponent_id = r.player_id
          AND m2.round_number = m.round_number AND m2.source = 'ocr'
        )) as mirror_match_count
FROM results r
JOIN tournaments t ON r.tournament_id = t.tournament_id
JOIN stores s ON t.store_id = s.store_id
LEFT JOIN formats f ON t.format = f.format_id
WHERE r.player_id = $1
ORDER BY t.event_date DESC
LIMIT 50
```

Simpler alternative — since we can't easily distinguish mirror vs self with the current `source` column, consider adding a `is_mirror BOOLEAN DEFAULT FALSE` column to matches, or just compare `match_count` vs `rounds`:

```sql
-- Simpler: just get match_count and compare to rounds in R
(SELECT COUNT(*) FROM matches m
 WHERE m.tournament_id = r.tournament_id AND m.player_id = r.player_id) as match_count
```

**Update badge rendering** in `output$sr_match_tournament_history` (line 263-284):

```r
rounds <- if (!is.na(t$rounds)) as.integer(t$rounds) else NA
match_count <- if (!is.na(t$match_count)) as.integer(t$match_count) else 0L

badge <- if (is.na(rounds)) {
  if (match_count > 0) span(class = "badge bg-success", paste(match_count, "matches"))
  else span(class = "badge bg-secondary", "No match data")
} else if (match_count >= rounds) {
  span(class = "badge bg-success", sprintf("Complete (%d/%d)", match_count, rounds))
} else if (match_count > 0) {
  span(class = "badge bg-warning text-dark", sprintf("Partial (%d/%d)", match_count, rounds))
} else {
  span(class = "badge bg-secondary", "No match data")
}
```

#### 3B: Existing Data Preview

When a tournament is selected that already has match data, show a read-only summary before the upload form. Add to `output$sr_match_upload_form` (after the tournament context banner, before the screenshot upload):

```r
# Query existing matches for this player in this tournament
existing_matches <- safe_query(db_pool, "
  SELECT m.round_number, m.games_won, m.games_lost, m.games_tied, m.match_points,
         m.source, p.display_name as opponent_name
  FROM matches m
  LEFT JOIN players p ON m.opponent_id = p.player_id
  WHERE m.tournament_id = $1 AND m.player_id = $2
  ORDER BY m.round_number
", params = list(tournament_id, player_id), default = data.frame())

if (nrow(existing_matches) > 0) {
  rounds <- selected$rounds
  existing_count <- nrow(existing_matches)

  if (!is.na(rounds) && existing_count >= rounds) {
    msg <- "All rounds recorded. Upload to update your match history."
    alert_class <- "alert-success"
  } else if (!is.na(rounds)) {
    msg <- sprintf("%d of %d rounds have data. Upload to add your match history.",
                   existing_count, rounds)
    alert_class <- "alert-info"
  } else {
    msg <- sprintf("%d rounds recorded. Upload to update.", existing_count)
    alert_class <- "alert-info"
  }

  # Render the alert + a compact summary table of existing matches
}
```

#### 3C: Better Post-Submit Toast

Replace the current toast (line 970-973) with detail from upsert results:

```r
parts <- c()
if (matches_new > 0) parts <- c(parts, paste(matches_new, "new"))
if (matches_updated > 0) parts <- c(parts, paste(matches_updated, "updated"))
total <- matches_new + matches_updated

notify(
  sprintf("Match history submitted! %d matches saved (%s).", total, paste(parts, collapse = ", ")),
  type = "message"
)
```

---

## Implementation Order

1. **Workstream 1** first — fix the sync script so no more sequence gaps are created. Run the one-time sequence reset on production.
2. **Workstream 2** next — upsert logic + error handling cleanup. This is the core bug fix.
3. **Workstream 3** last — UI improvements are additive and can be done incrementally.

## Testing Checklist

- [ ] Run `sync_limitless.py` with `--dry-run` to verify INSERT statements no longer include `match_id`
- [ ] After sync, verify `SELECT last_value FROM matches_match_id_seq` matches `MAX(match_id)`
- [ ] Submit match history via OCR for a tournament with no prior match data (fresh insert)
- [ ] Submit match history for a tournament where the player already has mirror rows (upsert overwrites)
- [ ] Re-submit same match history (upsert updates, toast says "4 updated")
- [ ] Submit for a tournament where opponent already submitted their perspective (mirror rows preserved)
- [ ] Verify tournament list badges show "Complete (4/4)", "Partial (2/4)", or "No match data"
- [ ] Verify existing data preview appears when selecting a tournament with prior matches

## Risk Notes

- The `(xmax = 0) AS was_inserted` PostgreSQL trick may not work through the R `pool` package if connection settings differ. Fallback: just count total successful upserts without distinguishing new/updated.
- The sequence name `matches_match_id_seq` is PostgreSQL's default naming for `GENERATED BY DEFAULT AS IDENTITY`. Verify with `pg_get_serial_sequence('matches', 'match_id')`.
- Adding `is_mirror` column to matches would be cleaner long-term but is not required for this fix.
