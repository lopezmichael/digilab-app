# views/tournaments-ui.R
# Tournaments history tab UI with filters and detail modal

tagList(
  # Title strip with integrated filters
  div(
    class = "page-title-strip mb-3",
    div(
      class = "title-strip-content",
      # Left side: page title
      div(
        class = "title-strip-context",
        bsicons::bs_icon("trophy", class = "title-strip-icon"),
        tags$span(class = "title-strip-text", "Tournament History")
      ),
      # Right side: compact filters
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
                     title = "Reset filters"),
        tags$button(
          class = "btn-title-strip-filters",
          `data-target` = "tournaments_advanced_filters",
          icon("sliders"),
          "Filters"
        )
      )
    )
  ),
  # Advanced filters row (hidden by default)
  div(
    id = "tournaments_advanced_filters",
    class = "advanced-filters-row",
    div(class = "advanced-filter-group",
      tags$label("Store", class = "advanced-filter-label", `for` = "tournaments_store_filter"),
      selectInput("tournaments_store_filter", NULL,
        choices = list("All" = ""),
        width = "160px")
    ),
    div(class = "advanced-filter-group",
      tags$label("From", class = "advanced-filter-label", `for` = "tournaments_date_from"),
      dateInput("tournaments_date_from", NULL, value = NA, width = "110px")
    ),
    div(class = "advanced-filter-group",
      tags$label("To", class = "advanced-filter-label", `for` = "tournaments_date_to"),
      dateInput("tournaments_date_to", NULL, value = NA, width = "110px")
    ),
    div(class = "advanced-filter-group",
      tags$label("Size", class = "advanced-filter-label", `for` = "tournaments_size_filter"),
      selectInput("tournaments_size_filter", NULL,
        choices = list("Any" = "0", "8+" = "8", "16+" = "16", "32+" = "32", "64+" = "64", "128+" = "128"),
        width = "80px", selectize = FALSE)
    ),
    actionButton("tournaments_clear_advanced", "Clear All",
      class = "btn btn-outline-secondary btn-sm btn-clear-advanced")
  ),

  # Help text
  div(class = "page-help-text",
    div(class = "info-hint-box text-center",
      bsicons::bs_icon("info-circle", class = "info-hint-icon"),
      "Browse all recorded events. Click a tournament to see full standings, decks played, and match records."
    )
  ),

  card(
    card_header(
      class = "d-flex justify-content-between align-items-center",
      "All Tournaments",
      span(class = "small text-muted", "Click a row for full results")
    ),
    card_body(
      div(
        id = "tournament_history_skeleton",
        skeleton_table(rows = 8)
      ),
      reactableOutput("tournament_history")
    )
  ),

  # Tournament detail modal (rendered dynamically)
  uiOutput("tournament_detail_modal")
)
