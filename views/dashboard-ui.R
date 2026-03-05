# views/dashboard-ui.R
# Dashboard tab UI
# Sourced inside output$dashboard_page renderUI.
# Expects `format_choices_with_all` in local environment.

tagList(
  # Title strip with integrated filters
  div(
    class = "page-title-strip mb-2",
    div(
      class = "title-strip-content",
      # Left side: context display
      div(
        class = "title-strip-context",
        bsicons::bs_icon("grid-3x3-gap", class = "title-strip-icon"),
        tags$span(class = "title-strip-text", uiOutput("dashboard_context_text", inline = TRUE))
      ),
      # Right side: compact filters
      div(
        class = "title-strip-controls",
        div(
          class = "title-strip-select",
          selectInput("dashboard_format", NULL,
                      choices = format_choices_with_all,
                      selected = "",
                      width = "140px",
                      selectize = FALSE)
        ),
        div(
          class = "title-strip-select",
          selectInput("dashboard_event_type", NULL,
                      choices = list(
                        "All Events" = "",
                        "Event Types" = EVENT_TYPES
                      ),
                      selected = "",
                      width = "120px",
                      selectize = FALSE)
        ),
        actionButton("reset_dashboard_filters", NULL,
                     icon = icon("rotate-right"),
                     class = "btn-title-strip-reset",
                     title = "Reset filters")
      )
    )
  ),

  # Help text
  div(class = "page-help-text",
    div(class = "info-hint-box text-center",
      bsicons::bs_icon("info-circle", class = "info-hint-icon"),
      "Overview of your scene's tournament activity, trending decks, and top performers. Use filters above to drill into specific formats or event types."
    )
  ),

  # Value boxes with digital Digimon aesthetic
  div(
    class = "overview-value-boxes mb-3",
    layout_columns(
      col_widths = breakpoints(
        sm = c(12, 12, 12, 12),
        md = c(6, 6, 6, 6),
        lg = c(3, 3, 3, 3)
      ),
      # Box 1: Tournaments (format-filtered)
      div(
        class = "value-box-digital vb-tournaments",
        div(class = "vb-digital-grid"),
        div(
          class = "vb-content",
          div(class = "vb-label", "TOURNAMENTS"),
          div(class = "vb-value", textOutput("total_tournaments_val", inline = TRUE)),
          div(class = "vb-subtitle", "this format")
        )
      ),
      # Box 2: Players (unique in format)
      div(
        class = "value-box-digital vb-players",
        div(class = "vb-digital-grid"),
        div(
          class = "vb-content",
          div(class = "vb-label", "PLAYERS"),
          div(class = "vb-value", textOutput("total_players_val", inline = TRUE)),
          div(class = "vb-subtitle", "unique")
        )
      ),
      # Box 3: Trending deck (biggest meta share increase)
      div(
        class = "value-box-digital vb-hotdeck",
        div(class = "vb-digital-grid"),
        div(
          class = "vb-content-with-image",
          div(
            class = "vb-image-showcase",
            uiOutput("hot_deck_image")
          ),
          div(
            class = "vb-content",
            div(class = "vb-label",
                bsicons::bs_icon("fire", class = "vb-label-icon"),
                "TRENDING"),
            div(class = "vb-value vb-value-deck", uiOutput("hot_deck_name", inline = TRUE)),
            div(class = "vb-subtitle", uiOutput("hot_deck_trend", inline = TRUE))
          )
        )
      ),
      # Box 4: Most Played deck (highest meta share)
      div(
        class = "value-box-digital vb-topdeck",
        div(class = "vb-digital-grid"),
        div(
          class = "vb-content-with-image",
          div(
            class = "vb-image-showcase",
            uiOutput("top_deck_image")
          ),
          div(
            class = "vb-content",
            div(class = "vb-label",
                bsicons::bs_icon("trophy", class = "vb-label-icon"),
                "MOST PLAYED"),
            div(class = "vb-value vb-value-deck", textOutput("most_popular_deck_val", inline = TRUE)),
            div(class = "vb-subtitle", uiOutput("top_deck_meta_share", inline = TRUE))
          )
        )
      )
    )
  ),

  # Top Decks with card images (primary visual)
  card(
    card_header(
      class = "d-flex justify-content-between align-items-center",
      div(
        class = "d-flex align-items-center gap-2",
        bsicons::bs_icon("collection", class = "text-primary"),
        uiOutput("top_decks_header", inline = TRUE)
      ),
      span(class = "small text-muted", "Click a deck for details")
    ),
    card_body(
      class = "top-decks-container",
      uiOutput("top_decks_with_images")
    )
  ),

  # Spacer
  div(class = "mb-3"),

  # Rising Stars section
  card(
    card_header(
      class = "d-flex justify-content-between align-items-center",
      div(
        class = "d-flex align-items-center gap-2",
        bsicons::bs_icon("graph-up-arrow", class = "text-success"),
        "Rising Stars"
      ),
      tags$span(class = "text-muted small", "Top finishes (last 30 days)")
    ),
    card_body(
      class = "rising-stars-section",
      uiOutput("rising_stars_cards")
    )
  ),

  # Spacer
  div(class = "mb-3"),

  # Meta Diversity + Recent Tournaments row
  layout_columns(
    col_widths = breakpoints(
      sm = c(12, 12),
      md = c(4, 8)
    ),
    # Meta Diversity gauge card
    card(
      card_header(
        class = "d-flex justify-content-between align-items-center",
        div(
          class = "d-flex align-items-center gap-2",
          bsicons::bs_icon("pie-chart", class = "text-info"),
          "Meta Diversity"
        ),
        uiOutput("meta_diversity_decks_count", inline = TRUE)
      ),
      card_body(
        class = "p-2 d-flex flex-column",
        div(
          class = "flex-grow-1",
          div(id = "meta_diversity_gauge_skeleton", skeleton_chart(bars = 1, height = "180px")),
          highchartOutput("meta_diversity_gauge", height = "220px")
        ),
        div(
          class = "info-hint-box text-center",
          bsicons::bs_icon("info-circle", class = "info-hint-icon"),
          "How evenly distributed tournament wins are across different decks. Higher = healthier meta."
        )
      )
    ),
    # Recent Tournaments table
    card(
      card_header(
        class = "d-flex justify-content-between align-items-center",
        div(
          class = "d-flex align-items-center gap-2",
          bsicons::bs_icon("calendar-event", class = "text-primary"),
          "Recent Tournaments"
        ),
        span(class = "small text-muted", "Click a row for full results")
      ),
      card_body(
        div(id = "recent_tournaments_skeleton", skeleton_table(rows = 5)),
        reactableOutput("recent_tournaments")
      )
    )
  ),

  # Spacer
  div(class = "mb-3"),

  # Top 3 Conversion + Color Distribution row
  layout_columns(
    col_widths = breakpoints(sm = c(12, 12), md = c(6, 6)),
    card(
      card_header(
        class = "d-flex justify-content-between align-items-center",
        div(
          class = "d-flex align-items-center gap-2",
          bsicons::bs_icon("bullseye", class = "text-warning"),
          "Top 3 Conversion"
        ),
        uiOutput("conversion_threshold_note", inline = TRUE)
      ),
      card_body(
        class = "p-0",
        div(id = "conversion_rate_chart_skeleton", skeleton_chart(bars = 5, height = "240px")),
        highchartOutput("conversion_rate_chart", height = "280px")
      )
    ),
    card(
      card_header(
        class = "d-flex align-items-center gap-2",
        bsicons::bs_icon("palette", class = "text-info"),
        "Color Distribution"
      ),
      card_body(
        class = "p-0",
        div(id = "color_dist_chart_skeleton", skeleton_chart(bars = 7, height = "240px")),
        highchartOutput("color_dist_chart", height = "280px")
      )
    )
  ),

  # Spacer
  div(class = "mb-3"),

  # Meta Share Over Time
  card(
    card_header(
      class = "d-flex align-items-center gap-2",
      bsicons::bs_icon("bar-chart-line", class = "text-info"),
      "Meta Share Over Time"
    ),
    card_body(
      class = "p-0",
      div(id = "meta_share_timeline_skeleton", skeleton_chart(bars = 10, height = "310px")),
      highchartOutput("meta_share_timeline", height = "350px")
    )
  ),

  # Spacer
  div(class = "mb-3"),

  # Player Attendance chart
  card(
    card_header(
      class = "d-flex align-items-center gap-2",
      bsicons::bs_icon("activity", class = "text-primary"),
      "Player Attendance"
    ),
    card_body(
      class = "p-0",
      div(id = "tournaments_trend_chart_skeleton", skeleton_chart(bars = 8, height = "240px")),
      highchartOutput("tournaments_trend_chart", height = "280px")
    )
  ),

  # Spacer
  div(class = "mb-3"),

  # Player Growth & Retention
  card(
    card_header(
      class = "d-flex align-items-center gap-2",
      bsicons::bs_icon("people", class = "text-success"),
      "Player Growth & Retention"
    ),
    card_body(
      class = "p-2",
      div(id = "player_growth_chart_skeleton", skeleton_chart(bars = 6, height = "160px")),
      highchartOutput("player_growth_chart", height = "200px")
    )
  )
)
