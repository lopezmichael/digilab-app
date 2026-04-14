#!/usr/bin/env python3
"""
Backfill decklist_json for results that have a decklist_url but no JSON.

Supported domains:
  1. digimoncard.dev /p/{DCG_CODE}        — decode DCG binary format (no network)
  2. digimoncard.dev /deckbuilder/{uuid}  — POST to data8675309.php API
  3. digimonmeta.com ?dg=...              — parse URL query param (no network)
  4. digitalgateopen.com ?main=&egg=      — parse URL query params (no network)
  5. digimoncard.app /deck/{uuid}         — fetch from public REST API
  6. bandai-tcg-plus.com /deck_code_recipe — two-step public API

Unsupported (stored as URL-only):
  - digimoncard.io — Cloudflare-protected, no server-side API access
  - Limitless URLs without JSON — deck wasn't shared publicly

Usage:
  python scripts/backfill_decklist_json.py [--dry-run]
"""

import argparse
import io
import json
import os
import re
import time
import urllib.request
from base64 import urlsafe_b64decode
from urllib.parse import urlparse, parse_qs, quote, unquote

import psycopg2
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# ---------------------------------------------------------------------------
# DCG Codec — vendored decode logic from niamu/digimon-card-game
# https://github.com/niamu/digimon-card-game/tree/main/codec/python
# Vendored from commit: latest as of 2026-04-12 (codec v5)
# License: EPL-2.0
# Note: Do NOT run this script with python -O (asserts are used for validation)
# ---------------------------------------------------------------------------

DCG_PREFIX = "DCG"
DCG_VERSION = 5

_BASE36_LOOKUP = {
    0: "0", 1: "1", 2: "2", 3: "3", 4: "4", 5: "5", 6: "6", 7: "7",
    8: "8", 9: "9", 10: "A", 11: "B", 12: "C", 13: "D", 14: "E", 15: "F",
    16: "G", 17: "H", 18: "I", 19: "J", 20: "K", 21: "L", 22: "M", 23: "N",
    24: "O", 25: "P", 26: "Q", 27: "R", 28: "S", 29: "T", 30: "U", 31: "V",
    32: "W", 33: "X", 34: "Y", 35: "Z",
}


def _base36_to_char(base_36):
    return _BASE36_LOOKUP.get(base_36, "")


def _compute_checksum(total_card_bytes, buffer):
    return sum(buffer) & 0xFF


def _get_u8(deck_bytes):
    return deck_bytes.read1(1)[0]


def _get_u32(deck_bytes):
    return deck_bytes.read1(4)


def _read_bits_from_byte(current_byte, mask_bits, delta_shift, out_bits):
    return ((current_byte & ((1 << mask_bits) - 1)) << delta_shift) | out_bits


def _is_carry_bit(current_byte, mask_bits):
    return 0 != current_byte & (1 << mask_bits)


def _read_encoded_u32(base_value, current_byte, delta_shift, deck_bytes):
    if delta_shift - 1 == 0 or _is_carry_bit(current_byte, delta_shift - 1):
        while True:
            next_byte = _get_u8(deck_bytes)
            base_value = _read_bits_from_byte(
                next_byte, 8 - 1, delta_shift - 1, base_value
            )
            if not _is_carry_bit(next_byte, 8 - 1):
                break
            delta_shift += 8 - 1
    else:
        return _read_bits_from_byte(current_byte, delta_shift - 1, 0, 0)
    return base_value


def _deserialize_card(version, deck_bytes, card_set, card_set_padding, prev_card_number):
    current_byte = _get_u8(deck_bytes)
    card_count = (current_byte >> 6) + 1 if version == 0 else current_byte + 1
    current_byte = current_byte if version == 0 else _get_u8(deck_bytes)
    card_parallel_id = current_byte >> 3 & 0x07 if version == 0 else current_byte >> 5
    delta_shift = 3 if version == 0 else 5
    card_number = _read_bits_from_byte(current_byte, delta_shift - 1, 0, 0)
    prev_card_number += _read_encoded_u32(
        card_number, current_byte, delta_shift, deck_bytes
    )
    card = {
        "number": f"{card_set}-{str(prev_card_number).zfill(card_set_padding)}",
        "count": card_count,
    }
    if card_parallel_id != 0:
        card["parallel-id"] = card_parallel_id
    return (prev_card_number, card)


