# Store Request → Discord Webhook Pipeline

**Date:** 2026-02-27
**Status:** Approved
**Scope:** In-app store request form, Discord webhook routing, admin scenes update

---

## Context

Store requests currently go through an external Google Form linked from the Stores tab. With the Discord server now structured with Forum channels and scene-coordination threads, we can replace the Google Form with an in-app form that routes requests directly to the right Discord thread via webhooks.

This is the first webhook pipeline — bug reports and feature requests will follow the same pattern later.

## Goals

1. Replace the Google Form with an in-app store request modal
2. Route requests to the correct Discord channel based on whether the scene exists
3. Add `discord_thread_id` to scenes for direct routing
4. Add Discord Thread ID field to admin manage scenes form
5. Fire-and-forget delivery — never block the user

---

## User Flow

### Entry Point

"Request a Store" button on the public Stores tab → opens a modal.

### Modal — Step 1: Scene Selection

Dropdown listing all active scenes from the database. Last option: **"My area isn't listed"**.

### Existing Scene Path

| Field | Type | Required |
|-------|------|----------|
| Scene | Dropdown (pre-selected) | Yes |
| Store name | Text input | Yes |
| City/State | Text input | Yes |

- Submit → webhook posts to that scene's `#scene-coordination` thread
- Confirmation: "Your store request has been sent to the scene admin!"

### New Scene Path

| Field | Type | Required |
|-------|------|----------|
| Store name | Text input | Yes |
| City/State/Country | Text input | Yes |
| Discord username | Text input | Yes |
| Join Discord link | Display only | — |

- Submit → webhook creates a new Forum post in `#scene-requests` with `New Request` tag
- Confirmation: "Your request has been submitted! Join our Discord to follow up."

---

## Webhook Module: `R/discord_webhook.R`

Three functions using `httr2`:

### `discord_post_to_scene(scene_id, store_name, city_state)`

Looks up `discord_thread_id` from DB, posts to that scene's `#scene-coordination` thread. Falls back to `#scene-requests` if no thread ID is set.

### `discord_post_scene_request(store_name, location, discord_username)`

Creates a new Forum post in `#scene-requests` with the `New Request` tag.

### `discord_send(webhook_url, body, thread_id = NULL)`

Base helper. Handles HTTP POST via `httr2`. Fire-and-forget — errors logged to Sentry but never block the user. Webhook delivery is best-effort.

### Message Format

**Existing scene** (posted to scene's coordination thread):

```
**New Store Request**
**Store:** Nerd Rage Gaming
**Location:** Buffalo Grove, IL
**Submitted:** 2/27/2026 6:48 PM CT
*Submitted via DigiLab*
```

**New scene** (new Forum post in #scene-requests):

Post title: `Store Request: Buffalo Grove, IL`

```
**Store:** Nerd Rage Gaming
**Location:** Buffalo Grove, IL
**Discord:** @MazinPanda
**Submitted:** 2/27/2026 6:48 PM CT
*Submitted via DigiLab*
```

---

## Database Changes

```sql
ALTER TABLE scenes ADD COLUMN discord_thread_id TEXT;
ALTER TABLE scenes ADD COLUMN country TEXT;
ALTER TABLE scenes ADD COLUMN state_region TEXT;
```

- `discord_thread_id`: Backfill existing scenes by copying thread IDs from Discord (right-click thread → Copy Link → number at the end of the URL).
- `country` and `state_region`: Auto-populated via Mapbox reverse geocode when a scene is created or updated. Backfill existing scenes via one-time reverse geocode script. Stored for queries and filtering but not shown in the admin table (display name already communicates geography).

---

## Admin Manage Scenes Update

### Form Changes

- **Display name** input gets helper text: `Format: Country/State (City/Region)`
- **Discord Thread ID** text input (optional) — scenes without a thread ID fall back to posting in `#scene-requests`
- **Country + state_region** auto-filled from reverse geocode on save (not user-editable)

### Scenes Table

Updated table with search and pagination:

| Column | Source | Notes |
|--------|--------|-------|
| Name | `display_name` | Existing |
| Slug | `slug` | Existing |
| Type | `scene_type` | Metro / Online |
| Active | `is_active` | Checkmark/X |
| Stores | COUNT from join | Existing |
| Discord | `discord_thread_id` | Checkmark/X for linked thread |
| Created | `created_at` | Date added |

- Searchable via reactable search bar
- Adjustable rows per page

### Stores Panel → Map with Legend

When a scene is selected, the "Stores in Selected Scene" section becomes a map:

- Map centered on the scene coordinates with store markers
- Sidebar legend listing store names — click to highlight marker
- Zoom-to-location when a different scene is selected
- Uses existing `atom_mapgl(theme = "digital")` pattern from public stores
- If no stores or no coordinates, shows a fallback message

### Onboarding Workflow

1. Create scene in admin panel (country/state auto-filled from geocode)
2. Create `#scene-coordination` thread in Discord
3. Copy thread ID from Discord URL
4. Paste into the scene's Discord Thread ID field
5. Save — store requests for that scene now route directly

---

## Environment Variables

```
DISCORD_WEBHOOK_SCENE_COORDINATION=https://discord.com/api/webhooks/...
DISCORD_WEBHOOK_SCENE_REQUESTS=https://discord.com/api/webhooks/...
DISCORD_TAG_NEW_REQUEST=<numeric tag ID from Discord>
```

Add to `.env`, `.env.example`, and Posit Connect Cloud environment configuration.

---

## Error Handling

- Webhook failures are logged to Sentry with context (scene_id, store_name, webhook_url)
- User always sees a success confirmation — delivery is best-effort
- If `discord_thread_id` is missing for a scene, fall back to `#scene-requests`
- If all webhooks fail (e.g., invalid URL), the request is still "submitted" from the user's perspective — it just doesn't reach Discord

---

## Dependencies

- `httr2` (already in use for OCR and Mapbox geocoding)
- Discord webhook URLs (created per Forum channel in Discord server settings)
- `discord_thread_id` backfilled for existing scenes

## What This Does NOT Include

- Bug report or feature request forms (future pipelines, same pattern)
- Two-way Discord sync (would require a bot, deferred)
- In-app store request tracking/status (requests are tracked in Discord, not the app)
