"""
Sync DigimonCard.io Cards to Database

Fetches all cards from DigimonCard.io API and caches them in the database.
This allows the Shiny app to search cards locally without external API calls.

Usage:
    python scripts/sync_cards.py --by-set           # Full sync by set (recommended)
    python scripts/sync_cards.py --by-set --incremental  # Only add new cards (fast)
    python scripts/sync_cards.py --set BT-21 --by-set    # Sync specific set
    python scripts/sync_cards.py --discover         # Find new set prefixes

Flags:
    --by-set       Fetch by set/pack instead of color (more comprehensive)
    --incremental  Skip cards already in database (faster for updates)
    --discover     Scan API for new/unknown set prefixes
    --set X        Sync only a specific set (e.g., BT-21, ST-15)

Prerequisites:
    pip install psycopg2-binary python-dotenv requests
    NEON_HOST and NEON_PASSWORD in .env file
"""

import os
import re
import sys
import time
import argparse
import requests
import psycopg2
from psycopg2.extras import execute_values
from dotenv import load_dotenv
from datetime import datetime

load_dotenv()

# Configuration
API_BASE = "https://digimoncard.io/index.php/api-public"
COLORS = ["Red", "Blue", "Yellow", "Green", "Purple", "Black", "White"]

# Rate limiting: 15 requests per 10 seconds
REQUEST_DELAY = 0.7  # ~14 requests per 10 seconds (safe margin)


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


def is_standard_art(card_id: str) -> bool:
    """Check if card ID is a standard (non-alternate) art."""
    # Valid patterns: BT13-087, EX10-042, ST15-01, P-001, LM-001
    # Invalid: BT13-087_P1, BT13-087-P1, anything with underscore or extra suffix
    pattern = r'^[A-Z]{1,3}\d{0,2}-\d{2,3}$'
    return bool(re.match(pattern, card_id))


def extract_set_code(card_id: str) -> str:
    """Extract set code from card ID (e.g., 'BT13' from 'BT13-087')."""
    match = re.match(r'^([A-Z]{1,3}\d{0,2})-', card_id)
    return match.group(1) if match else None


def fetch_cards_by_color(color: str, set_filter: str = None) -> list:
    """Fetch all cards of a specific color from the API."""
    url = f"{API_BASE}/search"
    params = {
        "color": color,
        "limit": 1000  # Get all cards
    }
    if set_filter:
        params["pack"] = set_filter

    headers = {
        "User-Agent": "DigimonTCGTracker/1.0 (CardSync)"
    }

    try:
        response = requests.get(url, params=params, headers=headers, timeout=30)

        if response.status_code == 400:
            return []  # No results

        if response.status_code != 200:
            print(f"    API error: HTTP {response.status_code}")
            return []

        return response.json()

    except Exception as e:
        print(f"    Request failed: {e}")
        return []


def fetch_cards_by_set(set_code: str) -> list:
    """Fetch all cards from a specific set/pack from the API."""
    url = f"{API_BASE}/search"
    params = {
        "pack": set_code,
        "limit": 1000
    }

    headers = {
        "User-Agent": "DigimonTCGTracker/1.0 (CardSync)"
    }

    try:
        response = requests.get(url, params=params, headers=headers, timeout=30)

        if response.status_code == 400:
            return []  # No results

        if response.status_code != 200:
            print(f"    API error: HTTP {response.status_code}")
            return []

        return response.json()

    except Exception as e:
        print(f"    Request failed: {e}")
        return []


def discover_prefixes() -> dict:
    """Scan API to discover all card prefixes and their counts."""
    print("\nDiscovering card prefixes from API...")

    all_prefixes = {}

    for color in COLORS:
        print(f"  Scanning {color}...", end=" ", flush=True)
        cards = fetch_cards_by_color(color)

        for card in cards:
            card_id = card.get("id") or card.get("cardnumber", "")
            match = re.match(r'^([A-Z]+)', card_id)
            if match:
                prefix = match.group(1)
                if prefix not in all_prefixes:
                    all_prefixes[prefix] = {"count": 0, "examples": []}
                all_prefixes[prefix]["count"] += 1
                if len(all_prefixes[prefix]["examples"]) < 3:
                    all_prefixes[prefix]["examples"].append(card_id)

        print(f"found {len(cards)} cards")
        time.sleep(REQUEST_DELAY)

    return all_prefixes


