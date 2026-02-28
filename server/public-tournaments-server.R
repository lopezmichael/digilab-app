# =============================================================================
# Public: Tournaments Tab Server Logic
# =============================================================================
# Note: Contains overview_tournament_clicked handler which is triggered from
# the Dashboard tab to open tournament details from "Recent Tournaments" table.

# Reset tournaments filters
observeEvent(input$reset_tournaments_filters, {
  updateTextInput(session, "tournaments_search", value = "")
  updateSelectInput(session, "tournaments_format", selected = "")
  updateSelectInput(session, "tournaments_event_type", selected = "")
})

# Debounce search input (300ms)
tournaments_search_debounced <- reactive(input$tournaments_search) |> debounce(300)

output$tournament_history <- renderReactable({
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
    LEFT JOIN results r ON t.tournament_id = r.tournament_id AND r.placement = 1
    LEFT JOIN players p ON r.player_id = p.player_id
    LEFT JOIN deck_archetypes da ON r.archetype_id = da.archetype_id
    WHERE 1=1 ", filter_sql, "
    ORDER BY t.event_date DESC
  ")

  result <- safe_query(db_pool, query, params = filter_params, default = data.frame())

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
}) |> bindCache(
  input$tournaments_format,
  input$tournaments_event_type,
  tournaments_search_debounced(),
  rv$current_scene,
  rv$community_filter,
  rv$data_refresh
)

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
      tags$a(
        href = LINKS$discord, target = "_blank",
        class = "btn btn-outline-secondary",
        bsicons::bs_icon("flag"), " Report Error"
      ),
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
