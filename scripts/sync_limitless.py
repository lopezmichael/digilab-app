"""
Sync LimitlessTCG Tournament Data to Database

Fetches tournament data from the LimitlessTCG API and imports it into the
DigiLab PostgreSQL database (Neon). Handles players, results, matches, and
deck mapping.

Usage:
    python scripts/sync_limitless.py --organizer 452 --since 2025-10-01
    python scripts/sync_limitless.py --organizer 452 --since 2025-10-01 --dry-run
    python scripts/sync_limitless.py --all-tier1 --since 2025-10-01
    python scripts/sync_limitless.py --all-tier1 --incremental  (use last sync date)
    python scripts/sync_limitless.py --all-tier1 --incremental --classify  (+ auto-classify)
    python scripts/sync_limitless.py --all-tier1 --since 2025-10-01 --limit 5
    python scripts/sync_limitless.py --repair  (re-fetch missing standings)
    python scripts/sync_limitless.py --all-tier1 --since 2025-01-01 --clean  (fresh re-import)

Arguments:
    --organizer ID     Limitless organizer ID to sync
    --all-tier1        Sync all Tier 1 organizers (452, 281, 559, 578)
    --since DATE       Only sync tournaments on or after this date (YYYY-MM-DD)
    --incremental      Auto-detect since date from last sync (stored in limitless_sync_state)
    --classify         Run deck archetype auto-classification after sync
    --dry-run          Show what would be synced without writing to DB
    --limit N          Max tournaments to sync (useful for testing)
    --repair           Re-fetch standings/pairings for tournaments missing results
    --clean            Delete existing Limitless data before sync (for fresh re-import)

Prerequisites:
    pip install psycopg2-binary python-dotenv requests
    NEON_HOST and NEON_PASSWORD env vars required (in .env file)
    Stores with limitless_organizer_id must exist in database before syncing
"""

import os
import re
import sys
import time
import json
import argparse
import requests
import psycopg2
from psycopg2.extras import execute_values
from datetime import datetime, timedelta
from dotenv import load_dotenv

load_dotenv()

# =============================================================================
# Configuration
# =============================================================================

API_BASE = "https://play.limitlesstcg.com/api"
REQUEST_DELAY = 1.5  # seconds between API calls

# Tier 1 organizers for --all-tier1 flag
# These are high-quality organizers with good deck coverage (50%+ decklists)
TIER1_ORGANIZERS = {
    452: "Eagle's Nest",
    281: "PHOENIX REBORN",
    559: "DMV Drakes",
    578: "MasterRukasu",
}


# =============================================================================
# Database Connection
# =============================================================================

def get_connection():
    """Connect to Neon PostgreSQL."""
    host = os.getenv("NEON_HOST")
    dbname = os.getenv("NEON_DATABASE", "neondb")
    user = os.getenv("NEON_USER")
    password = os.getenv("NEON_PASSWORD")

    if not host or not password:
        print("Error: NEON_HOST and NEON_PASSWORD env vars required")
        sys.exit(1)

    return psycopg2.connect(
        host=host,
        dbname=dbname,
        user=user,
        password=password,
        port=5432,
        sslmode="require"
    )


# =============================================================================
# API Client
# =============================================================================

def api_get(endpoint, params=None):
    """Make a GET request to the Limitless TCG API with rate limiting.

    Args:
        endpoint: API endpoint path (e.g., "/tournaments")
        params: Optional query parameters dict

    Returns:
        Parsed JSON response, or None on error
    """
    url = f"{API_BASE}{endpoint}"
    headers = {
        "User-Agent": "DigiLab/1.0 (LimitlessSync)",
        "Accept": "application/json",
    }

    try:
        response = requests.get(url, params=params, headers=headers, timeout=30)

        # Check rate limit headers
        remaining = response.headers.get("X-RateLimit-Remaining")
        if remaining is not None:
            remaining = int(remaining)
            if remaining < 5:
                print(f"    [Rate limit] Only {remaining} requests remaining, pausing 5s...")
                time.sleep(5)
            elif remaining < 20:
                print(f"    [Rate limit] {remaining} requests remaining, pausing 2s...")
                time.sleep(2)

        if response.status_code == 404:
            return None

        if response.status_code != 200:
            print(f"    API error: HTTP {response.status_code} for {endpoint}")
            return None

        return response.json()

    except requests.exceptions.Timeout:
        print(f"    API timeout for {endpoint}")
        return None
    except requests.exceptions.RequestException as e:
        print(f"    API request failed for {endpoint}: {e}")
        return None
    except json.JSONDecodeError:
        print(f"    API returned invalid JSON for {endpoint}")
        return None


def fetch_tournaments_for_organizer(organizer_id, since_date=None):
    """Fetch all DCG tournaments for an organizer, paginated.

    Args:
        organizer_id: Limitless organizer ID
        since_date: Only return tournaments on or after this date (YYYY-MM-DD string)

    Returns:
        List of tournament dicts from the API
    """
    all_tournaments = []
    page = 1

    while True:
        print(f"    Fetching tournament list page {page}...", end=" ", flush=True)
        data = api_get("/tournaments", params={
            "game": "DCG",
            "organizerId": organizer_id,
            "limit": 50,
            "page": page,
        })
        time.sleep(REQUEST_DELAY)

        if data is None or len(data) == 0:
            print("done (no more pages)")
            break

        print(f"got {len(data)} tournaments")

        for t in data:
            # Filter by date if specified
            event_date = t.get("date", "")
            if since_date and event_date < since_date:
                continue
            all_tournaments.append(t)

        # If we got fewer than 50, we've reached the last page
        if len(data) < 50:
            break

        page += 1

    return all_tournaments


def fetch_tournament_details(tournament_id):
    """Fetch detailed info for a single tournament.

    Returns:
        Tournament details dict, or None on error
    """
    data = api_get(f"/tournaments/{tournament_id}/details")
    time.sleep(REQUEST_DELAY)
    return data


def fetch_tournament_standings(tournament_id):
    """Fetch standings/results for a tournament.

    Returns:
        List of standing dicts, or empty list on error
    """
    data = api_get(f"/tournaments/{tournament_id}/standings")
    time.sleep(REQUEST_DELAY)
    return data if data is not None else []


def fetch_tournament_pairings(tournament_id):
    """Fetch round-by-round pairings for a tournament.

    Returns:
        List of pairing dicts, or empty list on error
    """
    data = api_get(f"/tournaments/{tournament_id}/pairings")
    time.sleep(REQUEST_DELAY)
    return data if data is not None else []


# =============================================================================
# Format Inference
# =============================================================================

