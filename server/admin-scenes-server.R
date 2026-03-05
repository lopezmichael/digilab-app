# =============================================================================
# Admin Scenes Server - Manage scenes (super admin only)
# =============================================================================

# Editing state
editing_scene_id <- reactiveVal(NULL)

# Output for conditional panels
output$editing_scene <- reactive({ !is.null(editing_scene_id()) })
outputOptions(output, "editing_scene", suspendWhenHidden = FALSE)

# --- Scenes Table ---
scenes_data <- reactive({
  rv$data_refresh  # Trigger refresh
  req(db_pool, rv$is_superadmin)
  safe_query(db_pool,
    "SELECT s.scene_id, s.display_name, s.slug, s.scene_type, s.latitude, s.longitude,
            s.is_active, s.discord_thread_id, s.country, s.state_region,
            TO_CHAR(s.created_at, 'YYYY-MM-DD') as created_at,
            COUNT(st.store_id) as store_count
     FROM scenes s
     LEFT JOIN stores st ON s.scene_id = st.scene_id AND st.is_active = TRUE
     GROUP BY s.scene_id, s.display_name, s.slug, s.scene_type, s.latitude, s.longitude,
              s.is_active, s.discord_thread_id, s.country, s.state_region, s.created_at
     ORDER BY s.scene_type, s.display_name",
    default = data.frame())
})

