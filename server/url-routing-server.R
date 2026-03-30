# =============================================================================
# URL Routing Server Logic
# Handles deep linking for shareable URLs
# =============================================================================

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

#' Generate URL-friendly slug from text (wrapper around shared generate_slug)
#' @param text String to slugify
#' @return Lowercase string with special chars replaced by hyphens
slugify <- function(text) {
  if (is.null(text) || is.na(text) || text == "") return("")
  result <- generate_slug(text)
  if (is.na(result)) "" else result
}

#' Parse query string into named list
#' @param query_string URL query string (with or without leading ?)
#' @return Named list of parameters
parse_url_params <- function(query_string) {
  if (is.null(query_string) || query_string == "") return(list())

  # Remove leading ?
query_string <- gsub("^\\?", "", query_string)
  if (query_string == "") return(list())

  # Split into key=value pairs
  pairs <- strsplit(query_string, "&")[[1]]
  params <- list()

  for (pair in pairs) {
    parts <- strsplit(pair, "=")[[1]]
    if (length(parts) == 2) {
      key <- utils::URLdecode(parts[1])
      value <- utils::URLdecode(parts[2])
      params[[key]] <- value
    }
  }

  params
}

#' Build URL query string from parameters
#' @param params Named list of parameters
#' @return Query string starting with ?
build_url_query <- function(params) {
  if (length(params) == 0) return("")

  # Filter out NULL/NA values
  params <- params[!sapply(params, function(x) is.null(x) || is.na(x) || x == "")]
  if (length(params) == 0) return("")

  pairs <- sapply(names(params), function(key) {
    paste0(utils::URLencode(key, reserved = TRUE), "=",
           utils::URLencode(as.character(params[[key]]), reserved = TRUE))
  })

  paste0("?", paste(pairs, collapse = "&"))
}

#' Send URL update to browser
#' @param session Shiny session
#' @param params Named list of URL parameters
#' @param replace If TRUE, replace current history entry; if FALSE, push new entry
update_browser_url <- function(session, params, replace = FALSE) {
  url <- build_url_query(params)
  message_type <- if (replace) "replaceUrl" else "pushUrl"
  session$sendCustomMessage(message_type, list(url = url, state = params))
}

# -----------------------------------------------------------------------------
# URL Parameter Handlers
# -----------------------------------------------------------------------------

