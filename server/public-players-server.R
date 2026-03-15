# =============================================================================
# Public: Players Tab Server Logic
# =============================================================================
# Note: Contains overview_player_clicked handler which is triggered from
# the Dashboard tab to open player details from "Top Players" table.

# ---------------------------------------------------------------------------
# Page Rendering (desktop vs mobile)
# ---------------------------------------------------------------------------
output$players_page <- renderUI({
  format_choices_with_all <- get_format_choices_with_all(db_pool)
  if (is_mobile()) {
    source("views/mobile-players-ui.R", local = TRUE)$value
  } else {
    source("views/players-ui.R", local = TRUE)$value
  }
})

# Shared reactive: fetch snapshot ratings for historical format (or NULL)
historical_snapshot_data <- reactive({
  selected_format <- input$players_format
  latest_format <- get_latest_format_id()

  is_historical <- !is.null(selected_format) && selected_format != "" &&
                   !is.null(latest_format) && selected_format != latest_format

  if (!is_historical) {
    return(NULL)
  }

  result <- safe_query(db_pool,
    "SELECT player_id, competitive_rating, achievement_score
     FROM rating_snapshots WHERE format_id = $1",
    params = list(selected_format),
    default = data.frame(player_id = integer(), competitive_rating = integer(),
                         achievement_score = integer()))

  if (nrow(result) > 0) result else NULL
})

# Debounce search input (300ms)
players_search_debounced <- reactive(input$players_search) |> debounce(300)

# Generate inline SVG sparkline from a numeric vector
make_sparkline_svg <- function(values, width = 120, height = 24, color = "#00C8FF") {
  if (length(values) < 2) return(NULL)

  # Normalize to 0-1 range
  min_val <- min(values, na.rm = TRUE)
  max_val <- max(values, na.rm = TRUE)
  if (max_val == min_val) {
    normalized <- rep(0.5, length(values))
  } else {
    normalized <- (values - min_val) / (max_val - min_val)
  }

  # Build SVG points
  n <- length(normalized)
  x_step <- (width - 4) / max(n - 1, 1)
  points <- paste(
    sapply(seq_along(normalized), function(i) {
      x <- 2 + (i - 1) * x_step
      y <- 2 + (1 - normalized[i]) * (height - 4)
      sprintf("%.1f,%.1f", x, y)
    }),
    collapse = " "
  )

  # End dot color based on recent trend
  trend_up <- normalized[n] > normalized[max(1, n - 3)]
  dot_color <- if (trend_up) "#38A169" else "#E5383B"
  last_x <- 2 + (n - 1) * x_step
  last_y <- 2 + (1 - normalized[n]) * (height - 4)

  sprintf(
    '<svg class="rating-sparkline" width="%d" height="%d" viewBox="0 0 %d %d">
      <polyline points="%s" fill="none" stroke="%s" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
      <circle cx="%.1f" cy="%.1f" r="2.5" fill="%s"/>
    </svg>',
    width, height, width, height, points, color, last_x, last_y, dot_color
  )
}

# Reset players filters
observeEvent(input$reset_players_filters, {
  updateTextInput(session, "players_search", value = "")
  updateSelectInput(session, "players_format", selected = "")
  session$sendCustomMessage("resetPillToggle", list(inputId = "players_min_events", value = "0"))
  updateSelectInput(session, "players_store_filter", selected = "")
  updateSelectInput(session, "players_win_pct_filter", selected = "0")
  updateCheckboxInput(session, "players_top3_toggle", value = FALSE)
  updateCheckboxInput(session, "players_decklist_toggle", value = FALSE)
})


