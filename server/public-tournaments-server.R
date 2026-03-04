# =============================================================================
# Public: Tournaments Tab Server Logic
# =============================================================================
# Note: Contains overview_tournament_clicked handler which is triggered from
# the Dashboard tab to open tournament details from "Recent Tournaments" table.

# ---------------------------------------------------------------------------
# Page Rendering (desktop vs mobile)
# ---------------------------------------------------------------------------
output$tournaments_page <- renderUI({
  if (is_mobile()) {
    source("views/mobile-tournaments-ui.R", local = TRUE)$value
  } else {
    tournaments_ui
  }
})

# Reset tournaments filters
observeEvent(input$reset_tournaments_filters, {
  updateTextInput(session, "tournaments_search", value = "")
  updateSelectInput(session, "tournaments_format", selected = "")
  updateSelectInput(session, "tournaments_event_type", selected = "")
})

# Debounce search input (300ms)
tournaments_search_debounced <- reactive(input$tournaments_search) |> debounce(300)

# ---------------------------------------------------------------------------
# Shared data reactive — used by both desktop reactable and mobile cards
# ---------------------------------------------------------------------------
tournaments_data <- reactive({
  rv$data_refresh  # Trigger refresh on admin changes

  # Build parameterized filters to prevent SQL injection
  search_filters <- build_filters_param(
    table_alias = "s",
    search = tournaments_search_debounced(),
    search_column = "name",
    start_idx = 1
  )

  format_filters <- build_filters_param(
    table_alias = "t",
    format = input$tournaments_format,
    scene = rv$current_scene,
    store_alias = "s",
    community_store = rv$community_filter,
    start_idx = search_filters$next_idx
  )

  event_type_filters <- build_filters_param(
    table_alias = "t",
    event_type = input$tournaments_event_type,
    start_idx = format_filters$next_idx
  )

  # Combine filter SQL and params
  filter_sql <- paste(search_filters$sql, format_filters$sql, event_type_filters$sql)
  filter_params <- c(search_filters$params, format_filters$params, event_type_filters$params)

  query <- paste0("
    SELECT t.tournament_id, t.event_date as \"Date\", s.name as \"Store\", t.event_type as \"Type\",
           t.format as \"Format\", t.player_count as \"Players\", t.rounds as \"Rounds\",
           p.display_name as \"Winner\", da.archetype_name as \"Winning Deck\"
    FROM tournaments t
    JOIN stores s ON t.store_id = s.store_id
    LEFT JOIN LATERAL (
      SELECT r2.player_id, r2.archetype_id
      FROM results r2
      WHERE r2.tournament_id = t.tournament_id AND r2.placement = 1
      ORDER BY r2.result_id
      LIMIT 1
    ) r ON true
    LEFT JOIN players p ON r.player_id = p.player_id
    LEFT JOIN deck_archetypes da ON r.archetype_id = da.archetype_id
    WHERE 1=1 ", filter_sql, "
    ORDER BY t.event_date DESC
  ")

  safe_query(db_pool, query, params = filter_params, default = data.frame())
}) |> bindCache(
  input$tournaments_format,
  input$tournaments_event_type,
  tournaments_search_debounced(),
  rv$current_scene,
  rv$community_filter,
  rv$data_refresh
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
      Date = colDef(minWidth = 90),
      Store = colDef(minWidth = 150),
      Type = colDef(minWidth = 90),
      Format = colDef(minWidth = 70),
      Players = colDef(minWidth = 70, align = "center"),
      Rounds = colDef(minWidth = 60, align = "center"),
      Winner = colDef(minWidth = 120),
      `Winning Deck` = colDef(minWidth = 120)
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

    # Build the secondary line: players + winner
    detail_parts <- c()
    if (!is.na(row$Players)) {
      detail_parts <- c(detail_parts, paste0(row$Players, " players"))
    }
    if (!is.na(row$Winner) && nchar(row$Winner) > 0) {
      detail_parts <- c(detail_parts, paste0("Winner: ", row$Winner))
    }
    detail_line <- paste(detail_parts, collapse = " \u00b7 ")

    div(
      class = "mobile-list-card",
      onclick = sprintf(
        "Shiny.setInputValue('tournament_clicked', %d, {priority: 'event'})",
        row$tournament_id
      ),
      div(class = "mobile-card-row",
        div(class = "mobile-card-tertiary", date_display),
        div(class = "mobile-card-tertiary", row$Type)
      ),
      div(class = "mobile-card-primary", row$Store),
      div(class = "mobile-card-secondary", detail_line)
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
        sprintf("Show more (%d remaining)", remaining)
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
    SELECT r.placement as \"Place\", p.display_name as \"Player\", da.archetype_name as \"Deck\",
           da.primary_color as color, r.wins as \"W\", r.losses as \"L\", r.ties as \"T\", r.decklist_url
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
      tagList(
        h6(class = "modal-section-header", "Final Standings"),
        tags$table(
          class = "table table-sm table-striped",
          tags$thead(
            tags$tr(
              tags$th("Place"), tags$th("Player"), tags$th("Deck"),
              tags$th("Record"), tags$th("")
            )
          ),
          tags$tbody(
            lapply(1:nrow(results), function(i) {
              row <- results[i, ]
              tags$tr(
                tags$td(
                  class = if (row$Place == 1) "place-1st" else if (row$Place == 2) "place-2nd" else if (row$Place == 3) "place-3rd" else "",
                  ordinal(row$Place)
                ),
                tags$td(row$Player),
                tags$td(
                  span(class = paste("deck-badge", paste0("deck-badge-", tolower(row$color))), row$Deck)
                ),
                tags$td(sprintf("%d-%d%s", row$W, row$L, if (row$T > 0) sprintf("-%d", row$T) else "")),
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
      digital_empty_state("No results recorded", "// tournament data pending", "list-ul", mascot = "agumon")
    }
  ))
})
outputOptions(output, "tournament_detail_modal", suspendWhenHidden = FALSE)
