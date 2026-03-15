# views/mobile-meta-ui.R
# Mobile-optimized Meta view with deck archetype cards
# Sourced inside output$meta_page when is_mobile() is TRUE.
# Returns a bare tagList (no assignment) so source(...)$value works.

tagList(
  # -- Title strip: search + toggle + reset ------------------------------------
  div(
    class = "page-title-strip mb-2",
    div(
      class = "title-strip-content",
      div(
        class = "title-strip-context",
        bsicons::bs_icon("stack", class = "title-strip-icon"),
        tags$span(class = "title-strip-text", "Deck Meta")
      ),
      div(
        class = "title-strip-controls",
        div(
          class = "title-strip-search",
          textInput("meta_search", NULL, placeholder = "Search...", width = "120px")
        ),
        tags$button(
          type = "button",
          class = "btn-title-strip-filters",
          `data-target` = "mobile_meta_filters",
          icon("sliders"),
          "Filters"
        ),
        actionButton("reset_meta_filters", NULL,
                     icon = icon("rotate-right"),
                     class = "btn-title-strip-reset",
                     title = "Reset filters")
      )
    )
  ),

  # -- Collapsible filters (hidden by default) ---------------------------------
  div(
    id = "mobile_meta_filters",
    class = "advanced-filters-row mobile-filters-panel",
    div(class = "advanced-filter-group mobile-filter-full",
      tags$label("Format", class = "advanced-filter-label"),
      selectInput("meta_format", NULL,
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
          `data-input-id` = "meta_min_entries",
          tags$button("Unranked", class = "pill-option active", `data-value` = "0"),
          tags$button("Ranked", class = "pill-option", `data-value` = "10")
        )
      ),
      div(class = "advanced-filter-group",
        tags$label("Conv %", class = "advanced-filter-label"),
        selectInput("meta_conversion_filter", NULL,
          choices = list("Any" = "0", "5%+" = "5", "10%+" = "10", "20%+" = "20", "30%+" = "30"),
          width = "100%", selectize = FALSE)
      )
    ),
    div(class = "advanced-filter-group mobile-filter-full",
      tags$label("Color", class = "advanced-filter-label"),
      div(id = "meta_color_pills", class = "color-filter-pills",
        tags$span(class = "color-pill", `data-color` = "Red",
          tags$span(class = "color-dot"), "Red"),
        tags$span(class = "color-pill", `data-color` = "Blue",
          tags$span(class = "color-dot"), "Blue"),
        tags$span(class = "color-pill", `data-color` = "Yellow",
          tags$span(class = "color-dot"), "Yellow"),
        tags$span(class = "color-pill", `data-color` = "Green",
          tags$span(class = "color-dot"), "Green"),
        tags$span(class = "color-pill", `data-color` = "Black",
          tags$span(class = "color-dot"), "Black"),
        tags$span(class = "color-pill", `data-color` = "Purple",
          tags$span(class = "color-dot"), "Purple"),
        tags$span(class = "color-pill", `data-color` = "White",
          tags$span(class = "color-dot"), "White")
      )
    ),
    div(class = "mobile-filter-checkbox-row",
      span(class = "mobile-filter-note", "These filters also apply to deck detail cards"),
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

  # -- Help text --------------------------------------------------------------
  div(class = "page-help-text",
    div(class = "info-hint-box text-center",
      bsicons::bs_icon("info-circle", class = "info-hint-icon"),
      "Deck performance across all tournaments. Tap a deck for its full profile."
    )
  ),

  # Skeleton loading state (auto-hidden when cards render)
  skeleton_cards(n = 3, id_prefix = "mobile_meta_cards"),

  # -- Mobile card container --------------------------------------------------
  uiOutput("mobile_meta_cards"),

  # -- Deck detail modal (rendered dynamically) -------------------------------
  uiOutput("deck_detail_modal")
)
