# =============================================================================
# Admin Users Server - Manage admin accounts (super admin only)
# =============================================================================

# Editing state
editing_admin_id <- reactiveVal(NULL)

# Output for conditional panels
output$editing_admin <- reactive({ !is.null(editing_admin_id()) })
outputOptions(output, "editing_admin", suspendWhenHidden = FALSE)

# --- Load scene choices for dropdown ---
# Only fires when on admin_users tab (prevents race condition with lazy-loaded UI)
observe({
  rv$current_nav
  req(rv$current_nav == "admin_users")
  req(db_pool, rv$is_superadmin)

  # Check if UI has rendered yet (admin_role is a sibling input that's always visible)
  if (is.null(input$admin_role)) {
    # UI not ready yet, retry shortly
    invalidateLater(100)
    return()
  }

  scenes <- safe_query(db_pool,
    "SELECT scene_id, display_name FROM scenes
     WHERE scene_type IN ('metro', 'online') AND is_active = TRUE
     ORDER BY display_name",
    default = data.frame())
  if (nrow(scenes) > 0) {
    choices <- setNames(as.character(scenes$scene_id), scenes$display_name)
    # Preserve current selection when repopulating choices
    current_selection <- isolate(input$admin_scene)
    updateSelectInput(session, "admin_scene",
                      choices = c("Select scene..." = "", choices),
                      selected = current_selection)
  }
})

# --- Admin Users Table ---
admin_users_data <- reactive({
  rv$data_refresh  # Trigger refresh
  req(db_pool, rv$is_superadmin)
  safe_query(db_pool,
    "SELECT u.user_id, u.username, u.display_name, u.role,
            u.is_active, u.created_at, u.scene_id, s.display_name as scene_name
     FROM admin_users u
     LEFT JOIN scenes s ON u.scene_id = s.scene_id
     ORDER BY u.role DESC, u.display_name",
    default = data.frame())
})

output$admin_users_grouped <- renderUI({
  df <- admin_users_data()
  req(nrow(df) > 0)

  # Get all active scenes to find uncovered ones
  all_scenes <- safe_query(db_pool,
    "SELECT scene_id, display_name FROM scenes WHERE is_active = TRUE ORDER BY display_name",
    default = data.frame())

  # Split into groups
  supers <- df[df$role == "super_admin", ]
  scene_admins <- df[df$role == "scene_admin", ]
  covered_scene_ids <- unique(scene_admins$scene_id)
  uncovered <- if (nrow(all_scenes) > 0) {
    all_scenes[!all_scenes$scene_id %in% covered_scene_ids, ]
  } else {
    data.frame()
  }

  # Helper to build a user row
  make_user_row <- function(row) {
    div(
      class = "admin-user-row",
      onclick = sprintf("Shiny.setInputValue('admin_user_clicked', {user_id: %d, nonce: Math.random()}, {priority: 'event'})", row$user_id),
      div(class = "admin-user-row-name", row$display_name),
      div(class = "admin-user-row-username", paste0("@", row$username)),
      div(class = "admin-user-row-status", if (row$is_active) "\u2705" else "\u274c")
    )
  }

  sections <- tagList()

  # Super admins section
  if (nrow(supers) > 0) {
    super_rows <- lapply(seq_len(nrow(supers)), function(i) make_user_row(supers[i, ]))
    sections <- tagAppendChildren(sections,
      div(class = "admin-users-group",
        div(class = "admin-users-group-header",
          "All Scenes",
          span(class = "badge bg-primary", nrow(supers))
        ),
        tagList(super_rows)
      )
    )
  }

  # Scene admins grouped by scene
  if (nrow(scene_admins) > 0) {
    scene_names <- unique(scene_admins$scene_name)
    scene_names <- sort(scene_names)
    for (sname in scene_names) {
      group <- scene_admins[scene_admins$scene_name == sname, ]
      group_rows <- lapply(seq_len(nrow(group)), function(i) make_user_row(group[i, ]))
      sections <- tagAppendChildren(sections,
        div(class = "admin-users-group",
          div(class = "admin-users-group-header",
            sname,
            span(class = "badge bg-secondary", nrow(group))
          ),
          tagList(group_rows)
        )
      )
    }
  }

  # Uncovered scenes section
  if (nrow(uncovered) > 0) {
    badges <- lapply(uncovered$display_name, function(name) {
      span(class = "uncovered-scene-badge", name)
    })
    sections <- tagAppendChildren(sections,
      div(class = "admin-users-group",
        div(class = "admin-users-group-header",
          "No Admin Assigned",
          span(class = "badge bg-warning text-dark", nrow(uncovered))
        ),
        div(class = "uncovered-scenes-list", tagList(badges))
      )
    )
  }

  sections
})