def _parse_dcg_deck(deck_bytes):
    version_and_digi_egg_count = _get_u8(deck_bytes)
    version = version_and_digi_egg_count >> 4
    assert DCG_VERSION >= version, f"Deck version {version} not supported"
    digi_egg_set_count = version_and_digi_egg_count & (
        0x07 if (3 <= version <= 4) else 0x0F
    )
    checksum = _get_u8(deck_bytes)
    deck_name_length = _get_u8(deck_bytes)
    if version >= 5:
        deck_name_length &= 0x3F
    total_card_bytes = (
        len(deck_bytes.getbuffer()[deck_bytes.tell():]) - deck_name_length
    )
    header_size = deck_bytes.tell()
    computed_checksum = _compute_checksum(
        total_card_bytes,
        deck_bytes.getbuffer()[header_size: total_card_bytes + header_size],
    )
    assert checksum == computed_checksum, f"Deck checksum failed. {checksum} != {computed_checksum}"

    sideboard_byte = _get_u8(deck_bytes) if version >= 2 else 0
    sideboard_count = sideboard_byte & 0x7F if version >= 4 else sideboard_byte

    cards = []
    while len(deck_bytes.getbuffer()[deck_bytes.tell():]) > deck_name_length:
        if version == 0:
            card_set = str(_get_u32(deck_bytes).decode("UTF-8")).strip()
        else:
            card_set = ""
            current_byte = _get_u8(deck_bytes)
            card_set += _base36_to_char(current_byte & 0x3F)
            while current_byte >> 7 != 0:
                current_byte = _get_u8(deck_bytes)
                card_set += _base36_to_char(current_byte & 0x3F)
        padding_and_set_count = _get_u8(deck_bytes)
        card_set_padding = (padding_and_set_count >> 6) + 1
        card_set_count = (
            _read_encoded_u32(
                padding_and_set_count, padding_and_set_count, 6, deck_bytes
            )
            if version >= 2
            else padding_and_set_count & 0x3F
        )
        prev_card_number = 0
        for _ in range(card_set_count):
            prev_card_number, card = _deserialize_card(
                version, deck_bytes, card_set, card_set_padding, prev_card_number
            )
            cards.append(card)

    return {
        "digi-eggs": cards[:digi_egg_set_count],
        "deck": cards[digi_egg_set_count:(len(cards) - sideboard_count)],
    }


def decode_dcg(s):
    """Decode a DCG deck code string into {digi-eggs: [...], deck: [...]}."""
    prefix, deck_code = s[:len(DCG_PREFIX)], s[len(DCG_PREFIX):]
    assert prefix == DCG_PREFIX, "Prefix was not 'DCG'"
    deck_code_bytes = deck_code.encode("UTF-8")
    deck_bytes = urlsafe_b64decode(
        (deck_code_bytes + (b"=" * (4 - (len(deck_code_bytes) % 4))))
    )
    return _parse_dcg_deck(io.BytesIO(deck_bytes))


# ---------------------------------------------------------------------------
# Card lookup cache — maps card_id -> {name, card_type}
# ---------------------------------------------------------------------------

_card_cache = {}


def load_card_cache(cursor):
    """Load all cards from the database into memory for fast lookups."""
    cursor.execute("SELECT card_id, name, card_type FROM cards")
    for card_id, name, card_type in cursor.fetchall():
        _card_cache[card_id] = {"name": name, "card_type": card_type}
    print(f"  Loaded {len(_card_cache)} cards into cache")


def card_type_to_category(card_type):
    """Map cards.card_type to the Limitless JSON category key."""
    mapping = {
        "Digimon": "digimon",
        "Tamer": "tamer",
        "Option": "option",
        "Digi-Egg": "egg",
    }
    return mapping.get(card_type, "digimon")