# Process initial URL on app load
observeEvent(input$url_initial, {


  params <- parse_url_params(input$url_initial$search)
  if (length(params) == 0) return()

  # Process in order: scene -> tab -> entity modal

  # 1. Scene filter
  #    Resolve slug to Shiny-internal format (e.g., "texas" → "state:Texas")
  #    so the dropdown and filter builders work with the prefix convention.
  if (!is.null(params$scene)) {
    resolved_scene <- resolve_scene_slug(db_pool, params$scene)
    rv$current_scene <- resolved_scene

    # Derive continent from resolved scene value for proper dropdown sync
    if (startsWith(resolved_scene, "country:") || startsWith(resolved_scene, "state:")) {
      # Country/state scenes: look up continent from DB
      country_val <- if (startsWith(resolved_scene, "state:")) {
        parse_state_prefix(resolved_scene)$country
      } else {
        sub("^country:", "", resolved_scene)
      }
      cont <- safe_query(db_pool,
        "SELECT DISTINCT continent FROM scenes WHERE country = $1 AND continent IS NOT NULL LIMIT 1",
        params = list(country_val), default = data.frame(continent = "all"))
      if (nrow(cont) > 0 && !is.na(cont$continent[1])) {
        rv$current_continent <- cont$continent[1]
        updateSelectInput(session, "continent_selector", selected = cont$continent[1])
        session$sendCustomMessage("updateContinentIcon", get_continent_icon(cont$continent[1]))
      }
    } else if (resolved_scene == "online") {
      rv$current_continent <- "online"
      updateSelectInput(session, "continent_selector", selected = "online")
      session$sendCustomMessage("updateContinentIcon", get_continent_icon("online"))
    } else if (resolved_scene != "all") {
      # Regular metro slug: look up its continent
      cont <- safe_query(db_pool,
        "SELECT continent FROM scenes WHERE slug = $1 AND continent IS NOT NULL LIMIT 1",
        params = list(resolved_scene), default = data.frame(continent = "all"))
      if (nrow(cont) > 0 && !is.na(cont$continent[1])) {
        rv$current_continent <- cont$continent[1]
        updateSelectInput(session, "continent_selector", selected = cont$continent[1])
        session$sendCustomMessage("updateContinentIcon", get_continent_icon(cont$continent[1]))
      }
    }
  }

  # 1b. Community filter (store-specific view)
  if (!is.null(params$community)) {
    # Look up store by slug
    store <- safe_query(db_pool,
      "SELECT store_id, scene_id FROM stores WHERE slug = $1 AND is_active = TRUE",
      params = list(params$community),
      default = data.frame(store_id = integer(), scene_id = integer()))

    if (nrow(store) == 1) {
      rv$community_filter <- params$community
      # Also set scene to the store's scene if available
      if (!is.na(store$scene_id)) {
        scene_result <- safe_query(db_pool,
          "SELECT slug FROM scenes WHERE scene_id = $1",
          params = list(store$scene_id),
          default = data.frame(slug = character()))
        if (nrow(scene_result) == 1 && !is.na(scene_result$slug)) {
          rv$current_scene <- scene_result$slug
        }
      }
      shinyjs::delay(150, {
        session$sendCustomMessage("resetPillToggle", list(inputId = "players_min_events", value = "0"))
        session$sendCustomMessage("resetPillToggle", list(inputId = "meta_min_entries", value = "0"))
      })
    }
  }

  # 2. Tab navigation
  if (!is.null(params$tab)) {
    valid_tabs <- c("dashboard", "players", "meta", "tournaments", "stores",
                    "submit_results", "about", "faq", "for_tos")
    if (params$tab %in% valid_tabs) {
      # Use slight delay to ensure UI is ready
      shinyjs::delay(100, {
        nav_select("main_content", params$tab)
        rv$current_nav <- params$tab
      })
    }
  }

  # 3. Entity modals (player, deck, store, tournament)
  # Use delay to ensure tab navigation completes first
  shinyjs::delay(200, {
    # Player modal
    if (!is.null(params$player) || !is.null(params$player_id)) {
      open_entity_from_url("player", params$player, params$player_id)
    }

    # Deck modal
    if (!is.null(params$deck) || !is.null(params$deck_id)) {
      # Navigate to meta tab first if not there
      if (is.null(params$tab) || params$tab != "meta") {
        nav_select("main_content", "meta")
        rv$current_nav <- "meta"
      }
      shinyjs::delay(100, {
        open_entity_from_url("deck", params$deck, params$deck_id)
      })
    }

    # Store modal
    if (!is.null(params$store) || !is.null(params$store_id)) {
      open_entity_from_url("store", params$store, params$store_id)
    }

    # Tournament modal
    if (!is.null(params$tournament) || !is.null(params$tournament_id)) {
      open_entity_from_url("tournament", params$tournament, params$tournament_id)
    }
  })
}, once = TRUE)

# Handle browser back/forward button
observeEvent(input$url_popstate, {


  params <- parse_url_params(input$url_popstate$search)

  # Close any open modals first
  removeModal()

  # If URL has no entity params, we're done (modal closed via back button)
  has_entity <- any(c("player", "player_id", "deck", "deck_id",
                       "store", "store_id", "tournament", "tournament_id") %in% names(params))

  if (!has_entity) {
    # Just navigating between tabs or closing modal
    if (!is.null(params$tab)) {
      nav_select("main_content", params$tab)
      rv$current_nav <- params$tab
    }
    return()
  }

  # Re-open the modal from the URL (forward button case)
  if (!is.null(params$player) || !is.null(params$player_id)) {
    open_entity_from_url("player", params$player, params$player_id)
  } else if (!is.null(params$deck) || !is.null(params$deck_id)) {
    open_entity_from_url("deck", params$deck, params$deck_id)
  } else if (!is.null(params$store) || !is.null(params$store_id)) {
    open_entity_from_url("store", params$store, params$store_id)
  } else if (!is.null(params$tournament) || !is.null(params$tournament_id)) {
    open_entity_from_url("tournament", params$tournament, params$tournament_id)
  }
})

# Handle "Copy Link" toast notification
observeEvent(input$link_copied, {
  notify("Link copied to clipboard!", type = "message", duration = 2)
})

# Handle modal close - clear entity from URL and reset reactive values
observeEvent(input$modal_closed, {
  # Clear URL entity parameter
  clear_url_entity(session)

  # Clear all selected entity IDs to prevent modal from re-appearing
  # when user navigates to a different tab
  rv$selected_player_id <- NULL
  rv$selected_store_id <- NULL
  rv$selected_archetype_id <- NULL
  rv$selected_tournament_id <- NULL
})

