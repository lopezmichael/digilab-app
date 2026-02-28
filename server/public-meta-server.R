# =============================================================================
# Public: Meta Analysis Server Logic
# =============================================================================

# Reset meta filters
observeEvent(input$reset_meta_filters, {
  updateTextInput(session, "meta_search", value = "")
  updateSelectInput(session, "meta_format", selected = "")
  # Reset pill toggle to dynamic default based on current scope
  tournament_count <- count_tournaments_for_scope(db_pool, rv$current_scene, rv$community_filter)
  default_min <- get_default_min_events(tournament_count)
  session$sendCustomMessage("resetPillToggle", list(inputId = "meta_min_entries", value = default_min))
})

# Debounce search input (300ms)
meta_search_debounced <- reactive(input$meta_search) |> debounce(300)

# Archetype stats
output$archetype_stats <- renderReactable({
  rv$data_refresh  # Trigger refresh on admin changes


  # Build parameterized filters to prevent SQL injection
  search_filters <- build_filters_param(
    table_alias = "da",
    search = meta_search_debounced(),
    search_column = "archetype_name",
    start_idx = 1
  )

  format_filters <- build_filters_param(
    table_alias = "t",
    format = input$meta_format,
    scene = rv$current_scene,
    store_alias = "s",
    community_store = rv$community_filter,
    start_idx = search_filters$next_idx
  )

  min_entries <- as.numeric(input$meta_min_entries)
  if (is.na(min_entries)) min_entries <- 0

  # HAVING clause parameter is numbered after all filter params
  having_idx <- format_filters$next_idx

  # Combine filter SQL and params
  combined_sql <- paste(search_filters$sql, format_filters$sql)
  combined_params <- c(search_filters$params, format_filters$params, list(as.integer(min_entries)))

  # Exclude UNKNOWN archetype from analytics
  result <- safe_query(db_pool, sprintf("
    SELECT da.archetype_id, da.archetype_name as \"Deck\", da.primary_color as \"Color\",
           COUNT(r.result_id) as \"Entries\",
           COUNT(CASE WHEN r.placement = 1 THEN 1 END) as \"1sts\",
           COUNT(CASE WHEN r.placement <= 3 THEN 1 END) as \"Top 3s\",
           ROUND(SUM(r.wins) * 100.0 / NULLIF(SUM(r.wins) + SUM(r.losses), 0), 1) as \"Win %%\"
    FROM deck_archetypes da
    JOIN results r ON da.archetype_id = r.archetype_id
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    JOIN stores s ON t.store_id = s.store_id
    WHERE 1=1 AND da.archetype_name != 'UNKNOWN' %s
    GROUP BY da.archetype_id, da.archetype_name, da.primary_color
    HAVING COUNT(r.result_id) >= $%d
    ORDER BY COUNT(r.result_id) DESC, COUNT(CASE WHEN r.placement = 1 THEN 1 END) DESC
  ", combined_sql, having_idx), params = combined_params, default = data.frame())

  if (nrow(result) == 0) {
    has_filters <- nchar(trimws(meta_search_debounced() %||% "")) > 0 ||
                   nchar(trimws(input$meta_format %||% "")) > 0
    if (has_filters) {
      return(digital_empty_state(
        title = "No decks match your filters",
        subtitle = "// try adjusting search or format",
        icon = "funnel"
      ))
    } else {
      return(digital_empty_state(
        title = "No deck data available",
        subtitle = "// meta data pending",
        icon = "stack",
        mascot = "agumon"
      ))
    }
  }

  # Calculate Meta % (share of total entries)
  total_entries <- sum(result$Entries)
  result$`Meta %` <- round(result$Entries * 100 / total_entries, 1)

  # Calculate Conv % (conversion rate: Top 3s / Entries)
  result$`Conv %` <- round(result$`Top 3s` * 100 / result$Entries, 1)

  reactable(
    result,
    compact = TRUE,
    striped = TRUE,
    pagination = TRUE,
    defaultPageSize = 32,
    rowStyle = list(cursor = "pointer"),
    onClick = JS("function(rowInfo, column) {
      if (rowInfo) {
        Shiny.setInputValue('archetype_clicked', rowInfo.row.archetype_id, {priority: 'event'})
      }
    }"),
    columns = list(
      archetype_id = colDef(show = FALSE),
      Deck = colDef(minWidth = 150),
      Color = colDef(minWidth = 80, cell = function(value) deck_color_badge(value)),
      Entries = colDef(minWidth = 70, align = "center"),
      `Meta %` = colDef(minWidth = 70, align = "center"),
      `1sts` = colDef(minWidth = 50, align = "center"),
      `Top 3s` = colDef(minWidth = 60, align = "center"),
      `Conv %` = colDef(minWidth = 70, align = "center"),
      `Win %` = colDef(minWidth = 60, align = "center")
    )
  )
}) |> bindCache(
  input$meta_format,
  meta_search_debounced(),
  input$meta_min_entries,
  rv$current_scene,
  rv$community_filter,
  rv$data_refresh
)

# Handle archetype row click - open detail modal
observeEvent(input$archetype_clicked, {
  rv$selected_archetype_id <- input$archetype_clicked
})

# Render deck detail modal
output$deck_detail_modal <- renderUI({
  req(rv$selected_archetype_id)

  archetype_id <- rv$selected_archetype_id


  # Get archetype info
  archetype <- safe_query(db_pool, "
    SELECT archetype_name, primary_color, secondary_color, display_card_id, slug
    FROM deck_archetypes
    WHERE archetype_id = $1
  ", params = list(archetype_id), default = data.frame())

  if (nrow(archetype) == 0) return(NULL)

  # Build scene filter for modal queries (includes community filter)
  # start_idx = 2 because $1 is used for archetype_id in each query
  scene_filters <- build_filters_param(
    table_alias = "t",
    scene = rv$current_scene,
    store_alias = "s",
    community_store = rv$community_filter,
    start_idx = 2
  )

  # Get overall stats with meta share and conversion rate
  stats <- safe_query(db_pool, sprintf("
    WITH deck_stats AS (
      SELECT COUNT(r.result_id) as entries,
             COUNT(DISTINCT r.tournament_id) as tournaments,
             COUNT(DISTINCT r.player_id) as pilots,
             ROUND(AVG(r.placement), 1) as avg_place,
             COUNT(CASE WHEN r.placement = 1 THEN 1 END) as first_places,
             COUNT(CASE WHEN r.placement <= 3 THEN 1 END) as top3,
             ROUND(SUM(r.wins) * 100.0 / NULLIF(SUM(r.wins) + SUM(r.losses), 0), 1) as win_pct
      FROM results r
      JOIN tournaments t ON r.tournament_id = t.tournament_id
      JOIN stores s ON t.store_id = s.store_id
      WHERE r.archetype_id = $1 %s
    ),
    total_entries AS (
      SELECT COUNT(*) as total
      FROM results r
      JOIN tournaments t ON r.tournament_id = t.tournament_id
      JOIN stores s ON t.store_id = s.store_id
      WHERE 1=1 %s
    )
    SELECT ds.*,
           ROUND(ds.entries * 100.0 / NULLIF(te.total, 0), 1) as meta_pct,
           ROUND(ds.top3 * 100.0 / NULLIF(ds.entries, 0), 1) as conv_pct
    FROM deck_stats ds, total_entries te
  ", scene_filters$sql, scene_filters$sql),
  params = c(list(archetype_id), scene_filters$params),
  default = data.frame())

  # Get top pilots (include player_id for clickable links)
  top_pilots <- safe_query(db_pool, sprintf("
    SELECT p.player_id,
           p.display_name as \"Player\",
           COUNT(*) as \"Times\",
           COUNT(CASE WHEN r.placement = 1 THEN 1 END) as \"Wins\",
           ROUND(SUM(r.wins) * 100.0 / NULLIF(SUM(r.wins) + SUM(r.losses), 0), 1) as \"Win %%\"
    FROM results r
    JOIN players p ON r.player_id = p.player_id
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    JOIN stores s ON t.store_id = s.store_id
    WHERE r.archetype_id = $1 %s
    GROUP BY p.player_id, p.display_name
    ORDER BY COUNT(CASE WHEN r.placement = 1 THEN 1 END) DESC, COUNT(*) DESC
    LIMIT 5
  ", scene_filters$sql), params = c(list(archetype_id), scene_filters$params), default = data.frame())

  # Get recent results with this deck
  recent_results <- safe_query(db_pool, sprintf("
    SELECT t.event_date as \"Date\", s.name as \"Store\", p.display_name as \"Player\",
           r.placement as \"Place\", r.wins as \"W\", r.losses as \"L\", r.decklist_url
    FROM results r
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    JOIN stores s ON t.store_id = s.store_id
    JOIN players p ON r.player_id = p.player_id
    WHERE r.archetype_id = $1 %s
    ORDER BY t.event_date DESC, r.placement ASC
    LIMIT 10
  ", scene_filters$sql), params = c(list(archetype_id), scene_filters$params), default = data.frame())

  # Card image URL
  card_img_url <- if (!is.na(archetype$display_card_id) && archetype$display_card_id != "") {
    sprintf("https://images.digimoncard.io/images/cards/%s.jpg", archetype$display_card_id)
  } else NULL

  # Color badge
  color_class <- paste0("deck-badge-", tolower(archetype$primary_color))

  # Update URL for deep linking
  deck_slug <- if (!is.null(archetype$slug) && !is.na(archetype$slug) && archetype$slug != "") {
    archetype$slug
  } else {
    slugify(archetype$archetype_name)  # Fallback to generating from name
  }
  update_url_for_deck(session, archetype_id, deck_slug)

  # Build modal
  showModal(modalDialog(
    title = div(
      class = "d-flex align-items-center gap-2",
      span(class = paste("deck-badge", color_class), archetype$archetype_name)
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
      actionButton("report_error_deck", tagList(bsicons::bs_icon("flag"), " Report Error"),
                   class = "btn btn-outline-warning"),
      modalButton("Close")
    ),

    # Card image and stats side by side
    div(
      class = "d-flex gap-3 mb-3",

      # Card image
      if (!is.null(card_img_url)) {
        div(
          class = "flex-shrink-0",
          tags$img(
            src = card_img_url,
            class = "rounded shadow deck-modal-image",
            alt = archetype$archetype_name
          )
        )
      },

      # Stats
      div(
        class = "flex-grow-1",
        div(
          class = "modal-stats-box d-flex justify-content-evenly flex-wrap p-3 h-100 align-items-center",
          div(
            class = "modal-stat-item",
            div(class = "modal-stat-value", if (!is.na(stats$meta_pct)) paste0(stats$meta_pct, "%") else "-"),
            div(class = "modal-stat-label", "Meta %")
          ),
          div(
            class = "modal-stat-item",
            div(class = "modal-stat-value", stats$pilots),
            div(class = "modal-stat-label", "Pilots")
          ),
          div(
            class = "modal-stat-item",
            div(class = "modal-stat-value stat-highlight place-1st", stats$first_places),
            div(class = "modal-stat-label", "1sts")
          ),
          div(
            class = "modal-stat-item",
            div(class = "modal-stat-value", if (!is.na(stats$conv_pct)) paste0(stats$conv_pct, "%") else "-"),
            div(class = "modal-stat-label", "Conv %")
          ),
          div(
            class = "modal-stat-item",
            div(class = "modal-stat-value", if (!is.na(stats$win_pct)) paste0(stats$win_pct, "%") else "-"),
            div(class = "modal-stat-label", "Win Rate")
          ),
          div(
            class = "modal-stat-item",
            div(class = "modal-stat-value", if (!is.na(stats$avg_place)) stats$avg_place else "-"),
            div(class = "modal-stat-label", "Avg Place")
          )
        )
      )
    ),

    # Top pilots (clickable to open player modal)
    if (nrow(top_pilots) > 0) {
      tagList(
        h6(class = "modal-section-header", "Top Pilots"),
        tags$table(
          class = "table table-sm table-striped",
          tags$thead(
            tags$tr(
              tags$th("Player"), tags$th("Times Played"), tags$th("Wins"), tags$th("Win %")
            )
          ),
          tags$tbody(
            lapply(1:nrow(top_pilots), function(i) {
              row <- top_pilots[i, ]
              tags$tr(
                tags$td(
                  tags$a(
                    href = "#",
                    class = "text-primary text-decoration-none clickable-row",
                    onclick = sprintf("Shiny.setInputValue('modal_player_clicked', %d, {priority: 'event'}); return false;", row$player_id),
                    row$Player
                  )
                ),
                tags$td(class = "text-center", row$Times),
                tags$td(class = "text-center", row$Wins),
                tags$td(class = "text-center", if (!is.na(row$`Win %`)) paste0(row$`Win %`, "%") else "-")
              )
            })
          )
        )
      )
    },

    # Recent results
    if (nrow(recent_results) > 0) {
      tagList(
        h6(class = "modal-section-header mt-3", "Recent Results"),
        tags$table(
          class = "table table-sm table-striped",
          tags$thead(
            tags$tr(
              tags$th("Date"), tags$th("Store"), tags$th("Player"),
              tags$th("Place"), tags$th("Record"), tags$th("")
            )
          ),
          tags$tbody(
            lapply(1:nrow(recent_results), function(i) {
              row <- recent_results[i, ]
              tags$tr(
                tags$td(format(as.Date(row$Date), "%b %d")),
                tags$td(row$Store),
                tags$td(row$Player),
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
      digital_empty_state("No tournament history", "// player data pending", "person-x", mascot = "agumon")
    }
  ))
})
outputOptions(output, "deck_detail_modal", suspendWhenHidden = FALSE)
