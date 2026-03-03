---
currentVersion: "1.2.0"
lastUpdated: "2026-03-03"

inProgress: []

planned:
  - id: meta-insights-app
    title: "Meta Insights App"
    description: "Standalone analytics app for deep deck meta analysis, matchup data, and tournament trend insights."
    tags: [new-app, analytics]
    targetVersion: "Future"

  - id: achievement-badges
    title: "Achievement Badges"
    description: "Auto-calculated player achievements displayed in player modals — tournament streaks, deck mastery, and scene milestones."
    tags: [gamification, feature]
    targetVersion: "Future"

  - id: performance-optimization
    title: "Performance & Scaling"
    description: "Dashboard query optimization with materialized views, expanded caching, lazy tab loading, and connection pool tuning."
    tags: [scaling]
    targetVersion: "Future"

  - id: regional-admin-tier
    title: "Regional Admin Tier"
    description: "New admin role between Super Admin and Scene Admin for country or state-level oversight with cross-scene management."
    tags: [admin, scaling]
    targetVersion: "Future"

  - id: mobile-data-entry
    title: "Mobile Data Entry"
    description: "Mobile-first progressive web app for tournament result entry by organizers in the field."
    tags: [mobile, feature]
    targetVersion: "Future"

completed:
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

  - id: cross-scene-collision-fix
    title: "Cross-Scene Player Collision Fix"
    description: "Fixed player name collisions across scenes with scene-scoped matching and duplicate detection scripts."
    tags: [data, feature]
    date: "2026-03"
    version: "v1.1.2"

  - id: app-subdomain-migration
    title: "App Moved to app.digilab.cards"
    description: "Migrated the Shiny app from digilab.cards to app.digilab.cards to make room for the public website."
    tags: [website, scaling]
    date: "2026-03"
    version: "v1.1.2"

  - id: discord-integration
    title: "Discord Integration & Error Reporting"
    description: "Discord webhook system with themed bots, in-app request modals, contextual error reporting, and bug report forms."
    tags: [integration, community]
    date: "2026-02"
    version: "v1.1.0"

  - id: public-launch
    title: "Public Launch"
    description: "v1.0 release with PWA support, performance profiling, responsive grids, and production hardening."
    tags: [feature, ux]
    date: "2026-02"
    version: "v1.0.0"

  - id: admin-auth
    title: "Admin Authentication"
    description: "Per-user admin accounts with bcrypt hashing, role-based permissions, scene scoping, and admin management UI."
    tags: [security, admin]
    date: "2026-02"
    version: "v0.29.0"

  - id: onboarding-help
    title: "Onboarding & Help System"
    description: "Three-step onboarding carousel, contextual hints, per-page help text, and Agumon mascot integration."
    tags: [ux, feature]
    date: "2026-02"
    version: "v0.27.0"

  - id: limitless-integration
    title: "Limitless TCG Integration"
    description: "Automated sync of online tournament results from Limitless TCG with deck auto-classification and player matching."
    tags: [integration, data]
    date: "2026-02"
    version: "v0.24.0"

  - id: multi-region
    title: "Multi-Region Support"
    description: "Scene hierarchy with global, country, state, and metro levels. Scene selector, geolocation, and cross-scene filtering."
    tags: [feature, scaling]
    date: "2026-02"
    version: "v0.23.1"

  - id: deep-linking
    title: "Deep Linking & Shareable URLs"
    description: "Shareable URLs for players, decks, stores, and tournaments with browser history support and Copy Link buttons."
    tags: [feature, sharing]
    date: "2026-02"
    version: "v0.21.0"

  - id: rating-system
    title: "Rating System"
    description: "Competitive Rating (Elo-style), Achievement Score (points-based), and Store Rating with methodology documentation."
    tags: [ratings, methodology]
    date: "2026-02"
    version: "v0.14.0"
---

# DigiLab Roadmap

**Current Version:** v1.2.0
**Last Updated:** 2026-03-03

> This file is the source of truth for the [public roadmap](https://digilab.cards/roadmap).
> A GitHub Action syncs the YAML frontmatter to the website on every push to main.

---

## Planned

| Feature | Description | Target |
|---------|-------------|--------|
| **Meta Insights App** | Standalone analytics app for deep deck meta analysis, matchup data, and tournament trend insights | Future |
| **Achievement Badges** | Auto-calculated player achievements — tournament streaks, deck mastery, and scene milestones | Future |
| **Performance & Scaling** | Materialized views, expanded caching, lazy tab loading, and query optimization | Future |
| **Regional Admin Tier** | Country/state-level admin oversight role with cross-scene management capabilities | Future |
| **Mobile Data Entry** | Mobile-first PWA for organizer tournament result entry in the field | Future |

---

## Recently Completed

| Version | Feature | Shipped |
|---------|---------|---------|
| v1.2.0 | Rating System Redesign | 2026-03 |
| v1.2.0 | DigiLab Website | 2026-03 |
| v1.1.2 | Cross-Scene Player Collision Fix | 2026-03 |
| v1.1.2 | App Moved to app.digilab.cards | 2026-03 |
| v1.1.0 | Discord Integration & Error Reporting | 2026-02 |
| v1.0.0 | Public Launch | 2026-02 |
| v0.29.0 | Admin Authentication | 2026-02 |
| v0.27.0 | Onboarding & Help System | 2026-02 |
| v0.24.0 | Limitless TCG Integration | 2026-02 |
| v0.23.1 | Multi-Region Support | 2026-02 |
| v0.21.0 | Deep Linking & Shareable URLs | 2026-02 |
| v0.14.0 | Rating System | 2026-02 |

See [CHANGELOG.md](CHANGELOG.md) for detailed version history.

---

## Frontmatter Sync

The YAML frontmatter above is the machine-readable roadmap data. A GitHub Action in the
`digilab-web` repo extracts it and converts it to `src/data/roadmap.yaml` for the website.

**To update the roadmap:** Edit the YAML frontmatter, then update the markdown sections
to match. Push to main and the website syncs automatically.

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
| ~~DI3~~ | ~~BUG~~ | ~~Rating recalc scope audit~~ (Done in v1.2.0 — single-pass chronological algorithm) |
| ~~DI4~~ | ~~FEATURE~~ | ~~Chronological rating calculation~~ (Done in v1.2.0 — tournaments processed in date order) |
| ~~DI5~~ | ~~REFACTOR~~ | ~~Rating recalc on backfill~~ (Done in v1.2.0 — `calculate_ratings_from_date()` for partial rebuilds) |

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
| BLOG1 | FEATURE | DigiLab Blog/News section | Announce changes, explain methodology, share meta insights. First post: Rating System v2.0 |
| BLOG2 | FEATURE | Public roadmap page | Link from blog, show what's coming, build transparency |
| BLOG3 | FEATURE | Methodology documentation | Rating formulas, achievement scoring, store ratings — public-facing explainers |
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
| ~~Static website at digilab.cards (WS1/WS2/SEO1)~~ | Done in v1.2.0 — Astro site at digilab.cards with blog, roadmap, landing page |
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

## References

- **Bug Documentation:** `docs/solutions/`
- **Design Documents:** `docs/plans/`
- **Development Log:** `logs/dev_log.md`
- **SVG Assets:** `docs/digimon-mascots.md` — placement tracking, future commission spec, art style guidelines
