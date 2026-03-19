# =============================================================================
# Public: Tournaments Tab Server Logic
# =============================================================================
# Note: Contains overview_tournament_clicked handler which is triggered from
# the Dashboard tab to open tournament details from "Recent Tournaments" table.

# ---------------------------------------------------------------------------
# Page Rendering (desktop vs mobile)
# ---------------------------------------------------------------------------
output$tournaments_page <- renderUI({
  format_choices_with_all <- get_format_choices_with_all(db_pool)
  if (is_mobile()) {
    source("views/mobile-tournaments-ui.R", local = TRUE)$value
  } else {
    source("views/tournaments-ui.R", local = TRUE)$value
  }
})

# Reset tournaments filters
observeEvent(input$reset_tournaments_filters, {
  updateTextInput(session, "tournaments_search", value = "")
  updateSelectInput(session, "tournaments_format", selected = "")
  updateSelectInput(session, "tournaments_event_type", selected = "")
  updateSelectInput(session, "tournaments_store_filter", selected = "")
  updateDateInput(session, "tournaments_date_from", value = NA)
  updateDateInput(session, "tournaments_date_to", value = NA)
  updateSelectInput(session, "tournaments_size_filter", selected = "0")
})

# Update store filter choices when scene changes or tab is first visited
observe({
  req("tournaments" %in% visited_tabs())
  rv$refresh_tournaments

  # Wait for advanced filter UI to render (isolate to avoid re-firing on selection change)
  if (is.null(isolate(input$tournaments_store_filter))) {
    invalidateLater(200)
    return()
  }

  scene_filters <- build_filters_param(
    table_alias = "s",
    scene = rv$current_scene,
    continent = rv$current_continent,
    store_alias = "s"
  )

  stores <- safe_query(db_pool, sprintf(
    "SELECT DISTINCT s.slug, s.name FROM stores s
     JOIN tournaments t ON s.store_id = t.store_id
     WHERE s.is_active = TRUE AND s.slug IS NOT NULL %s
     ORDER BY s.name", scene_filters$sql),
  params = scene_filters$params,
  default = data.frame(slug = character(), name = character()))

  store_choices <- list("All" = "")
  if (nrow(stores) > 0) {
    for (i in seq_len(nrow(stores))) {
      nm <- stores$name[i]
      if (is.na(nm) || nm == "" || is.na(stores$slug[i])) next
      store_choices[[nm]] <- stores$slug[i]
    }
  }
  current <- isolate(input$tournaments_store_filter)
  selected <- if (!is.null(current) && current %in% unlist(store_choices)) current else ""
  updateSelectInput(session, "tournaments_store_filter", choices = store_choices, selected = selected)
})

# Debounce search input (300ms)
tournaments_search_debounced <- reactive(input$tournaments_search) |> debounce(300)

# ---------------------------------------------------------------------------
# Shared data reactive — used by both desktop reactable and mobile cards
# ---------------------------------------------------------------------------
tournaments_data <- reactive({
  req("tournaments" %in% visited_tabs())  # Lazy load: skip until tab visited
  rv$refresh_tournaments  # Trigger refresh on admin changes

  filters <- build_mv_filters(
    format = input$tournaments_format,
    event_type = input$tournaments_event_type,
    scene = rv$current_scene,
    continent = rv$current_continent,
    community_store = rv$community_filter,
    search = tournaments_search_debounced(),
    search_column = "store_name",
    start_idx = 1
  )

  # Advanced filters: store (same pattern as players tab)
  store_filter <- input$tournaments_store_filter %||% ""
  if (nchar(store_filter) > 0) {
    store_idx <- filters$next_idx
    filters$sql <- paste0(filters$sql, sprintf(" AND slug = $%d", store_idx))
    filters$params <- c(filters$params, list(store_filter))
    filters$next_idx <- store_idx + 1
  }

  # Advanced filters: date range
  date_from <- input$tournaments_date_from
  if (length(date_from) == 1 && !is.na(date_from)) {
    idx <- filters$next_idx
    filters$sql <- paste0(filters$sql, sprintf(" AND event_date >= $%d", idx))
    filters$params <- c(filters$params, list(as.character(date_from)))
    filters$next_idx <- idx + 1
  }

  date_to <- input$tournaments_date_to
  if (length(date_to) == 1 && !is.na(date_to)) {
    idx <- filters$next_idx
    filters$sql <- paste0(filters$sql, sprintf(" AND event_date <= $%d", idx))
    filters$params <- c(filters$params, list(as.character(date_to)))
    filters$next_idx <- idx + 1
  }

  # Advanced filters: minimum size
  size_min <- as.numeric(input$tournaments_size_filter %||% 0)
  if (length(size_min) == 0 || is.na(size_min)) size_min <- 0
  if (size_min > 0) {
    idx <- filters$next_idx
    filters$sql <- paste0(filters$sql, sprintf(" AND player_count >= $%d", idx))
    filters$params <- c(filters$params, list(as.integer(size_min)))
    filters$next_idx <- idx + 1
  }

  query <- paste0("
    SELECT tournament_id, event_date as \"Date\", store_name as \"Store\",
           country, is_online,
           event_type as \"Type\", format as \"Format\", player_count as \"Players\",
           rounds as \"Rounds\", winner_name as \"Winner\", winning_deck as \"Winning Deck\",
           winning_deck_color, winning_deck_secondary_color
    FROM mv_tournament_list
    WHERE 1=1 ", filters$sql, "
    ORDER BY event_date DESC
  ")

  safe_query(db_pool, query, params = filters$params, default = data.frame())
}) |> bindCache(
  input$tournaments_format,
  input$tournaments_event_type,
  tournaments_search_debounced(),
  input$tournaments_store_filter,
  input$tournaments_date_from,
  input$tournaments_date_to,
  input$tournaments_size_filter,
  rv$current_scene,
  rv$current_continent,
  rv$community_filter,
  rv$refresh_tournaments
)

# ---------------------------------------------------------------------------
# Desktop: Reactable output
# ---------------------------------------------------------------------------
output$tournament_history <- renderReactable({
  result <- tournaments_data()

  if (nrow(result) == 0) {
    has_filters <- nchar(trimws(tournaments_search_debounced() %||% "")) > 0 ||
                   nchar(trimws(input$tournaments_format %||% "")) > 0 ||
                   nchar(trimws(input$tournaments_event_type %||% "")) > 0
    if (has_filters) {
      return(digital_empty_state(
        title = "No tournaments match your filters",
        subtitle = "// try adjusting search or filters",
        icon = "funnel"
      ))
    } else {
      return(digital_empty_state(
        title = "No tournaments recorded",
        subtitle = "// tournament data pending",
        icon = "trophy",
        mascot = "agumon"
      ))
    }
  }

  # Format event type nicely
  result$Type <- sapply(result$Type, format_event_type)

  # Build scene indicator (flag emoji or globe for online)
  result$Scene <- sapply(seq_len(nrow(result)), function(i) {
    if (isTRUE(result$is_online[i])) return("\U0001F310")
    country <- result$country[i]
    if (is.na(country) || country == "") return("")
    # Map common countries to flag emojis
    switch(country,
      "United States" = "\U0001F1FA\U0001F1F8",
      "Canada" = "\U0001F1E8\U0001F1E6",
      "Mexico" = "\U0001F1F2\U0001F1FD",
      "United Kingdom" = "\U0001F1EC\U0001F1E7",
      "Japan" = "\U0001F1EF\U0001F1F5",
      "Australia" = "\U0001F1E6\U0001F1FA",
      "Germany" = "\U0001F1E9\U0001F1EA",
      "France" = "\U0001F1EB\U0001F1F7",
      "Italy" = "\U0001F1EE\U0001F1F9",
      "Spain" = "\U0001F1EA\U0001F1F8",
      "Brazil" = "\U0001F1E7\U0001F1F7",
      "South Korea" = "\U0001F1F0\U0001F1F7",
      "Philippines" = "\U0001F1F5\U0001F1ED",
      "Singapore" = "\U0001F1F8\U0001F1EC",
      "Netherlands" = "\U0001F1F3\U0001F1F1",
      "Belgium" = "\U0001F1E7\U0001F1EA",
      "\U0001F3F3\uFE0F"
    )
  })

  # Create Winning Deck column as HTML (with color badge, dual-color aware)
  result$winning_deck_html <- sapply(seq_len(nrow(result)), function(i) {
    deck <- result$`Winning Deck`[i]
    if (is.na(deck) || deck == "" || deck == "-") return("-")
    primary <- result$winning_deck_color[i]
    secondary <- result$winning_deck_secondary_color[i]
    sec <- if (!is.na(secondary) && secondary != "") secondary else NULL
    as.character(deck_name_badge(deck, primary, sec))
  })

  reactable(
    result,
    compact = TRUE,
    striped = TRUE,
    pagination = TRUE,
    defaultPageSize = 32,
    defaultSorted = list(Date = "desc"),
    rowStyle = list(cursor = "pointer"),
    onClick = JS("function(rowInfo, column) {
      if (rowInfo) {
        Shiny.setInputValue('tournament_clicked', rowInfo.row.tournament_id, {priority: 'event'})
      }
    }"),
    columns = list(
      tournament_id = colDef(show = FALSE),
      country = colDef(show = FALSE),
      is_online = colDef(show = FALSE),
      winning_deck_color = colDef(show = FALSE),
      winning_deck_secondary_color = colDef(show = FALSE),
      Date = colDef(minWidth = 90),
      Scene = colDef(minWidth = 40, align = "center", name = ""),
      Store = colDef(minWidth = 150),
      Type = colDef(minWidth = 90),
      Format = colDef(minWidth = 70),
      Players = colDef(minWidth = 70, align = "center"),
      Rounds = colDef(minWidth = 60, align = "center"),
      Winner = colDef(minWidth = 120),
      `Winning Deck` = colDef(show = FALSE),
      winning_deck_html = colDef(name = "Winning Deck", minWidth = 120, html = TRUE)
    )
  )
})

# ---------------------------------------------------------------------------
# Mobile: Stacked tournament cards with load-more pagination
# ---------------------------------------------------------------------------
mobile_tournaments_limit <- reactiveVal(20)

# Reset limit when filters change
observeEvent(list(
  input$tournaments_format,
  input$tournaments_event_type,
  tournaments_search_debounced()
), {
  mobile_tournaments_limit(20)
}, ignoreInit = TRUE)

# Load more button
observeEvent(input$load_more_mobile_tournaments, {
  mobile_tournaments_limit(mobile_tournaments_limit() + 20)
})

output$mobile_tournaments_cards <- renderUI({
  req(is_mobile())

  result <- tournaments_data()

  if (nrow(result) == 0) {
    has_filters <- nchar(trimws(tournaments_search_debounced() %||% "")) > 0 ||
                   nchar(trimws(input$tournaments_format %||% "")) > 0 ||
                   nchar(trimws(input$tournaments_event_type %||% "")) > 0
    if (has_filters) {
      return(digital_empty_state(
        title = "No tournaments match your filters",
        subtitle = "// try adjusting search or filters",
        icon = "funnel"
      ))
    } else {
      return(digital_empty_state(
        title = "No tournaments recorded",
        subtitle = "// tournament data pending",
        icon = "trophy",
        mascot = "agumon"
      ))
    }
  }

  # Format event type nicely
  result$Type <- sapply(result$Type, format_event_type)

  total_rows <- nrow(result)
  show_n <- min(mobile_tournaments_limit(), total_rows)
  result <- result[seq_len(show_n), , drop = FALSE]

  cards <- lapply(seq_len(nrow(result)), function(i) {
    row <- result[i, ]

    # Format date for display
    date_display <- format(as.Date(row$Date), "%b %d, %Y")

    # Format badge
    format_display <- if (!is.na(row$Format) && nchar(row$Format) > 0) row$Format else NULL

    # Winner display
    winner_tag <- if (!is.na(row$Winner) && nchar(row$Winner) > 0) {
      span(class = "mobile-card-meta-stats",
        bsicons::bs_icon("trophy-fill", class = "mobile-tournament-trophy"),
        row$Winner)
    }

    # Players display
    players_display <- if (!is.na(row$Players)) sprintf("%d players", row$Players) else NULL

    div(
      class = "mobile-list-card",
      onclick = sprintf(
        "Shiny.setInputValue('tournament_clicked', %d, {priority: 'event'})",
        row$tournament_id
      ),
      # Row 1: Store name + Format badge
      div(class = "mobile-card-row",
        span(class = "mobile-card-primary", row$Store),
        if (!is.null(format_display)) {
          span(class = "mobile-card-format-badge", format_display)
        }
      ),
      # Row 2: Date · Type (left) | Players · Winner (right)
      div(class = "mobile-card-row",
        span(class = "mobile-card-meta-stats",
          date_display,
          span(class = "mobile-card-separator", "\u00b7"),
          row$Type),
        if (!is.null(winner_tag)) {
          winner_tag
        } else if (!is.null(players_display)) {
          span(class = "mobile-card-meta-stats", players_display)
        }
      )
    )
  })

  # Build card list with optional load-more button
  card_list <- div(class = "mobile-card-list", cards)

  if (show_n < total_rows) {
    remaining <- total_rows - show_n
    tagList(
      card_list,
      tags$button(
        class = "mobile-load-more",
        onclick = "Shiny.setInputValue('load_more_mobile_tournaments', Math.random(), {priority: 'event'})",
        span(class = "mobile-load-more-label", "LOAD MORE"),
        span(class = "mobile-load-more-count", sprintf("%d remaining", remaining))
      )
    )
  } else {
    card_list
  }
})

# Handle tournament row click - open detail modal
observeEvent(input$tournament_clicked, {
  rv$selected_tournament_id <- input$tournament_clicked
})

# Handle Overview tournament click - open modal on overview
observeEvent(input$overview_tournament_clicked, {
  rv$selected_tournament_id <- input$overview_tournament_clicked
})

# Render tournament detail modal
output$tournament_detail_modal <- renderUI({
  req(rv$selected_tournament_id)

  tournament_id <- rv$selected_tournament_id


  # Get tournament info (include store_id for clickable link)
  tournament <- safe_query(db_pool, "
    SELECT t.event_date, t.event_type, t.format, t.player_count, t.rounds,
           s.store_id, s.name as store_name
    FROM tournaments t
    JOIN stores s ON t.store_id = s.store_id
    WHERE t.tournament_id = $1
  ", params = list(tournament_id), default = data.frame())

  if (nrow(tournament) == 0) return(NULL)

  # Get all results for this tournament
  results <- safe_query(db_pool, "
    SELECT r.placement as \"Place\",
           CASE WHEN p.is_anonymized THEN 'Anonymous' ELSE p.display_name END as \"Player\",
           da.archetype_name as \"Deck\",
           da.primary_color as color, da.secondary_color, r.wins as \"W\", r.losses as \"L\", r.ties as \"T\", r.decklist_url,
           p.is_anonymized
    FROM results r
    JOIN players p ON r.player_id = p.player_id
    JOIN deck_archetypes da ON r.archetype_id = da.archetype_id
    WHERE r.tournament_id = $1
    ORDER BY r.placement ASC
  ", params = list(tournament_id), default = data.frame())

  # Format event type
  event_type_display <- format_event_type(tournament$event_type)

  # Update URL for deep linking
  update_url_for_tournament(session, tournament_id)

  # Build modal
  showModal(modalDialog(
    title = div(
      class = "d-flex align-items-center gap-2",
      bsicons::bs_icon("trophy"),
      span(tournament$store_name),
      span(class = "text-muted", "-"),
      span(format(as.Date(tournament$event_date), "%B %d, %Y"))
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
      actionButton("report_error_tournament", tagList(bsicons::bs_icon("flag"), " Report Error"),
                   class = "btn btn-outline-warning"),
      modalButton("Close")
    ),

    # Tournament info
    div(
      class = "modal-stats-box d-flex justify-content-evenly mb-3 p-3 flex-wrap",
      div(
        class = "modal-stat-item",
        div(class = "modal-stat-value", event_type_display),
        div(class = "modal-stat-label", "Event Type")
      ),
      div(
        class = "modal-stat-item",
        div(class = "modal-stat-value", if (!is.na(tournament$format)) tournament$format else "-"),
        div(class = "modal-stat-label", "Format")
      ),
      div(
        class = "modal-stat-item",
        div(class = "modal-stat-value stat-highlight", tournament$player_count),
        div(class = "modal-stat-label", "Players")
      ),
      div(
        class = "modal-stat-item",
        div(class = "modal-stat-value", if (!is.na(tournament$rounds)) tournament$rounds else "-"),
        div(class = "modal-stat-label", "Rounds")
      )
    ),

    # Full standings
    if (nrow(results) > 0) {
      display_results <- data.frame(
        Place = vapply(results$Place, function(p) {
          cls <- if (p == 1) "place-1st" else if (p == 2) "place-2nd" else if (p == 3) "place-3rd" else ""
          as.character(tags$span(class = cls, ordinal(p)))
        }, character(1)),
        Player = results$Player,
        Deck = vapply(seq_len(nrow(results)), function(i) {
          as.character(deck_name_badge(results$Deck[i], results$color[i], results$secondary_color[i]))
        }, character(1)),
        Record = sprintf("%d-%d%s", results$W, results$L,
          ifelse(results$T > 0, sprintf("-%d", results$T), "")),
        Decklist = unname(vapply(results$decklist_url, function(u) {
          tag <- decklist_link_icon(u)
          if (!is.null(tag)) as.character(tag) else ""
        }, character(1))),
        stringsAsFactors = FALSE,
        row.names = NULL
      )

      tagList(
        h6(class = "modal-section-header", "Final Standings"),
        reactable(
          display_results,
          compact = TRUE,
          striped = TRUE,
          pagination = TRUE,
          defaultPageSize = 10,
          columns = list(
            Place = colDef(minWidth = 55, align = "center", html = TRUE),
            Player = colDef(minWidth = 120),
            Deck = colDef(minWidth = 120, html = TRUE),
            Record = colDef(minWidth = 60, align = "center"),
            Decklist = colDef(name = "", minWidth = 40, html = TRUE)
          )
        )
      )
    } else {
      digital_empty_state("No results recorded", "// tournament data pending", "list-ul", mascot = "agumon")
    }
  ))
})
outputOptions(output, "tournament_detail_modal", suspendWhenHidden = FALSE)