def infer_format(tournament_name, event_date, cursor):
    """Infer format from tournament name or date.

    Strategy 1: Parse set code from tournament name (e.g., "BT19 Weekly")
    Strategy 2: Fall back to most recent format by release date

    Args:
        tournament_name: Tournament name string
        event_date: Event date string (YYYY-MM-DD)
        cursor: psycopg2 cursor

    Returns:
        Format ID string (e.g., "BT19") or None
    """
    # Strategy 1: Parse from name
    match = re.search(r'(BT)-?(\d+)|(EX)-?(\d+)', tournament_name, re.IGNORECASE)
    if match:
        if match.group(1):  # BT match
            return f"BT{match.group(2)}"
        else:  # EX match
            return f"EX{match.group(4)}"

    # Strategy 2: Date-based fallback
    try:
        cursor.execute("""
            SELECT format_id FROM formats
            WHERE release_date <= %s
            ORDER BY release_date DESC
            LIMIT 1
        """, (event_date,))
        result = cursor.fetchone()
        return result[0] if result else None
    except Exception as e:
        print(f"    Warning: Could not infer format from date: {e}")
        return None


# =============================================================================
# Player Resolution
# =============================================================================

def resolve_player(cursor, limitless_username, display_name, player_cache):
    """Find or create a player by Limitless username.

    Args:
        cursor: psycopg2 cursor
        limitless_username: Limitless username string
        display_name: Player's display name from Limitless
        player_cache: Dict mapping limitless_username -> player_id (updated in place)

    Returns:
        player_id integer
    """
    # Check cache first
    if limitless_username in player_cache:
        return player_cache[limitless_username]

    # Check database by limitless_username
    cursor.execute(
        "SELECT player_id FROM players WHERE limitless_username = %s",
        (limitless_username,)
    )
    row = cursor.fetchone()

    if row:
        player_cache[limitless_username] = row[0]
        return row[0]

    # Create new player (let PostgreSQL generate player_id via IDENTITY)
    cursor.execute("""
        INSERT INTO players (display_name, limitless_username, is_active)
        VALUES (%s, %s, TRUE)
        RETURNING player_id
    """, (display_name, limitless_username))
    new_id = cursor.fetchone()[0]

    player_cache[limitless_username] = new_id
    return new_id


# =============================================================================
# Deck Mapping
# =============================================================================

# UNKNOWN archetype ID - used for "other" deck type and unmapped decks
UNKNOWN_ARCHETYPE_ID = 50


def resolve_deck(cursor, deck_info, deck_map_cache):
    """Map a Limitless deck to a local archetype, creating deck_request if needed.

    Args:
        cursor: psycopg2 cursor
        deck_info: Deck dict from Limitless standing (may have 'id' and 'name')
        deck_map_cache: Dict mapping limitless_deck_id -> archetype_id or None

    Returns:
        Tuple of (archetype_id or None, pending_deck_request_id or None)
    """
    if not deck_info:
        return None, None

    deck_id = deck_info.get("id")
    deck_name = deck_info.get("name", "Unknown")

    if not deck_id:
        return None, None

    # Map "other" deck to UNKNOWN archetype (no deck request needed)
    if deck_id == "other":
        return UNKNOWN_ARCHETYPE_ID, None

    # Check cache
    if deck_id in deck_map_cache:
        return deck_map_cache[deck_id], None

    # Check limitless_deck_map table
    cursor.execute(
        "SELECT archetype_id FROM limitless_deck_map WHERE limitless_deck_id = %s",
        (deck_id,)
    )
    row = cursor.fetchone()

    if row:
        # Entry exists in map
        archetype_id = row[0]  # May be None if not yet mapped
        deck_map_cache[deck_id] = archetype_id
        return archetype_id, None

    # Not in map at all — insert with null archetype and create deck request
    cursor.execute("""
        INSERT INTO limitless_deck_map (limitless_deck_id, limitless_deck_name, archetype_id)
        VALUES (%s, %s, NULL)
    """, (deck_id, deck_name))

    # Create a deck request for admin review
    cursor.execute("""
        INSERT INTO deck_requests (deck_name, primary_color, status, submitted_at)
        VALUES (%s, 'Unknown', 'pending', CURRENT_TIMESTAMP)
        RETURNING request_id
    """, (f"[Limitless] {deck_name}",))
    next_request_id = cursor.fetchone()[0]

    deck_map_cache[deck_id] = None
    return None, next_request_id


# =============================================================================
# Tournament Sync
# =============================================================================

def count_total_rounds(details):
    """Count total rounds across all phases in tournament details.

    Args:
        details: Tournament details dict from API

    Returns:
        Total round count integer, or None if can't determine
    """
    phases = details.get("phases", [])
    if not phases:
        return None

    total_rounds = 0
    for phase in phases:
        rounds_in_phase = phase.get("rounds", 0)
        if isinstance(rounds_in_phase, int):
            total_rounds += rounds_in_phase
        elif isinstance(rounds_in_phase, list):
            total_rounds += len(rounds_in_phase)

    return total_rounds if total_rounds > 0 else None


