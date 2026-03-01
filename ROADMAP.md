# DigiLab - Roadmap

This document outlines the planned features, improvements, and bug fixes for the tournament tracker.

**Current Version:** v1.1.2
**Cadence:** ~1 milestone per week

---

## Post-v1.0 / Deferred

### User Accounts (Full)

**Design:** `docs/plans/2026-02-05-user-accounts-design.md`

Upgrade from simple password auth to full user account system:

| ID | Type | Description |
|----|------|-------------|
| UA1 | FEATURE | Discord OAuth login ("Login with Discord") via `httr2` |
| UA6 | FEATURE | Admin invite links (Super Admin generates link → Scene Admin) |
| UA7 | FEATURE | Direct user promotion (Super Admin promotes existing users) |
| UA9 | SECURITY | Cookie-based session persistence (survives page refresh) |
| UA11 | SECURITY | `admin_actions` audit log table (who, what, when, before/after) |
| UA12 | SECURITY | Rate limiting on admin mutations |

### Regional Admin Tier

| ID | Type | Description |
|----|------|-------------|
| RA1 | FEATURE | Regional Admin role — new tier between Super Admin and Scene Admin for country/state-level oversight |
| RA2 | SCHEMA | Admin hierarchy — Regional Admin can manage multiple scenes within their geography |
| RA3 | FEATURE | Regional Admin permissions — approve new stores, onboard scene admins, view cross-scene reports |
| RA4 | UI | Regional Admin dashboard — aggregated stats across managed scenes |

### Admin Safety & Audit

| ID | Type | Description |
|----|------|-------------|
| AS1 | UX | Separate Add vs Edit modes on admin forms — disable fields until explicit "Edit" or "New" click to prevent accidental overwrites |
| AS2 | FEATURE | `admin_actions` audit log — track who changed what and when (scene edits, store reassignments, admin account changes) with before/after snapshots |
| AS3 | FEATURE | Undo/restore from audit log — surface recent changes with one-click revert |

### Discord Integrations

| ID | Type | Description |
|----|------|-------------|
| DC1 | FEATURE | Discord bot for scene admin onboarding — new admin requests via Discord, Super Admin approves |
| ~~DC2~~ | ~~FEATURE~~ | ~~Store submission queue — community members suggest new stores via Discord, admins approve/reject~~ (Done in v1.1.0 — in-app modals route to Discord) |
| ~~DC3~~ | ~~FEATURE~~ | ~~Discord webhook notifications — alert admins when new submissions need review~~ (Done in v1.1.0 — webhook routing for store requests, error reports, bug reports) |
| DC4 | INTEGRATION | Link Discord users to DigiLab accounts — enables bot-based workflows |

### Multi-Region Extras

| ID | Type | Description |
|----|------|-------------|
| MR8 | SCHEMA | Add `tier` to tournaments table (local, regional, national, international) |
| MR9 | FEATURE | Player "home scene" inference (mode of tournament scenes played) |
| MR11 | FEATURE | Cross-scene badges in player modal ("Competed in: DFW, Houston, Austin") |

### Mascot & Branding

| ID | Type | Description |
|----|------|-------------|
| DM6 | UI | Digivice footer watermark — subtle branding element |
| DM8 | UI | Agumon achievement unlocked — celebrating pose (needs F10) |
| DM-COMM | BRANDING | Commission custom Digimon SVG set — multi-character, multi-mood |

See `docs/digimon-mascots.md` for full spec and art style guidelines.

### Performance & Scaling

Dashboard is the current bottleneck — loads multiple charts and stats on startup.

| ID | Type | Description |
|----|------|-------------|
| PERF1 | PERFORMANCE | Query audit — identify slowest queries with `EXPLAIN ANALYZE`, add missing indexes |
| PERF2 | PERFORMANCE | Materialized views for dashboard aggregations (pre-computed stats refreshed periodically) |
| PERF3 | PERFORMANCE | Expand `bindCache()` coverage — audit which outputs aren't cached yet |
| PERF4 | PERFORMANCE | Lazy tab loading — defer data fetch until tab is actually visited |
| PERF5 | PERFORMANCE | Neon connection pool tuning — review pool size limits and timeouts |
| PERF6 | PERFORMANCE | Batch initial queries — combine startup queries into fewer DB round trips |

