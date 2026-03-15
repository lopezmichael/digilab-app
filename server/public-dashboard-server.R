# =============================================================================
# Public: Dashboard Tab Server Logic
# =============================================================================
# Note: This file contains all Dashboard/Overview tab functionality including:
# - Context text and value boxes
# - Most popular deck and hot deck calculations
# - Recent tournaments and top players tables
# - All dashboard charts (meta share, conversion, color distribution, trends)

# ---------------------------------------------------------------------------
# Page Rendering (desktop vs mobile)
# ---------------------------------------------------------------------------
output$dashboard_page <- renderUI({
  format_choices_with_all <- get_format_choices_with_all(db_pool)
  if (is_mobile()) {
    source("views/mobile-dashboard-ui.R", local = TRUE)$value
  } else {
    source("views/dashboard-ui.R", local = TRUE)$value
  }
})

# ---------------------------------------------------------------------------
# Shared chart theme mode reactive
# ---------------------------------------------------------------------------
chart_mode <- reactive({
  if (!is.null(input$dark_mode) && input$dark_mode == "dark") "dark" else "light"
})

# ---------------------------------------------------------------------------
# Dashboard Data
# ---------------------------------------------------------------------------

# Dashboard context text (shows current filter state)
output$dashboard_context_text <- renderUI({
  format_name <- if (!is.null(input$dashboard_format) && input$dashboard_format != "") {
    # Get format display name from database (parameterized query)
    result <- safe_query(db_pool,
        "SELECT display_name FROM formats WHERE format_id = $1",
        params = list(input$dashboard_format),
        default = data.frame(display_name = character(0))
      )
      if (nrow(result) > 0) result$display_name[1] else input$dashboard_format
  } else {
    "All Formats"
  }

  event_name <- if (!is.null(input$dashboard_event_type) && input$dashboard_event_type != "") {
    # Format event type nicely
    formatted <- gsub("_", " ", input$dashboard_event_type)
    formatted <- gsub("\\b([a-z])", "\\U\\1", formatted, perl = TRUE)
    formatted
  } else {
    "All Events"
  }

  HTML(paste0(format_name, " <span style='opacity: 0.6;'>·</span> ", event_name))
}) |> bindCache(input$dashboard_format, input$dashboard_event_type)

# Value box outputs (read from core_metrics batch reactive)
output$total_tournaments_val <- renderText({
  core_metrics()$tournaments
})

output$total_players_val <- renderText({
  core_metrics()$players
})

