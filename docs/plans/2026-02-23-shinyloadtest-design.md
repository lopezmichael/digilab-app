# MR17: shinyloadtest Performance Profiling — Design Document

**Date:** 2026-02-23
**Status:** Approved
**Goal:** Profile DigiLab locally to identify performance bottlenecks and determine the Posit Connect tier needed for 75-100 concurrent users.

## Approach

**Local profiling in two phases.** No changes to app code — measurement only.

- **Phase A (profvis):** Flamegraph profiling to find slow R functions and queries during a single-user session.
- **Phase B (shinyloadtest):** Replay recorded sessions at increasing concurrency (1, 5, 10, 25 users) to find the breaking point.

Optimizations are a separate follow-up task based on findings.

## Current State

- **Hosting:** Posit Connect Cloud free tier (4GB RAM, 1 CPU)
- **Target:** 75-100 concurrent users at peak after v1.0 launch
- **Existing caching:** 14 `bindCache()` calls, pre-computed rating cache tables
- **Database:** Single DuckDB connection per session (no pooling)
- **Observers:** ~203 `observeEvent` calls across server modules
- **No existing profiling infrastructure**

## Tools & Dependencies

**R packages:**
- `profvis` — CPU flamegraph profiling
- `shinyloadtest` — session recording and result analysis

**External tool:**
- `shinycannon` — Java CLI for replaying recorded sessions with N concurrent users. Requires Java 8+. Download from [rstudio/shinycannon releases](https://github.com/rstudio/shinycannon/releases).

**New files:**
- `scripts/profile_app.R` — profvis wrapper to launch app with profiling
- `scripts/record_session.R` — one-liner to start recording a user session
- `scripts/analyze_loadtest.R` — load shinycannon results, generate report
- `loadtest/` directory for recordings and results (gitignored)

## Phase A: profvis Code Profiling

**Goal:** Find which R functions and queries are slowest.

1. Run `profvis::profvis({shiny::runApp()})` to start profiled app
2. Walk through key user flows:
   - Dashboard load (charts, value boxes, hot deck calculation)
   - Switch scenes (full data refresh)
   - Open player modal (rating history query)
   - Open deck modal (meta stats)
   - Switch to Tournaments tab, click a tournament
   - Switch formats
3. Stop app — profvis opens interactive flamegraph
4. Identify top 5 slowest call stacks with file:line references

**Looking for:**
- SQL queries >500ms
- Reactive chains that re-fire unnecessarily
- Large data frame allocations
- Startup time breakdown

## Phase B: shinyloadtest Concurrency Testing

**Goal:** Find at what concurrency the app starts degrading.

1. **Record** — Run app normally, then `shinyloadtest::record_session("http://127.0.0.1:PORT")`. Walk through the typical user journey in the browser. Close when done. Saves `recording.log`.

2. **Replay** — Run `shinycannon` at increasing concurrency:
   - 1 user (baseline)
   - 5 users
   - 10 users
   - 25 users

   Command: `shinycannon recording.log http://127.0.0.1:PORT --workers N --loaded-duration-minutes 2`

3. **Analyze** — `shinyloadtest::load_runs()` generates:
   - Session duration vs baseline
   - Event waterfall (which outputs are slow under load)
   - Latency distribution (p50/p95/p99 per concurrency level)
   - The "knee" — where response times spike

**Looking for:**
- Concurrency level where p95 latency exceeds 3 seconds
- Which outputs degrade first (likely dashboard complex queries)
- Memory growth per session (determines max users per GB)
- Whether single DuckDB connection becomes a bottleneck

## Deliverables

1. **`docs/profiling-report.md`** — Findings document:
   - Top 5 bottlenecks from profvis (function, file:line, timing)
   - Concurrency knee point (e.g., "degrades at N concurrent users")
   - Memory per session estimate
   - Per-output latency table at each concurrency level
   - Posit Connect tier recommendation with math

2. **Optimization recommendations** — Prioritized by measured impact:
   - Connection pooling (`pool` package)
   - Additional `bindCache()` on slow outputs
   - Query optimization (indexes, result limits)
   - Async queries (`promises`/`future`)

3. **Tier recommendation** — Memory-per-session x target concurrency = required tier

## What This Does NOT Do

- No app code changes
- No optimization implementation (separate follow-up)
- No production load testing (local only)
- No CI/CD integration
