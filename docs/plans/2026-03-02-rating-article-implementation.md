# Rating System Article Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a blog post with 4 interactive Highcharter charts explaining the rating system redesign to players.

**Architecture:** Generate comparison data and 4 self-contained HTML charts from R (highcharter + atomtemplates theme), then write the MDX article in the digilab-web Astro blog. Charts are exported as standalone HTML widgets and embedded via the existing `<ChartEmbed>` component.

**Tech Stack:** R (highcharter, htmlwidgets, atomtemplates), Astro MDX blog

**Repos:**
- `E:\Michael Lopez\Projects\repos\digilab-app` — chart generation script + comparison data
- `E:\Michael Lopez\Projects\repos\digilab-web` — blog article + chart HTML files

---

### Task 1: Generate Fresh Comparison Data

The snapshot directory is empty — we need fresh CSV data comparing old vs new algorithms.

**Files:**
- Run: `scripts/analysis/compare_algorithms_readonly.R`
- Output: `scripts/analysis/snapshots/algorithm_comparison_*.csv`

**Step 1: Run the comparison script**

```bash
cd "E:\Michael Lopez\Projects\repos\digilab-app"
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "source('scripts/analysis/compare_algorithms_readonly.R'); run_comparison()"
```

Expected: CSV written to `scripts/analysis/snapshots/` with columns: `player_id`, `display_name`, `competitive_rating_old`, `competitive_rating_new`, `events_played`, `rating_change`, `rank_old`, `rank_new`, `rank_change`

**Step 2: Verify the data**

```bash
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" -e "
  d <- read.csv(list.files('scripts/analysis/snapshots', pattern='algorithm_comparison', full.names=TRUE)[1])
  cat('Rows:', nrow(d), '\n')
  cat('Columns:', paste(names(d), collapse=', '), '\n')
  cat('Rating range OLD:', range(d\$competitive_rating_old), '\n')
  cat('Rating range NEW:', range(d\$competitive_rating_new), '\n')
"
```

Expected: ~1100+ rows with all expected columns.

**Step 3: Commit**

```bash
git add scripts/analysis/snapshots/
git commit -m "data: generate fresh algorithm comparison snapshot"
```

---

### Task 2: Create Blog Chart Generation Script

Create a single R script that generates all 4 interactive Highcharter charts as self-contained HTML files.

**Files:**
- Create: `scripts/analysis/generate_blog_charts.R`

**Step 1: Write the chart generation script**

The script must:
1. Load comparison CSV from `scripts/analysis/snapshots/`
2. Generate 4 charts using `highcharter` with `atomtemplates::hc_theme_atom_switch("dark")` as base theme
3. Override series colors with Digimon card palette:
   - 2-color: Blue `#2D7DD2`, Orange `#F7941D`
   - Positive/negative: Green `#38A169`, Red `#E5383B`
4. Export each as self-contained HTML via `htmlwidgets::saveWidget()`
5. Save to a configurable output directory (default: `../digilab-web/public/charts/`)

**Chart 1: `rating-distribution-comparison.html`**
- Type: `hc_chart(type = "areaspline")` with two overlaid series
- Compute density/histogram bins for old and new ratings (binwidth ~15)
- Old series: orange `#F7941D`, opacity 0.4
- New series: blue `#2D7DD2`, opacity 0.6
- X-axis: "Rating" (range ~1200-1800)
- Y-axis: "Players"
- Subtitle: "Old system (orange) produced a flat spread. New system (blue) produces a proper bell curve."

**Chart 2: `rank-change-distribution.html`**
- Type: `hc_chart(type = "column")`
- Histogram of `rank_change` column (bin size ~10 positions)
- Color each bar: green `#38A169` if bin center > 0, red `#E5383B` if < 0, gray if ~0
- X-axis: "Rank Change (positions)"
- Y-axis: "Number of Players"
- Subtitle: "Positive = improved rank. 47.5% of players moved up."

