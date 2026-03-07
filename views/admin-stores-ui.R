# views/admin-stores-ui.R
# Admin - Manage stores UI

admin_stores_ui <- tagList(
  uiOutput("pending_store_requests"),
  h2("Edit Stores"),
  # Scene filter indicator and override toggle for superadmins
  conditionalPanel(
    condition = "output.is_superadmin == true",
    div(
      class = "d-flex justify-content-end mb-2",
      checkboxInput("admin_stores_show_all_scenes", "Show all scenes", value = FALSE)
    )
  ),
  uiOutput("admin_stores_scene_indicator"),
  div(class = "page-help-text",
    div(class = "info-hint-box",
      bsicons::bs_icon("info-circle", class = "info-hint-icon"),
      "Manage store locations and schedules. Check 'Online' for virtual organizers without a physical address."
    )
  ),
  div(
    class = "admin-panel",
    layout_columns(
      col_widths = breakpoints(sm = c(12, 12), md = c(6, 6)),
      card(
        card_header(
          class = "d-flex justify-content-between align-items-center",
          span(id = "store_form_title", "Add New Store"),
          conditionalPanel(
            condition = "input.editing_store_id && input.editing_store_id != ''",
            actionButton("cancel_edit_store", "Cancel Edit", class = "btn-sm btn-outline-secondary")
          )
        ),
        card_body(
          # Hidden field for edit mode
          textInput("editing_store_id", NULL, value = ""),
          tags$script("document.getElementById('editing_store_id').parentElement.style.display = 'none';"),

          checkboxInput("store_is_online", "Online store (no physical location)", value = FALSE),

          # Physical store fields (shown when checkbox unchecked)
          conditionalPanel(
            condition = "!input.store_is_online",
            textInput("store_name", "Store Name"),
            selectInput("store_country_physical", "Country",
              choices = COUNTRY_CHOICES,
              selected = "USA"
            ),
            textInput("store_address", "Street Address"),
            layout_columns(
              col_widths = breakpoints(sm = c(12, 12, 12), md = c(5, 4, 3)),
              textInput("store_city", "City"),
              textInput("store_state", "State / Province"),
              textInput("store_zip", "Postal Code")
            )
          ),

          # Online store fields (shown when checkbox checked)
          conditionalPanel(
            condition = "input.store_is_online",
            textInput("store_name_online", "Store/Organizer Name"),
            selectInput("store_country", "Country",
              choices = COUNTRY_CHOICES,
              selected = "USA"
            ),
            textInput("store_region", "Region/Coverage (optional)", placeholder = "e.g., DC/MD/VA, Texas, Global")
          ),

          # Common fields for both
          selectInput("store_scene", "Scene",
            choices = c("Select scene..." = ""),
            selectize = FALSE
          ),
          textInput("store_website", "Website (optional)"),

          # Geocode message only for physical stores
          conditionalPanel(
            condition = "!input.store_is_online",
            div(
              class = "text-muted small mb-2",
              bsicons::bs_icon("geo-alt"), " Map coordinates will be set automatically from the address"
            )
          ),

          # Schedule management section (for physical stores - both new and editing)
          conditionalPanel(
            condition = "!input.store_is_online",
            hr(),
            h5("Regular Schedule"),
            # Show existing schedules when editing
            conditionalPanel(
              condition = "input.editing_store_id && input.editing_store_id != ''",
              p(class = "text-muted small", "Click a schedule to delete it"),
              reactableOutput("store_schedules_table")
            ),
            # Show pending schedules when adding new store
            conditionalPanel(
              condition = "!input.editing_store_id || input.editing_store_id == ''",
              uiOutput("pending_schedules_display")
            ),
            div(
              class = "mt-3",
              layout_columns(
                col_widths = breakpoints(sm = c(6, 6, 6, 6), md = c(4, 3, 3, 2)),
                selectInput(
                  "schedule_day", "Day",
                  choices = list(
                    "Sunday" = "0",
                    "Monday" = "1",
                    "Tuesday" = "2",
                    "Wednesday" = "3",
                    "Thursday" = "4",
                    "Friday" = "5",
                    "Saturday" = "6"
                  ),
                  selected = "1",
                  selectize = FALSE
                ),
                textInput(
                  "schedule_time", "Time",
                  value = "19:00",
                  placeholder = "HH:MM (e.g., 19:00)"
                ),
                selectInput(
                  "schedule_frequency", "Frequency",
                  choices = list(
                    "Weekly" = "weekly",
                    "Biweekly" = "biweekly",
                    "Monthly" = "monthly"
                  ),
                  selected = "weekly",
                  selectize = FALSE
                ),
                div(
                  class = "d-flex align-items-end h-100",
                  actionButton("add_schedule", "Add", class = "btn-outline-primary btn-sm")
                )
              ),
              # Conditional qualifier inputs for biweekly/monthly
              conditionalPanel(
                condition = "input.schedule_frequency == 'monthly'",
                selectInput("schedule_week_of_month", "Week of Month",
                  choices = list(
                    "1st" = "1st", "2nd" = "2nd", "3rd" = "3rd",
                    "4th" = "4th", "Last" = "last"
                  ),
                  selected = "1st",
                  selectize = FALSE
                )
              ),
              conditionalPanel(
                condition = "input.schedule_frequency == 'biweekly'",
                dateInput("schedule_next_occurrence", "Next Occurrence",
                  value = Sys.Date())
              )
            )
          ),

          hr(),
          div(
            class = "d-flex gap-2",
            actionButton("add_store", "Add Store", class = "btn-primary"),
            actionButton("update_store", "Update Store", class = "btn-success", style = "display: none;"),
            actionButton("delete_store", "Delete Store", class = "btn-danger", style = "display: none;")
          )
        )
      ),
      card(
        card_header(
          class = "d-flex justify-content-between align-items-center",
          "Current Stores",
          div(
            class = "d-flex align-items-center gap-3",
            span(class = "small text-muted", "Click to edit"),
            div(
              class = "d-flex align-items-center gap-2 small",
              span(
                style = "width: 12px; height: 12px; background: rgba(245, 183, 0, 0.3); border-left: 2px solid #F5B700; display: inline-block;",
                title = "Missing schedule or ZIP"
              ),
              span(class = "text-muted", "Incomplete")
            )
          )
        ),
        card_body(
          reactableOutput("admin_store_list")
        )
      )
    )
  )
)
