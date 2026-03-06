# =============================================================================
# Admin: Edit Stores Server Logic
# =============================================================================

# -----------------------------------------------------------------------------
# Mapbox Geocoding Helper
# -----------------------------------------------------------------------------
#' Geocode an address using Mapbox Geocoding API
#'
#' @param address Full address string to geocode
#' @return List with lat and lng, or list(lat = NA, lng = NA) if failed
geocode_with_mapbox <- function(address) {
  # Get Mapbox token from environment

  mapbox_token <- Sys.getenv("MAPBOX_ACCESS_TOKEN")
  if (mapbox_token == "") {
    warning("MAPBOX_ACCESS_TOKEN not set")
    return(list(lat = NA_real_, lng = NA_real_))
  }

  tryCatch({
    # URL encode the address
    encoded_address <- utils::URLencode(address, reserved = TRUE)

    # Build request URL
    url <- sprintf(
      "https://api.mapbox.com/geocoding/v5/mapbox.places/%s.json?access_token=%s&limit=1",
      encoded_address,
      mapbox_token
    )

    # Make request using httr2
    resp <- httr2::request(url) |>
      httr2::req_timeout(10) |>
      httr2::req_perform()

    # Parse response
    result <- httr2::resp_body_json(resp)

    # Check if we got results
    if (length(result$features) == 0) {
      return(list(lat = NA_real_, lng = NA_real_))
    }

    # Mapbox returns [longitude, latitude]
    coords <- result$features[[1]]$center
    list(lat = coords[[2]], lng = coords[[1]])

  }, error = function(e) {
    warning(paste("Mapbox geocoding error:", e$message))
    list(lat = NA_real_, lng = NA_real_)
  })
}

# -----------------------------------------------------------------------------
# Mapbox Reverse Geocoding Helper
# -----------------------------------------------------------------------------
#' Reverse geocode coordinates using Mapbox Geocoding API
#'
#' @param lat Latitude
#' @param lng Longitude
#' @return List with country and state_region, or NAs if failed
reverse_geocode_with_mapbox <- function(lat, lng) {
  mapbox_token <- Sys.getenv("MAPBOX_ACCESS_TOKEN")
  if (mapbox_token == "") {
    warning("MAPBOX_ACCESS_TOKEN not set")
    return(list(country = NA_character_, state_region = NA_character_))
  }

  tryCatch({
    url <- sprintf(
      "https://api.mapbox.com/geocoding/v5/mapbox.places/%s,%s.json?access_token=%s&types=region,country",
      lng, lat, mapbox_token
    )

    resp <- httr2::request(url) |>
      httr2::req_timeout(10) |>
      httr2::req_perform()

    result <- httr2::resp_body_json(resp)

    country <- NA_character_
    state_region <- NA_character_

    if (length(result$features) > 0) {
      for (feat in result$features) {
        feat_id <- feat$id %||% ""
        if (grepl("^country\\.", feat_id)) {
          country <- feat$text
        } else if (grepl("^region\\.", feat_id)) {
          state_region <- feat$text
        }
      }
    }

    list(country = country, state_region = state_region)

  }, error = function(e) {
    warning(paste("Mapbox reverse geocoding error:", e$message))
    list(country = NA_character_, state_region = NA_character_)
  })
}

