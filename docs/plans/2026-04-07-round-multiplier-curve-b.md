# Round Multiplier Curve B — Large Event Rating Scaling

**Date:** 2026-04-07
**Status:** Planned
**Roadmap ID:** `round-multiplier-curve-b`

## Problem

A player placing 9th out of 234 players at a regional (+10) gained roughly the same rating as placing 1st out of 12 at a weekly local (+9). Players expect large, competitive events to carry more weight.

### Root Cause

The rating algorithm normalizes by dividing by `num_opponents` (line 167 in `R/ratings.R`). This normalization exists because the system creates N-1 "implied matchups" from final standings (since we don't have round-by-round results for most events). The division prevents artificial inflation from those implied matchups — but it also perfectly cancels out tournament size.

Mathematically, the rating change for a 1st place finish simplifies to:

```
change = K × (1 - avg_expected_score) × round_mult
```

The `num_opponents` in the sum and the `/ num_opponents` normalization cancel out entirely. **Tournament size is a non-factor.**

The only size-adjacent lever is the round multiplier, which caps at 1.4 for 7+ rounds. An 8-round 234-player regional gets the same multiplier as a hypothetical 7-round 16-player event.

### Why Normalization Exists (and should stay)

Standard Elo systems (FIDE chess, Glicko, TrueSkill) process actual head-to-head games and let changes accumulate — more games = more total change. Our system doesn't have round-by-round results for most tournaments, only final standings. We infer N-1 "virtual matchups" per player against every other player.

Without normalization, a 234-player event would create 233 implied games per player, producing rating swings of ±200+ points. The `/num_opponents` normalization brings implied matchups back to a single representative result.

The normalization is correct for what it does. The problem is that tournament size information is lost in the process, and the round multiplier cap prevents rounds from compensating.

## Solution: Curve B Round Multiplier

Adjust the round multiplier formula so that events with 5+ rounds (which correlate strongly with larger, more competitive events) carry progressively more weight.

### Formula

```
rounds <= 4:  round_mult = 1.0 + (rounds - 3) × 0.1     (unchanged)
rounds > 4:   round_mult = 1.1 + (rounds - 4) × 0.2     (steeper slope, no cap)
```

### Multiplier Table

| Rounds | Current | Curve B | Change |
|--------|---------|---------|--------|
| 1      | 0.8     | 0.8     | —      |
| 2      | 0.9     | 0.9     | —      |
| 3      | 1.0     | 1.0     | —      |
| 4      | 1.1     | 1.1     | —      |
| **5**  | 1.2     | **1.3** | +8%    |
| **6**  | 1.3     | **1.5** | +15%   |
| **7**  | 1.4     | **1.7** | +21%   |
| **8**  | 1.4 (cap) | **1.9** | +36%   |
| **9**  | 1.4 (cap) | **2.1** | +50%   |
| **10** | 1.4 (cap) | **2.3** | +64%   |

### Why This Works

- Rounds correlate strongly with event size (avg players: 3 rounds → 9, 5 rounds → 28, 8 rounds → 181)
- Rounds reflect actual competitive rigor — more rounds of Swiss pairing = more refined placements
- No new concepts — just a formula tweak to an existing parameter
- Easy to explain: "events with more rounds of competitive play carry more weight"

## Impact Analysis

### Tournament Distribution

| Rounds | Tournaments | Unique Players | % Increase |
|--------|-------------|----------------|------------|
| 5      | 117         | 882            | +8%        |
| 6      | 14          | 174            | +15%       |
| 8      | 2           | 362            | +36%       |
| **Total affected** | **133 (6%)** | **1,151 (27%)** | |
| Unaffected (1-4 rounds) | 2,051 (94%) | 3,146 (73%) | |

### Rating Change Impact (1st Place Average)

| Size Bucket | Avg Rounds | Tournaments | Current | Curve B |
|-------------|-----------|-------------|---------|---------|
| 4-7 players | 2.8 | 630 | +16.5 | +16.5 (unchanged) |
| 8-11 | 3.3 | 789 | +16.5 | +16.6 (unchanged) |
| 12-15 | 3.6 | 350 | +16.7 | +16.7 (unchanged) |
| 16-23 | 4.0 | 211 | +17.9 | +18.2 (+0.3) |
| 24-31 | 4.5 | 71 | +16.6 | +17.3 (+0.7) |
| 32-63 | 5.1 | 59 | +15.1 | +16.3 (+1.2) |
| **64+** | **8.0** | **2** | **+25.5** | **+34.6 (+9.1)** |

### Net Rating Impact Distribution

| Impact Range | Players |
|-------------|---------|
| > +10 points | 24 |
| +6 to +10 | 64 |
| +1 to +5 | 346 |
| No change | 177 |
| -1 to -5 | 441 |
| -6 to -10 | 82 |
| < -10 points | 17 |

Most affected players shift by 1-5 points. Largest individual impacts: +24 (top performer across multiple 5+ round events) and -14 (poor performer across multiple 5+ round events).

### Key Example: roy1001 at 234-Player Regional

| Player | Rating Before | Current | Curve B |
|--------|--------------|---------|---------|
| roy1001 (9th, established) | 1613 | +10 | **+14** |
| 1st place (provisional, 1500) | 1500 | +34 | **+46** |
| Last place (provisional, 1500) | 1500 | -33 | **-45** |

### Hypothetical Worlds (500 players, 10 rounds)

| Winner's Rating | Current | Curve B |
|----------------|---------|---------|
| 1600 (good) | +13 | **+22** |
| 1700 (great) | +9 | **+15** |
| 1800 (best in world) | +6 | **+10** |

## Alternatives Considered

### Option A: Remove Round Cap Only
Just removing the 1.4 cap gives 1.5 for 8 rounds — only a 7% bump (1.5/1.4). Too small to matter because the `/num_opponents` normalization is the dominant force.

### Option C: Aggressive Curve (0.3/round above 4)
Rounds 8 → 2.3, rounds 10 → 2.9. Provisional players at large events would see swings of ±54, which feels too punishing for casual players attending their first major event.

### Size Multiplier (flat 1.5× for 64+)
Simple "major event" flag. Clean and surgical but doesn't differentiate between event sizes above 64, doesn't help 32-63 player events at all, and introduces a second multiplier concept.

### Remove Normalization Entirely
Academically correct (standard Elo) but would multiply all rating changes by 3-8× across every tournament size. Complete disruption of existing ratings.

### sqrt(rounds) / sqrt(num_opponents) Normalization
Dampened version of removing normalization. Still doubles most changes across all tournament sizes — too disruptive.

## Implementation

### Code Change

Single change in `R/ratings.R`, `calculate_ratings_single_pass()`:

```r
# Current (line 126-127):
rounds <- if (is.na(tourney$rounds)) 3 else tourney$rounds
round_mult <- min(1.0 + (rounds - 3) * 0.1, 1.4)

# Curve B:
rounds <- if (is.na(tourney$rounds)) 3 else tourney$rounds
round_mult <- if (rounds <= 4) {
  1.0 + (rounds - 3) * 0.1
} else {
  1.1 + (rounds - 4) * 0.2
}
```

Also update the legacy `calculate_competitive_ratings()` function (line 322-323) to match, for consistency.

### Deployment Steps

1. Create feature branch `fix/round-multiplier-curve-b`
2. Update round multiplier formula in both functions
3. Run full rating rebuild (`calculate_ratings_single_pass` with `from_date = NULL`)
4. Verify rating history changes match expected impact
5. Update methodology documentation / blog post
6. Communicate change to community before deploying

### Communication Plan

**Framing for players:**

> We adjusted how the rating system weights tournaments with more rounds of competitive play. Previously, the bonus for longer events capped at 7 rounds — meaning an 8-round regional with 234 players counted the same as a 7-round event. Now, each additional round above 4 carries more weight, reflecting the deeper competitive signal that longer Swiss tournaments provide.
>
> **What changed:**
> - Events with 4 or fewer rounds (90%+ of weekly locals): no change
> - Events with 5-6 rounds: small increase (~8-15%)
> - Events with 8+ rounds (regionals, majors): meaningful increase (~36%)
>
> **Why:** More rounds of Swiss pairing means stronger opponents at your skill level and more refined final standings. Placing well at a major event should be worth more than the same placement at a weekly local.
>
> Most players will see their rating shift by 1-5 points. Players who performed well at larger events will see modest gains; players who performed poorly at them will see modest dips.

## Why Not Address the Normalization Directly?

The `/num_opponents` normalization is technically a departure from standard Elo, but it has produced stable, predictable ratings across 2,100+ tournaments and 4,300+ players. Changing it would re-rate every player by significant amounts.

The round multiplier approach threads the needle: it uses an existing, understood parameter to reintroduce size sensitivity without disrupting the foundation. If the platform grows to host many more large events, a deeper normalization rework can be revisited — but Curve B handles the current and near-future needs cleanly.