def make_card_dict(card_id, count, name=None):
    """Build a Limitless-format card dict from a card ID, count, and optional name."""
    parts = card_id.split("-", 1)
    return {
        "count": count,
        "name": name or card_id,
        "set": parts[0] if len(parts) == 2 else "",
        "number": parts[1] if len(parts) == 2 else card_id,
    }


def enrich_card(card_id, count):
    """Build a Limitless-format card dict with name lookup from cards table."""
    info = _card_cache.get(card_id)
    card_dict = make_card_dict(card_id, count, info["name"] if info else None)
    return card_dict, (info["card_type"] if info else None)


def flat_cards_to_4cat(card_list):
    """
    Convert a flat list of (card_id, count) into the 4-category Limitless format.
    Returns {"digimon": [...], "tamer": [...], "option": [...], "egg": [...]} or None.
    """
    result = {"digimon": [], "tamer": [], "option": [], "egg": []}
    unknown_cards = []

    for card_id, count in card_list:
        card_dict, card_type = enrich_card(card_id, count)
        if card_type:
            category = card_type_to_category(card_type)
            result[category].append(card_dict)
        else:
            unknown_cards.append(card_id)

    if unknown_cards:
        print(f"    Warning: {len(unknown_cards)} unknown card IDs: {unknown_cards[:5]}")

    # Only return if we have at least some cards
    total = sum(len(v) for v in result.values())
    return result if total > 0 else None


# ---------------------------------------------------------------------------
# Domain parsers
# ---------------------------------------------------------------------------

def parse_digimoncard_dev(url):
    """
    Parse digimoncard.dev /p/{DCG_CODE} URLs.
    Returns list of (card_id, count) tuples or None.
    """
    parsed = urlparse(url)
    path = parsed.path

    # Only handle /p/ paths (DCG codes), not /deckbuilder/ UUIDs
    match = re.match(r'^/p/(.+)$', path)
    if not match:
        return None

    dcg_code = unquote(match.group(1))
    try:
        decoded = decode_dcg(dcg_code)
    except Exception as e:
        print(f"    DCG decode error: {e}")
        return None

    cards = []
    for card in decoded.get("digi-eggs", []):
        cards.append((card["number"], card["count"]))
    for card in decoded.get("deck", []):
        cards.append((card["number"], card["count"]))
    return cards


def parse_digimonmeta(url):
    """
    Parse digimonmeta.com ?dg= URLs.
    Format: {count}n{card_id} joined by 'a'
    Example: 4nBT13-007a3nBT13-093
    Returns list of (card_id, count) tuples or None.
    """
    parsed = urlparse(url)
    params = parse_qs(parsed.query)
    dg = params.get("dg", [None])[0]
    if not dg:
        return None

    cards = []
    for entry in dg.split("a"):
        entry = entry.strip()
        if not entry:
            continue
        match = re.match(r'^(\d+)n(.+)$', entry)
        if match:
            count = int(match.group(1))
            card_id = match.group(2).strip()
            cards.append((card_id, count))
    return cards if cards else None


def parse_digitalgateopen(url):
    """
    Parse digitalgateopen.com ?main=...&egg=... URLs.
    Format: {card_id}x{count} comma-separated
    Example: main=BT23-048x4,BT23-017x2&egg=BT23-002x4
    Returns list of (card_id, count) tuples or None.
    """
    parsed = urlparse(url)
    params = parse_qs(parsed.query)

    cards = []
    for param_key in ["main", "egg"]:
        raw = params.get(param_key, [None])[0]
        if not raw:
            continue
        for entry in raw.split(","):
            entry = entry.strip()
            if not entry:
                continue
            match = re.match(r'^(.+?)x(\d+)$', entry)
            if match:
                card_id = match.group(1).strip()
                count = int(match.group(2))
                cards.append((card_id, count))
    return cards if cards else None


