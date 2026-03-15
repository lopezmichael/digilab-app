# views/admin-decks-ui.R
# Admin - Manage deck archetypes UI

admin_decks_ui <- tagList(
  div(
    class = "d-flex justify-content-between align-items-center mb-3",
    h2("Edit Deck Archetypes", class = "mb-0"),
    actionButton("show_merge_deck_modal", "Merge Decks",
                 class = "btn-outline-warning",
                 icon = icon("code-merge"))
  ),

  # Pending deck requests section (collapsible)
  uiOutput("deck_requests_section"),

  div(class = "page-help-text",
    div(class = "info-hint-box",
      bsicons::bs_icon("info-circle", class = "info-hint-icon"),
      "Define deck archetypes with colors and a display card. Players' results are tagged with these archetypes for meta analysis."
    )
  ),
  div(
    class = "admin-panel",
    layout_columns(
      col_widths = breakpoints(sm = c(12, 12), md = c(6, 6)),
      card(
        card_header(
          class = "d-flex justify-content-between align-items-center",
          span(id = "deck_form_title", "Add New Archetype"),
          conditionalPanel(
            condition = "input.editing_archetype_id && input.editing_archetype_id != ''",
            actionButton("cancel_edit_archetype", "Cancel Edit", class = "btn-sm btn-outline-secondary")
          )
        ),
        card_body(
          class = "admin-form-body",
          # Hidden field for edit mode
          textInput("editing_archetype_id", NULL, value = ""),
          tags$script("document.getElementById('editing_archetype_id').parentElement.style.display = 'none';"),

          # --- Identity section ---
          div(class = "admin-form-section",
            div(class = "admin-form-section-label",
              bsicons::bs_icon("palette-fill"),
              "Identity"
            ),
            textInput("deck_name", "Archetype Name", placeholder = "e.g., Fenriloogamon"),
            selectInput("deck_primary_color", "Primary Color",
                        choices = c("Red", "Blue", "Yellow", "Green", "Purple", "Black", "White")),
            selectInput("deck_secondary_color", "Secondary Color",
                        choices = c("None" = "", "Red", "Blue", "Yellow", "Green", "Purple", "Black", "White")),
            checkboxInput("deck_multi_color", "Multi-color deck (3+ colors)", value = FALSE),
            tags$small(class = "form-text text-muted d-block mt-n2 mb-2",
              "Check for decks with 3+ colors. For dual-color decks, use Primary and Secondary color instead.")
          ),

          # --- Display Card section ---
          div(class = "admin-form-section",
            div(class = "admin-form-section-label",
              bsicons::bs_icon("image"),
              "Display Card"
            ),
            layout_columns(
              col_widths = breakpoints(sm = c(12, 12), md = c(4, 8)),
              # Card preview on left
              div(
                class = "text-center",
                div(
                  id = "card_preview_container",
                  class = "rounded p-2 card-preview-container",
                  uiOutput("selected_card_preview")
                )
              ),
              # Search controls on right
              div(
                # Row 1: Search input + button (aligned with flexbox)
                div(
                  class = "search-row-aligned",
                  div(class = "search-input-wrapper", textInput("card_search", "Search", placeholder = "Type card name...")),
                  div(class = "search-btn-wrapper",
                      actionButton("search_card_btn", bsicons::bs_icon("search"),
                                   class = "btn-card-search"))
                ),
                # Row 2: Card ID with inline info icon in label
                div(
                  tags$label(
                    `for` = "selected_card_id",
                    class = "form-label d-flex align-items-center gap-1",
                    "Selected Card ID",
                    tags$span(
                      class = "text-muted help-icon",
                      title = "Click a card from search results to auto-fill, or enter a card ID manually",
                      bsicons::bs_icon("info-circle", size = "0.9rem")
                    )
                  ),
                  textInput("selected_card_id", NULL, placeholder = "e.g., BT17-042")
                )
              )
            ),
            # Search results in dedicated box below
            div(
              class = "card-search-results-container p-2 mt-2 card-search-results-min",
              tags$label(class = "form-label small text-muted", "Search Results"),
              uiOutput("card_search_results")
            )
          ),

          # --- Action buttons ---
          div(
            class = "admin-form-actions",
            actionButton("add_archetype", "Add Archetype", class = "btn-primary"),
            actionButton("update_archetype", "Update Archetype", class = "btn-success", style = "display: none;"),
            actionButton("delete_archetype", "Delete Archetype", class = "btn-danger", style = "display: none;")
          )
        )
      ),
      card(
        card_header(
          class = "d-flex justify-content-between align-items-center",
          div(
            "Current Archetypes",
            div(class = "small text-muted", "Decks without cards shown first")
          ),
          span(class = "small text-muted", "Click a row to edit")
        ),
        card_body(
          div(class = "deck-color-filters mb-2",
            actionLink("deck_filter_all", "All", class = "deck-filter-chip active"),
            actionLink("deck_filter_red", "Red", class = "deck-filter-chip"),
            actionLink("deck_filter_blue", "Blue", class = "deck-filter-chip"),
            actionLink("deck_filter_yellow", "Yellow", class = "deck-filter-chip"),
            actionLink("deck_filter_green", "Green", class = "deck-filter-chip"),
            actionLink("deck_filter_purple", "Purple", class = "deck-filter-chip"),
            actionLink("deck_filter_black", "Black", class = "deck-filter-chip"),
            actionLink("deck_filter_white", "White", class = "deck-filter-chip")
          ),
          reactableOutput("archetype_list")
        )
      )
    )
  )
)
