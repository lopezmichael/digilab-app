# views/admin-players-ui.R
# Admin - Manage players UI

admin_players_ui <- tagList(
  div(
    class = "d-flex justify-content-between align-items-center mb-3",
    h2("Edit Players", class = "mb-0"),
    actionButton("show_merge_modal", "Merge Players",
                 class = "btn-outline-warning",
                 icon = icon("code-merge"))
  ),
  div(class = "page-help-text",
    div(class = "info-hint-box",
      bsicons::bs_icon("info-circle", class = "info-hint-icon"),
      "Select a player to edit their display name. Players are created automatically when tournament results are submitted."
    )
  ),
  # Scene filter indicator and override toggle for superadmins
  conditionalPanel(
    condition = "output.is_superadmin == true",
    div(
      class = "d-flex justify-content-end mb-2",
      checkboxInput("admin_players_show_all_scenes", "Show all scenes", value = FALSE)
    )
  ),
  uiOutput("admin_players_scene_indicator"),
  uiOutput("suggested_merges_section"),
  div(
    class = "admin-panel",
    layout_columns(
      col_widths = breakpoints(sm = c(12, 12), md = c(5, 7)),
      card(
        card_header(
          class = "d-flex justify-content-between align-items-center",
          span(id = "player_form_title", "Edit Player"),
          conditionalPanel(
            condition = "input.editing_player_id && input.editing_player_id != ''",
            actionButton("cancel_edit_player", "Cancel", class = "btn-sm btn-outline-secondary")
          )
        ),
        card_body(
          # Hidden field for edit mode
          textInput("editing_player_id", NULL, value = ""),
          tags$script("document.getElementById('editing_player_id').parentElement.style.display = 'none';"),

          p(class = "text-muted small", "Select a player from the list to edit or delete."),

          textInput("player_display_name", "Display Name", placeholder = "Enter player name..."),
          textInput("player_member_number", "Member Number", placeholder = "e.g. 0012345678"),

          hr(),

          # Player stats (read-only info)
          uiOutput("player_stats_info"),

          hr(),

          # Action buttons
          div(
            class = "d-flex gap-2",
            shinyjs::hidden(
              actionButton("update_player", "Update Player", class = "btn-success")
            ),
            shinyjs::hidden(
              actionButton("delete_player", "Delete Player", class = "btn-danger")
            )
          )
        )
      ),
      card(
        card_header(
          class = "d-flex justify-content-between align-items-center",
          "All Players",
          div(
            class = "d-flex align-items-center gap-2",
            textInput("player_search", NULL, placeholder = "Search players...",
                      width = "200px"),
            span(class = "small text-muted", "Click a row to edit")
          )
        ),
        card_body(
          reactableOutput("player_list")
        )
      )
    )
  )
)
