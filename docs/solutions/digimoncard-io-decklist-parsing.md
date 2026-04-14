# digimoncard.io Decklist Parsing

**Date:** 2026-04-12
**Status:** Deferred — URL-only display for now
**Context:** v2.1.0 decklist pipeline investigation

## Current State

- 94 results across 79 unique digimoncard.io URLs, no `decklist_json`
- Two URL patterns:
  - `/deck/{slug}` (74 URLs) — e.g., `olympos-xii-by-vpassion-148440`
  - `/api/url-shorten/{code}` (20 URLs) — e.g., `z3l`
- All endpoints blocked by Cloudflare Managed Challenge (403 from server-side requests)

## What We Found

### JS Bundle Analysis

The deck viewer JS (`/build/assets/deck-show-D6GTzQ4p.js`) reveals these API endpoints:

| Endpoint | Method | Returns |
|----------|--------|---------|
| `/api/decks/{slug}/price-breakdown?type=tcgplayer` | GET | Card list with `card_number`, `card_name`, `quantity`, prices |
| `/api/decks/search?name={query}&limit=10` | GET | Deck search results |
| `/api/decks/compare?deck1={url}&deck2={url}` | GET | Deck comparison |
| `/api/decks/{slug}/download-images` | GET | ZIP of card images |

### Price Breakdown Endpoint (Most Useful)

From browser console (behind Cloudflare, so only works client-side):

```js
fetch('/api/decks/olympos-xii-by-vpassion-148440/price-breakdown?type=tcgplayer')
  .then(r => r.json())
  .then(d => console.log(d))
```

Returns:
```json
{
  "breakdown": [
    {
      "card_number": "BT24-031",
      "card_name": "Elecmon",
      "quantity": 4,
      "price_each": 0.2,
      "total_price": 0.8,
      "product_id": 670217,
      "set_name": "Time Stranger",
      "purchase_url": "https://..."
    }
  ],
  "total_price": 278.87,
  "cards_without_prices": 1
}
```

This gives us everything needed for `decklist_json` — `card_number`, `card_name`, `quantity`. Category (egg/digimon/tamer/option) can be derived from our `cards` table.

### Deck Data Structure

The JS also reveals the internal deck model:
- `mainDeck`, `eggDeck`, `sideDeck` arrays
- Cards have: `card_number`, `name`, `quantity`, `image_url`
- Deck metadata: `deckPrettyUrl`, `deckNum`, `deckName`

## Why Server-Side Parsing Doesn't Work

- Every endpoint (pages, API, URL shortener) returns Cloudflare Managed Challenge
- Requires real browser with JS execution + fingerprinting to pass
- Changing User-Agent or adding cookies doesn't bypass it
- The `origin` header alone is not sufficient

## Future Options

### Option A: Client-Side Fetch from Astro Site
When building the decklist viewer on the Astro site, the user's browser could call the price-breakdown API directly (not blocked by Cloudflare since it's a real browser). The Astro site could then send the parsed data back to our API.

### Option B: DCG Code Paste Field
digimoncard.io supports exporting decks as DCG codes. Add a "Paste DCG code" field alongside the URL field in the submit form. Organizers copy the code from digimoncard.io, we parse it locally with zero external calls.

### Option C: Browser-Based Batch Extraction (One-Time)
For the existing 94 results, a console script could iterate all slugs, call the price-breakdown API, and export a JSON blob for import. Only useful as a one-time backfill.

### Option D: Ask digimoncard.io for API Access
Reach out to the site maintainers about a public API or whitelisted access for community tools.

## Decision

Keeping digimoncard.io as URL-only display for now. The future decklist viewer modal will show "View on digimoncard.io" with a link. Revisit when building Astro site features — Option A (client-side fetch) is the most seamless if we have a server component to receive the data.
