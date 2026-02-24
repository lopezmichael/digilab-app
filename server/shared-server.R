# =============================================================================
# Shared Server Logic
# Contains: Database connection, navigation, authentication, helper functions
# =============================================================================

# ---------------------------------------------------------------------------
# Database Connection
# ---------------------------------------------------------------------------

observe({
  tryCatch({
    cache_count <- dbGetQuery(db_pool,
      "SELECT COUNT(*) as n FROM player_ratings_cache")$n
    if (is.na(cache_count) || cache_count == 0) {
      message("[startup] Ratings cache empty, populating...")
      recalculate_ratings_cache(db_pool)
      message("[startup] Ratings cache populated")
    }
  }, error = function(e) {
    message("[startup] Could not check/populate ratings cache: ", e$message)
  })

  admin_count <- tryCatch(
    dbGetQuery(db_pool, "SELECT COUNT(*) as n FROM admin_users"),
    error = function(e) data.frame(n = 0))
  if (nrow(admin_count) > 0 && admin_count$n[1] == 0) {
    rv$needs_bootstrap <- TRUE
  }

  session$sendCustomMessage("hideLoading", list())
}) |> bindEvent(TRUE, once = TRUE)

# Keepalive handler - receiving the input is enough to keep connection alive
observeEvent(input$keepalive_ping, {
  # No-op: just receiving this keeps the WebSocket active
}, ignoreInit = TRUE)

# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

observeEvent(input$header_home_click, {
  nav_select("main_content", "dashboard")
  rv$current_nav <- "dashboard"
  session$sendCustomMessage("updateSidebarNav", "nav_dashboard")
})

observeEvent(input$nav_dashboard, {
  nav_select("main_content", "dashboard")
  rv$current_nav <- "dashboard"
})

observeEvent(input$nav_stores, {
  nav_select("main_content", "stores")
  rv$current_nav <- "stores"
})

observeEvent(input$nav_players, {
  nav_select("main_content", "players")
  rv$current_nav <- "players"
})

observeEvent(input$nav_meta, {
  nav_select("main_content", "meta")
  rv$current_nav <- "meta"
})

observeEvent(input$nav_tournaments, {
  nav_select("main_content", "tournaments")
  rv$current_nav <- "tournaments"
})

observeEvent(input$nav_submit, {
  nav_select("main_content", "submit")
  rv$current_nav <- "submit"
})

# Mobile bottom tab bar navigation
observeEvent(input$mob_dashboard, {
  nav_select("main_content", "dashboard")
  rv$current_nav <- "dashboard"
  session$sendCustomMessage("updateSidebarNav", "nav_dashboard")
})
observeEvent(input$mob_players, {
  nav_select("main_content", "players")
  rv$current_nav <- "players"
  session$sendCustomMessage("updateSidebarNav", "nav_players")
})
observeEvent(input$mob_meta, {
  nav_select("main_content", "meta")
  rv$current_nav <- "meta"
  session$sendCustomMessage("updateSidebarNav", "nav_meta")
})
observeEvent(input$mob_tournaments, {
  nav_select("main_content", "tournaments")
  rv$current_nav <- "tournaments"
  session$sendCustomMessage("updateSidebarNav", "nav_tournaments")
})
observeEvent(input$mob_stores, {
  nav_select("main_content", "stores")
  rv$current_nav <- "stores"
  session$sendCustomMessage("updateSidebarNav", "nav_stores")
})
observeEvent(input$mob_submit, {
  nav_select("main_content", "submit")
  rv$current_nav <- "submit"
  session$sendCustomMessage("updateSidebarNav", "nav_submit")
})

observeEvent(input$nav_admin_results, {
  nav_select("main_content", "admin_results")
  rv$current_nav <- "admin_results"
})

observeEvent(input$nav_admin_tournaments, {
  nav_select("main_content", "admin_tournaments")
  rv$current_nav <- "admin_tournaments"
})

observeEvent(input$nav_admin_decks, {
  nav_select("main_content", "admin_decks")
  rv$current_nav <- "admin_decks"
})

observeEvent(input$nav_admin_stores, {
  nav_select("main_content", "admin_stores")
  rv$current_nav <- "admin_stores"
})

observeEvent(input$nav_admin_formats, {
  nav_select("main_content", "admin_formats")
  rv$current_nav <- "admin_formats"
})

observeEvent(input$nav_admin_players, {
  nav_select("main_content", "admin_players")
  rv$current_nav <- "admin_players"
})

observeEvent(input$nav_admin_users, {
  nav_select("main_content", "admin_users")
  rv$current_nav <- "admin_users"
})

