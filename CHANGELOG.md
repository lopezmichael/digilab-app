# Changelog

All notable changes to DigiLab will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## v1.1.0 - Database Migration (Neon PostgreSQL)

### Changed
- Migrated from DuckDB/MotherDuck to Neon PostgreSQL as the single database for all environments
- R connection layer now uses `pool` + `RPostgres` instead of `duckdb` package
- Simplified `safe_query()`/`safe_execute()` — removed retry/reconnect logic (no longer needed)
- Replaced `next_id()` MAX+1 pattern with PostgreSQL `INSERT ... RETURNING`
- Transaction blocks use `pool::localCheckout()` for proper isolation
- Python sync scripts (`sync_cards.py`, `sync_limitless.py`) rewritten for `psycopg2`
- GitHub Actions workflows use Neon env vars instead of MotherDuck token
- SQL placeholders converted from `?` to `$N` (RPostgres requirement)

### Added
- `db/schema_postgres.sql` (now `db/schema.sql`) — PostgreSQL schema with auto-increment IDs
- Foreign key constraints restored (15 relationships with CASCADE/RESTRICT/SET NULL)
- `scripts/migrate_to_neon.py` — one-time DuckDB → Neon data migration tool
- `pool` and `RPostgres` R package dependencies

### Removed
- `scripts/sync_to_motherduck.py` — no longer needed (single database)
- `scripts/sync_from_motherduck.py` — no longer needed
- `scripts/drop_fk_constraints.py` — FK constraints now work properly in Postgres
- MotherDuck connection logic (`connect_motherduck()`, `can_use_motherduck()`)
- DuckDB package dependency from production app
- `rv$db_con` reactive value — replaced by `db_pool` global

---

## [1.0.1] - 2026-02-23 - International Store Support

### Added
- **International Store Addresses**: Physical stores now support worldwide addresses
  - Full ~195 country dropdown (via `countrycode` package) with type-to-search on both physical and online store forms
  - Free-text "State / Province" field replaces hardcoded US state dropdown
  - "ZIP Code" renamed to "Postal Code" for international compatibility
  - Geocoding address string now includes country for better Mapbox accuracy
- **`R/constants.R`**: Shared constants file with `COUNTRY_CHOICES` list

### Changed
- **Online store country selector**: Upgraded from 6-item list to full country list
- **DB schema**: Removed `DEFAULT 'TX'` from `state` column (no migration needed)

### Dependencies
- Added `countrycode` 1.6.1 (ISO country names)

---

## [1.0.0] - 2026-02-23 - Public Launch

### Added
- **Enter/Submit Results Parity (ADM2)**: Migrated public Upload Results review grid to shared grid module from Enter Results
  - Member # column in shared grid (visible in both admin and public flows)
  - Searchable selectize deck dropdown replaces static select in both tabs
  - OCR quality validation with warning modal (proceed anyway / re-upload)
  - Blur-based player matching on public submit review grid
  - Entry vs review mode CSS for OCR-populated rows (subtle blue highlight)
  - Format and event type shown in both summary bars
  - Event types synced to shared `EVENT_TYPES` constant
  - Admin form validation (event type, format) and field reset after submit
- **Progressive Web App (PWA1)**: App is now installable ("Add to Home Screen") on mobile and desktop
  - Web app manifest with Digivice icons (192/512 standard + maskable) and dark theme
  - Offline-only service worker serves Agumon fallback page when network is unavailable
  - Favicon (`www/favicon.ico`) and Apple touch icon from Digivice SVG
  - `mobile-web-app-capable` meta tag for standalone mode on iOS/Android
- **Agumon Loading Spinner (DM9)**: Agumon SVG centered inside the circular loading gate animation with `gate-agumon-pulse` scale/opacity animation
- **Agumon Disconnect Overlay (DM3)**: Agumon SVG in the "Connection Lost" reconnect screen with `disconnect-agumon` bounce animation
- **Agumon 404 Not Found (DM7)**: Bad deep link URLs now show a modal with Agumon mascot, entity-specific title, and descriptive message instead of a toast notification
- **Digivice OG Image (DM11)**: New 1200x630 Open Graph image (`www/og-image.svg` / `og-image.png`) with large Digivice watermark behind DigiLab text
- **Digivice Logo Refresh (DM10)**: Updated `docs/digilab-logo.svg` and `docs/digilab-icon.svg` with Digivice icon
- **Mobile Column Hiding**: Stores table hides City, Avg Event Size, Avg Rating on mobile; admin tournaments table hides Type, Format, Rounds
- **Performance Profiling**: Load tested with shinycannon (1/5/10/25 concurrent users), profiled with profvis
- **Lazy Admin UI**: Admin views (`renderUI`) only generated when user authenticates as admin — reduces initial page weight for public visitors
- **Extended bindCache**: Added `bindCache()` to Players, Meta, Tournaments, and Stores tab outputs for cross-session caching
- **Responsive Top Decks & Rising Stars**: Dashboard grids show 4/6/8 items based on screen size (CSS nth-child breakpoints at 1600px/991px/640px)
- **Rising Stars Top 6**: Expanded from 4 to 6 players (up to 8 on large screens)
- **"Report Error" Buttons**: Styled button in player, meta, tournament, and store modal footers linking to Google Form
- **Clickable DigiLab Header**: App title navigates back to Dashboard
- **`next_id()` Helper**: Atomic ID generation replacing `SELECT MAX(id) + 1` pattern
- **`format_event_type()` Shared Helper**: Centralized event type display formatting (was duplicated 4x)
- **Browser Credential Saving**: Login, bootstrap, and change password forms wrapped in `<form>` tags with `autocomplete` attributes for browser password managers
- **iframe Permissions**: Added `clipboard-write` and `geolocation` to iframe `allow` attribute on digilab.cards

### Changed
- **Version Badge**: BETA badge replaced with "v1.0" version indicator
- **Sentry Version Tag**: Now reads from `APP_VERSION` variable instead of hardcoded string
- **Dashboard Value Boxes**: `total_stores_val` and `total_decks_val` now respect format/event type/scene filters and use `bindCache()`
- **Dashboard Filters**: `build_dashboard_filters()` and `build_community_filters()` refactored to delegate to shared `build_filters_param()`
- **OG Meta Tags**: Updated to reference `og-image.png` with dimensions, Twitter card upgraded to `summary_large_image`
- **Admin Layout Breakpoints (MOB1)**: All 8 admin and dashboard `layout_columns` calls now use `breakpoints()` for proper mobile stacking
- **Admin Results Mobile (MOB1)**: All `col-md-X` classes now include `col-12` prefix for mobile-first stacking
- **Tab Bar Tap Targets (MOB1)**: Increased mobile tab bar item padding and added `min-width: 44px` / `min-height: 44px` for WCAG compliance
- **Value Box Font Floor (MOB1)**: Bumped `.vb-label` and `.vb-subtitle` minimum font sizes at 576px breakpoint from 0.55/0.6rem to 0.65rem

### Security
- **Public Submit Server Hardened**: All 28 raw `dbGetQuery`/`dbExecute` calls migrated to `safe_query()`/`safe_execute()` wrappers
- **Transaction Safety**: Tournament and match history submissions wrapped in `BEGIN TRANSACTION`/`COMMIT`/`ROLLBACK`; write operations inside transactions use `DBI::dbExecute()` directly (not `safe_execute()`) so errors propagate and trigger clean rollback
- **OCR Sanity Check**: Prevents username numbers (e.g., "Legobuilder96") from inflating player count — caps max_rank when wildly disproportionate to parsed row count
- **Blank Row Filtering**: Public submission path now filters empty rows before database insert (matches admin path behavior)
- **ID Race Condition Fix**: Replaced `SELECT MAX(id) + 1` with `next_id()` helper in submit and admin-results servers
- **XSS Fix**: Scene map popup HTML now uses `htmltools::htmlEscape()` on user-facing names

### Fixed
- **Lazy-Loaded Admin Dropdowns**: Added `rv$current_nav` dependency to 4 observe blocks that populate dropdowns in lazy-loaded admin UI — scene assignment, store/format, merge deck, and merge player dropdowns were empty because `updateSelectInput` fired before the input existed in the DOM
- **Transaction Error Reporting**: Added Sentry reporting and logging to public submission transaction error handler
- **Agumon SVG Scope Bug**: `agumonSvg` variable was scoped inside `$(document).ready()`, causing `ReferenceError` in disconnect overlay IIFE — hoisted to outer scope
- **Agumon SVG Color/Size Swap**: `agumon_svg()` sprintf args were in wrong order (`size, size, color` instead of `color, size, size`), putting color value into height attribute
- **Tournament Modal Store Link**: Removed clickable store name (was navigating away from modal context)