def sync_tournament(cursor, tournament, organizer_id, store_id, dry_run=False):
    """Sync a single tournament: details, standings, pairings.

    Args:
        cursor: psycopg2 cursor
        tournament: Tournament dict from API listing
        organizer_id: Limitless organizer ID
        store_id: Local store_id to associate with
        dry_run: If True, only print what would happen

    Returns:
        Dict with sync stats, or None if skipped
    """
    limitless_id = str(tournament.get("id", ""))
    tournament_name = tournament.get("name", "Unknown Tournament")
    event_date = tournament.get("date", "")
    player_count = tournament.get("players", 0)

    print(f"\n  --- {tournament_name} ({event_date}) ---")
    print(f"      Limitless ID: {limitless_id}, Players: {player_count}")

    # Check if already synced
    cursor.execute(
        "SELECT tournament_id FROM tournaments WHERE limitless_id = %s",
        (limitless_id,)
    )
    existing = cursor.fetchone()

    if existing:
        print("      SKIPPED: Already synced")
        return None

    # Skip small tournaments
    if player_count and player_count < 4:
        print(f"      SKIPPED: Too few players ({player_count} < 4)")
        return None

    # Fetch details
    print("      Fetching details...", end=" ", flush=True)
    details = fetch_tournament_details(limitless_id)
    if details is None:
        print("FAILED")
        return None
    print("OK")

    # Count rounds from phases
    total_rounds = count_total_rounds(details)

    # Infer format
    format_id = infer_format(tournament_name, event_date, cursor)
    print(f"      Format: {format_id or '(unknown)'}, Rounds: {total_rounds or '(unknown)'}")

    if dry_run:
        print("      [DRY RUN] Would insert tournament, fetching standings for preview...")
        standings = fetch_tournament_standings(limitless_id)
        print(f"      [DRY RUN] Would process {len(standings)} standings")
        pairings = fetch_tournament_pairings(limitless_id)
        print(f"      [DRY RUN] Would process {len(pairings)} pairings")
        return {
            "tournament_name": tournament_name,
            "players": len(standings),
            "pairings": len(pairings),
            "dry_run": True,
        }

    # Fetch standings before inserting tournament (to check deck coverage)
    print("      Fetching standings...", end=" ", flush=True)
    standings = fetch_tournament_standings(limitless_id)
    print(f"got {len(standings)}")

    # Check deck coverage — skip tournaments where top 3 have no deck data
    if standings:
        top_3 = [s for s in standings if s.get("placing") and s["placing"] <= 3]
        top_3_with_deck = sum(1 for s in top_3 if s.get("deck") and s["deck"].get("id"))
        if top_3 and top_3_with_deck == 0:
            print(f"      SKIPPED: No deck data for top 3 players (tournament doesn't track decks)")
            return None

    # Insert tournament (let PostgreSQL generate tournament_id via IDENTITY)
    cursor.execute("""
        INSERT INTO tournaments
            (store_id, event_date, event_type, format, player_count,
             rounds, limitless_id, notes, created_at, updated_at)
        VALUES (%s, %s, 'online', %s, %s, %s, %s, %s, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        RETURNING tournament_id
    """, (
        store_id,
        event_date,
        format_id,
        player_count,
        total_rounds,
        limitless_id,
        f"Imported from Limitless TCG (organizer {organizer_id})",
    ))
    next_tournament_id = cursor.fetchone()[0]

    print(f"      Inserted tournament_id={next_tournament_id}")

    player_cache = {}  # limitless_username -> player_id
    deck_map_cache = {}  # limitless_deck_id -> archetype_id or None
    results_inserted = 0
    players_created = 0
    deck_requests_created = 0

    # Pre-load player cache with existing limitless usernames
    cursor.execute(
        "SELECT limitless_username, player_id FROM players WHERE limitless_username IS NOT NULL"
    )
    existing_players = cursor.fetchall()
    for row in existing_players:
        player_cache[row[0]] = row[1]

    # Pre-load deck map cache
    cursor.execute(
        "SELECT limitless_deck_id, archetype_id FROM limitless_deck_map"
    )
    existing_maps = cursor.fetchall()
    for row in existing_maps:
        deck_map_cache[row[0]] = row[1]

    players_before = len(player_cache)

    for standing in standings:
        limitless_username = standing.get("player", "")
        display_name = standing.get("name", limitless_username)
        placement = standing.get("placing")
        record = standing.get("record", {})
        wins = record.get("wins", 0)
        losses = record.get("losses", 0)
        ties = record.get("ties", 0)
        deck_info = standing.get("deck")
        decklist_info = standing.get("decklist")  # Full decklist with cards
        drop_info = standing.get("drop")

        if not limitless_username:
            continue

        # Resolve player
        player_id = resolve_player(cursor, limitless_username, display_name, player_cache)

        # Resolve deck — default to UNKNOWN if no deck info available
        archetype_id, pending_request_id = resolve_deck(cursor, deck_info, deck_map_cache)
        if archetype_id is None and pending_request_id is None:
            archetype_id = UNKNOWN_ARCHETYPE_ID
        if pending_request_id:
            deck_requests_created += 1

        # Build notes
        notes = None
        if drop_info:
            notes = f"Dropped at round {drop_info}" if isinstance(drop_info, int) else f"Dropped: {drop_info}"

        # Build decklist JSON (full card list from API)
        decklist_json = None
        if decklist_info and any(decklist_info.get(k) for k in ["digimon", "tamer", "option", "egg"]):
            decklist_json = json.dumps(decklist_info)

        # Build Limitless decklist URL
        decklist_url = f"https://play.limitlesstcg.com/tournament/{limitless_id}/player/{limitless_username}/decklist" if decklist_json else None

        # Insert result (let PostgreSQL generate result_id via IDENTITY)
        try:
            cursor.execute("""
                INSERT INTO results
                    (tournament_id, player_id, archetype_id, pending_deck_request_id,
                     placement, wins, losses, ties, decklist_json, decklist_url, notes,
                     created_at, updated_at)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
            """, (
                next_tournament_id,
                player_id,
                archetype_id,
                pending_request_id,
                placement,
                wins,
                losses,
                ties,
                decklist_json,
                decklist_url,
                notes,
            ))
            results_inserted += 1
        except Exception as e:
            if "unique" in str(e).lower() or "duplicate" in str(e).lower():
                print(f"      Warning: Duplicate result for player {limitless_username}, skipping")
            else:
                print(f"      Error inserting result for {limitless_username}: {e}")

    players_created = len(player_cache) - players_before
    print(f"      Results: {results_inserted} inserted, {players_created} new players, {deck_requests_created} deck requests")

    # Process pairings
    print("      Fetching pairings...", end=" ", flush=True)
    pairings = fetch_tournament_pairings(limitless_id)
    print(f"got {len(pairings)}")

    matches_inserted = 0

    for pairing in pairings:
        round_number = pairing.get("round")
        player1_username = pairing.get("player1", "")
        player2_username = pairing.get("player2", "")
        winner = str(pairing.get("winner", ""))

        # Skip BYE pairings (no opponent)
        if not player2_username:
            continue

        # Both players must be in cache (they were created during standings processing)
        if player1_username not in player_cache:
            continue
        if player2_username not in player_cache:
            continue

        player1_id = player_cache[player1_username]
        player2_id = player_cache[player2_username]

        # Derive match points from winner field
        if winner == player1_username:
            p1_points, p2_points = 3, 0
        elif winner == player2_username:
            p1_points, p2_points = 0, 3
        elif winner == "0":
            # Tie
            p1_points, p2_points = 1, 1
        elif winner == "-1":
            # Double loss
            p1_points, p2_points = 0, 0
        else:
            # Unknown winner value — treat as tie
            p1_points, p2_points = 1, 1

        # Insert two match rows (one per player perspective)
        cursor.execute(
            "SELECT COALESCE(MAX(match_id), 0) + 1 FROM matches"
        )
        next_match_id = cursor.fetchone()[0]

        try:
            # Player 1's perspective
            cursor.execute("""
                INSERT INTO matches
                    (match_id, tournament_id, round_number, player_id, opponent_id,
                     games_won, games_lost, games_tied, match_points, submitted_at)
                VALUES (%s, %s, %s, %s, %s, 0, 0, 0, %s, CURRENT_TIMESTAMP)
            """, (next_match_id, next_tournament_id, round_number, player1_id, player2_id, p1_points))

            # Player 2's perspective
            cursor.execute("""
                INSERT INTO matches
                    (match_id, tournament_id, round_number, player_id, opponent_id,
                     games_won, games_lost, games_tied, match_points, submitted_at)
                VALUES (%s, %s, %s, %s, %s, 0, 0, 0, %s, CURRENT_TIMESTAMP)
            """, (next_match_id + 1, next_tournament_id, round_number, player2_id, player1_id, p2_points))

            matches_inserted += 2
        except Exception as e:
            if "unique" in str(e).lower() or "duplicate" in str(e).lower():
                pass  # Duplicate pairing, skip silently
            else:
                print(f"      Error inserting match R{round_number} {player1_username} vs {player2_username}: {e}")

    print(f"      Matches: {matches_inserted} rows inserted ({matches_inserted // 2} pairings)")

    return {
        "tournament_name": tournament_name,
        "tournament_id": next_tournament_id,
        "event_date": event_date,
        "players": results_inserted,
        "players_created": players_created,
        "matches": matches_inserted,
        "deck_requests": deck_requests_created,
        "dry_run": False,
    }


