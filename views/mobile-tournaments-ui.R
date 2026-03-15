# views/mobile-tournaments-ui.R
# Mobile-optimized Tournaments view with stacked cards replacing reactable.
# Sourced inside output$tournaments_page when is_mobile() is TRUE.
# Returns a bare tagList (no assignment) so source(...)$value works.

tagList(
  # -- Title strip: search + toggle + reset ------------------------------------
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
        tags$button(
          type = "button",
          class = "btn-title-strip-filters",
          `data-target` = "mobile_tournaments_filters",
          icon("sliders"),
          "Filters"
        ),
        actionButton("reset_tournaments_filters", NULL,
                     icon = icon("rotate-right"),
                     class = "btn-title-strip-reset",
                     title = "Reset filters")
      )
    )
  ),

  # -- Collapsible filters (hidden by default) ---------------------------------
  div(
    id = "mobile_tournaments_filters",
    class = "advanced-filters-row mobile-filters-panel",
    div(class = "advanced-filter-group mobile-filter-full",
      tags$label("Format", class = "advanced-filter-label"),
      selectInput("tournaments_format", NULL,
                  choices = format_choices_with_all,
                  selected = "",
                  width = "100%",
                  selectize = FALSE)
    ),
    div(class = "mobile-filter-pair event-type-pair",
      div(class = "advanced-filter-group",
        tags$label("Event Type", class = "advanced-filter-label"),
        selectInput("tournaments_event_type", NULL,
                    choices = list(
                      "All Events" = "",
                      "Event Types" = EVENT_TYPES
                    ),
                    selected = "",
                    width = "100%",
                    selectize = FALSE)
      ),
      div(class = "advanced-filter-group",
        tags$label("Event Size", class = "advanced-filter-label"),
        selectInput("tournaments_size_filter", NULL,
          choices = list("Any" = "0", "8+" = "8", "16+" = "16", "32+" = "32", "64+" = "64", "128+" = "128"),
          width = "100%", selectize = FALSE)
      )
    ),
    div(class = "advanced-filter-group mobile-filter-full",
      tags$label("Store", class = "advanced-filter-label"),
      selectInput("tournaments_store_filter", NULL,
        choices = list("All" = ""),
        width = "100%")
    ),
    div(class = "mobile-filter-pair date-range-pair",
      div(class = "advanced-filter-group",
        tags$label("Date From", class = "advanced-filter-label"),
        dateInput("tournaments_date_from", NULL, value = NA, width = "100%")
      ),
      div(class = "advanced-filter-group",
        tags$label("Date To", class = "advanced-filter-label"),
        dateInput("tournaments_date_to", NULL, value = NA, width = "100%")
      )
    )
  ),

  # Skeleton loading state (auto-hidden when cards render)
  skeleton_cards(n = 3, id_prefix = "mobile_tournaments_cards"),

  # Card container rendered by server
  uiOutput("mobile_tournaments_cards"),

  # Tournament detail modal (rendered dynamically)
  uiOutput("tournament_detail_modal")
)
