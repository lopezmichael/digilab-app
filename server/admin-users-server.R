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
            u.is_active, u.created_at, s.display_name as scene_name
     FROM admin_users u
     LEFT JOIN scenes s ON u.scene_id = s.scene_id
     ORDER BY u.role DESC, u.display_name",
    default = data.frame())
})

output$admin_users_table <- renderReactable({
  df <- admin_users_data()
  req(nrow(df) > 0)

  reactable(
    df,
    columns = list(
      user_id = colDef(show = FALSE),
      username = colDef(name = "Username", minWidth = 100),
      display_name = colDef(name = "Name", minWidth = 100),
      role = colDef(name = "Role", minWidth = 100, cell = function(value) {
        if (value == "super_admin") "Super Admin" else "Scene Admin"
      }),
      scene_name = colDef(name = "Scene", minWidth = 100, cell = function(value) {
        if (is.na(value) || is.null(value)) "All (Super)" else value
      }),
      is_active = colDef(name = "Active", maxWidth = 80, cell = function(value) {
        if (value) "\u2705" else "\u274c"
      }),
      created_at = colDef(name = "Created", minWidth = 100, cell = function(value) {
        format(as.Date(value), "%b %d, %Y")
      })
    ),
    selection = "single",
    onClick = "select",
    highlight = TRUE,
    compact = TRUE,
    theme = reactableTheme(
      rowSelectedStyle = list(backgroundColor = "rgba(0, 123, 255, 0.1)")
    )
  )
})

# --- Row Selection: Populate edit form ---
observeEvent(getReactableState("admin_users_table", "selected"), {
  selected <- getReactableState("admin_users_table", "selected")
  if (is.null(selected) || length(selected) == 0) {
    editing_admin_id(NULL)
    return()
  }

  df <- admin_users_data()
  row <- df[selected, ]

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
  updateReactable("admin_users_table", selected = NA)
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
      updateReactable("admin_users_table", selected = NA)
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
  updateReactable("admin_users_table", selected = NA)
  shinyjs::html("admin_form_title", "Add Admin")
})