### Data Integrity (High Priority)

| ID | Type | Description |
|----|------|-------------|
| ~~DI1~~ | ~~BUG~~ | ~~Player name collision resolution — handle same name + different Bandai IDs across scenes (causes matching issues)~~ (Done in v1.1.2 — scene-scoped name matching) |
| ~~DI2~~ | ~~FEATURE~~ | ~~Player disambiguation UI — admin tool to review/merge/split players with conflicting identifiers~~ (Done in v1.1.2 — detection and fix scripts in `scripts/analysis/`) |
| DI3 | BUG | Rating recalc scope audit — verify ratings only update for players in the added tournament, not all players |
| DI4 | FEATURE | Chronological rating calculation — add time dimension to Elo, calculate from earliest result forward (supports backfilling) |
| DI5 | REFACTOR | Rating recalc on backfill — when older tournaments are added, recalculate affected players from that date forward |

### Infrastructure

| ID | Type | Description |
|----|------|-------------|
| MR17 | PERFORMANCE | ~~Profile with `shinyloadtest` and size Posit Connect tier~~ (Done in v1.0 — see profiling report) |
| INF1 | DEVEX | Sentry MCP integration — Claude Code workflow for proactive error monitoring, bug triage, and fix prioritization |
| INF2 | DEVEX | Sentry error collection workflow — document process for identifying, categorizing, and addressing production errors |
| ~~INF3~~ | ~~BUG~~ | ~~Sentry Discord bot not posting to #error-log — review bot permissions, channel config, alert rules~~ (Fixed in Sentry triage session, Feb 2026) |

### Feedback & Bug Reporting

| ID | Type | Description |
|----|------|-------------|
| ~~FB1~~ | ~~FEATURE~~ | ~~In-app feedback form — replace Google Form with native modal (bug report / feature request / general feedback)~~ (Done in v1.1.0 — bug report + data error modals with Discord webhook routing) |
| FB2 | FEATURE | Feedback admin queue — view/triage/respond to submissions in admin panel |
| ~~FB3~~ | ~~UX~~ | ~~Auto-attach context to bug reports — current tab, scene, browser, recent actions~~ (Done in v1.1.0 — auto-attaches current tab and scene context) |

---

## Parking Lot

Items for future consideration, not scheduled:

| ID | Type | Description | Notes |
|----|------|-------------|-------|
| MOB2 | UX | Mobile table improvements | Responsive columns, horizontal scroll UX, touch-friendly rows |
| MOB3 | UX | Mobile submit results review | Camera upload flow, form layout on small screens |
| FD1 | IMPROVEMENT | Smart format default | Default to current format group instead of "All Formats" |
| W2 | FEATURE | Methodology pages | Simple rating overview + detailed formula breakdown |
| W3 | FEATURE | Weekly Meta Report page | Auto-generated from tournament data |
| F10 | FEATURE | Player achievement badges | Auto-calculated, displayed in player modal |
| UX4 | UX | Player modal: deck history | Timeline of which decks they've played across formats |
| UX5 | UX | Deck modal: matchup matrix | Win/loss vs top decks — needs match-level data (not currently tracked) |
| UX11 | UX | Player modal: head-to-head teaser | "Best record vs: PlayerX (3-0)" |
| UX12 | UX | Tournament result distribution mini-chart | Top 3 deck colors shown inline per tournament row |
| MR10 | FEATURE | Scene comparison page | DFW vs Houston side-by-side stats |
| MR12 | FEATURE | Scene health dashboard | Admin trends, retention, store activity |
| P4 | FEATURE | One Piece TCG support | Multi-game expansion |
| P5 | FEATURE | Mobile-first data entry PWA | Consider after v1.0 platform evaluation |
| LI12 | FEATURE | Online store links | Discord/YouTube instead of address/map (partially done) |

---

## Removed / Won't Do

| Description | Reason |
|-------------|--------|
| Static website at digilab.cards (WS1/WS2/SEO1) | Deferred — community grows via Discord, not Google search. Revisit if organic traffic becomes a priority |
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

## Post-v1.0 Decision Point: Repository & Architecture Strategy

Before building out Discord integrations, satellite apps, or expanding significantly, decide on repo structure:

| Question | Option A | Option B |
|----------|----------|----------|
| Discord bot location? | Same repo (monorepo) | Separate `digilab-discord-bot` repo |
| Scene comparison / analytics tools? | Tab in main app | Standalone `digilab-analytics` app |
| Shared data access? | Direct DB connection | API layer between apps |
| Repo visibility? | Keep public (open source community) | Make private (protect business logic) |

**Considerations:**
- **Monorepo pros:** Shared types, easier deploys, single source of truth
- **Multi-repo pros:** Independent scaling, different tech stacks (Discord bot likely Node.js), cleaner separation
- **Private repo:** Protects rating algorithms, admin logic, sync scripts; lose community contributions
- **Hybrid:** Main app private, open-source specific utilities (OCR parser, deck classifier)

**Items affected by this decision:**
- DC1-DC4 (Discord Integrations)
- MR10 (Scene comparison page)
- MR12 (Scene health dashboard)
- Any future "satellite" features

---

## Post-v1.0 Decision Point: Platform Evaluation

After v1.0 launch data, evaluate whether to begin a Next.js migration based on:

| Question | If Yes → Next.js | If No → Stay Shiny |
|----------|------------------|---------------------|
| Is organic search traffic a growth priority? | SSR pages are crawlable | Word-of-mouth via Discord is enough |
| Hitting Posit Connect scaling limits? | Stateless architecture scales better | Caching solved the problem |
| Want standalone API for bots/tools? | API routes are native | Manual data sharing is fine |
| Want mobile app / PWA features? | Native strengths | Basic PWA on Shiny is sufficient |
| Multiple regions need fast edge loading? | CDN + edge rendering | Single-region performance is adequate |

The React PoC on `explore/react-rewrite` branch serves as a reference for future migration decisions.

---

## Completed

### v1.1.0 - Discord Integration & Error Reporting
- Discord webhook module (`R/discord_webhook.R`) with 3 Digimon-themed bots: Veemon (requests), Gatomon (coordination), Tentomon (bugs)
- In-app store/scene request modals replacing Google Form, routed to Discord via webhooks
- Contextual data error reporting from player/tournament/deck modals → scene coordination threads
- Bug report modal from footer + content pages → `#bug-reports` Discord Forum
- Admin scenes: Discord thread ID, country, state/region, reverse geocoding, edit confirmation dialog
- Content page overhauls: FAQ and For Organizers updated with webhook-powered error reporting
- Completed: DC2, DC3, FB1, FB3, INF3

### v1.0.4 - Dynamic Min Events
- Dynamic min events/entries filter defaults based on scene tournament count (<20: All, 20-100: 5+, >100: 10+)
- Help tooltips on min events filters explaining dynamic behavior
- FAQ entry for filter defaults
- Ko-fi link updated to digilab

### v1.0.0 - Public Launch
- Version badge: BETA → v1.0, clickable DigiLab header navigates to dashboard
- Performance: lazy admin UI (renderUI behind auth gate), bindCache on Players/Meta/Tournaments/Stores tabs
- Profiling: shinycannon load tests (1/5/10/25 users), profvis analysis, architecture docs
- Responsive grids: Top Decks and Rising Stars show 4/6/8 items by screen size
- Rising Stars expanded from top 4 to top 6 (up to 8 on large screens)
- "Report an error" Discord links in 4 modal footers
- Code review fixes: public submit server hardened (safe_query/safe_execute wrappers, transaction safety), XSS fix in scene map, next_id() helper replacing MAX+1 pattern, shared format_event_type() helper, dashboard value boxes respect filters
- PWA (PWA1): installable app with Digivice icons, offline Agumon fallback page, service worker, favicon

### v0.30.0 - Mobile & Polish
- Agumon mascot: loading spinner (DM9), disconnect overlay (DM3), 404 not-found modal (DM7)
- Digivice branding: logo/icon refresh (DM10), OG image with watermark (DM11)
- Mobile UX audit (MOB1): admin layout breakpoints, column hiding, tap targets, value box fonts, admin-results col-md fixes
- Edit tournaments grid (ADM1): shared grid module, step-transition UX, paste-from-spreadsheet, inline player matching, update/insert/delete diff save
- Enter/Submit Results parity (ADM2): migrated public submit to shared grid, member # column, selectize deck dropdown, OCR quality validation, blur player matching, summary bar format, admin validation + form reset
- Security audit: parameterized all SQL queries with user-controllable values (scene filters, search terms)

