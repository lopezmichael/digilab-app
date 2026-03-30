# =============================================================================
# Admin Scenes Server - Manage scenes (super admin only)
# =============================================================================

#' Derive continent from country name
#' @param country Character country name
#' @return Character continent code or NA
derive_continent <- function(country) {
  if (is.null(country) || is.na(country) || country == "") return(NA_character_)
  continent_map <- list(
    north_america = c("United States", "Canada", "Mexico"),
    south_america = c("Brazil", "Costa Rica", "Colombia", "Argentina", "Chile", "Peru"),
    europe = c("Germany", "Italy", "France", "Spain", "United Kingdom", "Netherlands",
               "Poland", "Portugal", "Sweden", "Norway", "Denmark", "Finland", "Austria",
               "Switzerland", "Belgium", "Czech Republic", "Romania", "Hungary", "Greece",
               "Ireland", "Croatia"),
    asia = c("Japan", "South Korea", "China", "Taiwan", "Philippines", "Thailand",
             "Malaysia", "Singapore", "Indonesia", "India", "Saudi Arabia"),
    oceania = c("Australia", "New Zealand"),
    africa = c("South Africa", "Nigeria", "Kenya", "Egypt")
  )
  for (cont in names(continent_map)) {
    if (country %in% continent_map[[cont]]) return(cont)
  }
  NA_character_
}

# Country code prefixes for non-US state scene slugs.
# Must match the CASE mapping in db/migrations/009_country_state_scenes.sql.
COUNTRY_SLUG_PREFIX <- c(
  "Germany" = "de", "Spain" = "es", "United Kingdom" = "uk",
  "Australia" = "au", "Brazil" = "br", "France" = "fr",
  "Italy" = "it", "Portugal" = "pt", "Canada" = "ca", "Mexico" = "mx"
)

#' Generate an accent-safe slug from text.
#' Transliterates common accented characters before slugifying.
#' @param text String to slugify
#' @return Lowercase slug with hyphens, or NA
accent_safe_slug <- function(text) {
  if (is.null(text) || is.na(text) || !nzchar(trimws(text))) return(NA_character_)
  text <- trimws(text)
  # Transliterate common accented characters to ASCII
  from <- "ÁÉÍÓÚáéíóúÀÈÌÒÙàèìòùÂÊÎÔÛâêîôûÄËÏÖÜäëïöüÃÑÕãñõÇç"
  to   <- "AEIOUaeiouAEIOUaeiouAEIOUaeiouAEIOUaeiouANOanocc"
  text <- chartr(from, to, text)
  text |> tolower() |>
    gsub("[^a-z0-9]+", "-", x = _) |>
    gsub("^-|-$", "", x = _)
}

