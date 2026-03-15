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
  if (nrow(scenes) == 0) { invalidateLater(500); return() }
  choices <- setNames(as.character(scenes$scene_id), scenes$display_name)
  # Preserve current selection when repopulating choices
  current_selection <- isolate(input$admin_scene)
  updateSelectInput(session, "admin_scene",
                    choices = c("Select scene..." = "", choices),
                    selected = current_selection)
})

# --- Populate scene filter dropdown ---
observe({
  req(rv$current_nav == "admin_users", db_pool, rv$is_superadmin)
  # Wait for UI to render
  if (is.null(input$admin_users_scene_filter)) {
    invalidateLater(100)
    return()
  }
  scenes <- safe_query(db_pool,
    "SELECT scene_id, display_name FROM scenes WHERE is_active = TRUE ORDER BY display_name",
    default = data.frame())
  if (nrow(scenes) == 0) { invalidateLater(500); return() }
  choices <- c("All Scenes" = "all",
               "Super Admins" = "super",
               "No Admin" = "uncovered",
               setNames(as.character(scenes$scene_id), scenes$display_name))
  current <- isolate(input$admin_users_scene_filter)
  updateSelectInput(session, "admin_users_scene_filter",
                    choices = choices, selected = current %||% "all")
})

# --- Admin Users Table ---
admin_users_data <- reactive({
  rv$data_refresh  # Trigger refresh
  req(db_pool, rv$is_superadmin)
  safe_query(db_pool,
    "SELECT u.user_id, u.username, u.discord_user_id, u.role,
            u.is_active, u.created_at, aus.scene_id, s.display_name as scene_name
     FROM admin_users u
     LEFT JOIN admin_user_scenes aus ON u.user_id = aus.user_id AND aus.is_primary = TRUE
     LEFT JOIN scenes s ON aus.scene_id = s.scene_id
     ORDER BY u.role DESC, u.username",
    default = data.frame())
})