def get_known_prefixes() -> set:
    """Return set of prefixes we currently handle."""
    return {"BT", "EX", "ST", "LM", "RB", "AD", "P", "BO"}


def get_all_sets() -> list:
    """Return list of all known set codes to sync."""
    # Booster sets BT-01 through BT-24 (and beyond as released)
    bt_sets = [f"BT-{i:02d}" for i in range(1, 25)]

    # EX sets EX-01 through EX-11
    ex_sets = [f"EX-{i:02d}" for i in range(1, 12)]

    # Starter decks - API uses ST-1 through ST-9 (single digit), then ST-10+
    st_sets = [f"ST-{i}" for i in range(1, 10)] + [f"ST-{i}" for i in range(10, 23)]

    # Limited card packs LM-01 through LM-08
    lm_sets = [f"LM-{i:02d}" for i in range(1, 9)]

    # Resurgence Booster
    rb_sets = ["RB-01"]

    # Advanced Booster
    ad_sets = ["AD-01"]

    # Excluded: BTC-01 (Ultimate Evolution - 438 cards, different game variant)
    # Excluded: DM (Demo Decks - 5 cards)
    # Excluded: MO (Unknown - 12 cards)

    # Major promo packs (P- cards are distributed across these)
    promo_packs = [
        # Tamer Battle Packs
        "Tamer Battle Pack 4",
        "Tamer Battle Pack 6",
        "Tamer Battle Pack 10",
        "Tamer Battle Pack 11",
        "Tamer Battle Pack 12",
        "Tamer Battle Pack 13",
        "Tamer Battle Pack 14",
        "Tamer Battle Pack 15",
        "Tamer Battle Pack 16",
        "Tamer Battle Pack 17",
        "Tamer Battle Pack 18",
        "Tamer Battle Pack 19",
        # Box Promotion Packs
        "Box Promotion Pack -Next Adventure-",
        "Box Promotion Pack: Across Time",
        "Box Promotion Pack: Alternative Being",
        "Box Promotion Pack: Animal Colosseum",
        "Box Promotion Pack: Beginning Observer",
        "Box Promotion Pack: Blast Ace",
        "Box Promotion Pack: Cyber Eden",
        "Box Promotion Pack: Dawn of Liberator",
        "Box Promotion Pack: Dimensional Phase",
        "Box Promotion Pack: Elemental Successor",
        "Box Promotion Pack: Exceed Apocalypse",
        "Box Promotion Pack: Hackers' Slumber",
        "Box Promotion Pack: Infernal Ascension",
        "Box Promotion Pack: Over the X",
        "Box Promotion Pack: Resurgence Booster",
        "Box Promotion Pack: Secret Crisis",
        "Box Promotion Pack: Time Stranger",
        "Box Promotion Pack: Versus Royal Knights",
        "Box Promotion Pack: Xros Evolution",
        # Dash Packs
        "Dash Pack Ver. 1.0",
        "Dash Pack Ver. 1.5",
        "Double Diamond Dash Pack",
        "Summer 2022 Dash Pack",
        "2026 Dash Pack Campaign",
        # Update/Anniversary Packs
        "Update Pack",
        "Update Pack 2024",
        "Update Pack 2025",
        "3rd Anniversary Survey Pack",
        "3rd Anniversary Update Pack",
        # Other notable promo sets
        "1-Year Anniversary Promo Pack",
        "25th Special Memorial Pack",
        "Memorial Collection 01",
        "Memorial Collection 02",
        "Ghost Game Promo Pack",
        "Digimon Survive Promo Pack",
        "Revision Pack 2023",
        "Special Release Memorial Pack",
    ]

    return bt_sets + ex_sets + st_sets + lm_sets + rb_sets + ad_sets + promo_packs


def process_card(card: dict) -> dict:
    """Transform API card data to our schema format."""
    card_id = card.get("id") or card.get("cardnumber", "")
    name = card.get("name", "")

    return {
        "card_id": card_id,
        "name": name,
        "display_name": f"{name} ({card_id})",
        "card_type": card.get("type", ""),
        "color": card.get("color", ""),
        "color2": card.get("color2") or None,
        "level": int(card.get("level")) if card.get("level") else None,
        "dp": int(card.get("dp")) if card.get("dp") else None,
        "play_cost": int(card.get("play_cost")) if card.get("play_cost") else None,
        "digi_type": card.get("digi_type") or None,
        "digi_type2": card.get("digi_type2") or None,
        "digi_type3": card.get("digi_type3") or None,
        "digi_type4": card.get("digi_type4") or None,
        "attribute": card.get("attribute") or None,
        "stage": card.get("stage") or None,
        "rarity": card.get("rarity") or None,
        "set_code": extract_set_code(card_id)
    }