# --- Row Click: Populate edit form ---
observeEvent(input$admin_user_clicked, {
  clicked <- input$admin_user_clicked
  if (is.null(clicked) || is.null(clicked$user_id)) return()

  df <- admin_users_data()
  row <- df[df$user_id == clicked$user_id, ]
  if (nrow(row) == 0) return()
  row <- row[1, ]

  editing_admin_id(row$user_id)
  updateTextInput(session, "admin_username", value = row$username)
  updateTextInput(session, "admin_display_name", value = row$display_name)
  updateTextInput(session, "admin_password", value = "")
  updateSelectInput(session, "admin_role", selected = row$role)

  # Set scene dropdown
  admin_row <- safe_query(db_pool,
    "SELECT scene_id FROM admin_users WHERE user_id = $1",
    params = list(row$user_id),
    default = data.frame())
  if (nrow(admin_row) > 0 && !is.na(admin_row$scene_id[1])) {
    updateSelectInput(session, "admin_scene", selected = as.character(admin_row$scene_id[1]))
  } else {
    updateSelectInput(session, "admin_scene", selected = "")
  }

  # Update toggle button label based on active status
  if (row$is_active) {
    updateActionButton(session, "toggle_admin_active_btn", label = "Deactivate")
  } else {
    updateActionButton(session, "toggle_admin_active_btn", label = "Reactivate")
  }

  # Update form title
  shinyjs::html("admin_form_title", "Edit Admin")
})

# --- Clear Form ---
observeEvent(input$clear_admin_form_btn, {
  editing_admin_id(NULL)
  updateTextInput(session, "admin_username", value = "")
  updateTextInput(session, "admin_display_name", value = "")
  updateTextInput(session, "admin_password", value = "")
  updateSelectInput(session, "admin_role", selected = "scene_admin")
  updateSelectInput(session, "admin_scene", selected = "")
  shinyjs::html("admin_form_title", "Add Admin")
})