output$admin_users_grouped <- renderUI({
  df <- admin_users_data()
  req(nrow(df) > 0)

  scene_filter <- input$admin_users_scene_filter %||% "all"

  # Get all active scenes to find uncovered ones
  all_scenes <- safe_query(db_pool,
    "SELECT scene_id, display_name FROM scenes WHERE is_active = TRUE ORDER BY display_name",
    default = data.frame())

  # Split into groups
  supers <- df[df$role == "super_admin", ]
  scene_admins <- df[df$role == "scene_admin" & !is.na(df$scene_name), ]
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
      div(class = "admin-user-row-name", row$username),
      div(class = "admin-user-row-status", if (isTRUE(row$is_active)) "\u2705" else "\u274c")
    )
  }

  # Apply scene filter
  show_supers <- scene_filter %in% c("all", "super")
  show_scene_admins <- scene_filter %in% c("all") || (!scene_filter %in% c("super", "uncovered"))
  show_uncovered <- scene_filter %in% c("all", "uncovered")

  # Filter scene admins to specific scene if a scene_id is selected
  if (!scene_filter %in% c("all", "super", "uncovered") && nrow(scene_admins) > 0) {
    scene_admins <- scene_admins[scene_admins$scene_id == as.integer(scene_filter), , drop = FALSE]
  }

  sections <- tagList()

  # Super admins section
  if (show_supers && nrow(supers) > 0) {
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
  if (show_scene_admins && nrow(scene_admins) > 0) {
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
  if (show_uncovered && nrow(uncovered) > 0) {
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

  if (length(sections) == 0) {
    return(div(class = "text-muted text-center py-3", "No admins match this filter"))
  }

  div(class = "admin-users-scroll", sections)
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
  updateTextInput(session, "admin_discord_id", value = row$discord_user_id %||% "")
  updateTextInput(session, "admin_password", value = "")
  updateSelectInput(session, "admin_role", selected = row$role)

  # Set scene dropdown (from junction table)
  admin_row <- safe_query(db_pool,
    "SELECT scene_id FROM admin_user_scenes WHERE user_id = $1 AND is_primary = TRUE",
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
  updateTextInput(session, "admin_discord_id", value = "")
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
  discord_user_id <- trimws(input$admin_discord_id)
  if (nchar(discord_user_id) == 0) discord_user_id <- NA_character_
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
      "INSERT INTO admin_users (username, password_hash, discord_user_id, role, scene_id)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING user_id",
      params = list(username, hash, discord_user_id, role,
                    if (is.na(scene_id)) NA_integer_ else scene_id),
      default = data.frame())

    if (nrow(insert_result) > 0) {
      # Also write to junction table
      new_uid <- insert_result$user_id[1]
      if (!is.na(scene_id)) {
        safe_execute(db_pool,
          "INSERT INTO admin_user_scenes (user_id, scene_id, is_primary)
           VALUES ($1, $2, TRUE)
           ON CONFLICT (user_id, scene_id) DO NOTHING",
          params = list(new_uid, scene_id))
      }
      # Look up scene display name for the DM template
      scene_name <- ""
      discord_thread_info <- ""
      if (!is.na(scene_id)) {
        scene_info <- safe_query(db_pool,
          "SELECT display_name, discord_thread_id FROM scenes WHERE scene_id = $1",
          params = list(scene_id),
          default = data.frame())
        if (nrow(scene_info) > 0) {
          scene_name <- scene_info$display_name[1]
          tid <- scene_info$discord_thread_id[1]
          if (!is.null(tid) && !is.na(tid) && nchar(tid) > 0) {
            discord_thread_info <- paste0("(Thread ID: ", tid, ")")
          }
        }
      }

      # Build welcome DM template
      thread_line <- if (nchar(discord_thread_info) > 0) {
        paste0("- Your scene coordination thread: ", discord_thread_info)
      } else {
        "- Your scene coordination thread: (will be set up soon)"
      }

      welcome_dm <- paste0(
        "Hey ", username, "! You've been added as a Scene Admin for ", scene_name,
        " on DigiLab. Here's everything you need to get started:\n\n",
        "**Your Login:**\n",
        "- App: https://app.digilab.cards/\n",
        "- Username: ", username, "\n",
        "- Password: ", password, "\n",
        "- Please change your password after your first login\n\n",
        "**First Steps:**\n",
        "1. Log in and click the Admin button (top-right corner)\n",
        "2. Check Admin -> Stores to verify your local store(s) are set up\n",
        "3. Head to Admin -> Enter Results to start adding tournament data\n",
        "4. You can paste results directly from a spreadsheet!\n\n",
        "**Resources:**\n",
        "- For Organizers guide: https://digilab.cards/organizers\n",
        thread_line, "\n",
        "- Report bugs or data errors using the buttons in the app\n\n",
        "Looking forward to seeing ", scene_name, " grow!"
      )

      # Store in reactive for the UI to display
      rv$welcome_dm_text <- welcome_dm
      rv$show_welcome_dm <- TRUE

      notify(paste0("Admin '", username, "' created"), type = "message")
      rv$data_refresh <- rv$data_refresh + 1

      # Clear form
      editing_admin_id(NULL)
      updateTextInput(session, "admin_username", value = "")
      updateTextInput(session, "admin_discord_id", value = "")
      updateTextInput(session, "admin_password", value = "")
      updateSelectInput(session, "admin_role", selected = "scene_admin")
      updateSelectInput(session, "admin_scene", selected = "")
      shinyjs::html("admin_form_title", "Add Admin")
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
        "UPDATE admin_users SET username = $1, password_hash = $2, discord_user_id = $3, role = $4, scene_id = $5
         WHERE user_id = $6",
        params = list(username, hash, discord_user_id, role,
                      if (is.na(scene_id)) NA_integer_ else scene_id, uid))
    } else {
      # Update without changing password
      safe_execute(db_pool,
        "UPDATE admin_users SET username = $1, discord_user_id = $2, role = $3, scene_id = $4
         WHERE user_id = $5",
        params = list(username, discord_user_id, role,
                      if (is.na(scene_id)) NA_integer_ else scene_id, uid))
    }

    # Sync junction table (transactional to avoid orphaned state)
    con <- pool::localCheckout(db_pool)
    tryCatch({
      DBI::dbExecute(con, "BEGIN")
      DBI::dbExecute(con,
        "DELETE FROM admin_user_scenes WHERE user_id = $1 AND is_primary = TRUE",
        params = list(uid))
      if (!is.na(scene_id)) {
        DBI::dbExecute(con,
          "INSERT INTO admin_user_scenes (user_id, scene_id, is_primary)
           VALUES ($1, $2, TRUE)
           ON CONFLICT (user_id, scene_id) DO UPDATE SET is_primary = TRUE",
          params = list(uid, scene_id))
      }
      DBI::dbExecute(con, "COMMIT")
    }, error = function(e) {
      try(DBI::dbExecute(con, "ROLLBACK"), silent = TRUE)
      warning("Junction table sync failed: ", e$message)
    })

    notify(paste0("Admin '", username, "' updated"), type = "message")
    rv$data_refresh <- rv$data_refresh + 1

    # If editing self, update reactive state
    if (uid == rv$admin_user$user_id) {
      rv$admin_user$discord_user_id <- discord_user_id
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

# --- Welcome DM Copy Area (shown after creating a scene admin) ---
output$welcome_dm_area <- renderUI({
  req(isTRUE(rv$show_welcome_dm), rv$welcome_dm_text)

  div(class = "welcome-dm-area",
    div(class = "d-flex justify-content-between align-items-center mb-2",
      h5(class = "mb-0",
        bsicons::bs_icon("chat-dots-fill", class = "me-2"),
        "Welcome DM Ready"
      ),
      actionButton("dismiss_welcome_dm", bsicons::bs_icon("x-lg"),
                   class = "btn btn-sm btn-outline-secondary py-0")
    ),
    tags$p(class = "text-muted small mb-2",
      "Copy and send this via Discord DM to the new admin:"
    ),
    tags$pre(class = "welcome-dm-text", rv$welcome_dm_text),
    actionButton("copy_welcome_dm",
                 tagList(bsicons::bs_icon("clipboard"), " Copy to Clipboard"),
                 class = "btn-primary btn-sm")
  )
})

observeEvent(input$copy_welcome_dm, {
  shinyjs::runjs(sprintf(
    "var text = %s; navigator.clipboard.writeText(text).then(function() { Shiny.setInputValue('dm_copied', Date.now(), {priority: 'event'}); });",
    jsonlite::toJSON(rv$welcome_dm_text, auto_unbox = TRUE)
  ))
})

observeEvent(input$dm_copied, {
  notify("Welcome DM copied to clipboard!", type = "message", duration = 3)
})

observeEvent(input$dismiss_welcome_dm, {
  rv$show_welcome_dm <- FALSE
  rv$welcome_dm_text <- NULL
})