# Update store filter choices when scene changes or tab is first visited
observe({
  req("players" %in% visited_tabs())
  rv$refresh_players; rv$refresh_tournaments
  scene <- rv$current_scene
  continent <- rv$current_continent
  scene_sql <- ""
  scene_params <- NULL

  if (!is.null(scene) && scene != "all" && scene != "online" && !startsWith(scene, "country:") && !startsWith(scene, "state:")) {
    scene_sql <- "AND s.scene_id IN (SELECT scene_id FROM scenes WHERE slug = $1)"
    scene_params <- list(scene)
  } else if (!is.null(scene) && startsWith(scene, "country:")) {
    scene_sql <- "AND s.scene_id IN (SELECT scene_id FROM scenes WHERE country = $1)"
    scene_params <- list(sub("^country:", "", scene))
  } else if (!is.null(scene) && startsWith(scene, "state:")) {
    scene_sql <- "AND s.scene_id IN (SELECT scene_id FROM scenes WHERE country = 'United States' AND state_region = $1)"
    scene_params <- list(sub("^state:", "", scene))
  } else if (!is.null(scene) && scene == "online") {
    scene_sql <- "AND s.is_online = TRUE"
  } else if (!is.null(continent) && continent != "all" && continent != "") {
    if (continent == "online") {
      scene_sql <- "AND s.is_online = TRUE"
    } else {
      scene_sql <- "AND s.scene_id IN (SELECT scene_id FROM scenes WHERE continent = $1)"
      scene_params <- list(continent)
    }
  }

  stores <- safe_query(db_pool, sprintf(
    "SELECT DISTINCT s.slug, s.name FROM stores s
     JOIN tournaments t ON s.store_id = t.store_id
     WHERE s.is_active = TRUE %s
     ORDER BY s.name", scene_sql),
  params = scene_params,
  default = data.frame(slug = character(), name = character()))

  store_choices <- list("All" = "")
  if (nrow(stores) > 0) {
    for (i in seq_len(nrow(stores))) {
      nm <- stores$name[i]
      if (is.na(nm) || nm == "") next
      store_choices[[nm]] <- stores$slug[i]
    }
  }
  updateSelectInput(session, "players_store_filter", choices = store_choices, selected = "")
})

# Historical rating indicator
output$historical_rating_badge <- renderUI({
  snapshot <- historical_snapshot_data()
  if (!is.null(snapshot)) {
    selected_format <- input$players_format
    div(class = "historical-rating-badge",
        bsicons::bs_icon("clock-history"),
        sprintf("Ratings from end of %s era", selected_format))
  }
})

# ---------------------------------------------------------------------------
# Shared reactive: filtered player data (consumed by desktop + mobile)
# ---------------------------------------------------------------------------
players_data <- reactive({
  req("players" %in% visited_tabs())  # Lazy load: skip until tab visited
  rv$refresh_players; rv$refresh_tournaments  # Trigger refresh on admin changes

  # Build MV filters
  filters <- build_mv_filters(
    format = input$players_format,
    scene = rv$current_scene,
    continent = rv$current_continent,
    community_store = rv$community_filter,
    search = players_search_debounced(),
    search_column = "display_name",
    start_idx = 1
  )

  # Advanced filters: store
  store_filter <- input$players_store_filter %||% ""
  if (nchar(store_filter) > 0) {
    store_idx <- filters$next_idx
    filters$sql <- paste0(filters$sql, sprintf(" AND slug = $%d", store_idx))
    filters$params <- c(filters$params, list(store_filter))
    filters$next_idx <- store_idx + 1
  }

  min_events <- as.numeric(input$players_min_events %||% 0)
  if (length(min_events) == 0 || is.na(min_events)) min_events <- 0

  having_idx <- filters$next_idx

  # Single query: player stats + main deck from MV, ratings from cache
  result <- safe_query(db_pool, sprintf("
    WITH player_agg AS (
      SELECT player_id, display_name as \"Player\",
             SUM(events)::int as \"Events\",
             SUM(wins)::int as \"W\", SUM(losses)::int as \"L\", SUM(ties)::int as \"T\",
             ROUND(SUM(wins) * 100.0 / NULLIF(SUM(wins) + SUM(losses), 0), 1) as \"Win %%\",
             SUM(firsts)::int as \"1sts\",
             SUM(top3s)::int as \"Top 3s\"
      FROM mv_player_store_stats
      WHERE NOT is_anonymized %s
      GROUP BY player_id, display_name
      HAVING SUM(events) >= $%d
    ),
    deck_ranked AS (
      SELECT player_id, archetype_name as main_deck, primary_color as main_deck_color,
             secondary_color as main_deck_secondary_color,
             ROW_NUMBER() OVER (PARTITION BY player_id ORDER BY SUM(times_played) DESC) as rn
      FROM mv_player_store_stats
      WHERE NOT is_anonymized %s
        AND archetype_name IS NOT NULL AND archetype_name != 'UNKNOWN'
      GROUP BY player_id, archetype_name, primary_color, secondary_color
    )
    SELECT pa.*,
           COALESCE(dr.main_deck, '-') as main_deck,
           COALESCE(dr.main_deck_color, '') as main_deck_color,
           COALESCE(dr.main_deck_secondary_color, '') as main_deck_secondary_color
    FROM player_agg pa
    LEFT JOIN deck_ranked dr ON pa.player_id = dr.player_id AND dr.rn = 1
  ", filters$sql, having_idx, filters$sql),
  params = c(filters$params, list(as.integer(min_events))),
  default = data.frame())

  # Advanced filters: win percentage minimum
  win_pct_min <- as.numeric(input$players_win_pct_filter %||% 0)
  if (length(win_pct_min) == 0 || is.na(win_pct_min)) win_pct_min <- 0
  if (win_pct_min > 0 && nrow(result) > 0) {
    result <- result[!is.na(result$`Win %`) & result$`Win %` >= win_pct_min, ]
  }

  # Advanced filters: top 3 only
  if (isTRUE(input$players_top3_toggle) && nrow(result) > 0) {
    result <- result[result$`Top 3s` > 0, ]
  }

  # Advanced filters: has decklist (scoped to current scene/format)
  if (isTRUE(input$players_decklist_toggle) && nrow(result) > 0) {
    dl_filters <- build_filters_param(
      table_alias = "t",
      format = input$players_format,
      scene = rv$current_scene,
      continent = rv$current_continent,
      community_store = rv$community_filter,
      store_alias = "s",
      start_idx = 1
    )
    decklist_player_ids <- safe_query(db_pool, sprintf(
      "SELECT DISTINCT r.player_id FROM results r
       JOIN tournaments t ON r.tournament_id = t.tournament_id
       JOIN stores s ON t.store_id = s.store_id
       WHERE r.decklist_url IS NOT NULL AND r.decklist_url != '' %s",
      dl_filters$sql),
      params = dl_filters$params,
      default = data.frame(player_id = integer()))
    result <- result[result$player_id %in% decklist_player_ids$player_id, ]
  }

  if (nrow(result) == 0) return(result)

  # Determine rating source: historical snapshot or live cache
  snapshot <- historical_snapshot_data()
  if (!is.null(snapshot) && nrow(snapshot) > 0) {
    result <- merge(result, snapshot, by = "player_id", all.x = TRUE)
  } else {
    comp_ratings <- player_competitive_ratings()
    if (nrow(comp_ratings) > 0) {
      result <- merge(result, comp_ratings, by = "player_id", all.x = TRUE)
    }
    ach_scores <- player_achievement_scores()
    if (nrow(ach_scores) > 0) {
      result <- merge(result, ach_scores, by = "player_id", all.x = TRUE)
    }
  }
  if (!"competitive_rating" %in% names(result)) result$competitive_rating <- NA
  if (!"achievement_score" %in% names(result)) result$achievement_score <- NA
  result$competitive_rating[is.na(result$competitive_rating)] <- 1500
  result$achievement_score[is.na(result$achievement_score)] <- 0

  # Sort by competitive rating
  result[order(-result$competitive_rating), ]
}) |> bindCache(
  input$players_format,
  players_search_debounced(),
  input$players_min_events,
  input$players_store_filter,
  input$players_win_pct_filter,
  input$players_top3_toggle,
  input$players_decklist_toggle,
  rv$current_scene,
  rv$current_continent,
  rv$community_filter,
  rv$refresh_players, rv$refresh_tournaments
)

# ---------------------------------------------------------------------------
# Desktop: Reactable output
# ---------------------------------------------------------------------------
output$player_standings <- renderReactable({
  result <- players_data()

  if (nrow(result) == 0) {
    has_filters <- nchar(trimws(players_search_debounced() %||% "")) > 0 ||
                   nchar(trimws(input$players_format %||% "")) > 0
    if (has_filters) {
      return(digital_empty_state(
        title = "No players match your filters",
        subtitle = "// try adjusting search or format",
        icon = "funnel"
      ))
    } else {
      return(digital_empty_state(
        title = "No players recorded",
        subtitle = "// player data pending",
        icon = "people",
        mascot = "agumon"
      ))
    }
  }

  # Create Record column as HTML (W-L-T with colors)
  result$Record <- sapply(1:nrow(result), function(i) {
    w <- result$W[i]
    l <- result$L[i]
    t <- result$T[i]
    sprintf(
      "<span style='color: #22c55e;'>%d</span>-<span style='color: #ef4444;'>%d</span>%s",
      as.integer(w), as.integer(l),
      if (t > 0) sprintf("-<span style='color: #f97316;'>%d</span>", as.integer(t)) else ""
    )
  })

  # Create Main Deck column as HTML (with color badge, dual-color aware)
  result$main_deck_html <- sapply(1:nrow(result), function(i) {
    deck <- result$main_deck[i]
    if (is.na(deck) || deck == "-") return("-")
    primary <- result$main_deck_color[i]
    secondary <- result$main_deck_secondary_color[i]
    sec <- if (!is.na(secondary) && secondary != "") secondary else NULL
    as.character(deck_name_badge(deck, primary, sec))
  })

  # Rating tier badge HTML
  result$rating_html <- sapply(result$competitive_rating, function(r) {
    tier_class <- if (r >= 1800) "rating-tier-elite"
                  else if (r >= 1700) "rating-tier-strong"
                  else if (r >= 1600) "rating-tier-good"
                  else if (r < 1500) "rating-tier-low"
                  else ""
    sprintf("<span class='desktop-rating-badge %s'>%s</span>",
            tier_class, as.integer(r))
  })

  reactable(
    result,
    compact = TRUE,
    striped = TRUE,
    pagination = TRUE,
    defaultPageSize = 32,
    rowStyle = JS("function(rowInfo) {
      var style = { cursor: 'pointer' };
      if (rowInfo.index === 0) {
        style.borderLeft = '3px solid #FFD700';
      } else if (rowInfo.index === 1) {
        style.borderLeft = '3px solid #C0C0C0';
      } else if (rowInfo.index === 2) {
        style.borderLeft = '3px solid #CD7F32';
      }
      return style;
    }"),
    onClick = JS("function(rowInfo, column) {
      if (rowInfo) {
        Shiny.setInputValue('player_clicked', rowInfo.row.player_id, {priority: 'event'})
      }
    }"),
    columns = list(
      player_id = colDef(show = FALSE),
      Player = colDef(minWidth = 140),
      Events = colDef(minWidth = 60, align = "center"),
      competitive_rating = colDef(
        name = "Rating",
        minWidth = 85,
        align = "center",
        cell = JS("function(cellInfo) {
          var r = cellInfo.value;
          var events = cellInfo.row.Events;
          if (events < 10) {
            return '<span class=\"desktop-rating-badge rating-tier-pending\">Pending</span>';
          }
          var tier = r >= 1800 ? 'rating-tier-elite' :
                    r >= 1700 ? 'rating-tier-strong' :
                    r >= 1600 ? 'rating-tier-good' :
                    r < 1500  ? 'rating-tier-low' : '';
          return '<span class=\"desktop-rating-badge ' + tier + '\">' + r + '</span>';
        }"),
        html = TRUE
      ),
      rating_html = colDef(show = FALSE),
      achievement_score = colDef(
        name = "Score",
        minWidth = 65,
        align = "center"
      ),
      `1sts` = colDef(minWidth = 45, align = "center"),
      `Top 3s` = colDef(minWidth = 55, align = "center"),
      W = colDef(show = FALSE),
      L = colDef(show = FALSE),
      T = colDef(show = FALSE),
      Record = colDef(
        name = "Record",
        minWidth = 80,
        align = "center",
        html = TRUE
      ),
      `Win %` = colDef(minWidth = 60, align = "center"),
      main_deck = colDef(show = FALSE),
      main_deck_color = colDef(show = FALSE),
      main_deck_secondary_color = colDef(show = FALSE),
      main_deck_html = colDef(
        name = "Main Deck",
        minWidth = 120,
        html = TRUE
      )
    )
  )
})

# ---------------------------------------------------------------------------
# Mobile Players — stacked card list replacing reactable
# ---------------------------------------------------------------------------
mobile_players_limit <- reactiveVal(20)

# Reset limit when any filter changes
observeEvent(list(input$players_format, input$players_search, input$players_min_events,
                  input$players_store_filter, input$players_win_pct_filter,
                  input$players_top3_toggle, input$players_decklist_toggle), {
  mobile_players_limit(20)
}, ignoreInit = TRUE)

# Load more button
observeEvent(input$mobile_players_load_more, {
  mobile_players_limit(mobile_players_limit() + 20)
})

output$mobile_players_cards <- renderUI({
  req(is_mobile())
  result <- players_data()

  if (nrow(result) == 0) {
    has_filters <- nchar(trimws(players_search_debounced() %||% "")) > 0 ||
                   nchar(trimws(input$players_format %||% "")) > 0
    if (has_filters) {
      return(digital_empty_state(
        title = "No players match your filters",
        subtitle = "// try adjusting search or format",
        icon = "funnel"
      ))
    } else {
      return(digital_empty_state(
        title = "No players recorded",
        subtitle = "// player data pending",
        icon = "people",
        mascot = "agumon"
      ))
    }
  }

  total_rows <- nrow(result)
  limit <- min(mobile_players_limit(), total_rows)
  display <- result[seq_len(limit), , drop = FALSE]

  # -- Build card list --------------------------------------------------------
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

    # Color-coded record (matches desktop table)
    record_tag <- tagList(
      span(style = "color: #22c55e;", as.integer(row$W)),
      "-",
      span(style = "color: #ef4444;", as.integer(row$L)),
      if (!is.na(row$T) && row$T > 0) tagList("-", span(style = "color: #f97316;", as.integer(row$T)))
    )

    # Main deck badge (dual-color aware)
    deck_tag <- if (nchar(row$main_deck) > 0 && row$main_deck != "-") {
      secondary <- row$main_deck_secondary_color
      sec <- if (!is.na(secondary) && nchar(secondary) > 0) secondary else NULL
      deck_name_badge(row$main_deck, row$main_deck_color, sec)
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

      # Row 2: Deck badge (left, under name) | Record · Events (right, under rating)
      div(class = "mobile-card-row",
        div(style = "padding-left: 2.5rem;",
          if (!is.null(deck_tag)) deck_tag
        ),
        span(class = "mobile-card-record",
          record_tag,
          span(class = "mobile-card-separator", "\u00b7"),
          span(sprintf("%d events", as.integer(row$Events)))
        )
      )
    )
  })

  # Assemble: card list + optional load-more button
  card_list <- div(class = "mobile-card-list", cards)

  if (limit < total_rows) {
    remaining <- total_rows - limit
    load_btn <- tags$button(
      class = "mobile-load-more",
      onclick = "Shiny.setInputValue('mobile_players_load_more', Math.random(), {priority: 'event'})",
      span(class = "mobile-load-more-label", "LOAD MORE"),
      span(class = "mobile-load-more-count", sprintf("%d remaining", remaining))
    )
    tagList(card_list, load_btn)
  } else {
    card_list
  }
})

