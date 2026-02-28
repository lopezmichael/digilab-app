# Discord Server Organization Design

**Date:** 2026-02-26
**Status:** Approved
**Scope:** DigiLab Discord server structure, roles, intake workflow, permissions

---

## Context

DigiLab Discord is 2 days old and primarily serves as an onboarding pipeline — people discover DigiLab, request their area be added, and get converted into scene admins. The initial channel structure (lounge, info, operations, onboarding) resulted in admin-requests threads becoming ad-hoc scene hubs. With 20+ scenes and growing across multiple countries, the server needs a scalable structure before patterns solidify.

## Goals

1. Replace chaotic admin-requests threads with structured, tagged Forum channels
2. Clear intake workflow with visible status at a glance
3. Tiered coordination spaces that scale — scenes graduate as communities grow
4. Reduce manual routing/triage burden on the dev
5. App → Discord webhook integration for bug reports, store requests, and scene routing

---

## Roles

| Role | Discord Permissions | Who |
|------|-------------------|-----|
| **Dev** | Full admin | Platform owner |
| **Platform Admin** | Manage channels, messages, roles | Trusted helpers (future) |
| **Scene Admin** | Access to coordination channels, post in forums | Onboarded scene admins |
| **@everyone** | Read public channels, post in intake forums | New visitors, players |

**Regional Coordinator** is NOT a Discord role — it's an app-level permission for users who manage multiple scenes in a country (e.g., someone coordinating all 4 Brazil scenes). In Discord, they're Scene Admins with access to `#regional-leads`.

---

## Channel Structure

```
📋 INFO
  #welcome            — Static welcome message + how to get started
  #announcements      — Platform announcements, new scene launches, updates
  #rules              — Server rules (keep short)

💬 LOUNGE
  #general            — Open chat for anyone
  #showcase           — Players sharing results, deck pics, etc. (future)

📥 REQUESTS (Forum channels — public, anyone can post)
  #scene-requests     — "Add my area to DigiLab"
  #feature-requests   — "I wish DigiLab had..."
  #bug-reports        — "Something's broken"

🔧 COORDINATION (Scene Admins+ only)
  #scene-coordination — Forum, one thread per scene for ongoing ops
  #data-collection    — Conversation about gathering/submitting data
  #resources          — Static reference: guides, tools, templates
  #regional-leads     — Private, dev + country coordinators only

🌎 REGIONAL HUBS (Scene Admins in those regions only)
  #brazil             — Cross-scene coordination for Brazil (template)
  (more channels added as countries hit 3+ scenes)

⚙️ OPS (Dev/Platform Admin only)
  #error-log          — Sentry alerts
  #dev-log            — Internal notes, deploy announcements
```

### Graduation Path

```
#scene-requests post → #scene-coordination thread → #regional-hubs channel
```

Scenes start as a forum post in #scene-requests during onboarding. Once live, they get a thread in #scene-coordination for ongoing ops. When a country accumulates 3+ scenes, it graduates to its own channel in Regional Hubs with a pinned message linking to the old threads for history.

**Note:** Discord does not support moving/merging threads between channels. When graduating, create the new channel, pin a link to the old threads, and let new conversation happen going forward. Old threads remain searchable.

### Thread Naming Convention

Use consistent naming for forum threads in #scene-requests and #scene-coordination:

**Format:** `Country/State (City/Region)`

**Examples:**
- `Brazil (São Paulo)` — country + state/city
- `Ohio (Cincinnati Area)` — US state + metro area
- `Pennsylvania (NEPA)` — US state + regional abbreviation
- `New Zealand (Wellington)` — country + city
- `Canada (Metro Vancouver)` — country + metro area
- `Denmark (Copenhagen)` — country + city
- `Portugal (Azores)` — country + region

**Guidelines:**
- Lead with the broadest geographic identifier (country for international, US state for domestic)
- Parenthetical should be recognizable to locals
- Use common abbreviations if well-known (NEPA, DMW, etc.)
- Match the scene name in the app when possible

---

## Forum Tags

### #scene-requests

| Tag | Color | Meaning |
|-----|-------|---------|
| `New Request` | Blue | Just submitted, not reviewed yet |
| `In Progress` | Yellow | Working with them on setup |
| `Needs Data` | Orange | Waiting on them to provide stores/tournament info |
| `Onboarded` | Green | Scene is live in the app |
| `On Hold` | Gray | Not enough activity yet, revisit later |