### Removed
- Duplicate `www/digilab-logo.svg` (original lives in `docs/`)
- `.loading-character` CSS class and `character-jump` animation (replaced by Agumon in loading gate)
- 4 duplicated `format_event_type()` implementations (now shared from `shared-server.R`)

## [0.29.0] - 2026-02-22 - Admin Auth & Automation

### Added
- **Per-User Admin Accounts**: `admin_users` table with bcrypt password hashing, roles (super_admin / scene_admin), and scene assignment
- **Admin Login Form**: Username/password authentication with bootstrap flow for first super admin creation
- **Permission-Scoped Admin Tabs**: Hidden unless logged in with appropriate role
- **Manage Admins UI**: Add, edit, and deactivate admin accounts (super admin only)
- **Manage Scenes UI**: Add, edit, and delete scenes with auto-geocoding (super admin only)
- **Change Password Form**: Collapsible form in admin modal for changing own password
- **Scene Scoping**: Scene admins locked to their assigned scene's data
- **Sentry Context Tags**: `active_tab`, `scene`, `is_admin`, `community` on all error captures
- **GA4 Custom Events**: `tab_visit`, `modal_open`, `scene_change` tracking

### Changed
- **Admin Modal**: Simplified header, collapsible change password section
- **Edit Stores**: Moved to admin section (was super admin only)
- **Scene Locations**: Auto-geocoded from location text field

### Fixed
- **Limitless Sync NULL Decks**: NULL deck archetypes now default to UNKNOWN (archetype_id=50)
- **Limitless Sync Filter**: Skip tournaments where top 3 players have no deck data (no-decklist tournaments)
- **GitHub Actions**: Both `sync-limitless.yml` (weekly) and `sync-cards.yml` (monthly) confirmed working

### Documentation
- **Admin Auth Design Doc**: `docs/plans/2026-02-22-admin-auth-design.md`

## [0.28.0] - 2026-02-22 - Content Updates, Error Tracking & Admin UX

### Added
- **OCR Layout-Aware Parser**: Replaced line-based text parsing with bounding box coordinate analysis using Google Cloud Vision annotations (73% → 95% accuracy)
  - `parse_standings_layout()`: 12-step algorithm normalizes coordinates, clusters rows by Y-position, assigns text to columns (Ranking, Username/Member, Win Points) by X-position
  - `parse_standings()` orchestrator: tries layout parser first, validates results, falls back to text parser
  - Medal icon rank inference: detects missing ranks 1-3 (gold/silver/bronze icons unreadable by GCV) and infers from Y-position ordering
  - Points validation: caps at `rounds * 3`, truncates merged digits (GCV sometimes merges "6" + "0" from adjacent OMW% column)
  - Noise filtering: app headers, B-logo variants, copyright fragments, garbled multi-word text without member numbers
  - `gcv_detect_text()` now returns bounding box annotations alongside full text for backward compatibility
  - Ranking-aware multi-screenshot merge with GUEST dedup and rank gap padding
  - GUEST player DB lookup: recovers real member numbers by matching username against players table
- **OCR Batch Test Harness**: `batch_test_folders()` and `batch_retest_folders()` in `scripts/batch_test_ocr.R` — 7 ground truth folders (11 screenshots, 106 expected players) with per-field accuracy scoring
- **LINKS Constant**: Centralized all external URLs (Discord, Ko-fi, GitHub, contact form) into a `LINKS` list in `app.R` — all views reference `LINKS$discord`, `LINKS$kofi`, etc.
- **FAQ Page Rewrite**: 5 categories (Getting Started, Ratings & Scores, Scenes & Regions, Data & Coverage, General), 22 questions covering all features through v0.27
- **About Page Rewrite**: Removed DFW-specific language, added "Active Scenes" stat with globe icon, Discord as primary contact link, multi-region audience types (Online Competitors, Community Builders)
- **For Organizers Page Rewrite**: New Limitless Integration section (3 panels), Community Links section (3 panels), split store submission into Physical/Online/Requirements, replaced GitHub with Discord for scene requests
- **Sentry Error Tracking**: `sentryR` integration with `SENTRY_DSN` env var — captures exceptions in `safe_query()`/`safe_execute()` and global Shiny error handler, with graceful no-op when not configured
- **Admin Info Hint Boxes**: Added to Enter Results, Edit Tournaments, and Edit Players (all 6 admin pages now have consistent help text)
- **Record Format Help Text**: Inline explanation below radio buttons ("Points: Total match points... W-L-T: Individual wins, losses, and ties")
- **Release Event Callout**: Info alert in results wizard Step 2 when event type is Release Event ("deck archetypes are set to Unknown automatically")
- **Player Matching Explanation**: Text above match summary badges in Upload Results Step 2 explaining matching by member number then username
- **Multi-Color Checkbox Help**: Inline explanation ("Check for decks with 3+ colors. For dual-color decks, use Primary and Secondary color instead")
- **Skeleton Loaders**: Digital-themed skeleton loaders on all public tables and dashboard charts with shimmer animation, auto-hidden when data renders
- **`skeleton_table()` / `skeleton_chart()` Helpers**: Reusable skeleton loader generators for table and chart card bodies
- **`admin_empty_state()` Helper**: Lightweight empty state variant for admin tables with consistent digital styling
- **Filter-Aware Empty States**: Public tables (Players, Meta, Tournaments) now show "No X match your filters" with funnel icon when filters are active, vs Agumon mascot "No data" when genuinely empty
- **`notify()` Smart Durations**: Wrapper around `showNotification()` — errors stick until dismissed, warnings last 8s, success messages last 4s
- **Digital Grid on All Card Headers**: Subtle grid pattern (Tier 2, 0.025 opacity) applied to all card headers, with stronger pattern (Tier 1, 0.04 opacity) on chart/feature cards
- **Circuit Node on All Card Headers**: Small cyan accent dot on all card headers (4px Tier 2), with larger dot (5px Tier 1) on chart/feature cards
- **Modal Body Grid Texture**: Very subtle digital grid overlay (0.015 opacity) on all modal bodies
- **Inline Form Validation**: Red border + glow on invalid fields across all 14 admin form handlers with auto-clear on user interaction
- **`show_field_error()` / `clear_field_error()` / `clear_all_field_errors()` Helpers**: Inline validation helpers using shinyjs
- **Debounced Search Inputs**: 300ms debounce on all 5 search inputs (Players, Meta, Tournaments, Admin Tournaments, Admin Players)
- **Value Box Count-Up Animation**: Numeric value boxes (Tournaments, Players) animate from old to new value with cubic ease-out; deck boxes fade in on update

### Changed
- **US States Dropdown**: Edit Stores state selection expanded from TX-only to all 50 US states + DC with `selectize = FALSE`
- **OCR Error Messages**: Replaced technical messages ("Check that GOOGLE_CLOUD_VISION_API_KEY is set") with user-friendly text in both standings and match history OCR flows
- **Geocoding Help Text**: Changed "Location will be automatically geocoded from address" to "Map coordinates will be set automatically from the address"
- **Cross-Page Navigation**: All 11 sidebar navigation handlers now update sidebar selection via `sendCustomMessage("updateSidebarNav", ...)`
- **Modal System Consolidated**: All 8 static Bootstrap modals (`tags$div(class="modal fade")` + jQuery triggers) migrated to Shiny's `showModal(modalDialog())` / `removeModal()` pattern — single modal system throughout the app
- **Tournament Results Editor**: Nested edit/delete modals now use re-show pattern (Shiny only supports one modal at a time)
- **Error Notifications Persistent**: Error toasts no longer auto-dismiss — user must click X to close
- **Admin Empty States Styled**: Admin formats and players tables now use `admin_empty_state()` instead of plain text reactable rows

### Removed
- Debug `message()` calls from `admin-decks-server.R` (UPDATE/DELETE archetype logging) and verbose file processing logs from `public-submit-server.R`
- Orphaned `about_result_count` server output and `faq_to_about` navigation handler
- ~270 lines of static Bootstrap modal HTML from 6 admin view files
- All jQuery `modal('show'/'hide')` calls from server files

### Documentation
- **OCR Layout Parser Design Doc**: `docs/plans/2026-02-22-ocr-layout-parser-design.md` — brainstorming design for bounding box approach
- **OCR Layout Parser Implementation Plan**: `docs/plans/2026-02-22-ocr-layout-parser-implementation.md` — 9-task implementation plan
- **Admin UX Audit Design Doc**: `docs/plans/2026-02-22-admin-ux-audit-design.md` — prioritized findings from REV1 audit (2 blockers, 3 high, 3 medium, 3 low)

