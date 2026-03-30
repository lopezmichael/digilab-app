---
currentVersion: "1.9.2"
lastUpdated: "2026-03-29"

inProgress: []

planned:

  - id: mobile-admin-tabs
    title: "Mobile Admin Tabs"
    description: "Mobile layouts for scene admin tabs (Edit Stores, Edit Tournaments, Edit Players) and super admin tabs (Edit Scenes, Edit Admins, Edit Decks)."
    tags: [mobile, admin]
    targetVersion: "v1.9.0"

  - id: postmessage-origin-fix
    title: "postMessage Origin Validation Tightening"
    description: "scene-selector.js sends postMessage with wildcard '*' origin. Tighten to 'https://app.digilab.cards'. The receiver side already validates origin, so risk is minimal — this is defense-in-depth."
    tags: [security, fix]
    targetVersion: "v1.9.0"


  # v1.10.0 — Onboarding & Dashboard Rework
  - id: onboarding-rework
    title: "Onboarding Flow Redesign"
    description: "Rework the 3-step welcome modal: Step 1 becomes scene picker (promoted from Step 2), Step 2 becomes 'Find Yourself' (player search by name or Bandai ID — personal connection), Step 3 becomes scene-at-a-glance data preview. Remove 'Join Community' from onboarding (move Discord/Ko-fi to footer). Improve skip behavior with locale detection and continent fallback. Never land on empty 'All Scenes' view."
    tags: [ux, activation, feature]
    targetVersion: "v1.9.0"

  - id: dashboard-reorder
    title: "Dashboard Reorder & Empty States"
    description: "Reorganize dashboard into three clear sections: 'Your Scene' (recent tournaments, rising stars — what happened at my locals), 'Meta Snapshot' (top decks, conversion rates, diversity — what should I play), and 'Scene Health' (attendance trends, growth — is my scene thriving). Add qualitative meta diversity labels. Add empty state handling for scenes with thin data using fallback cascade (Scene → Country → Continent → Global)."
    tags: [ux, activation, feature]
    targetVersion: "v1.10.0"

  # v2.0.0 — Astro Content Platform (digilab-web)
  # Platform shift: public read-only pages move to Astro SSR for shareability, SEO, and performance.
  # Shiny app scope narrows to admin/data-entry tools. Same Neon PostgreSQL database serves both.
  - id: astro-db-utility
    title: "Astro Database Utility Module"
    description: "Neon PostgreSQL connection module for Astro SSR pages and API routes. Connection pooling via pg package, shared query helpers, type-safe result mapping. Foundation for all Astro content pages. API routes serve JSON for Astro islands that need client-side data fetching (search, filters)."
    tags: [infrastructure, astro]
    targetVersion: "v2.0.0"

  - id: astro-tournament-pages
    title: "Tournament Pages"
    description: "SSR tournament detail pages at /tournament/[slug] — full results table, deck breakdown, store info, date/format. Highest shareability: TOs will link these immediately after events. Open Graph meta tags for rich Discord/social previews."
    tags: [astro, feature, seo]
    targetVersion: "v2.0.0"

  - id: astro-player-pages
    title: "Player Profile Pages"
    description: "SSR player profile pages at /player/[slug] — rating history chart, tournament history, deck usage breakdown, win rates, head-to-head records, scenes competed in. Astro island for interactive rating history chart (Highcharts JS). Achievement badges when available."
    tags: [astro, feature, seo]
    targetVersion: "v2.0.0"

  - id: astro-store-pages
    title: "Store Pages"
    description: "SSR store detail pages at /store/[slug] — location, schedule, upcoming/recent tournaments, regular players, store rating. TOs can use as their store's public page."
    tags: [astro, feature, seo]
    targetVersion: "v2.0.0"

  - id: astro-deck-pages
    title: "Deck Archetype Pages"
    description: "SSR deck archetype pages at /deck/[slug] — meta stats (play rate, conversion rate, avg placement), top pilots, tournament history, format trends. Foundation for deeper meta analysis in v2.1.0."
    tags: [astro, feature, seo]
    targetVersion: "v2.0.0"

  - id: astro-seo-foundation
    title: "SEO Foundation"
    description: "Dynamic Open Graph meta tags on all content pages, schema.org structured data (Event, Person, Organization), auto-generated sitemap from database, internal linking across page types, Google Search Console setup. Thousands of indexable pages from existing data."
    tags: [astro, seo, infrastructure]
    targetVersion: "v2.0.0"

  - id: shiny-modal-links
    title: "Shiny Modal → Astro Page Links"
    description: "Add 'View Full Profile' / 'Share' links to existing Shiny player, store, tournament, and deck modals that open the corresponding Astro page. Astro pages get 'Open in App' links back to Shiny for admin actions. Bridges the two platforms."
    tags: [ux, astro]
    targetVersion: "v2.0.0"

  # v2.1.0 — Meta Analysis Expansion (digilab-web)
  # Top community request (20 votes). Builds on v2.0.0 deck pages with deep analytical tools.
  - id: deck-explorer
    title: "Deck Explorer"
    description: "Comprehensive archetype analysis hub at /meta — global and scene-level meta overview with play rates, conversion rates, tier lists. Archetype detail pages expanded with card frequency analysis across decklists, sample/popular lists display, tech card tracking. Astro island for interactive filtering (format, scene, date range)."
    tags: [astro, feature, meta]
    targetVersion: "v2.1.0"

  - id: matchup-tables
    title: "Matchup Analysis"
    description: "Deck-vs-deck matchup tables built from 10.5k+ match records. Win rates with sample size indicators and confidence levels. Filterable by format, scene, date range. Transparency about data sources (mostly online Limitless data). Astro island for interactive matchup matrix (Highcharts JS heatmap)."
    tags: [astro, feature, meta]
    targetVersion: "v2.1.0"

  - id: format-trends
    title: "Format Meta Trends"
    description: "Meta share over time charts per format, deck rise/fall tracking, format health metrics (diversity index, top-heaviness). Compare meta across scenes and formats. Astro islands for interactive Highcharts time series."
    tags: [astro, feature, meta]
    targetVersion: "v2.1.0"

  - id: decklist-entry-expansion
    title: "Decklist Entry & Display Expansion"
    description: "Richer decklist display on Astro deck/tournament pages — card images from cached DigimonCard.io CDN, card grouping by type, visual deck builder integration. Text paste import for decklists. Feeds the deck explorer with more data."
    tags: [feature, data, astro]
    targetVersion: "v2.1.0"

  # v2.2.0 — Homepage Redesign & Retention (digilab-web)
  # Depends on content pages existing (v2.0.0) so homepage has real content to showcase.
  - id: homepage-redesign
    title: "Homepage Redesign"
    description: "Transform digilab.cards landing page from static marketing page to living hub with real data. Different experience for first-time vs returning visitors. Live tournament feed, trending decks, featured scenes, recent results. Circuit background animation, Agumon guide character. Reduce 55.6% bounce rate by showing value immediately."
    tags: [astro, ux, activation]
    targetVersion: "v2.2.0"

  - id: scene-pages
    title: "Scene Landing Pages"
    description: "SSR scene pages at /scene/[slug] — local leaderboard, recent tournaments, meta snapshot, active stores, community stats. Replaces Shiny Overview tab for public viewers. Astro island for leaderboard search/filter."
    tags: [astro, feature, community]
    targetVersion: "v2.2.0"

  - id: global-leaderboard
    title: "Global Leaderboard Page"
    description: "SSR leaderboard page at /players with scene/format filtering. Astro island for search-as-you-type and filter controls. Replaces Shiny Players tab for public viewers."
    tags: [astro, feature]
    targetVersion: "v2.2.0"

  # v2.3.0 — Mobile Polish & Platform Cleanup
  - id: mobile-responsive-pass
    title: "Mobile Responsive Pass"
    description: "Responsive design audit across all Astro pages — mobile-first layouts, touch targets, performance on slow connections. Astro pages should feel native on mobile at locals. PWA caching of previously visited pages for offline viewing. Review Shiny mobile views for consistency."
    tags: [mobile, ux, astro]
    targetVersion: "v2.3.0"

  - id: achievement-badges
    title: "Achievement Badges"
    description: "Auto-calculated player achievements displayed on Astro player profile pages — tournament streaks, deck mastery, scene milestones, format specialization. Gamification layer on top of existing data."
    tags: [gamification, feature, astro]
    targetVersion: "v2.3.0"

  # Infrastructure — float as needed
  - id: admin-audit-log
    title: "Admin Audit Log"
    description: "Track who changed what and when across all admin actions with before/after snapshots and optional undo."
    tags: [admin, security]
    targetVersion: "Infrastructure"

  - id: tournament-tiers
    title: "Tournament Tiers"
    description: "Add tier classification to tournaments (local, regional, national, international) for filtering and ranking context on both Shiny admin and Astro public pages."
    tags: [feature, data]
    targetVersion: "Infrastructure"

  - id: login-rate-limiting
    title: "Login Rate Limiting & Brute Force Protection"
    description: "Add per-username failed attempt tracking with exponential backoff and temporary lockout after 5 failures. Current admin login has no rate limiting — low risk given small user base and unlisted login page, but good hardening for scale."
    tags: [security, admin]
    targetVersion: "Infrastructure"

  - id: automated-testing
    title: "Automated Testing & CI"
    description: "Integration test suite for app loading, key queries, OCR parser accuracy, and regression prevention in CI."
    tags: [scaling]
    targetVersion: "Infrastructure"

  - id: accessibility-pass
    title: "Accessibility Pass"
    description: "WCAG compliance audit covering color contrast, screen reader labels, keyboard navigation, and ARIA attributes. Apply across both Shiny admin and Astro public pages."
    tags: [ux]
    targetVersion: "Infrastructure"

  - id: match-autofill
    title: "Match-by-Match Auto-Fill & Player Matching"
    description: "3-layer auto-fill for match-by-match flow: (1) match OCR opponents against tournament participants from results table, (2) pre-fill scores from other players' prior match submissions, (3) match_player() fuzzy matching with colored status indicators (green=matched, yellow=ambiguous, red=new) and interactive resolution UI."
    tags: [feature, data, ux]
    targetVersion: "v1.9.0"

  - id: round-by-round-visibility
    title: "Round-by-Round Data Visibility"
    description: "Player-facing visibility for round-by-round match data on Astro tournament pages. Show pairings, results per round, and head-to-head records."
    tags: [feature, data, astro]
    targetVersion: "v2.0.0"

  - id: cross-scene-badges
    title: "Cross-Scene Player Badges"
    description: "Show which scenes a player has competed in on their Astro profile page, with home scene inference."
    tags: [feature, community]
    targetVersion: "Infrastructure"

  - id: mascot-branding
    title: "Mascot & Branding"
    description: "Commission custom Digimon SVG set, Digivice footer watermark, and expanded Agumon poses for achievements, celebrations, and Astro homepage guide character."
    tags: [ux, content]
    targetVersion: "Future"

