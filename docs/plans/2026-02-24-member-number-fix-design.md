# Member Number Management Fix

**Date:** 2026-02-24
**Status:** Approved

## Problem

Member numbers can't be saved through any admin interface. Three of four code paths ignore `member_number` entirely:

| Operation | Handles member_number? |
|-----------|----------------------|
| Admin Edit Player | No - only saves display_name |
| Admin Results Entry | No - creates players without it |
| Player Merge | No - doesn't transfer it |
| Public Submission | Yes - but only if currently NULL |

Additionally, `match_player()` matches by name only (`LOWER(display_name) = LOWER($1) LIMIT 1`), causing cross-scene collisions when different players share the same name.

## Fixes

### Fix 1: Admin Edit Players — add member_number to edit form
- Add `member_number` text input to the edit player form
- Update the `UPDATE players` query to include `member_number`

### Fix 2: Results grid — member_number editing + auto-populate
- When a player name is entered and matched, auto-populate member_number from DB
- Admin can edit/override the member_number in the grid
- On save, update the player's member_number (only write if current is NULL or admin explicitly changed it)

### Fix 3: Merge — transfer member_number
- Copy source's member_number to target if target's is NULL (same pattern as limitless_username)
- If both have member numbers, keep target's

### Fix 4: Lightweight match_player improvement
- When member_number is provided, check it during matching
- Priority: exact member_number match > name match with same member_number > name match alone
- Reduces false cross-scene collisions without full rearchitecture

## Out of Scope (Future Work)

- Full player identity rearchitecture with scene-scoped matching
- Database unique constraint on member_number
- Member number as primary identifier instead of name
- These should be addressed in a future version when the app scales to more international scenes

## Files Changed

- `server/admin-players-server.R` — edit form update query
- `views/admin-players-ui.R` — add member_number input field
- `server/admin-results-server.R` — results grid save logic
- `R/admin_grid.R` — `match_player()` enhancement + auto-populate
