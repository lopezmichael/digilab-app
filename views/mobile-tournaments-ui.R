# views/mobile-tournaments-ui.R
# Mobile-optimized Tournaments view with stacked cards replacing reactable.
# Sourced inside output$tournaments_page when is_mobile() is TRUE.
# Returns a bare tagList (no assignment) so source(...)$value works.

tagList(
  # -- Title strip with filters (SAME input IDs as desktop) ------------------
  div(
    class = "page-title-strip mb-2",
    div(
      class = "title-strip-content",
      div(
        class = "title-strip-context",
        bsicons::bs_icon("trophy", class = "title-strip-icon"),
        tags$span(class = "title-strip-text", "Tournament History")
      ),
      div(
        class = "title-strip-controls",
        div(
          class = "title-strip-search",
          textInput("tournaments_search", NULL, placeholder = "Search...", width = "120px")
        ),
        div(
          class = "title-strip-select",
          selectInput("tournaments_format", NULL,
                      choices = format_choices_with_all,
                      selected = "",
                      width = "140px",
                      selectize = FALSE)
        ),
        div(
          class = "title-strip-select",
          selectInput("tournaments_event_type", NULL,
                      choices = list(
                        "All Events" = "",
                        "Event Types" = EVENT_TYPES
                      ),
                      selected = "",
                      width = "120px",
                      selectize = FALSE)
        ),
        actionButton("reset_tournaments_filters", NULL,
                     icon = icon("rotate-right"),
                     class = "btn-title-strip-reset",
                     title = "Reset filters")
      )
    )
  ),

  # Card container rendered by server
  uiOutput("mobile_tournaments_cards"),

  # Tournament detail modal (rendered dynamically)
  uiOutput("tournament_detail_modal")
)
