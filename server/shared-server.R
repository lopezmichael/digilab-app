# =============================================================================
# Shared Server Logic
# Contains: Database connection, navigation, authentication, helper functions
# =============================================================================

# ---------------------------------------------------------------------------
# Database Connection
# ---------------------------------------------------------------------------

observe({
  rv$db_con <- connect_db()

  # Once database is connected, check and populate ratings cache if empty
  if (!is.null(rv$db_con) && dbIsValid(rv$db_con)) {
    # Check if ratings cache is empty and populate if needed
    tryCatch({
      cache_count <- DBI::dbGetQuery(rv$db_con,
        "SELECT COUNT(*) as n FROM player_ratings_cache")$n
      if (is.na(cache_count) || cache_count == 0) {
        message("[startup] Ratings cache empty, populating...")
        recalculate_ratings_cache(rv$db_con)
        message("[startup] Ratings cache populated")
      }
    }, error = function(e) {
      message("[startup] Could not check/populate ratings cache: ", e$message)
    })

    # Hide loading screen - data is ready after cache check
    session$sendCustomMessage("hideLoading", list())
  }
})

# Keepalive handler - receiving the input is enough to keep connection alive
observeEvent(input$keepalive_ping, {
  # No-op: just receiving this keeps the WebSocket active
}, ignoreInit = TRUE)

# Clean shutdown: close database connection when app stops
onStop(function() {
  isolate({
    if (!is.null(rv$db_con) && DBI::dbIsValid(rv$db_con)) {
      tryCatch({
        DBI::dbDisconnect(rv$db_con)
        message("[shutdown] Database connection closed")
      }, error = function(e) {
        message("[shutdown] Error closing connection: ", conditionMessage(e))
      })
    }
  })
})

# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

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
})

observeEvent(input$faq_to_for_tos, {
  nav_select("main_content", "for_tos")
  rv$current_nav <- "for_tos"
})

observeEvent(input$faq_to_about, {
  nav_select("main_content", "about")
  rv$current_nav <- "about"
})

# FAQ → Upload Results
observeEvent(input$faq_to_upload, {
  nav_select("main_content", "submit")
  rv$current_nav <- "submit"
})
observeEvent(input$faq_to_upload2, {
  nav_select("main_content", "submit")
  rv$current_nav <- "submit"
})
observeEvent(input$faq_to_upload3, {
  nav_select("main_content", "submit")
  rv$current_nav <- "submit"
})

# FAQ → For Organizers (multiple links on the page)
observeEvent(input$faq_to_for_tos_new_scene, {
  nav_select("main_content", "for_tos")
  rv$current_nav <- "for_tos"
})
observeEvent(input$faq_to_for_tos2, {
  nav_select("main_content", "for_tos")
  rv$current_nav <- "for_tos"
})

# For Organizers → Upload Results (multiple links on the page)
observeEvent(input$tos_to_upload, {
  nav_select("main_content", "submit")
  rv$current_nav <- "submit"
})
observeEvent(input$tos_to_upload_btn, {
  nav_select("main_content", "submit")
  rv$current_nav <- "submit"
})
observeEvent(input$tos_to_upload2, {
  nav_select("main_content", "submit")
  rv$current_nav <- "submit"
})
observeEvent(input$tos_to_upload3, {
  nav_select("main_content", "submit")
  rv$current_nav <- "submit"
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
  req(rv$db_con)
  count <- safe_query(rv$db_con, "SELECT COUNT(*) as n FROM scenes WHERE slug != 'all'",
                      default = data.frame(n = 0))$n
  as.character(count)
})

output$about_store_count <- renderText({
  req(rv$db_con)
  count <- dbGetQuery(rv$db_con, "SELECT COUNT(*) FROM stores WHERE is_active = TRUE")[[1]]
  as.character(count)
})

output$about_player_count <- renderText({
  req(rv$db_con)
  count <- dbGetQuery(rv$db_con, "SELECT COUNT(*) FROM players WHERE is_active = TRUE")[[1]]
  as.character(count)
})