# Update URL when tab changes (for shareable tab links)
observeEvent(rv$current_nav, {
  # Public tabs that should have URL support

  public_tabs <- c("dashboard", "players", "meta", "tournaments", "stores",
                   "submit_results", "about", "faq", "for_tos")

  # Admin tabs should clear URL back to base

  admin_tabs <- c("admin_tournaments", "admin_decks",
                  "admin_stores", "admin_formats", "admin_players",
                  "admin_users", "admin_scenes")

  if (!is.null(rv$current_nav)) {
    # Track tab visit in GA4
    track_event("tab_visit", tab = rv$current_nav, scene = rv$current_scene %||% "all")

    if (rv$current_nav %in% public_tabs) {
      params <- list()
      if (rv$current_nav != "dashboard") {
        params$tab <- rv$current_nav
      }
      if (!is.null(rv$current_scene)) {
        params$scene <- scene_prefix_to_slug(db_pool, rv$current_scene)
      }
      # Use replace instead of push to avoid cluttering history with tab changes
      update_browser_url(session, params, replace = TRUE)
    } else if (rv$current_nav %in% admin_tabs) {
      # Clear URL for admin pages (no shareable links)
      update_browser_url(session, list(), replace = TRUE)
    }
  }
}, ignoreInit = TRUE)

# -----------------------------------------------------------------------------
# Entity Resolution Functions
# -----------------------------------------------------------------------------

#' Open entity modal from URL parameters
#' @param entity_type One of: player, deck, store, tournament
#' @param slug Human-readable identifier (e.g., "atomshell", "blue-flare")
#' @param id Database ID (takes precedence over slug if both provided)
open_entity_from_url <- function(entity_type, slug = NULL, id = NULL) {


  # Resolve to entity ID
  entity_id <- NULL

  if (!is.null(id)) {
    # Direct ID lookup
    entity_id <- as.integer(id)
  } else if (!is.null(slug)) {
    # Slug-based lookup
    entity_id <- resolve_entity_slug(entity_type, slug)
  }

  if (is.null(entity_id)) {
    entity_label <- tools::toTitleCase(entity_type)
    showModal(modalDialog(
      div(
        class = "not-found-modal",
        div(class = "not-found-mascot", agumon_svg(size = "72px", color = "#F7941D")),
        h4(class = "not-found-title", paste0(entity_label, " Not Found")),
        p(class = "not-found-message",
          paste0("The ", tolower(entity_label), " you're looking for doesn't exist or may have been removed."))
      ),
      title = NULL,
      footer = modalButton("Close"),
      size = "s",
      easyClose = TRUE
    ))
    return()
  }

  # Trigger the appropriate modal
  switch(entity_type,
    "player" = {
      rv$selected_player_id <- entity_id
    },
    "deck" = {
      rv$selected_archetype_id <- entity_id
    },
    "store" = {
      rv$selected_store_id <- entity_id
    },
    "tournament" = {
      rv$selected_tournament_id <- entity_id
    }
  )
}

#' Resolve entity slug to database ID
#' @param entity_type One of: player, deck, store, tournament
#' @param slug URL slug to look up
#' @return Entity ID or NULL if not found
resolve_entity_slug <- function(entity_type, slug) {


  result <- switch(entity_type,
    "player" = {
      # Players have a slug column for direct lookup
      player <- safe_query(db_pool, "SELECT player_id FROM players WHERE slug = $1 AND is_active = TRUE",
                           params = list(slug), default = data.frame(player_id = integer()))
      if (nrow(player) == 1) {
        player$player_id
      } else {
        # Fallback: slugify display_name for players without slug column populated
        players <- safe_query(db_pool, "SELECT player_id, display_name FROM players WHERE is_active = TRUE AND slug IS NULL",
                              default = data.frame(player_id = integer(), display_name = character()))
        match_idx <- which(sapply(players$display_name, slugify) == slug)
        if (length(match_idx) == 1) players$player_id[match_idx] else NULL
      }
    },
    "deck" = {
      # Decks have a slug column
      deck <- safe_query(db_pool, "SELECT archetype_id FROM deck_archetypes WHERE slug = $1 AND is_active = TRUE",
                         params = list(slug), default = data.frame(archetype_id = integer()))
      if (nrow(deck) == 1) deck$archetype_id else NULL
    },
    "store" = {
      # Stores have a slug column
      store <- safe_query(db_pool, "SELECT store_id FROM stores WHERE slug = $1 AND is_active = TRUE",
                          params = list(slug), default = data.frame(store_id = integer()))
      if (nrow(store) == 1) store$store_id else NULL
    },
    "tournament" = {
      # Tournaments use ID only (names aren't unique) — resolve numeric ID
      tid <- suppressWarnings(as.integer(slug))
      if (!is.na(tid)) {
        tournament <- safe_query(db_pool, "SELECT tournament_id FROM tournaments WHERE tournament_id = $1",
                                 params = list(tid), default = data.frame())
        if (nrow(tournament) == 1) tournament$tournament_id else NULL
      } else NULL
    }
  )

  result
}

