# =============================================================================
# Admin: Edit Stores Server Logic
# =============================================================================

# -----------------------------------------------------------------------------
# Mapbox Geocoding Helper
# -----------------------------------------------------------------------------
#' Geocode an address using Mapbox v6 with ArcGIS fallback
#'
#' @param address Full address string to geocode
#' @return List with lat and lng, or list(lat = NA, lng = NA) if failed
geocode_with_mapbox <- function(address) {
  # Try Mapbox v6 first
  mapbox_token <- Sys.getenv("MAPBOX_ACCESS_TOKEN")
  if (mapbox_token != "") {
    result <- tryCatch({
      encoded_address <- utils::URLencode(address, reserved = TRUE)
      url <- sprintf(
        "https://api.mapbox.com/search/geocode/v6/forward?q=%s&access_token=%s&limit=1",
        encoded_address, mapbox_token
      )
      resp <- httr2::request(url) |>
        httr2::req_timeout(10) |>
        httr2::req_perform()
      data <- httr2::resp_body_json(resp)
      if (length(data$features) > 0) {
        coords <- data$features[[1]]$properties$coordinates
        return(list(lat = coords$latitude, lng = coords$longitude))
      }
      NULL
    }, error = function(e) {
      warning(paste("Mapbox geocoding failed, trying ArcGIS:", e$message))
      NULL
    })
    if (!is.null(result)) return(result)
  }

  # Fallback: ArcGIS (free, no token, no IP restrictions)
  tryCatch({
    encoded_address <- utils::URLencode(address, reserved = TRUE)
    url <- sprintf(
      "https://geocode.arcgis.com/arcgis/rest/services/World/GeocodeServer/findAddressCandidates?SingleLine=%s&f=json&maxLocations=1",
      encoded_address
    )
    resp <- httr2::request(url) |>
      httr2::req_timeout(10) |>
      httr2::req_perform()
    data <- httr2::resp_body_json(resp)
    if (length(data$candidates) > 0) {
      loc <- data$candidates[[1]]$location
      return(list(lat = loc$y, lng = loc$x))
    }
    list(lat = NA_real_, lng = NA_real_)
  }, error = function(e) {
    warning(paste("ArcGIS geocoding error:", e$message))
    list(lat = NA_real_, lng = NA_real_)
  })
}

# -----------------------------------------------------------------------------
# Reverse Geocoding: Mapbox v6 with ArcGIS fallback
# -----------------------------------------------------------------------------
#' Reverse geocode coordinates using Mapbox v6 with ArcGIS fallback
#'
#' @param lat Latitude
#' @param lng Longitude
#' @return List with country and state_region, or NAs if failed
reverse_geocode_with_mapbox <- function(lat, lng) {
  # Try Mapbox v6 first
  mapbox_token <- Sys.getenv("MAPBOX_ACCESS_TOKEN")
  if (mapbox_token != "") {
    result <- tryCatch({
      url <- sprintf(
        "https://api.mapbox.com/search/geocode/v6/reverse?longitude=%s&latitude=%s&access_token=%s&types=region,country",
        lng, lat, mapbox_token
      )
      resp <- httr2::request(url) |>
        httr2::req_timeout(10) |>
        httr2::req_perform()
      data <- httr2::resp_body_json(resp)
      country <- NA_character_
      state_region <- NA_character_
      if (length(data$features) > 0) {
        for (feat in data$features) {
          feat_type <- feat$properties$feature_type %||% ""
          if (feat_type == "country") country <- feat$properties$name
          else if (feat_type == "region") state_region <- feat$properties$name
        }
      }
      if (!is.na(country) || !is.na(state_region)) {
        return(list(country = country, state_region = state_region))
      }
      NULL
    }, error = function(e) {
      warning(paste("Mapbox reverse geocoding failed, trying ArcGIS:", e$message))
      NULL
    })
    if (!is.null(result)) return(result)
  }

  # Fallback: ArcGIS
  tryCatch({
    url <- sprintf(
      "https://geocode.arcgis.com/arcgis/rest/services/World/GeocodeServer/reverseGeocode?location=%s,%s&f=json",
      lng, lat
    )
    resp <- httr2::request(url) |>
      httr2::req_timeout(10) |>
      httr2::req_perform()
    data <- httr2::resp_body_json(resp)
    address <- data$address %||% list()
    # ArcGIS returns full country name in CntryName and ISO code in CountryCode
    # Prefer CntryName (works for all countries), fall back to CountryCode
    country_name <- address$CntryName %||% NA_character_
    country_code <- address$CountryCode %||% NA_character_
    # ArcGIS CntryName is localized (e.g., Deutschland, 日本) — override to English
    country_override <- c(
      USA = "United States", GBR = "United Kingdom", KOR = "South Korea",
      JPN = "Japan", DEU = "Germany", ESP = "Spain", PRT = "Portugal",
      NLD = "Netherlands", POL = "Poland", SWE = "Sweden", NOR = "Norway",
      DNK = "Denmark", FIN = "Finland", AUT = "Austria", CHE = "Switzerland",
      BEL = "Belgium", CZE = "Czech Republic", ROU = "Romania",
      HUN = "Hungary", GRC = "Greece", MEX = "Mexico", SAU = "Saudi Arabia",
      EGY = "Egypt", BRA = "Brazil", PER = "Peru", TWN = "Taiwan",
      CHN = "China", HRV = "Croatia"
    )
    country <- if (!is.na(country_code) && country_code %in% names(country_override)) {
      country_override[[country_code]]
    } else if (!is.na(country_name) && nchar(country_name) > 0) {
      country_name
    } else {
      country_code
    }
    list(country = country, state_region = address$Region %||% NA_character_)
  }, error = function(e) {
    warning(paste("ArcGIS reverse geocoding error:", e$message))
    list(country = NA_character_, state_region = NA_character_)
  })
}