output$total_stores_val <- renderText({
  rv$refresh_tournaments; rv$refresh_decks; rv$refresh_players
  filters <- build_mv_filters(
    format = input$dashboard_format,
    event_type = input$dashboard_event_type,
    scene = rv$current_scene,
    continent = rv$current_continent,
    community_store = rv$community_filter,
    start_idx = 1
  )
  result <- safe_query(db_pool, paste("
    SELECT COUNT(DISTINCT store_id)::int as n
    FROM mv_tournament_list
    WHERE 1=1", filters$sql),
    params = filters$params, default = data.frame(n = 0))
  result$n
}) |> bindCache(input$dashboard_format, input$dashboard_event_type, rv$current_scene, rv$current_continent, rv$community_filter, rv$refresh_tournaments, rv$refresh_decks, rv$refresh_players)

output$total_decks_val <- renderText({
  rv$refresh_tournaments; rv$refresh_decks; rv$refresh_players
  filters <- build_mv_filters(
    format = input$dashboard_format,
    event_type = input$dashboard_event_type,
    scene = rv$current_scene,
    continent = rv$current_continent,
    community_store = rv$community_filter,
    start_idx = 1
  )
  result <- safe_query(db_pool, paste("
    SELECT COUNT(DISTINCT archetype_id)::int as n
    FROM mv_archetype_store_stats
    WHERE 1=1", filters$sql),
    params = filters$params, default = data.frame(n = 0))
  result$n
}) |> bindCache(input$dashboard_format, input$dashboard_event_type, rv$current_scene, rv$current_continent, rv$community_filter, rv$refresh_tournaments, rv$refresh_decks, rv$refresh_players)

# Most popular deck (Top Deck) reactive - reads from deck_analytics batch
most_popular_deck <- reactive({
  data <- deck_analytics()
  if (is.null(data) || nrow(data) == 0) return(NULL)
  data[1, ]  # First row is most popular (ordered by entries DESC)
})

output$most_popular_deck_val <- renderText({
  deck <- most_popular_deck()
  if (is.null(deck)) return("--")
  deck$archetype_name
})

# Top Deck image (for new value box layout)
output$top_deck_image <- renderUI({
  deck <- most_popular_deck()
  if (is.null(deck) || length(deck$display_card_id) == 0 ||
      is.na(deck$display_card_id) || nchar(deck$display_card_id) == 0) {
    return(NULL)
  }
  img_url <- sprintf("https://images.digimoncard.io/images/cards/%s.jpg", deck$display_card_id)
  tags$img(
    src = img_url,
    alt = deck$archetype_name
  )
})

# Top Deck meta share percentage
output$top_deck_meta_share <- renderUI({
  deck <- most_popular_deck()
  if (is.null(deck) || is.null(deck$meta_share)) return(HTML("--"))
  HTML(paste0(deck$meta_share, "% of meta"))
})

# Hot Deck calculation - compares meta share between older and newer tournaments
hot_deck <- reactive({


  filters <- build_dashboard_filters("t", "s")

  # Get tournament count to check if we have enough data
  tournament_count <- safe_query(db_pool, paste("
    SELECT COUNT(*) as n FROM tournaments t
    JOIN stores s ON t.store_id = s.store_id
    WHERE 1=1", filters$sql
  ), params = filters$params, default = data.frame(n = 0))$n

  # Need at least 10 tournaments for meaningful trend data
  if (tournament_count < 10) {
    return(list(insufficient_data = TRUE, tournament_count = tournament_count))
  }

  # Get median tournament date to split into older/newer halves
  median_date <- safe_query(db_pool, paste("
    SELECT TO_TIMESTAMP(
      PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY EXTRACT(EPOCH FROM event_date))
    )::date as median_date
    FROM tournaments t
    JOIN stores s ON t.store_id = s.store_id
    WHERE 1=1", filters$sql
  ), params = filters$params, default = data.frame(median_date = NA))$median_date

  # Build filters with start_idx = 2 for queries that prepend $1 for median_date
  date_filters <- build_dashboard_filters("t", "s", start_idx = 2)

  # Calculate meta share for older tournaments
  # Exclude UNKNOWN archetype from analytics
  # Params: median_date first ($1), then the filter params ($2+)
  older_params <- c(list(as.character(median_date)), date_filters$params)
  older_meta <- safe_query(db_pool, paste("
    SELECT da.archetype_name, da.display_card_id,
           ROUND(COUNT(r.result_id) * 100.0 / NULLIF(SUM(COUNT(r.result_id)) OVER(), 0), 2) as meta_share
    FROM deck_archetypes da
    JOIN results r ON da.archetype_id = r.archetype_id
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    JOIN stores s ON t.store_id = s.store_id
    WHERE t.event_date < $1 AND da.archetype_name != 'UNKNOWN'", date_filters$sql, "
    GROUP BY da.archetype_id, da.archetype_name, da.display_card_id
  "), params = older_params, default = data.frame())

  # Calculate meta share for newer tournaments
  # Exclude UNKNOWN archetype from analytics
  # Params: median_date first ($1), then the filter params ($2+)
  newer_params <- c(list(as.character(median_date)), date_filters$params)
  newer_meta <- safe_query(db_pool, paste("
    SELECT da.archetype_name, da.display_card_id,
           ROUND(COUNT(r.result_id) * 100.0 / NULLIF(SUM(COUNT(r.result_id)) OVER(), 0), 2) as meta_share
    FROM deck_archetypes da
    JOIN results r ON da.archetype_id = r.archetype_id
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    JOIN stores s ON t.store_id = s.store_id
    WHERE t.event_date >= $1 AND da.archetype_name != 'UNKNOWN'", date_filters$sql, "
    GROUP BY da.archetype_id, da.archetype_name, da.display_card_id
  "), params = newer_params, default = data.frame())

  if (nrow(older_meta) == 0 || nrow(newer_meta) == 0) {
    return(list(insufficient_data = TRUE, tournament_count = tournament_count))
  }

  # Merge and calculate delta
  merged <- merge(newer_meta, older_meta, by = c("archetype_name", "display_card_id"),
                  suffixes = c("_new", "_old"), all.x = TRUE)
  merged$meta_share_old[is.na(merged$meta_share_old)] <- 0
  merged$delta <- merged$meta_share_new - merged$meta_share_old

  # Find deck with biggest positive increase
  hot <- merged[which.max(merged$delta), ]

  if (nrow(hot) == 0 || hot$delta <= 0) {
    return(list(insufficient_data = FALSE, no_trending = TRUE))
  }

  list(
    insufficient_data = FALSE,
    archetype_name = hot$archetype_name,
    display_card_id = hot$display_card_id,
    delta = round(hot$delta, 1)
  )
})

output$hot_deck_name <- renderUI({
  hd <- hot_deck()
  if (is.null(hd)) return(HTML("<span class='vb-tracking'>--</span>"))

  if (isTRUE(hd$insufficient_data)) {
    return(HTML("<span class='vb-tracking'>Tracking...</span>"))
  }

  if (isTRUE(hd$no_trending)) {
    return(HTML("<span style='opacity: 0.7;'>No trend</span>"))
  }

  HTML(htmltools::htmlEscape(hd$archetype_name))
}) |> bindCache(input$dashboard_format, input$dashboard_event_type, rv$current_scene, rv$current_continent, rv$community_filter, rv$refresh_tournaments, rv$refresh_decks, rv$refresh_players)

output$hot_deck_trend <- renderUI({
  hd <- hot_deck()
  if (is.null(hd)) return(HTML(""))

  if (isTRUE(hd$insufficient_data)) {
    needed <- as.integer(10 - hd$tournament_count)
    return(HTML(sprintf("<span class='vb-trend-neutral'>%d more events needed</span>", needed)))
  }

  if (isTRUE(hd$no_trending)) {
    return(HTML("<span class='vb-trend-neutral'>stable meta</span>"))
  }

  HTML(sprintf("<span class='vb-trend-up'>+%s%% share</span>", hd$delta))
}) |> bindCache(input$dashboard_format, input$dashboard_event_type, rv$current_scene, rv$current_continent, rv$community_filter, rv$refresh_tournaments, rv$refresh_decks, rv$refresh_players)

# Hot Deck card image
output$hot_deck_image <- renderUI({
  hd <- hot_deck()
  if (is.null(hd) || isTRUE(hd$insufficient_data) || isTRUE(hd$no_trending)) {
    return(NULL)
  }
  if (is.null(hd$display_card_id) || length(hd$display_card_id) == 0 ||
      is.na(hd$display_card_id) || nchar(hd$display_card_id) == 0) {
    return(NULL)
  }
  img_url <- sprintf("https://images.digimoncard.io/images/cards/%s.jpg", hd$display_card_id)
  tags$img(
    src = img_url,
    alt = hd$archetype_name
  )
}) |> bindCache(input$dashboard_format, input$dashboard_event_type, rv$current_scene, rv$current_continent, rv$community_filter, rv$refresh_tournaments, rv$refresh_decks, rv$refresh_players)

# Legacy output for backward compatibility (if needed elsewhere)
output$most_popular_deck_image <- renderUI({
  deck <- most_popular_deck()
  if (is.null(deck) || length(deck$display_card_id) == 0 ||
      is.na(deck$display_card_id) || nchar(deck$display_card_id) == 0) {
    return(bsicons::bs_icon("collection", size = "2.5rem"))
  }
  img_url <- sprintf("https://images.digimoncard.io/images/cards/%s.jpg", deck$display_card_id)
  tags$img(
    src = img_url,
    class = "top-deck-image",
    alt = deck$archetype_name
  )
})

# Helper function to build dashboard filter conditions (parameterized for SQL injection prevention)
# Returns:
#   - sql: SQL fragment with $N placeholders (e.g., "AND t.format = $1 AND t.event_type = $2")
#   - params: List of parameter values in order matching the placeholders
#   - any_active: Boolean indicating if any filters are active
#   - next_idx: Next available parameter index for chaining
build_dashboard_filters <- function(table_alias = "t", store_alias = NULL, start_idx = 1) {
  build_filters_param(
    table_alias = table_alias,
    format = input$dashboard_format,
    event_type = input$dashboard_event_type,
    scene = rv$current_scene,
    continent = rv$current_continent,
    store_alias = store_alias,
    community_store = rv$community_filter,
    start_idx = start_idx
  )
}

# Community section: scene-only filtering (no format, no event type)
build_community_filters <- function(table_alias = "t", store_alias = NULL, start_idx = 1) {
  build_filters_param(
    table_alias = table_alias,
    scene = rv$current_scene,
    continent = rv$current_continent,
    store_alias = store_alias,
    community_store = rv$community_filter,
    start_idx = start_idx
  )
}

# ==========================================================================
# Batch reactive: all deck analytics in one query
# ==========================================================================
deck_analytics <- reactive({

  rv$refresh_tournaments; rv$refresh_decks; rv$refresh_players

  filters <- build_mv_filters(
    format = input$dashboard_format,
    event_type = input$dashboard_event_type,
    scene = rv$current_scene,
    continent = rv$current_continent,
    community_store = rv$community_filter,
    start_idx = 1
  )

  safe_query(db_pool, paste("
    SELECT archetype_id, archetype_name, display_card_id,
           primary_color, is_multi_color,
           SUM(entries)::int as entries,
           SUM(firsts)::int as first_places,
           SUM(top3s)::int as top3,
           ROUND(SUM(entries) * 100.0 / NULLIF(SUM(SUM(entries)) OVER(), 0), 1) as meta_share
    FROM mv_archetype_store_stats
    WHERE 1=1", filters$sql, "
    GROUP BY archetype_id, archetype_name, display_card_id,
             primary_color, is_multi_color
    ORDER BY entries DESC
  "), params = filters$params, default = data.frame())
}) |> bindCache(input$dashboard_format, input$dashboard_event_type, rv$current_scene, rv$current_continent, rv$community_filter, rv$refresh_tournaments, rv$refresh_decks, rv$refresh_players)

# ==========================================================================
# Batch reactive: core metrics (tournament + player counts)
# ==========================================================================
core_metrics <- reactive({

  rv$refresh_tournaments; rv$refresh_decks; rv$refresh_players

  filters <- build_mv_filters(
    format = input$dashboard_format,
    event_type = input$dashboard_event_type,
    scene = rv$current_scene,
    continent = rv$current_continent,
    community_store = rv$community_filter,
    start_idx = 1
  )

  # Use mv_tournament_list for correct distinct counts (can't SUM pre-aggregated distincts)
  result <- safe_query(db_pool, paste("
    WITH filtered AS (
      SELECT tournament_id FROM mv_tournament_list WHERE 1=1", filters$sql, "
    )
    SELECT
      (SELECT COUNT(*)::int FROM filtered) as tournaments,
      (SELECT COUNT(DISTINCT r.player_id)::int
       FROM results r WHERE r.tournament_id IN (SELECT tournament_id FROM filtered)) as players
  "), params = filters$params, default = data.frame(tournaments = 0, players = 0))

  if (nrow(result) > 0) as.list(result[1, ]) else list(tournaments = 0, players = 0)
}) |> bindCache(input$dashboard_format, input$dashboard_event_type, rv$current_scene, rv$current_continent, rv$community_filter, rv$refresh_tournaments, rv$refresh_decks, rv$refresh_players)

# Recent tournaments (community section - scene-only filtering)
# Shows Winner column, formatted Type, and Store Rating
# When "All Scenes" selected, also shows the Scene column
output$recent_tournaments <- renderReactable({
  rv$refresh_tournaments; rv$refresh_decks; rv$refresh_players  # Trigger refresh on admin changes

  show_all_scenes <- is.null(rv$current_scene) || rv$current_scene == "all"
  filters <- build_community_filters("t", "s")

  # Query with winner (player who got placement = 1) and store_id for rating join
  # Include scene info when showing all scenes (scene_type + country for flag display)
  if (show_all_scenes) {
    query <- paste("
      SELECT t.tournament_id, s.store_id, sc.scene_type, s.country,
             s.name as \"Store\", t.event_date as \"Date\",
             t.player_count as \"Players\",
             CASE WHEN p.is_anonymized THEN 'Anonymous' ELSE p.display_name END as \"Winner\"
      FROM tournaments t
      JOIN stores s ON t.store_id = s.store_id
      LEFT JOIN scenes sc ON s.scene_id = sc.scene_id
      LEFT JOIN LATERAL (
        SELECT r2.player_id
        FROM results r2
        WHERE r2.tournament_id = t.tournament_id AND r2.placement = 1
        ORDER BY r2.result_id
        LIMIT 1
      ) r ON true
      LEFT JOIN players p ON r.player_id = p.player_id
      WHERE 1=1", filters$sql, "
      ORDER BY t.event_date DESC
      LIMIT 10
    ")
  } else {
    query <- paste("
      SELECT t.tournament_id, s.store_id, s.name as \"Store\",
             t.event_date as \"Date\", t.player_count as \"Players\",
             CASE WHEN p.is_anonymized THEN 'Anonymous' ELSE p.display_name END as \"Winner\"
      FROM tournaments t
      JOIN stores s ON t.store_id = s.store_id
      LEFT JOIN LATERAL (
        SELECT r2.player_id
        FROM results r2
        WHERE r2.tournament_id = t.tournament_id AND r2.placement = 1
        ORDER BY r2.result_id
        LIMIT 1
      ) r ON true
      LEFT JOIN players p ON r.player_id = p.player_id
      WHERE 1=1", filters$sql, "
      ORDER BY t.event_date DESC
      LIMIT 10
    ")
  }

  data <- safe_query(db_pool, query, params = filters$params, default = data.frame())
  if (nrow(data) == 0) {
    return(reactable(data.frame(Message = "No tournaments yet"), compact = TRUE))
  }

  # Replace NA winners with "-"
  data$Winner[is.na(data$Winner)] <- "-"

  # Build location indicator column for "all scenes" view
  # Uses globe icon for online, flag icons for physical (via flag-icons CSS library)
  if (show_all_scenes) {
    # Country to ISO 3166-1-alpha-2 code mapping (lowercase for flag-icons)
    country_codes <- c(
      "USA" = "us",
      "Canada" = "ca",
      "UK" = "gb",
      "United Kingdom" = "gb",
      "Australia" = "au",
      "Germany" = "de",
      "France" = "fr",
      "Japan" = "jp",
      "Mexico" = "mx",
      "Brazil" = "br",
      "New Zealand" = "nz",
      "Netherlands" = "nl",
      "Spain" = "es",
      "Italy" = "it",
      "South Korea" = "kr",
      "Philippines" = "ph",
      "Singapore" = "sg",
      "Malaysia" = "my",
      "Indonesia" = "id",
      "Thailand" = "th"
    )

    data$Loc <- sapply(seq_len(nrow(data)), function(i) {
      if (!is.na(data$scene_type[i]) && data$scene_type[i] == "online") {
        "online"
      } else if (!is.na(data$country[i]) && data$country[i] %in% names(country_codes)) {
        country_codes[data$country[i]]
      } else {
        "unknown"
      }
    })
  }

  # Build columns list based on whether we're showing all scenes
  columns <- list(
    tournament_id = colDef(show = FALSE),
    store_id = colDef(show = FALSE),
    Store = colDef(
      style = list(overflow = "hidden", textOverflow = "ellipsis", whiteSpace = "nowrap")
    ),
    Date = colDef(
      width = 95,
      style = list(whiteSpace = "nowrap")
    ),
    Players = colDef(width = 45, align = "center", name = "#"),
    Winner = colDef(
      minWidth = 90,
      style = list(overflow = "hidden", textOverflow = "ellipsis", whiteSpace = "nowrap")
    )
  )

  # Add hidden columns for scene data when showing all scenes
  if (show_all_scenes) {
    columns$scene_type <- colDef(show = FALSE)
    columns$country <- colDef(show = FALSE)
  }

  # Add Loc column when showing all scenes (flag icons via flag-icons CSS library)
  if (show_all_scenes) {
    columns$Loc <- colDef(
      name = "",
      width = 36,
      align = "center",
      html = TRUE,
      cell = function(value) {
        if (value == "online") {
          # Globe icon for online scenes (using Bootstrap Icons)
          as.character(bsicons::bs_icon("globe", title = "Online"))
        } else if (value == "unknown") {
          # Dash for unknown
          "<span style='color: #9CA3AF; font-size: 0.75rem;'>--</span>"
        } else {
          # Country flag
          sprintf("<span class='fi fi-%s' title='%s'></span>", value, toupper(value))
        }
      }
    )
    # Reorder columns so Loc appears first
    col_order <- c("tournament_id", "store_id", "scene_type", "country", "Loc", "Store", "Date", "Players", "Winner")
    data <- data[, col_order]
  }

  reactable(data, compact = TRUE, striped = TRUE,
    rowStyle = list(cursor = "pointer"),
    onClick = JS("function(rowInfo, column) {
      if (rowInfo) {
        Shiny.setInputValue('overview_tournament_clicked', rowInfo.row.tournament_id, {priority: 'event'})
      }
    }"),
    columns = columns
  )
}) |> bindCache(rv$current_scene, rv$current_continent, rv$community_filter, rv$refresh_tournaments, rv$refresh_decks, rv$refresh_players)

# Meta Share Timeline - curved area chart showing deck popularity over time
# Shows top 5 or all decks based on toggle

output$meta_share_timeline <- renderHighchart({

  chart_mode <- chart_mode()
  filters <- build_mv_filters(
    format = input$dashboard_format,
    event_type = input$dashboard_event_type,
    scene = rv$current_scene,
    continent = rv$current_continent,
    community_store = rv$community_filter,
    start_idx = 1
  )

  result <- safe_query(db_pool, paste("
    SELECT week_start,
           archetype_name,
           primary_color,
           SUM(entries)::int as entries
    FROM mv_archetype_store_stats
    WHERE 1=1", filters$sql, "
    GROUP BY week_start, archetype_name, primary_color
    ORDER BY week_start, entries DESC
  "), params = filters$params, default = data.frame())

  if (nrow(result) == 0) {
    return(
      highchart() |>
        hc_subtitle(text = "No tournament data to display") |>
        hc_add_theme(hc_theme_atom_switch(chart_mode))
    )
  }

  # Convert dates
  if (!inherits(result$week_start, "Date")) {
    result$week_start <- as.Date(as.character(result$week_start))
  }

  # Calculate overall share and sort decks by color then popularity
  overall <- aggregate(entries ~ archetype_name + primary_color, data = result, FUN = sum)
  overall$overall_share <- overall$entries / sum(overall$entries) * 100

  # Sort by color order first, then by share within each color group
  color_order <- c("Red", "Blue", "Yellow", "Green", "Purple", "Black", "White", "Multi", "Other")
  overall$color_rank <- match(overall$primary_color, color_order)
  overall$color_rank[is.na(overall$color_rank)] <- 999  # Unknown colors last
  overall <- overall[order(overall$color_rank, -overall$overall_share), ]

  # Show all decks (sorted by color for visual grouping in legend)
  selected_decks <- overall$archetype_name

  # Get unique weeks
  weeks <- sort(unique(result$week_start))

  # Build color map for selected decks
  deck_colors <- sapply(selected_decks, function(d) {
    color_row <- overall[overall$archetype_name == d, ]
    if (nrow(color_row) > 0 && color_row$primary_color[1] %in% names(digimon_deck_colors)) {
      digimon_deck_colors[color_row$primary_color[1]]
    } else {
      "#6B7280"
    }
  })

  # Create series list for areaspline (curved area)
  series_list <- lapply(seq_along(selected_decks), function(i) {
    deck <- selected_decks[i]
    deck_data <- result[result$archetype_name == deck, ]

    # Build data points for all weeks (fill missing with 0 for continuous area)
    data_points <- sapply(weeks, function(w) {
      row <- deck_data[deck_data$week_start == w, ]
      if (nrow(row) > 0) row$entries[1] else 0
    })

    list(
      name = deck,
      data = as.list(data_points),
      color = unname(deck_colors[i])
    )
  })

  # Custom tooltip formatter: filter 0% values, sort desc, group <3% into "Other"
  tooltip_formatter <- JS("
    function() {
      var points = this.points.filter(function(p) { return p.percentage > 0; });
      points.sort(function(a, b) { return b.percentage - a.percentage; });
      var html = '<b>' + this.x + '</b><br/>';
      var otherPct = 0;
      var otherCount = 0;
      points.forEach(function(p) {
        if (p.percentage >= 3) {
          html += '<span style=\"color:' + p.series.color + '\">\u25CF</span> ' +
                  p.series.name + ': <b>' + Highcharts.numberFormat(p.percentage, 1) + '%</b><br/>';
        } else {
          otherPct += p.percentage;
          otherCount++;
        }
      });
      if (otherCount > 0) {
        html += '<span style=\"color:#6B7280\">\u25CF</span> Other (' + otherCount + ' decks): <b>' +
                Highcharts.numberFormat(otherPct, 1) + '%</b><br/>';
      }
      if (points.length === 0) {
        html += '<em>No data for this week</em>';
      }
      return html;
    }
  ")

  # Build the chart with areaspline for smooth curves
  highchart() |>
    hc_chart(type = "areaspline") |>
    hc_plotOptions(
      areaspline = list(
        stacking = "percent",
        lineWidth = 1.5,
        fillOpacity = 0.5,
        marker = list(
          enabled = FALSE,
          symbol = "circle",
          radius = 3,
          states = list(
            hover = list(enabled = TRUE)
          )
        )
      )
    ) |>
    hc_xAxis(
      categories = format(weeks, "%b %d"),
      title = list(text = NULL),
      labels = list(
        rotation = -45,
        style = list(fontSize = "10px")
      ),
      tickmarkPlacement = "on"
    ) |>
    hc_yAxis(
      title = list(text = if (is_mobile()) "" else "Meta Share"),
      labels = list(format = "{value}%"),
      min = 0
    ) |>
    hc_tooltip(
      shared = TRUE,
      crosshairs = TRUE,
      useHTML = TRUE,
      formatter = tooltip_formatter
    ) |>
    hc_legend(enabled = FALSE) |>
    hc_add_series_list(series_list) |>
    hc_add_theme(hc_theme_atom_switch(chart_mode))
}) |> bindCache(input$dashboard_format, input$dashboard_event_type, rv$current_scene, rv$current_continent, rv$community_filter, input$dark_mode, rv$refresh_tournaments, rv$refresh_decks, rv$refresh_players)

# Reactive: Total tournaments count for current filters - reads from core_metrics batch
filtered_tournament_count <- reactive({
  core_metrics()$tournaments
})

# Dynamic Top Decks header showing tournament count

output$top_decks_header <- renderUI({
  total <- filtered_tournament_count()
  if (total == 0) {
    "Top Decks"
  } else {
    sprintf("Top Decks (%d Tournaments)", as.integer(total))
  }
})

# Top Decks with Card Images
# Win rate = 1st place finishes / total tournaments in filter
output$top_decks_with_images <- renderUI({
  top_data <- deck_analytics()
  total_tournaments <- filtered_tournament_count()

  if (is.null(top_data) || nrow(top_data) == 0 || total_tournaments == 0) {
    return(digital_empty_state("No tournament data", "// awaiting results", "inbox", mascot = "agumon"))
  }

  # Sort by first places then entries, take top 8
  top_data <- top_data[order(-top_data$first_places, -top_data$entries), ]
  result <- head(top_data, 8)

  # Calculate win rate = 1st places / total tournaments
  result$win_rate <- round(result$first_places / total_tournaments * 100, 1)

  # Generate HTML for each deck
  deck_items <- lapply(1:nrow(result), function(i) {
    row <- result[i, ]
    # Card image URL from DigimonCard.io
    img_url <- if (!is.na(row$display_card_id) && nchar(row$display_card_id) > 0) {
      sprintf("https://images.digimoncard.io/images/cards/%s.jpg", row$display_card_id)
    } else {
      "https://images.digimoncard.io/images/cards/BT1-001.jpg"  # Fallback
    }

    # Color for the bar
    bar_color <- digimon_deck_colors[row$primary_color]
    if (is.na(bar_color)) bar_color <- "#6B7280"

    # Bar width = actual win rate percentage (absolute 0-100 scale)
    bar_width <- min(row$win_rate, 100)  # Cap at 100%

    div(class = "deck-item",
      style = "cursor: pointer;",
      onclick = sprintf("Shiny.setInputValue('overview_deck_clicked', %d, {priority: 'event'})", row$archetype_id),
      div(class = "deck-card-img",
        tags$img(src = img_url, alt = row$archetype_name, loading = "lazy")
      ),
      div(class = "deck-info",
        div(class = "deck-name", row$archetype_name),
        div(class = "deck-bar-container",
          div(class = "deck-bar",
            style = sprintf("width: %s%%; background-color: %s;", bar_width, bar_color)
          )
        ),
        div(class = "deck-stats",
          span(class = "deck-entries", sprintf("%d wins", as.integer(row$first_places))),
          span(class = "deck-pct", sprintf("%.1f%% win rate", row$win_rate))
        )
      )
    )
  })

  div(class = "top-decks-grid", deck_items)
})

# Top Decks click -> open deck modal on overview
observeEvent(input$overview_deck_clicked, {
  req(input$overview_deck_clicked)
  rv$selected_archetype_id <- input$overview_deck_clicked
})

# ---------------------------------------------------------------------------
# Dashboard Charts (Highcharter)
# ---------------------------------------------------------------------------

# Digimon TCG deck colors for charts
digimon_deck_colors <- c(
  "Red" = "#E5383B",
  "Blue" = "#2D7DD2",
  "Yellow" = "#F5B700",
  "Green" = "#38A169",
  "Black" = "#2D3748",
  "Purple" = "#805AD5",
  "White" = "#E2E8F0",
  "Multi" = "#EC4899",  # Pink for multi-color decks
  "Other" = "#9CA3AF"   # Gray for Other Decks category
)

# Top 3 Conversion threshold note - shows in card header
# Minimum entries: 10 for "All Scenes", 3 for specific scenes
output$conversion_threshold_note <- renderUI({
  show_all_scenes <- is.null(rv$current_scene) || rv$current_scene == "all"
  min_entries <- if (show_all_scenes) 10 else 3
  tags$span(class = "text-muted small", sprintf("Min. %d entries", min_entries))
})

# Top 3 Conversion Rate Chart - reads from deck_analytics batch
output$conversion_rate_chart <- renderHighchart({
  chart_mode <- chart_mode()
  show_all_scenes <- is.null(rv$current_scene) || rv$current_scene == "all"

  # Set minimum entries threshold based on scene selection
  min_entries <- if (show_all_scenes) 10 else 3

  data <- deck_analytics()
  if (is.null(data) || nrow(data) == 0) {
    return(
      highchart() |>
        hc_add_theme(hc_theme_atom_switch(chart_mode))
    )
  }

  # Filter to minimum entries and calculate conversion
  result <- data[data$entries >= min_entries, ]
  if (nrow(result) == 0) {
    return(
      highchart() |>
        hc_add_theme(hc_theme_atom_switch(chart_mode))
    )
  }
  result$conversion <- round(result$top3 * 100.0 / result$entries, 1)
  result$name <- result$archetype_name
  result$color <- result$primary_color
  result <- result[order(-result$conversion), ]
  result <- head(result, 5)

  # Assign colors based on deck color
  result$bar_color <- sapply(result$color, function(c) {
    col <- digimon_deck_colors[c]
    if (is.na(col)) "#6B7280" else col
  })

  highchart() |>
    hc_chart(type = "bar") |>
    hc_xAxis(categories = result$name, title = list(text = "")) |>
    hc_yAxis(title = list(text = ""), max = 100, labels = list(format = "{value}%")) |>
    hc_add_series(
      name = "Conversion",
      data = lapply(1:nrow(result), function(i) {
        list(y = result$conversion[i], color = result$bar_color[i],
             top3 = result$top3[i], entries = result$entries[i])
      }),
      showInLegend = FALSE,
      dataLabels = list(
        enabled = TRUE,
        format = "{y}%"
      )
    ) |>
    hc_tooltip(
      pointFormat = "<b>{point.y}%</b> top 3 rate<br/>({point.top3}/{point.entries} entries)",
      headerFormat = "<b>{point.key}</b><br/>"
    ) |>
    hc_add_theme(hc_theme_atom_switch(chart_mode))
}) |> bindCache(input$dashboard_format, input$dashboard_event_type, rv$current_scene, rv$current_continent, rv$community_filter, input$dark_mode, rv$refresh_tournaments, rv$refresh_decks, rv$refresh_players)

# Color Distribution Bar Chart - reads from deck_analytics batch
output$color_dist_chart <- renderHighchart({
  chart_mode <- chart_mode()

  data <- deck_analytics()
  if (is.null(data) || nrow(data) == 0) {
    return(
      highchart() |>
        hc_add_theme(hc_theme_atom_switch(chart_mode))
    )
  }

  # Aggregate by primary_color
  result <- aggregate(entries ~ primary_color, data = data, FUN = sum)
  names(result) <- c("color", "count")
  result <- result[order(-result$count), ]

  # Assign deck colors
  result$bar_color <- sapply(result$color, function(c) {
    col <- digimon_deck_colors[c]
    if (is.na(col)) "#6B7280" else col
  })

  highchart() |>
    hc_chart(type = "bar") |>
    hc_xAxis(categories = result$color, title = list(text = ""), labels = list(enabled = FALSE)) |>
    hc_yAxis(title = list(text = "")) |>
    hc_add_series(
      name = "Entries",
      data = lapply(1:nrow(result), function(i) {
        list(y = result$count[i], color = result$bar_color[i])
      }),
      showInLegend = FALSE,
      dataLabels = list(
        enabled = TRUE,
        format = "{point.category}"
      )
    ) |>
    hc_tooltip(pointFormat = "<b>{point.y}</b> entries") |>
    hc_add_theme(hc_theme_atom_switch(chart_mode))
}) |> bindCache(input$dashboard_format, input$dashboard_event_type, rv$current_scene, rv$current_continent, rv$community_filter, input$dark_mode, rv$refresh_tournaments, rv$refresh_decks, rv$refresh_players)

# Tournament Activity Chart (community section - scene-only filtering)
output$tournaments_trend_chart <- renderHighchart({

  chart_mode <- chart_mode()

  # Build community filter conditions (scene-only)
  filters <- build_community_filters("t", "s")

  # Query tournaments aggregated by day with avg players (parameterized)
  result <- safe_query(db_pool, paste("
    SELECT t.event_date,
           COUNT(*) as tournaments,
           ROUND(AVG(t.player_count), 1) as avg_players
    FROM tournaments t
    JOIN stores s ON t.store_id = s.store_id
    WHERE 1=1", filters$sql, "
    GROUP BY t.event_date
    ORDER BY t.event_date
  "), params = filters$params, default = data.frame())

  if (nrow(result) == 0) {
    return(
      highchart() |>
        hc_subtitle(text = "Tournament history will appear here") |>
        hc_add_theme(hc_theme_atom_switch(chart_mode))
    )
  }

  # Convert dates - handle both Date objects and character strings
  if (!inherits(result$event_date, "Date")) {
    result$event_date <- as.Date(as.character(result$event_date))
  }

  # Calculate 7-day (weekly) rolling average
  result$rolling_avg <- sapply(1:nrow(result), function(i) {
    current_date <- result$event_date[i]
    week_ago <- current_date - 7
    # Include all data points within the last 7 days
    in_window <- result$event_date >= week_ago & result$event_date <= current_date
    round(mean(result$avg_players[in_window], na.rm = TRUE), 1)
  })

  # Convert dates to milliseconds since epoch for Highcharts
  result$timestamp <- as.numeric(result$event_date) * 86400000  # days to milliseconds

  highchart() |>
    hc_chart(type = "spline") |>
    hc_xAxis(
      type = "datetime",
      title = list(text = NULL)
    ) |>
    hc_yAxis(title = list(text = if (is_mobile()) "" else "Players"), min = 0) |>
    hc_add_series(
      name = "Daily Avg",
      data = lapply(1:nrow(result), function(i) {
        list(x = result$timestamp[i], y = result$avg_players[i], tournaments = result$tournaments[i])
      }),
      color = "#0F4C81",
      marker = list(enabled = TRUE, radius = 4)
    ) |>
    hc_add_series(
      name = "7-Day Rolling Avg",
      data = lapply(1:nrow(result), function(i) {
        list(x = result$timestamp[i], y = result$rolling_avg[i])
      }),
      color = "#F7941D",
      dashStyle = "ShortDash",
      marker = list(enabled = FALSE)
    ) |>
    hc_tooltip(
      shared = TRUE,
      crosshairs = TRUE,
      pointFormat = "<b>{series.name}:</b> {point.y} players<br/>"
    ) |>
    hc_add_theme(hc_theme_atom_switch(chart_mode))
}) |> bindCache(rv$current_scene, rv$current_continent, rv$community_filter, input$dark_mode, rv$refresh_tournaments, rv$refresh_decks, rv$refresh_players)

# ---------------------------------------------------------------------------
# Scene Health Section
# ---------------------------------------------------------------------------

# Meta Diversity - reads from deck_analytics batch, calculates HHI-based diversity score
meta_diversity_data <- reactive({
  data <- deck_analytics()
  if (is.null(data) || nrow(data) == 0) return(list(score = 0, decks_with_wins = 0, total_wins = 0))

  # Only decks with wins
  winners <- data[data$first_places > 0, ]
  if (nrow(winners) == 0) return(list(score = 0, decks_with_wins = 0, total_wins = 0))

  total_wins <- sum(winners$first_places)
  shares <- winners$first_places / total_wins
  hhi <- sum(shares^2)

  # Convert to diversity score (0-100, higher = more diverse)
  # HHI of 1 = monopoly (one deck wins everything) -> score 0
  # HHI of 1/n = perfect equality -> score approaches 100
  diversity_score <- as.integer(round((1 - hhi) * 100, 0))

  list(score = diversity_score, decks_with_wins = nrow(winners), total_wins = total_wins)
})

# Meta Diversity decks count for header
output$meta_diversity_decks_count <- renderUI({
  data <- meta_diversity_data()
  if (is.null(data) || data$decks_with_wins == 0) {
    return(tags$span(class = "text-muted small", "No data"))
  }
  tags$span(class = "text-muted small", sprintf("%d decks with wins", as.integer(data$decks_with_wins)))
})

output$meta_diversity_gauge <- renderHighchart({
  data <- meta_diversity_data()
  chart_mode <- chart_mode()

  if (is.null(data) || data$decks_with_wins == 0) {
    return(
      highchart() |>
        hc_subtitle(text = "No data available") |>
        hc_add_theme(hc_theme_atom_switch(chart_mode))
    )
  }

  score <- as.integer(data$score)
  decks_with_wins <- data$decks_with_wins
  total_wins <- data$total_wins

  # Determine color and label based on score: red (<40), yellow (40-70), green (>70)
  if (score < 40) {
    score_color <- "#E5383B"  # red
    health_label <- "Low Diversity"
    health_desc <- "A few decks dominate the meta"
  } else if (score < 70) {
    score_color <- "#F5B700"  # yellow
    health_label <- "Moderate Diversity"
    health_desc <- "Several viable decks in the meta"
  } else {
    score_color <- "#38A169"  # green
    health_label <- "High Diversity"
    health_desc <- "Many competitive decks in the meta"
  }

  # Background color for the remaining portion
  bg_color <- if (chart_mode == "dark") "#475569" else "#e2e8f0"
  text_color <- if (chart_mode == "dark") "#e2e8f0" else "#1e293b"

  # Custom renderer to draw centered text in the donut hole
  center_text_renderer <- JS(sprintf("
    function() {
      var chart = this;
      var centerX = chart.plotLeft + chart.plotWidth / 2;
      var centerY = chart.plotTop + chart.plotHeight / 2;

      // Remove existing center text if re-rendering
      if (chart.centerText) {
        chart.centerText.destroy();
      }
      if (chart.centerSubtext) {
        chart.centerSubtext.destroy();
      }

      // Draw main score
      chart.centerText = chart.renderer.text('%s', centerX, centerY + 8)
        .css({
          fontSize: '28px',
          fontWeight: 'bold',
          color: '%s',
          textAnchor: 'middle'
        })
        .attr({ zIndex: 5, align: 'center' })
        .add();

      // Draw subtext
      chart.centerSubtext = chart.renderer.text('/ 100', centerX, centerY + 28)
        .css({
          fontSize: '12px',
          color: '%s',
          opacity: 0.7,
          textAnchor: 'middle'
        })
        .attr({ zIndex: 5, align: 'center' })
        .add();
    }
  ", score, text_color, text_color))

  highchart() |>
    hc_chart(
      type = "pie",
      spacing = c(0, 0, 0, 0),
      margin = c(0, 0, 0, 0),
      events = list(
        load = center_text_renderer,
        redraw = center_text_renderer
      )
    ) |>
    hc_title(text = NULL) |>
    hc_plotOptions(
      pie = list(
        innerSize = "70%",
        dataLabels = list(enabled = FALSE),
        startAngle = 0,
        endAngle = 360,
        cursor = "pointer"
      )
    ) |>
    hc_add_series(
      name = "Diversity",
      data = list(
        list(
          name = "Score",
          y = score,
          color = score_color,
          custom = list(
            healthLabel = health_label,
            healthDesc = health_desc,
            decksWithWins = decks_with_wins,
            totalWins = total_wins
          )
        ),
        list(name = "Remaining", y = 100 - score, color = bg_color)
      )
    ) |>
    hc_tooltip(
      useHTML = TRUE,
      formatter = JS(sprintf("
        function() {
          if (this.point.name === 'Remaining') {
            return false;  // Don't show tooltip for background
          }
          return '<div style=\"text-align:center;padding:8px;\">' +
            '<b style=\"font-size:14px;\">%s</b><br/>' +
            '<span style=\"opacity:0.8;\">%s</span><br/><br/>' +
            '<span style=\"font-size:12px;\">' +
            '<b>%d</b> decks with wins<br/>' +
            '<b>%d</b> total tournament wins' +
            '</span></div>';
        }
      ", health_label, health_desc, decks_with_wins, total_wins))
    ) |>
    hc_add_theme(hc_theme_atom_switch(chart_mode))
}) |> bindCache(input$dashboard_format, input$dashboard_event_type, rv$current_scene, rv$current_continent, rv$community_filter, input$dark_mode, rv$refresh_tournaments, rv$refresh_decks, rv$refresh_players)

# Player Growth & Retention Chart (community section - scene-only filtering)
output$player_growth_chart <- renderHighchart({

  chart_mode <- chart_mode()
  filters <- build_community_filters("t", "s")

  # Get player participation by week with their first ever tournament (parameterized)
  result <- safe_query(db_pool, paste("
    WITH player_first AS (
      SELECT r.player_id,
             MIN(t.event_date) as first_date,
             date_trunc('week', MIN(t.event_date)) as first_week
      FROM results r
      JOIN tournaments t ON r.tournament_id = t.tournament_id
      GROUP BY r.player_id
    ),
    player_weekly AS (
      SELECT DISTINCT
        date_trunc('week', t.event_date) as week,
        r.player_id,
        pf.first_week,
        pf.first_date
      FROM results r
      JOIN tournaments t ON r.tournament_id = t.tournament_id
      JOIN stores s ON t.store_id = s.store_id
      JOIN player_first pf ON r.player_id = pf.player_id
      WHERE 1=1", filters$sql, "
    ),
    player_cumulative AS (
      SELECT
        pw.week,
        pw.player_id,
        pw.first_week,
        (SELECT COUNT(DISTINCT t2.tournament_id)
         FROM results r2
         JOIN tournaments t2 ON r2.tournament_id = t2.tournament_id
         WHERE r2.player_id = pw.player_id
           AND date_trunc('week', t2.event_date) < pw.week) as prior_events
      FROM player_weekly pw
    )
    SELECT
      week,
      COUNT(CASE WHEN first_week = week THEN 1 END) as new_players,
      COUNT(CASE WHEN first_week < week AND prior_events < 3 THEN 1 END) as returning_players,
      COUNT(CASE WHEN prior_events >= 3 THEN 1 END) as regulars
    FROM player_cumulative
    GROUP BY week
    ORDER BY week
  "), params = filters$params, default = data.frame())

  if (nrow(result) == 0) {
    return(
      highchart() |>
        hc_subtitle(text = "No player data yet") |>
        hc_add_theme(hc_theme_atom_switch(chart_mode))
    )
  }

  # Convert week to Date if needed (date_trunc may return different types)
  if (!inherits(result$week, "Date")) {
    result$week <- as.Date(as.character(result$week))
  }

  highchart() |>
    hc_chart(type = "column") |>
    hc_title(text = NULL) |>
    hc_xAxis(
      categories = format(result$week, "%b %d"),
      title = list(text = NULL)
    ) |>
    hc_yAxis(
      title = list(text = if (is_mobile()) "" else "Players"),
      stackLabels = list(enabled = FALSE)
    ) |>
    hc_plotOptions(
      column = list(
        stacking = "normal",
        borderWidth = 0
      )
    ) |>
    hc_add_series(name = "New", data = result$new_players, color = "#38A169") |>
    hc_add_series(name = "Returning", data = result$returning_players, color = "#2D7DD2") |>
    hc_add_series(name = "Regulars", data = result$regulars, color = "#805AD5") |>
    hc_tooltip(
      shared = TRUE,
      pointFormat = "<b>{series.name}:</b> {point.y}<br/>"
    ) |>
    hc_legend(
      enabled = TRUE,
      layout = "horizontal",
      align = "center",
      verticalAlign = "bottom"
    ) |>
    hc_add_theme(hc_theme_atom_switch(chart_mode))
}) |> bindCache(rv$current_scene, rv$current_continent, rv$community_filter, input$dark_mode, rv$refresh_tournaments, rv$refresh_decks, rv$refresh_players)

# Rising Stars - players with strong recent performance (community section - scene-only filtering)
output$rising_stars_cards <- renderUI({

  # Build filters with start_idx = 2 because $1 is used for date_30_ago
  filters <- build_community_filters("t", "s", start_idx = 2)
  today <- Sys.Date()
  date_30_ago <- format(today - 30, "%Y-%m-%d")

  # Get players with top 3 finishes in last 30 days (parameterized)
  # Params: date_30_ago first ($1), then the filter params ($2+)
  query_params <- c(list(date_30_ago), filters$params)
  result <- safe_query(db_pool, paste("
    SELECT
      p.player_id,
      p.display_name,
      COUNT(CASE WHEN r.placement = 1 THEN 1 END) as recent_wins,
      COUNT(CASE WHEN r.placement <= 3 THEN 1 END) as recent_top3,
      COUNT(*) as recent_events
    FROM results r
    JOIN players p ON r.player_id = p.player_id
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    JOIN stores s ON t.store_id = s.store_id
    WHERE t.event_date >= $1 AND p.is_anonymized IS NOT TRUE", filters$sql, "
    GROUP BY p.player_id, p.display_name
    HAVING COUNT(CASE WHEN r.placement <= 3 THEN 1 END) > 0
    ORDER BY
      COUNT(CASE WHEN r.placement = 1 THEN 1 END) DESC,
      COUNT(CASE WHEN r.placement <= 3 THEN 1 END) DESC,
      COUNT(*) DESC
    LIMIT 8
  "), params = query_params, default = data.frame())

  if (nrow(result) == 0) {
    return(div(class = "text-muted text-center py-3", "No recent top placements"))
  }

  # Get competitive ratings and merge
  comp_ratings <- player_competitive_ratings()
  if (nrow(comp_ratings) > 0) {
    result <- merge(result, comp_ratings, by = "player_id", all.x = TRUE)
  }
  if (!"competitive_rating" %in% names(result)) result$competitive_rating <- NA
  result$competitive_rating[is.na(result$competitive_rating)] <- 1500

  # Re-sort after merge
  result <- result[order(-result$recent_wins, -result$recent_top3, -result$recent_events), ]

  # Build player cards
  div(class = "rising-stars-grid",
    lapply(1:nrow(result), function(i) {
      player <- result[i, ]
      # Build placement badges
      badges <- tagList()
      if (player$recent_wins > 0) {
        badges <- tagList(badges,
          span(class = "rising-star-badge badge-gold",
            bsicons::bs_icon("trophy-fill", class = "me-1"),
            player$recent_wins
          )
        )
      }
      if (player$recent_top3 - player$recent_wins > 0) {
        badges <- tagList(badges,
          span(class = "rising-star-badge badge-silver",
            bsicons::bs_icon("award-fill", class = "me-1"),
            player$recent_top3 - player$recent_wins
          )
        )
      }

      div(class = "rising-star-card",
        style = "cursor: pointer;",
        onclick = sprintf("Shiny.setInputValue('overview_rising_star_clicked', %d, {priority: 'event'})", player$player_id),
        div(class = "rising-star-rank", i),
        div(class = "rising-star-info",
          div(class = "rising-star-name", player$display_name),
          div(class = "rising-star-badges", badges)
        ),
        div(class = "rising-star-rating",
          span(class = "rating-value", player$competitive_rating),
          span(class = "rating-label", "Rating")
        )
      )
    })
  )
}) |> bindCache(rv$current_scene, rv$current_continent, rv$community_filter, rv$refresh_tournaments, rv$refresh_decks, rv$refresh_players)

# Rising Stars click -> open player modal on overview
observeEvent(input$overview_rising_star_clicked, {
  req(input$overview_rising_star_clicked)
  rv$selected_player_id <- input$overview_rising_star_clicked
})

# ---------------------------------------------------------------------------
# Mobile Dashboard Renderers
# ---------------------------------------------------------------------------

# Mobile Rising Stars — horizontal scroll cards reusing same data source
output$mobile_rising_stars <- renderUI({
  req(is_mobile())

  # Same query as output$rising_stars_cards (community section - scene-only filtering)
  filters <- build_community_filters("t", "s", start_idx = 2)
  today <- Sys.Date()
  date_30_ago <- format(today - 30, "%Y-%m-%d")

  query_params <- c(list(date_30_ago), filters$params)
  result <- safe_query(db_pool, paste("
    SELECT
      p.player_id,
      p.display_name,
      COUNT(CASE WHEN r.placement = 1 THEN 1 END) as recent_wins,
      COUNT(CASE WHEN r.placement <= 3 THEN 1 END) as recent_top3,
      COUNT(*) as recent_events
    FROM results r
    JOIN players p ON r.player_id = p.player_id
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    JOIN stores s ON t.store_id = s.store_id
    WHERE t.event_date >= $1 AND p.is_anonymized IS NOT TRUE", filters$sql, "
    GROUP BY p.player_id, p.display_name
    HAVING COUNT(CASE WHEN r.placement <= 3 THEN 1 END) > 0
    ORDER BY
      COUNT(CASE WHEN r.placement = 1 THEN 1 END) DESC,
      COUNT(CASE WHEN r.placement <= 3 THEN 1 END) DESC,
      COUNT(*) DESC
    LIMIT 8
  "), params = query_params, default = data.frame())

  if (nrow(result) == 0) {
    return(div(class = "text-muted text-center py-3", "No recent top placements"))
  }

  # Get competitive ratings and merge
  comp_ratings <- player_competitive_ratings()
  if (nrow(comp_ratings) > 0) {
    result <- merge(result, comp_ratings, by = "player_id", all.x = TRUE)
  }
  if (!"competitive_rating" %in% names(result)) result$competitive_rating <- NA
  result$competitive_rating[is.na(result$competitive_rating)] <- 1500
  result <- result[order(-result$recent_wins, -result$recent_top3, -result$recent_events), ]

  div(class = "mobile-horizontal-scroll mobile-scroll-compact",
    lapply(seq_len(nrow(result)), function(i) {
      player <- result[i, ]

      # Build placement badges (same classes as desktop)
      badges <- tagList()
      if (player$recent_wins > 0) {
        badges <- tagList(badges,
          span(class = "mobile-star-badge mobile-star-badge-gold",
            bsicons::bs_icon("trophy-fill"),
            player$recent_wins
          )
        )
      }
      if (player$recent_top3 - player$recent_wins > 0) {
        badges <- tagList(badges,
          span(class = "mobile-star-badge mobile-star-badge-silver",
            bsicons::bs_icon("award-fill"),
            player$recent_top3 - player$recent_wins
          )
        )
      }

      div(
        class = "mobile-star-card",
        onclick = sprintf("Shiny.setInputValue('overview_rising_star_clicked', %d, {priority: 'event'})", player$player_id),
        # Rank badge
        div(class = "mobile-rank-badge", i),
        # Player name
        div(class = "mobile-star-card-name", player$display_name),
        # Badges row
        div(class = "mobile-star-card-badges", badges),
        # Rating
        div(class = "mobile-star-card-rating",
          span(class = "mobile-star-card-rating-value", player$competitive_rating),
          span(class = "mobile-star-card-rating-label", "Rating")
        )
      )
    })
  )
}) |> bindCache(rv$current_scene, rv$current_continent, rv$community_filter, rv$refresh_tournaments, rv$refresh_decks, rv$refresh_players)

# Mobile Top Decks — horizontal scroll cards reusing deck_analytics() reactive
output$mobile_top_decks <- renderUI({
  req(is_mobile())

  top_data <- deck_analytics()
  total_tournaments <- filtered_tournament_count()

  if (is.null(top_data) || nrow(top_data) == 0 || total_tournaments == 0) {
    return(div(class = "text-muted text-center py-3", "No tournament data"))
  }

  # Sort by first places then entries, take top 8 (same as desktop)
  top_data <- top_data[order(-top_data$first_places, -top_data$entries), ]
  result <- head(top_data, 8)
  result$win_rate <- round(result$first_places / total_tournaments * 100, 1)

  div(class = "mobile-horizontal-scroll mobile-scroll-compact",
    lapply(seq_len(nrow(result)), function(i) {
      row <- result[i, ]

      # Card image
      img_url <- if (!is.na(row$display_card_id) && nchar(row$display_card_id) > 0) {
        sprintf("https://images.digimoncard.io/images/cards/%s.jpg", row$display_card_id)
      } else {
        NULL
      }

      # Deck color for accent
      deck_color <- digimon_deck_colors[row$primary_color]
      if (is.na(deck_color)) deck_color <- "#6B7280"

      # Bar width = win rate percentage (capped at 100)
      bar_width <- min(row$win_rate, 100)

      div(
        class = "mobile-deck-card",
        style = sprintf("border-left: 3px solid %s;", deck_color),
        onclick = sprintf("Shiny.setInputValue('overview_deck_clicked', %d, {priority: 'event'})", row$archetype_id),
        # Rank badge
        div(class = "mobile-rank-badge", i),
        # Card image thumbnail (if available)
        if (!is.null(img_url)) {
          tags$img(
            class = "mobile-deck-card-img",
            src = img_url,
            alt = row$archetype_name,
            loading = "lazy"
          )
        },
        # Deck name
        div(class = "mobile-deck-card-name", row$archetype_name),
        # Win rate bar (matches desktop)
        div(class = "mobile-deck-card-bar",
          div(class = "mobile-deck-card-bar-fill",
            style = sprintf("width: %s%%; background-color: %s;", bar_width, deck_color)
          )
        ),
        # Stats row
        div(class = "mobile-deck-card-stats",
          span(sprintf("%d wins", as.integer(row$first_places))),
          span(class = "mobile-deck-card-wins",
            sprintf("%.1f%% win", row$win_rate)
          )
        )
      )
    })
  )
}) |> bindCache(input$dashboard_format, input$dashboard_event_type, rv$current_scene, rv$current_continent, rv$community_filter, rv$refresh_tournaments, rv$refresh_decks, rv$refresh_players)

# Mobile Recent Tournaments — vertical card list replacing reactable
output$mobile_recent_tournaments <- renderUI({
  req(is_mobile())

  # Same query as output$recent_tournaments (community section - scene-only filtering)
  show_all_scenes <- is.null(rv$current_scene) || rv$current_scene == "all"
  filters <- build_community_filters("t", "s")

  # Include scene_type + country when showing all scenes (for flag display)
  if (show_all_scenes) {
    query <- paste("
      SELECT t.tournament_id, s.name as store_name,
             t.event_date, t.player_count,
             CASE WHEN p.is_anonymized THEN 'Anonymous' ELSE p.display_name END as winner_name,
             sc.scene_type, s.country
      FROM tournaments t
      JOIN stores s ON t.store_id = s.store_id
      LEFT JOIN scenes sc ON s.scene_id = sc.scene_id
      LEFT JOIN LATERAL (
        SELECT r2.player_id
        FROM results r2
        WHERE r2.tournament_id = t.tournament_id AND r2.placement = 1
        ORDER BY r2.result_id
        LIMIT 1
      ) r ON true
      LEFT JOIN players p ON r.player_id = p.player_id
      WHERE 1=1", filters$sql, "
      ORDER BY t.event_date DESC
      LIMIT 5
    ")
  } else {
    query <- paste("
      SELECT t.tournament_id, s.name as store_name,
             t.event_date, t.player_count,
             CASE WHEN p.is_anonymized THEN 'Anonymous' ELSE p.display_name END as winner_name
      FROM tournaments t
      JOIN stores s ON t.store_id = s.store_id
      LEFT JOIN LATERAL (
        SELECT r2.player_id
        FROM results r2
        WHERE r2.tournament_id = t.tournament_id AND r2.placement = 1
        ORDER BY r2.result_id
        LIMIT 1
      ) r ON true
      LEFT JOIN players p ON r.player_id = p.player_id
      WHERE 1=1", filters$sql, "
      ORDER BY t.event_date DESC
      LIMIT 5
    ")
  }

  data <- safe_query(db_pool, query, params = filters$params, default = data.frame())
  if (nrow(data) == 0) {
    return(div(class = "text-muted text-center py-3", "No tournaments yet"))
  }

  # Country code mapping (same as desktop recent_tournaments)
  country_codes <- c(
    "USA" = "us", "Canada" = "ca", "UK" = "gb", "United Kingdom" = "gb",
    "Australia" = "au", "Germany" = "de", "France" = "fr", "Japan" = "jp",
    "Mexico" = "mx", "Brazil" = "br", "New Zealand" = "nz",
    "Netherlands" = "nl", "Spain" = "es", "Italy" = "it",
    "South Korea" = "kr", "Philippines" = "ph", "Singapore" = "sg",
    "Malaysia" = "my", "Indonesia" = "id", "Thailand" = "th"
  )

  div(class = "mobile-tournament-list",
    lapply(seq_len(nrow(data)), function(i) {
      row <- data[i, ]
      winner <- if (is.na(row$winner_name)) "\u2014" else row$winner_name

      # Build flag element for all-scenes view
      flag_el <- NULL
      if (show_all_scenes) {
        if (!is.na(row$scene_type) && row$scene_type == "online") {
          flag_el <- span(class = "mobile-tournament-flag",
            bsicons::bs_icon("globe"))
        } else if (!is.na(row$country) && row$country %in% names(country_codes)) {
          flag_el <- span(class = "mobile-tournament-flag",
            tags$span(class = sprintf("fi fi-%s", country_codes[row$country])))
        }
      }

      div(
        class = "mobile-tournament-card",
        onclick = sprintf("Shiny.setInputValue('overview_tournament_clicked', %d, {priority: 'event'})", row$tournament_id),
        # Left: date badge
        div(class = "mobile-tournament-date",
          tags$span(class = "mobile-tournament-date-day",
            format(as.Date(row$event_date), "%d")),
          tags$span(class = "mobile-tournament-date-month",
            toupper(format(as.Date(row$event_date), "%b")))
        ),
        # Middle: store + winner
        div(class = "mobile-tournament-info",
          div(class = "mobile-tournament-store", flag_el, row$store_name),
          div(class = "mobile-tournament-winner",
            bsicons::bs_icon("trophy-fill", class = "me-1"),
            winner
          )
        ),
        # Right: player count pill
        div(class = "mobile-tournament-players",
          span(class = "mobile-tournament-players-count", row$player_count),
          span(class = "mobile-tournament-players-label", "players")
        )
      )
    })
  )
}) |> bindCache(rv$current_scene, rv$current_continent, rv$community_filter, rv$refresh_tournaments, rv$refresh_decks, rv$refresh_players)
