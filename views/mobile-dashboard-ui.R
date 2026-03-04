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
                      choices = list("All Formats" = ""),
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

  # -- Value boxes: 2x2 grid -------------------------------------------------
  div(
    class = "overview-value-boxes mb-3",
    layout_columns(
      col_widths = c(6, 6, 6, 6),
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
      # Box 3: Hot Deck
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
                "HOT DECK"),
            div(class = "vb-value vb-value-deck", uiOutput("hot_deck_name", inline = TRUE)),
            div(class = "vb-subtitle", uiOutput("hot_deck_trend", inline = TRUE))
          )
        )
      ),
      # Box 4: Top Deck
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
                "TOP DECK"),
            div(class = "vb-value vb-value-deck", textOutput("most_popular_deck_val", inline = TRUE)),
            div(class = "vb-subtitle", uiOutput("top_deck_meta_share", inline = TRUE))
          )
        )
      )
    )
  ),

  # -- Tournament Activity chart ---------------------------------------------
  div(class = "mobile-section-header", "Tournament Activity"),
  div(
    class = "mobile-chart-container",
    highchartOutput("tournaments_trend_chart", height = "250px")
  ),

  # -- Color Distribution chart ----------------------------------------------
  div(class = "mobile-section-header", "Color Distribution"),
  div(
    class = "mobile-chart-container",
    highchartOutput("color_dist_chart", height = "250px")
  ),

  # -- Meta Share Over Time --------------------------------------------------
  div(class = "mobile-section-header", "Meta Share Over Time"),
  div(
    class = "mobile-chart-container",
    highchartOutput("meta_share_timeline", height = "250px")
  ),

  # -- Player Growth & Retention --------------------------------------------
  div(class = "mobile-section-header", "Player Growth & Retention"),
  div(
    class = "mobile-chart-container",
    highchartOutput("player_growth_chart", height = "200px")
  ),

  # -- Rising Stars ----------------------------------------------------------
  div(class = "mobile-section-header", "Rising Stars"),
  uiOutput("mobile_rising_stars"),

  # -- Top Decks -------------------------------------------------------------
  div(class = "mobile-section-header", "Top Decks"),
  uiOutput("mobile_top_decks")
)
