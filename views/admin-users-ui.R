# views/admin-users-ui.R
# Admin - Manage admin accounts UI (super admin only)

admin_users_ui <- tagList(
  h2("Manage Admins"),
  div(class = "page-help-text",
    div(class = "info-hint-box",
      bsicons::bs_icon("info-circle", class = "info-hint-icon"),
      "Add, edit, and deactivate admin accounts. Scene admins can only manage data for their assigned scene."
    )
  ),
  div(
    class = "admin-panel",
    layout_columns(
      col_widths = c(7, 5),
      fill = FALSE,

      # Admin list table
      card(
        card_header("Admin Accounts"),
        card_body(
          reactableOutput("admin_users_table")
        )
      ),

      # Add/Edit form
      card(
        card_header(
          class = "d-flex justify-content-between align-items-center",
          span(id = "admin_form_title", "Add Admin"),
          conditionalPanel(
            condition = "output.editing_admin == true",
            actionLink("clear_admin_form_btn", "Clear",
                        class = "btn btn-sm btn-outline-secondary")
          )
        ),
        card_body(
          textInput("admin_username", "Username", placeholder = "e.g., sarah"),
          textInput("admin_display_name", "Display Name", placeholder = "e.g., Sarah"),
          passwordInput("admin_password", "Password"),
          tags$p(class = "form-text text-muted", id = "password_hint",
                 "Leave blank when editing to keep existing password."),
          selectInput("admin_role", "Role",
                      choices = c("Scene Admin" = "scene_admin",
                                  "Super Admin" = "super_admin"),
                      selected = "scene_admin",
                      selectize = FALSE),
          conditionalPanel(
            condition = "input.admin_role == 'scene_admin'",
            selectInput("admin_scene", "Assigned Scene",
                        choices = list("Select scene..." = ""),
                        selectize = FALSE)
          ),
          div(
            class = "d-flex gap-2 mt-3",
            actionButton("save_admin_btn", "Save", class = "btn-primary"),
            conditionalPanel(
              condition = "output.editing_admin == true",
              actionButton("toggle_admin_active_btn", "Deactivate",
                          class = "btn-outline-danger btn-sm")
            )
          )
        )
      )
    )
  )
)