**Chart 3: `rank-bump-chart.html`**
- Type: `hc_chart(type = "dumbbell")` or custom with `hc_add_series` using line segments
- Show top 25 players by old rank
- Each player: a horizontal line from (old_rank, player_name) to (new_rank, player_name)
- Blue `#2D7DD2` lines for players who improved, orange `#F7941D` for dropped
- Y-axis: player display names (categorical)
- X-axis: "Rank Position" (inverted — #1 at top)
- Tooltip: "{name}: #{old_rank} → #{new_rank} ({change})"

Implementation note: Highcharts doesn't have a native dumbbell. Use two `scatter` series (old rank dots, new rank dots) connected by `line` segments, or use the `highcharter::hc_add_series` with `type = "columnrange"` rotated horizontally. Alternative: use a simple `type = "scatter"` with two x-values per player and draw connecting lines via `plotLines` or `hc_add_series(type = "line")` per player.

Simplest approach: Use a horizontal bar/range chart where each bar goes from old_rank to new_rank for each player. `type = "columnrange"` with `inverted = TRUE`.

**Chart 4: `rating-vs-events.html`**
- Type: `hc_chart(type = "scatter")`
- X-axis: "Events Played", Y-axis: "Rank Change"
- Points colored: blue `#2D7DD2` if rank_change > 0, orange `#F7941D` if < 0
- Add a horizontal reference line at y = 0
- Tooltip: "{name}: {events} events, rank {change}"
- Subtitle: "No correlation between playing more and ranking higher — skill matters, not frequency."

**All charts shared config:**
- Base theme: `atomtemplates::hc_theme_atom_switch("dark")`
- Background: transparent (for iframe embedding)
- Font: inherit from page
- Responsive: `hc_responsive()` or let Highcharts handle it
- Credits: disabled (`hc_credits(enabled = FALSE)`)
- Exporting: disabled (`hc_exporting(enabled = FALSE)`)

**Step 2: Run the script and verify output**

```bash
"/c/Program Files/R/R-4.5.1/bin/Rscript.exe" scripts/analysis/generate_blog_charts.R
```

Expected: 4 HTML files written to `../digilab-web/public/charts/`

**Step 3: Verify charts load in browser**

Open each HTML file directly in a browser to confirm they render correctly with dark theme and proper colors.

**Step 4: Commit in both repos**

```bash
# digilab-app
cd "E:\Michael Lopez\Projects\repos\digilab-app"
git add scripts/analysis/generate_blog_charts.R
git commit -m "feat: add blog chart generation script for rating article"

# digilab-web
cd "E:\Michael Lopez\Projects\repos\digilab-web"
git add public/charts/
git commit -m "feat: add rating system comparison charts"
```

---

### Task 3: Write the Blog Article

Create the MDX blog post in the digilab-web repo.

**Files:**
- Create: `E:\Michael Lopez\Projects\repos\digilab-web\src\content\blog\new-rating-system.mdx`

**Step 1: Write the MDX article**

Frontmatter:
```yaml
---
title: "New Rating System: What Changed and Why"
description: "We found bugs in how ratings were calculated. Here's what we fixed, how it affects your rating, and the data to prove it."
date: 2026-03-02
category: analysis
tags: [ratings, elo, methodology]
author: Michael Lopez
chartEmbed: /charts/rating-distribution-comparison.html
featured: true
draft: true
---
```

Import the ChartEmbed component at the top of the MDX:
```mdx
import ChartEmbed from '../../components/ChartEmbed.astro';
```

Article sections (follow the design doc `docs/plans/2026-03-02-rating-article-design.md`):

1. **Intro** (~100 words) — "Your rating is about to change." Direct, no fluff.

2. **What Was Wrong** (~200 words) — 5 problems as a numbered list. Plain English, no jargon. Example framing:
   - "Every time we added a new tournament, every single player's rating shifted — even players who weren't in that tournament."
   - "Ties were counted as losses. If you and another player tied, you both lost rating."

3. **What Changed** (~200 words) — Markdown table comparing old vs new:

   | | Old System | New System |
   |---|---|---|
   | How it calculates | Recalculates everything 5 times | Processes each tournament once, in order |
   | Decay | Recent events count more, old ones fade | No decay — results are permanent |
   | Ties | Counted as a loss | Properly scored as a draw |
   | Adding a tournament | Shifts every player's rating | Only affects players from that date forward |

4. **The Numbers** (~200 words) — Stats + 2 charts:
   - Embed: `<ChartEmbed src="/charts/rating-distribution-comparison.html" height="450px" title="Rating Distribution: Before vs After" />`
   - Key stats: 1096 players analyzed, mean change +1.3, range compressed from 515 to 281 points
   - Embed: `<ChartEmbed src="/charts/rank-change-distribution.html" height="400px" title="How Many Positions Players Moved" />`
   - 47.5% improved rank, 41.1% dropped, 11.4% stayed within 10 spots

5. **Who Moved and Why** (~200 words) — Bump chart + explanation:
   - Embed: `<ChartEmbed src="/charts/rank-bump-chart.html" height="600px" title="Top 25 Players: Old Rank vs New Rank" />`
   - Patterns: low-event players who benefited from decay dropped; consistent players with older results improved

6. **Does Playing More Help?** (~150 words) — Scatter + debunk:
   - Embed: `<ChartEmbed src="/charts/rating-vs-events.html" height="400px" title="Rank Change vs Events Played" />`
   - "No. The old system rewarded showing up. The new one rewards winning."

7. **What Your Rating Means Now** (~150 words) — Practical guide as a simple table:
   - 1600+ = Top tier
   - 1500-1600 = Above average
   - 1400-1500 = Developing
   - Below 1400 = Getting started
   - "The gaps are smaller now, which means every point matters more."

**Step 2: Verify locally**

```bash
cd "E:\Michael Lopez\Projects\repos\digilab-web"
npm run dev
```

Open `http://localhost:4321/blog/new-rating-system` and verify:
- Article renders with all sections
- All 4 charts load in iframes
- Charts are interactive (hover tooltips work)
- Dark/light theme toggle works
- Mobile responsive

**Step 3: Commit**

```bash
cd "E:\Michael Lopez\Projects\repos\digilab-web"
git add src/content/blog/new-rating-system.mdx
git commit -m "feat: add rating system redesign article (draft)"
```

---

### Task 4: Final Review and Polish

**Step 1: Read through the full article end-to-end**

Check for:
- Tone: casual and direct, not corporate
- Flow: each section logically follows the previous
- Charts: each has context before and after
- No jargon without explanation
- Stats are accurate (cross-reference with `docs/plans/2026-03-01-rating-redesign-report.md`)

**Step 2: Verify chart responsiveness on mobile**

Use browser dev tools to check charts at 375px width.

**Step 3: Push both repos**

```bash
# digilab-app
cd "E:\Michael Lopez\Projects\repos\digilab-app"
git push origin develop

# digilab-web
cd "E:\Michael Lopez\Projects\repos\digilab-web"
git push
```

Note: Article stays `draft: true` until ready for the coordinated launch with the rating go-live.