# --- Generate Random Password ---
observeEvent(input$generate_password_btn, {
  # Generate a 12-character alphanumeric password
  chars <- c(letters, LETTERS, 0:9)
  pwd <- paste0(sample(chars, 12, replace = TRUE), collapse = "")
  # Show it in the password field as plain text so admin can copy it
  updateTextInput(session, "admin_password", value = pwd)
  # Temporarily switch to text input so password is visible for copying
  shinyjs::runjs("
    var el = document.getElementById('admin_password');
    if (el) { el.type = 'text'; setTimeout(function(){ el.select(); }, 50); }
  ")
  notify("Password generated — copy it now, it won't be shown again", type = "message", duration = 5)
})

# --- Save Admin (Create or Update) ---
observeEvent(input$save_admin_btn, {
  req(rv$is_superadmin)

  username <- trimws(input$admin_username)
  display_name <- trimws(input$admin_display_name)
  password <- input$admin_password
  role <- input$admin_role
  scene_id <- if (role == "scene_admin" && nchar(input$admin_scene) > 0) {
    as.integer(input$admin_scene)
  } else {
    NA_integer_
  }

  # Validation
  if (nchar(username) < 3) {
    notify("Username must be at least 3 characters", type = "warning")
    return()
  }
  if (nchar(display_name) == 0) {
    notify("Display name is required", type = "warning")
    return()
  }
  if (role == "scene_admin" && is.na(scene_id)) {
    notify("Scene admins must have an assigned scene", type = "warning")
    return()
  }

  if (is.null(editing_admin_id())) {
    # --- CREATE new admin ---
    if (nchar(password) < 8) {
      notify("Password must be at least 8 characters", type = "warning")
      return()
    }

    # Check username uniqueness
    existing <- safe_query(db_pool,
      "SELECT COUNT(*) as n FROM admin_users WHERE username = $1",
      params = list(username),
      default = data.frame(n = 0))
    if (existing$n[1] > 0) {
      notify("Username already exists", type = "error")
      return()
    }

    hash <- bcrypt::hashpw(password)

    insert_result <- safe_query(db_pool,
      "INSERT INTO admin_users (username, password_hash, display_name, role, scene_id)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING user_id",
      params = list(username, hash, display_name, role,
                    if (is.na(scene_id)) NA_integer_ else scene_id),
      default = data.frame())

    if (nrow(insert_result) > 0) {
      notify(paste0("Admin '", username, "' created"), type = "message")
      rv$data_refresh <- rv$data_refresh + 1
      # Clear form
      editing_admin_id(NULL)
      updateTextInput(session, "admin_username", value = "")
      updateTextInput(session, "admin_display_name", value = "")
      updateTextInput(session, "admin_password", value = "")
      updateSelectInput(session, "admin_role", selected = "scene_admin")
      updateSelectInput(session, "admin_scene", selected = "")
    } else {
      notify("Failed to create admin", type = "error")
    }

  } else {
    # --- UPDATE existing admin ---
    uid <- editing_admin_id()

    # Prevent super admin from changing own role
    if (uid == rv$admin_user$user_id && role != "super_admin") {
      notify("You cannot change your own role", type = "error")
      return()
    }

    # Check username uniqueness (excluding self)
    existing <- safe_query(db_pool,
      "SELECT COUNT(*) as n FROM admin_users WHERE username = $1 AND user_id != $2",
      params = list(username, uid),
      default = data.frame(n = 0))
    if (existing$n[1] > 0) {
      notify("Username already exists", type = "error")
      return()
    }

    if (nchar(password) > 0) {
      # Update with new password
      if (nchar(password) < 8) {
        notify("Password must be at least 8 characters", type = "warning")
        return()
      }
      hash <- bcrypt::hashpw(password)
      safe_execute(db_pool,
        "UPDATE admin_users SET username = $1, password_hash = $2, display_name = $3, role = $4, scene_id = $5
         WHERE user_id = $6",
        params = list(username, hash, display_name, role,
                      if (is.na(scene_id)) NA_integer_ else scene_id, uid))
    } else {
      # Update without changing password
      safe_execute(db_pool,
        "UPDATE admin_users SET username = $1, display_name = $2, role = $3, scene_id = $4
         WHERE user_id = $5",
        params = list(username, display_name, role,
                      if (is.na(scene_id)) NA_integer_ else scene_id, uid))
    }

    notify(paste0("Admin '", username, "' updated"), type = "message")
    rv$data_refresh <- rv$data_refresh + 1

    # If editing self, update reactive state
    if (uid == rv$admin_user$user_id) {
      rv$admin_user$display_name <- display_name
      rv$admin_user$username <- username
    }
  }
})

# --- Toggle Active Status ---
observeEvent(input$toggle_admin_active_btn, {
  req(rv$is_superadmin, !is.null(editing_admin_id()))
  uid <- editing_admin_id()

  # Prevent self-deactivation
  if (uid == rv$admin_user$user_id) {
    notify("You cannot deactivate your own account", type = "error")
    return()
  }

  # Get current status
  current <- safe_query(db_pool,
    "SELECT is_active, username FROM admin_users WHERE user_id = $1",
    params = list(uid),
    default = data.frame())
  if (nrow(current) == 0) return()

  new_status <- !current$is_active[1]

  safe_execute(db_pool,
    "UPDATE admin_users SET is_active = $1 WHERE user_id = $2",
    params = list(new_status, uid))

  action <- if (new_status) "reactivated" else "deactivated"
  notify(paste0("Admin '", current$username[1], "' ", action), type = "message")
  rv$data_refresh <- rv$data_refresh + 1

  # Clear selection
  editing_admin_id(NULL)
  shinyjs::html("admin_form_title", "Add Admin")
})
