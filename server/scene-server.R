# =============================================================================
# Scene Selection Server Logic
# Handles scene selection, onboarding modal, and localStorage sync
# =============================================================================

# -----------------------------------------------------------------------------
# Scene Choices Helper
# -----------------------------------------------------------------------------

#' Get available scene choices for dropdown
#' @return Named list of scene display names and slugs
get_scene_choices <- function(db_con) {
  # Start with "All Scenes" option
  choices <- list("All Scenes" = "all")

  # Get metro scenes from database
  scenes <- safe_query(db_con,
    "SELECT slug, display_name FROM scenes
     WHERE scene_type = 'metro' AND is_active = TRUE
     ORDER BY display_name",
    default = data.frame(slug = character(), display_name = character())
  )

  if (nrow(scenes) > 0) {
    for (i in seq_len(nrow(scenes))) {
      choices[[scenes$display_name[i]]] <- scenes$slug[i]
    }
  }

  # Add Online option
  choices[["Online / Webcam"]] <- "online"

  choices
}

#' Get scenes data with coordinates for map
#' @return Data frame with scene_id, display_name, slug, latitude, longitude
get_scenes_for_map <- function(db_con) {
  if (is.null(db_con) || !dbIsValid(db_con)) return(NULL)

  safe_query(db_con,
    "SELECT scene_id, display_name, slug, latitude, longitude
     FROM scenes
     WHERE scene_type = 'metro' AND is_active = TRUE
       AND latitude IS NOT NULL AND longitude IS NOT NULL",
    default = data.frame(scene_id = integer(), display_name = character(),
                         slug = character(), latitude = numeric(), longitude = numeric())
  )
}

# -----------------------------------------------------------------------------
# Populate Scene Dropdown from Database
# -----------------------------------------------------------------------------

observeEvent(db_pool, {


  choices <- get_scene_choices(db_pool)

  # Use stored scene preference if available and valid
  stored <- input$scene_from_storage
  selected <- "all"
  if (!is.null(stored) && !is.null(stored$scene) && stored$scene != "") {
    if (stored$scene %in% unlist(choices)) {
      selected <- stored$scene
    }
  }

  updateSelectInput(session, "scene_selector", choices = choices, selected = selected)
}, once = TRUE)

# -----------------------------------------------------------------------------
# Initialize Scene from localStorage
# -----------------------------------------------------------------------------

observeEvent(input$scene_from_storage, {


  stored <- input$scene_from_storage
  if (is.null(stored)) return()

  # Modal priority: Welcome > Announcement > Version (one per page load)
  if (isTRUE(stored$needsOnboarding)) {
    shinyjs::delay(500, {
      show_onboarding_modal()
    })
  } else {
    # Check for unseen announcement or version update
    last_seen_ann_id <- stored$lastSeenAnnouncementId  # integer or NULL from JS
    last_seen_version <- stored$lastSeenVersion         # string or NULL from JS

    shinyjs::delay(500, {
      # Query latest active, unexpired announcement
      latest_ann <- safe_query(db_pool,
        "SELECT id, title, body, announcement_type
         FROM announcements
         WHERE active = TRUE
           AND (expires_at IS NULL OR expires_at > NOW())
         ORDER BY created_at DESC
         LIMIT 1",
        default = data.frame())

      if (nrow(latest_ann) > 0 && (is.null(last_seen_ann_id) || latest_ann$id[1] != last_seen_ann_id)) {
        # Show announcement modal
        show_announcement_modal(latest_ann[1, ])
      } else if (is.null(last_seen_version) || last_seen_version != APP_VERSION) {
        # Show version changelog modal
        show_version_modal()
      }
    })
  }

  # If there's a stored scene preference, apply it
  if (!is.null(stored$scene) && stored$scene != "") {
    # Rebuild choices to ensure they include all DB scenes
    choices <- get_scene_choices(db_pool)
    if (stored$scene %in% unlist(choices)) {
      rv$current_scene <- stored$scene
      updateSelectInput(session, "scene_selector", choices = choices, selected = stored$scene)
      # Set dynamic min_events default for initial scene load
      shinyjs::delay(200, {
        tournament_count <- count_tournaments_for_scope(db_pool, stored$scene, NULL)
        default_min <- get_default_min_events(tournament_count)
        session$sendCustomMessage("resetPillToggle", list(inputId = "players_min_events", value = default_min))
        session$sendCustomMessage("resetPillToggle", list(inputId = "meta_min_entries", value = default_min))
      })
    }
  }
}, once = TRUE)

