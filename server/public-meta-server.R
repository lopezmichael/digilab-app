# =============================================================================
# Public: Meta Analysis Server Logic
# =============================================================================

# ---------------------------------------------------------------------------
# Page Rendering (desktop vs mobile)
# ---------------------------------------------------------------------------
output$meta_page <- renderUI({
  format_choices_with_all <- get_format_choices_with_all(db_pool)
  if (is_mobile()) {
    source("views/mobile-meta-ui.R", local = TRUE)$value
  } else {
    source("views/meta-ui.R", local = TRUE)$value
  }
})

# Reset meta filters
observeEvent(input$reset_meta_filters, {
  updateTextInput(session, "meta_search", value = "")
  updateSelectInput(session, "meta_format", selected = "")
  session$sendCustomMessage("resetPillToggle", list(inputId = "meta_min_entries", value = "0"))
  updateCheckboxInput(session, "meta_top3_toggle", value = FALSE)
  updateCheckboxInput(session, "meta_decklist_toggle", value = FALSE)
  session$sendCustomMessage("clearColorPills", TRUE)
  updateSelectInput(session, "meta_conversion_filter", selected = "0")
})

# Debounce search input (300ms)
meta_search_debounced <- reactive(input$meta_search) |> debounce(300)

# ---------------------------------------------------------------------------
# Shared data reactive for archetype stats (used by desktop + mobile)
# ---------------------------------------------------------------------------
meta_archetype_data <- reactive({
  req("meta" %in% visited_tabs())  # Lazy load: skip until tab visited
  rv$refresh_decks; rv$refresh_tournaments  # Trigger refresh on admin changes

  filters <- build_mv_filters(
    format = input$meta_format,
    scene = rv$current_scene,
    continent = rv$current_continent,
    community_store = rv$community_filter,
    search = meta_search_debounced(),
    search_column = "archetype_name",
    start_idx = 1
  )

  min_entries <- as.numeric(input$meta_min_entries %||% 0)
  if (length(min_entries) == 0 || is.na(min_entries)) min_entries <- 0

  having_idx <- filters$next_idx

  result <- safe_query(db_pool, sprintf("
    SELECT archetype_id, archetype_name as \"Deck\", primary_color as \"Color\", secondary_color,
           SUM(entries)::int as \"Entries\",
           SUM(firsts)::int as \"1sts\",
           SUM(top3s)::int as \"Top 3s\",
           ROUND(SUM(total_wins) * 100.0 / NULLIF(SUM(total_wins) + SUM(total_losses), 0), 1) as \"Win %%\"
    FROM mv_archetype_store_stats
    WHERE 1=1 %s
    GROUP BY archetype_id, archetype_name, primary_color, secondary_color
    HAVING SUM(entries) >= $%d
    ORDER BY SUM(entries) DESC, SUM(firsts) DESC
  ", filters$sql, having_idx),
  params = c(filters$params, list(as.integer(min_entries))),
  default = data.frame())

  if (nrow(result) == 0) return(result)

  # Calculate Meta % (share of total entries)
  total_entries <- sum(result$Entries)
  result$`Meta %` <- round(result$Entries * 100 / total_entries, 1)

  # Calculate Conv % (conversion rate: Top 3s / Entries)
  result$`Conv %` <- round(result$`Top 3s` * 100 / result$Entries, 1)

  # Advanced filters: top 3 only
  if (isTRUE(input$meta_top3_toggle) && nrow(result) > 0) {
    result <- result[result$`Top 3s` > 0, ]
  }

  # Advanced filters: has decklist (scoped to current scene/format)
  if (isTRUE(input$meta_decklist_toggle) && nrow(result) > 0) {
    dl_filters <- build_filters_param(
      table_alias = "t",
      format = input$meta_format,
      scene = rv$current_scene,
      continent = rv$current_continent,
      community_store = rv$community_filter,
      store_alias = "s",
      start_idx = 1
    )
    decklist_arch_ids <- safe_query(db_pool, sprintf(
      "SELECT DISTINCT r.archetype_id FROM results r
       JOIN tournaments t ON r.tournament_id = t.tournament_id
       JOIN stores s ON t.store_id = s.store_id
       WHERE r.decklist_url IS NOT NULL AND r.decklist_url != '' %s",
      dl_filters$sql),
      params = dl_filters$params,
      default = data.frame(archetype_id = integer()))
    result <- result[result$archetype_id %in% decklist_arch_ids$archetype_id, ]
  }

  # Advanced filters: conversion rate minimum
  conv_min <- as.numeric(input$meta_conversion_filter %||% 0)
  if (length(conv_min) == 0 || is.na(conv_min)) conv_min <- 0
  if (conv_min > 0 && nrow(result) > 0) {
    result <- result[!is.na(result$`Conv %`) & result$`Conv %` >= conv_min, ]
  }

  # Advanced filters: color (client-side, any match on primary or secondary)
  color_filter <- input$meta_color_pills
  if (!is.null(color_filter) && length(color_filter) > 0 && any(nchar(color_filter) > 0)) {
    match_primary <- result$Color %in% color_filter
    match_secondary <- !is.na(result$secondary_color) & result$secondary_color %in% color_filter
    result <- result[match_primary | match_secondary, ]
  }

  result
}) |> bindCache(
  input$meta_format,
  meta_search_debounced(),
  input$meta_min_entries,
  input$meta_color_pills,
  input$meta_top3_toggle,
  input$meta_decklist_toggle,
  input$meta_conversion_filter,
  rv$current_scene,
  rv$current_continent,
  rv$community_filter,
  rv$refresh_decks, rv$refresh_tournaments
)

# ---------------------------------------------------------------------------
# Desktop: Archetype stats reactable
# ---------------------------------------------------------------------------
output$archetype_stats <- renderReactable({
  result <- meta_archetype_data()

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
      secondary_color = colDef(show = FALSE),
      Deck = colDef(minWidth = 150),
      Color = colDef(minWidth = 80, cell = function(value, index) {
        secondary <- result$secondary_color[index]
        deck_color_badge_dual(value, secondary)
      }),
      Entries = colDef(minWidth = 70, align = "center"),
      `Meta %` = colDef(minWidth = 70, align = "center"),
      `1sts` = colDef(minWidth = 50, align = "center"),
      `Top 3s` = colDef(minWidth = 60, align = "center"),
      `Conv %` = colDef(minWidth = 70, align = "center"),
      `Win %` = colDef(minWidth = 60, align = "center")
    )
  )
})

