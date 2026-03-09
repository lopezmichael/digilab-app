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
    footer = actionButton("dismiss_announcement", "Got it", class = "btn-primary"),
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
      version_changelog_content(),
      tags$hr(class = "my-3"),
      tags$p(class = "text-muted small text-center",
        tags$a(href = LINKS$discord, target = "_blank", "Join Discord for updates")
      )
    ),
    footer = actionButton("dismiss_version", "Continue", class = "btn-primary"),
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
        bsicons::bs_icon("speedometer2", class = "text-success"),
        span("Faster page loads with optimized database queries and caching")
      ),
      div(class = "version-changelog-item",
        bsicons::bs_icon("shield-check", class = "text-primary"),
        span("Improved data reliability with automatic retry on transient errors")
      ),
      div(class = "version-changelog-item",
        bsicons::bs_icon("link-45deg", class = "text-info"),
        span("Decklist URL entry with domain allowlist for popular deck builders")
      ),
      div(class = "version-changelog-item",
        bsicons::bs_icon("arrow-repeat", class = "text-warning"),
        span("Rating updates now run in the background for snappier navigation")
      ),
      div(class = "version-changelog-item",
        bsicons::bs_icon("database-check", class = "text-success"),
        span("Transaction safety ensures tournament data stays consistent")
      )
    )
  )
}