# -----------------------------------------------------------------------------
# Scene Selector Dropdown
# -----------------------------------------------------------------------------

# Update scene when header dropdown changes
observeEvent(input$scene_selector, {
  new_scene <- input$scene_selector
  if (is.null(new_scene)) return()

  # Scene admins cannot switch scenes — force back to their assigned scene
  if (rv$is_admin && !rv$is_superadmin && !is.null(rv$admin_user) && !is.null(rv$admin_user$scene_id)) {
    scene_slug <- safe_query(db_pool,
      "SELECT slug FROM scenes WHERE scene_id = $1",
      params = list(rv$admin_user$scene_id),
      default = data.frame())
    if (nrow(scene_slug) > 0 && new_scene != scene_slug$slug[1]) {
      updateSelectInput(session, "scene_selector", selected = scene_slug$slug[1])
      notify("Scene admins can only manage their assigned scene", type = "warning")
      return()
    }
  }

  # Update reactive value
  rv$current_scene <- new_scene

  # Track scene change in GA4
  track_event("scene_change", scene = new_scene)

  # Save to localStorage
  session$sendCustomMessage("saveScenePreference", list(scene = new_scene))

  # Trigger data refresh
  rv$data_refresh <- Sys.time()

  # Update min_events default based on scene's tournament count
  tournament_count <- count_tournaments_for_scope(db_pool, new_scene, NULL)
  default_min <- get_default_min_events(tournament_count)
  session$sendCustomMessage("resetPillToggle", list(inputId = "players_min_events", value = default_min))
  session$sendCustomMessage("resetPillToggle", list(inputId = "meta_min_entries", value = default_min))
}, ignoreInit = TRUE)

# -----------------------------------------------------------------------------
# Onboarding Modal Functions
# -----------------------------------------------------------------------------

#' Show 3-step onboarding carousel modal
show_onboarding_modal <- function() {
  rv$onboarding_step <- 1
  showModal(modalDialog(
    onboarding_ui(),
    title = NULL,
    footer = NULL,
    size = "l",
    easyClose = FALSE,
    class = "onboarding-modal"
  ))
}

# Re-open onboarding from footer "Welcome Guide" link
observeEvent(input$open_welcome_guide, {
  show_onboarding_modal()
})

# Handle close onboarding (from links to About/FAQ)
observeEvent(input$close_onboarding, {
  removeModal()
  # Mark onboarding as complete with default scene
  session$sendCustomMessage("saveScenePreference", list(scene = "all"))
  rv$current_scene <- "all"
  updateSelectInput(session, "scene_selector", selected = "all")
})

# -----------------------------------------------------------------------------
# Onboarding Carousel Navigation
# -----------------------------------------------------------------------------