#' Ensure parent country and state scenes exist after creating a metro scene.
#' Creates missing parent scenes idempotently (checks before INSERT).
#' @param pool Database connection pool
#' @param country Character country name of the new metro scene
#' @param state_region Character state/region name (can be NULL)
#' @param continent Character continent code (can be NULL)
#' @param admin_username Character username of the admin performing the action (for audit trail)
ensure_parent_scenes <- function(pool, country, state_region, continent, admin_username = "system") {
  if (is.null(country) || is.na(country) || country == "") return()

  # 1. Ensure country scene exists
  country_slug <- accent_safe_slug(country)
  existing <- safe_query(pool,
    "SELECT scene_id FROM scenes WHERE scene_type = 'country' AND country = $1 LIMIT 1",
    params = list(country), default = data.frame())

  if (nrow(existing) == 0 && !is.na(country_slug)) {
    # Verify slug doesn't collide
    slug_check <- safe_query(pool,
      "SELECT COUNT(*) as n FROM scenes WHERE slug = $1",
      params = list(country_slug), default = data.frame(n = 1))
    if (slug_check$n[1] == 0) {
      safe_execute(pool,
        "INSERT INTO scenes (name, slug, display_name, scene_type, country, continent, is_active, updated_by)
         VALUES ($1, $2, $3, 'country', $4, $5, TRUE, $6)",
        params = list(country, country_slug, country, country, continent, admin_username))
      message(sprintf("[PARENT SCENES] Created country scene: %s (%s)", country, country_slug))
    }
  }

  # 2. Ensure state scene exists if 2+ metros now share this (country, state_region)
  if (is.null(state_region) || is.na(state_region) || state_region == "") return()

  metro_count <- safe_query(pool,
    "SELECT COUNT(*) as n FROM scenes
     WHERE scene_type = 'metro' AND is_active = TRUE
       AND country = $1 AND state_region = $2",
    params = list(country, state_region), default = data.frame(n = 0))

  if (metro_count$n[1] < 2) return()  # only 1 metro — no state scene needed yet

  state_exists <- safe_query(pool,
    "SELECT scene_id FROM scenes
     WHERE scene_type = 'state' AND country = $1 AND state_region = $2 LIMIT 1",
    params = list(country, state_region), default = data.frame())

  if (nrow(state_exists) > 0) return()  # already exists

  # Generate slug: US states use plain name, non-US use country-code prefix
  base_slug <- accent_safe_slug(state_region)
  if (is.na(base_slug)) return()

  if (country != "United States") {
    prefix <- COUNTRY_SLUG_PREFIX[country]
    if (is.na(prefix)) prefix <- tolower(substr(country, 1, 2))
    state_slug <- paste0(prefix, "-", base_slug)
  } else {
    state_slug <- base_slug
  }

  # Verify slug doesn't collide
  slug_check <- safe_query(pool,
    "SELECT COUNT(*) as n FROM scenes WHERE slug = $1",
    params = list(state_slug), default = data.frame(n = 1))
  if (slug_check$n[1] > 0) return()  # collision — skip, admin can create manually

  safe_execute(pool,
    "INSERT INTO scenes (name, slug, display_name, scene_type, country, state_region, continent, is_active, updated_by)
     VALUES ($1, $2, $3, 'state', $4, $5, $6, TRUE, $7)",
    params = list(state_region, state_slug, state_region, country, state_region, continent, admin_username))
  message(sprintf("[PARENT SCENES] Created state scene: %s / %s (%s)", country, state_region, state_slug))
}

# Editing state
editing_scene_id <- reactiveVal(NULL)

# Output for conditional panels
output$editing_scene <- reactive({ !is.null(editing_scene_id()) })
outputOptions(output, "editing_scene", suspendWhenHidden = FALSE)

