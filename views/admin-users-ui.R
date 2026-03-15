# views/admin-users-ui.R
# Admin - Manage admin accounts UI (super admin only)

admin_users_ui <- tagList(
  h2("Manage Admins"),
  div(class = "page-help-text",
    div(class = "info-hint-box",
      bsicons::bs_icon("info-circle", class = "info-hint-icon"),
      "Add, edit, and deactivate admin accounts. Scene admins manage their assigned scene. Regional admins inherit coverage over all scenes in their assigned countries/states."
    )
  ),
  div(
    class = "admin-panel",
    layout_columns(
      col_widths = breakpoints(sm = c(12, 12), md = c(7, 5)),
      fill = FALSE,

      # Admin list — scene-centric tree view
      card(
        card_header(
          class = "d-flex justify-content-between align-items-center",
          "Admin Accounts",
          div(
            class = "d-flex align-items-center gap-2",
            selectInput("admin_users_scene_filter", NULL,
              choices = c("All Scenes" = "all"),
              selected = "all",
              selectize = FALSE,
              width = "160px"
            )
          )
        ),
        card_body(
          class = "p-0",
          uiOutput("admin_users_grouped")
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
          class = "admin-form-body",

          # --- Identity section ---
          div(class = "admin-form-section",
            div(class = "admin-form-section-label",
              bsicons::bs_icon("person-fill"),
              "Identity"
            ),
            textInput("admin_username", "Username", placeholder = "e.g., sarah"),
            div(class = "admin-form-discord-group",
              tags$label("Discord User ID", class = "form-label",
                `for` = "admin_discord_id"),
              div(class = "admin-form-discord-input",
                span(class = "admin-form-input-icon",
                  bsicons::bs_icon("discord")
                ),
                tags$input(
                  id = "admin_discord_id",
                  type = "text",
                  class = "form-control shiny-input-text admin-form-discord-field",
                  placeholder = "123456789012345678"
                )
              ),
              tags$small(class = "form-text text-muted",
                "Right-click user in Discord → Copy User ID"
              )
            )
          ),

          # --- Authentication section ---
          div(class = "admin-form-section",
            div(class = "admin-form-section-label",
              bsicons::bs_icon("key-fill"),
              "Authentication"
            ),
            div(class = "admin-form-password-group",
              div(class = "admin-form-password-header",
                tags$label("Password", class = "form-label mb-0",
                  `for` = "admin_password"),
                actionLink("generate_password_btn", "Generate",
                  class = "admin-form-generate-btn")
              ),
              passwordInput("admin_password", NULL),
              tags$small(class = "form-text text-muted", id = "password_hint",
                "Leave blank when editing to keep existing password."
              )
            )
          ),

          # --- Assignment section ---
          div(class = "admin-form-section",
            div(class = "admin-form-section-label",
              bsicons::bs_icon("shield-fill"),
              "Assignment"
            ),
            selectInput("admin_role", "Role",
                        choices = c("Scene Admin" = "scene_admin",
                                    "Regional Admin" = "regional_admin",
                                    "Super Admin" = "super_admin"),
                        selected = "scene_admin",
                        selectize = FALSE),
            div(class = "admin-form-role-hint",
              id = "admin_role_hint",
              conditionalPanel(
                condition = "input.admin_role == 'scene_admin'",
                span("Manages data for a single assigned scene.")
              ),
              conditionalPanel(
                condition = "input.admin_role == 'regional_admin'",
                span("Inherits admin access for all scenes in selected regions.")
              ),
              conditionalPanel(
                condition = "input.admin_role == 'super_admin'",
                span("Full access to all scenes and admin settings.")
              )
            ),
            conditionalPanel(
              condition = "input.admin_role == 'scene_admin'",
              selectInput("admin_scene", "Assigned Scene",
                          choices = list("Select scene..." = ""),
                          selectize = FALSE)
            ),
            conditionalPanel(
              condition = "input.admin_role == 'regional_admin'",
              uiOutput("admin_region_selector")
            )
          ),

          # --- Action buttons ---
          div(class = "admin-form-actions",
            actionButton("save_admin_btn", "Save Admin", class = "btn-primary"),
            conditionalPanel(
              condition = "output.editing_admin == true",
              actionButton("toggle_admin_active_btn", "Deactivate",
                          class = "btn-outline-danger btn-sm")
            )
          )
        )
      )
    )
  ),
  uiOutput("welcome_dm_area")
)
