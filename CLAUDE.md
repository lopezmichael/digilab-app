# DigiLab - Claude Code Context

This document provides context for Claude Code to quickly understand and contribute to this project.

## Project Overview

A regional tournament tracking application for the Dallas-Fort Worth Digimon Trading Card Game community. Track player performance, store activity, deck meta, and local tournament results.

**Live App:** https://app.digilab.cards/

## Tech Stack

| Component | Technology |
|-----------|------------|
| Frontend | R Shiny with bslib + atomtemplates |
| Database | PostgreSQL (Neon) via pool + RPostgres |
| Charts | Highcharter |
| Maps | mapgl (Mapbox GL JS) |
| Tables | reactable |
| Card Data | DigimonCard.io API (cached locally) |
| Hosting | Posit Connect Cloud |

## Project Structure

```
digimon-tcg-standings/
├── app.R                    # Main Shiny application (thin wrapper, ~566 lines)
├── server/                  # Server logic modules
│   ├── shared-server.R      # Database, navigation, auth helpers
│   ├── public-dashboard-server.R  # Dashboard/Overview tab
│   ├── public-players-server.R    # Players tab
│   ├── public-meta-server.R       # Meta analysis tab
│   ├── public-tournaments-server.R # Tournaments tab
│   ├── public-stores-server.R     # Stores tab with map
│   ├── submit-shared-server.R     # Unified submit: wizard, grid, player matching
│   ├── submit-upload-server.R     # Submit: OCR + CSV upload
│   ├── submit-match-server.R      # Submit: match-by-match history
│   ├── submit-decklist-server.R   # Submit: standalone decklist URLs
│   ├── submit-grid-server.R       # Submit: paste/manual (admin, lazy-loaded)
│   ├── admin-tournaments-server.R # Tournament management
│   ├── admin-decks-server.R       # Deck archetype CRUD
│   ├── admin-stores-server.R      # Store management
│   ├── admin-players-server.R     # Player management
│   └── admin-formats-server.R     # Format management
├── views/                   # UI components
│   ├── dashboard-ui.R       # Dashboard with charts and stats
│   ├── stores-ui.R          # Store directory with map
│   ├── players-ui.R         # Player standings
│   ├── meta-ui.R            # Meta analysis
│   ├── tournaments-ui.R     # Tournament history
│   ├── submit-results-ui.R  # Unified submit results (card picker + wizard)
│   ├── mobile-dashboard-ui.R  # Mobile dashboard (conditional render)
│   ├── mobile-players-ui.R    # Mobile player cards
│   ├── mobile-meta-ui.R       # Mobile deck archetype cards
│   ├── mobile-tournaments-ui.R # Mobile tournament cards
│   ├── mobile-stores-ui.R     # Mobile compact map + store cards
│   ├── admin-decks-ui.R     # Deck archetype management
│   └── admin-stores-ui.R    # Store management
├── R/
│   ├── db_connection.R      # Database connection module
│   └── digimoncard_api.R    # DigimonCard.io API integration
├── scripts/                 # Python scripts for data sync
│   ├── sync_cards.py        # Sync cards from DigimonCard.io API
│   ├── sync_to_motherduck.py# Push local DB to cloud
│   └── sync_from_motherduck.py # Pull cloud DB to local
├── db/
│   └── schema.sql           # Database schema
├── docs/
│   ├── card-sync.md         # Card sync documentation
│   ├── plans/               # Design documents
│   └── solutions/           # Technical solutions & fixes
├── logs/
│   └── dev_log.md           # Development decisions log
├── data/
│   └── local.duckdb         # Local database (gitignored)
├── www/
│   ├── custom.css           # Custom styles (~3,600 lines)
│   └── mobile.css           # Mobile-only component styles
├── _brand.yml               # Atom brand configuration
├── CHANGELOG.md             # Version history
├── ARCHITECTURE.md          # Technical architecture reference
└── ROADMAP.md               # Future features and milestones
```

## Architecture Reference

**Always consult `ARCHITECTURE.md` before:**
- Adding new reactive values
- Creating new server modules
- Modifying navigation or modal patterns

The architecture doc contains:
- Server module structure and naming conventions (`public-*`, `admin-*`)
- Complete reactive values reference (32 values across 6 categories)
- Navigation patterns (tab switching, sidebar sync)
- Modal patterns (Bootstrap vs Shiny modals)
- Database patterns (connection handling, refresh triggers)

## Current Work

### Latest Release: v1.9.5 - Match Submission Pipeline Fix