## [0.27.0] - 2026-02-20 - Onboarding & Help

### Added
- **Onboarding Carousel**: Revamped first-visit modal with 3-step flow — Welcome (Agumon hero + feature list), Scene Selection (map + geolocation), Community Links (Discord, Ko-fi, For Organizers)
- **Welcome Guide**: Question-circle icon in footer reopens onboarding modal for returning users
- **Contextual Table Hints**: "Click a row for full results" on Recent Tournaments, "Click a deck for details" on Top Decks (dashboard)
- **Rating/Score FAQ Links**: Clickable links in Players tab help text navigate to FAQ methodology sections
- **Admin Page Hints**: Info hint boxes on Edit Stores, Edit Decks, and Edit Formats pages
- **Per-Page Help Text**: Info hint boxes on all 5 public tabs (Dashboard, Players, Meta, Tournaments, Stores) explaining what each tab offers
- **Agumon Empty States**: Agumon SVG mascot replaces generic icons in 7 empty state locations across all public tabs
- **Agumon on About Page**: Walking Agumon animation in the About page hero section (right-to-left with dust, turn, walk back)
- **`agumon_svg()` Helper**: Reusable function for inline Agumon SVG with configurable size and color
- **`digital_empty_state()` Mascot Parameter**: Optional `mascot = "agumon"` parameter to show Agumon instead of bsicons

### Changed
- Onboarding modal upgraded from single-step scene picker to 3-step carousel with progress bar, pill-shaped dot indicators, and per-step navigation (Skip/Get Started, Back/Almost Done, Back/Enter DigiLab)
- Map in onboarding step 2 triggers resize event when becoming visible (prevents blank Mapbox rendering)
- App version bumped to 0.27.0

## [0.25.0] - 2026-02-20 - Stores & Filtering Enhancements

### Added
- **Online Organizers World Map**: When "Online" scene selected, Stores tab shows world map with organizer markers placed by country/region
- **Cards View**: New card-based view toggle on Stores tab (replaces "All Stores" table), consistent across all scenes
- **Community Links**: Store-specific filtering via `?community=store-slug` URL parameter
  - Filters Dashboard, Players, Meta, and Tournaments to single store's data
  - Banner shows active filter with "View All" to clear
  - "Share Community View" button in store modals
  - Players and Meta tabs auto-switch to "All" filter (from "5+") when community filter active
- **Admin Scene Filtering**: Edit Players, Tournaments, and Stores tables respect scene selection
  - Super admins have "Show all scenes" toggle to override
- **Country Field**: Online stores can specify their country for map placement
- **Region-Based Mini Maps**: Online store modals show mini map centered on country/region with green marker

### Changed
- Stores tab view toggle renamed from "All Stores" to "Cards"
- Online organizers section only shows when scene is "all" (not when viewing specific regions)
- Unified store modal for both physical and online stores (consistent experience across Schedule/Cards views)
- Online store modals use globe icon; physical stores use shop icon

### Schema
- Added `country` column to stores table (default: 'USA')

## [0.24.0] - 2026-02-20 - Limitless Integration & Admin Improvements

### Added
- **Limitless TCG Integration**: Automated sync of online tournament data from Limitless API
  - New sync script (`scripts/sync_limitless.py`) fetches tournaments, standings, pairings
  - Player resolution and deck mapping with admin review queue
  - Match pairings synced to matches table for head-to-head records
  - Auto-classification script (`scripts/classify_decklists.py`) with 80+ archetype rules
  - Initial sync: 137 online tournaments, 2,124 results from 5 organizers
- **Deck Archetype Merge Tool**: Merge duplicate archetypes in Edit Decks admin tab
  - Moves all results and limitless mappings from source to target deck
  - Deletes source archetype after merge
