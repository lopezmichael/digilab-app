# views/admin-formats-ui.R
# Admin - Manage formats UI

admin_formats_ui <- tagList(
  h2("Edit Formats"),
  div(class = "page-help-text",
    div(class = "info-hint-box",
      bsicons::bs_icon("info-circle", class = "info-hint-icon"),
      "Add card sets and formats. Tournaments reference these for filtering by era."
    )
  ),
  div(
    class = "admin-panel",
    layout_columns(
      col_widths = breakpoints(sm = c(12, 12), md = c(5, 7)),
      card(
        card_header(
          class = "d-flex justify-content-between align-items-center",
          span(id = "format_form_title", "Add New Format"),
          conditionalPanel(
            condition = "input.editing_format_id && input.editing_format_id != ''",
            actionButton("cancel_edit_format", "Cancel Edit", class = "btn-sm btn-outline-secondary")
          )
        ),
        card_body(
          class = "admin-form-body",
          # Hidden field for edit mode (stores the original format_id being edited)
          textInput("editing_format_id", NULL, value = ""),
          tags$script("document.getElementById('editing_format_id').parentElement.style.display = 'none';"),

          # --- Format Info section ---
          div(class = "admin-form-section",
            div(class = "admin-form-section-label",
              bsicons::bs_icon("collection-fill"),
              "Format Info"
            ),
            textInput("format_id", "Set Code", placeholder = "e.g., BT20, EX09"),
            textInput("format_set_name", "Set Name", placeholder = "e.g., Xros Encounter"),
            dateInput("format_release_date", "Release Date", value = Sys.Date()),
            checkboxInput("format_is_active", "Active", value = TRUE),
            tags$small(class = "form-text text-muted d-block mt-n2 mb-2",
              "Formats are sorted by release date (most recent first)")
          ),

          # --- Action buttons ---
          div(
            class = "admin-form-actions",
            actionButton("add_format", "Add Format", class = "btn-primary"),
            actionButton("update_format", "Update Format", class = "btn-success", style = "display: none;"),
            actionButton("delete_format", "Delete Format", class = "btn-danger", style = "display: none;")
          )
        )
      ),
      card(
        card_header(
          class = "d-flex justify-content-between align-items-center",
          "Current Formats",
          span(class = "small text-muted", "Click a row to edit")
        ),
        card_body(
          reactableOutput("admin_format_list")
        )
      )
    )
  )
)
