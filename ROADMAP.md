---
currentVersion: "1.3.0"
lastUpdated: "2026-03-04"

inProgress:
  - id: mobile-public-views
    title: "Mobile Public Views"
    description: "Dedicated mobile layouts for all 5 public tabs — Overview, Players, Meta, Tournaments, Stores — with device detection, stacked card layouts, and mobile-optimized charts."
    tags: [mobile, ux]
    targetVersion: "v1.3.x"

  - id: pwa-enhancements
    title: "PWA Enhancements"
    description: "Expanded PWA icon sizes, dark mode tab bar, safe area insets for iPhone X+, and installability improvements."
    tags: [mobile, ux]
    targetVersion: "v1.3.x"

planned:
  # v1.4.0 — Mobile Admin & Data Entry
  - id: mobile-upload-tabs
    title: "Mobile Upload Tabs"
    description: "Mobile-optimized layouts for Upload Results and Enter Results tabs with touch-friendly grids and camera upload flow."
    tags: [mobile, ux]
    targetVersion: "v1.4.0"

  - id: mobile-admin-tabs
    title: "Mobile Admin Tabs"
    description: "Mobile layouts for scene admin tabs (Edit Stores, Edit Tournaments, Edit Players) and super admin tabs (Edit Scenes, Edit Admins, Edit Decks)."
    tags: [mobile, admin]
    targetVersion: "v1.4.0"

  - id: admin-search
    title: "Admin Search Functionality"
    description: "Add search and filtering to scene admin and super admin pages for faster data management at scale."
    tags: [admin, ux]
    targetVersion: "v1.4.0"

  # v1.5.0 — Tournament Data & Ingestion
  - id: decklist-entry
    title: "Decklist Entry & Backfill"
    description: "Add decklists during tournament result entry or backfill them later from the Edit Tournaments tab."
    tags: [feature, data]
    targetVersion: "v1.5.0"

  - id: casual-event-types
    title: "Casual Event Types"
    description: "New event types (regulation battles, casual night, experimental formats) that don't affect Elo ratings, keeping competitive scores clean."
    tags: [feature, ratings]
    targetVersion: "v1.5.0"

  - id: csv-upload
    title: "CSV Result Upload"
    description: "Import tournament results from Bandai TCG+ organizer CSV exports for faster, error-free data entry."
    tags: [feature, data]
    targetVersion: "v1.5.0"

  - id: ocr-improvements
    title: "OCR Upload Improvements"
    description: "Bug fixes and process improvements for screenshot-based OCR uploads including better error handling and accuracy."
    tags: [feature, data]
    targetVersion: "v1.5.0"

  - id: round-by-round
    title: "Round-by-Round Enhancements"
    description: "Improved UX for match history uploads, better database handling, and player-facing visibility for round-by-round data."
    tags: [feature, data]
    targetVersion: "v1.5.0"

  # v1.6.0 — UX Polish & Store Improvements
  - id: modal-improvements
    title: "Modal Improvements"
    description: "Enhanced player, store, and deck modals with rating sparklines, global vs local rank, deck history, and other data-rich additions."
    tags: [ux, feature]
    targetVersion: "v1.6.0"

  - id: store-page-reorg
    title: "All Scenes Store Reorganization"
    description: "Group stores by scene on the All Scenes view with collapsible sections and additional filtering options to reduce clutter."
    tags: [ux, feature]
    targetVersion: "v1.6.0"

  - id: scene-selector-redesign
    title: "Scene Selector Redesign"
    description: "Rethink the scene selection UX to handle growth beyond a single dropdown — grouped, searchable, or hierarchical selection."
    tags: [ux, scaling]
    targetVersion: "v1.6.0"

  # v1.7.0 — Performance & Caching
  - id: query-optimization
    title: "Query Optimization"
    description: "Audit slow queries with EXPLAIN ANALYZE, add missing indexes, and implement materialized views for dashboard aggregations."
    tags: [scaling]
    targetVersion: "v1.7.0"

  - id: caching-expansion
    title: "Caching Expansion"
    description: "Expand bindCache() coverage across all outputs, batch startup queries, and tune Neon connection pool settings."
    tags: [scaling]
    targetVersion: "v1.7.0"

  - id: lazy-tab-loading
    title: "Lazy Tab Loading"
    description: "Defer data fetching until a tab is actually visited instead of loading all tabs on startup."
    tags: [scaling]
    targetVersion: "v1.7.0"

  # v1.8.0 — Achievement Badges & Gamification
  - id: achievement-badges
    title: "Achievement Badges"
    description: "Auto-calculated player achievements displayed in player modals — tournament streaks, deck mastery, and scene milestones."
    tags: [gamification, feature]
    targetVersion: "v1.8.0"

  # v1.9.0 — Regional Admin & Multi-Region
  - id: regional-admin-tier
    title: "Regional Admin Tier"
    description: "New admin role between Super Admin and Scene Admin for country or state-level oversight with cross-scene management."
    tags: [admin, scaling]
    targetVersion: "v1.9.0"

  - id: admin-audit-log
    title: "Admin Audit Log"
    description: "Track who changed what and when across all admin actions with before/after snapshots and optional undo."
    tags: [admin, security]
    targetVersion: "v1.9.0"

  - id: tournament-tiers
    title: "Tournament Tiers"
    description: "Add tier classification to tournaments (local, regional, national, international) for filtering and ranking context."
    tags: [feature, data]
    targetVersion: "v1.9.0"

  - id: cross-scene-badges
    title: "Cross-Scene Player Badges"
    description: "Show which scenes a player has competed in within their player modal, with home scene inference."
    tags: [feature, community]
    targetVersion: "v1.9.0"

  # Future
  - id: meta-insights-app
    title: "Meta Insights App"
    description: "Standalone analytics app for deep deck meta analysis, matchup data, and tournament trend insights."
    tags: [new-app, analytics]
    targetVersion: "Future"

  - id: dev-insights-app
    title: "Dev Insights App"
    description: "Internal analytics dashboard for development metrics, app usage patterns, and operational monitoring."
    tags: [new-app, analytics]
    targetVersion: "Future"

  - id: mascot-branding
    title: "Mascot & Branding"
    description: "Commission custom Digimon SVG set, Digivice footer watermark, and expanded Agumon poses for achievements and celebrations."
    tags: [ux, content]
    targetVersion: "Future"

  - id: accessibility-pass
    title: "Accessibility Pass"
    description: "WCAG compliance audit covering color contrast, screen reader labels, keyboard navigation, and ARIA attributes."
    tags: [ux]
    targetVersion: "Future"

  - id: automated-testing
    title: "Automated Testing & CI"
    description: "Integration test suite for app loading, key queries, OCR parser accuracy, and regression prevention in CI."
    tags: [scaling]
    targetVersion: "Future"

