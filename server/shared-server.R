# =============================================================================
# Shared Server Logic
# Contains: Database connection, navigation, authentication, helper functions
# =============================================================================

# ---------------------------------------------------------------------------
# Shared Helper: Current Admin Username
# Used for audit columns (updated_by) on admin edits
# ---------------------------------------------------------------------------

current_admin_username <- function(rv) {
  rv$admin_user$username %||% "unknown"
}

# ---------------------------------------------------------------------------
# Shared Helper: Fuzzy Match Check (pg_trgm)
# ---------------------------------------------------------------------------

find_similar_stores <- function(pool, store_name, scene_id) {
  safe_query(pool, "
    SELECT name, city,
           similarity(LOWER(name), LOWER($1)) AS sim
    FROM stores
    WHERE is_active = TRUE AND scene_id = $2
      AND similarity(LOWER(name), LOWER($1)) > 0.3
    ORDER BY sim DESC
    LIMIT 5
  ", params = list(store_name, as.integer(scene_id)),
  default = data.frame(name = character(), city = character(), sim = numeric()))
}

find_similar_scenes <- function(pool, city_name) {
  # Two-pronged search:
  # 1. Fuzzy match against scene display names
  # 2. Check if any store city matches — surfaces the parent scene
  safe_query(pool, "
    SELECT display_name, MAX(sim) AS sim FROM (
      SELECT display_name, similarity(LOWER(display_name), LOWER($1)) AS sim
      FROM scenes
      WHERE is_active = TRUE
        AND similarity(LOWER(display_name), LOWER($1)) > 0.25

      UNION ALL

      SELECT sc.display_name, similarity(LOWER(s.city), LOWER($1)) AS sim
      FROM stores s
      JOIN scenes sc ON s.scene_id = sc.scene_id
      WHERE s.is_active = TRUE AND sc.is_active = TRUE
        AND similarity(LOWER(s.city), LOWER($1)) > 0.4
    ) matches
    GROUP BY display_name
    ORDER BY MAX(sim) DESC
    LIMIT 5
  ", params = list(city_name),
  default = data.frame(display_name = character(), sim = numeric()))
}

show_fuzzy_match_modal <- function(matches_ui, original_action_id, title, icon) {
  showModal(modalDialog(
    title = tagList(bsicons::bs_icon(icon), " ", title),
    div(
      div(class = "alert alert-warning d-flex align-items-start gap-2 mb-3",
        bsicons::bs_icon("exclamation-triangle-fill", class = "flex-shrink-0 mt-1"),
        div("We found similar entries that already exist. Is this a duplicate?")
      ),
      matches_ui,
      div(class = "text-muted small mt-3",
        "If none of these match, go ahead and submit.")
    ),
    footer = tagList(
      actionButton(paste0(original_action_id, "_cancel_fuzzy"), "Go Back & Edit", class = "btn-secondary"),
      actionButton(paste0(original_action_id, "_confirm_fuzzy"), "Not a Duplicate — Submit", class = "btn-primary")
    ),
    easyClose = TRUE
  ))
}

# ---------------------------------------------------------------------------
# Shared Helper: Store Request Modal
# ---------------------------------------------------------------------------

show_store_request_modal <- function(prefill = NULL) {
  scenes <- safe_query(db_pool,
    "SELECT scene_id, display_name FROM scenes WHERE is_active = TRUE ORDER BY display_name",
    default = data.frame())

  scene_choices <- list()
  if (nrow(scenes) > 0) {
    scene_choices <- setNames(as.character(scenes$scene_id), scenes$display_name)
  }

  # Pre-select: use prefill if returning from fuzzy check, else current scene
  selected_scene <- prefill$scene_id
  if (is.null(selected_scene) && !is.null(rv$current_scene) && !rv$current_scene %in% c("all", "online")) {
    scene_row <- safe_query(db_pool,
      "SELECT scene_id FROM scenes WHERE slug = $1",
      params = list(rv$current_scene), default = data.frame())
    if (nrow(scene_row) > 0) selected_scene <- as.character(scene_row$scene_id[1])
  }

  showModal(modalDialog(
    title = tagList(bsicons::bs_icon("shop"), " Request a Store"),
    div(
      selectInput("store_req_scene", "Scene / Area *",
                  choices = scene_choices,
                  selected = selected_scene,
                  selectize = FALSE),
      textInput("store_req_name", "Store Name *", value = prefill$store_name %||% ""),
      textInput("store_req_city", "City *", value = prefill$city %||% ""),
      textInput("store_req_state", "State / Country *",
                value = prefill$state %||% "",
                placeholder = "e.g., TX or Germany"),
      textInput("store_req_discord", "Your Discord Username *",
                value = prefill$discord_username %||% "",
                placeholder = "So we can follow up"),
      tags$small(class = "form-text text-muted d-block mt-2",
                 "Don't see your scene? Use ",
                 actionLink("store_req_switch_to_scene", "Request a Scene"),
                 " instead.")
    ),
    footer = tagList(
      modalButton("Cancel"),
      actionButton("submit_store_request", "Submit", class = "btn-primary")
    ),
    easyClose = TRUE
  ))
}