Fixed match-by-match submissions silently saving 0 matches due to PostgreSQL sequence collision with Limitless sync. Replaced plain INSERTs with upserts, added tournament completeness badges, and existing data preview in the match submission UI. See `CHANGELOG.md` for full details.

See `ROADMAP.md` for the full version plan.

### Recent Releases

| Version | Focus |
|---------|-------|
| v1.9.5 | Match Submission Pipeline Fix |
| v1.9.4 | Sentry Error Reporting Blind Spots |
| v1.9.3 | Country & State Scene Hierarchy |
| v1.9.2 | Match History Schema & Layout-Aware Parser |
| v1.9.1 | Auto-Anonymize Guest & Placeholder Players |
| v1.9.0 | Unified Submit Results Tab |
| v1.7.8 | Admin Scene Scoping & Merge Fix |
| v1.7.7 | Duplicate Player Name Fixes |
| v1.7.6 | Country-Grouped Scene Dropdowns & Store Filters |
| v1.7.5 | Discord Webhook Embeds |
| v1.7.4 | Admin Permission Tier Scoping |
| v1.7.3 | Discord Restructure & Admin UI Design Pass |
| v1.7.2 | Dual-Color Badges, Rating Snapshots & Bug Fixes |
| v1.7.0 | Filter Redesign & Scene Restructure |
| v1.6.0 | Player Identity & Disambiguation |
| v1.5.2 | Prepared Statement Resilience |
| v1.5.0 | Performance & Caching |
| v1.4.0 | Admin Infrastructure & Request Queue |
| v1.3.2 | Sentry Error Fixes |
| v1.3.1 | Fixes & Upload Improvements |

### Key Architectural Decisions

**Multi-Region (v0.23, implemented):**
- Scenes hierarchy: Global → Country → State → Metro
- "Online" as a special top-level scene for webcam tournaments
- Players don't belong to scenes; they appear on leaderboards based on where they've competed
- Rating is global; leaderboards are filtered views

**Limitless Integration (v0.24, implemented):**
- Online organizers = virtual stores (`is_online = TRUE`, Online scene)
- Sync via `scripts/sync_limitless.py` with deck auto-classification
- Online tournaments feed same Elo rating pool as locals

**User Accounts (deferred, originally v0.22):**
- Discord OAuth for authentication (free, TCG community already uses Discord)
- Permission levels: Viewer (default, no login), Scene Admin, Super Admin
- Design doc: `docs/plans/2026-02-05-user-accounts-design.md`

### Completed Features

**UI/UX (v0.12-v0.13):**
- Digital Digimon aesthetic throughout
- Responsive mobile design
- App-wide loading screen
- Modal stat boxes and cross-modal navigation

**Rating System (v0.14):**
- Competitive Rating (Elo-style)
- Achievement Score (points-based)
- Store Rating (weighted blend)

**Content Pages (v0.19):**
- About, FAQ, For Organizers pages
- Footer navigation
- Open Graph meta tags, GA4 tracking

### Minor Outstanding Items

- [ ] Replace header cards icon with Digivice SVG (v1.0)
- [ ] Mobile table column prioritization (v1.0)
- [ ] Achievement Score decay decision (future)

## Key Logs and Documentation

### Development Log
**Location:** `logs/dev_log.md`

Contains dated entries explaining development decisions, technical choices, and blockers. Always update this log when making significant technical decisions.

### Changelog
**Location:** `CHANGELOG.md`

Semantic versioning log of all features, fixes, and changes. Update when releasing new versions.

### Design Documents
**Location:** `docs/plans/`

Contains design documents for features before implementation. Key active plans:
- `2026-02-05-user-accounts-design.md` - Discord OAuth, permissions, admin workflow (to be created)
- `2026-02-04-region-expansion-design.md` - Scenes hierarchy, multi-region support
- `2026-02-04-deep-linking-design.md` - Shareable URLs, browser history
- `2026-02-04-content-pages-design.md` - About, FAQ, For Organizers pages
- `2026-02-22-ocr-layout-parser-design.md` - Layout-aware OCR parser using bounding box coordinates
- `2026-02-03-public-submissions-design.md` - Screenshot OCR, public result submission
- `2026-02-01-rating-system-design.md` - Competitive Rating, Achievement Score, Store Rating methodology

Historical/completed plans in the same folder.

## Important Technical Notes

### Database Connection
- Uses Neon PostgreSQL for all environments (local dev, Posit Connect, GitHub Actions)
- Connection pooling via R `pool` package + `RPostgres`
- `db_pool` object created once at app startup, shared across all sessions
- No `rv$db_con` — pool passed directly to `dbGetQuery()`/`dbExecute()`
- Environment vars: `NEON_HOST`, `NEON_DATABASE`, `NEON_USER`, `NEON_PASSWORD`

