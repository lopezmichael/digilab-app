-- DigiLab - Digimon TCG Tournament Tracker
-- Database Schema for MotherDuck (Cloud DuckDB)
-- Version: 1.4.0
-- Created: January 2026
-- Updated: 2026-02-19 - Added Limitless TCG integration tables

-- =============================================================================
-- SCENES TABLE
-- Hierarchical geographic organization (Global -> Country -> State -> Metro)
-- Enables multi-region support and deep linking with ?scene=dfw URLs
-- =============================================================================
CREATE TABLE IF NOT EXISTS scenes (
    scene_id INTEGER PRIMARY KEY,
    name VARCHAR NOT NULL,
    slug VARCHAR UNIQUE,              -- URL-friendly identifier (e.g., 'dfw', 'online')
    display_name VARCHAR,             -- Human-readable name (e.g., 'Dallas-Fort Worth')
    parent_scene_id INTEGER,          -- FK to parent scene (Texas -> USA -> Global)
    scene_type VARCHAR NOT NULL,      -- 'global', 'country', 'state', 'metro', 'online'
    latitude DECIMAL(9, 6),           -- Center point for map views
    longitude DECIMAL(9, 6),
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for scene queries
CREATE INDEX IF NOT EXISTS idx_scenes_slug ON scenes(slug);
CREATE INDEX IF NOT EXISTS idx_scenes_parent ON scenes(parent_scene_id);
CREATE INDEX IF NOT EXISTS idx_scenes_type ON scenes(scene_type);

-- =============================================================================
-- STORES TABLE
-- Tracks local game stores hosting Digimon TCG events
-- =============================================================================
CREATE TABLE IF NOT EXISTS stores (
    store_id INTEGER PRIMARY KEY,
    name VARCHAR NOT NULL,
    slug VARCHAR,                     -- URL-friendly identifier for deep linking
    address VARCHAR,
    city VARCHAR NOT NULL,
    state VARCHAR,
    zip_code VARCHAR,
    latitude DECIMAL(9, 6),
    longitude DECIMAL(9, 6),
    scene_id INTEGER,                 -- FK to scenes table
    schedule_info TEXT,               -- Legacy: JSON stored as text (use store_schedules instead)
    tcgplus_store_id VARCHAR,
    website VARCHAR,
    phone VARCHAR,
    is_active BOOLEAN DEFAULT TRUE,
    is_online BOOLEAN DEFAULT FALSE,
    country VARCHAR DEFAULT 'USA',        -- Country code for international support
    limitless_organizer_id INTEGER,  -- Limitless TCG organizer ID for auto-sync
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create index for store slug lookups
CREATE INDEX IF NOT EXISTS idx_stores_slug ON stores(slug);
CREATE INDEX IF NOT EXISTS idx_stores_scene ON stores(scene_id);
CREATE INDEX IF NOT EXISTS idx_stores_limitless ON stores(limitless_organizer_id);

-- =============================================================================
-- STORE SCHEDULES TABLE
-- Tracks recurring event schedules for stores (e.g., "Wednesdays at 7pm")
-- One row per day/time slot - stores with multiple events have multiple rows
-- =============================================================================
CREATE TABLE IF NOT EXISTS store_schedules (
    schedule_id INTEGER PRIMARY KEY,
    store_id INTEGER NOT NULL,          -- References stores(store_id) - no FK for DuckDB compat
    day_of_week INTEGER NOT NULL,       -- 0=Sunday, 1=Monday, ..., 6=Saturday
    start_time TEXT NOT NULL,           -- "19:00" format (24-hour)
    frequency VARCHAR DEFAULT 'weekly', -- weekly, biweekly, monthly
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for schedule queries
CREATE INDEX IF NOT EXISTS idx_store_schedules_store ON store_schedules(store_id);
CREATE INDEX IF NOT EXISTS idx_store_schedules_day ON store_schedules(day_of_week);
CREATE INDEX IF NOT EXISTS idx_store_schedules_active ON store_schedules(is_active);

-- =============================================================================
-- FORMATS TABLE
-- Reference table for game formats/sets (BT19, EX08, etc.)
-- =============================================================================
CREATE TABLE IF NOT EXISTS formats (
    format_id VARCHAR PRIMARY KEY,           -- Set code: 'BT19', 'EX08', etc.
    set_name VARCHAR NOT NULL,               -- Full name: 'Xros Encounter'
    display_name VARCHAR NOT NULL,           -- Display: 'BT19 (Xros Encounter)'
    release_date DATE,                       -- Release date for sorting
    sort_order INTEGER,                      -- Manual sort order (lower = newer)
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create index for format lookups
CREATE INDEX IF NOT EXISTS idx_formats_active ON formats(is_active);
CREATE INDEX IF NOT EXISTS idx_formats_sort ON formats(sort_order);

-- =============================================================================
-- CARDS TABLE
-- Cached card data from DigimonCard.io API for local search
-- =============================================================================
CREATE TABLE IF NOT EXISTS cards (
    card_id VARCHAR PRIMARY KEY,          -- e.g., "BT13-087"
    name VARCHAR NOT NULL,                -- e.g., "Beelzemon"
    display_name VARCHAR NOT NULL,        -- e.g., "Beelzemon (BT13-087)"
    card_type VARCHAR NOT NULL,           -- "Digimon", "Tamer", "Option", "Digi-Egg"
    color VARCHAR,                        -- Primary color
    color2 VARCHAR,                       -- Secondary color (if any)
    level INTEGER,                        -- Digimon level (NULL for others)
    dp INTEGER,                           -- Digimon DP (NULL for others)
    play_cost INTEGER,
    digi_type VARCHAR,                    -- e.g., "Demon Lord"
    stage VARCHAR,                        -- e.g., "Mega"
    rarity VARCHAR,                       -- e.g., "SR"
    set_code VARCHAR,                     -- e.g., "BT13" (extracted from card_id)
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for card lookups
CREATE INDEX IF NOT EXISTS idx_cards_name ON cards(name);
CREATE INDEX IF NOT EXISTS idx_cards_type ON cards(card_type);
CREATE INDEX IF NOT EXISTS idx_cards_color ON cards(color);
CREATE INDEX IF NOT EXISTS idx_cards_set ON cards(set_code);

-- =============================================================================
-- PLAYERS TABLE
-- Tracks players participating in local tournaments
-- =============================================================================
CREATE TABLE IF NOT EXISTS players (
    player_id INTEGER PRIMARY KEY,
    display_name VARCHAR NOT NULL,
    tcgplus_id VARCHAR,
    member_number VARCHAR,  -- Bandai TCG+ member number (0000XXXXXX), uniqueness enforced in app
    limitless_username VARCHAR,
    home_store_id INTEGER,              -- References stores(store_id) - no FK for DuckDB compat
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create index for player lookups
CREATE INDEX IF NOT EXISTS idx_players_display_name ON players(display_name);
CREATE INDEX IF NOT EXISTS idx_players_tcgplus_id ON players(tcgplus_id);

-- =============================================================================
-- DECK ARCHETYPES TABLE
-- Reference table mapping community deck names to associated cards
-- =============================================================================
CREATE TABLE IF NOT EXISTS deck_archetypes (
    archetype_id INTEGER PRIMARY KEY,
    archetype_name VARCHAR NOT NULL UNIQUE,
    slug VARCHAR,                     -- URL-friendly identifier for deep linking
    display_card_id VARCHAR,
    primary_color VARCHAR NOT NULL,
    secondary_color VARCHAR,
    playstyle_tags TEXT,              -- JSON array stored as text
    is_active BOOLEAN DEFAULT TRUE,
    is_multi_color BOOLEAN DEFAULT FALSE,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for archetype lookups
CREATE INDEX IF NOT EXISTS idx_archetypes_name ON deck_archetypes(archetype_name);
CREATE INDEX IF NOT EXISTS idx_archetypes_slug ON deck_archetypes(slug);
CREATE INDEX IF NOT EXISTS idx_archetypes_color ON deck_archetypes(primary_color);

-- =============================================================================
-- ARCHETYPE CARDS TABLE (Junction Table)
-- Links archetypes to their associated cards from DigimonCard.io
-- =============================================================================
CREATE TABLE IF NOT EXISTS archetype_cards (
    archetype_id INTEGER NOT NULL,       -- References deck_archetypes(archetype_id) - no FK for DuckDB compat
    card_id VARCHAR NOT NULL,
    card_role VARCHAR NOT NULL,
    is_core BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (archetype_id, card_id)
);

-- Create index for card lookups (find decks using a specific card)
CREATE INDEX IF NOT EXISTS idx_archetype_cards_card_id ON archetype_cards(card_id);

-- =============================================================================
-- DECK REQUESTS TABLE
-- Tracks pending deck archetype requests from public submissions
-- =============================================================================
CREATE TABLE IF NOT EXISTS deck_requests (
    request_id INTEGER PRIMARY KEY,
    deck_name TEXT NOT NULL,
    primary_color TEXT NOT NULL,
    secondary_color TEXT,
    display_card_id TEXT,
    status TEXT DEFAULT 'pending',  -- pending, approved, rejected
    approved_archetype_id INTEGER,  -- Links to created deck after approval
    submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    reviewed_at TIMESTAMP
);

-- Create index for pending requests lookup
CREATE INDEX IF NOT EXISTS idx_deck_requests_status ON deck_requests(status);

-- =============================================================================
-- TOURNAMENTS TABLE
-- Tracks individual tournament events
-- =============================================================================
CREATE TABLE IF NOT EXISTS tournaments (
    tournament_id INTEGER PRIMARY KEY,
    store_id INTEGER NOT NULL,            -- References stores(store_id) - no FK for DuckDB compat
    event_date DATE NOT NULL,
    event_type VARCHAR NOT NULL,
    format VARCHAR,
    player_count INTEGER,
    rounds INTEGER,
    limitless_id VARCHAR,
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for tournament queries
CREATE INDEX IF NOT EXISTS idx_tournaments_store ON tournaments(store_id);
CREATE INDEX IF NOT EXISTS idx_tournaments_date ON tournaments(event_date);
CREATE INDEX IF NOT EXISTS idx_tournaments_type ON tournaments(event_type);

-- =============================================================================
-- RESULTS TABLE
-- Tracks player results for each tournament
-- Note: FK constraints intentionally omitted - DuckDB UPDATE operations fail
-- on tables with FK constraints because it uses DELETE+INSERT internally.
-- See docs/solutions/duckdb-fk-constraint-fix.md for details.
-- =============================================================================
CREATE TABLE IF NOT EXISTS results (
    result_id INTEGER PRIMARY KEY,
    tournament_id INTEGER NOT NULL,  -- References tournaments(tournament_id)
    player_id INTEGER NOT NULL,      -- References players(player_id)
    archetype_id INTEGER,            -- References deck_archetypes(archetype_id)
    pending_deck_request_id INTEGER, -- Links to pending deck request (for auto-update on approval)
    placement INTEGER,
    wins INTEGER DEFAULT 0,
    losses INTEGER DEFAULT 0,
    ties INTEGER DEFAULT 0,
    decklist_url VARCHAR,  -- Link to external decklist (DeckLog, digimonmeta, etc.)
    decklist_json TEXT,  -- JSON stored as text (for future full decklist storage)
    notes TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(tournament_id, player_id)
);

-- Create indexes for result queries
CREATE INDEX IF NOT EXISTS idx_results_tournament ON results(tournament_id);
CREATE INDEX IF NOT EXISTS idx_results_player ON results(player_id);
CREATE INDEX IF NOT EXISTS idx_results_archetype ON results(archetype_id);
CREATE INDEX IF NOT EXISTS idx_results_placement ON results(placement);
CREATE INDEX IF NOT EXISTS idx_results_pending_deck ON results(pending_deck_request_id);

-- =============================================================================
-- MATCHES TABLE
-- Tracks round-by-round match data from match history screenshots
-- Note: If both players submit match history, we'll have two rows for the
-- same match (from each perspective). This is intentional for simplicity.
-- =============================================================================
CREATE TABLE IF NOT EXISTS matches (
    match_id INTEGER PRIMARY KEY,
    tournament_id INTEGER NOT NULL,    -- References tournaments(tournament_id)
    round_number INTEGER NOT NULL,
    player_id INTEGER NOT NULL,        -- Player who submitted this record
    opponent_id INTEGER NOT NULL,      -- Their opponent
    games_won INTEGER NOT NULL DEFAULT 0,
    games_lost INTEGER NOT NULL DEFAULT 0,
    games_tied INTEGER NOT NULL DEFAULT 0,
    match_points INTEGER NOT NULL DEFAULT 0,  -- 3=win, 1=draw, 0=loss
    submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(tournament_id, round_number, player_id)
);

-- Create indexes for match queries
CREATE INDEX IF NOT EXISTS idx_matches_tournament ON matches(tournament_id);
CREATE INDEX IF NOT EXISTS idx_matches_player ON matches(player_id);
CREATE INDEX IF NOT EXISTS idx_matches_opponent ON matches(opponent_id);

-- =============================================================================
-- DATA INGESTION LOG TABLE
-- Tracks API calls and data imports for debugging
-- =============================================================================
CREATE TABLE IF NOT EXISTS ingestion_log (
    log_id INTEGER PRIMARY KEY,
    source VARCHAR NOT NULL,
    action VARCHAR NOT NULL,
    status VARCHAR NOT NULL,
    records_affected INTEGER DEFAULT 0,
    error_message TEXT,
    metadata TEXT,  -- JSON stored as text
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- PLAYER RATINGS CACHE TABLE
-- Pre-computed player ratings for performance (recomputed on result submission)
-- =============================================================================
CREATE TABLE IF NOT EXISTS player_ratings_cache (
    player_id INTEGER PRIMARY KEY,
    competitive_rating INTEGER NOT NULL DEFAULT 1500,
    achievement_score INTEGER NOT NULL DEFAULT 0,
    events_played INTEGER NOT NULL DEFAULT 0,
    last_computed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- STORE RATINGS CACHE TABLE
-- Pre-computed store ratings for performance (recomputed on result submission)
-- =============================================================================
CREATE TABLE IF NOT EXISTS store_ratings_cache (
    store_id INTEGER PRIMARY KEY,
    avg_player_rating INTEGER NOT NULL DEFAULT 1500,
    last_computed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- =============================================================================
-- RATING SNAPSHOTS TABLE
-- Historical ratings frozen at the end of each format era
-- =============================================================================
CREATE TABLE IF NOT EXISTS rating_snapshots (
    player_id INTEGER NOT NULL,
    format_id VARCHAR NOT NULL,
    competitive_rating INTEGER NOT NULL DEFAULT 1500,
    achievement_score INTEGER NOT NULL DEFAULT 0,
    events_played INTEGER NOT NULL DEFAULT 0,
    player_rank INTEGER,
    snapshot_date DATE NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (player_id, format_id)
);

CREATE INDEX IF NOT EXISTS idx_rating_snapshots_format ON rating_snapshots(format_id);

-- =============================================================================
-- LIMITLESS DECK MAP TABLE
-- Maps Limitless TCG deck archetype identifiers to local deck_archetypes
-- Populated during sync; unmapped decks create deck_requests for admin review
-- =============================================================================
CREATE TABLE IF NOT EXISTS limitless_deck_map (
    limitless_deck_id VARCHAR NOT NULL PRIMARY KEY,  -- e.g., "imperialdramon"
    limitless_deck_name VARCHAR,                     -- Human-readable name from Limitless
    archetype_id INTEGER                             -- References deck_archetypes(archetype_id)
);

-- =============================================================================
-- LIMITLESS SYNC STATE TABLE
-- Tracks per-organizer sync progress for incremental imports
-- =============================================================================
CREATE TABLE IF NOT EXISTS limitless_sync_state (
    organizer_id INTEGER NOT NULL PRIMARY KEY,       -- Limitless organizer ID
    last_synced_at TIMESTAMP,                        -- When sync last ran
    last_tournament_date TIMESTAMP,                  -- Most recent tournament date synced
    tournaments_synced INTEGER DEFAULT 0             -- Total tournaments imported
);

-- =============================================================================
-- ADMIN USERS TABLE
-- Per-user admin accounts with bcrypt password hashes and role-based access
-- Replaces shared ADMIN_PASSWORD/SUPERADMIN_PASSWORD env vars
-- =============================================================================
CREATE TABLE IF NOT EXISTS admin_users (
    user_id INTEGER PRIMARY KEY,
    username TEXT UNIQUE NOT NULL,
    password_hash TEXT NOT NULL,
    display_name TEXT NOT NULL,
    role TEXT NOT NULL DEFAULT 'scene_admin',
    scene_id INTEGER,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_admin_users_username ON admin_users(username);

-- =============================================================================
-- VIEWS FOR COMMON QUERIES
-- =============================================================================

-- Player standings with win rate and favorite deck
CREATE OR REPLACE VIEW player_standings AS
WITH player_deck_counts AS (
    SELECT
        r.player_id,
        r.archetype_id,
        COUNT(*) AS times_played,
        ROW_NUMBER() OVER (PARTITION BY r.player_id ORDER BY COUNT(*) DESC) AS rn
    FROM results r
    WHERE r.archetype_id IS NOT NULL
    GROUP BY r.player_id, r.archetype_id
)
SELECT
    p.player_id,
    p.display_name,
    COUNT(DISTINCT r.tournament_id) AS tournaments_played,
    SUM(r.wins) AS total_wins,
    SUM(r.losses) AS total_losses,
    SUM(r.ties) AS total_ties,
    ROUND(SUM(r.wins) * 100.0 / NULLIF(SUM(r.wins) + SUM(r.losses), 0), 1) AS win_rate,
    ROUND(AVG(r.placement), 2) AS avg_placement,
    COUNT(CASE WHEN r.placement = 1 THEN 1 END) AS first_place_finishes,
    COUNT(CASE WHEN r.placement <= 4 THEN 1 END) AS top4_finishes,
    pdc.archetype_id AS favorite_deck_id,
    da.archetype_name AS favorite_deck
FROM players p
LEFT JOIN results r ON p.player_id = r.player_id
LEFT JOIN player_deck_counts pdc ON p.player_id = pdc.player_id AND pdc.rn = 1
LEFT JOIN deck_archetypes da ON pdc.archetype_id = da.archetype_id
GROUP BY p.player_id, p.display_name, pdc.archetype_id, da.archetype_name;

-- Archetype meta breakdown with secondary color and top4 rate
CREATE OR REPLACE VIEW archetype_meta AS
SELECT
    da.archetype_id,
    da.archetype_name,
    da.primary_color,
    da.secondary_color,
    da.display_card_id,
    COUNT(r.result_id) AS times_played,
    ROUND(AVG(r.placement), 2) AS avg_placement,
    COUNT(CASE WHEN r.placement = 1 THEN 1 END) AS tournament_wins,
    COUNT(CASE WHEN r.placement <= 4 THEN 1 END) AS top4_finishes,
    ROUND(COUNT(CASE WHEN r.placement = 1 THEN 1 END) * 100.0 / NULLIF(COUNT(r.result_id), 0), 1) AS conversion_rate,
    ROUND(COUNT(CASE WHEN r.placement <= 4 THEN 1 END) * 100.0 / NULLIF(COUNT(r.result_id), 0), 1) AS top4_rate,
    SUM(r.wins) AS total_match_wins,
    SUM(r.losses) AS total_match_losses,
    ROUND(SUM(r.wins) * 100.0 / NULLIF(SUM(r.wins) + SUM(r.losses), 0), 1) AS win_rate
FROM deck_archetypes da
LEFT JOIN results r ON da.archetype_id = r.archetype_id
GROUP BY da.archetype_id, da.archetype_name, da.primary_color, da.secondary_color, da.display_card_id;

-- Store activity summary with location and unique players
CREATE OR REPLACE VIEW store_activity AS
SELECT
    s.store_id,
    s.name AS store_name,
    s.city,
    s.latitude,
    s.longitude,
    s.address,
    s.is_online,
    COUNT(DISTINCT t.tournament_id) AS total_tournaments,
    COUNT(DISTINCT r.player_id) AS unique_players,
    SUM(t.player_count) AS total_attendance,
    ROUND(AVG(t.player_count), 1) AS avg_attendance,
    MAX(t.event_date) AS last_event_date,
    MIN(t.event_date) AS first_event_date
FROM stores s
LEFT JOIN tournaments t ON s.store_id = t.store_id
LEFT JOIN results r ON t.tournament_id = r.tournament_id
WHERE s.is_active = TRUE
GROUP BY s.store_id, s.name, s.city, s.latitude, s.longitude, s.address, s.is_online;