# =============================================================================
# Sync State Management
# =============================================================================

def update_sync_state(cursor, organizer_id, tournaments_synced, last_tournament_date):
    """Update or insert the sync state for an organizer.

    Args:
        cursor: psycopg2 cursor
        organizer_id: Limitless organizer ID
        tournaments_synced: Number of tournaments synced in this run
        last_tournament_date: Date string of the most recent tournament synced
    """
    cursor.execute(
        "SELECT organizer_id FROM limitless_sync_state WHERE organizer_id = %s",
        (organizer_id,)
    )
    existing = cursor.fetchone()

    if existing:
        cursor.execute("""
            UPDATE limitless_sync_state
            SET last_synced_at = CURRENT_TIMESTAMP,
                last_tournament_date = %s,
                tournaments_synced = tournaments_synced + %s
            WHERE organizer_id = %s
        """, (last_tournament_date, tournaments_synced, organizer_id))
    else:
        cursor.execute("""
            INSERT INTO limitless_sync_state
                (organizer_id, last_synced_at, last_tournament_date, tournaments_synced)
            VALUES (%s, CURRENT_TIMESTAMP, %s, %s)
        """, (organizer_id, last_tournament_date, tournaments_synced))


def log_ingestion(cursor, organizer_id, action, status, records_affected, error_message=None, metadata=None):
    """Write an entry to the ingestion_log table.

    Args:
        cursor: psycopg2 cursor
        organizer_id: Limitless organizer ID
        action: Action description
        status: 'success' or 'error'
        records_affected: Number of records processed
        error_message: Optional error message
        metadata: Optional metadata dict (will be JSON-serialized)
    """
    cursor.execute(
        "SELECT COALESCE(MAX(log_id), 0) + 1 FROM ingestion_log"
    )
    next_log_id = cursor.fetchone()[0]

    metadata_str = json.dumps(metadata) if metadata else None

    cursor.execute("""
        INSERT INTO ingestion_log
            (log_id, source, action, status, records_affected, error_message, metadata, created_at)
        VALUES (%s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
    """, (
        next_log_id,
        f"limitless_organizer_{organizer_id}",
        action,
        status,
        records_affected,
        error_message,
        metadata_str,
    ))


# =============================================================================
# Organizer Sync Orchestration
# =============================================================================

def sync_organizer(conn, cursor, organizer_id, since_date, dry_run=False, limit=None):
    """Sync all tournaments for an organizer.

    Args:
        conn: psycopg2 connection (for commits)
        cursor: psycopg2 cursor
        organizer_id: Limitless organizer ID
        since_date: Only sync tournaments on or after this date (YYYY-MM-DD)
        dry_run: If True, don't write to database
        limit: Max tournaments to sync (None for unlimited)

    Returns:
        Dict with overall sync stats
    """
    organizer_name = TIER1_ORGANIZERS.get(organizer_id, f"Organizer {organizer_id}")
    print(f"\n{'=' * 60}")
    print(f"Syncing: {organizer_name} (ID: {organizer_id})")
    print(f"{'=' * 60}")

    # Resolve store
    cursor.execute(
        "SELECT store_id, name FROM stores WHERE limitless_organizer_id = %s",
        (organizer_id,)
    )
    store_row = cursor.fetchone()

    if not store_row:
        print(f"  ERROR: No store found with limitless_organizer_id = {organizer_id}")
        print(f"  Create the store in the admin panel first, then set its limitless_organizer_id.")
        if not dry_run:
            log_ingestion(cursor, organizer_id, "sync", "error", 0,
                          f"No store found for organizer {organizer_id}")
            conn.commit()
        return {"error": f"No store for organizer {organizer_id}"}

    store_id = store_row[0]
    store_name = store_row[1]
    print(f"  Store: {store_name} (store_id={store_id})")

    # Fetch tournament list
    print(f"  Fetching tournaments since {since_date}...")
    tournaments = fetch_tournaments_for_organizer(organizer_id, since_date)
    print(f"  Found {len(tournaments)} tournaments to process")

    if limit and len(tournaments) > limit:
        print(f"  Limiting to {limit} tournaments (--limit flag)")
        tournaments = tournaments[:limit]

    # Sync each tournament
    stats = {
        "organizer_id": organizer_id,
        "organizer_name": organizer_name,
        "tournaments_found": len(tournaments),
        "tournaments_synced": 0,
        "tournaments_skipped": 0,
        "total_results": 0,
        "total_matches": 0,
        "total_players_created": 0,
        "total_deck_requests": 0,
        "last_tournament_date": None,
    }

    for tournament in tournaments:
        try:
            result = sync_tournament(cursor, tournament, organizer_id, store_id, dry_run)

            if result is None:
                stats["tournaments_skipped"] += 1
            else:
                stats["tournaments_synced"] += 1
                stats["total_results"] += result.get("players", 0)
                stats["total_matches"] += result.get("matches", 0)
                stats["total_players_created"] += result.get("players_created", 0)
                stats["total_deck_requests"] += result.get("deck_requests", 0)

                event_date = result.get("event_date") or tournament.get("date")
                if event_date:
                    if stats["last_tournament_date"] is None or event_date > stats["last_tournament_date"]:
                        stats["last_tournament_date"] = event_date

            # Commit after each tournament to avoid losing progress
            if not dry_run:
                conn.commit()

        except Exception as e:
            print(f"      ERROR syncing tournament: {e}")
            conn.rollback()
            stats["tournaments_skipped"] += 1
            if not dry_run:
                log_ingestion(cursor, organizer_id, "sync_tournament", "error", 0,
                              str(e), {"tournament_id": tournament.get("id")})
                conn.commit()

    # Update sync state and log
    if not dry_run and stats["tournaments_synced"] > 0:
        update_sync_state(cursor, organizer_id,
                          stats["tournaments_synced"],
                          stats["last_tournament_date"])

        log_ingestion(cursor, organizer_id, "sync", "success",
                      stats["total_results"],
                      metadata={
                          "tournaments_synced": stats["tournaments_synced"],
                          "tournaments_skipped": stats["tournaments_skipped"],
                          "players_created": stats["total_players_created"],
                          "deck_requests_created": stats["total_deck_requests"],
                      })
        conn.commit()

    # Print summary for this organizer
    print(f"\n  Summary for {organizer_name}:")
    print(f"    Tournaments synced: {stats['tournaments_synced']}")
    print(f"    Tournaments skipped: {stats['tournaments_skipped']}")
    print(f"    Results inserted: {stats['total_results']}")
    print(f"    Matches inserted: {stats['total_matches']}")
    print(f"    New players created: {stats['total_players_created']}")
    print(f"    Deck requests created: {stats['total_deck_requests']}")

    return stats


