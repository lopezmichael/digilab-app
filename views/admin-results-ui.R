# views/admin-results-ui.R
# Admin - Enter tournament results with wizard flow

admin_results_ui <- tagList(
  h2("Enter Tournament Results"),
  div(class = "page-help-text",
    div(class = "info-hint-box",
      bsicons::bs_icon("info-circle", class = "info-hint-icon"),
      "Create a new tournament and enter player results. Use the grid to add placements, player names, records, and deck archetypes."
    )
  ),

  # Wizard step indicator
  div(
    class = "wizard-steps d-flex gap-3 mb-4",
    div(
      id = "step1_indicator",
      class = "wizard-step active",
      span(class = "step-number", "1"),
      span(class = "step-label", "Tournament Details")
    ),
    div(
      id = "step2_indicator",
      class = "wizard-step",
      span(class = "step-number", "2"),
      span(class = "step-label", "Add Results")
    ),
    div(
      id = "step3_indicator",
      class = "wizard-step",
      span(class = "step-number", "3"),
      span(class = "step-label", "Decklists")
    )
  ),

  # Step 1: Tournament Details
  div(
    id = "wizard_step1",
    card(
        card_header("Tournament Details"),
        card_body(
          class = "tournament-details-form",
          # Row 1: Scene + Store + Date
          div(
            class = "row g-3 mb-3",
            div(class = "col-12 col-md-4",
                selectInput("tournament_scene", "Scene", choices = c("Loading..." = ""))),
            div(class = "col-12 col-md-4",
                selectInput("tournament_store", "Store", choices = c("Select scene first..." = ""))),
            div(class = "col-12 col-md-4",
                div(
                  class = "date-required",
                  dateInput("tournament_date", "Date *", value = NA),
                  div(id = "date_required_hint", class = "date-required-hint", "Required")
                ))
          ),
          # Row 2: Event Type + Format
          div(
            class = "row g-3 mb-3",
            div(class = "col-12 col-md-6",
                selectInput("tournament_type", "Event Type",
                            choices = c("Select event type..." = "", EVENT_TYPES))),
            div(class = "col-12 col-md-6",
                selectInput("tournament_format", "Format/Set", choices = list("Loading..." = "")))
          ),
          # Row 3: Players + Rounds
          div(
            class = "row g-3 mb-3",
            div(class = "col-12 col-md-6",
                numericInput("tournament_players", "Number of Players", value = 8, min = 2)),
            div(class = "col-12 col-md-6",
                numericInput("tournament_rounds", "Number of Rounds", value = 3, min = 1))
          ),
          # Row 4: Record Format
          div(
            class = "row g-3 mb-3",
            div(class = "col-12 col-md-6",
                radioButtons("admin_record_format", "Record Format",
                             choices = c("Points" = "points", "W-L-T" = "wlt"),
                             selected = "points", inline = TRUE),
                div(class = "text-muted small mt-1",
                    "Points: Total match points (e.g., from Bandai TCG+ standings). ",
                    "W-L-T: Individual wins, losses, and ties."))
          ),
          div(
            class = "d-flex justify-content-end mt-3",
            actionButton("create_tournament", "Create Tournament", class = "btn-primary btn-lg",
                         icon = icon("arrow-right"))
          )
        )
      )
  ),

  # Step 2: Enter Results Grid (hidden initially)
  shinyjs::hidden(
    div(
      id = "wizard_step2",
      class = "admin-panel",
      # Tournament summary bar
      uiOutput("tournament_summary_bar"),

      # Release event notice (shown/hidden by server based on event type)
      shinyjs::hidden(
        div(
          id = "release_event_deck_notice",
          class = "alert alert-info d-flex mb-3",
          bsicons::bs_icon("box-seam", class = "me-2 flex-shrink-0", size = "1.2em"),
          "Release events use sealed product, so deck archetypes are set to Unknown automatically."
        )
      ),

      card(
        card_header(
          class = "d-flex justify-content-between align-items-center",
          div(
            class = "d-flex align-items-center gap-2",
            span("Enter Results"),
            uiOutput("admin_record_format_badge", inline = TRUE)
          ),
          div(
            class = "d-flex align-items-center gap-2",
            uiOutput("admin_filled_count", inline = TRUE),
            actionButton("admin_paste_btn", "Paste from Spreadsheet",
                         class = "btn-sm btn-outline-primary",
                         icon = icon("clipboard"))
          )
        ),
        card_body(
          uiOutput("admin_grid_table")
        )
      ),

      # Bottom navigation
      div(
        class = "d-flex justify-content-between mt-3",
        div(
          class = "d-flex gap-2",
          actionButton("wizard_back", "Back to Details", class = "btn-secondary",
                       icon = icon("arrow-left")),
          actionButton("clear_tournament", "Start Over", class = "btn-outline-warning",
                       icon = icon("rotate-left"))
        ),
        actionButton("admin_submit_results", "Submit Results", class = "btn-primary btn-lg",
                     icon = icon("check"))
      )
    )
  ),

  # Step 3: Decklist Links (hidden initially)
  shinyjs::hidden(
    div(
      id = "wizard_step3",
      class = "admin-panel",
      uiOutput("admin_decklist_summary_bar"),
      card(
        card_header(
          class = "d-flex justify-content-between align-items-center",
          span("Add Decklist Links"),
          span(class = "text-muted small", "Optional — paste external decklist URLs for any players")
        ),
        card_body(
          uiOutput("admin_decklist_table")
        )
      ),
      div(
        class = "d-flex justify-content-between mt-3",
        actionButton("admin_skip_decklists", "Skip", class = "btn-outline-secondary",
                     icon = icon("forward")),
        div(
          class = "d-flex gap-2",
          actionButton("admin_save_decklists", "Save Progress", class = "btn-primary",
                       icon = icon("floppy-disk")),
          actionButton("admin_done_decklists", "Done", class = "btn-success",
                       icon = icon("check"))
        )
      )
    )
  )
)