completed:
  # v1.9.2 — Match History Schema & Layout-Aware Parser
  - id: ocr-improvements
    title: "OCR Upload Improvements"
    description: "Layout-aware match history parser using GCV bounding boxes, match_type/source schema columns, mirror rows for local submissions, bye/default handling."
    tags: [feature, data]
    date: "2026-03"
    version: "v1.9.2"

  # v1.9.0 — Unified Submit Results
  - id: results-upload-redesign
    title: "Unified Submit Results Tab & Grid Improvements"
    description: "Consolidated public Submit and admin Enter Results into a single Submit Results tab with card-picker landing page. 6 entry methods, shared 3-step wizard, grid UX improvements (editable placement, tied placements, Add Player, W/L/T override). Subsumes grid-ux-improvements and edit-grid-record-format-switch."
    tags: [admin, ux, feature]
    date: "2026-03"
    version: "v1.9.0"

  # v1.8.0 — Datamon Bot
  - id: datamon-bot
    title: "Datamon Bot Launch"
    description: "Discord bot (discord.py) on DigitalOcean droplet. Role sync for Scene Admin/Regional Admin roles, slash commands (/admins, /roster, /scene), react-to-resolve, auto-archive stale threads, welcome DM delivery."
    tags: [integration, community, scaling]
    date: "2026-03"
    version: "v1.8.0"

  # v1.7.8 — Player Anonymization
  - id: player-anonymization
    title: "Player Anonymization Toggle"
    description: "Add is_anonymized flag to players table with toggle in Edit Players. Anonymized players show as 'Anonymous' in tournament results and are excluded from leaderboards, search, and profiles. Deck archetype data still counts toward meta stats. Reversible by admin."
    tags: [privacy, admin, feature]
    date: "2026-03"
    version: "v1.7.8"

  # v1.7.4 — Admin Permission Tier Scoping
  - id: admin-permission-tiers
    title: "Admin Permission Tier Scoping"
    description: "Regional admins can access Manage Admins (scene_admins only in their region). Suggested merges, merge modal, and scene requests scoped by tier. Server-side privilege escalation prevention. Fixed regional admin notification counts."
    tags: [admin, security]
    date: "2026-03"
    version: "v1.7.4"

  # v1.7.3 — Discord Restructure & Admin UI Design Pass
  - id: discord-restructure
    title: "Discord Restructure & App-Side Changes"
    description: "DB migration (discord_thread_id, admin_regions). Webhook refactor: per-action threads with @mentions. Thread ID capture + resolution sync. Regional admin role with country/state assignments and scene-centric tree view. Scene naming standardization (stripped prefixes, city slugs). All app-side prerequisites for Datamon bot."
    tags: [integration, admin, scaling]
    date: "2026-03"
    version: "v1.7.3"

  - id: admin-ui-design-pass
    title: "Admin UI Design Pass"
    description: "Sectioned form layouts with icons across all admin tabs + public Submit. Info-hint-box styled helper text. Global pagination styling. Admin tables aligned to public table styling. Table column cleanup (remove clutter, fix clipping, add missing columns)."
    tags: [ux, admin, style]
    date: "2026-03"
    version: "v1.7.3"

  - id: scene-slug-standardization
    title: "Scene Slug & Name Standardization"
    description: "Standardized slugs to city names (dfw → dallas-fort-worth). Stripped country prefixes from display_name (e.g., 'Brazil (São Paulo)' → 'São Paulo'). Slug redirect map for stale localStorage values."
    tags: [data, ux]
    date: "2026-03"
    version: "v1.7.3"

  - id: webhook-refactor
    title: "Webhook Refactor & Discord Restructure"
    description: "Repurposed #scene-coordination from per-scene threads to per-action-item threads with @mentions from junction table. Added discord_thread_id to admin_requests for bidirectional sync. Welcome DM automation with clipboard fallback."
    tags: [integration, admin]
    date: "2026-03"
    version: "v1.7.3"

  # v1.6.0 — Player Identity & Disambiguation
  - id: player-identity-disambiguation
    title: "Player Identity & Disambiguation"
    description: "Verification model (identity_status + home_scene_id), redesigned match_player() cascade (Bandai ID → scene-scoped name → fuzzy pg_trgm → new), disambiguation UI for ambiguous matches, fuzzy duplicate detection with 'Did you mean?' prompts, suggested Limitless→Local merges, unique member_number constraint."
    tags: [data, admin, scaling]
    date: "2026-03"
    version: "v1.6.0"

  - id: scene-filtered-store-dropdowns
    title: "Scene-Filtered Store Dropdowns & UX Fixes"
    description: "Scene filter on store dropdowns in Enter Results and Upload Results (defaults to current scene). Merge suggestion count in admin notification bar. Version modal dismiss button layout fix. Scene dropdown race condition fix in Edit Stores."
    tags: [ux, admin, fix]
    date: "2026-03"
    version: "v1.6.0"

  # v1.5.0 — Performance & Caching
  - id: safe-query-migration
    title: "Safe Query Migration & Transaction Safety"
    description: "Migrated 160 raw DB calls to safe_query/safe_execute with retry logic and Sentry reporting. Added transaction blocks for atomicity on Enter Results, Edit Tournament, and Delete Tournament. Extracted safe_query_impl to R/safe_db.R for global scope access."
    tags: [reliability, tech-debt]
    date: "2026-03"
    version: "v1.5.0"

  - id: performance-optimizations
    title: "Performance Optimizations (PERF1-6)"
    description: "Query timing instrumentation, lazy tab loading, bindCache expansion, pool tuning, batched startup queries, deferred rating recalculation via later::later(), and dashboard preload behind loading screen."
    tags: [scaling]
    date: "2026-03"
    version: "v1.5.0"

  - id: decklist-entry
    title: "Decklist Entry (Tier 1 — URL Links)"
    description: "Post-submission Step 3 across Enter Results, Upload Results, and Edit Tournaments for adding decklist URLs. Domain-allowlisted validation (7 approved deckbuilder sites), shared save component, sanitized display."
    tags: [feature, data, security]
    date: "2026-03"
    version: "v1.5.0"

  - id: materialized-views
    title: "Materialized Views (PERF2)"
    description: "5 pre-computed views replace multi-table JOINs across all public tabs. Per-store grain design with auto-refresh on admin mutations and Limitless sync."
    tags: [scaling]
    date: "2026-03"
    version: "v1.5.0"

  - id: bug-fixes-v1.5
    title: "Bug Fixes (BUG 1-4, BUG 6 + 4 new)"
    description: "Deck assignment mismatch, broken tournament deep links, points/WLT format persistence, modal stacking, decklist URL field restored, missing rating recalc on delete/public submit, welcome modal re-query, delete tournament error path."
    tags: [fix]
    date: "2026-03"
    version: "v1.5.0"

  # v1.4.0 — Admin Improvements & Request Queue
  - id: admin-request-queue
    title: "Admin Request Queue & Notification Widget"
    description: "Unified admin_requests table with notification widget, approve/reject workflow, Discord integration."
    tags: [admin, ux]
    date: "2026-03"
    version: "v1.4.0"

  - id: webhook-modal-improvements
    title: "Webhook Modal Improvements & Fuzzy Duplicate Detection"
    description: "Required Discord username, fuzzy store matching, DB persistence, request type dropdowns."
    tags: [admin, ux]
    date: "2026-03"
    version: "v1.4.0"

  - id: scene-onboarding-automation
    title: "Scene Onboarding Automation"
    description: "Auto-create Discord forum threads, preview modal, thread ID auto-save, scene announcements."
    tags: [admin, integration]
    date: "2026-03"
    version: "v1.4.0"

  - id: admin-tab-improvements
    title: "Admin Tab Improvements"
    description: "Search bars, filters, Users tab grouped by scene, required store fields, schedule qualifiers, auto-message templates."
    tags: [admin, ux]
    date: "2026-03"
    version: "v1.4.0"

  - id: iframe-storage-fix
    title: "iframe localStorage Fix & Announcement System"
    description: "postMessage bridge for mobile localStorage, announcement system, version changelog modal."
    tags: [ux, fix]
    date: "2026-03"
    version: "v1.4.0"

  - id: audit-columns
    title: "Audit Columns (updated_at/updated_by)"
    description: "Audit columns on tournaments, stores, players, deck_archetypes, and scenes tables."
    tags: [admin, data]
    date: "2026-03"
    version: "v1.4.0"

  - id: pending-requests-on-tabs
    title: "Data Error Cards on Tournaments Tab"
    description: "Pending request cards surfaced directly on admin tabs for quick resolution."
    tags: [admin, ux]
    date: "2026-03"
    version: "v1.4.0"

  # v1.3.2
  - id: rating-recalc-warning
    title: "Rating Recalculation Failure Warning"
    description: "Admin warning toast when post-submission rating recalculation fails silently. Covers all 4 recalculation call sites."
    tags: [fix, admin]
    date: "2026-03"
    version: "v1.3.2"

  # v1.3.1
  - id: casual-event-types
    title: "Casual Event Types"
    description: "New Casuals event type plus unrated event exclusions (casuals, regulation battles, release events, other) from competitive rating. Achievement scores still include all events."
    tags: [feature, ratings]
    date: "2026-03"
    version: "v1.3.1"

  - id: csv-upload
    title: "CSV Result Upload"
    description: "Upload Results tab accepts Bandai TCG+ CSV exports with validation (file size, columns, data ranges). CSV promoted as recommended upload method."
    tags: [feature, data]
    date: "2026-03"
    version: "v1.3.1"

  - id: store-page-reorg
    title: "All Scenes Store Reorganization"
    description: "All Scenes view shows scene summary cards instead of individual stores. Clicking navigates into the scene. Applied to desktop cards, schedule views, and mobile."
    tags: [ux, feature]
    date: "2026-03"
    version: "v1.3.1"


  # v1.3.0
  - id: mobile-player-cards
    title: "Mobile Player Card Redesign"
    description: "Styled player cards with tier-colored rating badges, top-3 left borders, color-coded W-L-T records, full-opacity deck badges, and stronger card borders."
    tags: [mobile, ux]
    date: "2026-03"
    version: "v1.3.0"

  - id: three-dot-modal
    title: "Three-Dot Menu → Modal"
    description: "Converted header three-dot dropdown to a styled modal matching admin login pattern. Moved Upload Results from mobile tab bar into the modal (mobile only), reducing tabs from 6 to 5."
    tags: [ux, mobile]
    date: "2026-03"
    version: "v1.3.0"

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