# --- Load scene choices for store dropdown ---
# Only fires when on admin_stores tab (prevents race condition with lazy-loaded UI)
# Scoped to admin's accessible scenes (scene admins see only their scenes, regional admins
# see scenes in their regions, super admins see all)
observe({
  rv$current_nav
  req(rv$current_nav == "admin_stores")
  rv$refresh_stores
  rv$refresh_scenes
  req(db_pool, rv$is_admin)

  # Check if UI has rendered yet
  if (is.null(input$store_name)) {
    # UI not ready yet, retry shortly
    invalidateLater(100)
    return()
  }

  # Scope choices to admin's accessible scenes
  accessible <- get_admin_accessible_scene_ids(db_pool, rv$admin_user)
  choices <- get_grouped_scene_choices(db_pool, key_by = "id", include_online = TRUE,
                                       scene_ids = accessible)

  # If choices came back empty (likely prepared stmt collision), retry
  if (length(choices) == 0) {
    invalidateLater(500)
    return()
  }

  # Preserve current selection when repopulating choices
  # Use editing_store_id to detect if admin is mid-edit; if so, keep their selection stable
  current_selection <- isolate(input$store_scene)
  editing_id <- isolate(input$editing_store_id)
  if (!is.null(editing_id) && nchar(editing_id) > 0 && (is.null(current_selection) || current_selection == "")) {
    # Mid-edit but selection is empty — look up the store's actual scene_id to prevent NULL
    stored_scene <- safe_query(db_pool, "SELECT scene_id FROM stores WHERE store_id = $1",
                 params = list(as.integer(editing_id)),
                 default = data.frame(scene_id = integer()))
    if (nrow(stored_scene) > 0 && !is.na(stored_scene$scene_id)) {
      current_selection <- as.character(stored_scene$scene_id)
    }
  }

  # Auto-select if admin only has one scene
  all_vals <- unlist(choices)
  if ((is.null(current_selection) || current_selection == "") && length(all_vals) == 1) {
    current_selection <- as.character(all_vals[[1]])
  }

  updateSelectInput(session, "store_scene",
                    choices = c("Select scene..." = "", choices),
                    selected = current_selection)
})

# --- Populate stores scene filter dropdown (superadmin only) ---
observe({
  req(rv$is_superadmin, db_pool)
  # Wait for UI to render
  if (is.null(input$admin_stores_scene_filter)) {
    invalidateLater(100)
    return()
  }
  scene_choices <- get_grouped_scene_choices(db_pool, key_by = "slug", include_online = TRUE)
  if (length(scene_choices) == 0) { invalidateLater(500); return() }
  choices <- c(list("Current Scene" = "current", "All Scenes" = "all"), scene_choices)
  current <- isolate(input$admin_stores_scene_filter)
  updateSelectInput(session, "admin_stores_scene_filter",
                    choices = choices, selected = current %||% "current")
})

# --- Populate scene dropdown for Enter Results (default to current scene) ---
observe({
  rv$refresh_scenes
  rv$current_nav
  req(db_pool, rv$is_admin)

  # Wait for Enter Results tab UI to render
  if (is.null(input$tournament_scene)) {
    invalidateLater(200)
    return()
  }

  choices <- get_grouped_scene_choices(db_pool, key_by = "id", include_online = FALSE)
  if (length(choices) == 0) return()

  # Add Online as a separate string value (downstream code checks == "online")
  choices[["Online / Webcam"]] <- "online"

  # Preserve current selection if already set; otherwise default to current scene
  current_selection <- isolate(input$tournament_scene)
  all_vals <- unlist(choices)
  if (!is.null(current_selection) && current_selection != "" && current_selection %in% all_vals) {
    selected <- current_selection
  } else {
    selected <- ""
    current <- rv$current_scene
    if (!is.null(current) && current != "all") {
      scene_row <- safe_query(db_pool, "SELECT scene_id FROM scenes WHERE slug = $1",
                              params = list(current), default = data.frame())
      if (nrow(scene_row) > 0 && as.character(scene_row$scene_id[1]) %in% all_vals) {
        selected <- as.character(scene_row$scene_id[1])
      } else if (current == "online") {
        selected <- "online"
      }
    }
  }

  updateSelectInput(session, "tournament_scene",
                    choices = c("Select scene..." = "", choices),
                    selected = selected)
})

