# views/mobile-players-ui.R
# Mobile-optimized Players view with stacked cards replacing reactable.
# Sourced inside output$players_page when is_mobile() is TRUE.
# Returns a bare tagList (no assignment) so source(...)$value works.

tagList(
  # -- Title strip with filters (SAME input IDs as desktop) ------------------
  div(
    class = "page-title-strip mb-2",
    div(
      class = "title-strip-content",
      div(
        class = "title-strip-context",
        bsicons::bs_icon("people", class = "title-strip-icon"),
        tags$span(class = "title-strip-text", "Player Standings")
      ),
      div(
        class = "title-strip-controls",
        div(
          class = "title-strip-search",
          textInput("players_search", NULL, placeholder = "Search...", width = "120px")
        ),
        div(
          class = "title-strip-select",
          selectInput("players_format", NULL,
                      choices = format_choices_with_all,
                      selected = "",
                      width = "140px",
                      selectize = FALSE)
        ),
        span(class = "title-strip-pill-label",
          "Min Events:",
          tags$span(
            class = "help-icon",
            title = "Default adjusts based on scene data. Newer scenes show all players; established scenes filter to frequent competitors.",
            bsicons::bs_icon("question-circle")
          )
        ),
        div(
          class = "pill-toggle",
          `data-input-id` = "players_min_events",
          tags$button("All", class = "pill-option", `data-value` = "0"),
          tags$button("5+", class = "pill-option active", `data-value` = "5"),
          tags$button("10+", class = "pill-option", `data-value` = "10")
        ),
        actionButton("reset_players_filters", NULL,
                     icon = icon("rotate-right"),
                     class = "btn-title-strip-reset",
                     title = "Reset filters")
      )
    )
  ),

  # Historical rating indicator (shown when viewing past format)
  uiOutput("historical_rating_badge"),

  # Card container rendered by server
  uiOutput("mobile_players_cards"),

  # Player detail modal (rendered dynamically)
  uiOutput("player_detail_modal")
)