# =============================================================================
# Repair Mode
# =============================================================================

def repair_tournament(cursor, tournament_id, limitless_id):
    """Re-fetch standings and pairings for a tournament missing results.

    Args:
        cursor: psycopg2 cursor
        tournament_id: Local tournament ID
        limitless_id: Limitless tournament ID

    Returns:
        Dict with repair stats
    """
    print(f"\n  --- Repairing tournament_id={tournament_id} (limitless: {limitless_id}) ---")

    player_cache = {}
    deck_map_cache = {}

    # Pre-load player cache
    cursor.execute(
        "SELECT limitless_username, player_id FROM players WHERE limitless_username IS NOT NULL"
    )
    existing_players = cursor.fetchall()
    for row in existing_players:
        player_cache[row[0]] = row[1]

    # Pre-load deck map cache
    cursor.execute(
        "SELECT limitless_deck_id, archetype_id FROM limitless_deck_map"
    )
    existing_maps = cursor.fetchall()
    for row in existing_maps:
        deck_map_cache[row[0]] = row[1]

    results_inserted = 0
    players_created = 0
    deck_requests_created = 0
    matches_inserted = 0
    players_before = len(player_cache)

    # Fetch and process standings
    print("      Fetching standings...", end=" ", flush=True)
    standings = fetch_tournament_standings(limitless_id)
    print(f"got {len(standings)}")

    if len(standings) == 0:
        print("      No standings returned (still rate limited?)")
        return {"results": 0, "matches": 0, "error": "No standings"}

    for standing in standings:
        limitless_username = standing.get("player", "")
        display_name = standing.get("name", limitless_username)
        placement = standing.get("placing")
        record = standing.get("record", {})
        wins = record.get("wins", 0)
        losses = record.get("losses", 0)
        ties = record.get("ties", 0)
        deck_info = standing.get("deck")
        drop_info = standing.get("drop")

        if not limitless_username:
            continue

        # Resolve player
        player_id = resolve_player(cursor, limitless_username, display_name, player_cache)

        # Resolve deck — default to UNKNOWN if no deck info available
        archetype_id, pending_request_id = resolve_deck(cursor, deck_info, deck_map_cache)
        if archetype_id is None and pending_request_id is None:
            archetype_id = UNKNOWN_ARCHETYPE_ID
        if pending_request_id:
            deck_requests_created += 1

        # Build notes
        notes = None
        if drop_info:
            notes = f"Dropped at round {drop_info}" if isinstance(drop_info, int) else f"Dropped: {drop_info}"

        # Check if result already exists
        cursor.execute(
            "SELECT result_id FROM results WHERE tournament_id = %s AND player_id = %s",
            (tournament_id, player_id)
        )
        existing = cursor.fetchone()

        if existing:
            continue  # Already have this result

        # Insert result (let PostgreSQL generate result_id via IDENTITY)
        try:
            cursor.execute("""
                INSERT INTO results
                    (tournament_id, player_id, archetype_id, pending_deck_request_id,
                     placement, wins, losses, ties, notes, created_at, updated_at)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
            """, (
                tournament_id,
                player_id,
                archetype_id,
                pending_request_id,
                placement,
                wins,
                losses,
                ties,
                notes,
            ))
            results_inserted += 1
        except Exception as e:
            if "unique" not in str(e).lower() and "duplicate" not in str(e).lower():
                print(f"      Error inserting result for {limitless_username}: {e}")

    players_created = len(player_cache) - players_before
    print(f"      Results: {results_inserted} inserted, {players_created} new players, {deck_requests_created} deck requests")

    # Fetch and process pairings
    print("      Fetching pairings...", end=" ", flush=True)
    pairings = fetch_tournament_pairings(limitless_id)
    print(f"got {len(pairings)}")

    for pairing in pairings:
        round_number = pairing.get("round")
        player1_username = pairing.get("player1", "")
        player2_username = pairing.get("player2", "")
        winner = str(pairing.get("winner", ""))

        if not player2_username:
            continue

        if player1_username not in player_cache or player2_username not in player_cache:
            continue

        player1_id = player_cache[player1_username]
        player2_id = player_cache[player2_username]

        # Check if match already exists
        cursor.execute(
            "SELECT match_id FROM matches WHERE tournament_id = %s AND round_number = %s AND player_id = %s AND opponent_id = %s",
            (tournament_id, round_number, player1_id, player2_id)
        )
        existing = cursor.fetchone()

        if existing:
            continue

        # Derive match points
        if winner == player1_username:
            p1_points, p2_points = 3, 0
        elif winner == player2_username:
            p1_points, p2_points = 0, 3
        elif winner == "0":
            p1_points, p2_points = 1, 1
        elif winner == "-1":
            p1_points, p2_points = 0, 0
        else:
            p1_points, p2_points = 1, 1

        cursor.execute(
            "SELECT COALESCE(MAX(match_id), 0) + 1 FROM matches"
        )
        next_match_id = cursor.fetchone()[0]

        try:
            cursor.execute("""
                INSERT INTO matches
                    (match_id, tournament_id, round_number, player_id, opponent_id,
                     games_won, games_lost, games_tied, match_points, submitted_at)
                VALUES (%s, %s, %s, %s, %s, 0, 0, 0, %s, CURRENT_TIMESTAMP)
            """, (next_match_id, tournament_id, round_number, player1_id, player2_id, p1_points))

            cursor.execute("""
                INSERT INTO matches
                    (match_id, tournament_id, round_number, player_id, opponent_id,
                     games_won, games_lost, games_tied, match_points, submitted_at)
                VALUES (%s, %s, %s, %s, %s, 0, 0, 0, %s, CURRENT_TIMESTAMP)
            """, (next_match_id + 1, tournament_id, round_number, player2_id, player1_id, p2_points))

            matches_inserted += 2
        except Exception as e:
            if "unique" not in str(e).lower() and "duplicate" not in str(e).lower():
                print(f"      Error inserting match: {e}")

    print(f"      Matches: {matches_inserted} rows inserted ({matches_inserted // 2} pairings)")

    return {
        "results": results_inserted,
        "matches": matches_inserted,
        "players_created": players_created,
        "deck_requests": deck_requests_created,
    }