# -----------------------------------------------------------------------------
# URL Update Triggers (called when modals open)
# -----------------------------------------------------------------------------

#' Update URL when player modal opens
#' Call this from player modal observers
update_url_for_player <- function(session, player_id, display_name) {
  track_event("modal_open", modal_type = "player", entity = display_name)
  slug <- slugify(display_name)
  params <- list(player = slug)

  # Preserve current tab in URL
  if (!is.null(rv$current_nav) && rv$current_nav != "dashboard") {
    params$tab <- rv$current_nav
  }

  # Preserve scene if set
  if (!is.null(rv$current_scene)) {
    params$scene <- scene_prefix_to_slug(db_pool, rv$current_scene)
  }

  # Preserve community filter if active
  if (!is.null(rv$community_filter)) {
    params$community <- rv$community_filter
  }

  update_browser_url(session, params, replace = FALSE)
}

#' Update URL when deck modal opens
update_url_for_deck <- function(session, archetype_id, slug) {
  track_event("modal_open", modal_type = "deck", entity = slug)
  params <- list(deck = slug, tab = "meta")

  if (!is.null(rv$current_scene)) {
    params$scene <- scene_prefix_to_slug(db_pool, rv$current_scene)
  }

  # Preserve community filter if active
  if (!is.null(rv$community_filter)) {
    params$community <- rv$community_filter
  }

  update_browser_url(session, params, replace = FALSE)
}

#' Update URL when store modal opens
update_url_for_store <- function(session, store_id, slug) {
  track_event("modal_open", modal_type = "store", entity = slug)
  params <- list(store = slug)

  if (!is.null(rv$current_nav) && rv$current_nav != "dashboard") {
    params$tab <- rv$current_nav
  }

  if (!is.null(rv$current_scene)) {
    params$scene <- scene_prefix_to_slug(db_pool, rv$current_scene)
  }

  # Preserve community filter if active
  if (!is.null(rv$community_filter)) {
    params$community <- rv$community_filter
  }

  update_browser_url(session, params, replace = FALSE)
}

#' Update URL when tournament modal opens
update_url_for_tournament <- function(session, tournament_id) {
  track_event("modal_open", modal_type = "tournament", entity = as.character(tournament_id))
  params <- list(tournament = tournament_id)

  if (!is.null(rv$current_nav) && rv$current_nav != "dashboard") {
    params$tab <- rv$current_nav
  }

  if (!is.null(rv$current_scene)) {
    params$scene <- scene_prefix_to_slug(db_pool, rv$current_scene)
  }

  # Preserve community filter if active
  if (!is.null(rv$community_filter)) {
    params$community <- rv$community_filter
  }

  update_browser_url(session, params, replace = FALSE)
}

#' Update URL for community-filtered view
update_url_for_community <- function(session, store_slug) {
  params <- list(community = store_slug)
  update_browser_url(session, params, replace = TRUE)
}

#' Clear community filter from URL
clear_community_filter <- function(session) {
  params <- list()
  if (!is.null(rv$current_nav) && rv$current_nav != "dashboard") {
    params$tab <- rv$current_nav
  }
  if (!is.null(rv$current_scene)) {
    params$scene <- scene_prefix_to_slug(db_pool, rv$current_scene)
  }
  update_browser_url(session, params, replace = TRUE)
}

#' Clear entity from URL (when modal closes)
clear_url_entity <- function(session) {
  params <- list()

  # Keep tab and scene
  if (!is.null(rv$current_nav) && rv$current_nav != "dashboard") {
    params$tab <- rv$current_nav
  }

  if (!is.null(rv$current_scene)) {
    params$scene <- scene_prefix_to_slug(db_pool, rv$current_scene)
  }

  update_browser_url(session, params, replace = TRUE)
}
