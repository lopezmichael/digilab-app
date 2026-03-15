# views/mobile-players-ui.R
# Mobile-optimized Players view with stacked cards replacing reactable.
# Sourced inside output$players_page when is_mobile() is TRUE.
# Returns a bare tagList (no assignment) so source(...)$value works.

tagList(
  # -- Title strip: search + toggle + reset ------------------------------------
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
          tags$label(class = "visually-hidden", `for` = "players_search", "Search players"),
          textInput("players_search", NULL, placeholder = "Search...", width = "120px")
        ),
        tags$button(
          type = "button",
          class = "btn-title-strip-filters",
          `data-target` = "mobile_players_filters",
          icon("sliders"),
          "Filters"
        ),
        actionButton("reset_players_filters", NULL,
                     icon = icon("rotate-right"),
                     class = "btn-title-strip-reset",
                     title = "Reset filters",
                     `aria-label` = "Reset filters")
      )
    )
  ),

  # -- Collapsible filters (hidden by default) ---------------------------------
  div(
    id = "mobile_players_filters",
    class = "advanced-filters-row mobile-filters-panel",
    div(class = "advanced-filter-group mobile-filter-full",
      tags$label("Format", class = "advanced-filter-label"),
      selectInput("players_format", NULL,
                  choices = format_choices_with_all,
                  selected = "",
                  width = "100%",
                  selectize = FALSE)
    ),
    div(class = "mobile-filter-pair",
      div(class = "advanced-filter-group",
        tags$label("Status", class = "advanced-filter-label"),
        div(
          class = "pill-toggle",
          `data-input-id` = "players_min_events",
          role = "radiogroup",
          `aria-label` = "Player ranking status",
          tags$button("Unranked", class = "pill-option active", `data-value` = "0", role = "radio", `aria-checked` = "true"),
          tags$button("Ranked", class = "pill-option", `data-value` = "10", role = "radio", `aria-checked` = "false")
        )
      ),
      div(class = "advanced-filter-group",
        tags$label("Win %", class = "advanced-filter-label"),
        selectInput("players_win_pct_filter", NULL,
          choices = list("Any" = "0", "50%+" = "50", "60%+" = "60", "70%+" = "70"),
          width = "100%", selectize = FALSE)
      )
    ),
    div(class = "advanced-filter-group mobile-filter-full",
      tags$label("Store", class = "advanced-filter-label"),
      selectInput("players_store_filter", NULL,
        choices = list("All" = ""),
        width = "100%")
    ),
    div(class = "mobile-filter-checkbox-row",
      span(class = "mobile-filter-note", "These filters also apply to player detail cards"),
      div(class = "advanced-filter-group",
        tags$label("Top 3 only", class = "advanced-filter-label"),
        checkboxInput("players_top3_toggle", NULL, value = FALSE)
      ),
      div(class = "advanced-filter-group",
        tags$label("Has decklist", class = "advanced-filter-label"),
        checkboxInput("players_decklist_toggle", NULL, value = FALSE)
      )
    )
  ),

  # Historical rating indicator (shown when viewing past format)
  uiOutput("historical_rating_badge"),

  # Skeleton loading state (auto-hidden when cards render)
  skeleton_cards(n = 3, id_prefix = "mobile_players_cards"),

  # Card container rendered by server
  uiOutput("mobile_players_cards"),

  # Player detail modal (rendered dynamically)
  uiOutput("player_detail_modal")
)