- Admin Enter Results: grid-based bulk entry replacing one-at-a-time flow
- Record Format toggle (Points or W-L-T) on tournament creation
- Paste from Spreadsheet modal for bulk data fill
- Inline player matching badges (matched with member #, new player)
- Auto-create new players on grid submit
- Upload results: delete row button (X) on each row in review table

### Changed
- Admin Enter Results Step 2: full-width grid replaces left-form + right-table layout
- Submit Results button replaces per-row Add Result + Mark Complete flow
- Player merge tool now transfers matches (both as player and opponent) and copies limitless_username
- Dashboard scene defaults to "all" on initial load (prevents empty state)

### Fixed
- Upload results: row count now always matches user-entered total players
- Admin table row selection mismatch: clicking a row in Edit Decks or Edit Stores now selects the correct row
- Archetype list now refreshes immediately after merging decks
- Dashboard showing 0 tournaments on initial page load (scene initialization race condition)

### Removed
- Quick-add player/deck inline forms in admin results entry (replaced by grid auto-create and deck request modal)
- Per-row edit/delete in admin results step 2 (use Edit Tournaments tab instead)

## [0.23.1] - 2026-02-18 - Multi-Region, Polish & Performance

### Added
- **Scene Selector**: Dropdown in header to filter by scene, dynamically loaded from database
- **First-Visit Onboarding Modal**: Single-step welcome flow with interactive map-based scene picker
  - "Find My Scene" geolocation, Online/Webcam and All Scenes options
- **Scene Filtering**: All data queries (dashboard, players, meta, tournaments, stores) filter by selected scene
- **localStorage Persistence**: Scene preference saved locally for return visits
- **Pill Toggle Filters**: Players tab (All/5+/10+ events, default 5+) and Deck Meta tab (All/5+/10+ entries)
- **Clickable Top Decks & Rising Stars**: Dashboard cards now open deck/player modals on click
- **Dashboard Section Split**: Format-specific meta section (top) + Community health section (bottom) with divider
- **Historical Format Ratings**: Rating snapshots frozen at format-era boundaries
  - `rating_snapshots` table stores competitive rating, achievement score, rank per format
  - Players tab shows historical ratings when a past format is selected (with visual badge)
  - Backfill support via `backfill_rating_snapshots()` in `R/ratings.R`
- **Connection Auto-Reconnection**: `safe_query()` detects stale connections and reconnects automatically
- **Clean Shutdown Handler**: `onStop()` properly disconnects database on app exit

### Changed
- **Batched Dashboard Queries**: Consolidated ~18 queries into batch reactives (`deck_analytics`, `core_metrics`)
- **Admin Button**: Simplified to lock icon only (no text)
- **Ko-fi Link**: Moved from footer to header as coffee icon button
- **Tab Rename**: "Meta Analysis" → "Deck Meta"
- **Onboarding**: Collapsed from two-step (welcome + scene picker) to single step
- **Community Queries**: Rising Stars, Player Attendance, Player Growth, and tables use scene-only filters (no format/event)
- **Dashboard Layout**: Removed redundant Top Players table; Recent Tournaments now shares row with Meta Diversity (4/8 split); Rising Stars moved below Top Decks; removed Community section divider
- **Player Growth Chart**: Switched from monthly to weekly granularity for better visibility while community is small
- **Meta Share Chart**: Uses raw counts with Highcharts percent stacking instead of pre-calculated percentages, ensuring shares always sum to 100%
- **Overview Modals**: Clicking Top Decks, Rising Stars, or Recent Tournaments on dashboard now opens modals in-place instead of switching tabs
- **Mobile Navbar**: Scene selector wraps to full-width row below title on mobile; BETA badge hidden; dark mode toggle positioned after scene selector; circuit line preserved on all screen sizes

### Security
- **XSS Prevention**: HTML-escape database-sourced deck names before rendering as raw HTML in dashboard and player tables

### Fixed
- Mobile header alignment and dark mode toggle visibility
- Onboarding feature cards no longer show non-clickable hover states (removed entirely)
- Event type filter defaulting to "Locals" instead of "All Events" on dashboard
- Missing event type display formatting for Regionals, Regulation Battle, Release Event, and Other
- Release events auto-assign UNKNOWN deck archetype (sealed packs don't have archetypes), with deck selector hidden during entry
- Mobile whitespace between navbar and content reduced

---

## [0.21.1] - 2026-02-17 - Performance & Security Foundations

### Security
- **SQL Parameterization (PF5)**: All 41 public SQL queries now use parameterized queries
  - Added `build_filters_param()` helper for safe WHERE clause construction
  - Prevents SQL injection vulnerabilities across all public server modules

### Added
- **Graceful Error Handling (PF6)**: New `safe_query()` wrapper for all 58 public database queries
  - Returns sensible defaults on database errors instead of crashing
  - Improves resilience during connection issues or invalid queries
- **Ratings Cache Tables (PF3)**: Pre-computed player and store ratings
  - New `player_ratings_cache` and `store_ratings_cache` tables
  - Cache auto-populates on startup if empty
  - Recalculates after result entry/modification
- **Visibility-Aware Keepalive (PF10)**: Connection stays alive while tab is active
  - Pauses keepalive pings when tab is hidden (saves server resources)
- **Custom Disconnect Overlay (PF11)**: Branded "Connection Lost" screen with reconnect button
- **SEO Files (PF7-9)**: Added `robots.txt`, `sitemap.xml`, and og:image meta tags

### Changed
- **Faster Loading (PF1)**: Removed artificial 800ms delay, reduced JS timeout to 200ms
- **Lazy-Load Admin Modules (PF4)**: Admin server code loads only when user logs in as admin
- **Dashboard Caching (PF2)**: Added `bindCache()` to 20+ dashboard outputs for cross-session caching

### Removed
- **Unused Libraries**: Removed 5 packages from startup (tidygeocoder, sysfonts, showtext, brand.yml, httr)
  - httr now lazy-loaded via namespacing in digimoncard_api.R
  - Estimated 1-2 second faster cold start on Posit Connect

---

## [0.21.0] - 2026-02-09 - Deep Linking & Shareable URLs

### Added
- **Shareable URLs**: Opening a modal updates the browser URL for easy sharing
  - Players: `?player=atomshell`
  - Decks: `?deck=blue-flare`
  - Stores: `?store=sci-fi-factory`
  - Tournaments: `?tournament=123`
- **Tab URLs**: Tab navigation reflected in URL (`?tab=meta`, `?tab=about`, etc.)
- **Scene Foundation**: URL supports scene parameter (`?scene=dfw`) for future multi-region
- **Copy Link Button**: All modals now have "Copy Link" button in footer
- **Browser History Support**: Back/forward buttons work with modal navigation

### Changed
- **URL Routing**: Admin pages clear URL to base (no shareable links for admin)
- **Schema**: Added `slug` column to `stores` and `deck_archetypes` tables
- **Schema**: Added `scenes` table with hierarchy (Global → Country → State → Metro)
- **Schema**: Added `scene_id` column to `stores` table

### Technical
- New `server/url-routing-server.R` for URL parsing and entity resolution
- New `www/url-routing.js` for browser history management (pushState/popstate)
- Slug-based entity resolution with fallback to slugified names

---

## [0.20.2] - 2026-02-09 - Store Modal & Map Improvements

### Added
- **Text Selection in Modals**: Can now select and copy text from all modals

### Changed
- **Store Modal Redesign**:
  - Stats list (left) + mini map (right) side-by-side layout
  - Address moved to header in standard format (street, city, state zip)
  - Website link as icon in header
  - Stats reordered: Events, Avg Event Size, Unique Players, Avg Player Rating, Last Event
- **Store Rating → Avg Player Rating**:
  - Removed confusing 0-100 "Store Rating" score
  - Replaced with weighted average player Elo (regulars count more)
  - Clearer meaning: shows competitive level of players at each store
- **Map Bubble Sizing**: Now tiered by avg event size instead of event count
  - No events: 5px (tiny dot)
  - < 8 players: 10px
  - 8-12 players: 14px
  - 13-18 players: 18px
  - 19-24 players: 22px
  - 25+ players: 26px
- **Store List Table**: Sorted by Events (not rating), renamed "Avg Size" to "Avg Event Size"

### Removed
- **Region Filter**: Removed draw-to-filter lasso functionality (will be replaced by scene selection in v0.23)
- **Store Rating from Tournament Modal**: No longer shows store rating stat

---

## [0.20.1] - 2026-02-09 - Scene Health Dashboard & Stores Tab Improvements

### Added
- **Scene Health Dashboard**: New analytics section on Overview tab
  - Meta Diversity gauge showing how evenly distributed tournament wins are (HHI-based)
  - Player Growth & Retention chart (new/returning/regular players by month)
  - Rising Stars section highlighting players with recent top finishes
  - Explanatory descriptions for user understanding
- **Store Schedules**: Stores now have structured recurring schedules
  - New `store_schedules` table for day/time/frequency data
  - Admin UI for managing store schedules in Edit Stores
  - Schedule view on Stores tab (weekly calendar sorted from today)
- **Store Modal Improvements**:
  - Mini map showing store location (Mapbox GL)
  - Regular Schedule section displaying store's weekly events
  - Removed low-value "Most Popular Deck" section

### Changed
- **Overview Tab Layout Improvements**:
  - Reorganized section order: Top Decks → Rising Stars → Scene Health → Charts → Tables
  - Split Meta Diversity and Player Growth into separate cards
  - Added icons to all section headers throughout Overview
  - Added consistent spacing between major sections
  - Renamed "Tournament Player Counts Over Time" to "Player Attendance"
- **Stores Tab View Toggle**: Switch between Schedule view and All Stores view
- **Color Distribution Chart**: Now shows decks by primary color (dual-color decks grouped by primary)
- **Orange Text Colors**: Darkened to #D97706 for better readability on light backgrounds
- **Map Styling**: Removed custom toolbar button styling, collapsed attribution by default
- **Geocoding**: Switched from OSM/Nominatim to Mapbox Geocoding API for better accuracy

### Fixed
- Highcharts axis labels, legends, and tooltips now use dark blue instead of burgundy (atomtemplates override)
- Mapbox popup text colors now use dark blue/slate instead of burgundy

---

## [0.20.0] - 2026-02-06 - Public Submissions, OCR & Mobile Navigation

### Added
- **Public Upload Results Tab**: Screenshot-based tournament submission with OCR
  - Upload Bandai TCG+ standings screenshots for automatic data extraction
  - Google Cloud Vision OCR integration (httr2 direct API calls)
  - Player pre-matching against database (by member number, then username)
  - Editable results preview with inline editing (names, points, decks)
  - Match status badges (Matched/Possible/New) with color coding
  - Processing spinner modal during OCR with status updates
  - Image thumbnail previews for uploaded screenshots (base64 encoded)
  - Pre-declared player count prevents data fabrication
  - WebP image format support alongside PNG/JPEG
  - Confirmation checkbox before final submission
- **Match History Submission**: Upload round-by-round match data
  - Tournament selector with store filter
  - Player info inputs (username, member number) for linking to existing records
  - Round count pulled from selected tournament
  - Matches table in database for round-by-round data
- **Deck Request Queue**: Public users can request new deck archetypes
  - "Request new deck..." option in deck dropdown during submission
  - Modal form for deck name, colors, and optional card ID
  - Pending requests visible in all deck dropdowns
  - Admin review section in Edit Decks tab (Approve/Edit & Approve/Reject)
  - Auto-links results to approved decks
- **Mobile Bottom Tab Bar**: Native mobile navigation replacing sidebar
  - 6-tab bottom bar: Overview, Players, Meta, Tournaments, Stores, Upload
  - Sidebar and toggle arrow completely hidden on mobile (≤768px)
  - Active state syncs between sidebar and bottom bar via JS handlers
  - Desktop sidebar unchanged
- **Admin Modal Navigation**: Admin page links in modal for mobile access
  - Tapping Admin header button shows styled card-link navigation (mobile only)
  - Desktop modal unchanged (status + logout only)
- **Admin / Super Admin Tiers**: Two-tier password system for admin access
  - Admin password: Access to Enter Results, Edit Tournaments, Edit Players, Edit Decks
  - Super Admin password: Additional access to Edit Stores and Edit Formats
  - Single login modal, role determined by which password is entered
  - Server-side `req()` guards enforce superadmin-only access on stores/formats
- **Duplicate Tournament Warning**: Alert when store/date already has a tournament
- **Admin Quick-Add Player**: Member number field added to inline player creation
- **Database Schema**: `member_number` column added to players table
- **Database Schema**: `matches` table for round-by-round match data
- **Database Schema**: `deck_requests` table for pending deck submissions
- **Database Schema**: `pending_deck_request_id` column in results table

### Changed
- **Submit → Upload Results**: Renamed sidebar link to clarify difference from admin manual entry
- **For Organizers Page**: Rewritten to reflect new self-service OCR upload flow
- **FAQ Page**: Updated data source info, update frequency, "Achv" → "Score" label
- **About Page**: Updated player/TO descriptions for self-service uploads
- **OCR Parser Improvements**:
  - Apostrophe support in usernames (e.g., "Dragoon's Ghost")
  - GUEST##### IDs ignored (not stored, not matched)
  - Combined format handling for multi-screenshot tournaments
- **Upload UI Redesign**: Combined cards with sections, compact dropzone, inline tips
- **Mobile Upload Results**: Responsive layout for review/submit page
  - Match indicator positioned next to placement badge on mobile
  - Column headers hidden (stacked layout makes them redundant)
  - Touch-friendly inputs and buttons
- **Sidebar Width**: Increased from 220px to 230px to prevent tab name wrapping

### Technical
- OCR module: `R/ocr.R` with Google Cloud Vision integration
- Server module: `server/public-submit-server.R`
- UI module: `views/submit-ui.R`
- Design document: `docs/plans/2026-02-03-public-submissions-design.md`
- Migration script: `scripts/migrate_v0.20.0.R` for schema changes
- Sync script fix: `sync_from_motherduck.py` handles schema column differences
- Cross-page navigation links (FAQ/For Organizers → Upload Results)
- Mobile bottom bar server observers with sidebar sync
- Synced `renv.lock`: added `dotenv`, `httr2`; updated `duckdb` to 1.4.4, R to 4.5.1

---

## [0.19.0] - 2026-02-04 - Content Pages & UI Polish

### Added
- **Content Pages**: Three new informational pages accessible via footer navigation
  - **About**: Live stats, coverage info, "Track. Compete. Connect." tagline
  - **FAQ**: Accordion sections with enhanced rating explanations
  - **For Organizers**: Guides for submitting results, becoming a contributor
- **Footer Navigation**: Styled bar matching header aesthetic with About/FAQ/For Organizers links
- **Hot Deck Card Image**: Value box now displays deck card image like Top Deck
- **Top Deck Icon**: Added trophy icon to Top Deck label
- **Google Form Placeholders**: Contact form links throughout content pages
- **Open Graph Meta Tags**: Link previews on Discord, Twitter, and other platforms now show proper DigiLab branding and description
- **Branding Assets**: Created SVG logo, icon, and favicon for DigiLab
- **Favicon**: Browser tab now shows DigiLab "D" icon
- **Google Analytics**: Added GA4 tracking to monitor site usage and visitor demographics

### Changed
- **Seamless App Frame**: Header, sidebar, and footer now form cohesive visual frame
  - Sidebar uses vertical gradient matching header/footer colors
  - All edges flush with viewport (no gaps)
  - Mobile-optimized spacing
- **Dashboard Spacing**: Added margin between cards and grids for better visual separation
- **Renamed "For TOs"**: Changed to "For Organizers" (clearer than acronym)

### Fixed
- **Player Search Bug**: Fixed SQL error when searching players by name in Players tab
- **Light Mode Styles**: Content pages now properly styled in both light and dark modes
- **Mobile Sidebar**: Fixed gaps between header/sidebar and sidebar/footer on mobile

---

## [0.18.1] - 2026-02-03 - Code Cleanup Refactor

### Added
- **ARCHITECTURE.md**: Comprehensive technical reference document
  - Server module structure and naming conventions
  - Complete reactive values reference (32 values across 6 categories)
  - Navigation, modal, and database patterns
  - Quick reference cheatsheet

### Changed
- **Reactive Values (R4)**: Reorganized and documented all 32 reactive values in `app.R`
  - Grouped into 6 categories: Core, Navigation, Modal State, Form/Wizard, Refresh Triggers, Delete Permission
  - All values now initialized explicitly (no ad-hoc creation in server files)
  - Renamed for consistency:
    - `selected_store_detail` → `selected_store_id`
    - `selected_online_store_detail` → `selected_online_store_id`
    - `selected_player` → `selected_player_id`
- **CSS Cleanup (R5)**: Extracted 21 inline styles from R code to named CSS classes
  - Added 12 new classes to `www/custom.css`: card search grid/items, clickable rows, help icons, image styling, action buttons, map container, filter badges
  - Updated 8 R files to use CSS classes instead of inline styles
- **CLAUDE.md**: Added required workflow documentation
  - Superpowers usage now explicitly required
  - Git workflow requirements (feature branches, regular commits, review before merge)
  - R installation path for code verification
- **PROJECT_PLAN.md**: Moved to `docs/original-project-plan.md` (historical reference)

### Technical
- Design documents:
  - `docs/plans/2026-02-03-reactive-values-cleanup-design.md`
  - `docs/plans/2026-02-03-css-cleanup-design.md`
- No functional changes - refactor only affects code organization and documentation

---

## [0.18.0] - 2026-02-03 - Server Extraction Refactor

### Changed
- **Codebase Refactor**: Extracted public page server logic from monolithic `app.R` into modular server files
  - `app.R` reduced from 3,178 to 566 lines (~82% reduction)
  - Created 5 new public server modules:
    - `server/public-dashboard-server.R` (889 lines) - Dashboard/Overview tab
    - `server/public-stores-server.R` (851 lines) - Stores tab with map
    - `server/public-players-server.R` (364 lines) - Players tab
    - `server/public-meta-server.R` (305 lines) - Meta analysis tab
    - `server/public-tournaments-server.R` (237 lines) - Tournaments tab
  - Renamed `results-server.R` → `admin-results-server.R` for naming consistency
- **Naming Convention**: Standardized server module naming
  - `public-*` prefix for public/viewer-facing tabs
  - `admin-*` prefix for admin/management tabs

### Technical
- Design document: `docs/plans/2026-02-03-server-extraction-refactor.md`
- No functional changes - refactor only affects code organization
- All existing functionality preserved and tested

---

## [0.17.0] - 2026-02-03 - Admin UX Improvements

### Added
- **Edit Results from Edit Tournaments**: New "View/Edit Results" button when a tournament is selected
  - Opens modal showing all results for the tournament
  - Click any row to edit player, deck, placement, record, and decklist URL
  - Add new results directly from the modal
  - Delete results with confirmation
- **Required Date Field**: Enter Results date field now starts blank with required validation
  - Red border and "Required" hint shown until date is selected
  - Prevents accidental submissions with wrong date (previously defaulted to today)

### Changed
- **Duplicate Tournament Flow**: After duplicating a tournament, navigates to Edit Tournaments tab with the new tournament auto-selected (previously stayed on Enter Results page)

### Fixed
- **Date Observer Error**: Fixed crash when date input is empty during initial load (proper null/length checking)
- **Reactable Column Names**: Fixed invalid column name error in modal results table (`#` → `Place` internally)
- **Modal Input Widths**: Place/Wins/Losses/Ties fields now evenly distributed using `layout_columns`
- **Decklist URL Display**: Robustly handles various null/empty representations from DuckDB (NULL, NA, "", "NA")

---

## [0.16.1] - 2026-02-02 - DigiLab Rebranding

### Changed
- **App Rebranding**: Renamed from "Digimon TCG Tracker" to "DigiLab"
- **Custom Domain**: App now hosted at https://digilab.cards/ (GitHub Pages custom domain)
- **Documentation**: Updated all references to reflect new branding and URL

---

## [0.16.0] - 2026-02-02 - UX Improvements & Modal Enhancements

### Added
- **Manage Tournaments Admin Tab (I4)**: Full edit and delete capabilities for tournaments
  - Edit tournament details (date, store, format, event type, player count, rounds)
  - Cascade delete with confirmation (removes tournament and all associated results)
  - Searchable tournament list with filters
- **Overview Click Navigation (F1)**: Clicking rows in Overview tables opens modals and switches tabs
  - Top Players → Players tab + player modal
  - Recent Tournaments → Tournaments tab + tournament modal
- **Cross-Modal Navigation (I12)**: Click links within modals to navigate between entities
  - Player modal: Click home store → store modal
  - Deck modal: Click pilot name → player modal
  - Tournament modal: Click store name → store modal
- **Deck Modal Stats (I12)**: Added Meta % and Conv % (conversion rate)
- **Tournament Modal Stats (I12)**: Added Store Rating
- **'None' Option in Admin Dropdowns (I2)**: Clear/reset selection for store and event type fields

### Changed
- **Database Auto-Refresh (I5)**: All public tables now auto-refresh after admin modifications
- **Meta Chart Color Sorting (I13)**: "Meta Share Over Time" chart series sorted by deck color for visual grouping (Red, Blue, Yellow, Green, Purple, Black, White, Multi, Other)
- **Modal Naming Consistency (I12)**: "1st Places" → "1sts" across all modals
- **Top Pilots Table (I12)**: Pilot names now clickable links to player modals
- **Sidebar Tab Order**: Public tabs reordered by engagement (Overview, Players, Meta, Tournaments, Stores); Admin tabs reordered by frequency of use
- **Admin Tab Naming**: "Manage X" renamed to "Edit X" for shorter labels
- **Recent Tournaments Table (Overview)**: Removed Type column, optimized column widths so Store names have more room

### Fixed
- **Sidebar Navigation Sync**: Sidebar now correctly highlights active tab when navigating programmatically (via Overview clicks or cross-modal links)

### Technical
- Added `updateSidebarNav` JavaScript handler for programmatic sidebar updates
- Tournament management uses cascade delete pattern (results first, then tournament)
- Cross-modal navigation uses `removeModal()` + `nav_select()` + custom message pattern

---

## [0.15.0] - 2026-02-02 - Bug Fixes & Quick Polish

### Fixed
- **Modal Selection Bug (B1)**: Clicking rows after sorting tables now opens the correct modal. Changed from row-index-based selection to JavaScript onClick callbacks that pass actual row data (archetype_id, player_id, store_id, tournament_id).

### Added
- **GitHub & Ko-fi Links (I6)**: Header now includes GitHub repo link and Ko-fi support button
- **Meta % Column**: Meta tab now shows each deck's share of total entries
- **Conv % Column**: Meta tab now shows conversion rate (Top 3s / Entries)
- **Record Column**: Players tab now shows W-L-T with colored numbers (green wins, red losses, orange ties)
- **Main Deck Column**: Players tab now shows most-played deck with color badge

### Changed
- **Blue Deck Badge (I1)**: Blue decks now display "U" instead of "B" to distinguish from Black decks
- **Default Table Rows (I3)**: Meta, Stores, Tournaments, and Players tables now default to 32 rows
- **Top Decks Count**: Overview page now shows top 6 decks (was 8) for cleaner grid layouts across screen sizes
- **Players Tab Columns (I11a)**: Reorganized to Player, Events, Rating, Score, 1sts, Top 3s, Record, Win %, Main Deck
- **Meta Tab Columns (I11b)**: Reorganized to Deck, Color, Entries, Meta %, 1sts, Top 3s, Conv %, Win % (removed Avg Place)
- **Column Renames**: "Achv" → "Score", "1st" → "1sts", "1st Places" → "1sts", "Top 3" → "Top 3s" for consistency

### Technical
- Modal selection fix affects: archetype_stats, player_standings, store_list, tournament_history tables
- All use `Shiny.setInputValue()` with `{priority: 'event'}` for reliable event handling
- Pre-computed HTML columns for Record and Main Deck to avoid pagination index issues

---

## [0.14.0] - 2026-02-01 - Rating System

### Added
- **Competitive Player Rating**: Elo-style skill rating (1200-2000+ scale) based on tournament placements and opponent strength
  - Uses "implied results" from placements (place 3rd = beat everyone below, lost to everyone above)
  - 5 iterative passes for accurate strength-of-schedule calculation
  - 4-month half-life decay keeps ratings responsive to current form
  - Round multiplier rewards performance at longer events (1.0x-1.4x)
  - Provisional period (K=48) for first 5 events, then stabilizes (K=24)
- **Achievement Score**: Points-based engagement metric
  - Placement points scaled by tournament size (1st = 50-100 pts, participation = 5-10 pts)
  - Diversity bonuses: store variety (+10/25/50), deck variety (+15), format variety (+10)
- **Store Rating**: Venue quality score (0-100 scale)
  - Weighted blend: 50% player strength + 30% attendance + 20% activity
  - Based on last 6 months of tournament data
- **New R Module**: `R/ratings.R` containing all rating calculation functions

### Changed
- **Overview > Top Players**: Now shows Elo Rating and Achievement Score (replaces old weighted rating)
- **Overview > Recent Tournaments**: Now includes Store Rating column
- **Players Tab**: Now shows Elo Rating and Achievement Score columns
- **Stores Tab**: Now shows Store Rating column, sorted by rating by default
- **Rating Tooltip**: Updated to explain new Elo-style rating and achievement score

### Technical
- Ratings calculated reactively in-app (fast enough for real-time)
- Full design methodology documented in `docs/plans/2026-02-01-rating-system-design.md`

---

## [0.13.0] - 2026-01-31 - Mobile UI Polish

### Added
- **Responsive Value Boxes**: Value boxes now use bslib `breakpoints()` for proper responsive behavior (full width on mobile, 2x2 on tablet, 4-column on desktop)
- **Mobile Filter Layouts**: Dashboard uses 2-row filter layout, other pages (Players, Meta, Tournaments) use 3-row layout with CSS `:has()` selector

### Changed
- **App Title**: Shortened to "Digimon TCG Tracker" for better mobile fit
- **Header Spacing**: Reduced whitespace between header and content on both desktop and mobile
- **BETA Badge**: Hidden on mobile to prevent overlap with admin button

### Fixed
- **bslib Spacing Override**: Target `bslib-gap-spacing` and `bslib-mb-spacing` classes to reduce excessive whitespace
- **Value Box Width**: Fixed issue where value boxes only took 50% width on certain viewport sizes
- **Reset Button Alignment**: Reset button now properly inline with last filter dropdown on mobile

### Technical
- Mobile UI phase complete - both desktop and mobile designs now polished
- CSS uses `:has()` selector to differentiate page layouts without JavaScript
- bslib `breakpoints()` in R code handles responsive grid, CSS no longer fights inline styles

---

## [0.12.0] - 2026-01-31 - Title Strip Filter Polish

### Changed
- **Native HTML Selects**: All title strip dropdowns now use native selects (`selectize = FALSE`) for consistent cross-browser styling
- **Light Input Backgrounds**: Title strip inputs use light backgrounds (`rgba(255, 255, 255, 0.9)`) with dark text for maximum readability
- **Consistent Choice Structure**: Min entries/events dropdowns now use `list()` with string values matching format dropdown pattern
- **Descriptive Labels**: Filter options now more descriptive ("Any Events", "2+ Events" instead of "Any", "2+")

### Fixed
- **Dropdown Readability**: Dropdown menus now show dark text on light backgrounds (was white-on-white, invisible)
- **Inconsistent Selectize Rendering**: Native selects render consistently across all pages
- **Search Input Styling**: Search inputs now match dropdown styling with light backgrounds

### Technical
- Desktop UI design phase complete - ready for mobile responsiveness review
- All title strip filter inputs standardized across Overview, Tournaments, Meta Analysis, and Players pages

---

## [0.11.0] - 2026-01-30 - Desktop Design Complete

### Added
- **App-Wide Loading Screen**: "Opening Digital Gate..." sequence with spinning rings, scan line animation, and themed messages
- **Digital Empty States**: Scanner-aesthetic empty states with corner accents and pulsing icons throughout the app
- **Modal Stat Boxes**: All modals (tournament, player, deck) now have digital grid overlay with corner accents
- **Modal Section Headers**: "Final Standings", "Top Pilots", "Recent Results" etc. have circuit node accent
- **Placement Colors**: 1st place gold (#D4AF37), 2nd silver (#A8A9AD), 3rd bronze (#CD7F32)
- **Online Tournament Organizers**: Digital card styling with pulsing connection nodes
- **Header Enhancements**: Cards icon (placeholder for digivice), BETA badge, circuit line accent, icon pulse animation
- **Tournament Summary Bar**: Digital styling for the Enter Results page info bar

### Changed
- **Add Result Button**: Now uses blue-to-orange hover gradient (btn-add-result class)
- **W/L/T Inputs**: Individual "Wins", "Losses", "Ties" labels instead of grouped "Record (W/L/T)"
- **Search Button (Manage Decks)**: Matches digital theme, properly aligned with input
- **Info Icon (Manage Decks)**: Moved next to "Selected Card ID" label for cleaner layout
- **Card Search Results**: Individual cards have grid overlay and corner scan accents
- **Map Card**: "Location Scanner" header with scan animation on hover

### Fixed
- **prependContent Warning**: Loading overlay now injected via JavaScript to avoid htmlwidgets conflict
- **Search Button Alignment**: Properly aligned with input box using flexbox spacer

### Technical
- Desktop design overhaul complete - ready for mobile responsiveness review
- All design changes on `feature/ui-design-overhaul` branch (not yet merged to main)

---

## [0.10.0] - 2026-01-30 - Digital Design Language Extension

### Added
- **Header Bar Enhancement**: Subtle grid pattern overlay (4% opacity), glowing circuit node in top-right corner, faint circuit line along right edge
- **Sidebar Circuit Theming**: Vertical circuit line along left edge of navigation, glowing cyan node on active nav item
- **Card Search Scanner Effect**: Digital grid overlay on card preview (scanner aesthetic), hover glow on search results, selection pulse animation
- **Page Title Strips**: Players, Meta, and Tournaments pages now use integrated title strips with filters (matching dashboard style)
- **Modal Header Theming**: Grid pattern and circuit node in modal headers, blue gradient background, styled close button
- **Feature Card Headers**: Charts/key data cards automatically get grid pattern + circuit node in header (using CSS :has() selector)

### Changed
- **Consistent Filter UI**: All pages now use title strip pattern with compact inline filters
- **Card Hover Effects**: Data cards show subtle cyan glow on hover
- **Design System**: Extended digital Digimon aesthetic from value boxes to entire app

### Technical
- Design language documented in `docs/plans/2026-01-30-design-language-extension-proposal.md`
- CSS organized with clear section headers for each component type
- Uses CSS custom properties for consistent glow colors

---

## [0.9.0] - 2026-01-30 - Digital Value Box Redesign

### Added
- **Digital Digimon Aesthetic**: Value boxes redesigned with grid pattern overlay and circuit/wireframe accents inspired by Digimon TCG card designs
- **Title Strip**: New integrated filter bar showing format context ("BT-19 Format · Locals") with compact dropdown controls
- **Hot Deck Metric**: New value box showing trending deck with biggest meta share increase (with fallback for insufficient data)
- **Meta Share Display**: Top Deck now shows percentage of meta alongside deck name
- **Color-Coded Borders**: Each value box has distinctive left border (orange, blue, red, green)

### Changed
- **Format-Filtered Stats**: Tournaments and Players counts now respect format/event type filters
- **Value Box Layout**: Custom CSS implementation replacing bslib value_box for full design control
- **Filter UI**: Replaced separate filter row with integrated title strip
- **Reset Button**: Now uses refresh icon instead of text button

### Fixed
- **Mobile Layout**: Value boxes display as 2x2 grid on mobile devices
- **Dark Mode**: Value boxes properly styled for dark theme
- **Responsive Title Strip**: Stacks controls on smaller screens

---

## [0.8.0] - 2026-01-30 - Desktop UI Polish

### Changed
- **App Rebranding**: Renamed to "Digimon Locals Meta Tracker" with egg icon in header
- **Sidebar Logo**: Added Digimon TCG logo to sidebar, removed "Menu" text
- **Value Boxes**: Smaller titles, larger numbers and icons for better visual hierarchy
- **Format Default**: Overview page now auto-selects the most recent format
- **Meta Default**: Meta Analysis now shows all decks by default (min entries = 0)

### Added
- **Player Rating Column**: Players page now displays weighted rating (win% + top 3 rate + attendance)
- **Tournament Sorting**: Tournament History auto-sorts by date descending

### Fixed
- **Filter Alignment**: Reset buttons and search inputs properly aligned on all filter bars
- **Chart Polish**: Removed redundant x-axis labels from color distribution, capped meta share y-axis at 100%
- **Value Box Overflow**: Long deck names now truncate properly in "Most Popular Deck" box

---

## [0.7.0] - 2026-01-28 - UI Refactor & Card Sync Improvements

### Added
- **GitHub Pages Hosting**: App now accessible via clean URL at `lopezmichael.github.io/digimon-tcg-standings`
- **Card Sync Improvements**: Enhanced `sync_cards.py` with new flags:
  - `--by-set`: Fetch by set/pack for comprehensive coverage (catches multi-color cards)
  - `--incremental`: Only sync new cards for faster updates
  - `--discover`: Detect new set prefixes from API
- **Cloud-to-Local Sync**: New `sync_from_motherduck.py` script to pull cloud database locally
- **GitHub Actions**: Automated monthly card sync with manual trigger options
- **Documentation**: Added `docs/card-sync.md` guide and `scripts/README.md`

### Changed
- **Server Modularization**: Split monolithic `app.R` into focused server modules:
  - `server/shared-server.R`: Database, navigation, auth helpers
  - `server/results-server.R`: Tournament entry wizard
  - `server/admin-decks-server.R`: Deck archetype CRUD
  - `server/admin-stores-server.R`: Store management
  - `server/admin-formats-server.R`: Format management
- **UI Layouts**: Standardized form layouts using `layout_columns` with consistent column widths
- **Input Width Fix**: Fixed Shiny input overflow caused by default `min-width: 300px`
- **Card Database**: Expanded from ~2,800 to 4,200+ cards with fixed ST deck format and promo packs

### Fixed
- ST-1 through ST-9 starter deck cards now sync correctly (API uses single-digit format)
- Multi-color cards no longer missed during sync (set-based fetching catches all)

---

## [0.6.0] - 2026-01-27 - Format Management

### Added
- **Format Management Admin UI**: Manage game formats/sets via admin interface
  - Add, edit, and delete formats
  - Fields: Set Code, Set Name, Display Name, Release Date, Sort Order, Active status
  - Referential integrity checks (blocks delete if tournaments use format)
  - Dynamic dropdown updates across app when formats change
- **Formats Database Table**: New `formats` table for storing set information
  - `format_id` (primary key): Set code like 'BT19', 'EX08'
  - `set_name`: Full name like 'Xros Encounter'
  - `display_name`: Combined display like 'BT19 (Xros Encounter)'
  - `release_date`: For sorting by newest
  - `sort_order`: Manual sort override
  - `is_active`: Toggle visibility in dropdowns
- **Database Migration Script**: `R/migrate_v0.6.0.R` for adding formats table and seeding data

### Changed
- Format dropdowns now load from database instead of hardcoded list
- Dashboard and tournament entry forms dynamically update when formats are modified

### Migration Required
Run `source("R/migrate_v0.6.0.R")` then `migrate_v0.6.0(con)` to add formats table and seed initial data.

---

## [0.5.0] - 2026-01-27 - Admin Pages Enhancement

### Added
- **Online Store Support**: Flag-based system for online tournament organizers
  - "Online store" checkbox in Manage Stores form
  - Conditional fields: physical stores show address, online stores show region
  - Online Tournament Organizers section on Stores page
- **Wizard-based Results Entry**: Replaced bulk paste mode with 2-step wizard
  - Step 1: Tournament Details (store, date, type, format, players, rounds)
  - Step 2: Add Results with real-time results table
  - Tournament summary bar showing current tournament info
  - Results count header (X/Y players entered)
- **Duplicate Tournament Detection**: Modal warning when creating tournament for same store/date
  - Options: View/Edit Existing, Create Anyway, or Cancel
- **Quick Add Forms**: Add new players and decks inline during result entry
  - "+ New Player" link opens inline form
  - "+ New Deck" link opens inline form with color selection
- **Delete Functionality**: Hard delete for stores and deck archetypes
  - Referential integrity checks (blocks delete if related records exist)
  - Modal confirmation dialogs
- **Multi-color Deck Support**: Checkbox for decks with 3+ colors
  - Pink "Multi" badge display in tables
- **Database Migration Script**: `R/migrate_v0.5.0.R` for schema updates

### Changed
- Manage Decks form reorganized: card preview on left, search on right
- Results entry now uses wizard flow instead of single-page form
- Removed bulk paste mode entirely (replaced by wizard)

### Fixed
- Bind parameter error: NULL values now use NA_character_ for DuckDB compatibility
- Search button alignment in card search using flexbox
- NULL/NA handling in nchar() checks throughout admin forms

### Database
- Added `is_online` column to stores table (BOOLEAN DEFAULT FALSE)
- Added `is_multi_color` column to deck_archetypes table (BOOLEAN DEFAULT FALSE)
- Updated `store_activity` view to include `is_online` column

### Migration Required
Run `source("R/migrate_v0.5.0.R")` then `migrate_v0.5.0(con)` to add new columns to existing database.

---

## [0.4.0] - 2026-01-27 - Admin Improvements & Deployment Prep

### Added
- Bulk tournament entry mode (paste multiple results at once)
- Quick-add deck feature in results entry (for missing archetypes)
- Edit functionality for stores and decks (click row to edit)
- Admin table pagination (default 20 rows, options: 10/20/50/100)
- Card search in Manage Decks with clickable image results
- shinyjs integration for dynamic UI updates

### Changed
- All admin inputs now use single-row layout (no side-by-side fields)
- Card search uses DigimonCard.io API `id` field (not `cardnumber`)
- Card images use `.webp` format for better browser support
- Search box and button alignment fixed with Bootstrap grid

### Fixed
- Card search images now display correctly (was broken due to wrong API field)
- Selected Card ID auto-fills when clicking search results

### Documentation
- Updated README with current features, tech stack, and deployment instructions
- Added MAPBOX_ACCESS_TOKEN to .env.example
- Updated package installation list to match actual dependencies

---

## [0.3.1] - 2026-01-27 - Profiles & Filters

### Added
- Player profile modal (stats, favorite decks, tournament history)
- Deck archetype profile modal (card image, top pilots, recent results)
- Tournament detail modal (full standings with deck badges)
- Search filters on Players page (by player name)
- Search filters on Meta page (by deck name)
- Filters on Tournaments page (store search, format, event type)
- Winner and Winning Deck columns in Tournaments table
- Store detail modal with recent tournaments and top players

### Changed
- Consistent two-row filter layout across all pages
- Stats in profile modals use evenly distributed flexbox
- Store modal includes winning deck name and decklist link
- Dynamic bubble sizing on store map based on tournament activity

---

## [0.3.0] - 2026-01-26 - Dashboard & Visualizations

### Added
- Most Popular Deck value box with card image
  - Replaces Stores value box
  - Shows deck thumbnail from DigimonCard.io
  - Respects all dashboard filters
- Weighted Player Rating system
  - Formula: (Win% x 0.5) + (Top 3 Rate x 30) + (Events Bonus up to 20)
  - Tooltip explains rating calculation
  - Rewards consistent performance, top finishes, and attendance
- Meta Share Over Time stacked area chart
  - Replaces Meta Breakdown table
  - Shows deck popularity trends by week
  - Decks with <5% share grouped as "Other Decks"
  - Color-coded by deck color
- Winner column in Recent Tournaments table
- 4-week rolling average line in Tournament Activity chart
- Interactive store map with MapGL integration
  - Atom-branded basemap via `atom_mapgl()` from atomtemplates
  - Uses "minimal" theme for consistent appearance in both light/dark app modes
  - Store markers with orange circles (#F7941D) and white stroke
  - Rich popups showing store details (name, city, address, schedule)
  - Light-themed popups for consistent readability
- Draw-to-filter region selection
  - Freehand polygon drawing for geographic filtering
  - Store list filters based on drawn region
  - Dashboard data (tournaments, players, meta) filters by selected stores
  - Visual filter indicator banner when region is active
  - "Clear Region" buttons on Stores and Dashboard pages
- Decklist URL field in tournament results entry form
- Auto-geocoding for stores using tidygeocoder
  - Addresses automatically geocoded when stores are added
  - Uses OpenStreetMap Nominatim API
- Dashboard visualizations with Highcharter
  - Top 4 Conversion Rate chart showing best performing decks (min. 2 entries)
  - Color Distribution bar chart counting both primary and secondary deck colors
  - Tournament Activity spline chart with weekly aggregation (dual-axis)
  - All charts respect store region filter, format filter, and dark mode
  - Uses atomtemplates `hc_theme_atom_switch()` for theming
- Comprehensive dashboard filtering system
  - Format filter: Filter by card set (BT19, EX08, BT18, etc.)
  - Event Type filter: Filter by tournament type (Locals, Evo Cup, Store Championship, etc.)
  - Date Range picker: Filter by custom date range
  - Reset Filters button: Clear all filters at once
  - All filters work together with store region filter from map
- Multi-color deck support
  - Dual-color decks (with secondary_color) shown as "Multi" in pink (#EC4899)
  - Color Distribution chart groups dual-color decks together
  - Added deck-badge-multi-color CSS class
- Top Decks display with card images
  - Shows top 8 deck archetypes with card thumbnails from DigimonCard.io
  - Horizontal progress bars color-coded by deck color
  - Responsive grid layout with dark mode support
- Format/set tracking for tournaments
  - Dropdown for selecting game format (BT19, EX08, etc.)
  - Stored in tournaments table
- Mock data seed scripts for testing
  - `R/seed_mock_data.R` - Creates 25 players, 20 tournaments, ~240 results
  - Proper format values (BT19, EX08, BT18, BT17, EX07, older)
  - Varied event types (locals, evo_cup, store_championship)
  - 4 months of date range with realistic distribution
  - `R/delete_mock_data.R` - Removes all mock data for real data collection
- Database migration script (`R/migrate_db.R`)
  - Adds decklist_url column to results table
  - Adds format column to tournaments table

### Changed
- Dashboard filter defaults now set to first format (BT19) and Locals
  - Future-proofed: always uses first item in FORMAT_CHOICES
- Top Decks section now shows win rate % instead of entry count
  - Minimum 2 entries required to appear
  - Sorted by win rate descending
- Top 3 Conversion Rate chart (changed from Top 4)
  - Shows top 5 decks for better visibility
- Tournament Activity chart now shows average players per event
  - Added 4-week rolling average trend line
  - Removed tournament count (redundant with value box)
- All Highcharts removed inline titles (titles now in card headers only)
- Recent Tournaments table improvements
  - Added Winner column (player with placement = 1)
  - Event type formatted nicely (e.g., "Evo Cup" instead of "evo_cup")
- Top Players table now sorted by weighted rating
  - Shows 1st place finishes column
  - Rating column with hover tooltip explaining formula
- Enhanced database views with additional metrics
  - `player_standings`: added favorite_deck, avg_placement
  - `archetype_meta`: added secondary_color, conversion_rate, top4_rate
  - `store_activity`: added latitude, longitude, unique_players
- Store management form no longer requires manual lat/lng entry

### Dependencies Added
- `mapgl` - Mapbox GL JS for interactive maps
- `sf` - Simple Features for spatial operations
- `tidygeocoder` - Address geocoding
- `highcharter` - Highcharts for R (interactive charts)

---

## [0.3.0] - 2026-01-26 - UI Refresh

### Added
- Views folder structure for modular UI organization
  - `views/dashboard-ui.R` - Dashboard with value boxes
  - `views/stores-ui.R` - Store directory
  - `views/players-ui.R` - Player standings
  - `views/meta-ui.R` - Meta analysis
  - `views/tournaments-ui.R` - Tournament history
  - `views/admin-results-ui.R` - Tournament entry form
  - `views/admin-decks-ui.R` - Deck archetype management
  - `views/admin-stores-ui.R` - Store management
- Digimon-themed brand configuration (`_brand.yml`)
  - Primary: Deep Digimon Blue (#0F4C81)
  - Secondary: Digimon Orange (#F7941D)
  - TCG deck colors for data visualization
  - Sequential/diverging palettes for charts
  - Typography (Poppins, Inter, Fira Code via Google Fonts)
- Custom CSS styling (`www/custom.css`)
  - Header bar with gradient and full-bleed design
  - Sidebar navigation with active state management
  - Responsive value boxes with fluid typography
  - Card styling with hover effects
  - Dark mode support with cohesive color scheme
  - Deck color badge utilities
- Sidebar + Header layout (modern dashboard pattern)
  - Full-bleed header with branding and actions
  - Collapsible sidebar navigation
  - Dark mode toggle in header
  - Admin login button in header

### Changed
- Refactored UI from shinydashboard to bslib + atomtemplates
  - `dashboardPage()` → `page_fillable()` with `layout_sidebar()`
  - Applied `atom_dashboard_theme()` for consistent theming
- Replaced all `tableOutput()` with `reactableOutput()` for better tables
- Migrated to `bslib` layout components (`layout_columns`, `card`, `value_box`)
- Value boxes use all-blue gradient theme for visual cohesion
- Added Bootstrap icons via `bsicons` package

### Dependencies Added
- `bslib` - Bootstrap theming framework
- `bsicons` - Bootstrap icons
- `reactable` - Interactive tables
- `atomtemplates` - Atom design system
- `sysfonts` - Google Fonts loading
- `showtext` - Font rendering

## [0.2.0] - 2026-01-25

### Added
- Project structure (R/, db/, logs/, data/, scripts/, tests/)
- MIT License
- Database schema for DuckDB with 6 tables + 3 views
  - Tables: `stores`, `players`, `deck_archetypes`, `archetype_cards`, `tournaments`, `results`, `ingestion_log`
  - Views: `player_standings`, `archetype_meta`, `store_activity`
- Database connection module (`R/db_connection.R`)
  - Auto-detecting `connect_db()` for local/MotherDuck environments
  - Local DuckDB for Windows development
  - MotherDuck support for Linux/Posit Connect deployment
- DigimonCard.io API integration (`R/digimoncard_api.R`)
  - Card search by name, number, color, type
  - Card image URL generation
  - Built-in rate limiting (15 req/10 sec)
- Seed data scripts
  - 13 DFW stores with addresses, coordinates, and Digimon event schedules
  - 25 deck archetypes with display cards for BT23/BT24 meta
- Logging framework
  - `CHANGELOG.md` - Version history
  - `logs/dev_log.md` - Development decisions
  - `data/archetype_changelog.md` - Archetype maintenance
- Python sync script for MotherDuck deployment (`scripts/sync_to_motherduck.py`)

### Technical Notes
- JSON columns use TEXT type (DuckDB JSON extension unavailable on Windows mingw)
- MotherDuck extension unavailable on Windows R; use local DuckDB for dev

## [0.1.0] - 2026-01-25

### Added
- Project initialization
- PROJECT_PLAN.md technical specification