completed:
  # v1.3.0
  - id: mobile-views
    title: "Mobile Views & PWA Fixes"
    description: "Dedicated mobile views for all 5 public pages with JS device detection, stacked card layouts, mobile CSS foundation, and PWA improvements including icon sizes and safe area insets."
    tags: [mobile, ux]
    date: "2026-03"
    version: "v1.3.0"

  # v1.2.0
  - id: rating-redesign
    title: "Rating System Redesign"
    description: "Complete overhaul of the competitive rating algorithm with single-pass chronological processing, proper tie handling, and no time-based decay."
    tags: [ratings, methodology]
    date: "2026-03"
    version: "v1.2.0"
    link: /blog/new-rating-system

  - id: digilab-website
    title: "DigiLab Website"
    description: "Public-facing website at digilab.cards with blog, public roadmap, and landing page. Built with Astro and hosted on Vercel."
    tags: [website, content]
    date: "2026-03"
    version: "v1.2.0"

  - id: app-subdomain-migration
    title: "App Moved to app.digilab.cards"
    description: "Migrated the Shiny app from digilab.cards to app.digilab.cards to make room for the public website."
    tags: [website, scaling]
    date: "2026-03"
    version: "v1.2.0"

  # v1.1.x
  - id: cross-scene-collision-fix
    title: "Cross-Scene Player Collision Fix"
    description: "Fixed player name collisions across scenes with scene-scoped matching and duplicate detection scripts."
    tags: [data, feature]
    date: "2026-03"
    version: "v1.1.2"

  - id: tournament-query-fix
    title: "Tournament Query Fix"
    description: "Fixed duplicate tournament rows caused by tied first-place finishers from Limitless Swiss events."
    tags: [data]
    date: "2026-02"
    version: "v1.1.1"

  - id: discord-integration
    title: "Discord Integration & Error Reporting"
    description: "Discord webhook system with themed Digimon bots, in-app request modals for stores and scenes, contextual error reporting, and bug report forms."
    tags: [integration, community]
    date: "2026-02"
    version: "v1.1.0"

  # v1.0.x
  - id: post-launch-fixes
    title: "Post-Launch Fixes & Polish"
    description: "9 patch releases covering database connection stability, Limitless integration fixes, deck request UX, member number management, global map improvements, dynamic min-event filters, admin dropdown fixes, and international store support."
    tags: [data, ux, admin]
    date: "2026-02"
    version: "v1.0.9"

  - id: public-launch
    title: "Public Launch"
    description: "v1.0 release with PWA support, Agumon mascot (loading, disconnect, 404), performance profiling, responsive grids, lazy admin UI, production hardening, and browser credential saving."
    tags: [feature, ux]
    date: "2026-02"
    version: "v1.0.0"

  # v0.29–v0.30
  - id: admin-auth
    title: "Admin Authentication"
    description: "Per-user admin accounts with bcrypt hashing, role-based permissions (super admin / scene admin), scene scoping, manage admins UI, and GA4 custom events."
    tags: [security, admin]
    date: "2026-02"
    version: "v0.29.0"

  - id: content-error-tracking
    title: "Content Updates, Error Tracking & Admin UX"
    description: "OCR layout-aware parser (73% → 95% accuracy), Sentry error tracking, FAQ/About/For Organizers rewrites, skeleton loaders, inline form validation, and UX polish round 2."
    tags: [feature, ux, data]
    date: "2026-02"
    version: "v0.28.0"

  - id: onboarding-help
    title: "Onboarding & Help System"
    description: "Three-step onboarding carousel, contextual hints, per-page help text, admin info boxes, and Agumon mascot integration across empty states."
    tags: [ux, feature]
    date: "2026-02"
    version: "v0.27.0"

  - id: ui-polish
    title: "UI Polish & Responsiveness"
    description: "Filter prominence, pill toggles, responsive grids, player attendance filtering, cards view default for stores, flat map projection, and player modal rating sparkline."
    tags: [ux]
    date: "2026-02"
    version: "v0.26.0"

  - id: stores-filtering
    title: "Stores & Filtering Enhancements"
    description: "Online organizers world map, cards view for stores, community links URL filtering, admin scene filtering, country field for online stores, and unified store modal."
    tags: [feature, ux]
    date: "2026-02"
    version: "v0.25.0"

  - id: limitless-integration
    title: "Limitless TCG Integration"
    description: "Automated sync of 137 online tournaments from Limitless TCG with deck auto-classification (80+ rules), grid-based bulk entry, paste from spreadsheet, and inline player matching."
    tags: [integration, data]
    date: "2026-02"
    version: "v0.24.0"

  - id: multi-region
    title: "Multi-Region Support"
    description: "Scene hierarchy (Global → Country → State → Metro), scene selector with geolocation, localStorage persistence, pill toggle filters, clickable dashboard cards, historical format ratings, and batched queries."
    tags: [feature, scaling]
    date: "2026-02"
    version: "v0.23.1"

  - id: performance-security
    title: "Performance & Security Foundations"
    description: "SQL parameterization for all public queries, safe_query() wrapper, ratings cache tables, bindCache() on 20+ outputs, lazy-load admin modules, visibility-aware keepalive, and SEO files."
    tags: [scaling, security]
    date: "2026-02"
    version: "v0.21.1"

  - id: deep-linking
    title: "Deep Linking & Shareable URLs"
    description: "Shareable URLs for players, decks, stores, and tournaments with browser history support, Copy Link buttons, and scene URL foundation."
    tags: [feature, sharing]
    date: "2026-02"
    version: "v0.21.0"

  - id: public-submissions
    title: "Public Submissions & OCR"
    description: "Screenshot-based tournament submission with Google Cloud Vision OCR, match history uploads, deck request queue, mobile bottom tab bar, and admin/super admin two-tier access."
    tags: [feature, data]
    date: "2026-02"
    version: "v0.20.0"

  - id: content-pages
    title: "Content Pages & UI Polish"
    description: "About, FAQ, and For Organizers content pages with footer navigation, Open Graph meta tags, Google Analytics, and branding assets."
    tags: [content, ux]
    date: "2026-02"
    version: "v0.19.0"

  - id: server-extraction
    title: "Server Extraction Refactor"
    description: "Extracted server logic from monolithic app.R (3,178 → 566 lines), created modular server files with public-*/admin-* naming, reactive values cleanup, and CSS cleanup."
    tags: [scaling]
    date: "2026-02"
    version: "v0.18.0"

  - id: admin-ux
    title: "Admin UX Improvements"
    description: "Edit results from tournaments tab, required date validation, duplicate tournament flow, and modal input fixes."
    tags: [admin, ux]
    date: "2026-02"
    version: "v0.17.0"

  - id: ux-modals
    title: "UX Improvements & Modal Enhancements"
    description: "Manage Tournaments admin tab, overview click navigation, cross-modal navigation, deck/tournament modal stats, auto-refresh after admin changes, and sidebar reorder."
    tags: [ux, feature]
    date: "2026-02"
    version: "v0.16.0"

  - id: digilab-rebranding
    title: "DigiLab Rebranding"
    description: "Renamed from 'Digimon TCG Tracker' to 'DigiLab' with custom domain at digilab.cards."
    tags: [website]
    date: "2026-02"
    version: "v0.16.1"

  - id: bug-fixes-polish
    title: "Bug Fixes & Quick Polish"
    description: "Modal selection fix, Meta %/Conv % columns, Record column with colored W-L-T, Main Deck column, blue deck badge fix, and default table rows increase."
    tags: [ux, data]
    date: "2026-02"
    version: "v0.15.0"

  - id: rating-system
    title: "Rating System"
    description: "Competitive Rating (Elo-style), Achievement Score (points-based), and Store Rating (weighted blend) with full methodology documentation."
    tags: [ratings, methodology]
    date: "2026-02"
    version: "v0.14.0"

  - id: mobile-ui-polish
    title: "Mobile UI Polish"
    description: "Responsive value boxes with breakpoints, mobile filter layouts, header spacing, and bslib spacing overrides."
    tags: [mobile, ux]
    date: "2026-01"
    version: "v0.13.0"

  - id: desktop-design
    title: "Desktop Design & Digital Aesthetic"
    description: "Complete digital Digimon design language — loading screen, empty states, modal stat boxes, digital grid overlays, circuit nodes, title strip filters, and value box redesign."
    tags: [ux]
    date: "2026-01"
    version: "v0.9.0"

  - id: foundation
    title: "Foundation & Core Features"
    description: "Initial app with tournament tracking, player standings, deck meta analysis, store directory, admin CRUD, format management, card sync from DigimonCard.io API, and GitHub Pages hosting."
    tags: [feature]
    date: "2026-01"
    version: "v0.7.0"