# Handle player row click - open detail modal
observeEvent(input$player_clicked, {
  rv$selected_player_id <- input$player_clicked
})

# Handle Overview player click - open modal on overview
observeEvent(input$overview_player_clicked, {
  rv$selected_player_id <- input$overview_player_clicked
})

# Render player detail modal
output$player_detail_modal <- renderUI({
  req(rv$selected_player_id)

  # React to advanced filter changes so modal updates
  input$players_top3_toggle
  input$players_decklist_toggle

  player_id <- rv$selected_player_id

  # Get player info (parameterized query)
  player <- safe_query(db_pool, "
    SELECT p.player_id, p.display_name, p.home_store_id, p.is_anonymized, s.name as home_store
    FROM players p
    LEFT JOIN stores s ON p.home_store_id = s.store_id
    WHERE p.player_id = $1
  ", params = list(player_id), default = data.frame())

  if (nrow(player) == 0) return(NULL)
  if (isTRUE(player$is_anonymized)) return(NULL)

  # Get overall stats including ties and avg placement (parameterized query)
  stats <- safe_query(db_pool, "
    SELECT COUNT(DISTINCT r.tournament_id) as events,
           SUM(r.wins) as wins, SUM(r.losses) as losses, SUM(r.ties) as ties,
           ROUND(SUM(r.wins) * 100.0 / NULLIF(SUM(r.wins) + SUM(r.losses), 0), 1) as win_pct,
           COUNT(CASE WHEN r.placement = 1 THEN 1 END) as first_places,
           COUNT(CASE WHEN r.placement <= 3 THEN 1 END) as top3,
           ROUND(AVG(r.placement), 1) as avg_placement
    FROM results r
    WHERE r.player_id = $1
  ", params = list(player_id), default = data.frame(events = 0, wins = 0, losses = 0, ties = 0, win_pct = NA, first_places = 0, top3 = 0, avg_placement = NA))

  # Get rating and achievement score
  p_ratings <- player_competitive_ratings()
  p_achievements <- player_achievement_scores()
  player_rating <- p_ratings$competitive_rating[p_ratings$player_id == player_id]
  player_score <- p_achievements$achievement_score[p_achievements$player_id == player_id]
  if (length(player_rating) == 0) player_rating <- 1500
  if (length(player_score) == 0) player_score <- 0

  # Get favorite decks (most played, parameterized query)
  # Exclude UNKNOWN archetype from player profiles
  favorite_decks <- safe_query(db_pool, "
    SELECT da.archetype_name as \"Deck\", da.primary_color as color,
           da.secondary_color,
           COUNT(*) as \"Times\",
           COUNT(CASE WHEN r.placement = 1 THEN 1 END) as \"Wins\"
    FROM results r
    JOIN deck_archetypes da ON r.archetype_id = da.archetype_id
    WHERE r.player_id = $1 AND da.archetype_name != 'UNKNOWN'
    GROUP BY da.archetype_id, da.archetype_name, da.primary_color, da.secondary_color
    ORDER BY COUNT(*) DESC
    LIMIT 5
  ", params = list(player_id), default = data.frame())

  # Get recent tournament results (parameterized query)
  recent_results <- safe_query(db_pool, "
    SELECT t.event_date as \"Date\", s.name as \"Store\", da.archetype_name as \"Deck\",
           r.placement as \"Place\", r.wins as \"W\", r.losses as \"L\", r.decklist_url
    FROM results r
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    JOIN stores s ON t.store_id = s.store_id
    JOIN deck_archetypes da ON r.archetype_id = da.archetype_id
    WHERE r.player_id = $1
    ORDER BY t.event_date DESC
    LIMIT 200
  ", params = list(player_id), default = data.frame())

  # Apply advanced filters to modal results
  if (isTRUE(input$players_top3_toggle) && nrow(recent_results) > 0) {
    recent_results <- recent_results[recent_results$Place <= 3, ]
  }
  if (isTRUE(input$players_decklist_toggle) && nrow(recent_results) > 0) {
    recent_results <- recent_results[!is.na(recent_results$decklist_url) & recent_results$decklist_url != "", ]
  }

  # Get placement history for sparkline
  sparkline_data <- safe_query(db_pool, "
    SELECT r.placement, t.player_count
    FROM results r
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    WHERE r.player_id = $1
      AND r.placement IS NOT NULL
      AND t.player_count IS NOT NULL
      AND t.player_count >= 4
    ORDER BY t.event_date ASC
  ", params = list(player_id), default = data.frame())

  # Compute placement percentile sparkline (1.0 = 1st place, 0.0 = last)
  sparkline_html <- NULL
  if (!is.null(sparkline_data) && nrow(sparkline_data) >= 3) {
    percentiles <- 1 - (sparkline_data$placement - 1) / pmax(sparkline_data$player_count - 1, 1)
    percentiles <- pmin(pmax(percentiles, 0), 1)
    if (length(percentiles) > 15) percentiles <- tail(percentiles, 15)
    sparkline_html <- make_sparkline_svg(percentiles)
  }

  # Update URL for deep linking
  update_url_for_player(session, player_id, player$display_name)

  # Build modal
  showModal(modalDialog(
    title = div(
      class = "d-flex align-items-center gap-2",
      bsicons::bs_icon("person-circle"),
      player$display_name
    ),
    size = "l",
    easyClose = TRUE,
    footer = tagList(
      tags$button(
        type = "button",
        class = "btn btn-outline-secondary me-auto",
        onclick = "copyCurrentUrl()",
        bsicons::bs_icon("link-45deg"), " Copy Link"
      ),
      actionButton("report_error_player", tagList(bsicons::bs_icon("flag"), " Report Error"),
                   class = "btn btn-outline-warning"),
      modalButton("Close")
    ),

    # Player info with clickable home store
    if (!is.na(player$home_store) && !is.na(player$home_store_id)) {
      p(class = "text-muted",
        bsicons::bs_icon("shop"), " Home store: ",
        actionLink(
          inputId = paste0("player_modal_store_", player$home_store_id),
          label = player$home_store,
          class = "text-primary",
          onclick = sprintf("Shiny.setInputValue('modal_store_clicked', %d, {priority: 'event'}); return false;", player$home_store_id)
        )
      )
    } else if (!is.na(player$home_store)) {
      p(class = "text-muted", bsicons::bs_icon("shop"), " Home store: ", player$home_store)
    },

    # Stats summary with Rating, Score, W-L-T colors
    div(
      class = "modal-stats-box d-flex justify-content-evenly mb-3 p-3 flex-wrap",
      div(
        class = "modal-stat-item",
        div(class = "modal-stat-value", stats$events),
        div(class = "modal-stat-label", "Events")
      ),
      div(
        class = "modal-stat-item",
        div(class = "modal-stat-value",
          span(class = "text-success", stats$wins %||% 0), "-",
          span(class = "text-danger", stats$losses %||% 0), "-",
          span(class = "text-warning", stats$ties %||% 0)
        ),
        div(class = "modal-stat-label", "Record")
      ),
      div(
        class = "modal-stat-item",
        div(class = "modal-stat-value", round(player_rating)),
        div(class = "modal-stat-label", "Rating"),
        if (!is.null(sparkline_html)) HTML(sparkline_html)
      ),
      div(
        class = "modal-stat-item",
        div(class = "modal-stat-value", player_score),
        div(class = "modal-stat-label", "Score")
      ),
      div(
        class = "modal-stat-item",
        div(class = "modal-stat-value stat-highlight place-1st", stats$first_places),
        div(class = "modal-stat-label", "1sts")
      ),
      div(
        class = "modal-stat-item",
        div(class = "modal-stat-value", if (!is.na(stats$avg_placement)) stats$avg_placement else "-"),
        div(class = "modal-stat-label", "Avg Place")
      )
    ),

    # Favorite decks
    if (nrow(favorite_decks) > 0) {
      tagList(
        h6(class = "modal-section-header", "Favorite Decks"),
        div(
          class = "d-flex flex-wrap gap-2 mb-3",
          lapply(1:nrow(favorite_decks), function(i) {
            deck <- favorite_decks[i, ]
            sec <- if (!is.na(deck$secondary_color) && deck$secondary_color != "") deck$secondary_color else NULL
            div(
              class = "d-flex align-items-center gap-1",
              deck_name_badge(deck$Deck, deck$color, sec),
              span(class = "small text-muted", sprintf("(%dx, %d wins)", as.integer(deck$Times), as.integer(deck$Wins)))
            )
          })
        )
      )
    },

    # Tournament history (paginated)
    if (nrow(recent_results) > 0) {
      display_results <- data.frame(
        Date = format(as.Date(recent_results$Date), "%b %d, %Y"),
        Store = recent_results$Store,
        Deck = recent_results$Deck,
        Place = vapply(recent_results$Place, function(p) {
          cls <- if (p == 1) "place-1st" else if (p == 2) "place-2nd" else if (p == 3) "place-3rd" else ""
          as.character(tags$span(class = cls, ordinal(p)))
        }, character(1)),
        Record = sprintf("%d-%d", recent_results$W, recent_results$L),
        Decklist = unname(vapply(recent_results$decklist_url, function(u) {
          tag <- decklist_link_icon(u)
          if (!is.null(tag)) as.character(tag) else ""
        }, character(1))),
        stringsAsFactors = FALSE,
        row.names = NULL
      )

      tagList(
        h6(class = "modal-section-header mt-3", "Tournament History"),
        reactable(
          display_results,
          compact = TRUE,
          striped = TRUE,
          pagination = TRUE,
          defaultPageSize = 10,
          columns = list(
            Date = colDef(minWidth = 90),
            Store = colDef(minWidth = 120),
            Deck = colDef(minWidth = 100),
            Place = colDef(minWidth = 55, align = "center", html = TRUE),
            Record = colDef(minWidth = 60, align = "center"),
            Decklist = colDef(
              name = "",
              minWidth = 40,
              html = TRUE
            )
          )
        )
      )
    } else {
      digital_empty_state("No tournament history", "// results data pending", "calendar-x", mascot = "agumon")
    }
  ))
})
outputOptions(output, "player_detail_modal", suspendWhenHidden = FALSE)
