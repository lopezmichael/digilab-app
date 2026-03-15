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
  req(db_pool, isTRUE(rv$is_superadmin) || isTRUE(rv$admin_user$role == "regional_admin"))

  # Check if UI has rendered yet (admin_role is a sibling input that's always visible)
  if (is.null(input$admin_role)) {
    # UI not ready yet, retry shortly
    invalidateLater(100)
    return()
  }

  is_regional <- isTRUE(rv$admin_user$role == "regional_admin")

  scenes <- safe_query(db_pool,
    "SELECT scene_id, display_name FROM scenes
     WHERE scene_type IN ('metro', 'online') AND is_active = TRUE
     ORDER BY display_name",
    default = data.frame())
  if (nrow(scenes) == 0) { invalidateLater(500); return() }

  # Regional admins: filter to their accessible scenes only
  if (is_regional) {
    admin_scene_ids <- get_admin_accessible_scene_ids(db_pool, rv$admin_user)
    scenes <- scenes[scenes$scene_id %in% admin_scene_ids, ]
  }

  choices <- setNames(as.character(scenes$scene_id), scenes$display_name)
  # Preserve current selection when repopulating choices
  current_selection <- isolate(input$admin_scene)
  updateSelectInput(session, "admin_scene",
                    choices = c("Select scene..." = "", choices),
                    selected = current_selection)
})

# --- Populate scene filter dropdown ---
observe({
  req(rv$current_nav == "admin_users", db_pool,
      isTRUE(rv$is_superadmin) || isTRUE(rv$admin_user$role == "regional_admin"))
  # Wait for UI to render
  if (is.null(input$admin_users_scene_filter)) {
    invalidateLater(100)
    return()
  }

  is_regional <- isTRUE(rv$admin_user$role == "regional_admin")

  scenes <- safe_query(db_pool,
    "SELECT scene_id, display_name FROM scenes WHERE is_active = TRUE ORDER BY display_name",
    default = data.frame())
  if (nrow(scenes) == 0) { invalidateLater(500); return() }

  # Regional admins: filter to their region's scenes, no Super/Uncovered filters
  if (is_regional) {
    admin_scene_ids <- get_admin_accessible_scene_ids(db_pool, rv$admin_user)
    scenes <- scenes[scenes$scene_id %in% admin_scene_ids, ]
    choices <- c("All Scenes" = "all",
                 "No Admin" = "uncovered",
                 setNames(as.character(scenes$scene_id), scenes$display_name))
  } else {
    choices <- c("All Scenes" = "all",
                 "Super Admins" = "super",
                 "No Admin" = "uncovered",
                 setNames(as.character(scenes$scene_id), scenes$display_name))
  }

  current <- isolate(input$admin_users_scene_filter)
  updateSelectInput(session, "admin_users_scene_filter",
                    choices = choices, selected = current %||% "all")
})

# --- Role dropdown restriction for regional admins ---
observe({
  req(rv$admin_user$role == "regional_admin")
  req(rv$current_nav == "admin_users")
  if (is.null(input$admin_role)) { invalidateLater(100); return() }
  updateSelectInput(session, "admin_role",
    choices = c("Scene Admin" = "scene_admin"),
    selected = "scene_admin")
})

# --- Region selector UI for regional_admin role ---
output$admin_region_selector <- renderUI({
  req(db_pool)

  # Get available regions from scenes
  regions <- safe_query(db_pool,
    "SELECT DISTINCT country, state_region FROM scenes
     WHERE is_active = TRUE AND country IS NOT NULL
     ORDER BY country, state_region",
    default = data.frame())
  if (nrow(regions) == 0) return(div(class = "text-muted", "No scenes available"))

  # Group by country
  countries <- unique(regions$country)

  # Build checkbox UI grouped by country
  region_ui <- lapply(countries, function(cty) {
    cty_regions <- regions[regions$country == cty, ]
    states <- cty_regions$state_region[!is.na(cty_regions$state_region)]
    states <- unique(states)

    # If country has 2+ distinct state_regions, show expandable sub-options
    if (length(states) >= 2) {
      # Country-level checkbox + individual state checkboxes
      tagList(
        div(class = "region-country-group mb-2",
          checkboxInput(
            paste0("region_country_", gsub("[^a-zA-Z0-9]", "_", cty)),
            tags$strong(cty),
            value = FALSE
          ),
          div(class = "ms-4",
            lapply(sort(states), function(st) {
              input_id <- paste0("region_state_", gsub("[^a-zA-Z0-9]", "_", cty), "_", gsub("[^a-zA-Z0-9]", "_", st))
              checkboxInput(input_id, st, value = FALSE)
            })
          )
        )
      )
    } else {
      # Country with 0-1 state_region — just show country checkbox
      div(class = "region-country-group mb-2",
        checkboxInput(
          paste0("region_country_", gsub("[^a-zA-Z0-9]", "_", cty)),
          tags$strong(cty),
          value = FALSE
        )
      )
    }
  })

  div(
    tags$label("Assigned Regions", class = "form-label"),
    tags$small(class = "form-text text-muted d-block mb-2",
      "Select countries or specific states/provinces. Country-level = all scenes in that country."
    ),
    div(class = "region-selector-scroll", style = "max-height: 250px; overflow-y: auto;",
      region_ui
    )
  )
})