**Current Version:** v1.6.0
**Last Updated:** 2026-03-12

> This file is the source of truth for the [public roadmap](https://digilab.cards/roadmap).
> A GitHub Action syncs the YAML frontmatter to the website on every push to main.

---

## In Progress

No features currently in progress.

---

## Planned

### v1.7.0 — Filter Redesign & Scene Restructure
| Feature | Description |
|---------|-------------|
| **Cascading Scene Selector** | Two-level continent + scene navbar selector with FA earth-* icons and country optgroups |
| **Advanced Filters** | Expandable filter accordion on all tabs — store, win %, date range, size, color, top 3, has decklist |
| **Ranked/Unranked Pill** | Replace All/5+/10+ with Ranked/Unranked, always default to Unranked |
| **Admin-Scene Junction Table** | Many-to-many admin-scene assignments, regional_admin role with child scene inheritance |
| **Scene Slug Standardization** | Standardize slugs to city names, update display_name before go-live |
| **Discord UI Cleanup** | Remove per-scene thread UI, deprecate discord_thread_id on scenes |

### v1.8.0 — Discord Restructure & Datamon Bot
| Feature | Description |
|---------|-------------|
| **Datamon Bot Launch** | Discord bot on DigitalOcean — role sync, slash commands, react-to-resolve, auto-archive |
| **Webhook Refactor** | Per-action-item threads in #scene-coordination with @mentions from junction table |
| **Automated Welcome DM** | Bot-sent credentials to new scene admins, eliminating manual DM + captcha friction |

### v1.9.0 — Results Redesign & Data Entry
| Feature | Description |
|---------|-------------|
| **Unified Upload Tab & Results Redesign** | Single Upload tab with 4 entry-point cards (Screenshot OCR, Bandai Export, Manual, Match-by-Match). Public/admin gating per method. |
| **Grid UX Improvements** | Add Player button, drag-to-reorder, tied placements, editable placement column |
| **Mobile Admin Tabs** | Mobile layouts for all scene admin and super admin tabs |
| **postMessage Origin Fix** | Tighten wildcard origin to app.digilab.cards (defense-in-depth) |

### v1.10.0 — Tournament Data & Ingestion
| Feature | Description |
|---------|-------------|
| **Decklist Entry Expansion** | Tier 2: Deck builder integration, text paste import, richer decklist display |
| **OCR Improvements** | Bug fixes and accuracy improvements for screenshot uploads |
| **Round-by-Round Enhancements** | Better UX, database handling, and player visibility |

### v1.11.0 — UX Polish & Modals
| Feature | Description |
|---------|-------------|
| **Modal Improvements** | Rating sparklines, global vs local rank, deck history in player/store/deck modals |
| **Accessibility Pass** | WCAG audit — color contrast, screen readers, keyboard navigation |

### v1.12.0 — Achievement Badges & Gamification
| Feature | Description |
|---------|-------------|
| **Achievement Badges** | Auto-calculated player achievements — streaks, deck mastery, scene milestones |

### v1.13.0 — Admin Infrastructure & Multi-Region
| Feature | Description |
|---------|-------------|
| **Admin Audit Log** | Track all admin changes with before/after snapshots and undo |
| **Tournament Tiers** | Local, regional, national, international classification |
| **Cross-Scene Badges** | Show scenes competed in with home scene inference |
| **Login Rate Limiting** | Per-username failed attempt tracking with exponential backoff and lockout |
| **Automated Testing & CI** | Integration tests for app loading, queries, OCR, regressions |

### Future
| Feature | Description |
|---------|-------------|
| **Mascot & Branding** | Custom Digimon SVG commission, expanded Agumon poses |

---

## Recently Completed

| Version | Feature | Shipped |
|---------|---------|---------|
| v1.6.0 | Player Identity & Disambiguation | 2026-03 |
| v1.6.0 | Scene-Filtered Store Dropdowns & UX Fixes | 2026-03 |
| v1.5.0 | Safe Query Migration & Transaction Safety | 2026-03 |
| v1.5.0 | Performance Optimizations (PERF1-6) | 2026-03 |
| v1.5.0 | Decklist Entry (URL Links) | 2026-03 |
| v1.5.0 | Materialized Views | 2026-03 |
| v1.5.0 | Bug Fixes (BUG 1-4, 6 + 4 new) | 2026-03 |
| v1.4.0 | Admin Infrastructure & Request Queue | 2026-03 |
| v1.3.2 | Sentry Error Fixes | 2026-03 |
| v1.3.1 | Fixes & Upload Improvements | 2026-03 |
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

## v1.4.0 — Admin Improvements & Request Queue

Design doc: `docs/plans/2026-03-06-v1.4-admin-improvements-design.md`

### Infrastructure
| ID | Type | Description |
|----|------|-------------|
| INF-PM1 | FIX | postMessage iframe storage bridge — fix mobile localStorage bug in PWA iframe |
| INF-AR1 | SCHEMA | `admin_requests` table — unified request queue for store/scene/data error/bug report submissions |
| INF-AN1 | SCHEMA | `announcements` table — admin-managed announcements for all users |
| INF-AU1 | SCHEMA | Audit columns — `updated_at`/`updated_by` on tournaments, stores, players, deck_archetypes, scenes |

### Notification Widget
| ID | Type | Description |
|----|------|-------------|
| NW1 | FEATURE | Admin notification bar — pending request counts, clickable navigation to relevant tabs |
| NW2 | FEATURE | Scene-aware filtering — scene admins see their scene, super admins see all |
| NW3 | FEATURE | Background refresh via reactiveTimer + manual invalidation |

### Webhook Modals & Request Queue
| ID | Type | Description |
|----|------|-------------|
| WM1 | UX | Required Discord username on all modals |
| WM2 | FEATURE | Store request: fuzzy name matching, request type dropdown, suggested stores for new scenes |
| WM3 | FEATURE | DB persistence — all submissions saved to admin_requests + Discord webhook |
| WM4 | FEATURE | Admin resolution flow — approve/reject with Discord auto-post for scene-relevant actions |

### Scene Onboarding Automation
| ID | Type | Description |
|----|------|-------------|
| SO1 | FEATURE | Scene request cards on Scenes tab — "Create Scene + Stores" / "Just Create Scene" / "Reject" |
| SO2 | FEATURE | Auto-create #scene-coordination forum thread via Discord webhook API (thread_name param) |
| SO3 | UX | Preview modal — editable welcome message before posting to Discord |
| SO4 | FEATURE | Auto-save discord_thread_id from webhook response — no manual thread ID entry |
| SO5 | FEATURE | Auto-post short announcement to #scene-updates channel |
| SO6 | FEATURE | Auto-post request details to #scene-requests forum on submission |

### Admin Tab Improvements
| ID | Type | Description |
|----|------|-------------|
| AT1 | UX | Tournaments tab: filter bar (scene, store, type, date range), 0-results warning |
| AT2 | UX | Decks tab (super admin): prominent request cards, searchable table, color filter chips, result count on edit |
| AT3 | UX | Stores tab: request cards, searchable table, scene filter, required street/city, geocode status indicator |
| AT4 | UX | Stores tab: schedule frequency qualifiers — biweekly next-occurrence date, monthly week-of-month dropdown |
| AT5 | UX | Players tab: rating + scene columns, scene filter, merge history display |
| AT6 | UX | Formats tab: searchable table |
| AT7 | UX | Scenes tab: announcements sub-section, store + admin count columns |
| AT8 | UX | Users tab: grouped-by-scene collapsible view, "No Admin Assigned" section |

### Auto-Message Templates
| ID | Type | Description |
|----|------|-------------|
| AM1 | FEATURE | Scene admin welcome DM — credentials, first steps, resource links, Discord thread link |
| AM2 | FEATURE | New scene Discord welcome message — detailed onboarding posted to #scene-coordination thread |
| AM3 | FEATURE | Copy-to-clipboard buttons via navigator.clipboard.writeText() |

### User-Facing Modals
| ID | Type | Description |
|----|------|-------------|
| UM1 | FIX | Welcome modal localStorage fix via postMessage bridge |
| UM2 | FEATURE | Announcement modal — show latest unseen announcement to returning visitors |
| UM3 | FEATURE | Version changelog modal — show what's new after app updates |
| UM4 | FEATURE | Modal priority: Welcome > Announcement > Version (one per page load) |

---

## v1.5.0 — Performance & Caching (COMPLETE)

| ID | Type | Status | Description |
|----|------|--------|-------------|
| PERF1 | PERFORMANCE | **DONE** | Query timing instrumentation — slow query logging >200ms |
| PERF2 | PERFORMANCE | **DONE** | Materialized views — 5 MVs replace all public tab JOINs, per-store grain, auto-refresh |
| PERF3 | PERFORMANCE | **DONE** | bindCache() expansion — 29 cached outputs across 6 files |
| PERF4 | PERFORMANCE | **DONE** | Lazy tab loading — `visited_tabs` reactive defers data fetch until tab visited |
| PERF5 | PERFORMANCE | **DONE** | Pool tuning — Neon connection pool size and timeout settings |
| PERF6 | PERFORMANCE | **DONE** | Batched startup queries — single query for ratings + admin count |
| SQM | RELIABILITY | **DONE** | Safe query migration — 160 raw DB calls → safe_query/safe_execute |
| TXN | RELIABILITY | **DONE** | Transaction blocks — Enter Results, Edit Tournament, Delete Tournament |
| DEFER | PERFORMANCE | **DONE** | Deferred rating recalc — `later::later()` on all 6 call sites |
| PRELOAD | PERFORMANCE | **DONE** | Dashboard preload — renders behind loading screen |

---

## v1.6.0 — Player Identity & Disambiguation (COMPLETE)

### Player Identity & Disambiguation

Design doc: `docs/plans/2026-03-09-player-identity-disambiguation-design.md`

| ID | Type | Status | Description |
|----|------|--------|-------------|
| PID1 | SCHEMA | **DONE** | `identity_status` + `home_scene_id` columns, unique `member_number` constraint, backfill migration |
| PID2 | FEATURE | **DONE** | Redesigned `match_player()` — scene-locked unverified, global verified, ambiguous status for multiple matches |
| PID3 | FEATURE | **DONE** | Player creation with verification — GUEST ID stripping, auto-set identity_status + home_scene_id |
| PID4 | UX | **DONE** | Disambiguation UI in admin grid — yellow warning for ambiguous matches, picker modal with player details |
| PID5 | UX | **DONE** | Fuzzy duplicate detection on new player creation using pg_trgm — "Did you mean?" prompt |
| PID5b | UX | **DONE** | Suggested Limitless→Local merges — card-based merge candidates in Players tab with Merge/Dismiss |
| PID6 | UX | | Unverified player report for scene admins — table with "Add Bandai ID" action to promote players |

### Scene-Filtered Store Dropdowns & UX Fixes

| ID | Type | Status | Description |
|----|------|--------|-------------|
| SF1 | UX | **DONE** | Scene dropdown on Enter Results and Upload Results filters store list, defaults to current scene |
| SF2 | UX | **DONE** | Merge suggestion count in admin notification bar with click-to-navigate |
| SF3 | FIX | **DONE** | Version modal dismiss button layout — always below social buttons, centered |
| SF4 | FIX | **DONE** | Scene dropdown race condition in Edit Stores — fetch choices + selected together |

---

## v1.7.0 — Filter Redesign & Scene Restructure

Design doc: `datamon-bot/DESIGN.md` (sections 3.3–3.5, 4.1–4.6)

### Cascading Scene Selector
| ID | Type | Description |
|----|------|-------------|
| CS1 | UX | Continent dropdown in navbar with FA `earth-*` icons + 3-letter codes (`globe` for All, `wifi` for Online) |
| CS2 | UX | Scene dropdown with country optgroups and "All of Country" entries |
| CS3 | SCHEMA | Add `continent` column to scenes table, populate from lat/lng |
| CS4 | DATA | Standardize scene slugs to city names (e.g., `dfw` → `dallas-fort-worth`) |
| CS5 | DATA | Update scene `display_name` to remove country prefix (right before go-live only) |

### Advanced Filters
| ID | Type | Description |
|----|------|-------------|
| AF1 | UX | "Advanced Filters" accordion toggle on all tab title strips |
| AF2 | UX | Players: store filter, win % dropdown (`Any`, `50%+`, `60%+`, `70%+`) |
| AF3 | UX | Tournaments: store filter, date range, size dropdown (`Any`, `8+`, `16+`, `32+`, `64+`, `128+`) |
| AF4 | UX | Meta: top 3 only toggle, has decklist toggle, color dropdown, top 3 conversion % dropdown, store filter |
| AF5 | UX | Ranked/Unranked pill toggle on Players and Meta tabs (replaces All/5+/10+) |
| AF6 | FIX | Remove auto-default min events logic — always default to Unranked |
| AF7 | UX | Store filter dropdown choices scoped to currently selected scene |

### Admin-Scene Junction Table
| ID | Type | Description |
|----|------|-------------|
| AJ1 | SCHEMA | Create `admin_user_scenes` junction table (many-to-many) |
| AJ2 | SCHEMA | Add `regional_admin` role option to `admin_users` |
| AJ3 | MIGRATION | Populate junction table from existing 1:1 `admin_users.scene_id` assignments |
| AJ4 | UX | Update admin user form for multi-scene assignment |
| AJ5 | UX | Show scene admin roster in scene edit view |

### Discord UI Cleanup
| ID | Type | Description |
|----|------|-------------|
| DC1 | UX | Remove "Post Welcome to Discord" button from scene edit UI |
| DC2 | UX | Remove `discord_thread_id` input field from scene form |
| DC3 | MIGRATION | NULL out `discord_thread_id` on all scenes (deprecate column) |

---

## v1.8.0 — Discord Restructure & Datamon Bot

Design doc: `datamon-bot/DESIGN.md` (sections 2, 5, 6, 7)

### Datamon Bot (datamon-bot repo)
| ID | Type | Description |
|----|------|-------------|
| DB1 | FEATURE | Scaffold discord.py bot with cog structure, deploy to DigitalOcean droplet |
| DB2 | FEATURE | Role sync — grant/revoke Scene Admin and Regional Admin Discord roles on admin changes |
| DB3 | FEATURE | Slash commands: `/admins <scene>`, `/roster`, `/scene <name>` |
| DB4 | FEATURE | React-to-resolve — checkmark reaction adds `Resolved` tag to forum thread |
| DB5 | FEATURE | Auto-archive sweep — `Resolved` after 3 days, inactive after 7 days |
| DB6 | FEATURE | Welcome DM delivery — send credentials to new scene admins via bot DM |
| DB7 | FEATURE | Stale thread reminders — @mention assigned admin after X days unresolved |

### Webhook Refactor (digilab-app repo)
| ID | Type | Description |
|----|------|-------------|
| WR1 | REFACTOR | Repurpose `discord_create_scene_thread()` → `discord_create_action_thread()` for per-item threads |
| WR2 | REFACTOR | Update `discord_post_to_scene()` and `discord_post_data_error()` to create threads with @mentions from junction table |
| WR3 | SCHEMA | Add `discord_thread_id` column to `admin_requests` for bidirectional sync |
| WR4 | FEATURE | Resolution → Discord sync — update thread tag when request resolved in-app |
| WR5 | FEATURE | Automated welcome DM trigger on admin creation (calls Discord REST API with bot token) |

### Discord Server Setup (manual)
| ID | Type | Description |
|----|------|-------------|
| DS1 | MANUAL | Archive/delete existing 70 scene threads in #scene-coordination |
| DS2 | MANUAL | Set up forum tags (continent + type + status) |
| DS3 | MANUAL | Create #scene-admin-chat text channel |
| DS4 | MANUAL | Create Discord bot application, Scene Admin and Regional Admin roles |

---

## v1.9.0 — Results Redesign & Data Entry

### Results & Upload Tab Redesign
| ID | Type | Description |
|----|------|-------------|
| RU1 | UX | Paired redesign of Enter Results and Upload Results tabs |
| RU2 | FEATURE | Mobile-optimized result entry with touch-friendly grids |
| RU3 | VALIDATION | Tournament data quality checks — future dates, store required, player count confirmation |

### Mobile Admin Tabs
| ID | Type | Description |
|----|------|-------------|
| MOB-AD1 | FEATURE | Mobile scene admin tabs (Edit Stores, Edit Tournaments, Edit Players) |
| MOB-AD2 | FEATURE | Mobile super admin tabs (Edit Scenes, Edit Admins, Edit Decks) |

---

## v1.10.0 — Tournament Data & Ingestion

### Decklist Entry & Backfill
| ID | Type | Description |
|----|------|-------------|
| DL1 | FEATURE | Add decklist URL/data during tournament result entry |
| DL2 | FEATURE | Backfill decklists from Edit Tournaments tab for past events |

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

## v1.11.0 — UX Polish & Modals

### Modal Improvements
| ID | Type | Description |
|----|------|-------------|
| MOD1 | UX | Rating sparkline in player modal — trend over recent events |
| MOD2 | UX | Global vs local rank display in player modal |
| MOD3 | UX | Player modal: deck history timeline across formats |
| MOD4 | UX | Store and deck modal enhancements (TBD based on review) |

---

## v1.12.0 — Achievement Badges & Gamification

| ID | Type | Description |
|----|------|-------------|
| F10 | FEATURE | Player achievement badges — auto-calculated, displayed in player modal |
| AB1 | FEATURE | Tournament streak badges (consecutive attendance, podium runs) |
| AB2 | FEATURE | Deck mastery badges (X wins with same archetype) |
| AB3 | FEATURE | Scene milestone badges (first event, 10th event, etc.) |
| AB4 | UI | Badge display in player modal and player cards |

---

## v1.13.0 — Admin Infrastructure & Multi-Region

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

### Repository & Architecture Strategy (RESOLVED)

| Question | Decision |
|----------|----------|
| Discord bot location? | Separate repo: `datamon-bot` (Python, discord.py) |
| Bot hosting? | DigitalOcean droplet (~$4-6/mo) |
| Shared data access? | Bot gets read-only Neon DB access; app calls Discord REST API directly |
| Scene comparison / analytics tools? | Tab in main app (TBD) |
| Repo visibility? | Keep public (open source community) (TBD) |

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