def sync_cards(conn, cursor, set_filter: str = None, by_set: bool = False, incremental: bool = False):
    """Fetch cards from API and upsert to database."""
    all_cards = []

    # Get existing card IDs if incremental mode
    existing_ids = set()
    if incremental:
        print("\nFetching existing card IDs from database...")
        cursor.execute("SELECT card_id FROM cards")
        result = cursor.fetchall()
        existing_ids = {row[0] for row in result}
        print(f"  Found {len(existing_ids)} existing cards")

    print("\nFetching cards from DigimonCard.io API...")

    if by_set and set_filter:
        # Fetch by set - more comprehensive for a specific set
        print(f"  Fetching all cards from set {set_filter}...", end=" ", flush=True)
        cards = fetch_cards_by_set(set_filter)

        # Filter to standard arts only
        standard_cards = [c for c in cards if is_standard_art(c.get("id") or c.get("cardnumber", ""))]

        print(f"found {len(cards)}, keeping {len(standard_cards)} (standard art)")
        all_cards.extend(standard_cards)

    elif by_set and not set_filter:
        # Fetch all known sets
        sets = get_all_sets()
        print(f"  Found {len(sets)} sets to sync")

        for set_code in sets:
            print(f"  Fetching {set_code}...", end=" ", flush=True)
            cards = fetch_cards_by_set(set_code)

            # Filter to standard arts only
            standard_cards = [c for c in cards if is_standard_art(c.get("id") or c.get("cardnumber", ""))]

            print(f"found {len(cards)}, keeping {len(standard_cards)} (standard art)")
            all_cards.extend(standard_cards)

            # Rate limiting
            time.sleep(REQUEST_DELAY)

    else:
        # Original color-based fetching
        for color in COLORS:
            print(f"  Fetching {color} cards...", end=" ", flush=True)
            cards = fetch_cards_by_color(color, set_filter)

            # Filter to standard arts only
            standard_cards = [c for c in cards if is_standard_art(c.get("id") or c.get("cardnumber", ""))]

            print(f"found {len(cards)}, keeping {len(standard_cards)} (standard art)")
            all_cards.extend(standard_cards)

            # Rate limiting
            time.sleep(REQUEST_DELAY)

    # Deduplicate by card_id (some cards appear in multiple colors/sets)
    seen_ids = set()
    unique_cards = []
    for card in all_cards:
        card_id = card.get("id") or card.get("cardnumber", "")
        if card_id not in seen_ids:
            seen_ids.add(card_id)
            unique_cards.append(card)

    print(f"\nTotal unique cards from API: {len(unique_cards)}")

    # Filter out existing cards in incremental mode
    if incremental and existing_ids:
        new_cards = [c for c in unique_cards if (c.get("id") or c.get("cardnumber", "")) not in existing_ids]
        skipped = len(unique_cards) - len(new_cards)
        print(f"Incremental mode: skipping {skipped} existing cards")
        unique_cards = new_cards

    print(f"Cards to sync: {len(unique_cards)}")

    if not unique_cards:
        print("No cards to sync.")
        return 0

    # Process and upsert cards
    print("\nUpserting to database...")

    processed = 0
    for card in unique_cards:
        try:
            card_data = process_card(card)

            # Upsert using INSERT ... ON CONFLICT DO UPDATE
            cursor.execute("""
                INSERT INTO cards
                (card_id, name, display_name, card_type, color, color2,
                 level, dp, play_cost, digi_type, digi_type2, digi_type3,
                 digi_type4, attribute, stage, rarity, set_code, updated_at)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, CURRENT_TIMESTAMP)
                ON CONFLICT (card_id) DO UPDATE SET
                    name = EXCLUDED.name,
                    display_name = EXCLUDED.display_name,
                    card_type = EXCLUDED.card_type,
                    color = EXCLUDED.color,
                    color2 = EXCLUDED.color2,
                    level = EXCLUDED.level,
                    dp = EXCLUDED.dp,
                    play_cost = EXCLUDED.play_cost,
                    digi_type = EXCLUDED.digi_type,
                    digi_type2 = EXCLUDED.digi_type2,
                    digi_type3 = EXCLUDED.digi_type3,
                    digi_type4 = EXCLUDED.digi_type4,
                    attribute = EXCLUDED.attribute,
                    stage = EXCLUDED.stage,
                    rarity = EXCLUDED.rarity,
                    set_code = EXCLUDED.set_code,
                    updated_at = CURRENT_TIMESTAMP
            """, [
                card_data["card_id"],
                card_data["name"],
                card_data["display_name"],
                card_data["card_type"],
                card_data["color"],
                card_data["color2"],
                card_data["level"],
                card_data["dp"],
                card_data["play_cost"],
                card_data["digi_type"],
                card_data["digi_type2"],
                card_data["digi_type3"],
                card_data["digi_type4"],
                card_data["attribute"],
                card_data["stage"],
                card_data["rarity"],
                card_data["set_code"]
            ])
            processed += 1

        except Exception as e:
            print(f"  Error processing {card.get('id', 'unknown')}: {e}")

    conn.commit()

    return processed


