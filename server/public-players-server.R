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
  # Reset pill toggle to dynamic default based on current scope
  tournament_count <- count_tournaments_for_scope(db_pool, rv$current_scene, rv$community_filter)
  default_min <- get_default_min_events(tournament_count)
  session$sendCustomMessage("resetPillToggle", list(inputId = "players_min_events", value = default_min))
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

output$player_standings <- renderReactable({
  rv$data_refresh  # Trigger refresh on admin changes


  # Build parameterized filters to prevent SQL injection
  search_filters <- build_filters_param(
    table_alias = "p",
    search = players_search_debounced(),
    search_column = "display_name",
    start_idx = 1
  )

  format_filters <- build_filters_param(
    table_alias = "t",
    format = input$players_format,
    scene = rv$current_scene,
    store_alias = "s",
    community_store = rv$community_filter,
    start_idx = search_filters$next_idx
  )

  # Combine filter SQL and params
  filter_sql <- paste(search_filters$sql, format_filters$sql)
  filter_params <- c(search_filters$params, format_filters$params)

  min_events <- as.numeric(input$players_min_events)
  if (is.na(min_events)) min_events <- 0

  # HAVING clause parameter is numbered after all filter params
  having_idx <- format_filters$next_idx

  # Build query with parameterized HAVING clause
  query <- sprintf("
    SELECT p.player_id, p.display_name as \"Player\",
           COUNT(DISTINCT r.tournament_id) as \"Events\",
           SUM(r.wins) as \"W\", SUM(r.losses) as \"L\", SUM(r.ties) as \"T\",
           ROUND(SUM(r.wins) * 100.0 / NULLIF(SUM(r.wins) + SUM(r.losses), 0), 1) as \"Win %%\",
           COUNT(CASE WHEN r.placement = 1 THEN 1 END) as \"1sts\",
           COUNT(CASE WHEN r.placement <= 3 THEN 1 END) as \"Top 3s\"
    FROM players p
    JOIN results r ON p.player_id = r.player_id
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    JOIN stores s ON t.store_id = s.store_id
    WHERE 1=1 %s
    GROUP BY p.player_id, p.display_name
    HAVING COUNT(DISTINCT r.tournament_id) >= $%d
  ", filter_sql, having_idx)

  result <- safe_query(db_pool, query, params = c(filter_params, list(min_events)), default = data.frame())

  # Get most played deck for each player (Main Deck)
  main_decks_query <- sprintf("
    WITH player_deck_counts AS (
      SELECT r.player_id, da.archetype_name, da.primary_color,
             COUNT(*) as times_played,
             ROW_NUMBER() OVER (PARTITION BY r.player_id ORDER BY COUNT(*) DESC) as rn
      FROM results r
      JOIN players p ON r.player_id = p.player_id
      JOIN deck_archetypes da ON r.archetype_id = da.archetype_id
      JOIN tournaments t ON r.tournament_id = t.tournament_id
      JOIN stores s ON t.store_id = s.store_id
      WHERE da.archetype_name != 'UNKNOWN' %s
      GROUP BY r.player_id, da.archetype_name, da.primary_color
    )
    SELECT player_id, archetype_name as main_deck, primary_color as main_deck_color
    FROM player_deck_counts
    WHERE rn = 1
  ", filter_sql)

  main_decks <- safe_query(db_pool, main_decks_query, params = filter_params, default = data.frame())

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

  # Determine rating source: historical snapshot or live cache
  snapshot <- historical_snapshot_data()

  if (!is.null(snapshot)) {
    # Historical format with available snapshots
    result <- merge(result, snapshot, by = "player_id", all.x = TRUE)
  } else {
    # Current format or no snapshots: use live cache
    comp_ratings <- player_competitive_ratings()
    result <- merge(result, comp_ratings, by = "player_id", all.x = TRUE)
    ach_scores <- player_achievement_scores()
    result <- merge(result, ach_scores, by = "player_id", all.x = TRUE)
  }
  result$competitive_rating[is.na(result$competitive_rating)] <- 1500
  result$achievement_score[is.na(result$achievement_score)] <- 0

  # Join with main decks
  result <- merge(result, main_decks, by = "player_id", all.x = TRUE)
  result$main_deck[is.na(result$main_deck)] <- "-"
  result$main_deck_color[is.na(result$main_deck_color)] <- ""

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

  # Create Main Deck column as HTML (with color badge)
  result$main_deck_html <- sapply(1:nrow(result), function(i) {
    deck <- result$main_deck[i]
    if (is.na(deck) || deck == "-") return("-")
    color <- result$main_deck_color[i]
    color_class <- if (!is.na(color) && color != "") {
      paste0("deck-badge deck-badge-", tolower(color))
    } else {
      "deck-badge"
    }
    sprintf("<span class='%s'>%s</span>", htmltools::htmlEscape(color_class), htmltools::htmlEscape(deck))
  })

  # Sort by competitive rating
  result <- result[order(-result$competitive_rating), ]

  reactable(
    result,
    compact = TRUE,
    striped = TRUE,
    pagination = TRUE,
    defaultPageSize = 32,
    rowStyle = list(cursor = "pointer"),
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
        minWidth = 75,
        align = "center"
      ),
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
      main_deck_html = colDef(
        name = "Main Deck",
        minWidth = 120,
        html = TRUE
      )
    )
  )
}) |> bindCache(
  input$players_format,
  players_search_debounced(),
  input$players_min_events,
  rv$current_scene,
  rv$community_filter,
  rv$data_refresh
)