def run_repair_mode(conn, cursor):
    """Find and repair tournaments with missing results/pairings.

    Args:
        conn: psycopg2 connection (for commits)
        cursor: psycopg2 cursor

    Returns:
        Dict with overall repair stats
    """
    print("\n" + "=" * 60)
    print("REPAIR MODE: Finding tournaments with missing data")
    print("=" * 60)

    # Find tournaments with limitless_id but 0 results
    cursor.execute("""
        SELECT t.tournament_id, t.limitless_id, t.player_count, t.event_date,
               COUNT(r.result_id) as result_count
        FROM tournaments t
        LEFT JOIN results r ON t.tournament_id = r.tournament_id
        WHERE t.limitless_id IS NOT NULL
        GROUP BY t.tournament_id, t.limitless_id, t.player_count, t.event_date
        HAVING COUNT(r.result_id) = 0
        ORDER BY t.event_date DESC
    """)
    missing_results = cursor.fetchall()

    # Find tournaments with results but 0 matches
    cursor.execute("""
        SELECT t.tournament_id, t.limitless_id, t.player_count, t.event_date,
               COUNT(r.result_id) as result_count, COUNT(m.match_id) as match_count
        FROM tournaments t
        LEFT JOIN results r ON t.tournament_id = r.tournament_id
        LEFT JOIN matches m ON t.tournament_id = m.tournament_id
        WHERE t.limitless_id IS NOT NULL
        GROUP BY t.tournament_id, t.limitless_id, t.player_count, t.event_date
        HAVING COUNT(r.result_id) > 0 AND COUNT(m.match_id) = 0
        ORDER BY t.event_date DESC
    """)
    missing_matches = cursor.fetchall()

    print(f"\nTournaments missing results: {len(missing_results)}")
    for t in missing_results:
        print(f"  t{t[0]} | {t[1][:20]}... | {t[2]} players | {t[3]}")

    print(f"\nTournaments missing matches (have results): {len(missing_matches)}")
    for t in missing_matches:
        print(f"  t{t[0]} | {t[1][:20]}... | {t[4]} results, 0 matches | {t[3]}")

    if not missing_results and not missing_matches:
        print("\nNo tournaments need repair!")
        return {"repaired": 0}

    print(f"\nRepairing {len(missing_results) + len(missing_matches)} tournaments...")

    total_results = 0
    total_matches = 0
    total_players = 0
    total_decks = 0
    repaired = 0

    # Repair tournaments missing results
    for t in missing_results:
        tournament_id, limitless_id = t[0], t[1]
        stats = repair_tournament(cursor, tournament_id, limitless_id)
        if stats.get("results", 0) > 0 or stats.get("matches", 0) > 0:
            repaired += 1
            total_results += stats.get("results", 0)
            total_matches += stats.get("matches", 0)
            total_players += stats.get("players_created", 0)
            total_decks += stats.get("deck_requests", 0)
        conn.commit()

    # Repair tournaments missing only matches
    for t in missing_matches:
        tournament_id, limitless_id = t[0], t[1]
        stats = repair_tournament(cursor, tournament_id, limitless_id)
        if stats.get("matches", 0) > 0:
            repaired += 1
            total_matches += stats.get("matches", 0)
        conn.commit()

    print("\n" + "=" * 60)
    print("REPAIR COMPLETE")
    print("=" * 60)
    print(f"Tournaments repaired: {repaired}")
    print(f"Results inserted: {total_results}")
    print(f"Matches inserted: {total_matches}")
    print(f"New players: {total_players}")
    print(f"Deck requests: {total_decks}")

    return {
        "repaired": repaired,
        "results": total_results,
        "matches": total_matches,
        "players": total_players,
        "deck_requests": total_decks,
    }


# =============================================================================
# Clean Mode
# =============================================================================

def clean_limitless_data(conn, cursor, organizer_ids=None):
    """Delete all Limitless-imported data for a fresh re-sync.

    Args:
        conn: psycopg2 connection (for commits)
        cursor: psycopg2 cursor
        organizer_ids: Optional list of organizer IDs to clean (None = all Limitless data)
    """
    if organizer_ids:
        # Get store_ids for these organizers
        placeholders = ",".join(["%s" for _ in organizer_ids])
        cursor.execute(f"""
            SELECT store_id FROM stores
            WHERE limitless_organizer_id IN ({placeholders})
        """, organizer_ids)
        store_ids = [r[0] for r in cursor.fetchall()]

        if not store_ids:
            print("  No stores found for specified organizers")
            return

        store_placeholders = ",".join(["%s" for _ in store_ids])

        # Get tournament_ids for these stores
        cursor.execute(f"""
            SELECT tournament_id FROM tournaments
            WHERE store_id IN ({store_placeholders})
            AND limitless_id IS NOT NULL
        """, store_ids)
        tournament_ids = [r[0] for r in cursor.fetchall()]

        if not tournament_ids:
            print("  No Limitless tournaments found for specified organizers")
            return

        tournament_placeholders = ",".join(["%s" for _ in tournament_ids])
        print(f"  Cleaning {len(tournament_ids)} tournaments from {len(store_ids)} stores...")

        # Delete in order: matches, results, tournaments, sync_state
        cursor.execute(f"""
            DELETE FROM matches WHERE tournament_id IN ({tournament_placeholders})
        """, tournament_ids)
        print(f"    Deleted matches")

        cursor.execute(f"""
            DELETE FROM results WHERE tournament_id IN ({tournament_placeholders})
        """, tournament_ids)
        print(f"    Deleted results")

        cursor.execute(f"""
            DELETE FROM tournaments WHERE tournament_id IN ({tournament_placeholders})
        """, tournament_ids)
        print(f"    Deleted tournaments")

        # Clear sync state for these organizers
        cursor.execute(f"""
            DELETE FROM limitless_sync_state WHERE organizer_id IN ({placeholders})
        """, organizer_ids)
        print(f"    Cleared sync state")

    else:
        # Clean ALL Limitless data
        print("  Cleaning ALL Limitless data...")

        # Get all Limitless tournament IDs
        cursor.execute("""
            SELECT tournament_id FROM tournaments WHERE limitless_id IS NOT NULL
        """)
        tournament_ids = [r[0] for r in cursor.fetchall()]

        if tournament_ids:
            tournament_placeholders = ",".join(["%s" for _ in tournament_ids])

            cursor.execute(f"""
                DELETE FROM matches WHERE tournament_id IN ({tournament_placeholders})
            """, tournament_ids)
            print(f"    Deleted matches from {len(tournament_ids)} tournaments")

            cursor.execute(f"""
                DELETE FROM results WHERE tournament_id IN ({tournament_placeholders})
            """, tournament_ids)
            print(f"    Deleted results")

            cursor.execute("""
                DELETE FROM tournaments WHERE limitless_id IS NOT NULL
            """)
            print(f"    Deleted {len(tournament_ids)} tournaments")

        # Clear all sync state
        cursor.execute("DELETE FROM limitless_sync_state")
        print(f"    Cleared sync state")

    conn.commit()
    # Note: We keep limitless_deck_map and deck_requests as those are curated mappings