# ---------------------------------------------------------------------------
# Shared Helper: Scene Request Modal
# ---------------------------------------------------------------------------

show_scene_request_modal <- function(prefill = NULL) {
  showModal(modalDialog(
    title = tagList(bsicons::bs_icon("globe2"), " Request a Scene"),
    div(
      tags$p(class = "text-muted mb-3",
             "Request a new scene for your city or region. We'll review and set it up."),
      textInput("scene_req_name", "City / Area Name *",
                value = prefill$city_name %||% "",
                placeholder = "e.g., Houston, S\u00e3o Paulo, Berlin"),
      textInput("scene_req_state", "State / Country *",
                value = prefill$state %||% "",
                placeholder = "e.g., TX, Brazil, Germany"),
      textAreaInput("scene_req_stores", "Known Stores (optional)",
                    value = prefill$stores %||% "",
                    placeholder = "List any stores that run Digimon TCG locals in this area, one per line",
                    rows = 3),
      textAreaInput("scene_req_notes", "Additional Info (optional)",
                    value = prefill$notes %||% "",
                    placeholder = "e.g., We run weekly locals with 8-12 players",
                    rows = 2),
      textInput("scene_req_discord", "Your Discord Username *",
                value = prefill$discord_username %||% "",
                placeholder = "So we can follow up"),
      div(class = "mt-2 text-center",
        tags$a(
          href = LINKS$discord, target = "_blank",
          class = "btn btn-sm btn-outline-primary",
          bsicons::bs_icon("discord", class = "me-1"),
          "Join our Discord"
        )
      )
    ),
    footer = tagList(
      modalButton("Cancel"),
      actionButton("submit_scene_request", "Submit", class = "btn-primary")
    ),
    easyClose = TRUE
  ))
}

# ---------------------------------------------------------------------------
# Database Connection
# ---------------------------------------------------------------------------