def main():
    parser = argparse.ArgumentParser(description="Sync DigimonCard.io cards to database")
    parser.add_argument("--set", help="Sync specific set only (e.g., BT-21)")
    parser.add_argument("--by-set", action="store_true", help="Fetch by set/pack instead of by color (more comprehensive)")
    parser.add_argument("--incremental", action="store_true", help="Only add cards not already in database (faster)")
    parser.add_argument("--discover", action="store_true", help="Discover new set prefixes from API")
    args = parser.parse_args()

    # Handle discover mode separately
    if args.discover:
        print("=" * 60)
        print("DigimonCard.io Prefix Discovery")
        print("=" * 60)

        prefixes = discover_prefixes()
        known = get_known_prefixes()

        print("\n" + "=" * 60)
        print("Results:")
        print("=" * 60)

        new_prefixes = []
        for prefix, data in sorted(prefixes.items(), key=lambda x: -x[1]["count"]):
            status = "KNOWN" if prefix in known else "NEW"
            if prefix not in known:
                new_prefixes.append(prefix)
            print(f"  {prefix}: {data['count']} cards [{status}]")
            print(f"      Examples: {', '.join(data['examples'])}")

        if new_prefixes:
            print(f"\n[!] New prefixes found: {', '.join(new_prefixes)}")
            print("    Consider adding these to get_all_sets() in sync_cards.py")
        else:
            print("\n[OK] No new prefixes found - all are handled")

        return

    print("=" * 60)
    print("DigimonCard.io Card Sync")
    print("=" * 60)

    print("Database: Neon PostgreSQL")

    mode_parts = []
    if args.set:
        mode_parts.append(f"Set {args.set}")
    else:
        mode_parts.append("Full sync")
    if args.by_set:
        mode_parts.append("(by pack)")
    else:
        mode_parts.append("(by color)")
    if args.incremental:
        mode_parts.append("[incremental]")
    print(f"Mode: {' '.join(mode_parts)}")
    print(f"Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

    # Connect to database
    print("\nConnecting to Neon PostgreSQL...")
    conn = get_connection()
    conn.autocommit = False
    cursor = conn.cursor()
    print("Connected!")

    # Ensure table exists
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS cards (
            card_id VARCHAR PRIMARY KEY,
            name VARCHAR NOT NULL,
            display_name VARCHAR NOT NULL,
            card_type VARCHAR NOT NULL,
            color VARCHAR,
            color2 VARCHAR,
            level INTEGER,
            dp INTEGER,
            play_cost INTEGER,
            digi_type VARCHAR,
            digi_type2 VARCHAR,
            digi_type3 VARCHAR,
            digi_type4 VARCHAR,
            attribute VARCHAR,
            stage VARCHAR,
            rarity VARCHAR,
            set_code VARCHAR,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    conn.commit()

    # Get count before sync
    cursor.execute("SELECT COUNT(*) FROM cards")
    before_count = cursor.fetchone()[0]
    print(f"Cards in database before sync: {before_count}")

    # Sync cards
    processed = sync_cards(conn, cursor, args.set, args.by_set, args.incremental)

    # Get count after sync
    cursor.execute("SELECT COUNT(*) FROM cards")
    after_count = cursor.fetchone()[0]

    cursor.close()
    conn.close()

    print("\n" + "=" * 60)
    print("Sync complete!")
    print("=" * 60)
    print(f"Cards processed: {processed}")
    print(f"Cards in database: {after_count}")
    print(f"New cards added: {after_count - before_count}")
    print("=" * 60)


if __name__ == "__main__":
    main()
