# Decklist JSON Collection & Viewer Design

**Date:** 2026-03-13
**Updated:** 2026-04-13
**Status:** Phase 1 Complete
**Goal:** Parse and store structured decklist JSON from all supported deckbuilder URLs, and eventually display full decklists to users in a modal.

## Background

We already store `decklist_json` for ~9,600 online Limitless tournament results via `sync_limitless.py`. Local tournament results have `decklist_url` links but no stored JSON. This plan extends JSON collection to all supported deckbuilder URLs.

### Current State (Post Phase 1 Backfill)

| Source | decklist_url | decklist_json | Count |
|--------|:---:|:---:|---:|
| Limitless (online) | Yes | Yes | ~9,600 |
| Local tournaments (parsed) | Yes | Yes | 98 |
| Local tournaments (unparseable) | Yes | No | ~156 (mostly digimoncard.io) |

## Supported Domains & Extraction Methods

### Parseable — No Network Call Required

These encode deck data directly in the URL:

**1. digimoncard.dev** (`/p/{DCG_CODE}`)
- URL path after `/p/` is a [DCG deck code](https://github.com/niamu/digimon-card-game) — a standardized base64-encoded binary format
- Decodes to card IDs + quantities (e.g., `BT13-007 x4`)
- Vendored Python decoder from `niamu/digimon-card-game` (EPL-2.0)
- **No network call needed** — all data is in the URL
- **Status:** Implemented, 18 URLs parsed

**2. digimonmeta.com** (`/deck-list/deckinfo2/?dg=...`)
- `dg=` query parameter encodes cards as `{count}n{card_id}` joined by `a`
- Example: `4nBT13-007a3nBT13-093` = 4x BT13-007, 3x BT13-093
- Flat list (no egg/main separation in URL)
- **No network call needed**
- **Status:** Implemented, 1 URL parsed

**3. digitalgateopen.com** (`/deck-builder/?main=...&egg=...`)
- `main=` and `egg=` query parameters with `{card_id}x{count}` comma-separated
- Example: `main=BT23-048x4,BT23-017x2&egg=BT23-002x4`
- Already separates eggs from main deck
- **No network call needed**
- **Status:** Implemented, 6 URLs parsed

### Parseable — API Call Required

**4. digimoncard.app** (`/deckbuilder/user/{uid}/deck/{uuid}`)
- Public REST API: `GET https://backend.digimoncard.app/api/decks/{uuid}`
- Returns JSON with `cards` field (JSON string of `[{id, count}]`)
- No auth required
- **Status:** Implemented, 29/39 parsed (10 deleted decks return 404)

**5. digimoncard.dev** (`/deckbuilder/{uuid}`)
- POST to `https://digimoncard.dev/data8675309.php` with `m=14` and `pubKey={uuid}`
- Requires `Origin: https://digimoncard.dev` header
- Returns JSON with `data.deck` (flat card ID list) and `data.ddto` (category counts: [eggs, digimon, tamers, options])
- **Status:** Implemented, 29 URLs parsed

**6. bandai-tcg-plus.com** (`/deck_code_recipe/{deck_code}`)
- Two-step public API:
  1. `GET /api/user/deck/url_code?deck_code={code}` → resolves to `url_code`
  2. `GET /api/user/deck/recipe?url_code={url_code}&game_title_id=2&encode=0` → full card details
- Returns card_number, card_name, card_count, and type per card
- Returns 4-category data directly (no card cache lookup needed)
- **Status:** Implemented, 16 Düsseldorf regional URLs parsed

**7. limitlesstcg.com** (online tournaments)
- Already handled by `sync_limitless.py`
- Tournament standings API returns full decklists
- No changes needed

### Not Parseable

**8. digimoncard.io** — Largest unparseable domain (94 URLs)
- Behind Cloudflare Managed Challenge (403 from server-side requests)
- Has a usable API (`/api/decks/{slug}/price-breakdown`) but only accessible from browser (client-side)
- Full investigation documented in `docs/solutions/digimoncard-io-decklist-parsing.md`
- **Current approach:** URL-only display, "View on digimoncard.io" in future viewer
- **Future option:** Client-side fetch from Astro site

### Removed from Allowlist

**tcgstacked.com** — No discoverable API or URL-encoded data. Zero current usage. Replaced with `bandai-tcg-plus.com`.

## JSON Format (Decided)

Using the **4-category Limitless format** to match existing data and support richer display:

```json
{
  "digimon": [
    {"count": 4, "name": "Beelzemon", "set": "BT13", "number": "087"}
  ],
  "tamer": [
    {"count": 3, "name": "Ai & Mako", "set": "BT13", "number": "093"}
  ],
  "option": [
    {"count": 2, "name": "Death Slinger", "set": "BT13", "number": "098"}
  ],
  "egg": [
    {"count": 4, "name": "Impmon", "set": "BT14", "number": "001"}
  ]
}
```

### Field Notes

- `name`: Card name from our `cards` table (looked up by `card_id` after parsing)
- `set` / `number`: Broken out from card_id for compatibility with existing Limitless format
- `count`: Quantity (1-4 typically)
- **Categories:** `digimon`, `tamer`, `option`, `egg` — matches Limitless format
- Flat parsers use card cache for type lookup; direct parsers (Bandai, digimoncard.dev deckbuilder) get types from the API response

## Implementation Phases

### Phase 1: Parser Functions + Backfill ✅

Implemented in `scripts/backfill_decklist_json.py` (Python):

1. **URL router** — `parse_decklist_url()` detects domain, dispatches to correct parser
2. **Flat parsers** (return card_id + count, enriched via card cache):
   - `parse_digimoncard_dev()` — DCG codec decode
   - `parse_digimonmeta()` — URL query param parsing
   - `parse_digitalgateopen()` — URL query param parsing
   - `parse_digimoncard_app()` — REST API fetch
3. **Direct parsers** (return 4-category JSON directly):
   - `parse_digimoncard_dev_deckbuilder()` — POST API with ddto category splitting
   - `parse_bandai_tcg_plus()` — two-step API with card type from response
4. **Card name enrichment** — `_card_cache` loaded from `cards` table, `flat_cards_to_4cat()` maps types
5. **Backfill** — 98 results backfilled, batch commits every 50, 0.5s rate limiting for API calls

### Phase 2: Scheduled Backfill (Planned)

Run the backfill script periodically to catch new submissions:
- Will be triggered from Astro site (not GitHub Actions or in-Shiny)
- Same script, same parsers — just runs on a schedule
- Currently: organizer submits URL → Shiny saves `decklist_url` only → backfill fills `decklist_json` later

### Phase 3: Decklist Viewer Modal (Future)

A new modal accessible from anywhere decklist links currently appear (tournament detail, player results, meta results, store results):

- **If `decklist_json` exists:** Render full visual decklist with card images from CDN, grouped by type
- **If only `decklist_url` exists (e.g., digimoncard.io):** Show the link with a message like "View decklist on digimoncard.io" and a note that the full card list isn't available for display
- **Card images:** Use existing CDN pattern from `cards` table (already cached)
- **Layout:** Card grid or list view, grouped by egg/digimon/tamer/option, showing card art + count

## Resolved Questions

1. **Format decision:** 4-category (`digimon`/`tamer`/`option`/`egg`) — matches existing Limitless data and `classify_decklists.py`
2. **DCG codec:** Vendored Python decoder (~150 lines) from `niamu/digimon-card-game` (EPL-2.0), embedded in backfill script
3. **API rate limits:** 0.5s sleep between API calls for digimoncard.app, bandai-tcg-plus.com, and digimoncard.dev deckbuilder
4. **digimoncard.io:** URL-only for now; client-side fetch from Astro is the future path (see `docs/solutions/digimoncard-io-decklist-parsing.md`)
5. **Backfill timing:** Python script run manually or on schedule; not in-Shiny

## Allowed Domains

```r
ALLOWED_DECKLIST_DOMAINS <- c(
  "digimoncard.dev",
  "digimoncard.io",
  "digimoncard.app",
  "digimonmeta.com",
  "digitalgateopen.com",
  "bandai-tcg-plus.com",
  "limitlesstcg.com",
  "play.limitlesstcg.com",
  "my.limitlesstcg.com"
)
```
