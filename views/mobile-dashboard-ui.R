# views/mobile-dashboard-ui.R
# Mobile-optimized Dashboard view
# Sourced inside output$dashboard_page when is_mobile() is TRUE.
# Returns a bare tagList (no assignment) so source(...)$value works.

tagList(
  # -- Title strip with filters (SAME input IDs as desktop) ------------------
  div(
    class = "page-title-strip mb-2",
    div(
      class = "title-strip-content",
      div(
        class = "title-strip-context",
        bsicons::bs_icon("grid-3x3-gap", class = "title-strip-icon"),
        tags$span(class = "title-strip-text", uiOutput("dashboard_context_text", inline = TRUE))
      ),
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

  # -- Value boxes: 2x2 CSS grid (no bslib breakpoints) ---------------------
  div(
    class = "mobile-value-boxes-grid mb-3",
    # Box 1: Tournaments
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
    # Box 2: Players
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
    # Box 3: Trending deck
    div(
      class = "value-box-digital vb-hotdeck",
      div(class = "vb-digital-grid"),
      div(
        class = "vb-content-with-image",
        div(class = "vb-image-showcase", uiOutput("hot_deck_image")),
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
    # Box 4: Most Played deck
    div(
      class = "value-box-digital vb-topdeck",
      div(class = "vb-digital-grid"),
      div(
        class = "vb-content-with-image",
        div(class = "vb-image-showcase", uiOutput("top_deck_image")),
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
  ),

  # -- All sections in a single accordion -----------------------------------
  accordion(
    id = "mobile_dashboard_sections",
    open = c("Top Decks", "Rising Stars"),
    multiple = TRUE,
    class = "mobile-dashboard-accordion",

    # -- Top Decks (open by default) -----------------------------------------
    accordion_panel(
      "Top Decks",
      icon = bsicons::bs_icon("collection"),
      uiOutput("mobile_top_decks")
    ),

    # -- Rising Stars (open by default) --------------------------------------
    accordion_panel(
      "Rising Stars",
      icon = bsicons::bs_icon("graph-up-arrow"),
      uiOutput("mobile_rising_stars")
    ),

    # -- Recent Tournaments (closed) -----------------------------------------
    accordion_panel(
      "Recent Tournaments",
      icon = bsicons::bs_icon("calendar-event"),
      uiOutput("mobile_recent_tournaments")
    ),

    # -- Analytics charts (all closed) ---------------------------------------
    accordion_panel(
      "Meta Diversity",
      icon = bsicons::bs_icon("pie-chart"),
      div(
        class = "mobile-chart-container",
        highchartOutput("meta_diversity_gauge", height = "200px")
      ),
      div(class = "info-hint-box text-center mb-2",
        bsicons::bs_icon("info-circle", class = "info-hint-icon"),
        "How evenly distributed tournament wins are across different decks. Higher = healthier meta."
      )
    ),
    accordion_panel(
      "Top 3 Conversion",
      icon = bsicons::bs_icon("bullseye"),
      div(
        class = "mobile-chart-container",
        highchartOutput("conversion_rate_chart", height = "250px")
      )
    ),
    accordion_panel(
      "Color Distribution",
      icon = bsicons::bs_icon("palette"),
      div(
        class = "mobile-chart-container",
        highchartOutput("color_dist_chart", height = "250px")
      )
    ),
    accordion_panel(
      "Meta Share Over Time",
      icon = bsicons::bs_icon("bar-chart-line"),
      div(
        class = "mobile-chart-container",
        highchartOutput("meta_share_timeline", height = "250px")
      )
    ),
    accordion_panel(
      "Tournament Activity",
      icon = bsicons::bs_icon("activity"),
      div(
        class = "mobile-chart-container",
        highchartOutput("tournaments_trend_chart", height = "250px")
      )
    ),
    accordion_panel(
      "Player Growth & Retention",
      icon = bsicons::bs_icon("people"),
      div(
        class = "mobile-chart-container",
        highchartOutput("player_growth_chart", height = "200px")
      )
    )
  )
)