### #bug-reports

| Tag | Color | Meaning |
|-----|-------|---------|
| `New` | Blue | Unreviewed |
| `Confirmed` | Yellow | Reproduced |
| `Fixed` | Green | Deployed |
| `Won't Fix` | Gray | Not a bug or not worth fixing |

### #feature-requests

| Tag | Color | Meaning |
|-----|-------|---------|
| `New` | Blue | Unreviewed |
| `Planned` | Yellow | On the roadmap |
| `Shipped` | Green | Released |
| `Not Planned` | Gray | Declined with explanation |

### #scene-coordination

Region tags for filtering scene threads by continent. Split into more granular tags as regions grow.

| Tag | Emoji | Covers |
|-----|-------|--------|
| `North America` | 🏔️ | USA, Canada, Mexico |
| `South America` | ☀️ | Brazil, Argentina, etc. |
| `Europe` | 🏰 | UK, EU countries |
| `Asia` | ⛩️ | Philippines, Japan, etc. |
| `Oceania` | 🌊 | Australia, New Zealand |
| `Africa` | 🌅 | (future scenes) |
| `Online` | 🌐 | Limitless organizers |

---

## Forum Post Guidelines & Pinned Posts

### #scene-requests

**Post Guidelines:**
> Tell us about your area! Include:
> - City/region and country
> - How many stores run Digimon TCG tournaments?
> - How often are tournaments held?
> - Are you a tournament organizer or a player?

**Default Reaction:** 🎉

**Pinned Post — "How Scene Requests Work":**
> Welcome! If your area isn't on DigiLab yet, create a post here and we'll work with you to get it set up.
>
> **What we need from you:**
> 1. Your city/region and country
> 2. Names of stores that run Digimon TCG events
> 3. Approximate tournament frequency (weekly, biweekly, monthly)
> 4. Whether you're an organizer or player
>
> **What happens next:**
> - We'll tag your post as we work through it
> - Once your scene is live, you'll get the Scene Admin role
> - Your scene gets its own thread in our coordination channel
>
> Tags: `New Request` → `In Progress` → `Needs Data` → `Onboarded`

### #bug-reports

**Post Guidelines:**
> Help us fix it! Include:
> - What page were you on?
> - What happened vs what you expected?
> - Device and browser (mobile/desktop, Chrome/Safari/etc.)
> - Screenshot if possible

**Default Reaction:** 👀

**Pinned Post — "How to Report a Bug":**
> Found something broken on DigiLab? Create a post here.
>
> **Please include:**
> 1. What page you were on (Dashboard, Players, Stores, etc.)
> 2. What happened and what you expected to happen
> 3. Your device and browser (e.g., iPhone Safari, Desktop Chrome)
> 4. A screenshot if you can
>
> We'll tag your report as we work on it:
> `New` → `Confirmed` → `Fixed`
>
> Quick issues may get patched the same day. Bigger fixes go on the roadmap.

### #feature-requests

**Post Guidelines:**
> What would make DigiLab better for you?
> - What feature or improvement do you want?
> - Why would it help you or your community?
> - Any examples from other apps/sites?

**Default Reaction:** 💡

**Pinned Post — "How Feature Requests Work":**
> Have an idea for DigiLab? We'd love to hear it. Create a post here.
>
> **Tell us:**
> 1. What you'd like to see
> 2. Why it would help you or your community
> 3. Examples from other apps if you have any
>
> We'll tag requests as we plan:
> `New` → `Planned` → `Shipped`
>
> Popular requests and things that align with the roadmap get prioritized. We can't build everything, but we read everything.

### #scene-coordination

**Post Guidelines:**
> This is your scene's home thread. Use it for:
> - Updating tournament schedules
> - Reporting new stores or closures
> - Coordinating with the DigiLab team
> - Asking questions about the platform

**Default Reaction:** ✅

**Pinned Post — "Welcome, Scene Admins":**
> Each scene gets its own thread here for ongoing operations — tournament updates, new stores, data questions, etc.
>
> **Your thread is where:**
> - Store requests and updates for your area get routed
> - You coordinate with us on data collection
> - You flag anything that needs attention
>
> Use the continent tags to filter to your region. Threads auto-archive when inactive and pop back up when there's new activity.
>
> Need help? Tag @Dev in your thread.

## Forum Settings

