# Rating System Article Design

**Date:** 2026-03-02
**Status:** Approved

## Overview

Blog post for digilab.cards/blog explaining the rating system redesign to competitive Digimon TCG players. Transparency post: we found problems, we fixed them, here's the proof.

**Target:** `digilab-web` repo (Astro + MDX blog at `src/content/blog/new-rating-system.mdx`)

## Article Structure

### Metadata (MDX Frontmatter)

```yaml
title: "New Rating System: What Changed and Why"
description: "We found bugs in how ratings were calculated. Here's what we fixed, how it affects your rating, and the data to prove it."
date: 2026-03-XX  # TBD launch date
category: analysis
tags: [ratings, elo, methodology]
author: Michael Lopez
chartEmbed: /charts/rating-distribution-comparison.html
featured: true
draft: true
```

### Sections

1. **Intro** (~100 words) — Hook: "Your rating is about to change. Here's why that's a good thing." Set expectations.

2. **What Was Wrong** (~200 words) — 5 problems in plain English:
   - Adding any tournament shifted everyone's ratings (butterfly effect)
   - Future tournaments affected past calculations (time travel bug)
   - Decay penalized you for not playing recently, even if you were still good
   - Ties counted as losses
   - No incremental updates possible

3. **What Changed** (~200 words) — Side-by-side comparison table:

   | | Old | New |
   |---|---|---|
   | Processing | 5 passes, all recalculated | Single pass, chronological |
   | Decay | 4-month half-life | None |
   | Ties | Counted as loss | Proper 0.5 |
   | Adding a tournament | Shifts everyone | Only affects that date forward |
   | Backfill | Full rebuild | Recalculate from date forward |

4. **The Numbers** (~200 words + 2 charts) — Visual centerpiece:
   - **Chart 1**: Rating distribution comparison (old vs new)
   - **Chart 2**: Rank change distribution (histogram)
   - Key stats: 1096 players, 47.5% improved rank, 41.1% dropped, 11.4% stable

5. **Who Moved and Why** (~200 words + 1 chart) — Patterns without naming specific players:
   - **Chart 3**: Bump/slope chart (top ~25-30 players, old rank → new rank)
   - Players with few recent events who benefited from decay: dropped
   - Players with consistent older results: improved
   - #1 stays #1

6. **Does Playing More Help?** (~150 words + 1 chart) — Debunking the frequency bias:
   - **Chart 4**: Rank change vs events played scatter
   - Old system rewarded frequent/recent play; new system rewards skill

7. **What Your Rating Means Now** (~150 words) — Practical guide:
   - 1500 = average competitive player
   - 1400-1500 = developing
   - 1500-1600 = above average
   - 1600+ = top tier
   - Range compressed from 515 to 281 points

## Charts

### Technology
- Generated in R using `highcharter` + `atomtemplates::hc_theme_atom_switch("dark")`
- Exported as self-contained HTML via `htmlwidgets::saveWidget(chart, "name.html", selfcontained = TRUE)`
- Placed in `digilab-web/public/charts/`
- Embedded in MDX via `<ChartEmbed src="/charts/name.html" height="450px" title="..." />`

### Color Palette

**2-color charts** (distribution, bump):
- Blue: `#2D7DD2` (Digimon Blue)
- Orange: `#F7941D` (DigiLab accent)

**Positive/negative charts** (rank change histogram):
- Green: `#38A169` (improved)
- Red: `#E5383B` (dropped)

**Multi-color (if needed)**:
- Red `#E5383B`, Blue `#2D7DD2`, Green `#38A169`, Yellow `#F5B700`, Purple `#805AD5`, Black `#2D3748`

### Chart Specifications

1. **`rating-distribution-comparison.html`** (Hero chart)
   - Type: Overlaid area/density chart
   - Old distribution (orange, semi-transparent) vs new (blue)
   - Shows flat/uniform → bell curve transformation
   - X-axis: Rating (1200-1800), Y-axis: Player count/density
   - Set as `chartEmbed` in frontmatter for post card preview

2. **`rank-change-distribution.html`**
   - Type: Histogram
   - X-axis: Position change (e.g., -100 to +100)
   - Green bars for improved, red bars for dropped
   - Centered around 0, shows spread of movement

3. **`rank-bump-chart.html`**
   - Type: Dumbbell/slope chart
   - Left: Old rank, Right: New rank
   - Lines connecting each player's positions
   - Blue lines = improved, orange lines = dropped
   - Top ~25-30 players, names labeled on right
   - Interactive: hover for details

4. **`rating-vs-events.html`**
   - Type: Scatter plot
   - X-axis: Number of events played
   - Y-axis: Rank change (positive = improved)
   - Points colored blue/orange (improved/dropped)
   - Optional trend line showing no correlation (the point)

### Chart Generation Script

Location: `scripts/analysis/generate_blog_charts.R` in `digilab-app`

Data source: Comparison CSV from `scripts/analysis/snapshots/` or live DB query.

## Delivery

1. Charts generated in `digilab-app` via R script
2. HTML files copied to `digilab-web/public/charts/`
3. Article written as MDX in `digilab-web/src/content/blog/new-rating-system.mdx`
4. Published as `draft: true` initially, flip to `false` on launch day
5. Discord announcement links to article

## Data Sources

All data from the existing analysis (1096 players):
- Rating range: OLD (1245-1760) → NEW (1364-1645)
- Mean change: +1.3 points, median: +3.0
- Max increase: +146, max decrease: -176
- Std dev: 52.1 points
- 47.5% improved rank, 41.1% dropped, 11.4% stable (within ±10)
