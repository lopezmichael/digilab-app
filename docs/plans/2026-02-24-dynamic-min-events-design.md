# Dynamic Min Events Default Design

**Date:** 2026-02-24
**Status:** Approved
**Target Version:** v1.1 or later

## Overview

The Players and Deck Meta tabs currently default to showing "5+ events" minimum filter. This works well for established scenes with lots of data, but makes newer scenes appear empty or sparsely populated.

This design proposes dynamically adjusting the default minimum events filter based on how much tournament data exists for the current view (scene or community).

## Problem Statement

1. **New scenes look empty**: A newly added scene (e.g., a new metro or store partner) with 10 tournaments would show very few players when filtering to "5+ events"
2. **Community views are affected**: Store-specific community links (`?community=store-slug`) for new partners show sparse data
3. **One-size-fits-all doesn't scale**: As DigiLab expands to more regions, some will be mature while others are just starting

## Current Implementation

### UI Component

Both tabs use a `pill-toggle` button group (not a dropdown):

**Players tab** (`views/players-ui.R:32-38`):
```html
<span class="title-strip-pill-label">Min Events:</span>
<div class="pill-toggle" data-input-id="players_min_events">
  <button class="pill-option" data-value="0">All</button>
  <button class="pill-option active" data-value="5">5+</button>
  <button class="pill-option" data-value="10">10+</button>
</div>
```

**Meta tab** (`views/meta-ui.R:31-37`):
```html
<span class="title-strip-pill-label">Min Entries:</span>
<div class="pill-toggle" data-input-id="meta_min_entries">
  <button class="pill-option" data-value="0">All</button>
  <button class="pill-option active" data-value="5">5+</button>
  <button class="pill-option" data-value="10">10+</button>
</div>
```

### Current Default Logic

| Context | Default | Location |
|---------|---------|----------|
| Initial page load | 5+ | Hardcoded `active` class in HTML |
| Community view (`?community=`) | All | `url-routing-server.R:114-115` |
| Clear community filter | 5+ | `shared-server.R:933-934` |
| Reset filters button | 5+ | `public-players-server.R:77`, `public-meta-server.R:9` |

### JavaScript Integration

The pill-toggle is controlled via custom messages:
- `session$sendCustomMessage("setPillToggle", list(inputId = "...", value = "5"))`
- `session$sendCustomMessage("resetPillToggle", list(inputId = "...", value = "5"))`

---

## Proposed Solution

### Dynamic Thresholds

| Tournament Count | Default Min Events | Rationale |
|------------------|-------------------|-----------|
| < 20 | All | Still building community; show everyone |
| 20 - 100 | 5+ | Established; regulars emerging |
| > 100 | 10+ | Mature scene; highlight committed players |

These thresholds ensure at least 10-20 players typically appear when the filtered default is applied.

### Scope of Tournament Count

The tournament count should match the current data scope:

| View | Count Query |
|------|-------------|
| Scene selected (e.g., "Dallas Fort Worth") | Tournaments where `store.scene_id = current_scene_id` |
| "All" scenes | Total tournaments in database |
| Community view (`?community=store-slug`) | Tournaments for that specific store |
| Online scene | Tournaments where `store.is_online = TRUE` |

### Behavior

1. **Session-based default**: The dynamic default is a session preference, not URL-persisted
2. **User can override**: Manual selection always takes precedence during the session
3. **Scene change updates default**: When scene changes, recalculate and apply new default
4. **Community view follows same rules**: Count that store's tournaments, apply threshold

---

## Implementation

### Helper Function

Add to `server/shared-server.R`:

```r
#' Calculate default min_events based on tournament count
#'
#' @param tournament_count Integer count of tournaments
#' @return Character value for pill-toggle: "0", "5", or "10"
get_default_min_events <- function(tournament_count) {
  if (is.null(tournament_count) || is.na(tournament_count)) {
    return("5")  # Fallback to current default
  }
  if (tournament_count < 20) {
    return("0")  # "All"
  } else if (tournament_count <= 100) {
    return("5")  # "5+"
  } else {
    return("10") # "10+"
  }
}
```

### Tournament Count Query

Add reactive or function to count tournaments for current scope:

```r
#' Count tournaments for the current view scope
#'
#' @param scene_slug Current scene slug or "all"
#' @param community_slug Optional community filter slug
#' @return Integer count of tournaments
count_tournaments_for_scope <- function(scene_slug, community_slug = NULL) {
  if (!is.null(community_slug)) {
    # Community view: count for specific store
    result <- safe_query(db_pool,
      "SELECT COUNT(*) as n FROM tournaments t
       JOIN stores s ON t.store_id = s.store_id
       WHERE s.slug = $1",
      params = list(community_slug),
      default = data.frame(n = 0))
  } else if (scene_slug == "all") {
    # All scenes
    result <- safe_query(db_pool,
      "SELECT COUNT(*) as n FROM tournaments",
      default = data.frame(n = 0))
  } else {
    # Specific scene
    result <- safe_query(db_pool,
      "SELECT COUNT(*) as n FROM tournaments t
       JOIN stores s ON t.store_id = s.store_id
       JOIN scenes sc ON s.scene_id = sc.scene_id
       WHERE sc.slug = $1",
      params = list(scene_slug),
      default = data.frame(n = 0))
  }
  return(result$n[1])
}
```

### Integration Points

**1. Scene change** (`server/scene-server.R`, around line 130):

