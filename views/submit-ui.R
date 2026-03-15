# views/submit-ui.R
# Public Upload Results tab UI

submit_ui <- tagList(
  # Title strip
  div(
    class = "page-title-strip mb-3",
    div(
      class = "title-strip-content",
      div(
        class = "title-strip-context",
        bsicons::bs_icon("cloud-upload", class = "title-strip-icon"),
        tags$span(class = "title-strip-text", "Upload Results")
      ),
      div(
        class = "title-strip-controls",
        span(class = "small text-muted", "Upload Bandai TCG+ screenshots or CSV exports to add tournament data")
      )
    )
  ),

  # Main content with tabs
  navset_card_tab(
    id = "submit_tabs",

    # Tournament Results Tab
    nav_panel(
      title = tagList(bsicons::bs_icon("trophy"), " Tournament Results"),
      value = "tournament",

      div(
        class = "p-3",

        # Wizard step indicator
        div(
          class = "wizard-steps d-flex gap-3 mb-4",
          div(
            id = "submit_step1_indicator",
            class = "wizard-step active",
            span(class = "step-number", "1"),
            span(class = "step-label", "Upload Results")
          ),
          div(
            id = "submit_step2_indicator",
            class = "wizard-step",
            span(class = "step-number", "2"),
            span(class = "step-label", "Review & Submit")
          ),
          div(
            id = "submit_step3_indicator",
            class = "wizard-step",
            span(class = "step-number", "3"),
            span(class = "step-label", "Decklists")
          )
        ),

        # Step 1: Combined Tournament Details + Screenshot Upload
        div(
          id = "submit_wizard_step1",

          card(
            card_header(
              class = "d-flex align-items-center gap-2",
              bsicons::bs_icon("clipboard-data"),
              "Tournament Information"
            ),
            card_body(
              class = "admin-form-body",

              # --- Tournament Details section ---
              div(class = "admin-form-section submit-form-inputs",
                div(class = "admin-form-section-label",
                  bsicons::bs_icon("calendar-event"),
                  "Tournament Details"
                ),
                layout_columns(
                  col_widths = breakpoints(sm = c(12, 12, 12), md = c(4, 4, 4)),
                  selectInput("submit_scene", "Scene",
                              choices = c("Loading..." = ""),
                              selectize = FALSE),
                  div(
                    selectInput("submit_store", "Store",
                                choices = c("Select scene first..." = ""),
                                selectize = FALSE),
                    actionLink("submit_request_store", "Store not listed? Request it",
                               class = "small text-primary")
                  ),
                  dateInput("submit_date", "Date", value = character(0))
                ),
                layout_columns(
                  col_widths = breakpoints(sm = c(6, 6, 6, 6), md = c(4, 4, 2, 2)),
                  selectInput("submit_event_type", "Event Type",
                              choices = c("Select..." = "", EVENT_TYPES),
                              selectize = FALSE),
                  selectInput("submit_format", "Format",
                              choices = c("Loading..." = ""),
                              selectize = FALSE),
                  numericInput("submit_players", "Total Players", value = 8, min = 2, max = 256),
                  numericInput("submit_rounds", "Total Rounds", value = 4, min = 1, max = 15)
                ),

                # Warning if tournament already exists for this store/date
                uiOutput("submit_duplicate_warning")
              ),

              # --- Upload section ---
              div(class = "admin-form-section",
                div(class = "admin-form-section-label",
                  bsicons::bs_icon("cloud-upload"),
                  "Upload Standings"
                ),
                div(
                  class = "d-flex align-items-start gap-3",
                  # Upload area - compact
                  div(
                    class = "upload-dropzone flex-shrink-0",
                    fileInput("submit_screenshots", NULL,
                              multiple = TRUE,
                              accept = c("image/png", "image/jpeg", "image/jpg", "image/webp",
                                         ".png", ".jpg", ".jpeg", ".webp",
                                         "text/csv", ".csv"),
                              placeholder = "No files selected",
                              buttonLabel = tags$span(bsicons::bs_icon("cloud-upload"), " Browse"))
                  ),
                  # Tips - compact inline
                  div(
                    class = "upload-tips small text-muted",
                    div(class = "mb-1 fw-semibold", bsicons::bs_icon("filetype-csv", class = "me-1"), "Bandai TCG+ CSV export (recommended)"),
                    div(class = "mb-1", bsicons::bs_icon("camera", class = "me-1"), "Or upload standings screenshots from Bandai TCG+"),
                    div(bsicons::bs_icon("images", class = "me-1"), "Multiple screenshots OK if standings span screens")
                  )
                ),

                # Image thumbnails preview
                uiOutput("submit_screenshot_preview")
              ),

              # Process button - right aligned
              div(
                class = "admin-form-actions justify-content-end",
                actionButton("submit_process_ocr", "Process Results",
                             class = "btn-primary",
                             icon = icon("arrow-right"))
              )
            )
          )
        ),

        # Step 2: Review & Edit Results (hidden initially)
        shinyjs::hidden(
          div(
            id = "submit_wizard_step2",

            # Summary banner
            uiOutput("submit_summary_banner"),

            # Instructions callout - prominent at top
            div(
              class = "alert alert-primary d-flex mb-3",
              bsicons::bs_icon("pencil-square", class = "me-2 flex-shrink-0", size = "1.2em"),
              div(
                tags$strong("Review and edit the extracted data"),
                tags$br(),
                tags$small("Check that player names and points are correct. ",
                           "Select a deck archetype for each player if known (optional). ",
                           "Click ", bsicons::bs_icon("x-circle"), " to reject a matched player and create them as new.")
              )
            ),

            # Player matching explanation
            div(
              class = "text-muted small mb-3",
              bsicons::bs_icon("people", class = "me-1"),
              "Players are matched by member number first, then by username. ",
              tags$strong("Matched"), " = existing player in database. ",
              tags$strong("New"), " = will be created on submit."
            ),

            # Match summary badges - prominent
            uiOutput("submit_match_summary"),

            # Results card
            card(
              class = "mt-3",
              card_header(
                class = "d-flex justify-content-between align-items-center",
                div(
                  class = "d-flex align-items-center gap-2",
                  span("Player Results"),
                  span(class = "badge bg-info", "Points mode")
                ),
                uiOutput("submit_filled_count", inline = TRUE)
              ),
              card_body(
                uiOutput("submit_results_table")
              )
            ),

            # Confirmation checkbox
            div(
              class = "mt-3",
              checkboxInput("submit_confirm",
                            "I confirm this data is accurate",
                            value = FALSE)
            ),

            # Navigation buttons
            div(
              class = "d-flex justify-content-between mt-3",
              actionButton("submit_back", "Back", class = "btn-secondary",
                           icon = icon("arrow-left")),
              actionButton("submit_tournament", "Submit Tournament",
                           class = "btn-primary btn-lg", icon = icon("check"))
            )
          )
        ),

        # Step 3: Decklist Links (hidden initially)
        shinyjs::hidden(
          div(
            id = "submit_wizard_step3",
            uiOutput("submit_decklist_summary_bar"),
            card(
              card_header(
                class = "d-flex justify-content-between align-items-center",
                span("Add Decklist Links"),
                span(class = "text-muted small", "Optional — paste external decklist URLs for any players")
              ),
              card_body(
                uiOutput("submit_decklist_table")
              )
            ),
            div(
              class = "d-flex justify-content-between mt-3",
              actionButton("submit_skip_decklists", "Skip", class = "btn-outline-secondary",
                           icon = icon("forward")),
              div(
                class = "d-flex gap-2",
                actionButton("submit_save_decklists", "Save Progress", class = "btn-primary",
                             icon = icon("floppy-disk")),
                actionButton("submit_done_decklists", "Done", class = "btn-success",
                             icon = icon("check"))
              )
            )
          )
        )
      )
    ),

    # Match History Tab
    nav_panel(
      title = tagList(bsicons::bs_icon("list-ol"), " Match History"),
      value = "match_history",

      div(
        class = "p-3",

        # Combined card for all match history input
        card(
          card_header(
            class = "d-flex align-items-center gap-2",
            bsicons::bs_icon("list-check"),
            "Submit Match History"
          ),
          card_body(
            class = "admin-form-body",

            # --- Tournament Selection section ---
            div(class = "admin-form-section",
              div(class = "admin-form-section-label",
                bsicons::bs_icon("trophy"),
                "Select Tournament"
              ),
              layout_columns(
                col_widths = breakpoints(sm = c(12, 12), md = c(6, 6)),
                selectInput("match_store", "Store",
                            choices = c("All stores" = ""),
                            selectize = FALSE),
                selectInput("match_tournament", "Tournament",
                            choices = c("Select a tournament..." = ""),
                            selectize = FALSE)
              ),
              uiOutput("match_tournament_info")
            ),

            # --- Player Info section ---
            div(class = "admin-form-section",
              div(class = "admin-form-section-label",
                bsicons::bs_icon("person-fill"),
                "Your Player Info"
              ),
              layout_columns(
                col_widths = breakpoints(sm = c(12, 12), md = c(6, 6)),
                div(
                  textInput("match_player_username", "Username",
                            placeholder = "e.g., HappyCat"),
                  div(id = "match_username_hint", class = "form-text text-danger d-none", "Required")
                ),
                div(
                  textInput("match_player_member", "Member Number",
                            placeholder = "e.g., 0000123456"),
                  div(id = "match_member_hint", class = "form-text text-danger d-none", "Required")
                )
              )
            ),

            # --- Screenshot section ---
            div(class = "admin-form-section",
              div(class = "admin-form-section-label",
                bsicons::bs_icon("camera"),
                "Match History Screenshot"
              ),
              div(
                class = "d-flex align-items-start gap-3",
                # Upload area - compact
                div(
                  class = "upload-dropzone flex-shrink-0",
                  fileInput("match_screenshots", NULL,
                            multiple = FALSE,
                            accept = c("image/png", "image/jpeg", "image/jpg", "image/webp", ".png", ".jpg", ".jpeg", ".webp"),
                            placeholder = "No file selected",
                            buttonLabel = tags$span(bsicons::bs_icon("cloud-upload"), " Browse"))
                ),
                # Tips - compact inline
                div(
                  class = "upload-tips small text-muted",
                  div(bsicons::bs_icon("info-circle", class = "me-1"), "Screenshot from Bandai TCG+ match history screen")
                )
              ),

              # Image thumbnail preview
              uiOutput("match_screenshot_preview")
            ),

            # Process button - right aligned
            div(
              class = "admin-form-actions justify-content-end",
              actionButton("match_process_ocr", "Process Screenshot",
                           class = "btn-primary",
                           icon = icon("magic"))
            )
          )
        ),

        # Match History Preview (shown after OCR)
        uiOutput("match_results_preview"),

        # Submit Button (shown after OCR)
        uiOutput("match_final_button")
      )
    )
  )
)