# Helper: read selected regions from checkbox inputs
get_selected_regions <- function(input, db_pool) {
  regions <- safe_query(db_pool,
    "SELECT DISTINCT country, state_region FROM scenes
     WHERE is_active = TRUE AND country IS NOT NULL
     ORDER BY country, state_region",
    default = data.frame())
  if (nrow(regions) == 0) return(data.frame(country = character(), state_region = character()))

  selected <- data.frame(country = character(), state_region = character(), stringsAsFactors = FALSE)
  countries <- unique(regions$country)

  for (cty in countries) {
    cty_id <- paste0("region_country_", gsub("[^a-zA-Z0-9]", "_", cty))
    country_checked <- isTRUE(input[[cty_id]])

    cty_regions <- regions[regions$country == cty, ]
    states <- cty_regions$state_region[!is.na(cty_regions$state_region)]
    states <- unique(states)

    if (country_checked) {
      # Country-level selection (state_region = NULL means whole country)
      selected <- rbind(selected, data.frame(country = cty, state_region = NA_character_, stringsAsFactors = FALSE))
    } else if (length(states) >= 2) {
      # Check individual states
      for (st in states) {
        st_id <- paste0("region_state_", gsub("[^a-zA-Z0-9]", "_", cty), "_", gsub("[^a-zA-Z0-9]", "_", st))
        if (isTRUE(input[[st_id]])) {
          selected <- rbind(selected, data.frame(country = cty, state_region = st, stringsAsFactors = FALSE))
        }
      }
    }
  }

  selected
}

# --- Admin Users Data ---
admin_users_data <- reactive({
  rv$refresh_users  # Trigger refresh
  req(db_pool, isTRUE(rv$is_superadmin) || isTRUE(rv$admin_user$role == "regional_admin"))
  safe_query(db_pool,
    "SELECT u.user_id, u.username, u.discord_user_id, u.role,
            u.is_active, u.created_at, aus.scene_id, s.display_name as scene_name
     FROM admin_users u
     LEFT JOIN admin_user_scenes aus ON u.user_id = aus.user_id AND aus.is_primary = TRUE
     LEFT JOIN scenes s ON aus.scene_id = s.scene_id
     ORDER BY u.role DESC, u.username",
    default = data.frame())
})

