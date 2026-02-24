# DigiLab

A regional tournament tracking application for the Digimon Trading Card Game community. Track player performance, store activity, deck meta, and local tournament results.

**Live App:** https://digilab.cards/

**Current Version:** v1.0.3

## Features

### For Players
- **Player Ratings**: Elo-style competitive rating system with achievement scores
- **Tournament History**: Track your results, favorite decks, and performance trends
- **Meta Analysis**: See what decks are winning and their conversion rates
- **Store Directory**: Interactive map of local game stores with tournament schedules
- **Scene Filtering**: Pick your region (or Online) and see leaderboards scoped to your area
- **Installable PWA**: Add DigiLab to your home screen on mobile or desktop

### For Tournament Organizers
- **Screenshot OCR**: Submit tournament results by uploading Bandai TCG+ standings screenshots (95% accuracy)
- **Limitless Integration**: Online tournament results sync automatically with deck auto-classification
- **Tournament Management**: Edit tournaments, results, and player data
- **Store Management**: Add and manage store information
- **Per-User Admin Accounts**: Role-based access with super admin and scene admin roles

### Dashboard & Analytics
- **Interactive Dashboard**: Value boxes, charts, and tables showing tournament activity
- **Meta Share Trends**: Track deck popularity over time with stacked area charts
- **Color Distribution**: See the breakdown of deck colors in the meta
- **Top Decks**: Visual grid showing the most successful archetypes with card images

### Design
- **Digital Digimon Aesthetic**: Custom UI with grid patterns, circuit accents, and cyan glow effects
- **Agumon Mascot**: Loading spinner, disconnect screen, 404 modals, and empty states
- **Responsive Design**: Optimized for both desktop and mobile devices
- **Dark/Light Mode**: Full theme support with consistent styling

## Tech Stack

| Component | Technology |
|-----------|------------|
| Frontend | R Shiny with bslib + atomtemplates |
| Database | PostgreSQL (Neon) |
| Charts | Highcharter |
| Maps | mapgl (Mapbox GL JS) |
| Tables | reactable |
| OCR | Google Cloud Vision API |
| Card Data | DigimonCard.io API (cached locally) |
| Hosting | Posit Connect Cloud |

## Installation

### Prerequisites

- R 4.3+
- Mapbox access token (for map features)
- Google Cloud Vision API key (for OCR features)

### Required R Packages

```r
install.packages(c(
  # Core Shiny
  "shiny", "shinyjs", "bslib", "bsicons", "htmltools",
  # Database
  "DBI", "duckdb",
  # API/Data
  "httr2", "jsonlite", "base64enc",
  # Visualization
  "reactable", "highcharter", "mapgl", "sf",
  # Fonts
  "sysfonts", "showtext",
  # Geocoding
  "tidygeocoder"
))

# Install atomtemplates from GitHub
remotes::install_github("lopezmichael/atomtemplates")
```

### Setup

1. Clone the repository:
```bash
git clone https://github.com/lopezmichael/digimon-tcg-standings.git
cd digimon-tcg-standings
```

2. Create a `.env` file with your tokens:
```bash
cp .env.example .env
```

3. Edit `.env` and add your credentials:
```
MOTHERDUCK_TOKEN=your_motherduck_token_here
MAPBOX_ACCESS_TOKEN=your_mapbox_token_here
GOOGLE_CLOUD_VISION_API_KEY=your_google_cloud_vision_key_here
```

4. Initialize the database and seed data:
```r
source("scripts/init_database.R")
source("scripts/seed_stores.R")
source("scripts/seed_archetypes.R")
source("scripts/seed_formats.R")
```

5. (Optional) Add mock data for testing:
```r
source("scripts/seed_mock_data.R")
```

6. Run the app:
```r
shiny::runApp()
```

## Project Structure

```
digimon-tcg-standings/
├── app.R                    # Main Shiny application
├── R/
│   ├── db_connection.R      # Database connection module
│   ├── digimoncard_api.R    # DigimonCard.io API integration
│   ├── ratings.R            # Rating system calculations
│   └── ocr.R                # Google Cloud Vision OCR integration
├── server/                  # Server logic modules
│   ├── shared-server.R      # Database, navigation, auth helpers
│   ├── public-*.R           # Public page server logic
│   └── admin-*.R            # Admin page server logic
├── views/                   # UI components
│   ├── dashboard-ui.R       # Dashboard with charts and stats
│   ├── about-ui.R           # About page
│   ├── faq-ui.R             # FAQ page
│   └── ...                  # Other UI modules
├── scripts/                 # Database and sync scripts
├── db/
│   └── schema.sql           # Database schema
├── docs/
│   ├── plans/               # Design documents
│   └── solutions/           # Technical solutions
├── www/
│   └── custom.css           # Custom styles (~2000 lines)
├── _brand.yml               # Brand configuration
├── CHANGELOG.md             # Version history
├── ROADMAP.md               # Future features and milestones
└── ARCHITECTURE.md          # Technical architecture reference
```

## Database Schema

### Core Tables
- `stores` - Local game store information (name, address, coordinates, schedule)
- `players` - Player profiles with optional Bandai member numbers
- `deck_archetypes` - Community deck names and display cards
- `tournaments` - Tournament events with format, type, and metadata
- `results` - Player tournament results (placement, record, deck, decklist URL)
- `formats` - Game formats/sets (BT19, EX08, etc.)
- `cards` - Card database from DigimonCard.io (4,200+ cards)

### Views
- `player_standings` - Aggregated player statistics
- `archetype_meta` - Deck performance metrics
- `store_activity` - Store tournament summary

## Rating System

DigiLab uses a three-part rating system:

| Rating | Description |
|--------|-------------|
| **Competitive Rating** | Elo-style skill rating (1200-2000+ scale) based on tournament placements and opponent strength |
| **Achievement Score** | Points-based engagement metric rewarding participation, top finishes, and variety |
| **Store Rating** | Venue quality score (0-100) based on player strength, attendance, and activity |

See `docs/plans/2026-02-01-rating-system-design.md` for full methodology.

## Python Scripts

### Card Sync

Syncs card data from DigimonCard.io API:

```bash
# Regular update (fast - only new cards)
python scripts/sync_cards.py --by-set --incremental

# Full re-sync
python scripts/sync_cards.py --by-set
```

See [docs/card-sync.md](docs/card-sync.md) for full documentation.

### Database Sync

```bash
# Push local database to MotherDuck cloud
python scripts/sync_to_motherduck.py

# Pull cloud database to local
python scripts/sync_from_motherduck.py --yes
```

## Roadmap

See [ROADMAP.md](ROADMAP.md) for the full development roadmap.

DigiLab v1.0 is now live. See [ROADMAP.md](ROADMAP.md) for post-launch plans including full user accounts, achievement badges, and more.

## Contributing

Contributions welcome! Please open an issue or submit a pull request.

For development guidelines, see [CLAUDE.md](CLAUDE.md).

## Support

- **Issues:** [GitHub Issues](https://github.com/lopezmichael/digimon-tcg-standings/issues)
- **Support:** [Ko-fi](https://ko-fi.com/atomshell)

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- [DigimonCard.io](https://digimoncard.io) for card data API
- [DigimonMeta](https://digimonmeta.com) and [Digital Gate Open](https://digitalgateopen.com) for meta research
- [atomtemplates](https://github.com/lopezmichael/atomtemplates) for the Shiny design system
- The DFW Digimon TCG community for being the inspiration for DigiLab
