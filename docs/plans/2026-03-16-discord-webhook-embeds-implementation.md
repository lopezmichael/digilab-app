# Discord Webhook Embeds & Mentions — Implementation Plan

**Date:** 2026-03-16
**Status:** Ready for implementation
**Scope:** Convert all Discord webhook messages to embeds, add missing mentions, add request IDs, re-wire scene updates
**File:** `R/discord_webhook.R` (primary) + call sites in server files

**Design spec:** See `datamon-bot/docs/superpowers/specs/2026-03-16-webhook-and-bot-messaging-design.md` for full context on why these changes are being made and how they integrate with the datamon-bot thread watcher overhaul.

---

## Overview

All Discord webhook messages currently use plain markdown text via the `content` field. This plan converts them to Discord embeds with:
- Color-coded sidebars by request type
- Structured field layouts
- Request IDs in footers for cross-referencing
- ISO timestamps (Discord renders in viewer's local timezone)
- @mentions moved to `content` (mentions inside embeds don't trigger notifications)

Additionally:
- Scene requests and bug reports get super_admin @mentions (currently nobody is pinged)
- Data error fallback (no scene) gets super_admin mentions
- Store requests get the submitter's Discord username added
- Scene update announcements are re-wired to fire automatically on scene creation

---

## Color Reference

| Request Type | Color (hex) | Color (int) | Use in |
|---|---|---|---|
| Store Request | `#5865F2` | `5793266` | `discord_post_to_scene()` |
| Scene Request | `#9B59B6` | `10181046` | `discord_post_scene_request()` |
| Data Error | `#E67E22` | `15105570` | `discord_post_data_error()` |
| Bug Report | `#E74C3C` | `15158332` | `discord_post_bug_report()` |
| Scene Update | `#57F287` | `5763719` | `discord_post_scene_update()` |
| Resolved | `#2ECC71` | `3066993` | `discord_resolve_thread()` |
| Rejected | `#95A5A6` | `9807270` | `discord_resolve_thread()` |

---

## Step 1: Add `get_super_admin_mentions()` helper

**File:** `R/discord_webhook.R`
**Insert after:** `get_scene_admin_mentions()` (after line ~127)

This is a new function needed by steps 3, 4, and 5.

```r
get_super_admin_mentions <- function(db_pool) {
  tryCatch({
    mentions <- pool::dbGetQuery(db_pool, "
      SELECT DISTINCT discord_user_id
      FROM admin_users
      WHERE role = 'super_admin'
        AND is_active = TRUE
        AND discord_user_id IS NOT NULL
        AND discord_user_id != ''
    ")

    if (nrow(mentions) == 0) return("")

    ids <- mentions$discord_user_id[!is.na(mentions$discord_user_id) & nchar(mentions$discord_user_id) > 0]
    if (length(ids) == 0) return("")
    paste0("<@", ids, ">", collapse = " ")
  }, error = function(e) {
    warning(paste("Failed to fetch super admin mentions:", e$message))
    ""
  })
}
```

**Pattern:** Identical to `get_scene_admin_mentions()` but queries `role = 'super_admin'` instead of scene-specific admins.

---

## Step 2: Convert `discord_post_to_scene()` to embed (Store Requests)

**File:** `R/discord_webhook.R`, lines 131-177
**Channel:** `#scene-coordination`

### Current behavior:
- Builds plain text `content` with store name, location, scene, timestamp
- Appends scene admin mentions to content
- Passes content + tags to `discord_create_action_thread()`

### New behavior:
- Build an embed object with structured fields
- Move mentions to top-level `content` (outside embed, so notifications fire)
- Add request ID to footer

### Changes needed:

**Function signature change** — add `request_id` parameter:
```r
discord_post_to_scene <- function(scene_id, store_name, city_state, db_pool, request_id = NULL)
```

**Replace the content-building section** (roughly lines 145-165) with:

```r
# Build embed
embed <- list(
  title = "New Store Request",
  color = 5793266L,
  fields = list(
    list(name = "Store", value = store_name, inline = TRUE),
    list(name = "Location", value = city_state, inline = TRUE),
    list(name = "Scene", value = scene_display_name, inline = TRUE)
  ),
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
)

# Add discord username if available (currently not passed — see call site change)
# if (nchar(discord_username) > 0) {
#   embed$fields <- c(embed$fields, list(list(name = "Discord", value = discord_username, inline = TRUE)))
# }

# Add footer with request ID
footer_text <- "Submitted via DigiLab"
if (!is.null(request_id)) {
  footer_text <- paste0("Request #", request_id, " \u2022 ", footer_text)
}
embed$footer <- list(text = footer_text)

# Mentions go in content (outside embed) so notifications work
mentions <- get_scene_admin_mentions(scene_id, db_pool)
```

**Update the `discord_create_action_thread()` call** to pass embeds instead of content:

The `discord_create_action_thread()` function currently accepts `message_content` as a string. You'll need to update it to accept either content or embeds. The simplest approach: add an `embeds` parameter and modify the body construction:

```r
discord_create_action_thread <- function(thread_title, message_content = NULL, tags = list(),
                                          webhook_url = NULL, embeds = NULL) {
  body <- list(
    thread_name = thread_title,
    applied_tags = tags
  )
  if (!is.null(embeds)) {
    body$embeds <- embeds
  }
  if (!is.null(message_content) && nchar(message_content) > 0) {
    body$content <- message_content
  }
  # ... rest unchanged
}
```

Then call it with:
```r
discord_create_action_thread(
  thread_title = paste0("Store Request: ", store_name, " - ", city_state),
  message_content = mentions,  # mentions only (triggers notifications)
  embeds = list(embed),
  tags = tags,
  webhook_url = webhook_url
)
```

### Call site change:

**File:** `server/public-stores-server.R` (around line 1916)

Pass `request_id` to the function. The request is inserted before the webhook call, so the ID is available:

```r
# After INSERT ... RETURNING id
request_id <- req_result$id[1]

thread_id <- discord_post_to_scene(scene_id, store_name, location, db_pool, request_id = request_id)
```

**Note:** To also include `discord_username` in the embed, you'll need to pass it through. Check if it's available at the call site — the user's Discord username is captured in the form and saved to `admin_requests.discord_username`.

---

## Step 3: Convert `discord_post_scene_request()` to embed + add mentions

**File:** `R/discord_webhook.R`, lines 181-211
**Channel:** `#scene-requests`

### Current behavior:
- Builds plain text content
- No @mentions
- Creates thread with `DISCORD_TAG_NEW_REQUEST` tag

### New behavior:
- Embed with purple sidebar
- **Add super_admin mentions** (new — these are global requests that need platform admin triage)
- Request ID in footer

### Function signature change:
```r
discord_post_scene_request <- function(store_name, location, discord_username, db_pool = NULL, request_id = NULL)
```

**Note:** `db_pool` is needed now for `get_super_admin_mentions()`. Check the call site in `server/public-stores-server.R` to confirm `db_pool` is available (it should be — it's a reactive value accessible in the server).

### Embed structure:
```r
embed <- list(
  title = "New Scene Request",
  color = 10181046L,
  fields = list(
    list(name = "Store/Community", value = store_name, inline = TRUE),
    list(name = "Location", value = location, inline = TRUE)
  ),
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
)

if (!is.null(discord_username) && nchar(discord_username) > 0) {
  embed$fields <- c(embed$fields, list(list(name = "Discord", value = discord_username, inline = TRUE)))
}

footer_text <- "Submitted via DigiLab"
if (!is.null(request_id)) {
  footer_text <- paste0("Request #", request_id, " \u2022 ", footer_text)
}
embed$footer <- list(text = footer_text)

# NEW: mention super_admins
mentions <- if (!is.null(db_pool)) get_super_admin_mentions(db_pool) else ""
```

### Call site change:

**File:** `server/public-stores-server.R`

Find the call to `discord_post_scene_request()` and add `db_pool` and `request_id`:
```r
thread_id <- discord_post_scene_request(store_name, location, discord_username,
                                         db_pool = db_pool, request_id = request_id)
```

---

## Step 4: Convert `discord_post_data_error()` to embed

**File:** `R/discord_webhook.R`, lines 215-275
**Channel:** `#scene-coordination` (or `#bug-reports` fallback)

### Current behavior:
- Builds plain text content
- Scene admin mentions for scene-routed errors
- Falls back to `discord_post_bug_report()` if no scene

### New behavior:
- Embed with orange sidebar
- Request ID in footer
- **Fallback path:** when no scene, still post to `#bug-reports` but add super_admin mentions

### Function signature change:
```r
discord_post_data_error <- function(scene_id, item_type, item_name, description,
                                     discord_username, db_pool, request_id = NULL)
```

### Embed structure (scene-routed):
```r
embed <- list(
  title = "Data Error Report",
  color = 15105570L,
  fields = list(
    list(name = "Type", value = item_type, inline = TRUE),
    list(name = "Item", value = item_name, inline = TRUE),
    list(name = "Scene", value = scene_display_name, inline = TRUE),
    list(name = "Description", value = description, inline = FALSE)
  ),
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
)

if (!is.null(discord_username) && nchar(discord_username) > 0) {
  embed$fields <- c(embed$fields, list(list(name = "Discord", value = discord_username, inline = TRUE)))
}

footer_text <- "Submitted via DigiLab"
if (!is.null(request_id)) {
  footer_text <- paste0("Request #", request_id, " \u2022 ", footer_text)
}
embed$footer <- list(text = footer_text)

mentions <- get_scene_admin_mentions(scene_id, db_pool)
```

### Fallback path (no scene):

Currently falls back to `discord_post_bug_report()`. Update the fallback call to pass `request_id` and change it to also mention super_admins. The simplest approach: update `discord_post_bug_report()` to accept a `db_pool` parameter (see Step 5), then the fallback naturally gets super_admin mentions.

### Call site change:

**File:** `server/shared-server.R` (around lines 674-681)

Add `request_id`:
```r
thread_id <- discord_post_data_error(
  scene_id = scene_id,
  item_type = data_error_context$item_type,
  item_name = data_error_context$item_name,
  description = description,
  discord_username = discord_username,
  db_pool = db_pool,
  request_id = request_id
)
```

---

## Step 5: Convert `discord_post_bug_report()` to embed + add mentions

**File:** `R/discord_webhook.R`, lines 279-312
**Channel:** `#bug-reports`

### Current behavior:
- Builds plain text content with description, context, discord username
- No @mentions
- Creates thread with `DISCORD_TAG_NEW_BUG` tag

### New behavior:
- Embed with red sidebar
- **Add super_admin mentions**
- Request ID in footer

### Function signature change:
```r
discord_post_bug_report <- function(title, description, context, discord_username,
                                     db_pool = NULL, request_id = NULL)
```

### Embed structure:
```r
embed <- list(
  title = paste0("Bug: ", substr(title, 1, 90)),
  color = 15158332L,
  fields = list(
    list(name = "Description", value = description, inline = FALSE),
    list(name = "Context", value = context, inline = TRUE)
  ),
  timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
)

if (!is.null(discord_username) && nchar(discord_username) > 0) {
  embed$fields <- c(embed$fields, list(list(name = "Discord", value = discord_username, inline = TRUE)))
}

footer_text <- "Submitted via DigiLab"
if (!is.null(request_id)) {
  footer_text <- paste0("Request #", request_id, " \u2022 ", footer_text)
}
embed$footer <- list(text = footer_text)

# NEW: mention super_admins for triage
mentions <- if (!is.null(db_pool)) get_super_admin_mentions(db_pool) else ""
```

### Call site changes:

**File:** `server/shared-server.R`

Find both call sites for `discord_post_bug_report()`:
1. Direct bug report submission
2. Data error fallback (no scene)

Add `db_pool` and `request_id` to both:
```r
thread_id <- discord_post_bug_report(title, description, context, discord_username,
                                      db_pool = db_pool, request_id = request_id)
```

---

## Step 6: Convert `discord_resolve_thread()` to embed

**File:** `R/discord_webhook.R`, lines 375-440
**Channel:** Existing thread (any forum channel)

### Current behavior:
- Posts plain text: `"**Resolved** by {admin} via DigiLab"` or `"**Rejected** by ..."`
- Adds `DISCORD_TAG_RESOLVED` tag via PATCH

### New behavior:
- Post an embed instead of plain text
- Green sidebar for resolved, grey for rejected
- Add timestamp

### Changes:

Replace the message body construction (around line 388):

```r
label <- if (action == "resolved") "Resolved" else "Rejected"
color <- if (action == "resolved") 3066993L else 9807270L

msg_body <- list(
  embeds = list(list(
    title = label,
    description = paste0("by ", resolved_by, " via DigiLab"),
    color = color,
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  ))
)
```

The rest of the function (GET current tags, PATCH to add resolved tag) stays the same.

### Call site: No changes needed. `server/admin-notifications-server.R` line 439 already passes the right parameters.

---

## Step 7: Update `discord_create_action_thread()` to support embeds

**File:** `R/discord_webhook.R`, lines 46-97

This is the base function that creates forum threads. It needs to support embeds alongside or instead of plain text content.

### Current signature:
```r
discord_create_action_thread <- function(thread_title, message_content, tags = list(), webhook_url = NULL)
```

### New signature:
```r
discord_create_action_thread <- function(thread_title, message_content = NULL, tags = list(),
                                          webhook_url = NULL, embeds = NULL)
```

### Body construction change:

Replace the body building (around line 70):

```r
body <- list(
  thread_name = thread_title,
  applied_tags = tags
)

# Embeds go in the body if provided
if (!is.null(embeds)) {
  body$embeds <- embeds
}

# Content (used for @mentions) goes alongside embeds
if (!is.null(message_content) && nchar(message_content) > 0) {
  body$content <- message_content
}
```

This is backward-compatible — existing callers that pass `message_content` will still work.

---

## Step 8: Convert `discord_post_scene_update()` to embed + re-wire trigger

**File:** `R/discord_webhook.R`, lines 498-533
**Channel:** `#scene-updates`

### Part A: Convert to embed

### Current behavior:
- Randomly selects from 6 plain text templates
- Posts via `discord_send()` (not a thread, just a channel message)

### New behavior:
- Embed with green sidebar
- Keep random template selection for the description
- Add location/continent fields

### New function:
```r
discord_post_scene_update <- function(scene_name, country = NULL, state_region = NULL, continent = NULL) {
  webhook_url <- Sys.getenv("DISCORD_WEBHOOK_SCENE_UPDATES", "")
  if (nchar(webhook_url) == 0) return(invisible(FALSE))

  templates <- c(
    paste0("**", scene_name, "** just joined DigiLab! Check out their local leaderboard and tournament history."),
    paste0("Welcome to the family, **", scene_name, "**! Your scene is now live."),
    paste0("**", scene_name, "** is officially on the map! Local players can now find their stats and standings."),
    paste0("A new scene has arrived! **", scene_name, "** is ready to track tournaments, players, and meta."),
    paste0("The DigiLab network grows! Welcome **", scene_name, "** to the community."),
    paste0("**", scene_name, "** has entered the arena! Another scene joins the DigiLab family.")
  )

  embed <- list(
    title = paste0("New Scene: ", scene_name),
    description = sample(templates, 1),
    color = 5763719L,
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    footer = list(text = "DigiLab")
  )

  # Add location fields if available
  fields <- list()
  if (!is.null(country) && !is.na(country) && nchar(country) > 0) {
    location <- country
    if (!is.null(state_region) && !is.na(state_region) && nchar(state_region) > 0) {
      location <- paste0(state_region, ", ", country)
    }
    fields <- c(fields, list(list(name = "Location", value = location, inline = TRUE)))
  }
  if (!is.null(continent) && !is.na(continent) && nchar(continent) > 0) {
    # Pretty-print continent name
    continent_label <- gsub("_", " ", continent)
    continent_label <- paste0(toupper(substr(continent_label, 1, 1)), substr(continent_label, 2, nchar(continent_label)))
    fields <- c(fields, list(list(name = "Continent", value = continent_label, inline = TRUE)))
  }
  if (length(fields) > 0) {
    embed$fields <- fields
  }

  body <- list(embeds = list(embed))
  discord_send(webhook_url, body)
}
```

### Part B: Re-wire the trigger

**File:** `server/admin-scenes-server.R`
**Location:** Inside `execute_scene_save()` (around line 381-391)

After the `INSERT INTO scenes` succeeds and you have the new `scene_id`, call the update function:

```r
# After successful INSERT ... RETURNING scene_id
if (nrow(insert_result) > 0) {
  # Post scene update announcement
  discord_post_scene_update(
    scene_name = form$display_name,
    country = form$country,
    state_region = form$state_region,
    continent = derive_continent(form$country)
  )
}
```

**Important:** Only call this on INSERT (new scene creation), NOT on UPDATE (editing existing scene). The current code likely has branching for create vs edit — make sure the call is only in the create branch.

---

## Step 9: Verification Checklist

After implementing all changes, verify each webhook by triggering it and checking Discord:

- [ ] **Store request:** Submit via app → `#scene-coordination` gets blue embed with fields, footer with request ID, admin mentions
- [ ] **Scene request:** Submit via app → `#scene-requests` gets purple embed, super_admin mentions, request ID
- [ ] **Data error (with scene):** Report via app → `#scene-coordination` gets orange embed, scene admin mentions, request ID
- [ ] **Data error (no scene):** Report via app → `#bug-reports` gets orange embed, super_admin mentions, request ID
- [ ] **Bug report:** Submit via app → `#bug-reports` gets red embed, super_admin mentions, request ID
- [ ] **Resolution:** Resolve via admin panel → existing thread gets green embed "Resolved by X via DigiLab"
- [ ] **Rejection:** Reject via admin panel → existing thread gets grey embed "Rejected by X via DigiLab"
- [ ] **Scene update:** Create new scene via admin → `#scene-updates` gets green embed with scene name, location, continent
- [ ] **Existing tags preserved:** Store request embeds still have continent + store_request tags
- [ ] **Mentions trigger notifications:** Admin gets Discord notification ping (not just silent embed)

---

## Files Changed Summary

| File | Changes |
|---|---|
| `R/discord_webhook.R` | All 7 `discord_post_*`/`discord_resolve_*` functions converted to embeds; `discord_create_action_thread()` updated to accept embeds; new `get_super_admin_mentions()` helper |
| `server/public-stores-server.R` | Pass `request_id` to `discord_post_to_scene()` and `discord_post_scene_request()`; pass `db_pool` to scene request |
| `server/shared-server.R` | Pass `request_id` and `db_pool` to `discord_post_data_error()` and `discord_post_bug_report()` |
| `server/admin-scenes-server.R` | Add `discord_post_scene_update()` call after scene INSERT |
| `server/admin-notifications-server.R` | No changes needed (resolve handler already passes correct params) |