observeEvent(input$nav_admin_scenes, {
  nav_select("main_content", "admin_scenes")
  rv$current_nav <- "admin_scenes"
})

# Admin modal navigation (for mobile access)
observeEvent(input$modal_admin_results, {
  removeModal()
  nav_select("main_content", "admin_results")
  rv$current_nav <- "admin_results"
})
observeEvent(input$modal_admin_tournaments, {
  removeModal()
  nav_select("main_content", "admin_tournaments")
  rv$current_nav <- "admin_tournaments"
})
observeEvent(input$modal_admin_players, {
  removeModal()
  nav_select("main_content", "admin_players")
  rv$current_nav <- "admin_players"
})
observeEvent(input$modal_admin_decks, {
  removeModal()
  nav_select("main_content", "admin_decks")
  rv$current_nav <- "admin_decks"
})
observeEvent(input$modal_admin_stores, {
  removeModal()
  nav_select("main_content", "admin_stores")
  rv$current_nav <- "admin_stores"
})
observeEvent(input$modal_admin_formats, {
  removeModal()
  nav_select("main_content", "admin_formats")
  rv$current_nav <- "admin_formats"
})
observeEvent(input$modal_admin_users, {
  removeModal()
  nav_select("main_content", "admin_users")
  rv$current_nav <- "admin_users"
})
observeEvent(input$modal_admin_scenes, {
  removeModal()
  nav_select("main_content", "admin_scenes")
  rv$current_nav <- "admin_scenes"
})

# Content pages (footer navigation)
observeEvent(input$nav_about, {
  nav_select("main_content", "about")
  rv$current_nav <- "about"
})

observeEvent(input$nav_faq, {
  nav_select("main_content", "faq")
  rv$current_nav <- "faq"
})

observeEvent(input$nav_for_tos, {
  nav_select("main_content", "for_tos")
  rv$current_nav <- "for_tos"
})

# Cross-page navigation links (from content pages)
observeEvent(input$about_to_for_tos, {
  nav_select("main_content", "for_tos")
  rv$current_nav <- "for_tos"
  session$sendCustomMessage("updateSidebarNav", "nav_for_tos")
})

observeEvent(input$faq_to_for_tos, {
  nav_select("main_content", "for_tos")
  rv$current_nav <- "for_tos"
  session$sendCustomMessage("updateSidebarNav", "nav_for_tos")
})

# FAQ → Upload Results
observeEvent(input$faq_to_upload, {
  nav_select("main_content", "submit")
  rv$current_nav <- "submit"
  session$sendCustomMessage("updateSidebarNav", "nav_submit")
})
observeEvent(input$faq_to_upload2, {
  nav_select("main_content", "submit")
  rv$current_nav <- "submit"
  session$sendCustomMessage("updateSidebarNav", "nav_submit")
})
observeEvent(input$faq_to_upload3, {
  nav_select("main_content", "submit")
  rv$current_nav <- "submit"
  session$sendCustomMessage("updateSidebarNav", "nav_submit")
})

# FAQ → For Organizers (multiple links on the page)
observeEvent(input$faq_to_for_tos_new_scene, {
  nav_select("main_content", "for_tos")
  rv$current_nav <- "for_tos"
  session$sendCustomMessage("updateSidebarNav", "nav_for_tos")
})
observeEvent(input$faq_to_for_tos2, {
  nav_select("main_content", "for_tos")
  rv$current_nav <- "for_tos"
  session$sendCustomMessage("updateSidebarNav", "nav_for_tos")
})

# For Organizers → Upload Results (multiple links on the page)
observeEvent(input$tos_to_upload, {
  nav_select("main_content", "submit")
  rv$current_nav <- "submit"
  session$sendCustomMessage("updateSidebarNav", "nav_submit")
})
observeEvent(input$tos_to_upload_btn, {
  nav_select("main_content", "submit")
  rv$current_nav <- "submit"
  session$sendCustomMessage("updateSidebarNav", "nav_submit")
})
observeEvent(input$tos_to_upload2, {
  nav_select("main_content", "submit")
  rv$current_nav <- "submit"
  session$sendCustomMessage("updateSidebarNav", "nav_submit")
})
observeEvent(input$tos_to_upload3, {
  nav_select("main_content", "submit")
  rv$current_nav <- "submit"
  session$sendCustomMessage("updateSidebarNav", "nav_submit")
})

# ---------------------------------------------------------------------------
# FAQ Navigation from Info Icons (Rating/Score column headers)
# ---------------------------------------------------------------------------