observe({
  # Batch startup checks into a single query
  startup <- tryCatch(
    dbGetQuery(db_pool, "
      SELECT
        (SELECT COUNT(*) FROM player_ratings_cache) as ratings_count,
        (SELECT COUNT(*) FROM admin_users) as admin_count
    "),
    error = function(e) {
      message("[startup] Database check failed: ", e$message)
      data.frame(ratings_count = NA, admin_count = 0)
    }
  )

  ratings_count <- startup$ratings_count %||% 0
  if (is.na(ratings_count) || ratings_count == 0) {
    message("[startup] Ratings cache empty, populating...")
    tryCatch({
      recalculate_ratings_cache(db_pool)
      message("[startup] Ratings cache populated")
    }, error = function(e) {
      message("[startup] Could not populate ratings cache: ", e$message)
    })
  }

  admin_count <- startup$admin_count %||% 0
  if (is.na(admin_count) || admin_count == 0) {
    rv$needs_bootstrap <- TRUE
  }

  session$sendCustomMessage("hideLoading", list())
}) |> bindEvent(TRUE, once = TRUE)

# Keepalive handler - receiving the input is enough to keep connection alive
observeEvent(input$keepalive_ping, {
  # No-op: just receiving this keeps the WebSocket active
}, ignoreInit = TRUE)

# ---------------------------------------------------------------------------
# Device Detection
# ---------------------------------------------------------------------------

is_mobile <- reactive({
  info <- input$device_info
  if (is.null(info)) return(FALSE)
  info$type == "mobile"
})

# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------

# Track which tabs have been visited for lazy data loading.
# Dashboard is pre-visited since it's the default landing tab.
visited_tabs <- reactiveVal("dashboard")

# Mark current tab as visited whenever navigation changes
observeEvent(rv$current_nav, {
  current <- rv$current_nav
  visited <- visited_tabs()
  if (!current %in% visited) {
    visited_tabs(c(visited, current))
  }
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

# ---------------------------------------------------------------------------
# Header Help Dropdown Actions
# ---------------------------------------------------------------------------

# Help & Resources modal (three-dot menu)
observeEvent(input$help_menu_link, {
  showModal(modalDialog(
    title = tagList(bsicons::bs_icon("three-dots-vertical"), " Help & Resources"),
    # Links section
    tags$div(class = "help-modal-section-label", "LINKS"),
    div(
      class = "help-modal-group",
      tags$a(href = "https://digilab.cards/faq",
             target = "_blank", rel = "noopener noreferrer",
             class = "help-modal-item",
             bsicons::bs_icon("question-circle"),
             span("FAQ"),
             bsicons::bs_icon("box-arrow-up-right", class = "help-modal-external")),
      tags$a(href = "https://digilab.cards/organizers",
             target = "_blank", rel = "noopener noreferrer",
             class = "help-modal-item",
             bsicons::bs_icon("person-badge"),
             span("For Organizers"),
             bsicons::bs_icon("box-arrow-up-right", class = "help-modal-external")),
      tags$a(href = "https://digilab.cards/roadmap",
             target = "_blank", rel = "noopener noreferrer",
             class = "help-modal-item",
             bsicons::bs_icon("map"),
             span("Roadmap"),
             bsicons::bs_icon("box-arrow-up-right", class = "help-modal-external"))
    ),
    # Actions section
    tags$div(class = "help-modal-section-label", "ACTIONS"),
    div(
      class = "help-modal-group",
      actionLink("help_modal_bug_report",
                 tagList(bsicons::bs_icon("bug"), span("Report a Bug")),
                 class = "help-modal-item"),
      actionLink("help_modal_store_request",
                 tagList(bsicons::bs_icon("shop"), span("Request a Store")),
                 class = "help-modal-item"),
      actionLink("help_modal_scene_request",
                 tagList(bsicons::bs_icon("globe2"), span("Request a Scene")),
                 class = "help-modal-item")
    ),
    # Upload (mobile only)
    div(
      class = "help-modal-mobile-only",
      tags$div(class = "help-modal-section-label", "QUICK NAV"),
      div(
        class = "help-modal-group",
        actionLink("help_modal_upload",
                   tagList(bsicons::bs_icon("cloud-upload"), span("Upload Results")),
                   class = "help-modal-item")
      )
    ),
    footer = modalButton("Close"),
    easyClose = TRUE
  ))
})

# Help modal actions
observeEvent(input$help_modal_bug_report, {
  removeModal()
  show_bug_report_modal()
})

observeEvent(input$help_modal_store_request, {
  removeModal()
  show_store_request_modal()
})

observeEvent(input$help_modal_scene_request, {
  removeModal()
  show_scene_request_modal()
})

# Switch from store request modal to scene request modal
observeEvent(input$store_req_switch_to_scene, {
  removeModal()
  show_scene_request_modal()
})

observeEvent(input$help_modal_upload, {
  removeModal()
  nav_select("main_content", "submit")
  rv$current_nav <- "submit"
  session$sendCustomMessage("updateSidebarNav", "nav_submit")
})

# ---------------------------------------------------------------------------
# FAQ Navigation from Info Icons (open external FAQ instead)
# ---------------------------------------------------------------------------

observeEvent(input$goto_faq_rating, {
  # Open external FAQ page in new tab
  shinyjs::runjs("window.open('https://digilab.cards/faq#competitive-rating', '_blank');")
})

observeEvent(input$goto_faq_score, {
  # Open external FAQ page in new tab
  shinyjs::runjs("window.open('https://digilab.cards/faq#achievement-score', '_blank');")
})

# ---------------------------------------------------------------------------
# Data Error Report Modal (shared across player/tournament/deck modals)
# ---------------------------------------------------------------------------

# Reactive to store context for the data error report
data_error_context <- reactiveValues(
  item_type = NULL,
  item_name = NULL,
  scene_id = NULL
)

# Player modal → data error report
observeEvent(input$report_error_player, {
  player <- tryCatch(
    safe_query(db_pool,
      "SELECT display_name FROM players WHERE player_id = $1",
      params = list(rv$selected_player_id),
      default = data.frame()),
    error = function(e) data.frame()
  )
  # Look up scene from the player's most recent tournament
  player_scene <- tryCatch(
    safe_query(db_pool,
      "SELECT s.scene_id FROM results r
       JOIN tournaments t ON r.tournament_id = t.tournament_id
       JOIN stores s ON t.store_id = s.store_id
       WHERE r.player_id = $1 AND s.scene_id IS NOT NULL
       ORDER BY t.event_date DESC LIMIT 1",
      params = list(rv$selected_player_id),
      default = data.frame()),
    error = function(e) data.frame()
  )
  data_error_context$item_type <- "Player"
  data_error_context$item_name <- if (nrow(player) > 0) player$display_name[1] else "Unknown"
  data_error_context$scene_id <- if (nrow(player_scene) > 0) player_scene$scene_id[1] else NULL
  show_data_error_modal(data_error_context$item_type, data_error_context$item_name)
})

# Tournament modal → data error report
observeEvent(input$report_error_tournament, {
  tourn <- tryCatch(
    safe_query(db_pool,
      "SELECT t.event_date, s.name as store_name, s.scene_id
       FROM tournaments t JOIN stores s ON t.store_id = s.store_id
       WHERE t.tournament_id = $1",
      params = list(rv$selected_tournament_id),
      default = data.frame()),
    error = function(e) data.frame()
  )
  data_error_context$item_type <- "Tournament"
  data_error_context$item_name <- if (nrow(tourn) > 0) {
    paste0(tourn$store_name[1], " - ", tourn$event_date[1])
  } else "Unknown"
  data_error_context$scene_id <- if (nrow(tourn) > 0 && !is.na(tourn$scene_id[1])) tourn$scene_id[1] else NULL
  show_data_error_modal(data_error_context$item_type, data_error_context$item_name)
})

# Deck modal → data error report
observeEvent(input$report_error_deck, {
  deck <- tryCatch(
    safe_query(db_pool,
      "SELECT archetype_name FROM deck_archetypes WHERE archetype_id = $1",
      params = list(rv$selected_archetype_id),
      default = data.frame()),
    error = function(e) data.frame()
  )
  data_error_context$item_type <- "Deck"
  data_error_context$item_name <- if (nrow(deck) > 0) deck$archetype_name[1] else "Unknown"
  data_error_context$scene_id <- NULL  # Decks are global, no inherent scene
  show_data_error_modal(data_error_context$item_type, data_error_context$item_name)
})

# Helper to show the data error modal
show_data_error_modal <- function(item_type, item_name) {
  # Clear previous values
  updateTextAreaInput(session, "data_error_description", value = "")
  updateTextInput(session, "data_error_discord", value = "")

  showModal(modalDialog(
    title = tagList(bsicons::bs_icon("flag"), " Report Data Error"),
    div(
      div(class = "mb-3 p-2 rounded", style = "background: rgba(255,255,255,0.05);",
        tags$small(class = "text-muted", "Reporting error for:"),
        tags$div(class = "fw-bold", paste(item_type, "-", item_name))
      ),
      textAreaInput("data_error_description", "What's wrong?",
                    placeholder = "Describe the error (e.g., 'Deck should be Blue Flare, not Jesmon')",
                    rows = 3),
      textInput("data_error_discord", "Your Discord Username *",
                placeholder = "So we can follow up")
    ),
    footer = tagList(
      modalButton("Cancel"),
      actionButton("submit_data_error", "Submit Report", class = "btn-primary")
    ),
    size = "m",
    easyClose = TRUE
  ))
}

# Handle data error submission
observeEvent(input$submit_data_error, {
  description <- trimws(input$data_error_description)

  if (nchar(description) == 0) {
    notify("Please describe the error", type = "warning")
    return()
  }

  discord_username <- trimws(input$data_error_discord)
  if (nchar(discord_username) == 0) {
    notify("Discord username is required so we can follow up", type = "warning")
    return()
  }

  tryCatch({
    # Use item's scene first (from tournament/player), fall back to user's selected scene
    scene_id <- data_error_context$scene_id
    if (is.null(scene_id) && !is.null(rv$current_scene) && rv$current_scene != "all") {
      scene_row <- safe_query(db_pool,
        "SELECT scene_id FROM scenes WHERE slug = $1",
        params = list(rv$current_scene),
        default = data.frame())
      if (nrow(scene_row) > 0) scene_id <- scene_row$scene_id[1]
    }

    # Persist to admin_requests table
    payload <- list(
      context = paste(data_error_context$item_type, "-", data_error_context$item_name),
      description = description
    )
    safe_execute(db_pool, "
      INSERT INTO admin_requests (request_type, scene_id, payload, discord_username)
      VALUES ($1, $2, $3, $4)
    ", params = list("data_error", scene_id, jsonlite::toJSON(payload, auto_unbox = TRUE), discord_username))

    # Fire Discord webhook
    if (!is.null(scene_id)) {
      discord_post_data_error(
        scene_id = scene_id,
        item_type = data_error_context$item_type,
        item_name = data_error_context$item_name,
        description = description,
        discord_username = discord_username,
        db_pool = db_pool
      )
    } else {
      discord_post_bug_report(
        title = paste("Data Error:", data_error_context$item_type, "-", data_error_context$item_name),
        description = description,
        context = paste("Tab:", rv$current_nav),
        discord_username = discord_username
      )
    }

    # Refresh notification bar
    rv$requests_refresh <- (rv$requests_refresh %||% 0) + 1

    removeModal()
    notify("Error report submitted! We'll follow up on Discord.", type = "message", duration = 5)
  }, error = function(e) {
    warning(paste("Data error report failed:", e$message))
    removeModal()
    notify("Report received but couldn't send to Discord. We'll follow up manually.", type = "warning", duration = 5)
  })
})

# ---------------------------------------------------------------------------
# Bug Report Modal (general bugs — footer + content pages)
# ---------------------------------------------------------------------------

show_bug_report_modal <- function() {
  # Clear previous values
  updateTextInput(session, "bug_report_title", value = "")
  updateTextAreaInput(session, "bug_report_description", value = "")
  updateTextInput(session, "bug_report_discord", value = "")

  showModal(modalDialog(
    title = tagList(bsicons::bs_icon("bug"), " Report a Bug"),
    div(
      textInput("bug_report_title", "Title",
                placeholder = "Brief summary of the issue"),
      textAreaInput("bug_report_description", "What happened?",
                    placeholder = "What were you trying to do? What went wrong?",
                    rows = 4),
      textInput("bug_report_discord", "Your Discord Username *",
                placeholder = "So we can follow up")
    ),
    footer = tagList(
      modalButton("Cancel"),
      actionButton("submit_bug_report", "Submit Report", class = "btn-primary")
    ),
    size = "m",
    easyClose = TRUE
  ))
}

# Handle bug report submission
observeEvent(input$submit_bug_report, {
  title <- trimws(input$bug_report_title)
  description <- trimws(input$bug_report_description)

  if (nchar(title) == 0) {
    notify("Please provide a title", type = "warning")
    return()
  }
  if (nchar(description) == 0) {
    notify("Please describe the issue", type = "warning")
    return()
  }

  discord_username <- trimws(input$bug_report_discord)
  if (nchar(discord_username) == 0) {
    notify("Discord username is required so we can follow up", type = "warning")
    return()
  }

  tryCatch({
    context_parts <- c()
    if (!is.null(rv$current_nav)) context_parts <- c(context_parts, paste("Tab:", rv$current_nav))
    if (!is.null(rv$current_scene) && rv$current_scene != "all") {
      context_parts <- c(context_parts, paste("Scene:", rv$current_scene))
    }
    context <- paste(context_parts, collapse = ", ")

    # Persist to admin_requests table
    payload <- list(title = title, description = description, context = context)
    safe_execute(db_pool, "
      INSERT INTO admin_requests (request_type, scene_id, payload, discord_username)
      VALUES ($1, NULL, $2, $3)
    ", params = list("bug_report", jsonlite::toJSON(payload, auto_unbox = TRUE), discord_username))

    # Fire Discord webhook
    discord_post_bug_report(
      title = title,
      description = description,
      context = context,
      discord_username = discord_username
    )

    # Refresh notification bar
    rv$requests_refresh <- (rv$requests_refresh %||% 0) + 1

    removeModal()
    notify("Bug report submitted! We'll follow up on Discord.", type = "message", duration = 5)
  }, error = function(e) {
    warning(paste("Bug report failed:", e$message))
    removeModal()
    notify("Report received but couldn't send to Discord. We'll follow up manually.", type = "warning", duration = 5)
  })
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
    admin_name <- rv$admin_user$username

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
    "SELECT user_id, username, password_hash, discord_user_id, role, scene_id
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
    discord_user_id = user$discord_user_id[1],
    role = user$role[1],
    scene_id = if (is.na(user$scene_id[1])) NULL else user$scene_id[1]
  )

  removeModal()
  notify(paste0("Welcome, ", user$username[1], "!"), type = "message")

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
  password <- input$bootstrap_password
  confirm <- input$bootstrap_confirm

  # Validation
  if (nchar(username) < 3) {
    notify("Username must be at least 3 characters", type = "warning")
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
    "INSERT INTO admin_users (username, password_hash, role, scene_id)
     VALUES ($1, $2, 'super_admin', NULL) RETURNING user_id",
    params = list(username, hash),
    default = data.frame())

  if (nrow(result) > 0) {
    new_id <- result$user_id[1]
    rv$needs_bootstrap <- FALSE
    rv$is_admin <- TRUE
    rv$is_superadmin <- TRUE
    rv$admin_user <- list(
      user_id = new_id,
      username = username,
      discord_user_id = NA_character_,
      role = "super_admin",
      scene_id = NULL
    )
    removeModal()
    notify(paste0("Super admin account created. Welcome, ", username, "!"), type = "message")

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

  # Check if UI has rendered yet (tournament_date is a sibling input that's always visible)
  if (is.null(input$tournament_date)) {
    # UI not ready yet, retry shortly
    invalidateLater(100)
    return()
  }

  # Preserve current selection when repopulating choices
  current_selection <- isolate(input$tournament_store)
  store_choices <- get_store_choices(db_pool, include_none = TRUE)
  updateSelectInput(session, "tournament_store",
                    choices = store_choices,
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
  # Helper to detect retryable connection pool / prepared statement errors
  is_prepared_stmt_error <- function(msg) {
    grepl("prepared statement", msg, ignore.case = TRUE) ||
    grepl("bind message supplies", msg, ignore.case = TRUE) ||
    grepl("needs to be bound", msg, ignore.case = TRUE) ||
    grepl("multiple queries.*same column", msg, ignore.case = TRUE) ||
    grepl("Query requires \\d+ params", msg, ignore.case = TRUE) ||
    grepl("invalid input syntax", msg, ignore.case = TRUE)
  }

  # Time the query for performance monitoring
  start_time <- proc.time()[["elapsed"]]

  # First attempt
  result <- tryCatch({
    if (!is.null(params) && length(params) > 0) {
      DBI::dbGetQuery(pool, query, params = params)
    } else {
      DBI::dbGetQuery(pool, query)
    }
  }, error = function(e) e)

  # If prepared statement error, retry once (connection pool may have stale state)
  if (inherits(result, "error") && is_prepared_stmt_error(conditionMessage(result))) {
    message("[safe_query] Prepared statement error, retrying: ", conditionMessage(result))
    Sys.sleep(0.1)  # Brief pause before retry
    result <- tryCatch({
      if (!is.null(params) && length(params) > 0) {
        DBI::dbGetQuery(pool, query, params = params)
      } else {
        DBI::dbGetQuery(pool, query)
      }
    }, error = function(e) e)
  }

  # Log slow queries (>200ms)
  elapsed_ms <- (proc.time()[["elapsed"]] - start_time) * 1000
  if (elapsed_ms > 200) {
    query_preview <- substr(gsub("\\s+", " ", trimws(query)), 1, 120)
    rows <- if (is.data.frame(result)) nrow(result) else "?"
    message(sprintf("[SLOW QUERY %.0fms, %s rows] %s", elapsed_ms, rows, query_preview))
  }

  # Handle final result
  if (inherits(result, "error")) {
    query_preview <- substr(gsub("\\s+", " ", query), 1, 500)
    params_preview <- if (!is.null(params)) paste(sapply(params, as.character), collapse = ", ") else "NULL"
    message("[safe_query] Error: ", conditionMessage(result), " | Query: ", query_preview, " | Params: ", params_preview)
    if (sentry_enabled) {
      tryCatch(
        sentryR::capture_exception(result, tags = c(
          sentry_context_tags(),
          list(query_preview = query_preview, params = params_preview)
        )),
        error = function(se) NULL
      )
    }
    return(default)
  }

  result
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
  # Helper to detect retryable connection pool / prepared statement errors
  is_prepared_stmt_error <- function(msg) {
    grepl("prepared statement", msg, ignore.case = TRUE) ||
    grepl("bind message supplies", msg, ignore.case = TRUE) ||
    grepl("needs to be bound", msg, ignore.case = TRUE) ||
    grepl("multiple queries.*same column", msg, ignore.case = TRUE) ||
    grepl("Query requires \\d+ params", msg, ignore.case = TRUE) ||
    grepl("invalid input syntax", msg, ignore.case = TRUE)
  }

  # Time the query for performance monitoring
  start_time <- proc.time()[["elapsed"]]

  # First attempt
  result <- tryCatch({
    if (!is.null(params) && length(params) > 0) {
      DBI::dbExecute(pool, query, params = params)
    } else {
      DBI::dbExecute(pool, query)
    }
  }, error = function(e) e)

  # If prepared statement error, retry once (connection pool may have stale state)
  if (inherits(result, "error") && is_prepared_stmt_error(conditionMessage(result))) {
    message("[safe_execute] Prepared statement error, retrying: ", conditionMessage(result))
    Sys.sleep(0.1)  # Brief pause before retry
    result <- tryCatch({
      if (!is.null(params) && length(params) > 0) {
        DBI::dbExecute(pool, query, params = params)
      } else {
        DBI::dbExecute(pool, query)
      }
    }, error = function(e) e)
  }

  # Log slow writes (>200ms)
  elapsed_ms <- (proc.time()[["elapsed"]] - start_time) * 1000
  if (elapsed_ms > 200) {
    query_preview <- substr(gsub("\\s+", " ", trimws(query)), 1, 120)
    message(sprintf("[SLOW EXECUTE %.0fms] %s", elapsed_ms, query_preview))
  }

  # Handle final result
  if (inherits(result, "error")) {
    message("[safe_execute] Error: ", conditionMessage(result))
    message("[safe_execute] Query: ", substr(gsub("\\s+", " ", query), 1, 200))
    if (sentry_enabled) {
      tryCatch(sentryR::capture_exception(result, tags = sentry_context_tags()), error = function(se) NULL)
    }
    return(0)
  }

  result
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
  if (nrow(formats) == 0 || !"format_id" %in% names(formats)) {
    return(c("No formats configured" = ""))
  }
  choices <- setNames(formats$format_id, formats$display_name)
  return(choices)
}

# Format choices with "All Formats" header for selectInputs.
# Called inside each page's renderUI so choices are populated at render time.
get_format_choices_with_all <- function(pool) {
  list(
    "All Formats" = "",
    "Recent Formats" = get_format_choices(pool)
  )
}

# Update ADMIN format dropdown (Enter Results wizard)
# Only fires when on admin_results tab (prevents race condition with lazy-loaded UI)
observe({
  rv$current_nav
  req(rv$current_nav == "admin_results")
  rv$format_refresh
  req(rv$is_admin)

  # Check if UI has rendered yet (tournament_date is a sibling input that's always visible)
  if (is.null(input$tournament_date)) {
    # UI not ready yet, retry shortly
    invalidateLater(100)
    return()
  }

  format_choices <- get_format_choices(db_pool)
  current_tournament <- isolate(input$tournament_format)
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
  # Reset filters to dynamic default for current scene
 tournament_count <- count_tournaments_for_scope(db_pool, rv$current_scene, NULL)
  default_min <- get_default_min_events(tournament_count)
  session$sendCustomMessage("resetPillToggle", list(inputId = "players_min_events", value = default_min))
  session$sendCustomMessage("resetPillToggle", list(inputId = "meta_min_entries", value = default_min))
  notify("Community filter cleared", type = "message", duration = 2)
})

# -----------------------------------------------------------------------------
# Dynamic Min Events Helpers
# -----------------------------------------------------------------------------

#' Calculate default min_events based on tournament count
#'
#' Returns the appropriate default filter value for the min events pill toggle
#' based on how much tournament data exists for the current scope.
#'
#' @param tournament_count Integer count of tournaments
#' @return Character value for pill-toggle: "0" (All), "5" (5+), or "10" (10+)
get_default_min_events <- function(tournament_count) {
  if (is.null(tournament_count) || is.na(tournament_count)) {
    return("5")  # Fallback to current default
  }
  if (tournament_count < 20) {
    return("0")  # "All"
  } else if (tournament_count <= 100) {
    return("5")  # "5+"
  } else {
    return("10") # "10+"

  }
}

#' Count tournaments for the current view scope
#'
#' Returns the number of tournaments visible in the current scope, which is used
#' to determine the appropriate default min events filter.
#'
#' @param db_pool Database connection pool
#' @param scene_slug Current scene slug or "all"
#' @param community_slug Optional community filter slug (store slug)
#' @return Integer count of tournaments
count_tournaments_for_scope <- function(db_pool, scene_slug, community_slug = NULL) {
  if (!is.null(community_slug) && community_slug != "") {
    # Community view: count for specific store
    result <- safe_query(db_pool,
      "SELECT COUNT(*) as n FROM tournaments t JOIN stores s ON t.store_id = s.store_id WHERE s.slug = $1",
      params = list(community_slug),
      default = data.frame(n = 0))
  } else if (is.null(scene_slug) || scene_slug == "all") {
    # All scenes
    result <- safe_query(db_pool,
      "SELECT COUNT(*) as n FROM tournaments",
      default = data.frame(n = 0))
  } else if (scene_slug == "online") {
    # Online scene: count tournaments from online stores
    result <- safe_query(db_pool,
      "SELECT COUNT(*) as n FROM tournaments t JOIN stores s ON t.store_id = s.store_id WHERE s.is_online = TRUE",
      default = data.frame(n = 0))
  } else {
    # Specific scene
    result <- safe_query(db_pool,
      "SELECT COUNT(*) as n FROM tournaments t JOIN stores s ON t.store_id = s.store_id JOIN scenes sc ON s.scene_id = sc.scene_id WHERE sc.slug = $1",
      params = list(scene_slug),
      default = data.frame(n = 0))
  }
  return(result$n[1])
}

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

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
    "casuals" = "Casuals",
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

# ---------------------------------------------------------------------------
# Materialized View Helpers
# ---------------------------------------------------------------------------

# Build WHERE clause filters for materialized view queries.
# MV columns use flat names (no table aliases needed for JOINs).
# Set alias if using a table alias in the query (e.g., "mv").
build_mv_filters <- function(format = NULL,
                             event_type = NULL,
                             scene = NULL,
                             community_store = NULL,
                             search = NULL,
                             search_column = NULL,
                             start_idx = 1,
                             alias = NULL) {
  prefix <- if (!is.null(alias)) paste0(alias, ".") else ""
  sql_parts <- character(0)
  params <- list()
  idx <- start_idx

  # Format filter
  if (!is.null(format) && format != "") {
    sql_parts <- c(sql_parts, sprintf("AND %sformat = $%d", prefix, idx))
    params <- c(params, list(format))
    idx <- idx + 1
  }

  # Event type filter
  if (!is.null(event_type) && event_type != "") {
    sql_parts <- c(sql_parts, sprintf("AND %sevent_type = $%d", prefix, idx))
    params <- c(params, list(event_type))
    idx <- idx + 1
  }

  # Search filter (LIKE match, case-insensitive)
  if (!is.null(search) && trimws(search) != "" && !is.null(search_column)) {
    col_ref <- if (!is.null(alias)) sprintf("%s.%s", alias, search_column) else search_column
    sql_parts <- c(sql_parts, sprintf("AND LOWER(%s) LIKE LOWER($%d)", col_ref, idx))
    params <- c(params, list(paste0("%", trimws(search), "%")))
    idx <- idx + 1
  }

  # Community store filter (takes precedence over scene)
  if (!is.null(community_store) && community_store != "") {
    sql_parts <- c(sql_parts, sprintf("AND %sslug = $%d", prefix, idx))
    params <- c(params, list(community_store))
    idx <- idx + 1
  } else if (!is.null(scene) && scene != "" && scene != "all") {
    if (scene == "online") {
      sql_parts <- c(sql_parts, sprintf("AND %sis_online = TRUE", prefix))
    } else {
      sql_parts <- c(sql_parts, sprintf(
        "AND %sscene_id = (SELECT scene_id FROM scenes WHERE slug = $%d)", prefix, idx
      ))
      params <- c(params, list(scene))
      idx <- idx + 1
    }
  }

  list(
    sql = paste(sql_parts, collapse = " "),
    params = params,
    next_idx = idx
  )
}

# Refresh all materialized views concurrently.
# Called after data mutations (result submission, tournament edit, sync).
refresh_materialized_views <- function(pool) {
  views <- c("mv_player_store_stats", "mv_archetype_store_stats",
             "mv_tournament_list", "mv_store_summary", "mv_dashboard_counts")
  con <- pool::localCheckout(pool)
  for (v in views) {
    tryCatch(
      DBI::dbExecute(con, sprintf("REFRESH MATERIALIZED VIEW CONCURRENTLY %s", v)),
      error = function(e) message(sprintf("[MV REFRESH ERROR] %s: %s", v, e$message))
    )
  }
}

# Check if materialized views exist (used for graceful fallback)
mv_views_exist <- function(pool) {
  result <- tryCatch(
    dbGetQuery(pool, "
      SELECT COUNT(*) as n FROM pg_matviews
      WHERE matviewname IN ('mv_player_store_stats', 'mv_archetype_store_stats',
                            'mv_tournament_list', 'mv_store_summary', 'mv_dashboard_counts')
    "),
    error = function(e) data.frame(n = 0)
  )
  result$n[1] == 5
}

# Auto-refresh materialized views when data changes
observe({
  rv$data_refresh
  req(rv$data_refresh > 0)  # Skip initial value
  refresh_materialized_views(db_pool)
})