# =============================================================================
# Main
# =============================================================================

def get_incremental_since_date(cursor):
    """Get the earliest last_tournament_date from sync state for incremental sync.

    Returns a date 1 day before the oldest last sync to ensure we catch everything.
    Falls back to 30 days ago if no sync state exists.
    """
    try:
        cursor.execute("""
            SELECT MIN(last_tournament_date) FROM limitless_sync_state
            WHERE last_tournament_date IS NOT NULL
        """)
        result = cursor.fetchone()

        if result and result[0]:
            # Parse the date and subtract 1 day for safety overlap
            # psycopg2 may return a date object or string depending on column type
            last_date_val = result[0]
            if isinstance(last_date_val, str):
                last_date = datetime.strptime(last_date_val, "%Y-%m-%d")
            else:
                # It's a date/datetime object
                last_date = datetime(last_date_val.year, last_date_val.month, last_date_val.day)
            since_date = last_date - timedelta(days=1)
            return since_date.strftime("%Y-%m-%d")
    except Exception as e:
        print(f"  Warning: Could not read sync state: {e}")

    # Default to 30 days ago
    default_date = datetime.now() - timedelta(days=30)
    return default_date.strftime("%Y-%m-%d")


def run_classify_decklists(cursor):
    """Run deck archetype auto-classification on UNKNOWN decklists.

    For decklists that can't be classified or match an archetype not in DB,
    creates deck_requests for admin review.
    """
    print("\n" + "=" * 60)
    print("AUTO-CLASSIFYING UNKNOWN DECKLISTS")
    print("=" * 60)

    # Import classification logic (add scripts dir to path for GitHub Actions)
    from pathlib import Path
    scripts_dir = Path(__file__).parent
    if str(scripts_dir) not in sys.path:
        sys.path.insert(0, str(scripts_dir))
    from classify_decklists import CLASSIFICATION_RULES, classify_decklist

    # Get archetype name to ID mapping
    cursor.execute('''
        SELECT archetype_id, archetype_name FROM deck_archetypes
    ''')
    archetypes = cursor.fetchall()
    archetype_map = {name: id for id, name in archetypes}

    # Get UNKNOWN decklist results from online tournaments (that don't already have a pending deck request)
    cursor.execute('''
        SELECT r.result_id, r.decklist_json
        FROM results r
        JOIN tournaments t ON r.tournament_id = t.tournament_id
        JOIN stores s ON t.store_id = s.store_id
        JOIN deck_archetypes d ON r.archetype_id = d.archetype_id
        WHERE s.is_online = TRUE
          AND d.archetype_name = 'UNKNOWN'
          AND r.decklist_json IS NOT NULL
          AND r.decklist_json != ''
          AND r.pending_deck_request_id IS NULL
    ''')
    results = cursor.fetchall()

    print(f"  Found {len(results)} UNKNOWN results with decklists (no pending request)")

    if len(results) == 0:
        print("  Nothing to classify!")
        return 0

    # Track outcomes
    updates = []
    missing_archetypes = {}  # archetype_name -> [(result_id, decklist_json), ...]
    unclassifiable = []      # [(result_id, decklist_json), ...]

    # Classify each decklist
    for result_id, decklist_json in results:
        archetype_name = classify_decklist(decklist_json)
        if archetype_name:
            archetype_id = archetype_map.get(archetype_name)
            if archetype_id:
                # Found in DB - can update directly
                updates.append((archetype_id, result_id))
            else:
                # Classification matched but archetype not in DB
                if archetype_name not in missing_archetypes:
                    missing_archetypes[archetype_name] = []
                missing_archetypes[archetype_name].append((result_id, decklist_json))
        else:
            # Classification failed - no matching rules
            unclassifiable.append((result_id, decklist_json))

    # Apply direct updates
    for archetype_id, result_id in updates:
        cursor.execute(
            "UPDATE results SET archetype_id = %s WHERE result_id = %s",
            (archetype_id, result_id)
        )

    print(f"  Classified {len(updates)} decklists")

    # Create deck_requests for missing archetypes (one per archetype, not per result)
    requests_created = 0
    for archetype_name, result_list in missing_archetypes.items():
        # Create one deck request for this missing archetype
        # Use the first result's decklist as the example
        first_result_id, first_decklist = result_list[0]

        cursor.execute("""
            INSERT INTO deck_requests
                (deck_name, primary_color, status, submitted_at,
                 suggested_archetype_name, decklist_json, source, result_id)
            VALUES (%s, 'Unknown', 'pending', CURRENT_TIMESTAMP,
                    %s, %s, 'classification', %s)
            RETURNING request_id
        """, (
            f"[Auto] {archetype_name}",
            archetype_name,
            first_decklist,
            first_result_id
        ))
        next_request_id = cursor.fetchone()[0]

        # Link all results with this archetype to this deck request
        for result_id, _ in result_list:
            cursor.execute(
                "UPDATE results SET pending_deck_request_id = %s WHERE result_id = %s",
                (next_request_id, result_id)
            )

        requests_created += 1
        print(f"    Created deck request for '{archetype_name}' ({len(result_list)} results)")

    # Create deck_requests for unclassifiable decklists (one per result)
    for result_id, decklist_json in unclassifiable:
        cursor.execute("""
            INSERT INTO deck_requests
                (deck_name, primary_color, status, submitted_at,
                 suggested_archetype_name, decklist_json, source, result_id)
            VALUES (%s, 'Unknown', 'needs_classification', CURRENT_TIMESTAMP,
                    NULL, %s, 'classification', %s)
            RETURNING request_id
        """, (
            "[Auto] Unclassified Deck",
            decklist_json,
            result_id
        ))
        next_request_id = cursor.fetchone()[0]

        cursor.execute(
            "UPDATE results SET pending_deck_request_id = %s WHERE result_id = %s",
            (next_request_id, result_id)
        )
        requests_created += 1

    if unclassifiable:
        print(f"    Created {len(unclassifiable)} deck requests for unclassifiable decklists")

    total_missing = sum(len(r) for r in missing_archetypes.values())
    print(f"  Summary:")
    print(f"    - Directly classified: {len(updates)}")
    print(f"    - Missing archetypes: {total_missing} results ({len(missing_archetypes)} unique archetypes)")
    print(f"    - Unclassifiable: {len(unclassifiable)}")
    print(f"    - Deck requests created: {requests_created}")

    return len(updates)