# ---------------------------------------------------------------------------
# Mobile: Archetype deck cards with load-more pagination
# ---------------------------------------------------------------------------
mobile_meta_limit <- reactiveVal(20)

# Reset limit when filters change
observeEvent(list(input$meta_format, meta_search_debounced(), input$meta_min_entries), {
  mobile_meta_limit(20)
}, ignoreInit = TRUE)

# Load more button handler
observeEvent(input$mobile_meta_load_more, {
  mobile_meta_limit(mobile_meta_limit() + 20)
})

output$mobile_meta_cards <- renderUI({
  req(is_mobile())

  result <- meta_archetype_data()

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

  n <- min(mobile_meta_limit(), nrow(result))
  show_data <- result[1:n, ]

  cards <- lapply(seq_len(nrow(show_data)), function(i) {
    row <- show_data[i, ]

    # Deck color for left border and badge tint
    color_hex <- digimon_deck_colors[row$Color]
    if (is.na(color_hex)) color_hex <- "#9CA3AF"

    # Dual-color gradient border or single color
    secondary_hex <- NULL
    if (!is.na(row$secondary_color) && row$secondary_color != "") {
      secondary_hex <- digimon_deck_colors[row$secondary_color]
      if (is.na(secondary_hex)) secondary_hex <- NULL
    }
    border_style <- if (!is.null(secondary_hex)) {
      sprintf("border-left: 3px solid; border-image: linear-gradient(%s, %s) 1;", color_hex, secondary_hex)
    } else {
      paste0("border-left-color: ", color_hex, ";")
    }

    # Meta % badge with deck-color tint
    meta_pct <- sprintf("%.1f%%", row$`Meta %`)
    # Convert hex to rgba for translucent badge background
    rgb <- col2rgb(color_hex)
    badge_bg <- sprintf("background: rgba(%d, %d, %d, 0.12);", rgb[1], rgb[2], rgb[3])
    badge_color <- paste0("color: ", color_hex, ";")
    badge_style <- paste0(badge_bg, badge_color)

    # Win % display
    win_pct <- if (!is.na(row$`Win %`)) paste0(row$`Win %`, "%") else "-"

    # Top 3s display
    tops_label <- if (row$`Top 3s` == 1) "top" else "tops"

    div(
      class = "mobile-list-card meta-deck-card",
      style = border_style,
      onclick = sprintf(
        "Shiny.setInputValue('archetype_clicked', %d, {priority: 'event'})",
        row$archetype_id
      ),
      # Row 1: Deck name + Meta % badge
      div(class = "mobile-card-row",
        span(class = "mobile-card-primary", row$Deck),
        span(class = "mobile-card-meta-badge",
             style = badge_style,
             meta_pct)
      ),
      # Row 2: Entries (left) | Win% · Top 3s (right)
      div(class = "mobile-card-row",
        span(class = "mobile-card-meta-stats",
          sprintf("%d entries", row$Entries)),
        span(class = "mobile-card-meta-stats",
          sprintf("%s win \u00b7 %d %s", win_pct, row$`Top 3s`, tops_label))
      )
    )
  })

  tagList(
    div(class = "mobile-card-list", cards),
    if (n < nrow(result)) {
      remaining <- nrow(result) - n
      tags$button(
        class = "mobile-load-more",
        onclick = "Shiny.setInputValue('mobile_meta_load_more', Math.random(), {priority: 'event'})",
        span(class = "mobile-load-more-label", "LOAD MORE"),
        span(class = "mobile-load-more-count", sprintf("%d remaining", remaining))
      )
    }
  )
})

