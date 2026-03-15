# views/admin-tournaments-ui.R
# Admin - Manage tournaments UI

admin_tournaments_ui <- tagList(
  uiOutput("pending_data_errors"),
  h2("Edit Tournaments"),
  div(class = "page-help-text",
    div(class = "info-hint-box",
      bsicons::bs_icon("info-circle", class = "info-hint-icon"),
      "Select a tournament from the list to edit details or manage results. Use 'View/Edit Results' to open the results grid for bulk editing."
    )
  ),
  # Scene filter indicator and override toggle for superadmins
  conditionalPanel(
    condition = "output.is_superadmin == true",
    div(
      class = "d-flex justify-content-end mb-2",
      checkboxInput("admin_tournaments_show_all_scenes", "Show all scenes", value = FALSE)
    )
  ),
  uiOutput("admin_tournaments_scene_indicator"),
  div(
    id = "edit_tournaments_main",
    class = "admin-panel",
    layout_columns(
      col_widths = breakpoints(sm = c(12, 12), md = c(5, 7)),
      card(
        card_header(
          class = "d-flex justify-content-between align-items-center",
          span(id = "tournament_form_title", "Edit Tournament"),
          conditionalPanel(
            condition = "input.editing_tournament_id && input.editing_tournament_id != ''",
            actionButton("cancel_edit_tournament", "Cancel", class = "btn-sm btn-outline-secondary")
          )
        ),
        card_body(
          class = "admin-form-body",
          # Hidden field for edit mode
          hidden_edit_field("editing_tournament_id"),

          p(class = "text-muted small", "Select a tournament from the list to edit or delete."),

          # --- Event Details section ---
          admin_section("calendar-event", "Event Details",
            selectInput("edit_tournament_store", tags$span("Store", tags$span(class = "required-indicator", "*")), choices = NULL),
            dateInput("edit_tournament_date", tags$span("Date", tags$span(class = "required-indicator", "*")), value = Sys.Date()),
            layout_columns(
              col_widths = breakpoints(sm = c(12, 12), md = c(6, 6)),
              selectInput("edit_tournament_type", "Event Type",
                          choices = c("Select event type..." = "", EVENT_TYPES)),
              selectInput("edit_tournament_format", tags$span("Format/Set", tags$span(class = "required-indicator", "*")), choices = list("Loading..." = ""))
            )
          ),

          # --- Size section ---
          admin_section("people-fill", "Size",
            layout_columns(
              col_widths = breakpoints(sm = c(12, 12), md = c(6, 6)),
              numericInput("edit_tournament_players", "Number of Players", value = 8, min = 2),
              numericInput("edit_tournament_rounds", "Number of Rounds", value = 3, min = 1)
            )
          ),

          # --- Stats section ---
          admin_section("bar-chart-fill", "Stats",
            uiOutput("tournament_stats_info"),
            # View/Edit Results button (only shown when tournament selected)
            shinyjs::hidden(
              div(
                id = "view_results_btn_container",
                class = "mt-3",
                actionButton("view_edit_results", "View/Edit Results",
                             class = "btn-primary w-100",
                             icon = icon("list-check"))
              )
            )
          ),

          # --- Action buttons ---
          div(
            class = "admin-form-actions",
            shinyjs::hidden(
              actionButton("update_tournament", "Update Tournament", class = "btn-success")
            ),
            shinyjs::hidden(
              actionButton("delete_tournament", "Delete Tournament", class = "btn-danger")
            )
          )
        )
      ),
      card(
        card_header(
          class = "d-flex justify-content-between align-items-center",
          "All Tournaments",
          div(
            class = "d-flex align-items-center gap-2",
            textInput("admin_tournament_search", NULL, placeholder = "Search...",
                      width = "150px"),
            span(class = "small text-muted", "Click a row to edit")
          )
        ),
        card_body(
          reactableOutput("admin_tournament_list")
        )
      )
    )
  ),
  # Edit Results Grid (hidden initially, shown when View/Edit Results is clicked)
  shinyjs::hidden(
    div(
      id = "edit_results_grid_section",
      class = "admin-panel mt-3",

      # Tournament summary bar
      uiOutput("edit_grid_summary_bar"),

      card(
        card_header(
          class = "d-flex justify-content-between align-items-center",
          div(
            class = "d-flex align-items-center gap-2",
            span("Edit Results"),
            uiOutput("edit_record_format_badge", inline = TRUE)
          ),
          div(
            class = "d-flex align-items-center gap-2",
            uiOutput("edit_filled_count", inline = TRUE),
            actionButton("edit_paste_btn", "Paste from Spreadsheet",
                         class = "btn-sm btn-outline-primary",
                         icon = icon("clipboard"))
          )
        ),
        card_body(
          uiOutput("edit_grid_table")
        )
      ),

      # Bottom navigation
      div(
        class = "d-flex justify-content-between mt-3",
        actionButton("edit_grid_cancel", "Cancel", class = "btn-secondary",
                     icon = icon("xmark")),
        actionButton("edit_grid_save", "Save Changes", class = "btn-primary btn-lg",
                     icon = icon("check"))
      )
    )
  ),

  # Edit Decklist Links (hidden initially, shown after saving results)
  shinyjs::hidden(
    div(
      id = "edit_decklist_section",
      class = "admin-panel mt-3",
      uiOutput("edit_decklist_summary_bar"),
      card(
        card_header(
          class = "d-flex justify-content-between align-items-center",
          span("Add Decklist Links"),
          span(class = "text-muted small", "Optional — paste external decklist URLs for any players")
        ),
        card_body(
          uiOutput("edit_decklist_table")
        )
      ),
      div(
        class = "d-flex justify-content-between mt-3",
        actionButton("edit_decklist_skip", "Skip", class = "btn-outline-secondary",
                     icon = icon("forward")),
        div(
          class = "d-flex gap-2",
          actionButton("edit_decklist_save", "Save Progress", class = "btn-primary",
                       icon = icon("floppy-disk")),
          actionButton("edit_decklist_done", "Done", class = "btn-success",
                       icon = icon("check"))
        )
      )
    )
  )
)