output$about_tournament_count <- renderText({
  req(rv$db_con)
  count <- dbGetQuery(rv$db_con, "SELECT COUNT(*) FROM tournaments")[[1]]
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
    # Already logged in - show admin nav + logout
    role_label <- if (rv$is_superadmin) "super admin" else "admin"

    # Build admin nav links
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
      actionLink("modal_admin_decks",
                 tagList(bsicons::bs_icon("collection"), " Edit Decks"),
                 class = "admin-modal-link")
    )

    # Add super admin links if applicable
    superadmin_links <- NULL
    if (rv$is_superadmin) {
      superadmin_links <- tagList(
        tags$hr(class = "my-2"),
        tags$div(class = "admin-modal-section", "Super Admin"),
        actionLink("modal_admin_stores",
                   tagList(bsicons::bs_icon("shop"), " Edit Stores"),
                   class = "admin-modal-link"),
        actionLink("modal_admin_formats",
                   tagList(bsicons::bs_icon("calendar3"), " Edit Formats"),
                   class = "admin-modal-link")
      )
    }

    showModal(modalDialog(
      title = paste0("Admin (", role_label, ")"),
      div(
        class = "admin-modal-nav",
        admin_links,
        superadmin_links
      ),
      footer = tagList(
        actionButton("logout_btn", "Logout", class = "btn-warning"),
        modalButton("Close")
      )
    ))
  } else if (is.null(ADMIN_PASSWORD) && is.null(SUPERADMIN_PASSWORD)) {
    # Admin login disabled
    showModal(modalDialog(
      title = "Admin Login Disabled",
      "Admin login is not configured. Set the ADMIN_PASSWORD environment variable to enable.",
      footer = modalButton("Close")
    ))
  } else {
    # Show login form
    showModal(modalDialog(
      title = "Admin Login",
      passwordInput("admin_password", "Password"),
      footer = tagList(
        actionButton("login_btn", "Login", class = "btn-primary"),
        modalButton("Cancel")
      )
    ))
  }
})

# Handle login
observeEvent(input$login_btn, {
  pw <- input$admin_password

  if (!is.null(SUPERADMIN_PASSWORD) && pw == SUPERADMIN_PASSWORD) {
    rv$is_admin <- TRUE
    rv$is_superadmin <- TRUE
    removeModal()
    notify("Logged in as super admin", type = "message")
  } else if (!is.null(ADMIN_PASSWORD) && pw == ADMIN_PASSWORD) {
    rv$is_admin <- TRUE
    rv$is_superadmin <- FALSE
    removeModal()
    notify("Logged in as admin", type = "message")
  } else {
    notify("Invalid password", type = "error")
    return()
  }

  # Update dropdowns with data
  updateSelectInput(session, "tournament_store",
                    choices = get_store_choices(rv$db_con, include_none = TRUE))
})

# Handle logout
observeEvent(input$logout_btn, {
  rv$is_admin <- FALSE
  rv$is_superadmin <- FALSE
  rv$active_tournament_id <- NULL
  removeModal()
  notify("Logged out", type = "message")
  # Navigate back to dashboard
  nav_select("main_content", "dashboard")
  rv$current_nav <- "dashboard"
})