### Database Notes
1. **Parameterized queries:** RPostgres uses `$1, $2, $3` numbered placeholders (not `?`)
2. **Connection pool:** The `pool` package manages connection lifecycle — no manual connect/disconnect
3. **Transactions:** Use `pool::localCheckout(db_pool)` to get a dedicated connection for multi-statement transactions
4. **FK constraints:** Properly enforced — INSERT order matters (parents before children)
5. **Auto-increment IDs:** Tables use `GENERATED BY DEFAULT AS IDENTITY` — use `INSERT ... RETURNING id` instead of `next_id()`

### Shiny selectInput Styling
- **Use `selectize = FALSE` for title strip dropdowns** - Native HTML selects are more consistently stylable
- Selectize.js dropdown options cannot be reliably styled with CSS (browser ignores most option styling)
- Native selects with light backgrounds (`rgba(255, 255, 255, 0.9)`) and dark text work best
- When using native selects, choice values should use `list()` with string values for consistency

### DigimonCard.io API
- API returns 403 on Posit Connect Cloud (blocks server IPs)
- Solution: Cards cached in `cards` table, synced via `scripts/sync_cards.py`
- Card images (CDN) work fine - only API endpoints blocked
- GitHub Actions runs monthly sync via `.github/workflows/sync-cards.yml`

### Environment Variables
Required in `.env` file (copy from `.env.example`):
```
NEON_HOST=your-project.us-east-2.aws.neon.tech
NEON_DATABASE=neondb
NEON_USER=neondb_owner
NEON_PASSWORD=your_password_here
MAPBOX_ACCESS_TOKEN=your_mapbox_token_here
```

## Required Workflows

### Superpowers (REQUIRED)

**Always use superpowers for any non-trivial work.** This is not optional.

| Superpower | When to Use | Required? |
|------------|-------------|-----------|
| `brainstorming` | Before any new feature or creative work | Yes |
| `writing-plans` | Before implementing multi-step tasks | Yes |
| `subagent-driven-development` | When executing plans with independent tasks | Yes |
| `verification-before-completion` | Before claiming work is complete | Yes |
| `finishing-a-development-branch` | When ready to merge/PR | Yes |

### Standard Feature Workflow

```
1. User requests new feature
2. /brainstorming - Explore intent and requirements
3. /writing-plans - Create design doc in docs/plans/
4. Get user approval
5. Create feature branch (git checkout -b feature/feature-name)
6. /subagent-driven-development - Execute implementation
7. Commit regularly (small, logical commits)
8. /verification-before-completion - Verify everything works
9. /finishing-a-development-branch - Create PR for review
10. Merge to main after approval
```

### Git Workflow (REQUIRED)

**Feature branches:** All new features and non-trivial changes must be developed on feature branches, not directly on main.

```bash
# Create feature branch
git checkout -b feature/feature-name

# Or for refactors
git checkout -b refactor/refactor-name

# Or for fixes
git checkout -b fix/fix-name
```

**Commit regularly:** Make small, logical commits as you work. Don't wait until everything is done.

**Review before merge:** Feature branches require review before merging to main. Use PRs or get explicit user approval.

**v1.0 Release Strategy:** All new features from v0.20 onward should be developed in feature branches and merged incrementally as they're completed and tested. Main should stay stable with released versions.

**Exception:** Documentation-only changes and minor config tweaks can go directly to main. Non-trivial bug fixes (especially anything touching auth, player identity, or transaction logic) should use feature branches with review.

### Code Verification (REQUIRED)

Before committing, always verify code works:

**R Installation Path (Windows):**
```bash
# R is installed at:
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe"

# Run syntax check
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "source('app.R')"

# Run lintr (if available)
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "lintr::lint('app.R')"
```

**Manual verification:** If R can't be run from bash, ask the user to:
1. Run `shiny::runApp()` and verify app loads
2. Test the specific feature/fix that was changed
3. Confirm no console errors

### Documentation Updates (REQUIRED)

Keep documentation in sync with code changes. Update these files regularly:

| File | When to Update |
|------|----------------|
| `CHANGELOG.md` | Every version release (features, fixes, changes) |
| `logs/dev_log.md` | Significant technical decisions, blockers, architecture changes |
| `ARCHITECTURE.md` | New reactive values, server modules, or patterns |
| `README.md` | New features, changed setup instructions, updated screenshots |
| `ROADMAP.md` | Completed milestones, new planned features |
| `version_changelog_content()` | Feature releases (x.X.0) only — update highlights in `server/scene-server.R` |