# --- Scene-Centric Tree View ---
output$admin_users_grouped <- renderUI({
  df <- admin_users_data()
  req(nrow(df) > 0)

  scene_filter <- input$admin_users_scene_filter %||% "all"
  is_regional <- isTRUE(rv$admin_user$role == "regional_admin")
  admin_scene_ids <- if (is_regional) get_admin_accessible_scene_ids(db_pool, rv$admin_user) else NULL

  # Get all active metro/online scenes with geographic info
  all_scenes <- safe_query(db_pool,
    "SELECT scene_id, display_name, country, state_region FROM scenes
     WHERE is_active = TRUE AND scene_type IN ('metro', 'online')
     ORDER BY country, state_region, display_name",
    default = data.frame())

  # Regional admins: filter scenes to their region only
  if (is_regional && !is.null(admin_scene_ids)) {
    all_scenes <- all_scenes[all_scenes$scene_id %in% admin_scene_ids, ]
  }

  # Get all admin assignments
  # Direct scene_admin assignments
  direct_assignments <- safe_query(db_pool,
    "SELECT aus.scene_id, au.user_id, au.username, au.discord_user_id, au.role, au.is_active
     FROM admin_user_scenes aus
     JOIN admin_users au ON aus.user_id = au.user_id
     WHERE au.role = 'scene_admin'",
    default = data.frame())

  # Regional admin assignments
  regional_assignments <- safe_query(db_pool,
    "SELECT ar.country, ar.state_region, au.user_id, au.username, au.discord_user_id, au.role, au.is_active
     FROM admin_regions ar
     JOIN admin_users au ON ar.user_id = au.user_id
     WHERE au.role = 'regional_admin'",
    default = data.frame())

  # Helper to build a user row
  make_user_row <- function(username, user_id, is_active, role_label = NULL,
                            inherited = FALSE, discord_user_id = NULL) {
    role_badge <- if (!is.null(role_label)) {
      cls <- switch(role_label,
        "Regional" = "admin-role-badge--regional",
        "Scene" = "admin-role-badge--scene",
        "Super" = "admin-role-badge--super",
        "admin-role-badge--scene"
      )
      span(class = paste("admin-role-badge", cls), role_label)
    }
    inherit_tag <- if (inherited) {
      span(class = "admin-inherited-tag", "inherited")
    }
    status_cls <- if (isTRUE(is_active)) "admin-status--active" else "admin-status--inactive"
    status_label <- if (isTRUE(is_active)) "Active" else "Inactive"

    # Discord indicator
    discord_indicator <- if (!is.null(discord_user_id) && !is.na(discord_user_id) && nchar(discord_user_id) > 0) {
      span(class = "admin-discord-indicator", title = "Discord linked",
        bsicons::bs_icon("discord", class = "admin-discord-icon"))
    }

    div(
      class = "admin-user-row",
      onclick = sprintf("Shiny.setInputValue('admin_user_clicked', {user_id: %d, nonce: Math.random()}, {priority: 'event'})", user_id),
      div(class = "admin-user-row-info",
        div(class = "admin-user-row-top",
          span(class = "admin-user-row-name", username),
          role_badge,
          inherit_tag
        )
      ),
      div(class = "admin-user-row-end",
        discord_indicator,
        div(class = paste("admin-status", status_cls),
          span(class = "admin-status-dot"),
          span(class = "admin-status-label", status_label)
        )
      )
    )
  }

  # Compute effective admins per scene
  scene_admins_map <- list()  # scene_id -> list of admin info
  for (i in seq_len(nrow(all_scenes))) {
    sid <- all_scenes$scene_id[i]
    admins <- list()

    # Direct assignments
    if (nrow(direct_assignments) > 0) {
      direct <- direct_assignments[direct_assignments$scene_id == sid, ]
      for (j in seq_len(nrow(direct))) {
        admins[[length(admins) + 1]] <- list(
          user_id = direct$user_id[j],
          username = direct$username[j],
          is_active = direct$is_active[j],
          discord_user_id = direct$discord_user_id[j],
          role_label = "Scene",
          inherited = FALSE
        )
      }
    }

    # Regional inheritance (hide other regional admins from regional admin view)
    if (nrow(regional_assignments) > 0 && !is_regional) {
      scene_country <- all_scenes$country[i]
      scene_state <- all_scenes$state_region[i]
      for (j in seq_len(nrow(regional_assignments))) {
        ra <- regional_assignments[j, ]
        if (!is.na(scene_country) && ra$country == scene_country) {
          if (is.na(ra$state_region) || (!is.na(scene_state) && ra$state_region == scene_state)) {
            # Check not already added as direct
            already <- any(sapply(admins, function(a) a$user_id == ra$user_id))
            if (!already) {
              admins[[length(admins) + 1]] <- list(
                user_id = ra$user_id,
                username = ra$username,
                is_active = ra$is_active,
                discord_user_id = ra$discord_user_id,
                role_label = "Regional",
                inherited = TRUE
              )
            }
          }
        }
      }
    }

    scene_admins_map[[as.character(sid)]] <- admins
  }

  # Determine which countries need state sub-levels
  # (any country with 2+ distinct state_region values)
  country_states <- list()
  if (nrow(all_scenes) > 0) {
    for (cty in unique(all_scenes$country[!is.na(all_scenes$country)])) {
      states <- unique(all_scenes$state_region[all_scenes$country == cty & !is.na(all_scenes$state_region)])
      if (length(states) >= 2) {
        country_states[[cty]] <- sort(states)
      }
    }
  }

  # Split admins
  supers <- df[df$role == "super_admin", ]

  # Apply scene filter (regional admins never see super admins section)
  show_supers <- !is_regional && scene_filter %in% c("all", "super")
  show_tree <- scene_filter %in% c("all") || (!scene_filter %in% c("super", "uncovered"))
  show_uncovered <- scene_filter %in% c("all", "uncovered")

  sections <- tagList()

  # Super admins section
  if (show_supers && nrow(supers) > 0) {
    super_rows <- lapply(seq_len(nrow(supers)), function(i) {
      make_user_row(supers$username[i], supers$user_id[i], supers$is_active[i],
                    role_label = "Super", discord_user_id = supers$discord_user_id[i])
    })
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

  # Scene-centric tree view grouped by country (and state where applicable)
  if (show_tree && nrow(all_scenes) > 0) {
    countries <- unique(all_scenes$country[!is.na(all_scenes$country)])
    countries <- sort(countries)

    # Filter to specific scene if a scene_id is selected
    filter_scene_id <- NULL
    if (!scene_filter %in% c("all", "super", "uncovered")) {
      filter_scene_id <- as.integer(scene_filter)
    }

    for (cty in countries) {
      cty_scenes <- all_scenes[all_scenes$country == cty & !is.na(all_scenes$country), ]
      if (filter_scene_id %in% cty_scenes$scene_id == FALSE && !is.null(filter_scene_id)) next

      has_state_level <- cty %in% names(country_states)

      # Regional admins for this country (shown at country level)
      cty_regional <- if (nrow(regional_assignments) > 0) {
        regional_assignments[regional_assignments$country == cty & is.na(regional_assignments$state_region), ]
      } else {
        data.frame()
      }

      country_content <- tagList()

      # Show country-level regional admins (hide from regional admin view)
      if (nrow(cty_regional) > 0 && !is_regional) {
        for (k in seq_len(nrow(cty_regional))) {
          country_content <- tagAppendChild(country_content,
            make_user_row(cty_regional$username[k], cty_regional$user_id[k],
                          cty_regional$is_active[k], "Regional",
                          discord_user_id = cty_regional$discord_user_id[k]))
        }
      }

      if (has_state_level) {
        # Group scenes by state
        for (st in country_states[[cty]]) {
          st_scenes <- cty_scenes[!is.na(cty_scenes$state_region) & cty_scenes$state_region == st, ]
          if (nrow(st_scenes) == 0) next
          if (!is.null(filter_scene_id) && !filter_scene_id %in% st_scenes$scene_id) next

          # State-level regional admins
          st_regional <- if (nrow(regional_assignments) > 0) {
            regional_assignments[regional_assignments$country == cty &
                                 !is.na(regional_assignments$state_region) &
                                 regional_assignments$state_region == st, ]
          } else {
            data.frame()
          }

          state_content <- tagList()

          # Show state-level regional admins (hide from regional admin view)
          if (nrow(st_regional) > 0 && !is_regional) {
            for (k in seq_len(nrow(st_regional))) {
              state_content <- tagAppendChild(state_content,
                make_user_row(st_regional$username[k], st_regional$user_id[k],
                              st_regional$is_active[k], "Regional",
                              discord_user_id = st_regional$discord_user_id[k]))
            }
          }

          # Individual scenes within this state
          for (si in seq_len(nrow(st_scenes))) {
            sid <- st_scenes$scene_id[si]
            if (!is.null(filter_scene_id) && sid != filter_scene_id) next
            scene_name <- st_scenes$display_name[si]
            admins <- scene_admins_map[[as.character(sid)]]

            if (length(admins) > 0) {
              admin_rows <- lapply(admins, function(a) {
                make_user_row(a$username, a$user_id, a$is_active, a$role_label, a$inherited, a$discord_user_id)
              })
              state_content <- tagAppendChild(state_content,
                div(class = "admin-tree-scene",
                  div(class = "admin-tree-scene-header",
                    bsicons::bs_icon("geo-alt-fill", class = "admin-tree-scene-icon"),
                    span(scene_name)
                  ),
                  tagList(admin_rows)
                )
              )
            } else {
              state_content <- tagAppendChild(state_content,
                div(class = "admin-tree-scene admin-tree-scene--uncovered",
                  div(class = "admin-tree-scene-header",
                    bsicons::bs_icon("geo-alt", class = "admin-tree-scene-icon"),
                    span(scene_name),
                    span(class = "uncovered-scene-badge", "No admin")
                  )
                )
              )
            }
          }

          country_content <- tagAppendChild(country_content,
            div(class = "admin-tree-state",
              div(class = "admin-tree-state-header", st),
              state_content
            )
          )
        }

        # Scenes without state_region in this country
        no_state_scenes <- cty_scenes[is.na(cty_scenes$state_region), ]
        for (si in seq_len(nrow(no_state_scenes))) {
          sid <- no_state_scenes$scene_id[si]
          if (!is.null(filter_scene_id) && sid != filter_scene_id) next
          scene_name <- no_state_scenes$display_name[si]
          admins <- scene_admins_map[[as.character(sid)]]

          if (length(admins) > 0) {
            admin_rows <- lapply(admins, function(a) {
              make_user_row(a$username, a$user_id, a$is_active, a$role_label, a$inherited)
            })
            country_content <- tagAppendChild(country_content,
              div(class = "admin-tree-scene ms-2 mb-1",
                div(class = "admin-tree-scene-name text-muted small", scene_name),
                tagList(admin_rows)
              )
            )
          } else {
            country_content <- tagAppendChild(country_content,
              div(class = "admin-tree-scene ms-2 mb-1",
                div(class = "admin-tree-scene-name text-muted small",
                  scene_name,
                  span(class = "uncovered-scene-badge ms-1", "No admin")
                )
              )
            )
          }
        }
      } else {
        # No state sub-level — scenes directly under country
        for (si in seq_len(nrow(cty_scenes))) {
          sid <- cty_scenes$scene_id[si]
          if (!is.null(filter_scene_id) && sid != filter_scene_id) next
          scene_name <- cty_scenes$display_name[si]
          admins <- scene_admins_map[[as.character(sid)]]

          if (length(admins) > 0) {
            admin_rows <- lapply(admins, function(a) {
              make_user_row(a$username, a$user_id, a$is_active, a$role_label, a$inherited)
            })
            country_content <- tagAppendChild(country_content,
              div(class = "admin-tree-scene ms-2 mb-1",
                div(class = "admin-tree-scene-name text-muted small", scene_name),
                tagList(admin_rows)
              )
            )
          } else {
            country_content <- tagAppendChild(country_content,
              div(class = "admin-tree-scene ms-2 mb-1",
                div(class = "admin-tree-scene-name text-muted small",
                  scene_name,
                  span(class = "uncovered-scene-badge ms-1", "No admin")
                )
              )
            )
          }
        }
      }

      sections <- tagAppendChildren(sections,
        div(class = "admin-users-group",
          div(class = "admin-users-group-header", cty),
          country_content
        )
      )
    }

    # Online scenes (no country)
    online_scenes <- all_scenes[is.na(all_scenes$country), ]
    if (nrow(online_scenes) > 0 && (is.null(filter_scene_id) || filter_scene_id %in% online_scenes$scene_id)) {
      online_content <- tagList()
      for (si in seq_len(nrow(online_scenes))) {
        sid <- online_scenes$scene_id[si]
        if (!is.null(filter_scene_id) && sid != filter_scene_id) next
        scene_name <- online_scenes$display_name[si]
        admins <- scene_admins_map[[as.character(sid)]]

        if (length(admins) > 0) {
          admin_rows <- lapply(admins, function(a) {
            make_user_row(a$username, a$user_id, a$is_active, a$role_label, a$inherited)
          })
          online_content <- tagAppendChild(online_content,
            div(class = "admin-tree-scene ms-2 mb-1",
              div(class = "admin-tree-scene-name text-muted small", scene_name),
              tagList(admin_rows)
            )
          )
        }
      }
      if (length(online_content) > 0) {
        sections <- tagAppendChildren(sections,
          div(class = "admin-users-group",
            div(class = "admin-users-group-header", "Online"),
            online_content
          )
        )
      }
    }
  }

  # Uncovered scenes section
  if (show_uncovered && nrow(all_scenes) > 0) {
    uncovered_names <- c()
    for (i in seq_len(nrow(all_scenes))) {
      sid <- all_scenes$scene_id[i]
      admins <- scene_admins_map[[as.character(sid)]]
      if (length(admins) == 0) {
        uncovered_names <- c(uncovered_names, all_scenes$display_name[i])
      }
    }
    if (length(uncovered_names) > 0) {
      badges <- lapply(uncovered_names, function(name) {
        span(class = "uncovered-scene-badge", name)
      })
      sections <- tagAppendChildren(sections,
        div(class = "admin-users-group",
          div(class = "admin-users-group-header",
            "No Admin Assigned",
            span(class = "badge bg-warning text-dark", length(uncovered_names))
          ),
          div(class = "uncovered-scenes-list", tagList(badges))
        )
      )
    }
  }

  if (length(sections) == 0) {
    return(div(class = "text-muted text-center py-3", "No admins match this filter"))
  }

  div(class = "admin-users-scroll scroll-fade", sections)
})

# --- Row Click: Populate edit form ---
observeEvent(input$admin_user_clicked, {
  clicked <- input$admin_user_clicked
  if (is.null(clicked) || is.null(clicked$user_id)) return()

  df <- admin_users_data()
  row <- df[df$user_id == clicked$user_id, ]
  if (nrow(row) == 0) return()
  row <- row[1, ]

  # Regional admin restrictions on who they can edit
  if (isTRUE(rv$admin_user$role == "regional_admin")) {
    if (row$role != "scene_admin") {
      notify("You can only edit scene admins", type = "warning")
      return()
    }
    # Check the target's scene is in their region
    target_scenes <- safe_query(db_pool,
      "SELECT scene_id FROM admin_user_scenes WHERE user_id = $1",
      params = list(row$user_id), default = data.frame())
    accessible <- get_admin_accessible_scene_ids(db_pool, rv$admin_user)
    if (nrow(target_scenes) > 0 && !any(target_scenes$scene_id %in% accessible)) {
      notify("This admin is outside your region", type = "warning")
      return()
    }
  }

  editing_admin_id(row$user_id)
  updateTextInput(session, "admin_username", value = row$username)
  updateTextInput(session, "admin_discord_id", value = row$discord_user_id %||% "")
  updateTextInput(session, "admin_password", value = "")
  updateSelectInput(session, "admin_role", selected = row$role)

  if (row$role == "scene_admin") {
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
  } else if (row$role == "regional_admin") {
    # Populate region checkboxes after UI renders
    # Need to wait for the conditional panel to show
    shinyjs::delay(200, {
      # Get this admin's regions
      admin_regions <- safe_query(db_pool,
        "SELECT country, state_region FROM admin_regions WHERE user_id = $1",
        params = list(row$user_id),
        default = data.frame())

      # Get all available regions
      all_regions <- safe_query(db_pool,
        "SELECT DISTINCT country, state_region FROM scenes
         WHERE is_active = TRUE AND country IS NOT NULL
         ORDER BY country, state_region",
        default = data.frame())

      countries <- unique(all_regions$country)

      for (cty in countries) {
        cty_id <- paste0("region_country_", gsub("[^a-zA-Z0-9]", "_", cty))

        # Check if this admin has country-level assignment
        has_country <- nrow(admin_regions) > 0 &&
          any(admin_regions$country == cty & is.na(admin_regions$state_region))
        updateCheckboxInput(session, cty_id, value = has_country)

        # Check state-level assignments
        cty_states <- all_regions$state_region[all_regions$country == cty & !is.na(all_regions$state_region)]
        cty_states <- unique(cty_states)
        for (st in cty_states) {
          st_id <- paste0("region_state_", gsub("[^a-zA-Z0-9]", "_", cty), "_", gsub("[^a-zA-Z0-9]", "_", st))
          has_state <- nrow(admin_regions) > 0 &&
            any(admin_regions$country == cty & !is.na(admin_regions$state_region) & admin_regions$state_region == st)
          updateCheckboxInput(session, st_id, value = has_state)
        }
      }
    })
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

# Helper: clear all region checkboxes
clear_region_checkboxes <- function(session, db_pool) {
  regions <- safe_query(db_pool,
    "SELECT DISTINCT country, state_region FROM scenes
     WHERE is_active = TRUE AND country IS NOT NULL",
    default = data.frame())
  if (nrow(regions) == 0) return()

  for (cty in unique(regions$country)) {
    cty_id <- paste0("region_country_", gsub("[^a-zA-Z0-9]", "_", cty))
    updateCheckboxInput(session, cty_id, value = FALSE)
    cty_states <- regions$state_region[regions$country == cty & !is.na(regions$state_region)]
    for (st in unique(cty_states)) {
      st_id <- paste0("region_state_", gsub("[^a-zA-Z0-9]", "_", cty), "_", gsub("[^a-zA-Z0-9]", "_", st))
      updateCheckboxInput(session, st_id, value = FALSE)
    }
  }
}

# --- Clear Form ---
observeEvent(input$clear_admin_form_btn, {
  editing_admin_id(NULL)
  updateTextInput(session, "admin_username", value = "")
  updateTextInput(session, "admin_discord_id", value = "")
  updateTextInput(session, "admin_password", value = "")
  updateSelectInput(session, "admin_role", selected = "scene_admin")
  updateSelectInput(session, "admin_scene", selected = "")
  clear_region_checkboxes(session, db_pool)
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
  req(isTRUE(rv$is_superadmin) || isTRUE(rv$admin_user$role == "regional_admin"))

  # Server-side validation for regional admins
  if (isTRUE(rv$admin_user$role == "regional_admin")) {
    if (input$admin_role != "scene_admin") {
      notify("You can only create scene admins", type = "error")
      return()
    }
    accessible <- get_admin_accessible_scene_ids(db_pool, rv$admin_user)
    selected_scene_val <- as.integer(input$admin_scene)
    if (is.na(selected_scene_val) || !selected_scene_val %in% accessible) {
      notify("This scene is not in your region", type = "error")
      return()
    }
    # Cannot edit own account
    if (!is.null(editing_admin_id()) && editing_admin_id() == rv$admin_user$user_id) {
      notify("You cannot edit your own account here", type = "error")
      return()
    }
    # If editing, target must be a scene_admin in their region
    if (!is.null(editing_admin_id())) {
      target <- safe_query(db_pool, "SELECT role FROM admin_users WHERE user_id = $1",
                           params = list(editing_admin_id()), default = data.frame())
      if (nrow(target) > 0 && target$role[1] != "scene_admin") {
        notify("You can only edit scene admins", type = "error")
        return()
      }
    }
  }

  username <- trimws(input$admin_username)
  discord_user_id <- trimws(input$admin_discord_id)
  if (nchar(discord_user_id) == 0) discord_user_id <- NA_character_
  password <- input$admin_password
  role <- input$admin_role

  # Scene ID for scene_admin
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
  if (role == "regional_admin") {
    selected_regions <- get_selected_regions(input, db_pool)
    if (nrow(selected_regions) == 0) {
      notify("Regional admins must have at least one assigned region", type = "warning")
      return()
    }
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
                    if (role == "scene_admin" && !is.na(scene_id)) scene_id else NA_integer_),
      default = data.frame())

    if (nrow(insert_result) > 0) {
      new_uid <- insert_result$user_id[1]

      if (role == "scene_admin" && !is.na(scene_id)) {
        # Write to junction table
        safe_execute(db_pool,
          "INSERT INTO admin_user_scenes (user_id, scene_id, is_primary)
           VALUES ($1, $2, TRUE)
           ON CONFLICT (user_id, scene_id) DO NOTHING",
          params = list(new_uid, scene_id))
      } else if (role == "regional_admin") {
        # Write to admin_regions table
        selected_regions <- get_selected_regions(input, db_pool)
        admin_name <- current_admin_username(rv)
        for (i in seq_len(nrow(selected_regions))) {
          safe_execute(db_pool,
            "INSERT INTO admin_regions (user_id, country, state_region, assigned_by)
             VALUES ($1, $2, $3, $4)
             ON CONFLICT (user_id, country, COALESCE(state_region, '')) DO NOTHING",
            params = list(new_uid, selected_regions$country[i],
                          if (is.na(selected_regions$state_region[i])) NA_character_ else selected_regions$state_region[i],
                          admin_name))
        }
      }

      # Build welcome DM template
      scene_name <- ""
      if (role == "scene_admin" && !is.na(scene_id)) {
        scene_info <- safe_query(db_pool,
          "SELECT display_name FROM scenes WHERE scene_id = $1",
          params = list(scene_id),
          default = data.frame())
        if (nrow(scene_info) > 0) scene_name <- scene_info$display_name[1]
      } else if (role == "regional_admin") {
        selected_regions <- get_selected_regions(input, db_pool)
        region_names <- apply(selected_regions, 1, function(r) {
          if (is.na(r["state_region"])) r["country"] else paste(r["country"], "-", r["state_region"])
        })
        scene_name <- paste(region_names, collapse = ", ")
      }

      role_label <- switch(role,
        scene_admin = "Scene Admin",
        regional_admin = "Regional Admin",
        super_admin = "Super Admin",
        role
      )

      welcome_dm <- paste0(
        "Hey ", username, "! You've been added as a ", role_label, " for ", scene_name,
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
        "- Coordinate with other admins in #scene-coordination\n",
        "- Report bugs or data errors using the buttons in the app\n\n",
        "Looking forward to seeing ", scene_name, " grow!"
      )

      # Try sending DM automatically if discord_user_id is set
      dm_sent <- FALSE
      if (!is.na(discord_user_id) && nchar(discord_user_id) > 0) {
        dm_sent <- discord_send_welcome_dm(discord_user_id, welcome_dm)
      }

      if (dm_sent) {
        notify(paste0("Admin '", username, "' created — welcome DM sent!"), type = "message")
      } else {
        # Store in reactive for the UI to display as copy-paste fallback
        rv$welcome_dm_text <- welcome_dm
        rv$show_welcome_dm <- TRUE
        notify(paste0("Admin '", username, "' created"), type = "message")
      }

      rv$refresh_users <- rv$refresh_users + 1

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
                      if (role == "scene_admin" && !is.na(scene_id)) scene_id else NA_integer_, uid))
    } else {
      # Update without changing password
      safe_execute(db_pool,
        "UPDATE admin_users SET username = $1, discord_user_id = $2, role = $3, scene_id = $4
         WHERE user_id = $5",
        params = list(username, discord_user_id, role,
                      if (role == "scene_admin" && !is.na(scene_id)) scene_id else NA_integer_, uid))
    }

    if (role == "scene_admin") {
      # Sync junction table (transactional to avoid orphaned state)
      con <- pool::localCheckout(db_pool)
      tryCatch({
        DBI::dbExecute(con, "BEGIN")
        DBI::dbExecute(con,
          "DELETE FROM admin_user_scenes WHERE user_id = $1 AND is_primary = TRUE",
          params = list(uid))
        # Also clear any regional assignments if switching from regional_admin
        DBI::dbExecute(con,
          "DELETE FROM admin_regions WHERE user_id = $1",
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
    } else if (role == "regional_admin") {
      # Sync admin_regions table
      selected_regions <- get_selected_regions(input, db_pool)
      admin_name <- current_admin_username(rv)
      con <- pool::localCheckout(db_pool)
      tryCatch({
        DBI::dbExecute(con, "BEGIN")
        # Clear existing assignments (both scene and region)
        DBI::dbExecute(con,
          "DELETE FROM admin_user_scenes WHERE user_id = $1",
          params = list(uid))
        DBI::dbExecute(con,
          "DELETE FROM admin_regions WHERE user_id = $1",
          params = list(uid))
        # Insert new region assignments
        for (i in seq_len(nrow(selected_regions))) {
          DBI::dbExecute(con,
            "INSERT INTO admin_regions (user_id, country, state_region, assigned_by)
             VALUES ($1, $2, $3, $4)",
            params = list(uid, selected_regions$country[i],
                          if (is.na(selected_regions$state_region[i])) NA_character_ else selected_regions$state_region[i],
                          admin_name))
        }
        DBI::dbExecute(con, "COMMIT")
      }, error = function(e) {
        try(DBI::dbExecute(con, "ROLLBACK"), silent = TRUE)
        warning("Region sync failed: ", e$message)
      })
    } else if (role == "super_admin") {
      # Clear scene and region assignments
      safe_execute(db_pool,
        "DELETE FROM admin_user_scenes WHERE user_id = $1",
        params = list(uid))
      safe_execute(db_pool,
        "DELETE FROM admin_regions WHERE user_id = $1",
        params = list(uid))
    }

    notify(paste0("Admin '", username, "' updated"), type = "message")
    rv$refresh_users <- rv$refresh_users + 1

    # If editing self, update reactive state
    if (uid == rv$admin_user$user_id) {
      rv$admin_user$discord_user_id <- discord_user_id
      rv$admin_user$username <- username
    }
  }
})

# --- Toggle Active Status ---
observeEvent(input$toggle_admin_active_btn, {
  req(isTRUE(rv$is_superadmin) || isTRUE(rv$admin_user$role == "regional_admin"),
      !is.null(editing_admin_id()))
  uid <- editing_admin_id()

  # Prevent self-deactivation
  if (uid == rv$admin_user$user_id) {
    notify("You cannot deactivate your own account", type = "error")
    return()
  }

  # Get current status
  current <- safe_query(db_pool,
    "SELECT is_active, username, role FROM admin_users WHERE user_id = $1",
    params = list(uid),
    default = data.frame())
  if (nrow(current) == 0) return()

  # Regional admins can only toggle scene_admins in their region
  if (isTRUE(rv$admin_user$role == "regional_admin")) {
    if (current$role[1] != "scene_admin") {
      notify("You can only deactivate scene admins", type = "error")
      return()
    }
    target_scenes <- safe_query(db_pool,
      "SELECT scene_id FROM admin_user_scenes WHERE user_id = $1",
      params = list(uid), default = data.frame())
    accessible <- get_admin_accessible_scene_ids(db_pool, rv$admin_user)
    if (nrow(target_scenes) > 0 && !any(target_scenes$scene_id %in% accessible)) {
      notify("This admin is outside your region", type = "error")
      return()
    }
  }

  new_status <- !current$is_active[1]

  safe_execute(db_pool,
    "UPDATE admin_users SET is_active = $1 WHERE user_id = $2",
    params = list(new_status, uid))

  action <- if (new_status) "reactivated" else "deactivated"
  notify(paste0("Admin '", current$username[1], "' ", action), type = "message")
  rv$refresh_users <- rv$refresh_users + 1

  # Clear selection
  editing_admin_id(NULL)
  shinyjs::html("admin_form_title", "Add Admin")
})

# --- Welcome DM Copy Area (shown after creating an admin when DM couldn't be sent) ---
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
    tags$pre(class = "welcome-dm-text scroll-fade", rv$welcome_dm_text),
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