# --- Scenes Table ---
scenes_data <- reactive({
  rv$refresh_scenes  # Trigger refresh
  req(db_pool, rv$is_superadmin)
  safe_query(db_pool,
    "SELECT s.scene_id, s.display_name, s.slug, s.scene_type, s.latitude, s.longitude,
            s.is_active, s.country, s.state_region,
            TO_CHAR(s.created_at, 'YYYY-MM-DD') as created_at,
            COUNT(st.store_id) as store_count,
            (SELECT COUNT(*) FROM admin_user_scenes aus WHERE aus.scene_id = s.scene_id) as admin_count
     FROM scenes s
     LEFT JOIN stores st ON s.scene_id = st.scene_id AND st.is_active = TRUE
     GROUP BY s.scene_id, s.display_name, s.slug, s.scene_type, s.latitude, s.longitude,
              s.is_active, s.country, s.state_region, s.created_at
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
      display_name = colDef(name = "Name", minWidth = 120, style = list(whiteSpace = "normal")),
      country = colDef(name = "Country", width = 85),
      slug = colDef(name = "Slug", minWidth = 80),
      scene_type = colDef(show = FALSE),
      latitude = colDef(show = FALSE),
      longitude = colDef(show = FALSE),
      is_active = colDef(name = "Active", width = 55, align = "center", cell = function(value) {
        if (value) "\u2705" else "\u274c"
      }),
      state_region = colDef(show = FALSE),
      created_at = colDef(show = FALSE),
      store_count = colDef(name = "# Stores", width = 75, align = "center"),
      admin_count = colDef(name = "# Admins", width = 80, align = "center")
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
       is_active = is_active,
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
      default = data.frame(n = 1))
    if (existing$n[1] > 0) {
      notify("A scene with that slug already exists", type = "error")
      return()
    }

    insert_result <- safe_query(db_pool,
      "INSERT INTO scenes (name, slug, display_name, scene_type, latitude, longitude,
       is_active, country, state_region, continent, updated_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
       RETURNING scene_id",
      params = list(form$display_name, form$slug, form$display_name, form$scene_type,
                    if (is.na(form$lat)) NA_real_ else form$lat,
                    if (is.na(form$lng)) NA_real_ else form$lng,
                    form$is_active, form$country, form$state_region,
                    derive_continent(form$country), current_admin_username(rv)),
      default = data.frame())

    if (nrow(insert_result) > 0) {
      notify(paste0("Scene '", form$display_name, "' created"), type = "message")

      # Auto-create parent country/state scenes if this is a new metro
      if (form$scene_type == "metro") {
        ensure_parent_scenes(db_pool, form$country, form$state_region,
                             derive_continent(form$country),
                             admin_username = current_admin_username(rv))
      }

      rv$refresh_scenes <- rv$refresh_scenes + 1

      # Post scene update announcement to Discord
      discord_post_scene_update(
        scene_name = form$display_name,
        country = form$country,
        state_region = form$state_region,
        continent = derive_continent(form$country)
      )

      # Clear form
      editing_scene_id(NULL)
      updateTextInput(session, "scene_display_name", value = "")
      updateTextInput(session, "scene_slug", value = "")
      updateSelectInput(session, "scene_type", selected = "metro")
      updateTextInput(session, "scene_location", value = "")
      updateCheckboxInput(session, "scene_is_active", value = TRUE)
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
      default = data.frame(n = 1))
    if (existing$n[1] > 0) {
      notify("A scene with that slug already exists", type = "error")
      return()
    }

    safe_execute(db_pool,
      "UPDATE scenes SET name = $1, slug = $2, display_name = $3, scene_type = $4,
       latitude = $5, longitude = $6, is_active = $7,
       country = $8, state_region = $9, continent = $10, updated_at = CURRENT_TIMESTAMP
       WHERE scene_id = $11",
      params = list(form$display_name, form$slug, form$display_name, form$scene_type,
                    if (is.na(form$lat)) NA_real_ else form$lat,
                    if (is.na(form$lng)) NA_real_ else form$lng,
                    form$is_active, form$country, form$state_region,
                    derive_continent(form$country), sid))

    notify(paste0("Scene '", form$display_name, "' updated"), type = "message")
    rv$refresh_scenes <- rv$refresh_scenes + 1
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

  # Check for admin users assigned to this scene (via junction table)
  admin_count <- safe_query(db_pool,
    "SELECT COUNT(*) as n FROM admin_user_scenes WHERE scene_id = $1",
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
  rv$refresh_scenes <- rv$refresh_scenes + 1

  # Clear form
  editing_scene_id(NULL)
  updateTextInput(session, "scene_display_name", value = "")
  updateTextInput(session, "scene_slug", value = "")
  updateSelectInput(session, "scene_type", selected = "metro")
  updateTextInput(session, "scene_location", value = "")
  updateCheckboxInput(session, "scene_is_active", value = TRUE)
  updateReactable("admin_scenes_table", selected = NA)
  shinyjs::html("scene_form_title", "Add Scene")
})

# =============================================================================
# Announcements Admin (super admin only)
# =============================================================================

# --- Announcements Table ---
announcements_data <- reactive({
  rv$refresh_scenes  # Announcements managed in scenes admin
  req(db_pool, rv$is_superadmin)
  safe_query(db_pool,
    "SELECT id, title, announcement_type, active,
            TO_CHAR(created_at, 'Mon DD, YYYY') as created_at,
            TO_CHAR(expires_at, 'YYYY-MM-DD') as expires_at
     FROM announcements
     ORDER BY created_at DESC",
    default = data.frame())
})

output$admin_announcements_table <- renderReactable({
  df <- announcements_data()
  if (nrow(df) == 0) return(NULL)

  reactable(
    df,
    columns = list(
      id = colDef(show = FALSE),
      title = colDef(name = "Title", minWidth = 150, style = list(whiteSpace = "normal")),
      announcement_type = colDef(name = "Type", width = 80, cell = function(value) {
        switch(value,
          info = "Info",
          donation = "Donation",
          update = "Update",
          event = "Event",
          value
        )
      }),
      active = colDef(name = "Active", maxWidth = 70, cell = function(value) {
        if (value) "\u2705" else "\u274c"
      }),
      created_at = colDef(name = "Created", maxWidth = 110),
      expires_at = colDef(name = "Expires", maxWidth = 100, cell = function(value) {
        if (is.null(value) || is.na(value)) "\u2014" else value
      })
    ),
    selection = "single",
    onClick = "select",
    highlight = TRUE,
    compact = TRUE,
    defaultPageSize = 5,
    theme = reactableTheme(
      rowSelectedStyle = list(backgroundColor = "rgba(0, 123, 255, 0.1)")
    )
  )
})

# --- Create Announcement ---
observeEvent(input$create_announcement_btn, {
  req(rv$is_superadmin)

  title <- trimws(input$announcement_title)
  body <- trimws(input$announcement_body)
  ann_type <- input$announcement_type
  no_expiry <- isTRUE(input$announcement_no_expiry)

  if (nchar(title) == 0) {
    notify("Title is required", type = "warning")
    return()
  }
  if (nchar(body) == 0) {
    notify("Body is required", type = "warning")
    return()
  }

  expires_at <- if (no_expiry) NA else input$announcement_expires_at

  # Deactivate all existing announcements (only one active at a time)
  safe_execute(db_pool,
    "UPDATE announcements SET active = FALSE WHERE active = TRUE")

  # Insert new announcement
  result <- safe_query(db_pool,
    "INSERT INTO announcements (title, body, announcement_type, active, expires_at)
     VALUES ($1, $2, $3, TRUE, $4)
     RETURNING id",
    params = list(title, body, ann_type,
                  if (is.na(expires_at)) NA else as.character(expires_at)),
    default = data.frame())

  if (nrow(result) > 0) {
    notify(paste0("Announcement '", title, "' created"), type = "message")
    rv$refresh_scenes <- rv$refresh_scenes + 1

    # Clear form
    updateTextInput(session, "announcement_title", value = "")
    updateTextAreaInput(session, "announcement_body", value = "")
    updateSelectInput(session, "announcement_type", selected = "info")
    updateCheckboxInput(session, "announcement_no_expiry", value = TRUE)
  } else {
    notify("Failed to create announcement", type = "error")
  }
})

# --- Toggle Active Status (via table selection) ---
observeEvent(getReactableState("admin_announcements_table", "selected"), {
  selected <- getReactableState("admin_announcements_table", "selected")
  if (is.null(selected) || length(selected) == 0) return()

  df <- announcements_data()
  row <- df[selected, ]

  # Show confirm dialog to toggle active status
  action_label <- if (row$active) "Deactivate" else "Activate"
  showModal(modalDialog(
    title = paste(action_label, "Announcement"),
    tags$p(
      paste0("Do you want to ", tolower(action_label), " \"", row$title, "\"?")
    ),
    if (!row$active) tags$p(class = "text-muted small",
      "Activating this will deactivate all other announcements."),
    footer = tagList(
      modalButton("Cancel"),
      actionButton("confirm_toggle_announcement", action_label,
                   class = if (row$active) "btn-outline-danger" else "btn-primary")
    ),
    easyClose = TRUE
  ))
})

observeEvent(input$confirm_toggle_announcement, {
  req(rv$is_superadmin)
  removeModal()

  selected <- getReactableState("admin_announcements_table", "selected")
  if (is.null(selected) || length(selected) == 0) return()

  df <- announcements_data()
  row <- df[selected, ]
  ann_id <- row$id

  if (row$active) {
    # Deactivate
    safe_execute(db_pool,
      "UPDATE announcements SET active = FALSE WHERE id = $1",
      params = list(ann_id))
    notify(paste0("'", row$title, "' deactivated"), type = "message")
  } else {
    # Activate (deactivate others first)
    safe_execute(db_pool,
      "UPDATE announcements SET active = FALSE WHERE active = TRUE")
    safe_execute(db_pool,
      "UPDATE announcements SET active = TRUE WHERE id = $1",
      params = list(ann_id))
    notify(paste0("'", row$title, "' activated"), type = "message")
  }

  rv$refresh_scenes <- rv$refresh_scenes + 1
  updateReactable("admin_announcements_table", selected = NA)
})
