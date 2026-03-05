# views/mobile-meta-ui.R
# Mobile-optimized Meta view with deck archetype cards
# Sourced inside output$meta_page when is_mobile() is TRUE.
# Returns a bare tagList (no assignment) so source(...)$value works.

tagList(
  # -- Title strip with filters (SAME input IDs as desktop) ------------------
  div(
    class = "page-title-strip mb-2",
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
        span(class = "title-strip-pill-label",
          "Min Entries:",
          tags$span(
            class = "help-icon",
            title = "Default adjusts based on scene data. Newer scenes show all decks; established scenes filter to frequently played archetypes.",
            bsicons::bs_icon("question-circle")
          )
        ),
        div(
          class = "pill-toggle",
          `data-input-id` = "meta_min_entries",
          tags$button("All", class = "pill-option", `data-value` = "0"),
          tags$button("5+", class = "pill-option active", `data-value` = "5"),
          tags$button("10+", class = "pill-option", `data-value` = "10")
        ),
        actionButton("reset_meta_filters", NULL,
                     icon = icon("rotate-right"),
                     class = "btn-title-strip-reset",
                     title = "Reset filters")
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

  # -- Mobile card container --------------------------------------------------
  uiOutput("mobile_meta_cards"),

  # -- Deck detail modal (rendered dynamically) -------------------------------
  uiOutput("deck_detail_modal")
)
