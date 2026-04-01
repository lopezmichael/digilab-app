# views/submit-results-ui.R
# Unified Submit Results tab UI — card picker landing + shared 3-step wizard

submit_results_ui <- tagList(
  # Title strip
  div(
    class = "page-title-strip mb-3",
    div(
      class = "title-strip-content",
      div(
        class = "title-strip-context",
        bsicons::bs_icon("cloud-upload", class = "title-strip-icon"),
        tags$span(class = "title-strip-text", "Submit Results")
      ),
      div(
        class = "title-strip-controls",
        span(class = "small text-muted", "Add tournament data via upload, manual entry, or match history")
      )
    )
  ),

  # =========================================================================
  # Card Picker Landing Page (id = "sr_method_picker")
  # =========================================================================
  div(
    id = "sr_method_picker",

    div(
      class = "sr-card-picker",

      # Row 1 (both): Bandai TCG+ Upload
      actionButton("sr_card_upload", NULL, class = "sr-method-card",
        div(
          class = "sr-method-card-inner",
          bsicons::bs_icon("cloud-upload", size = "2rem", class = "sr-card-icon text-primary"),
          div(class = "sr-card-title", "Bandai TCG+ Upload"),
          div(class = "sr-card-desc", "Upload standings screenshots or CSV exports from Bandai TCG+"),
          tags$small(class = "sr-card-help text-muted", "TOs can export standings CSV from the Bandai TCG+ platform after the event")
        )
      ),

      # Row 1 admin / Row 1 public: Manual Entry (admin) or Match-by-Match (public)
      # Admin only: Manual Entry (grid + paste)
      conditionalPanel(
        condition = "output.is_admin",
        actionButton("sr_card_grid_entry", NULL, class = "sr-method-card",
          div(
            class = "sr-method-card-inner",
            bsicons::bs_icon("pencil-square", size = "2rem", class = "sr-card-icon text-primary"),
            div(class = "sr-card-title", "Manual Entry"),
            div(class = "sr-card-desc", "Type results into an editable grid or paste tab-separated data from a spreadsheet"),
            tags$small(class = "sr-card-help text-muted", "Supports names-only, names+points, names+W/L/T, and more")
          )
        )
      ),

      # Row 1 public / Row 2 admin: Match-by-Match (everyone)
      actionButton("sr_card_match", NULL, class = "sr-method-card",
        div(
          class = "sr-method-card-inner",
          bsicons::bs_icon("list-ol", size = "2rem", class = "sr-card-icon text-primary"),
          div(class = "sr-card-title", "Match-by-Match"),
          div(class = "sr-card-desc", "Look up your tournaments and add round-by-round match results"),
          tags$small(class = "sr-card-help text-muted", "Upload a match history screenshot or fill in results manually")
        )
      ),

      # Row 2 admin: Coming Soon — Match-by-Match Batch Upload
      conditionalPanel(
        condition = "output.is_admin",
        div(class = "sr-method-card sr-method-card--coming-soon",
          div(
            class = "sr-method-card-inner",
            bsicons::bs_icon("filetype-csv", size = "2rem", class = "sr-card-icon"),
            div(class = "sr-card-title", "Full Match Import"),
            div(class = "sr-card-desc", "Upload round-by-round results for all players from a single CSV file"),
            tags$strong(class = "sr-card-coming-soon-label", "COMING SOON")
          )
        )
      ),

      # Row 2 public / Row 3 admin: Add Decklists (everyone, centered when solo)
      actionButton("sr_card_decklist", NULL, class = "sr-method-card",
        div(
          class = "sr-method-card-inner",
          bsicons::bs_icon("link-45deg", size = "2rem", class = "sr-card-icon text-primary"),
          div(class = "sr-card-title", "Add Decklists"),
          div(class = "sr-card-desc", "Link your decklists to tournaments you've played in"),
          tags$small(class = "sr-card-help text-muted", "Look up your tournaments by Bandai Member ID")
        )
      )
    )
  ),

  # =========================================================================
  # Shared Wizard (id = "sr_wizard", hidden initially)
  # For Upload, Paste, and Manual entry methods
  # =========================================================================
  shinyjs::hidden(
    div(
      id = "sr_wizard",

      # Back to picker button
      div(
        class = "mb-3",
        actionButton("sr_back_to_picker", tagList(bsicons::bs_icon("arrow-left"), " Back"),
                     class = "btn-sm btn-outline-secondary")
      ),

      # Wizard step indicator
      div(
        class = "wizard-steps d-flex gap-3 mb-4",
        div(
          id = "sr_step1_indicator",
          class = "wizard-step active",
          span(class = "step-number", "1"),
          span(class = "step-label", "Tournament Details")
        ),
        div(
          id = "sr_step2_indicator",
          class = "wizard-step",
          span(class = "step-number", "2"),
          span(class = "step-label", "Add Results")
        ),
        div(
          id = "sr_step3_indicator",
          class = "wizard-step",
          span(class = "step-number", "3"),
          span(class = "step-label", "Decklists")
        )
      ),

      # Step 1: Tournament Details (shared across upload/paste/manual)
      div(
        id = "sr_step1",
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
                selectInput("sr_scene", tags$span("Scene", tags$span(class = "required-indicator", "*")),
                            choices = c("Loading..." = ""),
                            selectize = FALSE),
                div(
                  selectInput("sr_store", tags$span("Store", tags$span(class = "required-indicator", "*")),
                              choices = c("Select scene first..." = ""),
                              selectize = FALSE),
                  actionLink("sr_request_store", "Store not listed? Request it",
                             class = "small text-primary")
                ),
                div(
                  class = "date-required",
                  dateInput("sr_date", tags$span("Date", tags$span(class = "required-indicator", "*")),
                            value = character(0)),
                  div(id = "sr_date_required_hint", class = "date-required-hint", "Required")
                )
              ),
              layout_columns(
                col_widths = breakpoints(sm = c(6, 6, 6, 6), md = c(4, 4, 2, 2)),
                selectInput("sr_event_type", tags$span("Event Type", tags$span(class = "required-indicator", "*")),
                            choices = c("Select..." = "", EVENT_TYPES),
                            selectize = FALSE),
                selectInput("sr_format", tags$span("Format", tags$span(class = "required-indicator", "*")),
                            choices = c("Loading..." = ""),
                            selectize = FALSE),
                numericInput("sr_players", "Total Players", value = 8, min = 2, max = 256),
                numericInput("sr_rounds", "Total Rounds", value = 4, min = 1, max = 15)
              ),

              # Record format (admin only)
              conditionalPanel(
                condition = "output.is_admin",
                div(
                  class = "row g-3",
                  div(class = "col-12 col-md-6",
                    radioButtons("sr_record_format", "Record Format",
                                 choices = c("Points" = "points", "W-L-T" = "wlt"),
                                 selected = "points", inline = TRUE),
                    tags$small(class = "form-text text-muted",
                      "Points: Total match points (e.g., from Bandai TCG+ standings). ",
                      "W-L-T: Individual wins, losses, and ties.")
                  )
                )
              ),

              # Duplicate warning
              uiOutput("sr_duplicate_warning")
            ),

            # --- Upload section (shown only for upload method) ---
            shinyjs::hidden(
              div(
                id = "sr_upload_section",
                class = "admin-form-section",
                div(class = "admin-form-section-label",
                  bsicons::bs_icon("cloud-upload"),
                  "Upload Standings"
                ),
                div(
                  class = "d-flex align-items-start gap-3",
                  div(
                    class = "upload-dropzone flex-shrink-0",
                    fileInput("sr_screenshots", NULL,
                              multiple = TRUE,
                              accept = c("image/png", "image/jpeg", "image/jpg", "image/webp",
                                         ".png", ".jpg", ".jpeg", ".webp",
                                         "text/csv", ".csv"),
                              placeholder = "No files selected",
                              buttonLabel = tags$span(bsicons::bs_icon("cloud-upload"), " Browse"))
                  ),
                  div(
                    class = "upload-tips small text-muted",
                    div(class = "mb-1 fw-semibold", bsicons::bs_icon("filetype-csv", class = "me-1"), "Bandai TCG+ CSV export (recommended)"),
                    div(class = "mb-1", bsicons::bs_icon("camera", class = "me-1"), "Or upload standings screenshots from Bandai TCG+"),
                    div(bsicons::bs_icon("images", class = "me-1"), "Multiple screenshots OK if standings span screens")
                  )
                ),

                # Image thumbnails preview
                uiOutput("sr_screenshot_preview")
              )
            ),

            # Process/Create button
            div(
              class = "admin-form-actions justify-content-end",
              actionButton("sr_step1_next", "Continue",
                           class = "btn-primary btn-lg",
                           icon = icon("arrow-right"))
            )
          )
        )
      ),

      # Step 2: Results Entry (method-specific, hidden initially)
      shinyjs::hidden(
        div(
          id = "sr_step2",
          uiOutput("sr_step2_content")
        )
      ),

      # Step 3: Decklists (hidden initially)
      shinyjs::hidden(
        div(
          id = "sr_step3",
          uiOutput("sr_decklist_summary_bar"),
          card(
            card_header(
              class = "d-flex justify-content-between align-items-center",
              span("Add Decklist Links"),
              span(class = "text-muted small", "Optional — paste external decklist URLs for any players")
            ),
            card_body(
              uiOutput("sr_decklist_table")
            )
          ),
          div(
            class = "d-flex justify-content-between mt-3",
            actionButton("sr_skip_decklists", "Skip", class = "btn-outline-secondary",
                         icon = icon("forward")),
            div(
              class = "d-flex gap-2",
              actionButton("sr_save_decklists", "Save Progress", class = "btn-primary",
                           icon = icon("floppy-disk")),
              actionButton("sr_done_decklists", "Done", class = "btn-success",
                           icon = icon("check"))
            )
          )
        )
      )
    )
  ),

  # =========================================================================
  # Match-by-Match Section (separate flow, hidden initially)
  # Bandai ID lookup → tournament history → upload screenshot → review → submit
  # =========================================================================
  shinyjs::hidden(
    div(
      id = "sr_match_section",

      # Back to picker
      div(
        class = "mb-3",
        actionButton("sr_match_back_to_picker", tagList(bsicons::bs_icon("arrow-left"), " Back"),
                     class = "btn-sm btn-outline-secondary")
      ),

      # Wizard step indicator (2 steps)
      div(
        class = "wizard-steps d-flex gap-3 mb-4",
        div(
          id = "sr_match_step1_indicator",
          class = "wizard-step active",
          span(class = "step-number", "1"),
          span(class = "step-label", "Upload Screenshot")
        ),
        div(
          id = "sr_match_step2_indicator",
          class = "wizard-step",
          span(class = "step-number", "2"),
          span(class = "step-label", "Review & Submit")
        )
      ),

      # Step 1: Player lookup → tournament selection → screenshot upload
      div(
        id = "sr_match_step1",

        # --- Player lookup card (always visible) ---
        card(
          card_header(
            class = "d-flex align-items-center gap-2",
            bsicons::bs_icon("list-ol"),
            "Match-by-Match Results"
          ),
          card_body(
            class = "admin-form-body",

            # --- Bandai ID lookup ---
            div(class = "admin-form-section",
              div(class = "admin-form-section-label",
                bsicons::bs_icon("person-badge"),
                "Player Lookup"
              ),
              div(
                class = "sr-lookup-row",
                textInput("sr_match_member_id", NULL,
                          placeholder = "e.g., 0000123456"),
                actionButton("sr_match_lookup", "Look Up",
                             class = "btn-primary",
                             icon = icon("search"))
              ),
              tags$small(class = "sr-form-hint",
                         "Enter your Bandai TCG+ Member Number to find your tournaments")
            ),

            # --- Player info (rendered after lookup) ---
            uiOutput("sr_match_player_info")
          )
        ),

        # --- Side-by-side: Tournament list + Upload panel (hidden until lookup) ---
        uiOutput("sr_match_split_panel")
      ),

      # Step 2: Review & submit (hidden initially)
      shinyjs::hidden(
        div(
          id = "sr_match_step2",
          uiOutput("sr_match_results_preview"),
          uiOutput("sr_match_final_button")
        )
      )
    )
  ),

  # =========================================================================
  # Add Decklists Section (standalone flow, hidden initially)
  # =========================================================================
  shinyjs::hidden(
    div(
      id = "sr_decklist_standalone",

      # Back to picker
      div(
        class = "mb-3",
        actionButton("sr_decklist_back_to_picker", tagList(bsicons::bs_icon("arrow-left"), " Back"),
                     class = "btn-sm btn-outline-secondary")
      ),

      card(
        card_header(
          class = "d-flex align-items-center gap-2",
          bsicons::bs_icon("link-45deg"),
          "Add Decklists"
        ),
        card_body(
          class = "admin-form-body",

          # --- Bandai ID lookup ---
          div(class = "admin-form-section",
            div(class = "admin-form-section-label",
              bsicons::bs_icon("person-badge"),
              "Player Lookup"
            ),
            div(
              class = "sr-lookup-row",
              textInput("sr_decklist_member_id", NULL,
                        placeholder = "e.g., 0000123456"),
              actionButton("sr_decklist_lookup", "Look Up",
                           class = "btn-primary",
                           icon = icon("search"))
            ),
            tags$small(class = "sr-form-hint",
                       "Enter your Bandai TCG+ Member Number to find your tournaments")
          ),

          # --- Tournament history (populated after lookup) ---
          uiOutput("sr_decklist_player_info"),
          uiOutput("sr_decklist_tournament_history"),
          uiOutput("sr_decklist_entry_form")
        )
      )
    )
  )
)
