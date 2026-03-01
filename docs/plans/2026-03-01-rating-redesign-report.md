# Rating System Redesign - Analysis Report

**Date:** 2026-03-01
**Status:** Analysis Complete, Pending Go-Live
**Related:** `docs/plans/2026-03-01-rating-system-redesign.md`

## Overview

This document captures the analysis and comparison between the old (5-pass with decay) and new (single-pass chronological) rating algorithms. This will serve as the basis for a public-facing blog post explaining the changes to players.

## Key Findings

### Distribution Shape

| Metric | OLD Algorithm | NEW Algorithm |
|--------|---------------|---------------|
| Rating Range | 1245 - 1760 (515 spread) | 1364 - 1645 (281 spread) |
| Mean Rating | 1497.9 | 1499.2 |
| Distribution Shape | Flat/Uniform | Bell Curve |

**The flat distribution in the old system was a red flag.** Proper Elo systems produce bell curves centered around the starting rating (1500). The decay mechanism was artificially spreading ratings out.

### Rating Changes (NEW - OLD)

- **Mean change:** +1.3 points
- **Median change:** +3.0 points
- **Max increase:** +146 points
- **Max decrease:** -176 points
- **Std deviation:** 52.1 points

### Rank Changes

| Change | Players | Percentage |
|--------|---------|------------|
| Improved 50+ positions | 293 | 26.7% |
| Improved 10-49 positions | 228 | 20.8% |
| Within ±10 positions | 125 | 11.4% |
| Dropped 10-49 positions | 206 | 18.8% |
| Dropped 50+ positions | 244 | 22.3% |

**Key observation:** More players improve rank (47.5%) than drop (41.1%), with 11.4% staying roughly the same.

### Who Was Most Affected

**Biggest rating drops:** Players with few events who played recently
- These players benefited most from: provisional K-factor + recent tournaments weighted heavily by decay
- Example: Adson went from #2 to #20 (only 4 events)

**Biggest rating gains:** Players with older events
- Their historical results are no longer penalized by decay
- Example: mako gained +146 points

### Specific Player Examples

| Player | OLD | NEW | Change | Rank Change |
|--------|-----|-----|--------|-------------|
| Nudes | 1647 (#46) | 1562 (#48) | -85 | -2 |
| PhotonZX24 | 1635 (#60) | 1546 (#79) | -89 | -19 |
| atomshell | 1514 (#454) | 1504 (#446) | -10 | +8 |

### Top 20 Stability

- **#1 (Rodrigo) stays #1** ✓
- Most top players remain in top 20, just with different numbers
- Significant shuffling in positions 2-20 due to decay removal

## Visualizations Generated

All saved in `scripts/analysis/snapshots/`:

1. `histogram_before_after.png` - Side-by-side distributions
2. `histogram_overlay.png` - Overlayed distributions with density curves
3. `histogram_rating_change.png` - Distribution of rating changes
4. `histogram_rank_change.png` - Distribution of rank changes
5. `scatter_old_vs_new.png` - Old vs new rating scatter plot
6. `scatter_rank_vs_events.png` - Rank change vs events played

## Messaging for Players

### Key Talking Points

1. **Rankings matter more than raw numbers** - positions are more stable than the numbers suggest
2. **The spread was artificial** - decay made it look like there was more skill difference than existed
3. **New system is fairer** - players aren't punished for taking breaks
4. **Everyone's numbers compressed** - it's not that anyone got worse, the scale is more accurate

### Simple Analogy

> "The old system gave bonus points for playing recently, which artificially inflated active players and penalized those who took breaks. The new system measures skill more accurately - your rating reflects your results, not when you played. Think of it like removing grade inflation: a B is still a B, the numbers are just more honest now."

### Technical Explanation (for those who want details)

The old algorithm had several issues:
1. **5-pass iteration** - recalculated everything when any tournament was added
2. **Time-based decay** - recent tournaments counted more, anchored to "today"
3. **Ties as losses** - tied placements were treated as 0 instead of 0.5

The new algorithm:
1. **Single-pass chronological** - processes tournaments once in date order
2. **No decay** - standard Elo doesn't use time-based weighting
3. **Proper tie handling** - ties are 0.5 (draw)

## Future: Blog/Website Ideas

### Proposed: DigiLab Blog/News Section

Create a blog or news section on digilab.cards to:
- Announce major changes like this rating redesign
- Explain methodology transparently
- Share meta analysis and insights
- Build community trust through transparency

### First Post: "Rating System v2.0"

Structure:
1. **Why we changed it** - problems with the old system
2. **What changed** - technical summary (accessible)
3. **How it affects you** - practical impact
4. **Visualizations** - the histograms showing before/after
5. **FAQ** - common questions

### Link to Roadmap

The blog could also link to:
- Public roadmap showing what's coming
- Changelog for recent updates
- FAQ/methodology documentation

## Files Created

### Analysis Scripts
- `scripts/analysis/rating_comparison.R` - Snapshot capture/compare tool
- `scripts/analysis/compare_algorithms_readonly.R` - Read-only algorithm comparison
- `scripts/analysis/visualize_comparison.R` - ggplot2 visualizations
- `scripts/analysis/capture_pre_redesign.R` - Pre-redesign snapshot wrapper
- Various helper scripts

### Data Files (gitignored)
- `scripts/analysis/snapshots/*.csv` - Comparison data
- `scripts/analysis/snapshots/*.png` - Generated charts

### Database
- `db/migrations/004_player_rating_history.sql` - New table for rating history
- Table created but empty (no data pushed yet)

## Next Steps

1. [ ] Write public-facing blog post based on this analysis
2. [ ] Consider adding blog/news section to digilab.cards
3. [ ] Get final approval on the algorithm changes
4. [ ] Push new algorithm to production
5. [ ] Announce in Discord with link to blog post
6. [ ] Monitor feedback and questions

## Rollback Plan

If issues arise after go-live:
1. Revert `R/ratings.R` to use `calculate_competitive_ratings()` (old algorithm)
2. Run `recalculate_ratings_cache(db_con, use_legacy = TRUE)`
3. Ratings will return to old values
