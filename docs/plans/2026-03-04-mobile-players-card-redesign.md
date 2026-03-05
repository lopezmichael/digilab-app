# Mobile Players Card Redesign

**Date:** 2026-03-04
**Status:** Approved
**Target:** v1.3.0

## Goal

Upgrade the mobile player cards from plain text rows to styled cards matching the dashboard's design quality, with rating + identity as the dual focus.

## Card Layout

```
┌─────────────────────────────────────────┐
│▌ #1  PlayerName                  1742   │  ← gold left border (top 3)
│      Agumon Badge        8-2 (80%)      │  ← deck + record
│      ████████░░           12 events     │  ← win rate bar + events
└─────────────────────────────────────────┘
```

- **Top row**: Rank number + player name (bold) + rating in JetBrains Mono with tier color
- **Middle row**: Main deck badge (color-coded, unchanged) + W-L record with win%
- **Bottom row**: Thin (4px) win rate bar + event count

## Visual Treatments

### Left Border (Top 3)
- Rank 1: Gold (#FFD700)
- Rank 2: Silver (#C0C0C0)
- Rank 3: Bronze (#CD7F32)
- Rank 4+: No left border accent

### Rating Tier Colors (Fixed Thresholds)
| Rating | Color | Class | Meaning |
|--------|-------|-------|---------|
| 1800+ | Gold (#FFD700) | `rating-tier-elite` | Elite |
| 1700-1799 | Cyan (#00C8FF) | `rating-tier-strong` | Strong |
| 1600-1699 | Green (#4CAF50) | `rating-tier-good` | Above average |
| 1500-1599 | Default text color | (no class) | Average |
| Below 1500 | Muted (opacity 0.5) | `rating-tier-low` | Below average |

Thresholds are fixed. New tiers (1900+, 2000+) can be added later as CSS classes.

### Win Rate Bar
- Thin (4px) horizontal bar below record
- Green (#4CAF50) for 60%+, amber (#F7941D) for 40-59%, red (#E53935) for below 40%
- Width = win percentage

### Rating Font
JetBrains Mono — matches Rising Stars cards on dashboard.

## What Stays the Same
- Card tap → player detail modal
- Load-more pagination (20 at a time)
- Search, format filter, min events filter
- Empty states
- Deck badges (existing color-coded badges)

## Files to Modify
- `server/public-players-server.R` — Update card HTML in `output$mobile_players_cards`
- `www/mobile.css` — Add player card styles, rating tier classes, win rate bar
