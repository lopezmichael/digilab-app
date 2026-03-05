# views/players-ui.R
# Players tab UI with player profiles

tagList(
  # Title strip with integrated filters
  div(
    class = "page-title-strip mb-3",
    div(
      class = "title-strip-content",
      # Left side: page title
      div(
        class = "title-strip-context",
        bsicons::bs_icon("people", class = "title-strip-icon"),
        tags$span(class = "title-strip-text", "Player Standings")
      ),
      # Right side: compact filters
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

  # Help text
  div(class = "page-help-text",
    div(class = "info-hint-box text-center",
      bsicons::bs_icon("info-circle", class = "info-hint-icon"),
      "Player leaderboard ranked by ",
      actionLink("goto_faq_rating", "Competitive Rating", class = "info-hint-link"),
      " and ",
      actionLink("goto_faq_score", "Achievement Score", class = "info-hint-link"),
      ". Click any player to see their full tournament history and stats."
    )
  ),

  card(
    card_header(
      class = "d-flex justify-content-between align-items-center",
      "Player Leaderboard",
      span(class = "small text-muted", "Click a row for player profile")
    ),
    card_body(
      div(
        id = "player_standings_skeleton",
        skeleton_table(rows = 8)
      ),
      reactableOutput("player_standings")
    )
  ),

  # Player detail modal (rendered dynamically)
  uiOutput("player_detail_modal")
)
