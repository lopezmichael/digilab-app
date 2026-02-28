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
5. Design for future app → Discord integration (webhooks) without building it now

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

💬 COMMUNITY
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

### Carl-bot Automation (Optional)

- **Welcome DM:** New members receive a message pointing them to #scene-requests
- **Auto-tag:** New forum posts default to `New Request` / `New`
- **Post templates:** Forum channels prompt structured input ("What city/region? How many stores? How often are tournaments held?")

---

## Permissions Matrix

| Channel | @everyone | Scene Admin | Platform Admin | Dev |
|---------|-----------|-------------|----------------|-----|
| **INFO** | Read | Read | Read + Write | Full |
| **COMMUNITY** | Read + Write | Read + Write | Read + Write | Full |
| **REQUESTS** (Forums) | Post + Reply to own | Post + Reply to any | Manage tags + posts | Full |
| **COORDINATION** | Hidden | Read + Write | Read + Write | Full |
| **#regional-leads** | Hidden | Hidden | Read + Write | Full |
| **REGIONAL HUBS** | Hidden | Their region only | All regions | Full |
| **OPS** | Hidden | Hidden | Hidden | Full |

---

## Migration Plan

Since the Discord is only 2 days old, this is effectively a fresh setup.

**Step 1:** Create new structure — Forum channels with tags and post templates, categories, permissions

**Step 2:** Move existing content
- `#get-started` content → split into short `#welcome` message + pinned guidelines in `#scene-requests`
- `#admin-requests` threads → recreate as posts in `#scene-requests` (tag appropriately) and `#scene-coordination` for already-onboarded scenes
- `#data-collection` → keep as-is, moves under Coordination
- `#error-log` → keep as-is, moves under OPS

**Step 3:** Set up Carl-bot — welcome DM, forum templates, auto-tags

**Step 4:** Announce — post in `#announcements` explaining the new layout, DM active scene admins

**Step 5:** Clean up — archive old channels (#admin-requests, #get-started, old onboarding category)

---

## Future: App → Discord Integration

The Forum channel structure supports Discord webhooks. A future in-app feedback form (FB1 on roadmap) could post directly to the appropriate forum channel. Deferred — design the webhook integration when ready to build it.