# ---------------------------------------------------------------------------
# Mobile Players — stacked card list replacing reactable
# ---------------------------------------------------------------------------
mobile_players_limit <- reactiveVal(20)

# Reset limit when filters change
observeEvent(list(input$players_format, input$players_search, input$players_min_events), {
  mobile_players_limit(20)
}, ignoreInit = TRUE)

# Load more button
observeEvent(input$mobile_players_load_more, {
  mobile_players_limit(mobile_players_limit() + 20)
})

output$mobile_players_cards <- renderUI({
  req(is_mobile())
  rv$data_refresh

  # -- Reuse exact same query logic as desktop renderReactable ----------------
  search_filters <- build_filters_param(
    table_alias = "p",
    search = players_search_debounced(),
    search_column = "display_name",
    start_idx = 1
  )

  format_filters <- build_filters_param(
    table_alias = "t",
    format = input$players_format,
    scene = rv$current_scene,
    store_alias = "s",
    community_store = rv$community_filter,
    start_idx = search_filters$next_idx
  )

  filter_sql <- paste(search_filters$sql, format_filters$sql)
  filter_params <- c(search_filters$params, format_filters$params)

  min_events <- as.numeric(input$players_min_events)
  if (is.na(min_events)) min_events <- 0
  having_idx <- format_filters$next_idx

  query <- sprintf("
    SELECT p.player_id, p.display_name as \"Player\",
           COUNT(DISTINCT r.tournament_id) as \"Events\",
           SUM(r.wins) as \"W\", SUM(r.losses) as \"L\", SUM(r.ties) as \"T\",
           ROUND(SUM(r.wins) * 100.0 / NULLIF(SUM(r.wins) + SUM(r.losses), 0), 1) as \"Win_Pct\",
           COUNT(CASE WHEN r.placement = 1 THEN 1 END) as \"Firsts\",
           COUNT(CASE WHEN r.placement <= 3 THEN 1 END) as \"Top3s\"
    FROM players p
    JOIN results r ON p.player_id = r.player_id
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    JOIN stores s ON t.store_id = s.store_id
    WHERE 1=1 %s
    GROUP BY p.player_id, p.display_name
    HAVING COUNT(DISTINCT r.tournament_id) >= $%d
  ", filter_sql, having_idx)

  result <- safe_query(db_pool, query,
    params = c(filter_params, list(min_events)),
    default = data.frame())

  # Main decks
  main_decks_query <- sprintf("
    WITH player_deck_counts AS (
      SELECT r.player_id, da.archetype_name, da.primary_color,
             COUNT(*) as times_played,
             ROW_NUMBER() OVER (PARTITION BY r.player_id ORDER BY COUNT(*) DESC) as rn
      FROM results r
      JOIN players p ON r.player_id = p.player_id
      JOIN deck_archetypes da ON r.archetype_id = da.archetype_id
      JOIN tournaments t ON r.tournament_id = t.tournament_id
      JOIN stores s ON t.store_id = s.store_id
      WHERE da.archetype_name != 'UNKNOWN' %s
      GROUP BY r.player_id, da.archetype_name, da.primary_color
    )
    SELECT player_id, archetype_name as main_deck, primary_color as main_deck_color
    FROM player_deck_counts
    WHERE rn = 1
  ", filter_sql)

  main_decks <- safe_query(db_pool, main_decks_query,
    params = filter_params, default = data.frame())

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

  # Ratings: historical snapshot or live
  snapshot <- historical_snapshot_data()
  if (!is.null(snapshot)) {
    result <- merge(result, snapshot, by = "player_id", all.x = TRUE)
  } else {
    comp_ratings <- player_competitive_ratings()
    result <- merge(result, comp_ratings, by = "player_id", all.x = TRUE)
    ach_scores <- player_achievement_scores()
    result <- merge(result, ach_scores, by = "player_id", all.x = TRUE)
  }
  result$competitive_rating[is.na(result$competitive_rating)] <- 1500
  result$achievement_score[is.na(result$achievement_score)] <- 0

  # Join main decks
  result <- merge(result, main_decks, by = "player_id", all.x = TRUE)
  result$main_deck[is.na(result$main_deck)] <- ""
  result$main_deck_color[is.na(result$main_deck_color)] <- ""

  # Sort by competitive rating descending

  result <- result[order(-result$competitive_rating), ]

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

      # Row 2: Deck badge (left-aligned under name)
      if (!is.null(deck_tag)) {
        div(class = "mobile-card-row",
          div(class = "mobile-card-secondary", style = "padding-left: 2.5rem;",
            deck_tag
          )
        )
      },

      # Row 3: Record | Events (left-aligned under name)
      div(class = "mobile-card-row",
        div(class = "mobile-card-secondary", style = "padding-left: 2.5rem;",
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
      sprintf("Load more (%d remaining)", remaining)
    )
    tagList(card_list, load_btn)
  } else {
    card_list
  }
}) |> bindCache(
  is_mobile(),
  input$players_format,
  players_search_debounced(),
  input$players_min_events,
  rv$current_scene,
  rv$community_filter,
  rv$data_refresh,
  mobile_players_limit()
)

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

  player_id <- rv$selected_player_id


  # Get player info (parameterized query)
  player <- safe_query(db_pool, "
    SELECT p.player_id, p.display_name, p.home_store_id, s.name as home_store
    FROM players p
    LEFT JOIN stores s ON p.home_store_id = s.store_id
    WHERE p.player_id = $1
  ", params = list(player_id), default = data.frame())

  if (nrow(player) == 0) return(NULL)

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
           COUNT(*) as \"Times\",
           COUNT(CASE WHEN r.placement = 1 THEN 1 END) as \"Wins\"
    FROM results r
    JOIN deck_archetypes da ON r.archetype_id = da.archetype_id
    WHERE r.player_id = $1 AND da.archetype_name != 'UNKNOWN'
    GROUP BY da.archetype_id, da.archetype_name, da.primary_color
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
    LIMIT 10
  ", params = list(player_id), default = data.frame())

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
            color_class <- paste0("deck-badge-", tolower(deck$color))
            div(
              class = "d-flex align-items-center gap-1",
              span(class = paste("deck-badge", color_class), deck$Deck),
              span(class = "small text-muted", sprintf("(%dx, %d wins)", as.integer(deck$Times), as.integer(deck$Wins)))
            )
          })
        )
      )
    },

    # Recent results
    if (nrow(recent_results) > 0) {
      tagList(
        h6(class = "modal-section-header", "Recent Results"),
        tags$table(
          class = "table table-sm table-striped",
          tags$thead(
            tags$tr(
              tags$th("Date"), tags$th("Store"), tags$th("Deck"),
              tags$th("Place"), tags$th("Record"), tags$th("")
            )
          ),
          tags$tbody(
            lapply(1:nrow(recent_results), function(i) {
              row <- recent_results[i, ]
              tags$tr(
                tags$td(format(as.Date(row$Date), "%b %d")),
                tags$td(row$Store),
                tags$td(row$Deck),
                tags$td(
                  class = if (row$Place == 1) "place-1st" else if (row$Place == 2) "place-2nd" else if (row$Place == 3) "place-3rd" else "",
                  ordinal(row$Place)
                ),
                tags$td(sprintf("%d-%d", row$W, row$L)),
                tags$td(
                  if (!is.na(row$decklist_url) && nchar(row$decklist_url) > 0) {
                    tags$a(
                      href = row$decklist_url,
                      target = "_blank",
                      title = "View decklist",
                      class = "text-primary",
                      bsicons::bs_icon("list-ul")
                    )
                  }
                )
              )
            })
          )
        )
      )
    } else {
      digital_empty_state("No results recorded", "// deck data pending", "clipboard-x", mascot = "agumon")
    }
  ))
})
outputOptions(output, "player_detail_modal", suspendWhenHidden = FALSE)