output$admin_scenes_table <- renderReactable({
  df <- scenes_data()
  req(nrow(df) > 0)

  reactable(
    df,
    columns = list(
      scene_id = colDef(show = FALSE),
      display_name = colDef(name = "Name", minWidth = 120),
      slug = colDef(name = "Slug", minWidth = 80),
      scene_type = colDef(name = "Type", maxWidth = 80, cell = function(value) {
        if (value == "metro") "Metro" else if (value == "online") "Online" else value
      }),
      latitude = colDef(show = FALSE),
      longitude = colDef(show = FALSE),
      is_active = colDef(name = "Active", maxWidth = 70, cell = function(value) {
        if (value) "\u2705" else "\u274c"
      }),
      discord_thread_id = colDef(name = "Discord", maxWidth = 75, cell = function(value) {
        if (!is.null(value) && !is.na(value) && nchar(value) > 0) "\u2705" else "\u274c"
      }),
      country = colDef(show = FALSE),
      state_region = colDef(show = FALSE),
      created_at = colDef(name = "Created", maxWidth = 100),
      store_count = colDef(name = "Stores", maxWidth = 70)
    ),
    searchable = TRUE,
    defaultPageSize = 10,
    showPageSizeOptions = TRUE,
    pageSizeOptions = c(10, 25, 50),
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
observeEvent(getReactableState("admin_scenes_table", "selected"), {
  selected <- getReactableState("admin_scenes_table", "selected")
  if (is.null(selected) || length(selected) == 0) {
    editing_scene_id(NULL)
    return()
  }

  df <- scenes_data()
  row <- df[selected, ]

  editing_scene_id(row$scene_id)
  updateTextInput(session, "scene_display_name", value = row$display_name)
  updateTextInput(session, "scene_slug", value = row$slug)
  updateSelectInput(session, "scene_type", selected = row$scene_type)

  # Build location hint from existing coordinates
  if (!is.na(row$latitude) && !is.na(row$longitude)) {
    updateTextInput(session, "scene_location",
                    value = paste0(row$display_name, " (has coordinates)"))
  } else {
    updateTextInput(session, "scene_location", value = "")
  }

  updateCheckboxInput(session, "scene_is_active", value = row$is_active)
  updateTextInput(session, "scene_discord_thread_id",
                  value = if (!is.na(row$discord_thread_id)) row$discord_thread_id else "")

  shinyjs::html("scene_form_title", "Edit Scene")
})

# --- Clear Form ---
observeEvent(input$clear_scene_form_btn, {
  editing_scene_id(NULL)
  updateTextInput(session, "scene_display_name", value = "")
  updateTextInput(session, "scene_slug", value = "")
  updateSelectInput(session, "scene_type", selected = "metro")
  updateTextInput(session, "scene_location", value = "")
  updateCheckboxInput(session, "scene_is_active", value = TRUE)
  updateTextInput(session, "scene_discord_thread_id", value = "")
  updateReactable("admin_scenes_table", selected = NA)
  shinyjs::html("scene_form_title", "Add Scene")
})

# --- Map container for selected scene ---
output$scene_map_container <- renderUI({
  sid <- editing_scene_id()
  if (is.null(sid)) {
    return(tags$p(class = "text-muted small", "Select a scene to view its stores."))
  }

  df <- scenes_data()
  row <- df[df$scene_id == sid, ]
  if (nrow(row) == 0 || is.na(row$latitude[1]) || is.na(row$longitude[1])) {
    return(tags$p(class = "text-muted small", "No coordinates for this scene."))
  }

  mapboxglOutput("scene_minimap", height = "250px")
})

# --- Render minimap ---
output$scene_minimap <- renderMapboxgl({
  sid <- editing_scene_id()
  req(sid)

  df <- scenes_data()
  row <- df[df$scene_id == sid, ]
  req(nrow(row) > 0, !is.na(row$latitude[1]))

  scene_lat <- row$latitude[1]
  scene_lng <- row$longitude[1]

  stores <- safe_query(db_pool,
    "SELECT name, latitude, longitude, is_online, is_active FROM stores
     WHERE scene_id = $1 AND latitude IS NOT NULL AND longitude IS NOT NULL
     ORDER BY name",
    params = list(sid),
    default = data.frame())

  # Start with scene center point for bounds
  scene_point <- sf::st_sf(
    geometry = sf::st_sfc(sf::st_point(c(scene_lng, scene_lat)), crs = 4326)
  )

  map <- atom_mapgl(theme = "digital")

  if (nrow(stores) > 0) {
    store_points <- sf::st_sf(
      name = stores$name,
      geometry = sf::st_sfc(
        lapply(seq_len(nrow(stores)), function(i) {
          sf::st_point(c(stores$longitude[i], stores$latitude[i]))
        }),
        crs = 4326
      )
    )

    # Combine scene center + store points for bounding box
    bounds_sf <- rbind(scene_point, store_points[, "geometry"])

    map <- map |>
      mapgl::add_circle_layer(
        id = "scene-stores",
        source = store_points,
        circle_color = "#F7941D",
        circle_radius = 8,
        circle_stroke_color = "#FFFFFF",
        circle_stroke_width = 2,
        circle_opacity = 0.9,
        tooltip = "name"
      ) |>
      mapgl::fit_bounds(bounds_sf, padding = 40, maxZoom = 11)
  } else {
    # No stores — just center on scene
    map <- map |>
      mapgl::set_view(center = c(scene_lng, scene_lat), zoom = 10)
  }

  map
})

# --- Stores legend sidebar ---
output$scene_stores_legend <- renderUI({
  sid <- editing_scene_id()
  if (is.null(sid)) return(NULL)

  stores <- safe_query(db_pool,
    "SELECT name, city, is_online, is_active FROM stores
     WHERE scene_id = $1 ORDER BY name",
    params = list(sid),
    default = data.frame())

  if (nrow(stores) == 0) {
    return(tags$p(class = "text-muted small", "No stores."))
  }

  store_items <- lapply(seq_len(nrow(stores)), function(i) {
    s <- stores[i, ]
    status <- if (s$is_active) "" else " (inactive)"
    location <- if (s$is_online) "Online" else s$city
    tags$div(
      class = "py-1 border-bottom",
      tags$div(class = "small fw-bold", paste0(s$name, status)),
      tags$div(class = "text-muted", style = "font-size: 0.7rem;", location)
    )
  })

  tagList(
    tags$div(class = "small text-muted mb-1",
             paste0(nrow(stores), " store", if (nrow(stores) != 1) "s")),
    do.call(tagList, store_items)
  )
})

# --- Save Scene (Create or Update) ---
# Helper to validate and geocode scene form inputs (shared by save + confirm)
validate_scene_form <- function() {
  display_name <- trimws(input$scene_display_name)
  slug <- trimws(tolower(input$scene_slug))
  scene_type <- input$scene_type
  is_active <- input$scene_is_active
  discord_thread_id <- trimws(input$scene_discord_thread_id)
  if (nchar(discord_thread_id) == 0) discord_thread_id <- NA_character_

  # Validation
  if (nchar(display_name) == 0) {
    notify("Display name is required", type = "warning")
    return(NULL)
  }
  if (nchar(slug) == 0) {
    notify("URL slug is required", type = "warning")
    return(NULL)
  }
  if (!grepl("^[a-z0-9-]+$", slug)) {
    notify("Slug must be lowercase letters, numbers, and hyphens only", type = "warning")
    return(NULL)
  }

  # Geocode for metro scenes
  lat <- NA_real_
  lng <- NA_real_
  country <- NA_character_
  state_region <- NA_character_
  if (scene_type == "metro") {
    location <- trimws(input$scene_location)

    # If editing and location field wasn't changed (still shows hint), keep existing coords
    if (!is.null(editing_scene_id())) {
      old_scene <- safe_query(db_pool,
        "SELECT latitude, longitude, country, state_region FROM scenes WHERE scene_id = $1",
        params = list(editing_scene_id()),
        default = data.frame())
      if (nrow(old_scene) > 0 && grepl("has coordinates", location, fixed = TRUE)) {
        lat <- old_scene$latitude[1]
        lng <- old_scene$longitude[1]
        country <- old_scene$country[1]
        state_region <- old_scene$state_region[1]
      }
    }

    # Geocode if we don't already have coordinates
    if (is.na(lat) || is.na(lng)) {
      if (nchar(location) == 0) {
        notify("Location is required for metro scenes (e.g., 'Houston, TX')", type = "warning")
        return(NULL)
      }
      notify("Geocoding location...", type = "message", duration = 2)
      geo_result <- geocode_with_mapbox(location)
      lat <- geo_result$lat
      lng <- geo_result$lng

      if (is.na(lat) || is.na(lng)) {
        notify("Could not geocode location. Try a more specific location (e.g., 'Houston, Texas, USA').",
               type = "warning", duration = 5)
        return(NULL)
      }

      geo_region <- reverse_geocode_with_mapbox(lat, lng)
      country <- geo_region$country
      state_region <- geo_region$state_region
    }
  }

  list(display_name = display_name, slug = slug, scene_type = scene_type,
       is_active = is_active, discord_thread_id = discord_thread_id,
       lat = lat, lng = lng, country = country, state_region = state_region)
}

# Temporarily store validated form data while waiting for confirmation
pending_scene_save <- reactiveVal(NULL)

observeEvent(input$save_scene_btn, {
  req(rv$is_superadmin)

  form <- validate_scene_form()
  if (is.null(form)) return()

  if (is.null(editing_scene_id())) {
    # --- CREATE: no confirmation needed ---
    pending_scene_save(form)
    execute_scene_save()
  } else {
    # --- UPDATE: show confirmation with original name from DB ---
    sid <- editing_scene_id()
    original <- safe_query(db_pool,
      "SELECT display_name FROM scenes WHERE scene_id = $1",
      params = list(sid),
      default = data.frame())
    original_name <- if (nrow(original) > 0) original$display_name[1] else paste("Scene", sid)

    pending_scene_save(form)

    showModal(modalDialog(
      title = "Confirm Scene Update",
      tags$p(
        "You are about to update ",
        tags$strong(original_name),
        if (original_name != form$display_name)
          tagList(" to ", tags$strong(form$display_name))
      ),
      if (original_name != form$display_name)
        tags$p(class = "text-warning small",
          bsicons::bs_icon("exclamation-triangle"),
          " The scene name is changing. Make sure you have the correct scene selected."
        ),
      footer = tagList(
        modalButton("Cancel"),
        actionButton("confirm_scene_save_btn", "Confirm Save", class = "btn-primary")
      ),
      easyClose = TRUE
    ))
  }
})

# --- Confirmed save (update path) ---
observeEvent(input$confirm_scene_save_btn, {
  removeModal()
  execute_scene_save()
})

# --- Execute the actual save (create or update) ---
execute_scene_save <- function() {
  form <- pending_scene_save()
  if (is.null(form)) return()
  pending_scene_save(NULL)

  if (is.null(editing_scene_id())) {
    # --- CREATE new scene ---
    existing <- safe_query(db_pool,
      "SELECT COUNT(*) as n FROM scenes WHERE slug = $1",
      params = list(form$slug),
      default = data.frame(n = 0))
    if (existing$n[1] > 0) {
      notify("A scene with that slug already exists", type = "error")
      return()
    }

    insert_result <- safe_query(db_pool,
      "INSERT INTO scenes (name, slug, display_name, scene_type, latitude, longitude,
       is_active, discord_thread_id, country, state_region)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
       RETURNING scene_id",
      params = list(form$display_name, form$slug, form$display_name, form$scene_type,
                    if (is.na(form$lat)) NA_real_ else form$lat,
                    if (is.na(form$lng)) NA_real_ else form$lng,
                    form$is_active, form$discord_thread_id, form$country, form$state_region),
      default = data.frame())

    if (nrow(insert_result) > 0) {
      notify(paste0("Scene '", form$display_name, "' created"), type = "message")
      rv$data_refresh <- rv$data_refresh + 1

      # Clear form
      editing_scene_id(NULL)
      updateTextInput(session, "scene_display_name", value = "")
      updateTextInput(session, "scene_slug", value = "")
      updateSelectInput(session, "scene_type", selected = "metro")
      updateTextInput(session, "scene_location", value = "")
      updateCheckboxInput(session, "scene_is_active", value = TRUE)
      updateTextInput(session, "scene_discord_thread_id", value = "")
      updateReactable("admin_scenes_table", selected = NA)
    } else {
      notify("Failed to create scene", type = "error")
    }

  } else {
    # --- UPDATE existing scene ---
    sid <- editing_scene_id()

    existing <- safe_query(db_pool,
      "SELECT COUNT(*) as n FROM scenes WHERE slug = $1 AND scene_id != $2",
      params = list(form$slug, sid),
      default = data.frame(n = 0))
    if (existing$n[1] > 0) {
      notify("A scene with that slug already exists", type = "error")
      return()
    }

    safe_execute(db_pool,
      "UPDATE scenes SET name = $1, slug = $2, display_name = $3, scene_type = $4,
       latitude = $5, longitude = $6, is_active = $7, discord_thread_id = $8,
       country = $9, state_region = $10, updated_at = CURRENT_TIMESTAMP
       WHERE scene_id = $11",
      params = list(form$display_name, form$slug, form$display_name, form$scene_type,
                    if (is.na(form$lat)) NA_real_ else form$lat,
                    if (is.na(form$lng)) NA_real_ else form$lng,
                    form$is_active, form$discord_thread_id, form$country, form$state_region, sid))

    notify(paste0("Scene '", form$display_name, "' updated"), type = "message")
    rv$data_refresh <- rv$data_refresh + 1
  }
}

# --- Delete Scene ---
observeEvent(input$delete_scene_btn, {
  req(rv$is_superadmin, !is.null(editing_scene_id()))
  sid <- editing_scene_id()

  # Check for associated stores
  store_count <- safe_query(db_pool,
    "SELECT COUNT(*) as n FROM stores WHERE scene_id = $1",
    params = list(sid),
    default = data.frame(n = 0))

  if (store_count$n[1] > 0) {
    notify(paste0("Cannot delete: ", store_count$n[1], " store(s) are assigned to this scene. Reassign them first."),
           type = "error", duration = 5)
    return()
  }

  # Check for admin users assigned to this scene
  admin_count <- safe_query(db_pool,
    "SELECT COUNT(*) as n FROM admin_users WHERE scene_id = $1",
    params = list(sid),
    default = data.frame(n = 0))

  if (admin_count$n[1] > 0) {
    notify(paste0("Cannot delete: ", admin_count$n[1], " admin(s) are assigned to this scene. Reassign them first."),
           type = "error", duration = 5)
    return()
  }

  safe_execute(db_pool,
    "DELETE FROM scenes WHERE scene_id = $1",
    params = list(sid))

  scene_name <- input$scene_display_name
  notify(paste0("Scene '", scene_name, "' deleted"), type = "message")
  rv$data_refresh <- rv$data_refresh + 1

  # Clear form
  editing_scene_id(NULL)
  updateTextInput(session, "scene_display_name", value = "")
  updateTextInput(session, "scene_slug", value = "")
  updateSelectInput(session, "scene_type", selected = "metro")
  updateTextInput(session, "scene_location", value = "")
  updateCheckboxInput(session, "scene_is_active", value = TRUE)
  updateTextInput(session, "scene_discord_thread_id", value = "")
  updateReactable("admin_scenes_table", selected = NA)
  shinyjs::html("scene_form_title", "Add Scene")
})