def main():
    parser = argparse.ArgumentParser(
        description="Sync LimitlessTCG tournament data to DigiLab database"
    )
    parser.add_argument("--organizer", type=int,
                        help="Limitless organizer ID to sync")
    parser.add_argument("--all-tier1", action="store_true",
                        help="Sync all Tier 1 organizers")
    parser.add_argument("--since",
                        help="Only sync tournaments on or after this date (YYYY-MM-DD)")
    parser.add_argument("--incremental", action="store_true",
                        help="Auto-detect since date from last sync state")
    parser.add_argument("--classify", action="store_true",
                        help="Run deck archetype auto-classification after sync")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would be synced without writing to DB")
    parser.add_argument("--limit", type=int, default=None,
                        help="Max tournaments to sync (useful for testing)")
    parser.add_argument("--repair", action="store_true",
                        help="Re-fetch standings/pairings for tournaments missing results")
    parser.add_argument("--clean", action="store_true",
                        help="Delete ALL existing Limitless data before sync (for fresh re-import)")
    args = parser.parse_args()

    # Validate arguments
    if not args.organizer and not args.all_tier1 and not args.repair:
        parser.error("Either --organizer ID, --all-tier1, or --repair is required")

    # Validate date format (not required for repair mode or incremental mode)
    if not args.repair and not args.incremental:
        if not args.since:
            parser.error("--since DATE is required (or use --incremental for auto-detect)")
        try:
            datetime.strptime(args.since, "%Y-%m-%d")
        except ValueError:
            parser.error(f"Invalid date format: {args.since} (expected YYYY-MM-DD)")

    print("=" * 60)
    print("LimitlessTCG Sync")
    print("=" * 60)
    print(f"Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print(f"Database: Neon PostgreSQL")

    # Connect to database
    print(f"\nConnecting to database...", end=" ", flush=True)
    try:
        conn = get_connection()
        cursor = conn.cursor()
        print("OK")
    except Exception as e:
        print(f"FAILED: {e}")
        sys.exit(1)

    # Handle repair mode separately
    if args.repair:
        print("Mode: REPAIR (re-fetch missing standings/pairings)")
        run_repair_mode(conn, cursor)
        cursor.close()
        conn.close()
        print("=" * 60)
        return

    # Normal sync mode
    if args.all_tier1:
        organizer_ids = list(TIER1_ORGANIZERS.keys())
    else:
        organizer_ids = [args.organizer]

    # Determine since date (incremental mode auto-detects from sync state)
    since_date = args.since
    if args.incremental:
        since_date = get_incremental_since_date(cursor)
        print(f"Mode: INCREMENTAL (auto-detected since date)")

    print(f"Since: {since_date}")
    print(f"Organizers: {', '.join(str(o) for o in organizer_ids)}")
    if args.limit:
        print(f"Limit: {args.limit} tournaments per organizer")
    if args.classify:
        print(f"Post-sync: Auto-classify UNKNOWN decklists")
    if args.dry_run:
        print("Mode: DRY RUN (no database writes)")

    # Clean existing Limitless data if --clean flag is set
    if args.clean:
        print("\n*** CLEAN MODE: Deleting existing Limitless data ***")
        clean_limitless_data(conn, cursor, organizer_ids if not args.all_tier1 else None)
        print("Clean complete.\n")

    # Sync each organizer
    all_stats = []
    for organizer_id in organizer_ids:
        try:
            stats = sync_organizer(conn, cursor, organizer_id, since_date, args.dry_run, args.limit)
            all_stats.append(stats)
        except Exception as e:
            print(f"\nERROR syncing organizer {organizer_id}: {e}")
            conn.rollback()
            all_stats.append({"error": str(e), "organizer_id": organizer_id})

    # Run auto-classification if requested
    classified_count = 0
    if args.classify and not args.dry_run:
        classified_count = run_classify_decklists(cursor)
        conn.commit()

    # Close connection
    cursor.close()
    conn.close()

    # Print overall summary
    print("\n" + "=" * 60)
    print("SYNC COMPLETE")
    print("=" * 60)

    total_synced = sum(s.get("tournaments_synced", 0) for s in all_stats)
    total_skipped = sum(s.get("tournaments_skipped", 0) for s in all_stats)
    total_results = sum(s.get("total_results", 0) for s in all_stats)
    total_matches = sum(s.get("total_matches", 0) for s in all_stats)
    total_players = sum(s.get("total_players_created", 0) for s in all_stats)
    total_decks = sum(s.get("total_deck_requests", 0) for s in all_stats)
    errors = [s for s in all_stats if "error" in s]

    print(f"Tournaments synced: {total_synced}")
    print(f"Tournaments skipped: {total_skipped}")
    print(f"Results inserted: {total_results}")
    print(f"Matches inserted: {total_matches}")
    print(f"New players: {total_players}")
    print(f"Deck requests: {total_decks}")
    if args.classify and not args.dry_run:
        print(f"Decklists classified: {classified_count}")

    if errors:
        print(f"\nErrors: {len(errors)}")
        for err in errors:
            print(f"  - Organizer {err.get('organizer_id', '?')}: {err.get('error', 'unknown')}")

    if args.dry_run:
        print("\n[DRY RUN] No changes were written to the database.")

    if total_decks > 0:
        print(f"\nNote: {total_decks} new deck request(s) created.")
        print(f"  Review in admin panel: Deck Requests > Map Limitless decks to archetypes")

    print("=" * 60)


if __name__ == "__main__":
    main()