# Handle archetype row click - open detail modal
observeEvent(input$archetype_clicked, {
  rv$selected_archetype_id <- input$archetype_clicked
})

# Render deck detail modal
output$deck_detail_modal <- renderUI({
  req(rv$selected_archetype_id)

  # React to advanced filter changes so modal updates
  input$meta_top3_toggle
  input$meta_decklist_toggle

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
    continent = rv$current_continent,
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
    WHERE r.archetype_id = $1 AND p.is_anonymized IS NOT TRUE %s
    GROUP BY p.player_id, p.display_name
    ORDER BY COUNT(CASE WHEN r.placement = 1 THEN 1 END) DESC, COUNT(*) DESC
    LIMIT 5
  ", scene_filters$sql), params = c(list(archetype_id), scene_filters$params), default = data.frame())

  # Get recent results with this deck
  recent_results <- safe_query(db_pool, sprintf("
    SELECT t.event_date as \"Date\", s.name as \"Store\",
           CASE WHEN p.is_anonymized THEN 'Anonymous' ELSE p.display_name END as \"Player\",
           r.placement as \"Place\", r.wins as \"W\", r.losses as \"L\", r.decklist_url
    FROM results r
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    JOIN stores s ON t.store_id = s.store_id
    JOIN players p ON r.player_id = p.player_id
    WHERE r.archetype_id = $1 %s
    ORDER BY t.event_date DESC, r.placement ASC
    LIMIT 200
  ", scene_filters$sql), params = c(list(archetype_id), scene_filters$params), default = data.frame())

  # Apply advanced filters to modal results
  if (isTRUE(input$meta_top3_toggle) && nrow(recent_results) > 0) {
    recent_results <- recent_results[recent_results$Place <= 3, ]
  }
  if (isTRUE(input$meta_decklist_toggle) && nrow(recent_results) > 0) {
    recent_results <- recent_results[!is.na(recent_results$decklist_url) & recent_results$decklist_url != "", ]
  }

  # Card image URL
  card_img_url <- if (!is.na(archetype$display_card_id) && archetype$display_card_id != "") {
    sprintf("https://images.digimoncard.io/images/cards/%s.jpg", archetype$display_card_id)
  } else NULL

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
      deck_name_badge(archetype$archetype_name, archetype$primary_color, archetype$secondary_color)
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
              tags$th("Player"), tags$th("Times Played"), tags$th("1sts"), tags$th("Win %")
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

    # Tournament history (paginated)
    if (nrow(recent_results) > 0) {
      # Format for display
      display_results <- data.frame(
        Date = format(as.Date(recent_results$Date), "%b %d, %Y"),
        Store = recent_results$Store,
        Player = recent_results$Player,
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
            Player = colDef(minWidth = 100),
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
outputOptions(output, "deck_detail_modal", suspendWhenHidden = FALSE)