After `rv$data_refresh <- Sys.time()`, add:
```r
# Update min_events default based on scene's tournament count
tournament_count <- count_tournaments_for_scope(new_scene, NULL)
default_min <- get_default_min_events(tournament_count)
session$sendCustomMessage("setPillToggle", list(inputId = "players_min_events", value = default_min))
session$sendCustomMessage("setPillToggle", list(inputId = "meta_min_entries", value = default_min))
```

**2. Community view load** (`server/url-routing-server.R`, around line 113-116):

Replace hardcoded "0" with dynamic calculation:
```r
# Calculate appropriate default for this community's data volume
tournament_count <- count_tournaments_for_scope(NULL, params$community)
default_min <- get_default_min_events(tournament_count)
shinyjs::delay(150, {
  session$sendCustomMessage("setPillToggle", list(inputId = "players_min_events", value = default_min))
  session$sendCustomMessage("setPillToggle", list(inputId = "meta_min_entries", value = default_min))
})
```

**3. Clear community filter** (`server/shared-server.R`, around line 932-934):

Update to use dynamic default based on current scene:
```r
# Reset to dynamic default for current scene
tournament_count <- count_tournaments_for_scope(rv$current_scene, NULL)
default_min <- get_default_min_events(tournament_count)
session$sendCustomMessage("setPillToggle", list(inputId = "players_min_events", value = default_min))
session$sendCustomMessage("setPillToggle", list(inputId = "meta_min_entries", value = default_min))
```

**4. Reset filters buttons** (`public-players-server.R:77`, `public-meta-server.R:9`):

Update to use dynamic default:
```r
# In reset_players_filters observer
tournament_count <- count_tournaments_for_scope(
  rv$current_scene,
  rv$community_filter
)
default_min <- get_default_min_events(tournament_count)
session$sendCustomMessage("resetPillToggle", list(inputId = "players_min_events", value = default_min))
```

**5. Initial page load**:

The HTML has `active` class on "5+" by default. On app load (after scene is determined), we should set the appropriate default. This could be handled in `scene-server.R` when scene is first established from URL or localStorage.

---

## User Communication

### Tooltip on Pill Toggle

Add a help icon next to "Min Events:" label with tooltip:

```r
span(class = "title-strip-pill-label",
  "Min Events:",
  tags$span(
    class = "help-icon",
    title = "Default filter adjusts based on tournament data available. Newer scenes show all players; established scenes filter to frequent competitors.",
    bsicons::bs_icon("question-circle")
  )
)
```

### FAQ Entry

Add to FAQ section:

```markdown
**Why does the minimum events filter default differently for different scenes?**

We adjust the default filter based on how established each scene is:

- **Newer scenes** (fewer than 20 tournaments) default to "All" so you can see everyone who's competed
- **Growing scenes** (20-100 tournaments) default to "5+" to highlight returning players
- **Established scenes** (100+ tournaments) default to "10+" to showcase committed competitors

You can always change the filter manually to see more or fewer players.
```

---

## Files to Modify

| File | Changes |
|------|---------|
| `server/shared-server.R` | Add `get_default_min_events()` and `count_tournaments_for_scope()` functions; update community filter clear logic |
| `server/scene-server.R` | Set dynamic default on scene change and initial load |
| `server/url-routing-server.R` | Use dynamic default for community view |
| `server/public-players-server.R` | Update reset filters to use dynamic default |
| `server/public-meta-server.R` | Update reset filters to use dynamic default |
| `views/players-ui.R` | Add tooltip to "Min Events:" label |
| `views/meta-ui.R` | Add tooltip to "Min Entries:" label |
| `views/faq-content.R` | Add FAQ entry explaining dynamic defaults |

---

## Edge Cases

1. **Scene with 0 tournaments**: Returns "All" (threshold < 20)
2. **Database error on count**: Fallback to "5" (current default)
3. **Rapid scene switching**: Each scene change triggers a new count; last one wins
4. **User manually changes filter, then scene changes**: Scene change updates to new default (manual selection is not "sticky" across scene changes)

---

## Performance Considerations

- Tournament count query is simple `COUNT(*)` with index-friendly JOINs
- Query runs on scene change (infrequent user action)
- Could cache counts per scene in `rv$scene_tournament_counts` if needed, refreshed with `rv$data_refresh`

---

## Testing Checklist

- [ ] New scene with < 20 tournaments defaults to "All"
- [ ] Scene with 20-100 tournaments defaults to "5+"
- [ ] Scene with > 100 tournaments defaults to "10+"
- [ ] Community view respects store's tournament count
- [ ] Scene change updates filter default correctly
- [ ] Clear community filter resets to scene's dynamic default
- [ ] Reset filters button uses dynamic default
- [ ] Tooltip appears and explains behavior
- [ ] FAQ entry is accessible via link

---

## Resolved Questions

1. **Should user's manual selection persist across scene changes?**
   - **Decision**: No (Option A). Scene change resets to the new scene's dynamic default.
   - Simpler implementation, ensures filter always matches scene's data volume.

2. **Should we show the threshold logic to users?**
   - **Decision**: Tooltip only (Option C). Keep UI clean, provide explanation on hover.
   - No visible "recommended" badge or subtitle - the tooltip on the help icon explains the behavior for curious users.

---

## Future Considerations

- **Per-format thresholds**: As formats change, older formats have more data. Could calculate separately per format if needed.
- **Admin visibility**: Show tournament counts in admin dashboard so admins understand why defaults differ.
- **Analytics**: Track which default users see and whether they change it, to validate thresholds.