### v0.29.0 - Admin Auth & Automation
- Per-user admin accounts: `admin_users` table with bcrypt password hashing, role (super_admin / scene_admin), scene assignment
- Admin login form: username/password check, bootstrap flow for first super admin creation
- Permission-scoped admin tabs: hidden unless logged in with appropriate role
- Manage Admins UI: add/edit/deactivate admin accounts (super admin only)
- Manage Scenes UI: add/edit/delete scenes with auto-geocoding (super admin only)
- Change password form: collapsible in admin modal
- Scene scoping: scene admins locked to their assigned scene
- Design doc: `docs/plans/2026-02-22-admin-auth-design.md`
- GitHub Actions review: both `sync-limitless.yml` (weekly) and `sync-cards.yml` (monthly) confirmed working
- Limitless sync fix: NULL deck archetypes now default to UNKNOWN (archetype_id=50)
- Limitless sync filter: skip tournaments where top 3 players have no deck data (no-decklist tournaments)
- Sentry context tags: active_tab, scene, is_admin, community on all error captures
- GA4 custom events: tab_visit, modal_open, scene_change tracking

### v0.28.0 - Content Updates, Error Tracking & Admin UX
- OCR layout-aware parser: bounding box analysis replaces line-based text parsing (73% → 95% accuracy)
  - Medal icon rank inference (ranks 1-3), points validation/truncation, expanded noise filtering
  - Batch test harness with 7 ground truth folders (11 screenshots, 106 expected players)
  - Design doc: `docs/plans/2026-02-22-ocr-layout-parser-design.md`
- FAQ page rewrite: 5 categories, 22 questions covering all features through v0.27
- About page rewrite: multi-region language, Active Scenes stat, Discord link
- For Organizers page rewrite: Limitless Integration section, Community Links section, scene request flow
- Centralized external URLs into `LINKS` constant (Discord, Ko-fi, GitHub, contact form)
- Sentry error tracking integration (`sentryR`) with `safe_query()`/`safe_execute()` capture and global error handler
- Cross-page navigation sidebar sync fix (all 11 handlers)
- REV1 Admin UX audit — design doc + full implementation:
  - Expanded TX-only state dropdown to all 50 US states + DC
  - Replaced technical OCR error messages with user-friendly text
  - Added record format help text, release event callout, player matching explanation
  - Standardized info hint boxes across all 6 admin pages
  - Removed debug `message()` calls from production code
  - Added multi-color checkbox and geocoding help text
- UX polish round 2: skeleton loaders, filter-aware empty states, `notify()` smart durations, inline form validation, debounced search, value box count-up animation, modal system consolidation

### v0.27.0 - Onboarding & Help
- Revamped onboarding modal — 3-step carousel: Welcome (Agumon hero + feature list), Scene Selection (map + geolocation), Community Links (Discord, Ko-fi, For Organizers)
- Progress bar, pill-shaped dot indicators, per-step navigation (Skip/Get Started, Back/Almost Done, Back/Enter DigiLab)
- Welcome Guide icon in footer to reopen onboarding for returning users
- Contextual hints on dashboard tables ("Click a row for full results", "Click a deck for details")
- Rating/Score FAQ links in Players tab help text → navigate to FAQ methodology
- Info hint boxes on admin pages (Stores, Decks, Formats) explaining each form
- Per-page help text on all 5 public tabs (Dashboard, Players, Meta, Tournaments, Stores)
- Agumon mascot in empty states (7 call sites), About page hero (walking animation), and onboarding welcome step
- `agumon_svg()` helper and `digital_empty_state(mascot)` parameter for consistent mascot placement

### v0.26.0 - UI Polish & Responsiveness
- Filter prominence improvements across all tabs
- Pill toggle prominence on Players & Deck Meta
- Hot Deck value box auto-resize text
- Top Decks and Rising Stars responsive grid
- Player attendance chart filtered to local events
- Stores: Cards view as default, improved card styling
- Flat map projection for All/Online scenes
- Player modal rating trend sparkline
- Agumon SVG on loading screen
- Mobile table column prioritization
- Admin table row selection audit fix