| Setting | #scene-requests | #bug-reports | #feature-requests | #scene-coordination |
|---------|----------------|-------------|-------------------|---------------------|
| Sort order | Recent Activity | Recent Activity | Recent Activity | Recent Activity |
| Auto-archive | 1 hour | 1 hour | 1 hour | 24 hours |
| Require tags | Yes | Yes | Yes | Yes |

---

## Intake Workflow

```
New person joins Discord
  → Sees #welcome (short intro, links to #scene-requests)
  → Posts in #scene-requests ("I want to add São Paulo")
  → Dev tags it "In Progress", replies with requirements
  → Back-and-forth happens in that forum post's thread
  → Scene goes live → tag "Onboarded"
  → Thread created in #scene-coordination for ongoing ops
  → Person receives Scene Admin role
  → If their country hits 3+ scenes → graduate to Regional Hub
```

### Carl-bot Automation

- **Welcome DM:**
  > Hey {user}, welcome to {server}!
  >
  > DigiLab is a community-built tournament tracker for Digimon TCG locals — track standings, deck meta, and scene history for your region at digilab.cards.
  >
  > A few useful spots to check out:
  > 📋 #welcome — how everything works
  > 🌍 #scene-requests — want your area on DigiLab? Start here
  > 💬 #general — jump in anytime
  >
  > Glad you're here!
- **Auto-tag:** New forum posts default to `New Request` / `New`
- **Post templates:** Forum channels prompt structured input ("What city/region? How many stores? How often are tournaments held?")

---

## Permissions Matrix

| Channel | @everyone | Scene Admin | Platform Admin | Dev |
|---------|-----------|-------------|----------------|-----|
| **INFO** | Read | Read | Read + Write | Full |
| **LOUNGE** | Read + Write | Read + Write | Read + Write | Full |
| **REQUESTS** (Forums) | Post + Reply to own | Post + Reply to any | Manage tags + posts | Full |
| **COORDINATION** | Hidden | Read + Write | Read + Write | Full |
| **#regional-leads** | Hidden | Hidden | Read + Write | Full |
| **REGIONAL HUBS** | Hidden | Their region only | All regions | Full |
| **OPS** | Hidden | Hidden | Hidden | Full |

---

## Migration Plan

Since the Discord is only 2 days old, this is effectively a fresh setup.

**Step 1:** Create new structure — Forum channels with tags and post templates, categories, permissions ✅

**Step 2:** Move existing content
- `#get-started` content → split into short `#welcome` message + pinned guidelines in `#scene-requests`
- `#admin-requests` threads → recreate as posts in `#scene-requests` (tag appropriately) and `#scene-coordination` for already-onboarded scenes
- `#feature-requests` old channel → migrate posts to new Forum (see Migrated Posts below)
- `#data-collection` → keep as-is, moves under Coordination
- `#error-log` → keep as-is, moves under OPS

**Step 3:** Set up Carl-bot — welcome DM, forum templates, auto-tags

**Step 4:** Announce — post in `#announcements` explaining the new layout, DM active scene admins