# ---------------------------------------------------------------------------
# Helper Functions
# ---------------------------------------------------------------------------

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
#' result <- safe_query(rv$db_con, "SELECT * FROM players")
#'
#' # Parameterized query
#' result <- safe_query(rv$db_con, "SELECT * FROM players WHERE player_id = ?",
#'                      params = list(42))
#'
#' # Custom default for aggregations
#' result <- safe_query(rv$db_con, "SELECT COUNT(*) as n FROM results",
#'                      default = data.frame(n = 0))
safe_query <- function(db_con, query, params = NULL, default = data.frame()) {
  # Try the query
  result <- tryCatch({
    if (!is.null(params) && length(params) > 0) {
      DBI::dbGetQuery(db_con, query, params = params)
    } else {
      DBI::dbGetQuery(db_con, query)
    }
  }, error = function(e) {
    msg <- conditionMessage(e)
    # Log the error with truncated query
    query_preview <- substr(gsub("\\s+", " ", query), 1, 200)
    message("[safe_query] Error: ", msg, " | Query: ", query_preview)

    # Attempt reconnection if connection is invalid
    if (!DBI::dbIsValid(db_con)) {
      message("[safe_query] Connection invalid, attempting reconnection...")
      tryCatch({
        new_con <- connect_db()
        # Update the shared reactive connection
        rv$db_con <- new_con
        message("[safe_query] Reconnected successfully")

        # Retry the query with new connection
        if (!is.null(params) && length(params) > 0) {
          return(DBI::dbGetQuery(new_con, query, params = params))
        } else {
          return(DBI::dbGetQuery(new_con, query))
        }
      }, error = function(e2) {
        message("[safe_query] Reconnection failed: ", conditionMessage(e2))
        return(NULL)
      })
    }

    NULL
  })

  if (is.null(result)) default else result
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
#' rows <- safe_execute(rv$db_con, "DELETE FROM results WHERE result_id = ?",
#'                      params = list(42))
safe_execute <- function(db_con, query, params = NULL) {
  tryCatch({
    if (!is.null(params) && length(params) > 0) {
      DBI::dbExecute(db_con, query, params = params)
    } else {
      DBI::dbExecute(db_con, query)
    }
  }, error = function(e) {
    message("[safe_execute] Error: ", conditionMessage(e))
    message("[safe_execute] Query: ", substr(gsub("\\s+", " ", query), 1, 200))
    0  # Return 0 rows affected on error
  })
}

get_store_choices <- function(con, include_none = FALSE) {
  if (is.null(con) || !dbIsValid(con)) return(c("Loading..." = ""))
  stores <- dbGetQuery(con, "SELECT store_id, name FROM stores WHERE is_active = TRUE ORDER BY name")
  choices <- setNames(stores$store_id, stores$name)
  if (include_none) {
    choices <- c("Select a store..." = "", choices)
  }
  return(choices)
}

get_archetype_choices <- function(con) {
  if (is.null(con) || !dbIsValid(con)) return(c("Loading..." = ""))
  archetypes <- dbGetQuery(con, "SELECT archetype_id, archetype_name FROM deck_archetypes WHERE is_active = TRUE ORDER BY archetype_name")
  choices <- setNames(archetypes$archetype_id, archetypes$archetype_name)
  return(choices)
}

get_player_choices <- function(con) {
  if (is.null(con) || !dbIsValid(con)) return(character(0))
  players <- dbGetQuery(con, "SELECT player_id, display_name FROM players WHERE is_active = TRUE ORDER BY display_name")
  choices <- setNames(players$player_id, players$display_name)
  return(choices)
}

get_format_choices <- function(con) {
  if (is.null(con) || !dbIsValid(con)) {
    return(c("Database unavailable" = ""))
  }
  formats <- dbGetQuery(con, "
    SELECT format_id, display_name
    FROM formats
    WHERE is_active = TRUE
    ORDER BY release_date DESC NULLS LAST
  ")
  if (nrow(formats) == 0) {
    return(c("No formats configured" = ""))
  }
  choices <- setNames(formats$format_id, formats$display_name)
  return(choices)
}

# Update format dropdowns when database connects or formats change
observe({
  # Trigger on db connection and format refresh
  rv$db_con
  rv$format_refresh

  if (!is.null(rv$db_con) && dbIsValid(rv$db_con)) {
    format_choices <- get_format_choices(rv$db_con)

    # Format choices with "All Formats" option
    format_choices_with_all <- list(
      "All Formats" = "",
      "Recent Formats" = format_choices
    )

    # Update all format dropdowns (default to All Formats to avoid empty results when new format has no data)
    updateSelectInput(session, "dashboard_format", choices = format_choices_with_all, selected = "")
    updateSelectInput(session, "players_format", choices = format_choices_with_all)
    updateSelectInput(session, "meta_format", choices = format_choices_with_all)
    updateSelectInput(session, "tournaments_format", choices = format_choices_with_all)
    updateSelectInput(session, "tournament_format", choices = format_choices)
  }
})

# Reactive: get the latest (current) format_id
get_latest_format_id <- reactive({
  if (is.null(rv$db_con) || !DBI::dbIsValid(rv$db_con)) return(NULL)
  result <- safe_query(rv$db_con,
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
  store <- safe_query(rv$db_con,
    "SELECT name FROM stores WHERE slug = ?",
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
#'   - sql: SQL fragment with ? placeholders (e.g., "AND t.format = ?")
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
#' # filters$sql: "AND t.format = ? AND t.event_type = ? AND s.scene_id = (SELECT scene_id FROM scenes WHERE slug = ?)"
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
                                 community_store = NULL) {
  sql_parts <- character(0)
  params <- list()

  # Format filter (exact match)
  if (!is.null(format) && format != "") {
    sql_parts <- c(sql_parts, sprintf("AND %s.format = ?", table_alias))
    params <- c(params, list(format))
  }

  # Event type filter (exact match)
  if (!is.null(event_type) && event_type != "") {
    sql_parts <- c(sql_parts, sprintf("AND %s.event_type = ?", table_alias))
    params <- c(params, list(event_type))
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
    sql_parts <- c(sql_parts, sprintf("AND LOWER(%s) LIKE LOWER(?)", col_ref))
    params <- c(params, list(paste0("%", search_term, "%")))
  }

  # ID filter (exact match)
  if (!is.null(id) && !is.na(id)) {
    # Use table alias if id_column doesn't contain a dot
    col_ref <- if (grepl("\\.", id_column)) {
      id_column
    } else {
      sprintf("%s.%s", table_alias, id_column)
    }
    sql_parts <- c(sql_parts, sprintf("AND %s = ?", col_ref))
    params <- c(params, list(as.integer(id)))
  }

  # Community filter (store-specific filtering - takes precedence over scene filter)
  if (!is.null(community_store) && community_store != "" && !is.null(store_alias)) {
    sql_parts <- c(sql_parts, sprintf("AND %s.slug = ?", store_alias))
    params <- c(params, list(community_store))
  } else {
    # Scene filter (requires store_alias to be set)
    if (!is.null(scene) && scene != "" && scene != "all" && !is.null(store_alias)) {
      if (scene == "online") {
        # Online scene filters by is_online flag (no parameter needed)
        sql_parts <- c(sql_parts, sprintf("AND %s.is_online = TRUE", store_alias))
      } else {
        # Regular scene filters by scene_id via slug lookup
        sql_parts <- c(sql_parts, sprintf(
          "AND %s.scene_id = (SELECT scene_id FROM scenes WHERE slug = ?)",
          store_alias
        ))
        params <- c(params, list(scene))
      }
    }
  }

  list(
    sql = paste(sql_parts, collapse = " "),
    params = params,
    any_active = length(params) > 0
  )
}
