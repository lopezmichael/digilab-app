# Mobile Players Card Redesign — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Upgrade mobile player cards with tier-colored ratings, top-3 left borders, win rate bars, and monospace rating font.

**Architecture:** Two files changed — CSS adds new player card classes and rating tier system, server R updates the card HTML template. No new queries, no new reactive values. Existing `mobile-list-card` base class is extended, not replaced.

**Tech Stack:** R Shiny (server-side HTML), CSS (mobile.css)

---

### Task 1: Add CSS — Rating tier classes and player card enhancements

**Files:**
- Modify: `www/mobile.css` (append after line 79, the `.mobile-card-rank.rank-3` rule)

**Step 1: Add rating tier color classes**

Append to `www/mobile.css` after the rank color rules (line 79):

```css
/* ---------------------------------------------------------------------------
 * Player Card Enhancements — tier colors, left borders, win rate bar
 * --------------------------------------------------------------------------- */

/* Rating tier colors (fixed thresholds) */
.rating-tier-elite  { color: #FFD700 !important; }
.rating-tier-strong { color: #00C8FF !important; }
.rating-tier-good   { color: #4CAF50 !important; }
.rating-tier-low    { opacity: 0.5; }

/* Rating value in monospace */
.mobile-card-rating {
  font-family: 'Fira Code', monospace;
  font-weight: 700;
  font-size: 0.9rem;
}

/* Top 3 left border accents */
.mobile-list-card.player-rank-1 {
  border-left: 3px solid #FFD700;
}

.mobile-list-card.player-rank-2 {
  border-left: 3px solid #C0C0C0;
}

.mobile-list-card.player-rank-3 {
  border-left: 3px solid #CD7F32;
}

/* Win rate bar */
.mobile-winrate-bar {
  height: 4px;
  border-radius: 2px;
  background: rgba(128, 128, 128, 0.15);
  margin-top: 0.35rem;
  overflow: hidden;
  flex: 1;
  max-width: 60%;
}

.mobile-winrate-fill {
  height: 100%;
  border-radius: 2px;
  transition: width 0.3s ease;
}

.mobile-winrate-fill.winrate-high   { background: #4CAF50; }
.mobile-winrate-fill.winrate-mid    { background: #F7941D; }
.mobile-winrate-fill.winrate-low    { background: #E53935; }
```

**Step 2: Verify CSS parses**

Open `www/mobile.css` and visually confirm no syntax errors in the appended block.

**Step 3: Commit**

```bash
git add www/mobile.css
git commit -m "feat: add player card CSS — tier colors, left borders, win rate bar"
```

---

### Task 2: Update server — Rebuild card HTML template

**Files:**
- Modify: `server/public-players-server.R:431-490` (the `lapply` card builder inside `output$mobile_players_cards`)

**Step 1: Replace the card builder**

In `server/public-players-server.R`, replace the `lapply` block (lines 431–490) with:

```r
  cards <- lapply(seq_len(nrow(display)), function(i) {
    row <- display[i, ]
    rank <- i

    # Rating tier class
    rating <- as.integer(row$competitive_rating)
    rating_class <- if (rating >= 1800) "rating-tier-elite"
                    else if (rating >= 1700) "rating-tier-strong"
                    else if (rating >= 1600) "rating-tier-good"
                    else if (rating < 1500) "rating-tier-low"
                    else ""

    # Card class with optional top-3 left border
    card_class <- paste("mobile-list-card",
      if (rank == 1) "player-rank-1"
      else if (rank == 2) "player-rank-2"
      else if (rank == 3) "player-rank-3"
      else "")

    # Win percentage
    win_pct_num <- if (!is.na(row$Win_Pct)) row$Win_Pct else 0
    win_pct <- if (!is.na(row$Win_Pct)) paste0(row$Win_Pct, "%") else "-"

    # Win rate bar color
    winrate_color <- if (win_pct_num >= 60) "winrate-high"
                     else if (win_pct_num >= 40) "winrate-mid"
                     else "winrate-low"

    # Record string: W-L or W-L-T
    record <- sprintf("%d-%d", as.integer(row$W), as.integer(row$L))
    if (!is.na(row$T) && row$T > 0) {
      record <- sprintf("%s-%d", record, as.integer(row$T))
    }

    # Main deck badge (unchanged logic)
    deck_tag <- if (nchar(row$main_deck) > 0) {
      color_class <- if (nchar(row$main_deck_color) > 0) {
        paste0("deck-badge deck-badge-", tolower(row$main_deck_color))
      } else {
        "deck-badge"
      }
      tags$span(class = color_class, row$main_deck)
    } else {
      NULL
    }

    div(
      class = card_class,
      onclick = sprintf("Shiny.setInputValue('player_clicked', %d, {priority: 'event'})", row$player_id),

      # Row 1: Rank + Name + Rating (monospace, tier-colored)
      div(class = "mobile-card-row",
        div(style = "display: flex; align-items: baseline; gap: 0.5rem;",
          span(class = paste("mobile-card-rank",
            if (rank == 1) "rank-1" else if (rank == 2) "rank-2" else if (rank == 3) "rank-3" else ""),
            rank),
          span(class = "mobile-card-primary", row$Player)
        ),
        span(class = paste("mobile-card-rating", rating_class), rating)
      ),

      # Row 2: Deck badge + Record + Win%
      div(class = "mobile-card-row",
        div(class = "mobile-card-secondary",
          if (!is.null(deck_tag)) tagList(deck_tag, span(style = "margin-left: 0.5rem;", record, " ", win_pct))
          else tagList(span(record), span(style = "margin-left: 0.5rem;", win_pct))
        ),
        div(class = "mobile-card-tertiary",
          sprintf("%d events", as.integer(row$Events))
        )
      ),

      # Row 3: Win rate bar
      div(class = "mobile-card-row", style = "align-items: center;",
        div(class = "mobile-winrate-bar",
          div(class = paste("mobile-winrate-fill", winrate_color),
              style = sprintf("width: %s%%", win_pct_num))
        )
      )
    )
  })
```

Key changes from the old template:
- `mobile-list-card` gets `player-rank-N` class for top-3 left borders
- Rating displayed with `mobile-card-rating` + tier class instead of plain `mobile-card-stat`
- Deck badge and record merged onto one row
- Win rate bar added as row 3
- Rank class logic stays the same (colored numbers)

**Step 2: Verify R syntax**

```bash
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "parse(file='server/public-players-server.R'); cat('OK\n')"
```

Expected: `OK`

**Step 3: Commit**

```bash
git add server/public-players-server.R
git commit -m "feat: redesign mobile player cards with tier ratings, borders, win bars"
```

---

### Task 3: Manual verification

**Step 1: Run the app**

Ask user to run `shiny::runApp()` and check:

1. **Mobile Players tab**: Cards show gold/silver/bronze left borders for top 3
2. **Rating numbers**: Monospace font, colored by tier (gold 1800+, cyan 1700+, green 1600+, default 1500s, muted <1500)
3. **Win rate bars**: Thin colored bars under each card (green/amber/red)
4. **Deck badges**: Still showing with color coding on row 2
5. **Card tap**: Opens player detail modal
6. **Load more**: Button still works
7. **Desktop**: Unchanged (these classes only appear in mobile render path)

**Step 2: Commit any fixes, then final commit**

```bash
git add -A
git commit -m "fix: player card adjustments from manual testing"
```