**Step 5:** Clean up — archive old channels (#admin-requests, #get-started, #feature-requests text channel, old onboarding category)

### Migrated Posts

Feature requests migrated from the old `#feature-requests` text channel to the new Forum:

**Post: "Self-service store submission with player validation"** — Tag: `Planned`
> **Requested by:** Kargalargus (2/26/2026)
>
> Allow players to manually add a store without submitting a Google Form. Add more regions by default and let players submit stores with validation/confirmation from other players to reduce friction and encourage more participation.
>
> **Dev note:** Aligns with the public submissions roadmap. Scene admins will manage stores for their areas — working toward removing the Google Form dependency.

**Post: "Import tournament results from Bandai TCG+ CSV export"** — Tag: `New`
> **Requested by:** Erich DTCG (2/26/2026)
>
> Bandai TCG+ has an event management dashboard that can export tournament results as a CSV file. Adding a CSV import option would let organizers submit results directly without screenshots, eliminating OCR errors.
>
> Sample CSV was shared via DM for reference.
>
> **Dev note:** Previously unaware of this export feature. Could be a more reliable alternative to screenshot OCR for organizers who use Bandai TCG+.

---

## App → Discord Webhook Integration

### Overview

The app sends messages to Discord channels via **webhooks** — no bot required. Webhooks are one-directional (app → Discord) and use simple HTTP POST requests. Each target Forum channel gets its own webhook URL stored as an environment variable.

### Use Cases

| Source | Target Channel | Behavior |
|--------|---------------|----------|
| Bug report (user submits in-app) | `#bug-reports` | Creates new Forum post with `New` tag |
| Feature request (user submits in-app) | `#feature-requests` | Creates new Forum post with `New` tag |
| Store request — existing scene | `#scene-coordination` | Replies to that scene's existing thread |
| Store request — new scene | `#scene-requests` | Creates new Forum post with `New Request` tag |
| Tournament error (system-detected) | `#error-log` | Posts error details (alongside Sentry) |

### How It Works

**Creating a new Forum post:**
```
POST https://discord.com/api/webhooks/{webhook_id}/{webhook_token}
Body: {
  "thread_name": "Bug: Login page broken on mobile",
  "content": "**Reported by:** PlayerName\n**Page:** Tournaments\n...",
  "applied_tags": ["<new_tag_id>"]
}
```

**Replying to an existing scene thread:**
```
POST https://discord.com/api/webhooks/{webhook_id}/{webhook_token}?thread_id={scene_thread_id}
Body: {
  "content": "**New Store Request**\nStore: Card Shop Tokyo\nSubmitted by: ..."
}
```

The `thread_id` query parameter routes the message to a specific Forum thread. This is how store requests land in the correct scene's thread.

### Routing Logic

When a user submits a store request in-app:

```
User submits store request
  → Is the scene already in the app?
    → YES: Look up scene's discord_thread_id → POST to #scene-coordination thread
    → NO:  POST to #scene-requests → creates new Forum post with "New Request" tag
```

The app UI handles this with a dropdown — if the user's area is listed, it routes to `#scene-coordination`; if they select "My area isn't listed," it routes to `#scene-requests`.

### Database Changes

```sql
-- Map each scene to its Discord Forum thread in #scene-coordination
ALTER TABLE scenes ADD COLUMN discord_thread_id TEXT;
```

When a scene is onboarded and its `#scene-coordination` thread is created, save the thread ID to this column. The app uses it for webhook routing.

### Environment Variables

```
DISCORD_WEBHOOK_BUG_REPORTS=https://discord.com/api/webhooks/...
DISCORD_WEBHOOK_FEATURE_REQUESTS=https://discord.com/api/webhooks/...
DISCORD_WEBHOOK_SCENE_REQUESTS=https://discord.com/api/webhooks/...
DISCORD_WEBHOOK_SCENE_COORDINATION=https://discord.com/api/webhooks/...
DISCORD_WEBHOOK_ERROR_LOG=https://discord.com/api/webhooks/...
```

### Implementation: `R/discord_webhook.R`

A small R module with:
- `discord_post_bug_report(title, description, reporter)` — new post in `#bug-reports`
- `discord_post_feature_request(title, description, reporter)` — new post in `#feature-requests`
- `discord_post_scene_request(city, country, details, submitter)` — new post in `#scene-requests`
- `discord_post_to_scene(scene_id, message)` — looks up `discord_thread_id` from DB, posts to that scene's `#scene-coordination` thread
- `discord_send(webhook_url, body, thread_id = NULL)` — base helper, handles HTTP POST, error handling, fire-and-forget (non-blocking so the UI doesn't wait on Discord)

Uses `httr2` for HTTP requests. Errors are logged but never block the user — webhook delivery is best-effort.

### Forum Thread Management

`#scene-coordination` uses Discord's auto-archive to stay clean:
- Threads with no activity auto-archive after a configurable period (24h / 3 days / 1 week)
- Archived threads are hidden from the default view — only active threads show
- When a webhook posts to a scene's thread, it unarchives and bumps to the top automatically
- Scene admins should mute the channel and follow their own thread for notifications
- Tags by country/region allow filtering to relevant threads

### Discord Setup Steps

1. Create one webhook per target Forum channel (5 webhooks total)
2. Save webhook URLs as environment variables
3. Note the numeric tag IDs from each Forum channel (needed for `applied_tags` in webhook payloads)
4. When onboarding a scene, save its `#scene-coordination` thread ID to the `scenes` table

### What This Does NOT Require

- **No Discord bot** — webhooks are stateless HTTP calls, no bot token or gateway connection
- **No OAuth** — webhook URLs are server-side secrets, not user-facing
- **No real-time sync back** — Discord replies don't flow back into the app (would need a bot for that, deferred)