def parse_digimoncard_app(url):
    """
    Parse digimoncard.app /deckbuilder/user/{uid}/deck/{uuid} URLs.
    Fetches from public REST API: GET https://backend.digimoncard.app/api/decks/{uuid}
    Returns list of (card_id, count) tuples or None.
    """
    parsed = urlparse(url)
    match = re.match(r'^/deckbuilder/user/[^/]+/deck/([a-f0-9-]+)', parsed.path)
    if not match:
        return None

    deck_uuid = match.group(1)

    try:
        api_url = f"https://backend.digimoncard.app/api/decks/{deck_uuid}"
        req = urllib.request.Request(api_url, headers={"User-Agent": "DigiLab/2.1.0"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        print(f"    digimoncard.app API error for {deck_uuid}: {e}")
        return None

    # API returns {"cards": "[{\"id\":\"BT15-006\",\"count\":4}, ...]", ...}
    # The cards field is a JSON string, not a parsed list
    cards_raw = data.get("cards", "[]")
    if isinstance(cards_raw, str):
        try:
            cards_data = json.loads(cards_raw)
        except (json.JSONDecodeError, TypeError):
            return None
    else:
        cards_data = cards_raw

    if not cards_data:
        return None

    cards = []
    for card in cards_data:
        card_id = card.get("id") or card.get("card_id") or card.get("cardNumber")
        count = card.get("count") or card.get("quantity") or 1
        if card_id:
            cards.append((card_id, int(count)))
    return cards if cards else None


def parse_digimoncard_dev_deckbuilder(url):
    """
    Parse digimoncard.dev /deckbuilder/{uuid} URLs.
    POST to data8675309.php with m=14 and pubKey={uuid}.
    Response: [{data: JSON string with deck[] and ddto[], ...}]
    ddto = [egg_count, digimon_count, tamer_count, option_count]
    deck = flat list of card IDs (duplicates = count)
    Returns 4-category JSON dict directly, or None.
    """
    parsed = urlparse(url)
    match = re.match(
        r'^/deckbuilder/([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$',
        parsed.path,
    )
    if not match:
        return None

    uuid = match.group(1)

    try:
        body = f"m=14&pubKey={uuid}".encode()
        req = urllib.request.Request(
            "https://digimoncard.dev/data8675309.php",
            data=body,
            headers={
                "User-Agent": "DigiLab/2.1.0",
                "Origin": "https://digimoncard.dev",
                "Content-Type": "application/x-www-form-urlencoded",
            },
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            rows = json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        print(f"    digimoncard.dev deckbuilder API error for {uuid}: {e}")
        return None

    if not rows or not isinstance(rows, list):
        return None

    data_str = rows[0].get("data")
    if not data_str:
        return None

    try:
        data = json.loads(data_str)
    except (json.JSONDecodeError, TypeError):
        return None

    deck_list = data.get("deck", [])
    ddto = data.get("ddto", [])  # [eggs, digimon, tamers, options]

    if not deck_list:
        return None

    # Use ddto to split flat deck_list into categories by card count
    categories = ["egg", "digimon", "tamer", "option"]
    result = {"digimon": [], "tamer": [], "option": [], "egg": []}

    card_idx = 0  # index into the flat deck_list
    for cat_idx, category in enumerate(categories):
        cat_count = ddto[cat_idx] if cat_idx < len(ddto) and ddto[cat_idx] else 0
        segment_end = card_idx + cat_count
        # Collapse duplicates in this segment
        seen = {}
        for i in range(card_idx, min(segment_end, len(deck_list))):
            cid = deck_list[i]
            seen[cid] = seen.get(cid, 0) + 1
        for cid, count in seen.items():
            card_name = _card_cache.get(cid, {}).get("name", cid)
            result[category].append(make_card_dict(cid, count, card_name))
        card_idx = segment_end

    total = sum(len(v) for v in result.values())
    return result if total > 0 else None


def parse_bandai_tcg_plus(url):
    """
    Parse bandai-tcg-plus.com /deck_code_recipe/{deck_code} URLs.
    Two-step API:
      1. /api/user/deck/url_code?deck_code={code} → resolves to dot-separated url_code
      2. /api/user/deck/recipe?url_code={url_code} → returns full card details
    Returns 4-category JSON dict directly (not flat cards), or None.
    """
    parsed = urlparse(url)
    match = re.match(r'^/deck_code_recipe/([A-Za-z0-9_-]+)', parsed.path)
    if not match:
        return None

    deck_code = match.group(1)

    # Step 1: Resolve deck_code → url_code
    try:
        step1_url = f"https://api.bandai-tcg-plus.com/api/user/deck/url_code?deck_code={deck_code}"
        req = urllib.request.Request(step1_url, headers={"User-Agent": "DigiLab/2.1.0"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        success = data.get("success", {})
        url_code = success.get("url_code")
        game_title_id = success.get("game_title_id", 2)
        if not url_code:
            print(f"    bandai-tcg-plus.com: no url_code returned for {deck_code}")
            return None
    except Exception as e:
        print(f"    bandai-tcg-plus.com API error (step 1) for {deck_code}: {e}")
        return None

    # Step 2: Fetch full recipe from url_code
    try:
        step2_url = (
            f"https://api.bandai-tcg-plus.com/api/user/deck/recipe"
            f"?url_code={quote(url_code)}&game_title_id={game_title_id}&encode=0"
        )
        req = urllib.request.Request(step2_url, headers={"User-Agent": "DigiLab/2.1.0"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
        success = data.get("success", {})
    except Exception as e:
        print(f"    bandai-tcg-plus.com API error (step 2) for {deck_code}: {e}")
        return None

    main_deck = success.get("main_deck", [])
    extra_deck = success.get("extra_deck", [])

    if not main_deck and not extra_deck:
        return None

    # Build 4-category JSON directly from the API response
    # API card types match our card_type_to_category mapping
    result = {"digimon": [], "tamer": [], "option": [], "egg": []}

    for card in main_deck + extra_deck:
        card_number = card.get("card_number", "")
        card_dict = make_card_dict(
            card_number,
            card.get("card_count", 1),
            card.get("card_name", card_number),
        )
        category = card_type_to_category(card.get("type", ""))
        result[category].append(card_dict)

    total = sum(len(v) for v in result.values())
    return result if total > 0 else None


# ---------------------------------------------------------------------------
# URL router
# ---------------------------------------------------------------------------

# Domains with implemented parsers — used for both routing and error tracking
# Parsers returning flat (card_id, count) lists (processed by flat_cards_to_4cat)
_FLAT_PARSERS = {
    "digimoncard.dev": parse_digimoncard_dev,
    "digimonmeta.com": parse_digimonmeta,
    "digitalgateopen.com": parse_digitalgateopen,
    "digimoncard.app": parse_digimoncard_app,
}
# Parsers returning final 4-category JSON directly
_DIRECT_PARSERS = {
    "bandai-tcg-plus.com": parse_bandai_tcg_plus,
}
PARSEABLE_DOMAINS = {**_FLAT_PARSERS, **_DIRECT_PARSERS}


def extract_domain(url):
    """Extract and normalize the domain from a URL."""
    hostname = urlparse(url).hostname or ""
    return hostname.lower().removeprefix("www.")


def parse_decklist_url(url):
    """
    Route a decklist URL to the appropriate parser.
    Returns 4-category JSON dict or None.
    """
    if not url or not url.strip():
        return None

    domain = extract_domain(url)

    # Direct parsers return final 4-category JSON
    if domain in _DIRECT_PARSERS:
        return _DIRECT_PARSERS[domain](url)

    # digimoncard.dev has two URL patterns:
    #   /p/{DCG_CODE} → flat parser (DCG codec decode)
    #   /deckbuilder/{uuid} → direct parser (API call)
    if domain == "digimoncard.dev":
        path = urlparse(url).path
        if path.startswith("/deckbuilder/"):
            return parse_digimoncard_dev_deckbuilder(url)
        # Fall through to flat parser for /p/ URLs

    # Flat parsers return (card_id, count) lists needing enrichment
    if domain in _FLAT_PARSERS:
        flat_cards = _FLAT_PARSERS[domain](url)
        if not flat_cards:
            return None
        return flat_cards_to_4cat(flat_cards)

    return None


# ---------------------------------------------------------------------------
# Main backfill
# ---------------------------------------------------------------------------

COMMIT_BATCH_SIZE = 50


def main():
    parser = argparse.ArgumentParser(description="Backfill decklist_json from decklist_url")
    parser.add_argument("--dry-run", action="store_true", help="Preview changes without writing to DB")
    args = parser.parse_args()

    print("Connecting to Neon PostgreSQL...", end=" ", flush=True)
    conn = psycopg2.connect(
        host=os.environ["NEON_HOST"],
        dbname=os.environ["NEON_DATABASE"],
        user=os.environ["NEON_USER"],
        password=os.environ["NEON_PASSWORD"],
        sslmode="require",
    )
    print("Connected!")

    try:
        cursor = conn.cursor()

        # Load card cache for name/type lookups
        print("Loading card cache...")
        load_card_cache(cursor)

        # Fetch all results with URL but no JSON
        cursor.execute("""
            SELECT result_id, decklist_url
            FROM results
            WHERE decklist_url IS NOT NULL
              AND decklist_url != ''
              AND (decklist_json IS NULL OR decklist_json = '')
            ORDER BY result_id
        """)
        rows = cursor.fetchall()
        print(f"Found {len(rows)} results with decklist_url but no decklist_json\n")

        if not rows:
            print("Nothing to backfill!")
            return

        # Track stats by domain
        stats = {
            "parsed": 0,
            "skipped_unsupported": 0,
            "skipped_error": 0,
            "by_domain": {},
        }
        uncommitted = 0

        for result_id, url in rows:
            domain = extract_domain(url)
            stats["by_domain"].setdefault(domain, {"total": 0, "parsed": 0, "errors": 0})
            stats["by_domain"][domain]["total"] += 1

            decklist_json = parse_decklist_url(url)

            if decklist_json is None:
                if domain in PARSEABLE_DOMAINS:
                    stats["skipped_error"] += 1
                    stats["by_domain"][domain]["errors"] += 1
                else:
                    stats["skipped_unsupported"] += 1
                continue

            stats["parsed"] += 1
            stats["by_domain"][domain]["parsed"] += 1

            json_str = json.dumps(decklist_json)
            total_cards = sum(
                card["count"]
                for cat in decklist_json.values()
                for card in cat
            )
            print(f"  [{result_id}] {domain} — {total_cards} cards total")

            if not args.dry_run:
                cursor.execute(
                    "UPDATE results SET decklist_json = %s, updated_at = CURRENT_TIMESTAMP WHERE result_id = %s",
                    (json_str, result_id),
                )
                uncommitted += 1
                if uncommitted >= COMMIT_BATCH_SIZE:
                    conn.commit()
                    print(f"    (committed batch of {uncommitted})")
                    uncommitted = 0

            # Rate limit API calls to external services
            needs_api = domain in ("digimoncard.app", "bandai-tcg-plus.com")
            if domain == "digimoncard.dev" and "/deckbuilder/" in url:
                needs_api = True
            if needs_api:
                time.sleep(0.5)

        if not args.dry_run and uncommitted > 0:
            conn.commit()
            print(f"\nCommitted {stats['parsed']} updates to database.")
        elif args.dry_run:
            print(f"\n[DRY RUN] Would update {stats['parsed']} results.")

        print(f"\nSummary:")
        print(f"  Parsed & backfilled: {stats['parsed']}")
        print(f"  Skipped (unsupported domain): {stats['skipped_unsupported']}")
        print(f"  Skipped (parse error): {stats['skipped_error']}")
        print(f"\nBy domain:")
        for domain, counts in sorted(stats["by_domain"].items()):
            print(f"  {domain}: {counts['parsed']}/{counts['total']} parsed, {counts['errors']} errors")

    finally:
        conn.close()


if __name__ == "__main__":
    main()