# --- Load scene choices for store dropdown ---
# Only fires when on admin_stores tab (prevents race condition with lazy-loaded UI)
observe({
  rv$current_nav
  req(rv$current_nav == "admin_stores")
  rv$data_refresh
  req(db_pool, rv$is_admin)

  # Check if UI has rendered yet
  if (is.null(input$store_name)) {
    # UI not ready yet, retry shortly
    invalidateLater(100)
    return()
  }

  scenes <- tryCatch(
    dbGetQuery(db_pool,
      "SELECT scene_id, display_name FROM scenes
       WHERE is_active = TRUE
       ORDER BY scene_type, display_name"),
    error = function(e) data.frame()
  )
  if (nrow(scenes) > 0) {
    choices <- setNames(as.character(scenes$scene_id), scenes$display_name)
    # Preserve current selection when repopulating choices (fixes scene clearing bug)
    current_selection <- isolate(input$store_scene)
    updateSelectInput(session, "store_scene",
                      choices = c("Select scene..." = "", choices),
                      selected = current_selection)
  }
})

# --- Refresh tournament_store dropdown on data changes ---
# Separated from add/update/delete handlers to prevent catalog race conditions.
# The SELECT runs in the next reactive cycle, after writes complete.
observe({
  rv$data_refresh
  req(db_pool, rv$is_admin)
  updateSelectInput(session, "tournament_store",
                    choices = get_store_choices(db_pool, include_none = TRUE))
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

  # ZIP code is required for physical stores
  if (!is_online && nchar(trimws(input$store_zip)) == 0) {
    show_field_error(session, "store_zip")
    notify("Please enter a ZIP code", type = "error")
    return()
  }

  # Check for duplicate store name in same city/region
  # For online stores with no region, check for duplicate name among online stores
  if (is_online && nchar(store_city) == 0) {
    existing <- dbGetQuery(db_pool, "
      SELECT store_id FROM stores
      WHERE LOWER(name) = LOWER($1) AND is_online = TRUE AND (city IS NULL OR city = '')
    ", params = list(store_name))
  } else {
    existing <- dbGetQuery(db_pool, "
      SELECT store_id FROM stores
      WHERE LOWER(name) = LOWER($1) AND LOWER(city) = LOWER($2)
    ", params = list(store_name, store_city))
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

    store_result <- dbGetQuery(db_pool, "
      INSERT INTO stores (name, address, city, state, zip_code, latitude, longitude, website, is_online, country, scene_id)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
      RETURNING store_id
    ", params = list(store_name, address, store_city_db,
                     state, zip_code, lat, lng, website, is_online, store_country, scene_id))
    new_id <- store_result$store_id[1]

    # Insert any pending schedules for physical stores
    if (!is_online && length(rv$pending_schedules) > 0) {
      for (i in seq_along(rv$pending_schedules)) {
        sched <- rv$pending_schedules[[i]]
        dbExecute(db_pool, "
          INSERT INTO store_schedules (store_id, day_of_week, start_time, frequency)
          VALUES ($1, $2, $3, $4)
        ", params = list(new_id, sched$day_of_week, sched$start_time, sched$frequency))
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
    rv$data_refresh <- (rv$data_refresh %||% 0) + 1

  }, error = function(e) {
    notify(paste("Error:", e$message), type = "error")
  })
})

# Admin store list
output$admin_store_list <- renderReactable({


  # Trigger refresh via rv$data_refresh (set after add/update/delete complete)
  # Do NOT use input$add_store etc. directly — they fire simultaneously with
  # the handler, racing on the same connection
  rv$data_refresh
  rv$schedules_refresh
  input$admin_stores_show_all_scenes

  scene <- rv$current_scene
  show_all <- isTRUE(input$admin_stores_show_all_scenes) && isTRUE(rv$is_superadmin)

  # Build scene filter
  scene_filter <- ""
  scene_params <- list()
  if (!show_all && !is.null(scene) && scene != "" && scene != "all") {
    if (scene == "online") {
      scene_filter <- "AND s.is_online = TRUE"
    } else {
      scene_filter <- "AND s.scene_id = (SELECT scene_id FROM scenes WHERE slug = $1)"
      scene_params <- list(scene)
    }
  }

  # Query stores with schedule count
  data <- dbGetQuery(db_pool, sprintf("
    SELECT s.store_id, s.name as \"Store\", s.city as \"City\", s.state as \"State\",
           s.is_online, s.zip_code,
           COUNT(ss.schedule_id) as schedule_count
    FROM stores s
    LEFT JOIN store_schedules ss ON s.store_id = ss.store_id AND ss.is_active = TRUE
    WHERE s.is_active = TRUE %s
    GROUP BY s.store_id, s.name, s.city, s.state, s.is_online, s.zip_code
    ORDER BY
      CASE WHEN s.is_online = FALSE AND COUNT(ss.schedule_id) = 0 THEN 0 ELSE 1 END,
      CASE WHEN s.zip_code IS NULL OR s.zip_code = '' THEN 0 ELSE 1 END,
      s.name
  ", scene_filter), params = if (length(scene_params) > 0) scene_params else NULL)

  if (nrow(data) == 0) {
    data <- data.frame(Message = "No stores yet")
    return(reactable(data, compact = TRUE))
  }

  # Determine completeness status for each row
  data$status <- sapply(1:nrow(data), function(i) {
    is_online <- isTRUE(data$is_online[i])
    has_schedule <- data$schedule_count[i] > 0
    has_zip <- !is.na(data$zip_code[i]) && nchar(data$zip_code[i]) > 0

    if (is_online) {
      "complete"  # Online stores don't need schedules or zip
    } else if (!has_schedule && !has_zip) {
      "missing_both"
    } else if (!has_schedule) {
      "missing_schedule"
    } else if (!has_zip) {
      "missing_zip"
    } else {
      "complete"
    }
  })

  # Store data for selection handler (avoids re-query with different ORDER BY)
  rv$admin_store_list_data <- data

  reactable(data, compact = TRUE, striped = FALSE,
    sortable = FALSE,
    selection = "single",
    onClick = "select",
    searchable = TRUE,
    defaultPageSize = 12,
    showPageSizeOptions = TRUE,
    pageSizeOptions = c(10, 20, 50, 100),
    rowStyle = function(index) {
      status <- data$status[index]
      base_style <- list(cursor = "pointer")

      if (status == "missing_both") {
        base_style$backgroundColor <- "rgba(229, 56, 59, 0.15)"  # Red tint
        base_style$borderLeft <- "3px solid #E5383B"
      } else if (status == "missing_schedule") {
        base_style$backgroundColor <- "rgba(245, 183, 0, 0.15)"  # Yellow tint
        base_style$borderLeft <- "3px solid #F5B700"
      } else if (status == "missing_zip") {
        base_style$backgroundColor <- "rgba(245, 183, 0, 0.1)"  # Light yellow tint
        base_style$borderLeft <- "3px solid #F5B700"
      }

      base_style
    },
    columns = list(
      store_id = colDef(show = FALSE),
      zip_code = colDef(show = FALSE),
      status = colDef(show = FALSE),
      Store = colDef(minWidth = 140),
      City = colDef(minWidth = 80),
      State = colDef(width = 50),
      is_online = colDef(
        name = "Type",
        width = 70,
        cell = function(value) if (isTRUE(value)) "Online" else "Physical"
      ),
      schedule_count = colDef(
        name = "Schedules",
        width = 85,
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
  store <- dbGetQuery(db_pool, "
    SELECT s.store_id, s.name, s.address, s.city, s.state, s.zip_code, s.website, s.is_online, s.country, s.scene_id
    FROM stores s
    WHERE s.store_id = $1
  ", params = list(store_id))

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
  updateSelectInput(session, "store_scene", selected = if (is.na(store$scene_id)) "" else as.character(store$scene_id))

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
        existing <- dbGetQuery(db_pool, "SELECT latitude, longitude FROM stores WHERE store_id = $1",
                               params = list(store_id))
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

    safe_execute(db_pool, "
      UPDATE stores
      SET name = $1, address = $2, city = $3, state = $4, zip_code = $5,
          latitude = $6, longitude = $7, website = $8, is_online = $9, country = $10, scene_id = $11, updated_at = CURRENT_TIMESTAMP
      WHERE store_id = $12
    ", params = list(store_name, address, store_city_db, state, zip_code, lat, lng, website, is_online, store_country, scene_id, store_id))

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
    rv$data_refresh <- (rv$data_refresh %||% 0) + 1

  }, error = function(e) {
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
  store <- dbGetQuery(db_pool, "SELECT name FROM stores WHERE store_id = $1",
                      params = list(store_id))

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
    "UPDATE stores SET is_active = FALSE, updated_at = CURRENT_TIMESTAMP WHERE store_id = $1",
    params = list(store_id))
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
  rv$data_refresh <- (rv$data_refresh %||% 0) + 1
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
        span(class = "badge bg-secondary", tools::toTitleCase(sched$frequency))
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

  schedules <- dbGetQuery(db_pool, "
    SELECT schedule_id, day_of_week, start_time, frequency
    FROM store_schedules
    WHERE store_id = $1 AND is_active = TRUE
    ORDER BY day_of_week, start_time
  ", params = list(store_id))

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

  # Capitalize frequency
  schedules$freq_display <- tools::toTitleCase(schedules$frequency)

  reactable(
    schedules[, c("schedule_id", "day_name", "time_display", "freq_display")],
    compact = TRUE,
    striped = TRUE,
    columns = list(
      schedule_id = colDef(show = FALSE),
      day_name = colDef(name = "Day", width = 100),
      time_display = colDef(name = "Time", width = 90),
      freq_display = colDef(name = "Frequency", width = 90)
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
      existing <- dbGetQuery(db_pool, "
        SELECT schedule_id FROM store_schedules
        WHERE store_id = $1 AND day_of_week = $2 AND start_time = $3 AND is_active = TRUE
      ", params = list(store_id, day_of_week, start_time))

      if (nrow(existing) > 0) {
        notify("This schedule already exists for this store", type = "warning")
        return()
      }

      dbExecute(db_pool, "
        INSERT INTO store_schedules (store_id, day_of_week, start_time, frequency)
        VALUES ($1, $2, $3, $4)
      ", params = list(store_id, day_of_week, start_time, frequency))

      notify(sprintf("Added %s schedule", DAY_LABELS[day_of_week + 1]), type = "message")

      # Trigger refresh
      rv$schedules_refresh <- (rv$schedules_refresh %||% 0) + 1

    }, error = function(e) {
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
      frequency = frequency
    )
    rv$pending_schedules <- c(rv$pending_schedules, list(new_schedule))

    notify(sprintf("Added %s schedule (will be saved with store)", DAY_LABELS[day_of_week + 1]), type = "message")
  }

  # Reset form inputs
  updateSelectInput(session, "schedule_day", selected = "1")
  updateTextInput(session, "schedule_time", value = "19:00")
  updateSelectInput(session, "schedule_frequency", selected = "weekly")
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
    dbExecute(db_pool, "
      UPDATE store_schedules SET is_active = FALSE, updated_at = CURRENT_TIMESTAMP
      WHERE schedule_id = $1
    ", params = list(rv$schedule_to_delete_id))

    notify("Schedule deleted", type = "message")
    removeModal()

    # Trigger refresh
    rv$schedules_refresh <- (rv$schedules_refresh %||% 0) + 1
    rv$schedule_to_delete_id <- NULL

  }, error = function(e) {
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