observeEvent(input$goto_faq_rating, {
  nav_select("main_content", "faq")
  rv$current_nav <- "faq"
  session$sendCustomMessage("updateSidebarNav", "nav_faq")
  # Open the competitive-rating accordion panel after a delay
  shinyjs::delay(300, {
    shinyjs::runjs("
      var panel = document.querySelector('#faq_ratings [data-value=\"competitive-rating\"] .accordion-button.collapsed');
      if (panel) panel.click();
    ")
  })
})

observeEvent(input$goto_faq_score, {
  nav_select("main_content", "faq")
  rv$current_nav <- "faq"
  session$sendCustomMessage("updateSidebarNav", "nav_faq")
  # Open the achievement-score accordion panel after a delay
  shinyjs::delay(300, {
    shinyjs::runjs("
      var panel = document.querySelector('#faq_ratings [data-value=\"achievement-score\"] .accordion-button.collapsed');
      if (panel) panel.click();
    ")
  })
})

# ---------------------------------------------------------------------------
# About Page Stats
# ---------------------------------------------------------------------------

output$about_scene_count <- renderText({
  count <- safe_query(db_pool, "SELECT COUNT(*) as n FROM scenes WHERE slug != 'all'",
                      default = data.frame(n = 0))$n
  as.character(count)
})

output$about_store_count <- renderText({
  count <- dbGetQuery(db_pool, "SELECT COUNT(*) FROM stores WHERE is_active = TRUE")[[1]]
  as.character(count)
})

output$about_player_count <- renderText({
  count <- dbGetQuery(db_pool, "SELECT COUNT(*) FROM players WHERE is_active = TRUE")[[1]]
  as.character(count)
})

output$about_tournament_count <- renderText({
  count <- dbGetQuery(db_pool, "SELECT COUNT(*) FROM tournaments")[[1]]
  as.character(count)
})

# ---------------------------------------------------------------------------
# Authentication
# ---------------------------------------------------------------------------

# Output for conditional panels
output$is_admin <- reactive({ rv$is_admin })
outputOptions(output, "is_admin", suspendWhenHidden = FALSE)

output$is_superadmin <- reactive({ rv$is_superadmin })
outputOptions(output, "is_superadmin", suspendWhenHidden = FALSE)

output$has_active_tournament <- reactive({ !is.null(rv$active_tournament_id) })
outputOptions(output, "has_active_tournament", suspendWhenHidden = FALSE)

# Login modal
observeEvent(input$admin_login_link, {
  if (rv$is_admin) {
    # Already logged in - show account info, change password, nav (mobile)
    role_label <- if (rv$is_superadmin) "Super Admin" else "Scene Admin"
    admin_name <- rv$admin_user$display_name

    # Get scene name for display
    scene_display <- "All Scenes"
    if (!is.null(rv$admin_user$scene_id)) {
      scene_row <- safe_query(db_pool,
        "SELECT display_name FROM scenes WHERE scene_id = $1",
        params = list(rv$admin_user$scene_id),
        default = data.frame())
      if (nrow(scene_row) > 0) scene_display <- scene_row$display_name[1]
    }

    # Account info section (visible on desktop and mobile)
    account_info <- div(
      class = "admin-account-info",
      div(class = "admin-account-row",
        span(class = "admin-account-label", "Username"),
        span(class = "admin-account-value", rv$admin_user$username)
      ),
      div(class = "admin-account-row",
        span(class = "admin-account-label", "Role"),
        span(class = "admin-account-value", role_label)
      ),
      div(class = "admin-account-row",
        span(class = "admin-account-label", "Scene"),
        span(class = "admin-account-value", scene_display)
      )
    )

    # Change password section (collapsible)
    change_password_section <- div(
      tags$a(
        class = "admin-change-pw-toggle",
        `data-bs-toggle` = "collapse",
        href = "#change_password_panel",
        role = "button",
        `aria-expanded` = "false",
        bsicons::bs_icon("key"), " Change Password ",
        bsicons::bs_icon("chevron-down", class = "admin-chevron-icon")
      ),
      tags$form(
        id = "change_password_panel",
        class = "collapse admin-change-password mt-2",
        autocomplete = "on",
        onsubmit = "event.preventDefault(); $('#change_password_btn').click();",
        tagAppendAttributes(passwordInput("change_current_password", "Current Password"), autocomplete = "current-password"),
        tagAppendAttributes(passwordInput("change_new_password", "New Password"), autocomplete = "new-password"),
        tagAppendAttributes(passwordInput("change_confirm_password", "Confirm New Password"), autocomplete = "new-password"),
        actionButton("change_password_btn", "Update Password",
                     class = "btn-primary btn-sm mt-1")
      )
    )

    # Mobile nav links (hidden on desktop)
    admin_links <- tagList(
      actionLink("modal_admin_results",
                 tagList(bsicons::bs_icon("pencil-square"), " Enter Results"),
                 class = "admin-modal-link"),
      actionLink("modal_admin_tournaments",
                 tagList(bsicons::bs_icon("trophy"), " Edit Tournaments"),
                 class = "admin-modal-link"),
      actionLink("modal_admin_players",
                 tagList(bsicons::bs_icon("people"), " Edit Players"),
                 class = "admin-modal-link"),
      actionLink("modal_admin_stores",
                 tagList(bsicons::bs_icon("shop"), " Edit Stores"),
                 class = "admin-modal-link")
    )

    # Add super admin links if applicable
    superadmin_links <- NULL
    if (rv$is_superadmin) {
      superadmin_links <- tagList(
        tags$hr(class = "my-2"),
        tags$div(class = "admin-modal-section", "Super Admin"),
        actionLink("modal_admin_decks",
                   tagList(bsicons::bs_icon("collection"), " Edit Decks"),
                   class = "admin-modal-link"),
        actionLink("modal_admin_formats",
                   tagList(bsicons::bs_icon("calendar3"), " Edit Formats"),
                   class = "admin-modal-link"),
        actionLink("modal_admin_users",
                   tagList(bsicons::bs_icon("person-gear"), " Manage Admins"),
                   class = "admin-modal-link"),
        actionLink("modal_admin_scenes",
                   tagList(bsicons::bs_icon("globe2"), " Manage Scenes"),
                   class = "admin-modal-link")
      )
    }

    showModal(modalDialog(
      title = "Account",
      account_info,
      tags$hr(class = "my-3"),
      change_password_section,
      div(
        class = "admin-modal-nav",
        tags$hr(class = "my-3"),
        tags$div(class = "admin-modal-section", "Navigation"),
        admin_links,
        superadmin_links
      ),
      footer = tagList(
        actionButton("logout_btn", "Logout", class = "btn-warning"),
        modalButton("Close")
      )
    ))
  } else if (rv$needs_bootstrap) {
    # First-time setup - create super admin
    showModal(modalDialog(
      title = "Create Super Admin",
      tags$p(class = "text-muted", "No admin accounts exist yet. Create the first super admin account."),
      tags$form(
        id = "bootstrap_form",
        autocomplete = "on",
        onsubmit = "event.preventDefault(); $('#bootstrap_btn').click();",
        tagAppendAttributes(textInput("bootstrap_username", "Username", placeholder = "e.g., michael"), autocomplete = "username"),
        textInput("bootstrap_display_name", "Display Name", placeholder = "e.g., Michael"),
        tags$div(
          tagAppendAttributes(passwordInput("bootstrap_password", "Password"), autocomplete = "new-password"),
          style = "margin-bottom: 0.5rem;"
        ),
        tagAppendAttributes(passwordInput("bootstrap_confirm", "Confirm Password"), autocomplete = "new-password")
      ),
      footer = tagList(
        actionButton("bootstrap_btn", "Create Account", class = "btn-primary"),
        modalButton("Cancel")
      )
    ))
  } else {
    # Normal login form (wrapped in <form> with autocomplete hints for browser password saving)
    showModal(modalDialog(
      title = "Admin Login",
      tags$form(
        id = "admin_login_form",
        autocomplete = "on",
        # Prevent default form submit (Shiny handles it via actionButton)
        onsubmit = "event.preventDefault(); $('#login_btn').click();",
        tagAppendAttributes(textInput("login_username", "Username"), autocomplete = "username"),
        tagAppendAttributes(passwordInput("login_password", "Password"), autocomplete = "current-password")
      ),
      footer = tagList(
        actionButton("login_btn", "Login", class = "btn-primary"),
        modalButton("Cancel")
      )
    ))
  }
})

# Handle login
observeEvent(input$login_btn, {
  username <- trimws(input$login_username)
  password <- input$login_password

  if (nchar(username) == 0 || nchar(password) == 0) {
    notify("Please enter username and password", type = "warning")
    return()
  }

  # Look up user
  user <- safe_query(db_pool,
    "SELECT user_id, username, password_hash, display_name, role, scene_id
     FROM admin_users WHERE username = $1 AND is_active = TRUE",
    params = list(username),
    default = data.frame())

  if (nrow(user) == 0) {
    notify("Invalid username or password", type = "error")
    return()
  }

  # Verify password
  if (!bcrypt::checkpw(password, user$password_hash[1])) {
    notify("Invalid username or password", type = "error")
    return()
  }

  # Success - set reactive state
  rv$is_admin <- TRUE
  rv$is_superadmin <- (user$role[1] == "super_admin")
  rv$admin_user <- list(
    user_id = user$user_id[1],
    username = user$username[1],
    display_name = user$display_name[1],
    role = user$role[1],
    scene_id = if (is.na(user$scene_id[1])) NULL else user$scene_id[1]
  )

  removeModal()
  notify(paste0("Welcome, ", user$display_name[1], "!"), type = "message")

  # Force scene for scene admins
  if (rv$admin_user$role == "scene_admin" && !is.null(rv$admin_user$scene_id)) {
    scene_slug <- safe_query(db_pool,
      "SELECT slug FROM scenes WHERE scene_id = $1",
      params = list(rv$admin_user$scene_id),
      default = data.frame())
    if (nrow(scene_slug) > 0) {
      updateSelectInput(session, "scene_selector", selected = scene_slug$slug[1])
    }
  }

  # Update dropdowns with data
  updateSelectInput(session, "tournament_store",
                    choices = get_store_choices(db_pool, include_none = TRUE))
})

# Handle bootstrap (first super admin creation)
observeEvent(input$bootstrap_btn, {
  username <- trimws(input$bootstrap_username)
  display_name <- trimws(input$bootstrap_display_name)
  password <- input$bootstrap_password
  confirm <- input$bootstrap_confirm

  # Validation
  if (nchar(username) < 3) {
    notify("Username must be at least 3 characters", type = "warning")
    return()
  }
  if (nchar(display_name) == 0) {
    notify("Display name is required", type = "warning")
    return()
  }
  if (nchar(password) < 8) {
    notify("Password must be at least 8 characters", type = "warning")
    return()
  }
  if (password != confirm) {
    notify("Passwords do not match", type = "error")
    return()
  }

  # Double-check table is still empty
  admin_count <- safe_query(db_pool,
    "SELECT COUNT(*) as n FROM admin_users",
    default = data.frame(n = 0))
  if (admin_count$n[1] > 0) {
    rv$needs_bootstrap <- FALSE
    notify("Admin accounts already exist. Please log in.", type = "warning")
    removeModal()
    return()
  }

  # Create super admin
  hash <- bcrypt::hashpw(password)

  result <- safe_query(db_pool,
    "INSERT INTO admin_users (username, password_hash, display_name, role, scene_id)
     VALUES ($1, $2, $3, 'super_admin', NULL) RETURNING user_id",
    params = list(username, hash, display_name),
    default = data.frame())

  if (nrow(result) > 0) {
    new_id <- result$user_id[1]
    rv$needs_bootstrap <- FALSE
    rv$is_admin <- TRUE
    rv$is_superadmin <- TRUE
    rv$admin_user <- list(
      user_id = new_id,
      username = username,
      display_name = display_name,
      role = "super_admin",
      scene_id = NULL
    )
    removeModal()
    notify(paste0("Super admin account created. Welcome, ", display_name, "!"), type = "message")

    # Update dropdowns with data
    updateSelectInput(session, "tournament_store",
                      choices = get_store_choices(db_pool, include_none = TRUE))
  } else {
    notify("Failed to create account. Please try again.", type = "error")
  }
})

# Keep store dropdown populated for Enter Results wizard
# Only fires when on admin_results tab (prevents race condition with lazy-loaded UI)
observe({
  rv$current_nav
  req(rv$current_nav == "admin_results")
  rv$data_refresh
  req(rv$is_admin)
  # Preserve current selection when repopulating choices
  current_selection <- isolate(input$tournament_store)
  updateSelectInput(session, "tournament_store",
                    choices = get_store_choices(db_pool, include_none = TRUE),
                    selected = current_selection)
})

# Handle logout
observeEvent(input$logout_btn, {
  rv$is_admin <- FALSE
  rv$is_superadmin <- FALSE
  rv$admin_user <- NULL
  rv$active_tournament_id <- NULL
  removeModal()
  notify("Logged out", type = "message")
  nav_select("main_content", "dashboard")
  rv$current_nav <- "dashboard"
})

# Handle change password
observeEvent(input$change_password_btn, {
  req(rv$is_admin, rv$admin_user)

  current_pw <- input$change_current_password
  new_pw <- input$change_new_password
  confirm_pw <- input$change_confirm_password

  if (nchar(current_pw) == 0) {
    notify("Please enter your current password", type = "warning")
    return()
  }
  if (nchar(new_pw) < 8) {
    notify("New password must be at least 8 characters", type = "warning")
    return()
  }
  if (new_pw != confirm_pw) {
    notify("New passwords do not match", type = "error")
    return()
  }

  # Verify current password
  user <- safe_query(db_pool,
    "SELECT password_hash FROM admin_users WHERE user_id = $1",
    params = list(rv$admin_user$user_id),
    default = data.frame())

  if (nrow(user) == 0) {
    notify("Account not found", type = "error")
    return()
  }

  if (!bcrypt::checkpw(current_pw, user$password_hash[1])) {
    notify("Current password is incorrect", type = "error")
    return()
  }

  # Update password
  old <- safe_query(db_pool,
    "SELECT * FROM admin_users WHERE user_id = $1",
    params = list(rv$admin_user$user_id),
    default = data.frame())

  new_hash <- bcrypt::hashpw(new_pw)
  safe_execute(db_pool,
    "UPDATE admin_users SET password_hash = $1 WHERE user_id = $2",
    params = list(new_hash, rv$admin_user$user_id))

  notify("Password updated successfully", type = "message")
  removeModal()
})

# ---------------------------------------------------------------------------
# Helper Functions
# ---------------------------------------------------------------------------

#' Track a custom GA4 event
#' @param event_name GA4 event name (e.g., "tab_visit", "modal_open")
#' @param ... Named parameters to include as event params
track_event <- function(event_name, ...) {
  params <- list(...)
  tryCatch(
    session$sendCustomMessage("trackEvent", list(event = event_name, params = params)),
    error = function(e) NULL
  )
}

#' Build Sentry context tags from current session state
#' @return Named list of tags for sentryR::capture_exception()
sentry_context_tags <- function() {
  tags <- list()
  tryCatch({
    if (!is.null(rv$current_nav)) tags$active_tab <- rv$current_nav
    if (!is.null(rv$current_scene)) tags$scene <- rv$current_scene
    if (!is.null(rv$is_admin) && rv$is_admin) tags$is_admin <- "true"
    if (!is.null(rv$community_filter)) tags$community <- rv$community_filter
  }, error = function(e) NULL)
  tags
}

#' Safe Database Query Wrapper
#'
#' Executes a database query with error handling, returning a sensible default
#' instead of crashing the app if the query fails. Useful for public-facing
#' queries where graceful degradation is preferred over error screens.
#'
#' @param db_con Database connection object from DBI
#' @param query Character. SQL query string (can include ? placeholders for params)
#' @param params List or NULL. Parameters for parameterized query (default: NULL)
#' @param default Default value to return on error (default: empty data.frame)
#'
#' @return Query result on success, or default value on error
#'
#' @examples
#' # Simple query
#' result <- safe_query(db_pool, "SELECT * FROM players")
#'
#' # Parameterized query
#' result <- safe_query(db_pool, "SELECT * FROM players WHERE player_id = $1",
#'                      params = list(42))
#'
#' # Custom default for aggregations
#' result <- safe_query(db_pool, "SELECT COUNT(*) as n FROM results",
#'                      default = data.frame(n = 0))
safe_query <- function(pool, query, params = NULL, default = data.frame()) {
  tryCatch({
    if (!is.null(params) && length(params) > 0) {
      DBI::dbGetQuery(pool, query, params = params)
    } else {
      DBI::dbGetQuery(pool, query)
    }
  }, error = function(e) {
    query_preview <- substr(gsub("\\s+", " ", query), 1, 200)
    message("[safe_query] Error: ", conditionMessage(e), " | Query: ", query_preview)
    if (sentry_enabled) {
      tryCatch(sentryR::capture_exception(e, tags = sentry_context_tags()), error = function(se) NULL)
    }
    default
  })
}

#' Safe Database Execute Wrapper
#'
#' Executes a database write operation (INSERT, UPDATE, DELETE) with error
#' handling. Returns 0 rows affected instead of crashing on error.
#'
#' @param db_con Database connection object from DBI
#' @param query Character. SQL statement string (can include ? placeholders for params)
#' @param params List or NULL. Parameters for parameterized query (default: NULL)
#'
#' @return Number of rows affected on success, or 0 on error
#'
#' @examples
#' # Simple execute
#' rows <- safe_execute(db_pool, "DELETE FROM results WHERE result_id = $1",
#'                      params = list(42))
safe_execute <- function(pool, query, params = NULL) {
  tryCatch({
    if (!is.null(params) && length(params) > 0) {
      DBI::dbExecute(pool, query, params = params)
    } else {
      DBI::dbExecute(pool, query)
    }
  }, error = function(e) {
    message("[safe_execute] Error: ", conditionMessage(e))
    message("[safe_execute] Query: ", substr(gsub("\\s+", " ", query), 1, 200))
    if (sentry_enabled) {
      tryCatch(sentryR::capture_exception(e, tags = sentry_context_tags()), error = function(se) NULL)
    }
    0
  })
}

get_store_choices <- function(pool, include_none = FALSE) {
  stores <- safe_query(pool, "SELECT store_id, name FROM stores WHERE is_active = TRUE ORDER BY name", default = data.frame())
  choices <- setNames(stores$store_id, stores$name)
  if (include_none) {
    choices <- c("Select a store..." = "", choices)
  }
  return(choices)
}

get_archetype_choices <- function(pool) {
  archetypes <- safe_query(pool, "SELECT archetype_id, archetype_name FROM deck_archetypes WHERE is_active = TRUE ORDER BY archetype_name", default = data.frame())
  choices <- setNames(archetypes$archetype_id, archetypes$archetype_name)
  return(choices)
}

get_player_choices <- function(pool) {
  players <- safe_query(pool, "SELECT player_id, display_name FROM players WHERE is_active = TRUE ORDER BY display_name", default = data.frame())
  choices <- setNames(players$player_id, players$display_name)
  return(choices)
}

get_format_choices <- function(pool) {
  formats <- safe_query(pool, "
    SELECT format_id, display_name
    FROM formats
    WHERE is_active = TRUE
    ORDER BY release_date DESC NULLS LAST
  ", default = data.frame())
  if (nrow(formats) == 0) {
    return(c("No formats configured" = ""))
  }
  choices <- setNames(formats$format_id, formats$display_name)
  return(choices)
}

# Update format dropdowns when database connects, formats change, or tab navigation
observe({
  # Trigger on format refresh or tab switch (ensures UI exists after lazy-load)
  rv$format_refresh
  rv$current_nav

  format_choices <- get_format_choices(db_pool)

  # Format choices with "All Formats" option
  format_choices_with_all <- list(
    "All Formats" = "",
    "Recent Formats" = format_choices
  )

  # Preserve current selections when repopulating choices
  current_dashboard <- isolate(input$dashboard_format)
  current_players <- isolate(input$players_format)
  current_meta <- isolate(input$meta_format)
  current_tournaments <- isolate(input$tournaments_format)
  current_tournament <- isolate(input$tournament_format)

  # Update all format dropdowns (preserve selections, default dashboard to All Formats)

  updateSelectInput(session, "dashboard_format", choices = format_choices_with_all,
                    selected = if (is.null(current_dashboard)) "" else current_dashboard)
  updateSelectInput(session, "players_format", choices = format_choices_with_all,
                    selected = current_players)
  updateSelectInput(session, "meta_format", choices = format_choices_with_all,
                    selected = current_meta)
  updateSelectInput(session, "tournaments_format", choices = format_choices_with_all,
                    selected = current_tournaments)
  updateSelectInput(session, "tournament_format", choices = format_choices,
                    selected = current_tournament)
})

# Reactive: get the latest (current) format_id
get_latest_format_id <- reactive({
  result <- safe_query(db_pool,
    "SELECT format_id FROM formats WHERE is_active = TRUE ORDER BY release_date DESC NULLS LAST LIMIT 1",
    default = data.frame(format_id = character()))
  if (nrow(result) > 0) result$format_id[1] else NULL
}) |> bindCache(rv$data_refresh)

# =============================================================================
# Community Filter Banner
# =============================================================================

# Render community filter banner
output$community_banner <- renderUI({
  req(rv$community_filter)

  # Look up store name
  store <- safe_query(db_pool,
    "SELECT name FROM stores WHERE slug = $1",
    params = list(rv$community_filter))

  if (nrow(store) == 0) return(NULL)

  community_banner_ui(store$name)
})

# Clear community filter
observeEvent(input$clear_community_filter, {
  rv$community_filter <- NULL
  clear_community_filter(session)
  # Reset filters back to defaults (5+) when clearing community filter
  session$sendCustomMessage("setPillToggle", list(inputId = "players_min_events", value = "5"))
  session$sendCustomMessage("setPillToggle", list(inputId = "meta_min_entries", value = "5"))
  notify("Community filter cleared", type = "message", duration = 2)
})

# Format event type for display
format_event_type <- function(et) {
  if (is.na(et)) return("Unknown")
  switch(et,
    "locals" = "Locals",
    "evo_cup" = "Evo Cup",
    "store_championship" = "Store Championship",
    "regional" = "Regional",
    "regionals" = "Regionals",
    "online" = "Online",
    "regulation_battle" = "Regulation Battle",
    "release_event" = "Release Event",
    "other" = "Other",
    et
  )
}

#' Build Parameterized SQL Filters
#'
#' Creates SQL WHERE clause fragments with parameterized placeholders to prevent
#' SQL injection. Returns both the SQL fragment and corresponding parameter values.
#'
#' @param table_alias Character. Table alias to use in SQL (e.g., "t" for "t.format")
#' @param format Character or NULL. Format value for exact match filter
#' @param event_type Character or NULL. Event type value for exact match filter
#' @param search Character or NULL. Search term for LIKE filter (will be wrapped with %)
#' @param search_column Character. Column name for search filter (default: "display_name")
#' @param id Integer or NULL. ID value for exact match filter
#' @param id_column Character. Column name for ID filter (default: "id")
#' @param scene Character or NULL. Scene slug for filtering ("all" = no filter, "online" = is_online stores)
#' @param store_alias Character or NULL. Table alias for stores table when filtering by scene
#' @param community_store Character or NULL. Store slug for community filtering (takes precedence over scene)
#'
#' @return List with:
#'   - sql: SQL fragment with $N placeholders (e.g., "AND t.format = $1")
#'   - params: List of parameter values in order
#'   - any_active: Boolean indicating if any filters are active
#'
#' @examples
#' filters <- build_filters_param(
#'   table_alias = "t",
#'   format = "BT-19",
#'   event_type = "locals",
#'   scene = "dfw",
#'   store_alias = "s"
#' )
#' # filters$sql: "AND t.format = $1 AND t.event_type = $2 AND s.scene_id = (SELECT scene_id FROM scenes WHERE slug = $3)"
#' # filters$params: list("BT-19", "locals", "dfw")
#'
#' query <- paste("SELECT * FROM tournaments t JOIN stores s ON t.store_id = s.store_id WHERE 1=1", filters$sql)
#' dbGetQuery(con, query, params = filters$params)
build_filters_param <- function(table_alias = "t",
                                 format = NULL,
                                 event_type = NULL,
                                 search = NULL,
                                 search_column = "display_name",
                                 id = NULL,
                                 id_column = "id",
                                 scene = NULL,
                                 store_alias = NULL,
                                 community_store = NULL,
                                 start_idx = 1) {
  sql_parts <- character(0)
  params <- list()
  idx <- start_idx

  # Format filter (exact match)
  if (!is.null(format) && format != "") {
    sql_parts <- c(sql_parts, sprintf("AND %s.format = $%d", table_alias, idx))
    params <- c(params, list(format))
    idx <- idx + 1
  }

  # Event type filter (exact match)
  if (!is.null(event_type) && event_type != "") {
    sql_parts <- c(sql_parts, sprintf("AND %s.event_type = $%d", table_alias, idx))
    params <- c(params, list(event_type))
    idx <- idx + 1
  }

  # Search filter (LIKE match, case-insensitive)
  if (!is.null(search) && trimws(search) != "") {
    search_term <- trimws(search)
    # Use table alias if search_column doesn't contain a dot (allowing "p.display_name" override)
    col_ref <- if (grepl("\\.", search_column)) {
      search_column
    } else {
      sprintf("%s.%s", table_alias, search_column)
    }
    sql_parts <- c(sql_parts, sprintf("AND LOWER(%s) LIKE LOWER($%d)", col_ref, idx))
    params <- c(params, list(paste0("%", search_term, "%")))
    idx <- idx + 1
  }

  # ID filter (exact match)
  if (!is.null(id) && !is.na(id)) {
    # Use table alias if id_column doesn't contain a dot
    col_ref <- if (grepl("\\.", id_column)) {
      id_column
    } else {
      sprintf("%s.%s", table_alias, id_column)
    }
    sql_parts <- c(sql_parts, sprintf("AND %s = $%d", col_ref, idx))
    params <- c(params, list(as.integer(id)))
    idx <- idx + 1
  }

  # Community filter (store-specific filtering - takes precedence over scene filter)
  if (!is.null(community_store) && community_store != "" && !is.null(store_alias)) {
    sql_parts <- c(sql_parts, sprintf("AND %s.slug = $%d", store_alias, idx))
    params <- c(params, list(community_store))
    idx <- idx + 1
  } else {
    # Scene filter (requires store_alias to be set)
    if (!is.null(scene) && scene != "" && scene != "all" && !is.null(store_alias)) {
      if (scene == "online") {
        # Online scene filters by is_online flag (no parameter needed)
        sql_parts <- c(sql_parts, sprintf("AND %s.is_online = TRUE", store_alias))
      } else {
        # Regular scene filters by scene_id via slug lookup
        sql_parts <- c(sql_parts, sprintf(
          "AND %s.scene_id = (SELECT scene_id FROM scenes WHERE slug = $%d)",
          store_alias, idx
        ))
        params <- c(params, list(scene))
        idx <- idx + 1
      }
    }
  }

  list(
    sql = paste(sql_parts, collapse = " "),
    params = params,
    any_active = length(params) > 0,
    next_idx = idx
  )
}
