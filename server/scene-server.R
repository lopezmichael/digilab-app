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
     ORDER BY display_name"
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

  dbGetQuery(db_con,
    "SELECT scene_id, display_name, slug, latitude, longitude
     FROM scenes
     WHERE scene_type = 'metro' AND is_active = TRUE
       AND latitude IS NOT NULL AND longitude IS NOT NULL"
  )
}

# -----------------------------------------------------------------------------
# Populate Scene Dropdown from Database
# -----------------------------------------------------------------------------

observeEvent(rv$db_con, {
  req(rv$db_con)

  choices <- get_scene_choices(rv$db_con)

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
  req(rv$db_con)

  stored <- input$scene_from_storage
  if (is.null(stored)) return()

  # If user needs onboarding (first visit), show the modal
  if (isTRUE(stored$needsOnboarding)) {
    # Show onboarding modal after a brief delay
    shinyjs::delay(500, {
      show_onboarding_modal()
    })
  }

  # If there's a stored scene preference, apply it
  if (!is.null(stored$scene) && stored$scene != "") {
    # Rebuild choices to ensure they include all DB scenes
    choices <- get_scene_choices(rv$db_con)
    if (stored$scene %in% unlist(choices)) {
      rv$current_scene <- stored$scene
      updateSelectInput(session, "scene_selector", choices = choices, selected = stored$scene)
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
    scene_slug <- safe_query(rv$db_con,
      "SELECT slug FROM scenes WHERE scene_id = ?",
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

  # Save to localStorage
  session$sendCustomMessage("saveScenePreference", list(scene = new_scene))

  # Trigger data refresh
  rv$data_refresh <- Sys.time()
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

# Step 3 footer inline links
observeEvent(input$onboarding_goto_about, {
  select_scene_and_close(rv$current_scene %||% "all")
  nav_select("main_content", "about")
  rv$current_nav <- "about"
})

observeEvent(input$onboarding_goto_faq, {
  select_scene_and_close(rv$current_scene %||% "all")
  nav_select("main_content", "faq")
  rv$current_nav <- "faq"
})

observeEvent(input$onboarding_goto_organizers, {
  select_scene_and_close(rv$current_scene %||% "all")
  nav_select("main_content", "for_tos")
  rv$current_nav <- "for_tos"
})

# -----------------------------------------------------------------------------
# Scene Selection (from onboarding modal)
# -----------------------------------------------------------------------------

# Handle "Online / Webcam" button
observeEvent(input$select_scene_online, {
  select_scene_and_close("online")
})

# Handle "All Scenes" button
observeEvent(input$select_scene_all, {
  select_scene_and_close("all")
})

# Helper function to select scene and close modal
select_scene_and_close <- function(scene_slug) {
  rv$current_scene <- scene_slug
  updateSelectInput(session, "scene_selector", selected = scene_slug)
  session$sendCustomMessage("saveScenePreference", list(scene = scene_slug))
  removeModal()
  rv$data_refresh <- Sys.time()
}

# -----------------------------------------------------------------------------
# Onboarding Map
# -----------------------------------------------------------------------------

output$onboarding_map <- mapgl::renderMapboxgl({
  req(rv$db_con)

  # Get scenes with coordinates
  scenes <- get_scenes_for_map(rv$db_con)

  # Default center on USA
  center_lng <- -98.5
  center_lat <- 39.8

  # Create base map using atom theme
  map <- atom_mapgl(theme = "digital")

  # Add scene markers if we have data
if (!is.null(scenes) && nrow(scenes) > 0) {
    # Build popup HTML for each scene
    scenes$popup <- sapply(seq_len(nrow(scenes)), function(i) {
      sprintf(
        '<div style="text-align:center;padding:12px 16px;min-width:140px;font-family:system-ui,-apple-system,sans-serif;">
          <div style="font-size:15px;font-weight:600;color:#1a1a2e;margin-bottom:10px;">%s</div>
          <button onclick="Shiny.setInputValue(\'select_scene_from_map\', \'%s\', {priority: \'event\'});"
                  style="background:#F7941D;color:white;border:none;padding:8px 20px;border-radius:6px;font-size:13px;font-weight:500;cursor:pointer;transition:background 0.2s;">
            Select
          </button>
        </div>',
        scenes$display_name[i], scenes$slug[i]
      )
    })

    # Convert to sf object
    scenes_sf <- sf::st_as_sf(scenes,
                              coords = c("longitude", "latitude"),
                              crs = 4326)

    map <- map |>
      add_atom_popup_style(theme = "light") |>
      mapgl::add_circle_layer(
        id = "scenes-layer",
        source = scenes_sf,
        circle_color = "#F7941D",
        circle_radius = 12,
        circle_stroke_color = "#FFFFFF",
        circle_stroke_width = 2,
        circle_opacity = 0.9,
        popup = "popup"
      ) |>
      mapgl::set_view(center = c(center_lng, center_lat), zoom = 3)
  } else {
    # No scenes - just show centered map
    map <- map |>
      mapgl::set_view(center = c(center_lng, center_lat), zoom = 3)
  }

  map
})

# Handle scene selection from map marker
observeEvent(input$select_scene_from_map, {
  scene_slug <- input$select_scene_from_map
  if (!is.null(scene_slug) && scene_slug != "") {
    select_scene_and_close(scene_slug)
  }
})

# -----------------------------------------------------------------------------
# Geolocation (Find My Scene)
# -----------------------------------------------------------------------------

observeEvent(input$find_my_scene, {
  req(rv$db_con)

  # Get scenes with coordinates to send to JavaScript
  scenes <- get_scenes_for_map(rv$db_con)

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
      # Auto-select nearest scene
      select_scene_and_close(nearest$slug)
      notify(
        sprintf("Selected %s (%.0f km away)", nearest$display_name, result$distance),
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

#' Build SQL WHERE clause fragment for scene filtering
#' @param scene_slug The current scene slug
#' @param store_alias SQL alias for stores table (default "s")
#' @return SQL fragment string or empty string if no filter needed
build_scene_filter <- function(scene_slug, store_alias = "s") {
  if (is.null(scene_slug) || scene_slug == "" || scene_slug == "all") {
    return("")
  }

  # Handle "online" specially
  if (scene_slug == "online") {
    return(sprintf("AND %s.is_online = TRUE", store_alias))
  }

  # Filter by scene_id via store's scene
  sprintf(
    "AND %s.scene_id = (SELECT scene_id FROM scenes WHERE slug = '%s')",
    store_alias, scene_slug
  )
}