**Guidelines:**
- Update `CHANGELOG.md` when releasing a new version (not every commit)
- Update `dev_log.md` for technical decisions worth remembering
- Update `README.md` when user-facing features change significantly
- Update `ARCHITECTURE.md` before adding new reactive values or modules
- On **feature releases (x.X.0)**: bump `APP_VERSION` in `app.R` and update `version_changelog_content()` in `server/scene-server.R` with 3-5 user-facing highlights (see ARCHITECTURE.md > Modal Patterns for details)
- **After any edit to `ROADMAP.md`**: run `python3 scripts/validate_roadmap.py` to catch duplicate YAML keys, missing fields, and structural errors before committing
- Don't let documentation drift - if you change code, check if docs need updating

### Player Identity Change Scenarios

When modifying the edit grid save handler, player matching, or detach logic, verify all scenarios:

| Scenario | Expected Behavior |
|----------|-------------------|
| Name unchanged, Bandai unchanged | Keep existing player |
| Name unchanged, Bandai changed (super admin) | Detach to new/existing player |
| Name changed, Bandai changed (super admin) | Detach to new/existing player |
| Name changed, Bandai unchanged | Name-change logic (resolve/rename) |
| Bandai changed, non-super-admin | No detach (existing behavior) |
| Target player already in tournament | Error message, full ROLLBACK |
| GUEST name or placeholder Bandai | Auto-anonymize on player creation |

### Security-Sensitive Code Patterns

When writing or reviewing code that handles auth, permissions, or data integrity:

- **Fail-closed defaults:** If a DB query fails, default to *denying* access, not granting it. Never use `default = 0` for permission/count checks — use `NA` and require positive confirmation.
- **Transaction-aware queries:** Inside `localCheckout(db_pool)` transactions, pass `conn` (not `db_pool`) to helper functions like `generate_unique_slug`. Pool connections can't see uncommitted rows from the current transaction.
- **Super admin gates:** Always check `isTRUE(rv$is_superadmin)` — never rely on truthiness of `rv$is_superadmin` alone, since it may be NULL.

## Development Workflow

### Running Locally

1. Copy `.env.example` to `.env` and add your tokens
2. Initialize database: `source("scripts/init_database.R")`
3. Seed data: Run seed scripts in `scripts/`
4. Run app: `shiny::runApp()`

### Adding Mock Data for Testing

```r
source("scripts/seed_mock_data.R")
```

### Syncing Database

All environments use the same Neon PostgreSQL database. No sync needed between local and cloud.

### Card Sync

```bash
# Regular update (fast - only new cards)
python scripts/sync_cards.py --by-set --incremental

# Full re-sync
python scripts/sync_cards.py --by-set
```

### Limitless TCG Sync (Online Tournaments)

```bash
# Manual: Incremental sync
python scripts/sync_limitless.py --all-tier1 --incremental --classify

# Manual: Sync since specific date
python scripts/sync_limitless.py --all-tier1 --since 2025-10-01 --classify

# Automated: GitHub Actions runs weekly (sync-limitless.yml)
```

**Tier 1 Organizers:** Eagle's Nest (452), PHOENIX REBORN (281), DMV Drakes (559), MasterRukasu (578), Expanse Italia (2536), DigiGalaxy (1009)

## Code Style Notes

- **UI refactoring:** Server logic is in `server/` files, UI in `views/` files
- **Tables:** Use `reactable` (not `tableOutput`)
- **Charts:** Use `highcharter` with `hc_theme_atom_switch()` for theming
- **Maps:** Use `atom_mapgl()` from atomtemplates
- **Layout:** Use `layout_columns` from bslib for consistent layouts

### CSS Guidelines

- **Location:** All custom styles in `www/custom.css`, brand config in `_brand.yml`
- **Organization:** CSS file has 45+ labeled sections - find the right section before adding
- **Prefer CSS classes over inline styles** - only use inline for JS visibility toggles or dynamic R values
- **Naming:** Component-based (`card-search-grid`), modifiers with `--` (`badge--success`)
- **Existing utilities:** `clickable-row`, `help-icon`, `deck-badge-{color}`, `place-1st/2nd/3rd`
- **Test both light/dark mode and mobile** when adding styles

See `ARCHITECTURE.md` > CSS Architecture for full documentation.

## Current Version

**v1.9.5** - Match Submission Pipeline Fix

See `CHANGELOG.md` for full version history and `ROADMAP.md` for upcoming features.