### v0.25.0 - Stores & Filtering Enhancements
- Online Organizers World Map with country-level markers
- Cards View replaces "All Stores" table on Stores tab
- Community Links (`?community=store-slug` URL filtering across all tabs)
- Admin Scene Filtering (admin tables respect scene selection, super admin override)
- Country field for online stores, region-based mini maps in modals
- Unified store modal for physical and online stores

### v0.24.0 - Limitless Integration & Admin Improvements
- Limitless TCG sync script (137 tournaments, 2,124 results from 5 organizers)
- Deck auto-classification (80+ archetype rules, 95% success rate)
- Deck archetype merge tool, enhanced player merge (matches + limitless_username)
- Grid-based bulk entry for tournament results
- Paste from Spreadsheet modal, inline player matching badges
- Admin table row selection fix, dashboard initialization fix

### v0.23.1 - Multi-Region, Polish & Performance
- Scene selector with dynamic DB loading, onboarding modal, localStorage persistence
- Geolocation "Find My Scene" support
- Scene filtering across all tabs
- Dashboard split: format-specific meta + community health sections
- Dashboard layout: removed Top Players table, rearranged into Meta Diversity + Recent Tournaments row
- Player Growth chart switched from monthly to weekly granularity
- Meta Share chart uses percent stacking (always sums to 100%)
- Overview modals open in-place instead of switching tabs
- Pill toggle filters on Players and Deck Meta tabs
- Top Decks and Rising Stars clickable (open modals)
- Historical format rating snapshots (frozen Elo at era boundaries)
- Batched dashboard queries (deck_analytics + core_metrics)
- Connection auto-reconnection, clean shutdown handler
- Admin lock icon, Ko-fi to header, tab rename to "Deck Meta"
- Release events auto-assign UNKNOWN deck archetype (sealed packs)
- Mobile navbar improvements, XSS prevention

### v0.21.1 - Performance & Security Foundations
- SQL parameterization for all public queries (security)
- safe_query() wrapper for graceful error handling (resilience)
- bindCache() on dashboard outputs (performance)
- Pre-computed ratings cache tables (performance)
- Faster loading: removed delays, lazy-load admin modules
- Library audit: removed 5 unused packages from startup
- Visibility-aware keepalive, custom disconnect overlay (UX)
- SEO: robots.txt, sitemap.xml, og:image meta tags

### v0.21.0 - Deep Linking & Shareable URLs
- Shareable URLs for players, decks, stores, tournaments
- Tab navigation via URL, scene parameter foundation
- Copy Link button in all modal footers
- Browser back/forward support for modal navigation
- Schema: `slug` columns, `scenes` table with hierarchy

### v0.20.2 - Store Modal Polish & Map Improvements
- Store modal redesign: two-column layout (stats + mini map)
- Replaced Store Rating with Avg Player Rating (weighted Elo)
- Tiered bubble sizing based on avg event size

### v0.20.1 - Store Schedules & Calendar
- Store schedules schema, admin UI for schedule management
- Weekly calendar view with schedule/all stores toggle
- Store modal mini map, Mapbox geocoding

### v0.20.0 - Public Submissions & OCR
- Public "Upload Results" tab with screenshot-based submission
- Google Cloud Vision OCR, player pre-matching, image previews

### v0.19.0 - Content Pages & UI Polish
- About, FAQ, For Organizers content pages
- Footer navigation, seamless app frame
- Open Graph meta tags, favicon, GA4 tracking

### v0.18.x - Code Cleanup & Server Extraction
- Extracted server logic into modular files (82% reduction in app.R)
- Reactive value cleanup, CSS cleanup, ARCHITECTURE.md

### v0.17.0 and earlier
- Admin UX improvements, DigiLab rebranding, rating system
- Mobile UI polish, desktop design overhaul, modal stat boxes

*See CHANGELOG.md for full version history.*

---

## References

- **Bug Documentation:** `docs/solutions/`
- **Design Documents:** `docs/plans/`
- **Development Log:** `logs/dev_log.md`
- **SVG Assets:** `docs/digimon-mascots.md` — placement tracking, future commission spec, art style guidelines
- **User Feedback:** [Google Sheet](https://docs.google.com/spreadsheets/d/11ZeL7yZo7ee4rIdbGCCLvx_Om2VtvXtcj4U6WmH4bS8/edit?gid=0#gid=0)