# Update step visibility, dots, progress bar, and nav buttons when step changes
observe({
  step <- rv$onboarding_step
  req(step)

  # Show/hide step containers
  for (i in 1:3) {
    if (i == step) {
      shinyjs::show(paste0("onboarding_step_", i))
    } else {
      shinyjs::hide(paste0("onboarding_step_", i))
    }
  }

  # Update progress bar width
  pct <- round(step / 3 * 100)
  shinyjs::runjs(sprintf(
    "var fill = document.getElementById('onboarding_progress_fill'); if (fill) fill.style.width = '%d%%';",
    pct
  ))

  # Update dot classes: active = pill, completed = filled, upcoming = dim
  shinyjs::runjs(sprintf("
    $('.onboarding-dot').removeClass('active completed upcoming');
    for (var i = 1; i <= 3; i++) {
      var dot = document.getElementById('onboarding_dot_' + i);
      if (dot) {
        if (i === %d) dot.classList.add('active');
        else if (i < %d) dot.classList.add('completed');
        else dot.classList.add('upcoming');
      }
    }
  ", step, step))

  # Toggle nav buttons per step
  # Left: skip (step 1) or back (steps 2-3)
  if (step == 1) {
    shinyjs::show("onboarding_skip")
    shinyjs::hide("onboarding_back")
  } else {
    shinyjs::hide("onboarding_skip")
    shinyjs::show("onboarding_back")
  }

  # Right: next (step 1), next_2 (step 2), finish (step 3)
  shinyjs::hide("onboarding_next")
  shinyjs::hide("onboarding_next_2")
  shinyjs::hide("onboarding_finish")
  if (step == 1) shinyjs::show("onboarding_next")
  if (step == 2) shinyjs::show("onboarding_next_2")
  if (step == 3) shinyjs::show("onboarding_finish")

  # Scroll modal to top when switching steps
  shinyjs::runjs("
    var modalBody = document.querySelector('.onboarding-modal .modal-body');
    if (modalBody) modalBody.scrollTop = 0;
  ")

  # Trigger map resize when scene step becomes visible
  if (step == 2) {
    shinyjs::runjs("setTimeout(function(){ window.dispatchEvent(new Event('resize')); }, 150);")
  }
})

# Next buttons (step 1 and step 2 both increment)
observeEvent(input$onboarding_next, {
  if (rv$onboarding_step < 3) {
    # Hide scene confirmation when arriving at Step 2 fresh
    shinyjs::hide("onboarding_scene_confirmed")
    rv$onboarding_step <- rv$onboarding_step + 1
  }
})

observeEvent(input$onboarding_next_2, {
  if (rv$onboarding_step < 3) {
    rv$onboarding_step <- rv$onboarding_step + 1
  }
})

# Back button
observeEvent(input$onboarding_back, {
  if (rv$onboarding_step > 1) {
    rv$onboarding_step <- rv$onboarding_step - 1
  }
})

# Skip button - default to "all" and close
observeEvent(input$onboarding_skip, {
  select_scene_and_close("all")
})

# Finish button (Get Started) - close with current scene or "all" default
observeEvent(input$onboarding_finish, {
  select_scene_and_close(rv$current_scene %||% "all")
})

# For Organizers link - close modal and navigate
observeEvent(input$onboarding_to_organizers, {
  select_scene_and_close(rv$current_scene %||% "all")
  nav_select("main_content", "for_tos")
  rv$current_nav <- "for_tos"
})


# -----------------------------------------------------------------------------
# Scene Selection (from onboarding modal)
# -----------------------------------------------------------------------------

# Handle "Online / Webcam" button
observeEvent(input$select_scene_online, {
  select_scene("online")
  show_scene_confirmation("Online / Webcam")
})

# Handle "All Scenes" button
observeEvent(input$select_scene_all, {
  select_scene("all")
  show_scene_confirmation("All Scenes")
})

# Helper: select scene without closing modal
select_scene <- function(scene_slug) {
  old_scene <- rv$current_scene
  rv$current_scene <- scene_slug
  updateSelectInput(session, "scene_selector", selected = scene_slug)
  session$sendCustomMessage("saveScenePreference", list(scene = scene_slug))
  # Only trigger data refresh if scene actually changed
  if (!identical(old_scene, scene_slug)) {
    rv$data_refresh <- Sys.time()
  }
}

# Helper: select scene AND close modal (for skip/finish/link handlers)
select_scene_and_close <- function(scene_slug) {
  select_scene(scene_slug)
  removeModal()
}

# Helper: show confirmation on Step 2 after scene selection
show_scene_confirmation <- function(display_name) {
  shinyjs::show("onboarding_scene_confirmed")
  shinyjs::html("onboarding_scene_label", paste("Scene selected:", display_name))
}

# -----------------------------------------------------------------------------
# Onboarding Map
# -----------------------------------------------------------------------------

output$onboarding_map <- mapgl::renderMapboxgl({

  # Get scenes with coordinates
  scenes <- get_scenes_for_map(db_pool)

  # Create flat world map
  map <- atom_mapgl(theme = "digital", projection = "mercator") |>
    add_atom_popup_style(theme = "light")

  # Add scene markers (interactive, with select popups)
  if (!is.null(scenes) && nrow(scenes) > 0) {
    scenes$popup <- sapply(seq_len(nrow(scenes)), function(i) {
      sprintf(
        '<div style="text-align:center;padding:12px 16px;min-width:140px;font-family:system-ui,-apple-system,sans-serif;">
          <div style="font-size:15px;font-weight:600;color:#1a1a2e;margin-bottom:10px;">%s</div>
          <button onclick="Shiny.setInputValue(\'select_scene_from_map\', \'%s\', {priority: \'event\'});"
                  style="background:#F7941D;color:white;border:none;padding:8px 20px;border-radius:6px;font-size:13px;font-weight:500;cursor:pointer;transition:background 0.2s;">
            Select
          </button>
        </div>',
        htmltools::htmlEscape(scenes$display_name[i]), htmltools::htmlEscape(scenes$slug[i])
      )
    })

    scenes_sf <- sf::st_as_sf(scenes,
                              coords = c("longitude", "latitude"),
                              crs = 4326)

    map <- map |>
      mapgl::add_circle_layer(
        id = "scenes-layer",
        source = scenes_sf,
        circle_color = "#F7941D",
        circle_radius = 12,
        circle_stroke_color = "#FFFFFF",
        circle_stroke_width = 2,
        circle_opacity = 0.9,
        popup = "popup"
      )
  }

  map |> mapgl::set_view(center = c(-40, 10), zoom = 1.2)
})

# Handle scene selection from map marker
observeEvent(input$select_scene_from_map, {
  scene_slug <- input$select_scene_from_map
  if (!is.null(scene_slug) && scene_slug != "") {
    select_scene(scene_slug)
    # Look up display name from DB
    scene_info <- safe_query(db_pool,
      "SELECT display_name FROM scenes WHERE slug = $1 LIMIT 1",
      params = list(scene_slug))
    label <- if (nrow(scene_info) > 0) scene_info$display_name[1] else scene_slug
    show_scene_confirmation(label)
  }
})

# -----------------------------------------------------------------------------
# Geolocation (Find My Scene)
# -----------------------------------------------------------------------------

observeEvent(input$find_my_scene, {


  # Get scenes with coordinates to send to JavaScript
  scenes <- get_scenes_for_map(db_pool)

  if (!is.null(scenes) && nrow(scenes) > 0) {
    scenes_list <- lapply(seq_len(nrow(scenes)), function(i) {
      list(
        slug = scenes$slug[i],
        display_name = scenes$display_name[i],
        latitude = scenes$latitude[i],
        longitude = scenes$longitude[i]
      )
    })

    session$sendCustomMessage("requestGeolocation", list(scenes = scenes_list))
  } else {
    notify("No scenes available", type = "warning")
  }
})

# Handle geolocation result
observeEvent(input$geolocation_result, {
  result <- input$geolocation_result
  if (is.null(result)) return()

  if (isTRUE(result$success)) {
    nearest <- result$nearestScene
    if (!is.null(nearest)) {
      # Auto-select nearest scene (stay on Step 2 with confirmation)
      select_scene(nearest$slug)
      show_scene_confirmation(nearest$display_name)
      notify(
        sprintf("Found %s (%.0f km away)", nearest$display_name, result$distance),
        type = "message",
        duration = 3
      )
    } else {
      notify("No nearby scenes found", type = "warning")
    }
  } else {
    notify(result$error %||% "Unable to get location", type = "warning")
  }
})

# -----------------------------------------------------------------------------
# Scene Filter Helper
# -----------------------------------------------------------------------------


# -----------------------------------------------------------------------------
# Announcement Modal
# -----------------------------------------------------------------------------

show_announcement_modal <- function(ann) {
  type_icons <- list(
    info = "info-circle-fill",
    donation = "cup-hot-fill",
    update = "arrow-up-circle-fill",
    event = "calendar-event-fill"
  )
  icon_name <- type_icons[[ann$announcement_type]] %||% "info-circle-fill"

  showModal(modalDialog(
    title = NULL,
    div(class = "announcement-modal-content",
      div(class = "announcement-modal-icon",
        bsicons::bs_icon(icon_name)
      ),
      h3(class = "announcement-modal-title", ann$title),
      div(class = "announcement-modal-body",
        lapply(strsplit(ann$body, "\n\n")[[1]], function(p) tags$p(trimws(p)))
      )
    ),
    footer = tagList(
      div(class = "social-row",
        tags$a(href = LINKS$discord, target = "_blank", rel = "noopener", class = "btn-social btn-discord",
          HTML('<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M20.317 4.37a19.791 19.791 0 0 0-4.885-1.515.074.074 0 0 0-.079.037c-.21.375-.444.864-.608 1.25a18.27 18.27 0 0 0-5.487 0 12.64 12.64 0 0 0-.617-1.25.077.077 0 0 0-.079-.037A19.736 19.736 0 0 0 3.677 4.37a.07.07 0 0 0-.032.027C.533 9.046-.32 13.58.099 18.057a.082.082 0 0 0 .031.057 19.9 19.9 0 0 0 5.993 3.03.078.078 0 0 0 .084-.028 14.09 14.09 0 0 0 1.226-1.994.076.076 0 0 0-.041-.106 13.107 13.107 0 0 1-1.872-.892.077.077 0 0 1-.008-.128 10.2 10.2 0 0 0 .372-.292.074.074 0 0 1 .077-.01c3.928 1.793 8.18 1.793 12.062 0a.074.074 0 0 1 .078.01c.12.098.246.198.373.292a.077.077 0 0 1-.006.127 12.299 12.299 0 0 1-1.873.892.077.077 0 0 0-.041.107c.36.698.772 1.362 1.225 1.993a.076.076 0 0 0 .084.028 19.839 19.839 0 0 0 6.002-3.03.077.077 0 0 0 .032-.054c.5-5.177-.838-9.674-3.549-13.66a.061.061 0 0 0-.031-.03zM8.02 15.33c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.956-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.956 2.418-2.157 2.418zm7.975 0c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.955-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.946 2.418-2.157 2.418z"/></svg>'),
          "Join Discord"
        ),
        tags$a(href = LINKS$kofi, target = "_blank", rel = "noopener", class = "btn-social btn-kofi",
          HTML('<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M23.881 8.948c-.773-4.085-4.859-4.593-4.859-4.593H.723c-.604 0-.679.798-.679.798s-.082 7.324-.022 11.822c.164 2.424 2.586 2.672 2.586 2.672s8.267-.023 11.966-.049c2.438-.426 2.683-2.566 2.658-3.734 4.352.24 7.422-2.831 6.649-6.916zm-11.062 3.511c-1.246 1.453-4.011 3.976-4.011 3.976s-.121.119-.31.023c-.076-.057-.108-.09-.108-.09-.443-.441-3.368-3.049-4.034-3.954-.709-.965-1.041-2.7-.091-3.71.951-1.01 3.005-1.086 4.363.407 0 0 1.565-1.782 3.468-.963 1.904.82 1.832 3.011.723 4.311zm6.173.478c-.928.116-1.682.028-1.682.028V7.284h1.77s1.971.551 1.971 2.638c0 1.913-.985 2.667-2.059 3.015z"/></svg>'),
          "Support on Ko-fi"
        )
      ),
      actionButton("dismiss_announcement", "Dismiss", class = "dismiss-link")
    ),
    size = "m",
    easyClose = TRUE,
    class = "announcement-modal"
  ))

  # Save seen state
  session$sendCustomMessage("saveSeenAnnouncement", list(id = ann$id))
}

observeEvent(input$dismiss_announcement, {
  removeModal()
})

# -----------------------------------------------------------------------------
# Version Changelog Modal
# -----------------------------------------------------------------------------

show_version_modal <- function() {
  showModal(modalDialog(
    title = NULL,
    div(class = "version-modal-content",
      div(class = "version-modal-header",
        bsicons::bs_icon("rocket-takeoff-fill"),
        h3(paste0("What's New in v", APP_VERSION))
      ),
      version_changelog_content()
    ),
    footer = div(class = "version-modal-footer",
      div(class = "social-row",
        tags$a(href = LINKS$discord, target = "_blank", rel = "noopener", class = "btn-social btn-discord",
          HTML('<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M20.317 4.37a19.791 19.791 0 0 0-4.885-1.515.074.074 0 0 0-.079.037c-.21.375-.444.864-.608 1.25a18.27 18.27 0 0 0-5.487 0 12.64 12.64 0 0 0-.617-1.25.077.077 0 0 0-.079-.037A19.736 19.736 0 0 0 3.677 4.37a.07.07 0 0 0-.032.027C.533 9.046-.32 13.58.099 18.057a.082.082 0 0 0 .031.057 19.9 19.9 0 0 0 5.993 3.03.078.078 0 0 0 .084-.028 14.09 14.09 0 0 0 1.226-1.994.076.076 0 0 0-.041-.106 13.107 13.107 0 0 1-1.872-.892.077.077 0 0 1-.008-.128 10.2 10.2 0 0 0 .372-.292.074.074 0 0 1 .077-.01c3.928 1.793 8.18 1.793 12.062 0a.074.074 0 0 1 .078.01c.12.098.246.198.373.292a.077.077 0 0 1-.006.127 12.299 12.299 0 0 1-1.873.892.077.077 0 0 0-.041.107c.36.698.772 1.362 1.225 1.993a.076.076 0 0 0 .084.028 19.839 19.839 0 0 0 6.002-3.03.077.077 0 0 0 .032-.054c.5-5.177-.838-9.674-3.549-13.66a.061.061 0 0 0-.031-.03zM8.02 15.33c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.956-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.956 2.418-2.157 2.418zm7.975 0c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.955-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.946 2.418-2.157 2.418z"/></svg>'),
          "Join Discord"
        ),
        tags$a(href = LINKS$kofi, target = "_blank", rel = "noopener", class = "btn-social btn-kofi",
          HTML('<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="currentColor"><path d="M23.881 8.948c-.773-4.085-4.859-4.593-4.859-4.593H.723c-.604 0-.679.798-.679.798s-.082 7.324-.022 11.822c.164 2.424 2.586 2.672 2.586 2.672s8.267-.023 11.966-.049c2.438-.426 2.683-2.566 2.658-3.734 4.352.24 7.422-2.831 6.649-6.916zm-11.062 3.511c-1.246 1.453-4.011 3.976-4.011 3.976s-.121.119-.31.023c-.076-.057-.108-.09-.108-.09-.443-.441-3.368-3.049-4.034-3.954-.709-.965-1.041-2.7-.091-3.71.951-1.01 3.005-1.086 4.363.407 0 0 1.565-1.782 3.468-.963 1.904.82 1.832 3.011.723 4.311zm6.173.478c-.928.116-1.682.028-1.682.028V7.284h1.77s1.971.551 1.971 2.638c0 1.913-.985 2.667-2.059 3.015z"/></svg>'),
          "Support on Ko-fi"
        )
      ),
      div(class = "dismiss-row",
        actionButton("dismiss_version", "Dismiss", class = "dismiss-link")
      )
    ),
    size = "m",
    easyClose = TRUE,
    class = "version-modal"
  ))

  session$sendCustomMessage("saveSeenVersion", list(version = APP_VERSION))
}

observeEvent(input$dismiss_version, {
  removeModal()
})

# Hardcoded changelog content — update each release
version_changelog_content <- function() {
  tagList(
    div(class = "version-changelog-items",
      div(class = "version-changelog-item",
        bsicons::bs_icon("person-check", class = "text-success"),
        span("Smarter player matching — Bandai ID verified players match globally, others stay scene-scoped")
      ),
      div(class = "version-changelog-item",
        bsicons::bs_icon("people", class = "text-info"),
        span("Fuzzy duplicate detection warns you when a new player looks similar to an existing one")
      ),
      div(class = "version-changelog-item",
        bsicons::bs_icon("question-circle", class = "text-warning"),
        span("Disambiguation UI lets you pick the right player when multiple matches are found")
      ),
      div(class = "version-changelog-item",
        bsicons::bs_icon("funnel", class = "text-primary"),
        span("Scene filter on store dropdowns — less clutter when entering tournament results")
      ),
      div(class = "version-changelog-item",
        bsicons::bs_icon("bell", class = "text-info"),
        span("Merge suggestions in admin notification bar for Limitless-to-local player matches")
      )
    )
  )
}