# --- Refresh tournament_store dropdown filtered by selected scene ---
observeEvent(input$tournament_scene, {
  scene_val <- input$tournament_scene
  if (is.null(scene_val) || scene_val == "") {
    updateSelectInput(session, "tournament_store",
                      choices = c("Select scene first..." = ""))
    return()
  }

  if (scene_val == "online") {
    stores <- safe_query(db_pool, "
      SELECT store_id, name FROM stores
      WHERE is_active = TRUE AND is_online = TRUE
      ORDER BY name
    ", default = data.frame())
  } else {
    stores <- safe_query(db_pool, "
      SELECT store_id, name FROM stores
      WHERE is_active = TRUE AND scene_id = $1
      ORDER BY name
    ", params = list(as.integer(scene_val)), default = data.frame())
  }

  choices <- if (nrow(stores) > 0) setNames(stores$store_id, stores$name) else character()
  updateSelectInput(session, "tournament_store",
                    choices = c("Select a store..." = "", choices))
})

# Add store
observeEvent(input$add_store, {

  req(rv$is_admin, db_pool)
  clear_all_field_errors(session)

  # Check if this is an online store
  is_online <- isTRUE(input$store_is_online)

  # Get country
  store_country <- if (is_online) {
    input$store_country %||% "USA"
  } else {
    input$store_country_physical %||% "USA"
  }

  # Get name from appropriate input based on is_online
  store_name <- if (is_online) {
    trimws(input$store_name_online)
  } else {
    trimws(input$store_name)
  }

  # Use region as "city" for online stores
  store_city <- if (is_online) {
    trimws(input$store_region)
  } else {
    trimws(input$store_city)
  }

  # Validation
  if (nchar(store_name) == 0) {
    show_field_error(session, if (is_online) "store_name_online" else "store_name")
    notify("Please enter a store name", type = "error")
    return()
  }

  # City is required for physical stores, optional for online stores
  if (!is_online && nchar(store_city) == 0) {
    show_field_error(session, "store_city")
    notify("Please enter a city", type = "error")
    return()
  }

  # Street address is required for physical stores
  if (!is_online && nchar(trimws(input$store_address)) == 0) {
    show_field_error(session, "store_address")
    notify("Please enter a street address", type = "error")
    return()
  }

  # ZIP code is required for physical stores
  if (!is_online && nchar(trimws(input$store_zip)) == 0) {
    show_field_error(session, "store_zip")
    notify("Please enter a ZIP code", type = "error")
    return()
  }

  # Scene is required
  if (is.null(input$store_scene) || input$store_scene == "") {
    show_field_error(session, "store_scene")
    notify("Please select a scene", type = "error")
    return()
  }

  # Check for duplicate store name in same city/region
  # For online stores with no region, check for duplicate name among online stores
  if (is_online && nchar(store_city) == 0) {
    existing <- safe_query(db_pool, "
      SELECT store_id FROM stores
      WHERE LOWER(name) = LOWER($1) AND is_online = TRUE AND (city IS NULL OR city = '')
    ", params = list(store_name), default = data.frame(store_id = integer()))
  } else {
    existing <- safe_query(db_pool, "
      SELECT store_id FROM stores
      WHERE LOWER(name) = LOWER($1) AND LOWER(city) = LOWER($2)
    ", params = list(store_name, store_city), default = data.frame(store_id = integer()))
  }

  if (nrow(existing) > 0) {
    if (is_online && nchar(store_city) == 0) {
      notify(
        sprintf("Online store '%s' already exists", store_name),
        type = "error"
      )
    } else {
      notify(
        sprintf("Store '%s' in %s already exists", store_name, store_city),
        type = "error"
      )
    }
    return()
  }

  # Validate website URL format if provided
  if (nchar(input$store_website) > 0 && !grepl("^https?://", input$store_website)) {
    show_field_error(session, "store_website")
    notify("Website should start with http:// or https://", type = "warning")
  }

  tryCatch({
    # Online stores don't need geocoding
    if (is_online) {
      lat <- NA_real_
      lng <- NA_real_
      address <- NA_character_
      state <- NA_character_
      zip_code <- NA_character_
    } else {
      # Build full address for geocoding (physical stores only)
      address_parts <- c(input$store_address, store_city)
      if (nchar(trimws(input$store_state)) > 0) address_parts <- c(address_parts, trimws(input$store_state))
      if (nchar(trimws(input$store_zip)) > 0) address_parts <- c(address_parts, trimws(input$store_zip))
      if (nchar(store_country) > 0) address_parts <- c(address_parts, store_country)
      full_address <- paste(address_parts, collapse = ", ")

      # Geocode the address using Mapbox
      notify("Geocoding address...", type = "message", duration = 2)
      geo_result <- geocode_with_mapbox(full_address)

      lat <- geo_result$lat
      lng <- geo_result$lng

      if (is.na(lat) || is.na(lng)) {
        notify("Could not geocode address. Store added without coordinates.", type = "warning")
        lat <- NA_real_
        lng <- NA_real_
      }

      # Use NA instead of NULL for parameterized queries
      zip_code <- if (nchar(trimws(input$store_zip)) > 0) trimws(input$store_zip) else NA_character_
      address <- if (nchar(trimws(input$store_address)) > 0) trimws(input$store_address) else NA_character_
      state <- if (nchar(trimws(input$store_state)) > 0) trimws(input$store_state) else NA_character_
    }

    # Common fields for both online and physical stores
    website <- if (nchar(input$store_website) > 0) input$store_website else NA_character_
    scene_id <- if (!is.null(input$store_scene) && input$store_scene != "") as.integer(input$store_scene) else NA_integer_

    # Use NA for empty city/region
    store_city_db <- if (nchar(store_city) > 0) store_city else NA_character_

    store_slug <- generate_unique_store_slug(db_pool, store_name)
    store_result <- safe_query(db_pool, "
      INSERT INTO stores (name, slug, address, city, state, zip_code, latitude, longitude, website, is_online, country, scene_id, updated_by)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
      RETURNING store_id
    ", params = list(store_name, store_slug, address, store_city_db,
                     state, zip_code, lat, lng, website, is_online, store_country, scene_id,
                     current_admin_username(rv)),
       default = data.frame(store_id = integer()))
    new_id <- store_result$store_id[1]

    # Insert any pending schedules
    if (length(rv$pending_schedules) > 0) {
      for (i in seq_along(rv$pending_schedules)) {
        sched <- rv$pending_schedules[[i]]
        safe_execute(db_pool, "
          INSERT INTO store_schedules (store_id, day_of_week, start_time, frequency, week_of_month, next_occurrence)
          VALUES ($1, $2, $3, $4, $5, $6::date)
        ", params = list(new_id, sched$day_of_week, sched$start_time, sched$frequency,
                         sched$week_of_month, if (is.na(sched$next_occurrence)) NA else sched$next_occurrence))
      }

      notify(paste("Added store:", store_name, "with", length(rv$pending_schedules), "schedule(s)"), type = "message")
      rv$pending_schedules <- list()  # Clear pending schedules
    } else {
      notify(paste("Added store:", store_name), type = "message")
    }

    # Clear form - both physical and online store fields
    updateTextInput(session, "store_name", value = "")
    updateTextInput(session, "store_name_online", value = "")
    updateTextInput(session, "store_region", value = "")
    updateTextInput(session, "store_address", value = "")
    updateTextInput(session, "store_city", value = "")
    updateTextInput(session, "store_state", value = "")
    updateTextInput(session, "store_zip", value = "")
    updateTextInput(session, "store_website", value = "")
    updateCheckboxInput(session, "store_is_online", value = FALSE)
    updateSelectInput(session, "store_country", selected = "USA")
    updateSelectInput(session, "store_country_physical", selected = "USA")
    updateSelectInput(session, "store_scene", selected = "")

    # Trigger refresh of public tables (also updates tournament_store dropdown via observer)
    rv$refresh_stores <- rv$refresh_stores + 1

  }, error = function(e) {
    if (sentry_enabled) tryCatch(sentryR::capture_exception(e, tags = sentry_context_tags()), error = function(se) NULL)
    notify(paste("Error:", e$message), type = "error")
  })
})

# Admin store list
output$admin_store_list <- renderReactable({


  # Trigger refresh via rv$refresh_stores (set after add/update/delete complete)
  # Do NOT use input$add_store etc. directly — they fire simultaneously with
  # the handler, racing on the same connection
  rv$refresh_stores
  rv$schedules_refresh
  input$admin_stores_scene_filter
  input$admin_stores_incomplete_only

  scene <- rv$current_scene
  scene_filter_val <- input$admin_stores_scene_filter %||% "current"

  # Determine effective scene filter
  if (isTRUE(rv$is_superadmin) && scene_filter_val == "all") {
    # Super admin showing all scenes
    show_all <- TRUE
  } else if (isTRUE(rv$is_superadmin) && !scene_filter_val %in% c("current", "all")) {
    # Super admin filtering to specific scene
    show_all <- FALSE
    scene <- scene_filter_val  # Use the selected scene slug
  } else {
    show_all <- FALSE
  }

  # Build scene filter
  scene_filter <- ""
  scene_params <- list()
  accessible <- get_admin_accessible_scene_ids(db_pool, rv$admin_user)

  if (!show_all && !is.null(accessible)) {
    # Non-superadmin: restrict to admin's accessible scenes
    scene_filter <- "AND s.scene_id = ANY($1::int[])"
    scene_params <- list(pg_array(accessible))
  } else if (!show_all && !is.null(scene) && scene != "" && scene != "all") {
    if (scene == "online") {
      scene_filter <- "AND s.is_online = TRUE"
    } else {
      scene_filter <- "AND s.scene_id = (SELECT scene_id FROM scenes WHERE slug = $1)"
      scene_params <- list(scene)
    }
  }

  # Query stores with schedule count
  data <- safe_query(db_pool, sprintf("
    SELECT s.store_id, s.name as \"Store\", s.city as \"City\", s.state as \"State\",
           s.country as \"Country\", s.is_online, s.zip_code,
           COUNT(ss.schedule_id) as schedule_count
    FROM stores s
    LEFT JOIN store_schedules ss ON s.store_id = ss.store_id AND ss.is_active = TRUE
    WHERE s.is_active = TRUE %s
    GROUP BY s.store_id, s.name, s.city, s.state, s.country, s.is_online, s.zip_code
    ORDER BY
      CASE WHEN s.is_online = FALSE AND COUNT(ss.schedule_id) = 0 THEN 0 ELSE 1 END,
      CASE WHEN s.zip_code IS NULL OR s.zip_code = '' THEN 0 ELSE 1 END,
      s.name
  ", scene_filter), params = if (length(scene_params) > 0) scene_params else NULL,
     default = data.frame())

  if (nrow(data) == 0) {
    data <- data.frame(Message = "No stores yet")
    return(reactable(data, compact = TRUE))
  }

  # Determine completeness status for each row
  data$status <- sapply(1:nrow(data), function(i) {
    is_online <- isTRUE(data$is_online[i])
    has_schedule <- isTRUE(data$schedule_count[i] > 0)
    has_zip <- !is.na(data$zip_code[i]) && nzchar(trimws(data$zip_code[i]))

    if (is_online) {
      "complete"
    } else if (!has_schedule && !has_zip) {
      "incomplete"
    } else if (!has_schedule || !has_zip) {
      "incomplete"
    } else {
      "complete"
    }
  })

  # Apply "incomplete only" filter
  if (isTRUE(input$admin_stores_incomplete_only)) {
    data <- data[data$status != "complete", , drop = FALSE]
    if (nrow(data) == 0) {
      return(reactable(data.frame(Message = "All stores are complete!"), compact = TRUE))
    }
  }

  # Store data for selection handler (avoids re-query with different ORDER BY)
  rv$admin_store_list_data <- data

  reactable(data, compact = TRUE, striped = FALSE,
    selection = "single",
    onClick = "select",
    searchable = TRUE,
    defaultPageSize = 12,
    showPageSizeOptions = TRUE,
    pageSizeOptions = c(10, 20, 50, 100),
    rowStyle = function(index) {
      status <- data$status[index]
      base_style <- list(cursor = "pointer")

      if (status != "complete") {
        base_style$backgroundColor <- "rgba(245, 183, 0, 0.12)"
        base_style$borderLeft <- "3px solid #F5B700"
      }

      base_style
    },
    columns = list(
      store_id = colDef(show = FALSE),
      zip_code = colDef(show = FALSE),
      status = colDef(show = FALSE),
      Store = colDef(minWidth = 160, style = list(whiteSpace = "normal")),
      City = colDef(minWidth = 90, style = list(whiteSpace = "normal")),
      State = colDef(show = FALSE),
      Country = colDef(width = 80),
      is_online = colDef(show = FALSE),
      schedule_count = colDef(
        name = "Sched.",
        width = 70,
        align = "center",
        cell = function(value, index) {
          is_online <- data$is_online[index]
          if (isTRUE(is_online)) {
            span(class = "text-muted", "-")
          } else if (value == 0) {
            span(
              class = "badge bg-warning text-dark",
              title = "No schedule - click to add",
              "None"
            )
          } else {
            span(class = "badge bg-success", value)
          }
        }
      )
    )
  )
})

# Handle store selection for editing
observeEvent(input$admin_store_list__reactable__selected, {

  selected_idx <- input$admin_store_list__reactable__selected

  if (is.null(selected_idx) || length(selected_idx) == 0) {
    return()
  }

  # Use stored table data to get store_id (avoids ORDER BY mismatch)
  table_data <- rv$admin_store_list_data
  if (is.null(table_data) || selected_idx > nrow(table_data)) return()

  store_id <- table_data$store_id[selected_idx]

  # Fetch full store details by ID
  store <- safe_query(db_pool, "
    SELECT s.store_id, s.name, s.address, s.city, s.state, s.zip_code, s.website, s.is_online, s.country, s.scene_id
    FROM stores s
    WHERE s.store_id = $1
  ", params = list(store_id),
     default = data.frame())

  if (nrow(store) == 0) return()
  store <- store[1, ]

  # Populate form for editing
  updateTextInput(session, "editing_store_id", value = as.character(store$store_id))

  # Handle online store fields
  is_online <- isTRUE(store$is_online)
  updateCheckboxInput(session, "store_is_online", value = is_online)

  if (is_online) {
    updateTextInput(session, "store_name_online", value = store$name)
    updateSelectInput(session, "store_country", selected = if (is.na(store$country)) "USA" else store$country)
    updateTextInput(session, "store_region", value = if (is.na(store$city)) "" else store$city)
    updateTextInput(session, "store_name", value = "")  # Clear physical store name
  } else {
    updateTextInput(session, "store_name", value = store$name)
    updateSelectInput(session, "store_country_physical", selected = if (is.na(store$country)) "USA" else store$country)
    updateTextInput(session, "store_name_online", value = "")  # Clear online store name
    updateTextInput(session, "store_region", value = "")
  }

  updateTextInput(session, "store_address", value = if (is.na(store$address)) "" else store$address)
  updateTextInput(session, "store_city", value = if (is.na(store$city)) "" else store$city)
  updateTextInput(session, "store_state", value = if (is.na(store$state)) "" else store$state)
  updateTextInput(session, "store_zip", value = if (is.na(store$zip_code)) "" else store$zip_code)
  updateTextInput(session, "store_website", value = if (is.na(store$website)) "" else store$website)
  # Set scene choices + selection together to avoid race condition where
  # choices haven't loaded yet and selected value gets silently dropped
  accessible <- get_admin_accessible_scene_ids(db_pool, rv$admin_user)
  scene_choices <- get_grouped_scene_choices(db_pool, key_by = "id", include_online = TRUE,
                                             scene_ids = accessible)
  updateSelectInput(session, "store_scene",
                    choices = c("Select scene..." = "", scene_choices),
                    selected = if (is.na(store$scene_id)) "" else as.character(store$scene_id))

  # Clear pending schedules when entering edit mode (we use database schedules instead)
  rv$pending_schedules <- list()

  # Show/hide buttons
  shinyjs::hide("add_store")
  shinyjs::show("update_store")
  shinyjs::show("delete_store")

  notify(sprintf("Editing: %s", store$name), type = "message", duration = 2)
})

# Update store
observeEvent(input$update_store, {
  req(rv$is_admin, db_pool)
  req(input$editing_store_id)
  clear_all_field_errors(session)

  store_id <- as.integer(input$editing_store_id)
  is_online <- isTRUE(input$store_is_online)

  store_country <- if (is_online) {
    input$store_country %||% "USA"
  } else {
    input$store_country_physical %||% "USA"
  }

  store_name <- if (is_online) {
    trimws(input$store_name_online)
  } else {
    trimws(input$store_name)
  }

  store_city <- if (is_online) {
    trimws(input$store_region)
  } else {
    trimws(input$store_city)
  }

  if (nchar(store_name) == 0) {
    show_field_error(session, if (is_online) "store_name_online" else "store_name")
    notify("Store name is required", type = "error")
    return()
  }

  # City only required for physical stores
  if (!is_online && nchar(store_city) == 0) {
    show_field_error(session, "store_city")
    notify("Please enter a city", type = "error")
    return()
  }

  # ZIP code required for physical stores
  if (!is_online && nchar(trimws(input$store_zip)) == 0) {
    show_field_error(session, "store_zip")
    notify("Please enter a ZIP code", type = "error")
    return()
  }

  # Scene required for all stores
  if (is.null(input$store_scene) || input$store_scene == "") {
    show_field_error(session, "store_scene")
    notify("Please select a scene", type = "error")
    return()
  }

  # Validate website URL format if provided
  if (nchar(input$store_website) > 0 && !grepl("^https?://", input$store_website)) {
    show_field_error(session, "store_website")
    notify("Website should start with http:// or https://", type = "warning")
  }

  tryCatch({
    # Online stores don't need geocoding
    if (is_online) {
      lat <- NA_real_
      lng <- NA_real_
      address <- NA_character_
      state <- NA_character_
      zip_code <- NA_character_
      store_city_db <- if (nchar(store_city) > 0) store_city else NA_character_
    } else {
      # Build full address for geocoding
      address_parts <- c(input$store_address, store_city)
      if (nchar(trimws(input$store_state)) > 0) address_parts <- c(address_parts, trimws(input$store_state))
      if (nchar(trimws(input$store_zip)) > 0) address_parts <- c(address_parts, trimws(input$store_zip))
      if (nchar(store_country) > 0) address_parts <- c(address_parts, store_country)
      full_address <- paste(address_parts, collapse = ", ")

      # Geocode the address using Mapbox
      notify("Geocoding address...", type = "message", duration = 2)
      geo_result <- geocode_with_mapbox(full_address)

      lat <- geo_result$lat
      lng <- geo_result$lng

      if (is.na(lat) || is.na(lng)) {
        notify("Could not geocode address. Keeping existing coordinates.", type = "warning")
        # Keep existing coordinates
        existing <- safe_query(db_pool, "SELECT latitude, longitude FROM stores WHERE store_id = $1",
                               params = list(store_id),
                               default = data.frame(latitude = NA_real_, longitude = NA_real_))
        lat <- existing$latitude
        lng <- existing$longitude
      }

      zip_code <- if (nchar(trimws(input$store_zip)) > 0) trimws(input$store_zip) else NA_character_
      address <- if (nchar(trimws(input$store_address)) > 0) trimws(input$store_address) else NA_character_
      state <- if (nchar(trimws(input$store_state)) > 0) trimws(input$store_state) else NA_character_
      store_city_db <- store_city
    }

    website <- if (nchar(input$store_website) > 0) input$store_website else NA_character_
    scene_id <- if (!is.null(input$store_scene) && input$store_scene != "") as.integer(input$store_scene) else NA_integer_

    updated_slug <- generate_unique_store_slug(db_pool, store_name, exclude_store_id = store_id)
    safe_execute(db_pool, "
      UPDATE stores
      SET name = $1, slug = $2, address = $3, city = $4, state = $5, zip_code = $6,
          latitude = $7, longitude = $8, website = $9, is_online = $10, country = $11, scene_id = $12,
          updated_at = CURRENT_TIMESTAMP, updated_by = $13
      WHERE store_id = $14
    ", params = list(store_name, updated_slug, address, store_city_db, state, zip_code, lat, lng, website, is_online, store_country, scene_id, current_admin_username(rv), store_id))

    notify(sprintf("Updated store: %s", store_name), type = "message")

    # Clear form and reset to add mode
    updateTextInput(session, "editing_store_id", value = "")
    updateTextInput(session, "store_name", value = "")
    updateTextInput(session, "store_name_online", value = "")
    updateTextInput(session, "store_region", value = "")
    updateTextInput(session, "store_address", value = "")
    updateTextInput(session, "store_city", value = "")
    updateTextInput(session, "store_state", value = "")
    updateTextInput(session, "store_zip", value = "")
    updateTextInput(session, "store_website", value = "")
    updateCheckboxInput(session, "store_is_online", value = FALSE)
    updateSelectInput(session, "store_country", selected = "USA")
    updateSelectInput(session, "store_country_physical", selected = "USA")
    updateSelectInput(session, "store_scene", selected = "")
    rv$pending_schedules <- list()  # Clear pending schedules

    shinyjs::show("add_store")
    shinyjs::hide("update_store")
    shinyjs::hide("delete_store")

    # Trigger refresh of public tables (also updates tournament_store dropdown via observer)
    rv$refresh_stores <- rv$refresh_stores + 1

  }, error = function(e) {
    if (sentry_enabled) tryCatch(sentryR::capture_exception(e, tags = sentry_context_tags()), error = function(se) NULL)
    notify(paste("Error:", e$message), type = "error")
  })
})

# Cancel edit store
observeEvent(input$cancel_edit_store, {
  updateTextInput(session, "editing_store_id", value = "")
  updateTextInput(session, "store_name", value = "")
  updateTextInput(session, "store_name_online", value = "")
  updateTextInput(session, "store_region", value = "")
  updateTextInput(session, "store_address", value = "")
  updateTextInput(session, "store_city", value = "")
  updateTextInput(session, "store_state", value = "")
  updateTextInput(session, "store_zip", value = "")
  updateTextInput(session, "store_website", value = "")
  updateCheckboxInput(session, "store_is_online", value = FALSE)
  updateSelectInput(session, "store_country", selected = "USA")
  updateSelectInput(session, "store_country_physical", selected = "USA")
  rv$pending_schedules <- list()  # Clear pending schedules

  shinyjs::show("add_store")
  shinyjs::hide("update_store")
  shinyjs::hide("delete_store")
})

# Check if store can be deleted (no related tournaments)
observe({
  req(input$editing_store_id, db_pool)
  store_id <- as.integer(input$editing_store_id)

  result <- safe_query(db_pool, "
    SELECT COUNT(*) as cnt FROM tournaments WHERE store_id = $1
  ", params = list(store_id), default = data.frame(cnt = 0))
  count <- result$cnt

  rv$store_tournament_count <- count
  rv$can_delete_store <- count == 0
})

# Delete button click - show modal
observeEvent(input$delete_store, {
  req(rv$is_admin, input$editing_store_id)

  store_id <- as.integer(input$editing_store_id)
  store <- safe_query(db_pool, "SELECT name FROM stores WHERE store_id = $1",
                      params = list(store_id),
                      default = data.frame(name = character()))

  if (rv$can_delete_store) {
    showModal(modalDialog(
      title = "Confirm Delete",
      div(
        p(sprintf("Are you sure you want to delete '%s'?", store$name)),
        p(class = "text-danger", "This action cannot be undone.")
      ),
      footer = tagList(
        actionButton("confirm_delete_store", "Delete", class = "btn-danger"),
        modalButton("Cancel")
      ),
      easyClose = TRUE
    ))
  } else {
    notify(
      sprintf("Cannot delete: %d tournament(s) reference this store", as.integer(rv$store_tournament_count)),
      type = "error"
    )
  }
})

# Confirm delete
observeEvent(input$confirm_delete_store, {
  req(rv$is_admin, db_pool, input$editing_store_id)
  store_id <- as.integer(input$editing_store_id)

  # Soft delete: set is_active = FALSE instead of hard DELETE.
  # All queries already filter WHERE is_active = TRUE.
  rows_updated <- safe_execute(db_pool,
    "UPDATE stores SET is_active = FALSE, updated_at = CURRENT_TIMESTAMP, updated_by = $2 WHERE store_id = $1",
    params = list(store_id, current_admin_username(rv)))
  delete_ok <- rows_updated > 0

  if (!delete_ok) {
    notify("Failed to delete store. Check logs for details.", type = "error")
    return()
  }

  notify("Store deleted", type = "message")

  # Hide modal and reset form
  removeModal()

  # Clear form
  updateTextInput(session, "editing_store_id", value = "")
  updateTextInput(session, "store_name", value = "")
  updateTextInput(session, "store_name_online", value = "")
  updateTextInput(session, "store_region", value = "")
  updateTextInput(session, "store_address", value = "")
  updateTextInput(session, "store_city", value = "")
  updateTextInput(session, "store_state", value = "")
  updateTextInput(session, "store_zip", value = "")
  updateTextInput(session, "store_website", value = "")
  updateCheckboxInput(session, "store_is_online", value = FALSE)
  updateSelectInput(session, "store_country", selected = "USA")
  updateSelectInput(session, "store_country_physical", selected = "USA")
  updateSelectInput(session, "store_scene", selected = "")
  rv$pending_schedules <- list()  # Clear pending schedules

  shinyjs::show("add_store")
  shinyjs::hide("update_store")
  shinyjs::hide("delete_store")

  # Trigger refresh of public tables (also updates tournament_store dropdown via observer)
  rv$refresh_stores <- rv$refresh_stores + 1
})

# =============================================================================
# Store Schedules Management
# =============================================================================

# Day of week labels
DAY_LABELS <- c("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")

# Pending schedules display (for new stores)
output$pending_schedules_display <- renderUI({
  schedules <- rv$pending_schedules

  if (length(schedules) == 0) {
    return(div(
      class = "text-muted small py-2",
      bsicons::bs_icon("calendar-plus", class = "me-1"),
      "No schedules added yet. Add at least one schedule below."
    ))
  }

  # Build schedule list
  schedule_items <- lapply(seq_along(schedules), function(i) {
    sched <- schedules[[i]]
    day_name <- DAY_LABELS[sched$day_of_week + 1]

    # Format time (24h to 12h)
    parts <- strsplit(sched$start_time, ":")[[1]]
    hour <- as.integer(parts[1])
    minute <- parts[2]
    ampm <- if (hour >= 12) "PM" else "AM"
    hour12 <- if (hour == 0) 12 else if (hour > 12) hour - 12 else hour
    time_display <- sprintf("%d:%s %s", hour12, minute, ampm)

    div(
      class = "d-flex justify-content-between align-items-center py-1 px-2 mb-1 bg-light rounded",
      div(
        span(class = "fw-medium", day_name),
        span(class = "text-muted mx-2", time_display),
        span(class = "badge bg-secondary", {
          freq <- sched$frequency
          if (freq == "monthly" && !is.na(sched$week_of_month)) {
            paste0(tools::toTitleCase(sched$week_of_month), " ", day_name, "/mo")
          } else if (freq == "biweekly" && !is.na(sched$next_occurrence)) {
            paste0("Biweekly (next: ", format(as.Date(sched$next_occurrence), "%b %d"), ")")
          } else {
            tools::toTitleCase(freq)
          }
        })
      ),
      actionButton(
        inputId = paste0("remove_pending_schedule_", i),
        label = bsicons::bs_icon("x"),
        class = "btn btn-sm btn-outline-danger py-0 px-1",
        onclick = sprintf("Shiny.setInputValue('remove_pending_schedule', %d, {priority: 'event'})", i)
      )
    )
  })

  div(
    p(class = "text-muted small mb-2", sprintf("%d schedule(s) to be added:", length(schedules))),
    schedule_items
  )
})

# Remove pending schedule
observeEvent(input$remove_pending_schedule, {
  idx <- input$remove_pending_schedule
  if (!is.null(idx) && idx > 0 && idx <= length(rv$pending_schedules)) {
    rv$pending_schedules <- rv$pending_schedules[-idx]
    notify("Schedule removed", type = "message", duration = 2)
  }
})

# Render schedules table for selected store
output$store_schedules_table <- renderReactable({
  req(input$editing_store_id)


  store_id <- as.integer(input$editing_store_id)

  # Trigger refresh when schedules change
  rv$schedules_refresh

  schedules <- safe_query(db_pool, "
    SELECT schedule_id, day_of_week, start_time, frequency, week_of_month, next_occurrence
    FROM store_schedules
    WHERE store_id = $1 AND is_active = TRUE
    ORDER BY day_of_week, start_time
  ", params = list(store_id), default = data.frame())

  if (nrow(schedules) == 0) {
    return(NULL)
  }

  # Convert day_of_week to label
  schedules$day_name <- DAY_LABELS[schedules$day_of_week + 1]

  # Format time for display (24h to 12h)
  schedules$time_display <- sapply(schedules$start_time, function(t) {
    parts <- strsplit(t, ":")[[1]]
    hour <- as.integer(parts[1])
    minute <- parts[2]
    ampm <- if (hour >= 12) "PM" else "AM"
    hour12 <- if (hour == 0) 12 else if (hour > 12) hour - 12 else hour
    sprintf("%d:%s %s", hour12, minute, ampm)
  })

  # Build frequency display with qualifier
  schedules$freq_display <- sapply(seq_len(nrow(schedules)), function(i) {
    freq <- schedules$frequency[i]
    if (freq == "monthly" && !is.na(schedules$week_of_month[i])) {
      paste0(tools::toTitleCase(schedules$week_of_month[i]), " ", schedules$day_name[i], "/mo")
    } else if (freq == "biweekly" && !is.na(schedules$next_occurrence[i])) {
      paste0("Biweekly (next: ", format(as.Date(schedules$next_occurrence[i]), "%b %d"), ")")
    } else {
      tools::toTitleCase(freq)
    }
  })

  reactable(
    schedules[, c("schedule_id", "day_name", "time_display", "freq_display")],
    compact = TRUE,
    striped = TRUE,
    columns = list(
      schedule_id = colDef(show = FALSE),
      day_name = colDef(name = "Day", width = 100),
      time_display = colDef(name = "Time", width = 90),
      freq_display = colDef(name = "Frequency", minWidth = 120)
    ),
    onClick = JS("function(rowInfo, column) {
      if (column.id !== 'delete') {
        Shiny.setInputValue('schedule_to_delete', rowInfo.row.schedule_id, {priority: 'event'});
      }
    }"),
    rowStyle = list(cursor = "pointer")
  )
})

# Add schedule (handles both new stores and editing existing stores)
observeEvent(input$add_schedule, {
  req(rv$is_admin, db_pool)
  clear_all_field_errors(session)

  day_of_week <- as.integer(input$schedule_day)
  start_time <- input$schedule_time
  frequency <- input$schedule_frequency
  week_of_month <- if (frequency == "monthly") input$schedule_week_of_month else NA_character_
  next_occurrence <- if (frequency == "biweekly" && !is.null(input$schedule_next_occurrence)) {
    as.character(input$schedule_next_occurrence)
  } else {
    NA_character_
  }

  # Validate time format
  if (is.null(start_time) || start_time == "") {
    show_field_error(session, "schedule_time")
    notify("Please enter a start time", type = "error")
    return()
  }

  # Check if we're editing an existing store or adding a new one
  is_editing <- !is.null(input$editing_store_id) && input$editing_store_id != ""

  if (is_editing) {
    # EDITING MODE: Insert directly to database
    store_id <- as.integer(input$editing_store_id)

    tryCatch({
      # Check for duplicate schedule
      existing <- safe_query(db_pool, "
        SELECT schedule_id FROM store_schedules
        WHERE store_id = $1 AND day_of_week = $2 AND start_time = $3 AND is_active = TRUE
      ", params = list(store_id, day_of_week, start_time),
         default = data.frame(schedule_id = integer()))

      if (nrow(existing) > 0) {
        notify("This schedule already exists for this store", type = "warning")
        return()
      }

      safe_execute(db_pool, "
        INSERT INTO store_schedules (store_id, day_of_week, start_time, frequency, week_of_month, next_occurrence)
        VALUES ($1, $2, $3, $4, $5, $6::date)
      ", params = list(store_id, day_of_week, start_time, frequency, week_of_month,
                       if (is.na(next_occurrence)) NA else next_occurrence))

      notify(sprintf("Added %s schedule", DAY_LABELS[day_of_week + 1]), type = "message")

      # Trigger refresh
      rv$schedules_refresh <- (rv$schedules_refresh %||% 0) + 1

    }, error = function(e) {
      if (sentry_enabled) tryCatch(sentryR::capture_exception(e, tags = sentry_context_tags()), error = function(se) NULL)
      notify(paste("Error adding schedule:", e$message), type = "error")
    })

  } else {
    # NEW STORE MODE: Add to pending schedules list
    # Check for duplicate in pending schedules
    is_duplicate <- any(sapply(rv$pending_schedules, function(s) {
      s$day_of_week == day_of_week && s$start_time == start_time
    }))

    if (is_duplicate) {
      notify("This schedule is already in your pending list", type = "warning")
      return()
    }

    # Add to pending schedules
    new_schedule <- list(
      day_of_week = day_of_week,
      start_time = start_time,
      frequency = frequency,
      week_of_month = week_of_month,
      next_occurrence = next_occurrence
    )
    rv$pending_schedules <- c(rv$pending_schedules, list(new_schedule))

    notify(sprintf("Added %s schedule (will be saved with store)", DAY_LABELS[day_of_week + 1]), type = "message")
  }

  # Reset form inputs
  updateSelectInput(session, "schedule_day", selected = "1")
  updateTextInput(session, "schedule_time", value = "19:00")
  updateSelectInput(session, "schedule_frequency", selected = "weekly")
  updateSelectInput(session, "schedule_week_of_month", selected = "1st")
  updateDateInput(session, "schedule_next_occurrence", value = Sys.Date())
})

# Delete schedule (triggered by clicking a row)
observeEvent(input$schedule_to_delete, {
  req(rv$is_admin, db_pool)

  schedule_id <- input$schedule_to_delete

  # Show confirmation
  showModal(modalDialog(
    title = "Delete Schedule",
    "Are you sure you want to delete this schedule?",
    footer = tagList(
      modalButton("Cancel"),
      actionButton("confirm_delete_schedule", "Delete", class = "btn-danger")
    ),
    easyClose = TRUE
  ))

  rv$schedule_to_delete_id <- schedule_id
})

# Confirm delete schedule
observeEvent(input$confirm_delete_schedule, {
  req(rv$is_admin, db_pool, rv$schedule_to_delete_id)

  tryCatch({
    safe_execute(db_pool, "
      UPDATE store_schedules SET is_active = FALSE, updated_at = CURRENT_TIMESTAMP
      WHERE schedule_id = $1
    ", params = list(rv$schedule_to_delete_id))

    notify("Schedule deleted", type = "message")
    removeModal()

    # Trigger refresh
    rv$schedules_refresh <- (rv$schedules_refresh %||% 0) + 1
    rv$schedule_to_delete_id <- NULL

  }, error = function(e) {
    if (sentry_enabled) tryCatch(sentryR::capture_exception(e, tags = sentry_context_tags()), error = function(se) NULL)
    notify(paste("Error deleting schedule:", e$message), type = "error")
  })
})

# Scene indicator for admin stores page
output$admin_stores_scene_indicator <- renderUI({
  scene <- rv$current_scene
  show_all <- isTRUE(input$admin_stores_show_all_scenes) && isTRUE(rv$is_superadmin)

  if (show_all || is.null(scene) || scene == "" || scene == "all") {
    return(NULL)
  }

  div(
    class = "badge bg-info mb-2",
    paste("Filtered to:", toupper(scene))
  )
})