---

# DigiLab Roadmap

**Current Version:** v1.3.0
**Last Updated:** 2026-03-04

> This file is the source of truth for the [public roadmap](https://digilab.cards/roadmap).
> A GitHub Action syncs the YAML frontmatter to the website on every push to main.

---

## In Progress

| Feature | Description | Target |
|---------|-------------|--------|
| **Mobile Public Views** | Dedicated mobile layouts for all 5 public tabs with device detection and stacked card layouts | v1.3.x |
| **PWA Enhancements** | Expanded icon sizes, dark mode tab bar, safe area insets, installability improvements | v1.3.x |

---

## Planned

### v1.4.0 — Mobile Admin & Data Entry
| Feature | Description |
|---------|-------------|
| **Mobile Upload Tabs** | Mobile-optimized Upload Results and Enter Results with touch-friendly grids |
| **Mobile Admin Tabs** | Mobile layouts for all scene admin and super admin tabs |
| **Admin Search** | Search and filtering across all admin pages |

### v1.5.0 — Tournament Data & Ingestion
| Feature | Description |
|---------|-------------|
| **Decklist Entry & Backfill** | Add decklists during result entry or backfill from Edit Tournaments |
| **Casual Event Types** | Regulation battles, casual night, experimental formats (no Elo impact) |
| **CSV Result Upload** | Import from Bandai TCG+ organizer CSV exports |
| **OCR Improvements** | Bug fixes and accuracy improvements for screenshot uploads |
| **Round-by-Round Enhancements** | Better UX, database handling, and player visibility |

### v1.6.0 — UX Polish & Store Improvements
| Feature | Description |
|---------|-------------|
| **Modal Improvements** | Rating sparklines, global vs local rank, deck history in player/store/deck modals |
| **All Scenes Store Reorg** | Group stores by scene with collapsible sections and filtering |
| **Scene Selector Redesign** | Scalable scene selection beyond a single dropdown |

### v1.7.0 — Performance & Caching
| Feature | Description |
|---------|-------------|
| **Query Optimization** | EXPLAIN ANALYZE audit, missing indexes, materialized views |
| **Caching Expansion** | Broader bindCache() coverage, batched startup queries, pool tuning |
| **Lazy Tab Loading** | Defer data fetch until tab is visited |

### v1.8.0 — Achievement Badges & Gamification
| Feature | Description |
|---------|-------------|
| **Achievement Badges** | Auto-calculated player achievements — streaks, deck mastery, scene milestones |

### v1.9.0 — Regional Admin & Multi-Region
| Feature | Description |
|---------|-------------|
| **Regional Admin Tier** | Country/state-level admin role with cross-scene management |
| **Admin Audit Log** | Track all admin changes with before/after snapshots and undo |
| **Tournament Tiers** | Local, regional, national, international classification |
| **Cross-Scene Badges** | Show scenes competed in with home scene inference |

### Future
| Feature | Description |
|---------|-------------|
| **Meta Insights App** | Standalone deep meta analysis, matchup data, tournament trends |
| **Dev Insights App** | Internal analytics for development metrics and operational monitoring |
| **Mascot & Branding** | Custom Digimon SVG commission, expanded Agumon poses |
| **Accessibility Pass** | WCAG audit — color contrast, screen readers, keyboard navigation |
| **Automated Testing & CI** | Integration tests for app loading, queries, OCR, regressions |

---

## Recently Completed

| Version | Feature | Shipped |
|---------|---------|---------|
| v1.3.0 | Mobile Views & PWA Fixes | 2026-03 |
| v1.2.0 | Rating System Redesign | 2026-03 |
| v1.2.0 | DigiLab Website | 2026-03 |
| v1.2.0 | App Moved to app.digilab.cards | 2026-03 |
| v1.1.2 | Cross-Scene Player Collision Fix | 2026-03 |
| v1.1.1 | Tournament Query Fix | 2026-02 |
| v1.1.0 | Discord Integration & Error Reporting | 2026-02 |
| v1.0.9 | Post-Launch Fixes & Polish (9 patches) | 2026-02 |
| v1.0.0 | Public Launch | 2026-02 |
| v0.29.0 | Admin Authentication | 2026-02 |
| v0.28.0 | Content Updates, Error Tracking & Admin UX | 2026-02 |
| v0.27.0 | Onboarding & Help System | 2026-02 |
| v0.26.0 | UI Polish & Responsiveness | 2026-02 |
| v0.25.0 | Stores & Filtering Enhancements | 2026-02 |
| v0.24.0 | Limitless TCG Integration | 2026-02 |
| v0.23.1 | Multi-Region Support | 2026-02 |
| v0.21.1 | Performance & Security Foundations | 2026-02 |
| v0.21.0 | Deep Linking & Shareable URLs | 2026-02 |
| v0.20.0 | Public Submissions & OCR | 2026-02 |
| v0.19.0 | Content Pages & UI Polish | 2026-02 |
| v0.18.0 | Server Extraction Refactor | 2026-02 |
| v0.17.0 | Admin UX Improvements | 2026-02 |
| v0.16.1 | DigiLab Rebranding | 2026-02 |
| v0.16.0 | UX Improvements & Modal Enhancements | 2026-02 |
| v0.15.0 | Bug Fixes & Quick Polish | 2026-02 |
| v0.14.0 | Rating System | 2026-02 |
| v0.13.0 | Mobile UI Polish | 2026-01 |
| v0.9.0 | Desktop Design & Digital Aesthetic | 2026-01 |
| v0.7.0 | Foundation & Core Features | 2026-01 |

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.

---

## Frontmatter Sync

The YAML frontmatter above is the machine-readable roadmap data. A GitHub Action in the
`digilab-web` repo (`sync-roadmap.yml`) fetches this file from `main`, extracts the YAML
between the `---` delimiters, and writes it to `src/data/roadmap.yaml` for the website.

**Sync triggers:** Weekly (Monday 9am UTC), manual dispatch, or `roadmap-updated` repository dispatch.

**To update the roadmap:** Edit the YAML frontmatter, then update the markdown sections
to match. Push to main, then trigger the sync manually from the `digilab-web` GitHub Actions
UI, or wait for the weekly sync.

**Available tags:** `ratings`, `methodology`, `new-app`, `analytics`, `feature`,
`gamification`, `mobile`, `ux`, `website`, `content`, `integration`, `community`,
`sharing`, `scaling`, `security`, `admin`, `data`

---

<!-- ============================================================
     INTERNAL PLANNING — Everything below is NOT synced to the website.
     The GitHub Action only reads the YAML frontmatter above.
     ============================================================ -->

# Internal Planning

Detailed task tracking, parking lot items, and decision points for development.
This section is internal-only and not published to the website.

---

## v1.4.0 — Mobile Admin & Data Entry

### Mobile Upload Tabs
| ID | Type | Description |
|----|------|-------------|
| MOB-UL1 | FEATURE | Mobile Upload Results — touch-friendly review grid, camera upload flow |
| MOB-UL2 | FEATURE | Mobile Enter Results — responsive grid entry for admin on mobile |

### Mobile Admin Tabs
| ID | Type | Description |
|----|------|-------------|
| MOB-AD1 | FEATURE | Mobile scene admin tabs (Edit Stores, Edit Tournaments, Edit Players) |
| MOB-AD2 | FEATURE | Mobile super admin tabs (Edit Scenes, Edit Admins, Edit Decks) |

### Admin Search
| ID | Type | Description |
|----|------|-------------|
| AS-SEARCH1 | FEATURE | Search/filter on Edit Stores, Edit Tournaments, Edit Players |
| AS-SEARCH2 | FEATURE | Search/filter on Edit Scenes, Edit Admins, Edit Decks |

---

## v1.5.0 — Tournament Data & Ingestion

### Decklist Entry & Backfill
| ID | Type | Description |
|----|------|-------------|
| DL1 | FEATURE | Add decklist URL/data during tournament result entry |
| DL2 | FEATURE | Backfill decklists from Edit Tournaments tab for past events |

### Casual Event Types
| ID | Type | Description |
|----|------|-------------|
| CE1 | FEATURE | New event types: Regulation Battle, Casual Night, Experimental Format |
| CE2 | FEATURE | Casual events excluded from Elo rating calculations |
| CE3 | UI | Visual distinction for casual events in tournament lists and modals |

### CSV Upload
| ID | Type | Description |
|----|------|-------------|
| CSV1 | FEATURE | Parse Bandai TCG+ organizer CSV export format |
| CSV2 | FEATURE | Map CSV columns to DigiLab result fields with preview |
| CSV3 | FEATURE | Player matching and deck resolution from CSV data |

### OCR Improvements
| ID | Type | Description |
|----|------|-------------|
| OCR1 | BUG | Investigate and fix known OCR upload issues |
| OCR2 | UX | Improve error messages and upload flow for failed parses |

### Round-by-Round
| ID | Type | Description |
|----|------|-------------|
| RBR1 | UX | Surface round-by-round data to players (currently hidden) |
| RBR2 | FEATURE | Improve match history upload UX and validation |
| RBR3 | SCHEMA | Review and enhance matches table for better round tracking |

---

## v1.6.0 — UX Polish & Store Improvements

### Modal Improvements
| ID | Type | Description |
|----|------|-------------|
| MOD1 | UX | Rating sparkline in player modal — trend over recent events |
| MOD2 | UX | Global vs local rank display in player modal |
| MOD3 | UX | Player modal: deck history timeline across formats |
| MOD4 | UX | Store and deck modal enhancements (TBD based on review) |

### Store Page Reorganization
| ID | Type | Description |
|----|------|-------------|
| SP1 | UX | Group stores by scene on All Scenes view with collapsible sections |
| SP2 | UX | Add filtering within store groups (by size, activity, rating) |
| SP3 | UX | Improve All Scenes map for large store counts |

### Scene Selector Redesign
| ID | Type | Description |
|----|------|-------------|
| SS1 | UX | Replace flat dropdown with grouped/searchable/hierarchical selector |
| SS2 | UX | Support for growing scene count without UX degradation |

---

## v1.7.0 — Performance & Caching

| ID | Type | Description |
|----|------|-------------|
| PERF1 | PERFORMANCE | Query audit — identify slowest queries with `EXPLAIN ANALYZE`, add missing indexes |
| PERF2 | PERFORMANCE | Materialized views for dashboard aggregations (pre-computed stats refreshed periodically) |
| PERF3 | PERFORMANCE | Expand `bindCache()` coverage — audit which outputs aren't cached yet |
| PERF4 | PERFORMANCE | Lazy tab loading — defer data fetch until tab is actually visited |
| PERF5 | PERFORMANCE | Neon connection pool tuning — review pool size limits and timeouts |
| PERF6 | PERFORMANCE | Batch initial queries — combine startup queries into fewer DB round trips |

---

## v1.8.0 — Achievement Badges & Gamification

| ID | Type | Description |
|----|------|-------------|
| F10 | FEATURE | Player achievement badges — auto-calculated, displayed in player modal |
| AB1 | FEATURE | Tournament streak badges (consecutive attendance, podium runs) |
| AB2 | FEATURE | Deck mastery badges (X wins with same archetype) |
| AB3 | FEATURE | Scene milestone badges (first event, 10th event, etc.) |
| AB4 | UI | Badge display in player modal and player cards |

---

## v1.9.0 — Regional Admin & Multi-Region

### Regional Admin Tier
| ID | Type | Description |
|----|------|-------------|
| RA1 | FEATURE | Regional Admin role — new tier between Super Admin and Scene Admin |
| RA2 | SCHEMA | Admin hierarchy — Regional Admin manages multiple scenes within their geography |
| RA3 | FEATURE | Regional Admin permissions — approve stores, onboard scene admins, view cross-scene reports |
| RA4 | UI | Regional Admin dashboard — aggregated stats across managed scenes |

### Admin Audit Log
| ID | Type | Description |
|----|------|-------------|
| AS2 | FEATURE | `admin_actions` audit log — track who changed what and when with before/after snapshots |
| AS3 | FEATURE | Undo/restore from audit log — surface recent changes with one-click revert |

### Multi-Region Extras
| ID | Type | Description |
|----|------|-------------|
| MR8 | SCHEMA | Add `tier` to tournaments table (local, regional, national, international) |
| MR9 | FEATURE | Player "home scene" inference (mode of tournament scenes played) |
| MR11 | FEATURE | Cross-scene badges in player modal ("Competed in: DFW, Houston, Austin") |

---

## Parking Lot

Items for future consideration, not scheduled:

| ID | Type | Description | Notes |
|----|------|-------------|-------|
| FD1 | IMPROVEMENT | Smart format default | Default to current format group instead of "All Formats" |
| W2 | FEATURE | Methodology pages | Simple rating overview + detailed formula breakdown |
| W3 | FEATURE | Weekly Meta Report page | Auto-generated from tournament data |
| UX5 | UX | Deck modal: matchup matrix | Win/loss vs top decks — needs match-level data |
| UX11 | UX | Player modal: head-to-head teaser | "Best record vs: PlayerX (3-0)" |
| UX12 | UX | Tournament result distribution mini-chart | Top 3 deck colors shown inline per tournament row |
| MR10 | FEATURE | Scene comparison page | DFW vs Houston side-by-side stats |
| MR12 | FEATURE | Scene health dashboard | Admin trends, retention, store activity |
| P4 | FEATURE | One Piece TCG support | Multi-game expansion |
| LI12 | FEATURE | Online store links | Discord/YouTube instead of address/map (partially done) |
| FB2 | FEATURE | Feedback admin queue | View/triage/respond to submissions in admin panel |
| DC1 | FEATURE | Discord bot for scene admin onboarding | Admin requests via Discord, Super Admin approves |
| DC4 | INTEGRATION | Link Discord users to DigiLab accounts | Enables bot-based workflows |
| INF1 | DEVEX | Sentry MCP integration | Claude Code workflow for proactive error monitoring |
| INF2 | DEVEX | Sentry error collection workflow | Process for identifying and addressing production errors |

---

## Removed / Won't Do

| Description | Reason |
|-------------|--------|
| ~~Static website at digilab.cards (WS1/WS2/SEO1)~~ | Done in v1.2.0 — Astro site at digilab.cards with blog, roadmap, landing page |
| ~~Discord OAuth / User Accounts (UA1-UA12)~~ | Current admin auth (bcrypt, role-based, scene-scoped) is sufficient for now |
| Structured data JSON-LD (SEO2) | Only useful with static site — deferred with it |
| Search Console integration (SEO3) | Low value without SEO strategy — revisit with static site |
| Embed widgets for stores (F8) | Share links in store/organizer modals already cover this |
| Discord bot for result reporting (P2) | Over-engineered — screenshot OCR + manual entry is sufficient |
| Store "Next Event" / upcoming section (UX7, UX14) | Bandai TCG Plus already covers event discovery |
| Community pulse dashboard (UX8) | Nice-to-have, not essential |
| Format callout banner (UX9) | Nice-to-have, not essential |
| Distance-based store sorting (UX13) | Scene filtering is sufficient |
| Pre-computed dashboard stats cache (MR16) | Partially done in v0.21.1 (ratings cache + bindCache). Revisit if performance degrades |
| Global search bar in header | Not needed — tabs and modals provide sufficient navigation |
| Guided tour (standalone) | Replaced by revamped onboarding modal carousel (OH1) |
| Deck modal: pilots leaderboard | Already covered by Deck Meta tab "top pilots" section |
| Expand to other Texas regions | Already supported by scenes hierarchy (multi-region implemented v0.23) |
| Limitless TCG API deep integration | Completed in v0.24 |
| Date range filtering on dashboard | Not needed — format filter is sufficient |
| Detailed player profile views | Modals already cover this |
| Detailed deck profile views | Modals already cover this |
| Event calendar page | Bandai TCG Plus already covers this |
| Store directory page | Bandai TCG Plus already covers this |
| Data export for users | Handle manually on request |
| Season/format archive view | Format filter already covers this |
| GitHub Action keepalive ping | Burns Posit Connect hours 24/7 for minimal benefit |
| Aggressive idle timeout increases | Wastes Posit Connect hours on zombie sessions |

---

## Decision Points

### Repository & Architecture Strategy

Before building out Discord integrations, satellite apps, or expanding significantly, decide on repo structure:

| Question | Option A | Option B |
|----------|----------|----------|
| Discord bot location? | Same repo (monorepo) | Separate `digilab-discord-bot` repo |
| Scene comparison / analytics tools? | Tab in main app | Standalone `digilab-analytics` app |
| Shared data access? | Direct DB connection | API layer between apps |
| Repo visibility? | Keep public (open source community) | Make private (protect business logic) |

### Platform Evaluation

Evaluate whether to begin a Next.js migration based on growth:

| Question | If Yes → Next.js | If No → Stay Shiny |
|----------|------------------|---------------------|
| Is organic search traffic a growth priority? | SSR pages are crawlable | Word-of-mouth via Discord is enough |
| Hitting Posit Connect scaling limits? | Stateless architecture scales better | Caching solved the problem |
| Want standalone API for bots/tools? | API routes are native | Manual data sharing is fine |
| Want mobile app / PWA features? | Native strengths | Basic PWA on Shiny is sufficient |
| Multiple regions need fast edge loading? | CDN + edge rendering | Single-region performance is adequate |

The React PoC on `explore/react-rewrite` branch serves as a reference for future migration decisions.

---

## References

- **Bug Documentation:** `docs/solutions/`
- **Design Documents:** `docs/plans/`
- **Development Log:** `logs/dev_log.md`
- **SVG Assets:** `docs/digimon-mascots.md` — placement tracking, future commission spec, art style guidelines
