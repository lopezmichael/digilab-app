# views/admin-scenes-ui.R
# Admin - Manage scenes UI (super admin only)

admin_scenes_ui <- tagList(
  h2("Manage Scenes"),
  div(class = "page-help-text",
    div(class = "info-hint-box",
      bsicons::bs_icon("info-circle", class = "info-hint-icon"),
      "Add and edit scenes (metro areas and online). Scenes organize stores and filter data across all tabs."
    )
  ),
  div(
    class = "admin-panel",
    layout_columns(
      col_widths = breakpoints(sm = c(12, 12), md = c(5, 7)),
      fill = FALSE,

      # Add/Edit form
      card(
        card_header(
          class = "d-flex justify-content-between align-items-center",
          span(id = "scene_form_title", "Add Scene"),
          conditionalPanel(
            condition = "output.editing_scene == true",
            actionLink("clear_scene_form_btn", "Clear",
                        class = "btn btn-sm btn-outline-secondary")
          )
        ),
        card_body(
          textInput("scene_display_name", "Display Name",
                    placeholder = "e.g., Ohio (Cincinnati Area)"),
          tags$small(class = "form-text text-muted d-block mt-n2 mb-2",
                     "Format: Country/State (City/Region)"),
          textInput("scene_slug", "URL Slug",
                    placeholder = "e.g., houston"),
          tags$small(class = "form-text text-muted d-block mt-n2 mb-2",
                     "Lowercase, no spaces. Used in URLs like ?scene=houston"),
          selectInput("scene_type", "Type",
                      choices = c("Metro Area" = "metro",
                                  "Online" = "online"),
                      selected = "metro",
                      selectize = FALSE),
          conditionalPanel(
            condition = "input.scene_type == 'metro'",
            textInput("scene_location", "Location",
                      placeholder = "e.g., Houston, TX"),
            div(
              class = "text-muted small mb-2",
              bsicons::bs_icon("geo-alt"),
              " Map coordinates will be set automatically from the location"
            )
          ),
          checkboxInput("scene_is_active", "Active", value = TRUE),
          textInput("scene_discord_thread_id", "Discord Thread ID",
                    placeholder = "e.g., 1234567890"),
          tags$small(class = "form-text text-muted d-block mt-n2 mb-2",
                     "Thread ID from #scene-coordination (right-click thread \u2192 Copy Link \u2192 number at end)"),
          div(
            class = "d-flex gap-2 mt-3",
            actionButton("save_scene_btn", "Save", class = "btn-primary"),
            conditionalPanel(
              condition = "output.editing_scene == true",
              actionButton("delete_scene_btn", "Delete",
                          class = "btn-outline-danger btn-sm")
            )
          )
        )
      ),

      # Scenes list + associated stores
      card(
        card_header(
          class = "d-flex justify-content-between align-items-center",
          "Scenes",
          span(class = "small text-muted", "Click a row to edit")
        ),
        card_body(
          reactableOutput("admin_scenes_table"),
          tags$hr(class = "my-3"),
          tags$h6("Stores in Selected Scene"),
          div(
            class = "d-flex gap-2",
            style = "min-height: 250px;",
            div(
              style = "flex: 1; min-width: 0;",
              uiOutput("scene_map_container")
            ),
            div(
              style = "width: 160px; flex-shrink: 0; overflow-y: auto; max-height: 250px;",
              uiOutput("scene_stores_legend")
            )
          )
        )
      )
    )
  )
)
