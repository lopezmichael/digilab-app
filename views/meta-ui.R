# views/meta-ui.R
# Meta analysis tab UI with deck profiles

tagList(
  # Title strip with integrated filters
  div(
    class = "page-title-strip mb-3",
    div(
      class = "title-strip-content",
      # Left side: page title
      div(
        class = "title-strip-context",
        bsicons::bs_icon("stack", class = "title-strip-icon"),
        tags$span(class = "title-strip-text", "Deck Meta")
      ),
      # Right side: compact filters
      div(
        class = "title-strip-controls",
        div(
          class = "title-strip-search",
          textInput("meta_search", NULL, placeholder = "Search...", width = "120px")
        ),
        div(
          class = "title-strip-select",
          selectInput("meta_format", NULL,
                      choices = format_choices_with_all,
                      selected = "",
                      width = "140px",
                      selectize = FALSE)
        ),
        span(class = "title-strip-pill-label", "Status"),
        div(
          class = "pill-toggle",
          `data-input-id` = "meta_min_entries",
          tags$button("Unranked", class = "pill-option active", `data-value` = "0"),
          tags$button("Ranked", class = "pill-option", `data-value` = "10")
        ),
        actionButton("reset_meta_filters", NULL,
                     icon = icon("rotate-right"),
                     class = "btn-title-strip-reset",
                     title = "Reset filters"),
        tags$button(
          type = "button",
          class = "btn-title-strip-filters",
          `data-target` = "meta_advanced_filters",
          icon("sliders"),
          "Filters"
        )
      )
    )
  ),
  # Advanced filters row (hidden by default)
  div(
    id = "meta_advanced_filters",
    class = "advanced-filters-row",
    # Row 1: Color pills + conversion %
    div(class = "advanced-filter-group",
      tags$label("Color", class = "advanced-filter-label"),
      color_filter_pills()
    ),
    div(class = "advanced-filter-group",
      tags$label("Conv %", class = "advanced-filter-label", `for` = "meta_conversion_filter"),
      selectInput("meta_conversion_filter", NULL,
        choices = list("Any" = "0", "5%+" = "5", "10%+" = "10", "20%+" = "20", "30%+" = "30"),
        width = "80px", selectize = FALSE)
    ),
    # Row 2: filters that also apply to deck profile modal
    div(class = "advanced-filter-row-2",
      span(class = "advanced-filter-hint", "Also filters deck profile modal:"),
      div(class = "advanced-filter-group",
        tags$label("Top 3 only", class = "advanced-filter-label"),
        checkboxInput("meta_top3_toggle", NULL, value = FALSE)
      ),
      div(class = "advanced-filter-group",
        tags$label("Has decklist", class = "advanced-filter-label"),
        checkboxInput("meta_decklist_toggle", NULL, value = FALSE)
      )
    )
  ),

  # Help text
  div(class = "page-help-text",
    div(class = "info-hint-box text-center",
      bsicons::bs_icon("info-circle", class = "info-hint-icon"),
      "Deck performance across all tournaments. See which archetypes are played most and which convert to top finishes."
    )
  ),

  card(
    card_header(
      class = "d-flex justify-content-between align-items-center",
      "Archetype Performance",
      span(class = "small text-muted", "Click a row for deck profile")
    ),
    card_body(
      div(
        id = "archetype_stats_skeleton",
        skeleton_table(rows = 8)
      ),
      reactableOutput("archetype_stats")
    )
  ),

  # Deck detail modal (rendered dynamically)
  uiOutput("deck_detail_modal")
)
