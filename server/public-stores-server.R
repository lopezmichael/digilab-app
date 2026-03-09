# =============================================================================
# Public: Stores Tab Server Logic
# =============================================================================
# Note: Contains modal_player_clicked handler which navigates to Players tab.
# This is kept here for now due to physical proximity; could move to shared-server.R later.
# Also contains reset_dashboard_filters which should ideally be in Dashboard server.

# ---------------------------------------------------------------------------
# Page Rendering (desktop vs mobile)
# ---------------------------------------------------------------------------
output$stores_page <- renderUI({
  if (is_mobile()) {
    source("views/mobile-stores-ui.R", local = TRUE)$value
  } else {
    source("views/stores-ui.R", local = TRUE)$value
  }
})

# =============================================================================
# View Toggle (Schedule / All Stores)
# =============================================================================

# Day of week labels
WEEKDAY_LABELS <- c("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")

# Handle Schedule view button click
observeEvent(input$stores_view_schedule, {
  shinyjs::runjs("
    document.getElementById('stores_view_mode').value = 'schedule';
    Shiny.setInputValue('stores_view_mode', 'schedule');
    document.getElementById('stores_view_schedule').classList.add('active');
    document.getElementById('stores_view_all').classList.remove('active');
  ")
})

# Handle All Stores view button click
observeEvent(input$stores_view_all, {
  shinyjs::runjs("
    document.getElementById('stores_view_mode').value = 'all';
    Shiny.setInputValue('stores_view_mode', 'all');
    document.getElementById('stores_view_all').classList.add('active');
    document.getElementById('stores_view_schedule').classList.remove('active');
  ")
})

# View hint text
output$stores_view_hint <- renderUI({
  view_mode <- input$stores_view_mode
  if (is.null(view_mode) || view_mode != "all") {
    span(class = "small text-muted", "Click a store for details")
  } else {
    span(class = "small text-muted", "Click a row for details")
  }
})

# Schedule view content
output$stores_schedule_content <- renderUI({
  req("stores" %in% visited_tabs())  # Lazy load: skip until tab visited

  rv$data_refresh  # Trigger refresh on admin changes

  # For "All Scenes", show scene summary cards (same as cards view)
  scene <- rv$current_scene
  if (is.null(scene) || scene == "" || scene == "all") {
    scene_stats <- safe_query(db_pool, "
      SELECT sc.slug, sc.display_name, sc.name as scene_name,
             COUNT(DISTINCT s.store_id) as store_count,
             COUNT(t.tournament_id) as total_events,
             COALESCE(ROUND(AVG(t.player_count), 1), 0) as avg_players
      FROM scenes sc
      JOIN stores s ON s.scene_id = sc.scene_id
        AND s.is_active = TRUE
        AND (s.is_online = FALSE OR s.is_online IS NULL)
      LEFT JOIN tournaments t ON s.store_id = t.store_id
      WHERE sc.is_active = TRUE
        AND sc.scene_type = 'metro'
      GROUP BY sc.scene_id, sc.slug, sc.display_name, sc.name
      ORDER BY COUNT(t.tournament_id) DESC
    ")

    if (nrow(scene_stats) == 0) {
      return(digital_empty_state("No scenes available", "// check back soon", "geo-alt", mascot = "agumon"))
    }

    return(render_scene_cards(scene_stats))
  }

  # Get current day of week (0=Sunday in JS, but R's wday returns 1=Sunday)
  today_wday <- as.integer(format(Sys.Date(), "%w"))  # 0=Sunday, 6=Saturday

  # Build scene filter for stores table
  scene_sql <- ""
  scene_params <- list()
  if (!is.null(scene) && scene != "" && scene != "all") {
    if (scene == "online") {
      scene_sql <- "AND s.is_online = TRUE"
    } else {
      scene_sql <- "AND s.scene_id = (SELECT scene_id FROM scenes WHERE slug = $1)"
      scene_params <- list(scene)
    }
  }

  # Query schedules with store info and tournament stats
  # Note: For non-online scenes, we exclude online stores by default
  base_online_filter <- if (is.null(scene) || scene == "" || scene == "all") {
    "AND (s.is_online = FALSE OR s.is_online IS NULL)"
  } else if (scene == "online") {
    ""  # Scene filter already handles is_online = TRUE
  } else {
    "AND (s.is_online = FALSE OR s.is_online IS NULL)"
  }

  schedules_query <- sprintf("
    WITH store_stats AS (
      SELECT store_id,
             COALESCE(ROUND(AVG(player_count), 0), 0) as avg_players
      FROM tournaments
      GROUP BY store_id
    )
    SELECT ss.day_of_week, ss.start_time, ss.frequency, ss.week_of_month, ss.next_occurrence,
           s.store_id, s.name as store_name, s.city,
           COALESCE(st.avg_players, 0) as avg_players
    FROM store_schedules ss
    JOIN stores s ON ss.store_id = s.store_id
    LEFT JOIN store_stats st ON s.store_id = st.store_id
    WHERE ss.is_active = TRUE
      AND s.is_active = TRUE
      %s
      %s
    ORDER BY ss.day_of_week, ss.start_time, s.name
  ", base_online_filter, scene_sql)

  schedules <- safe_query(db_pool, schedules_query, params = scene_params)

  # Get stores without schedules
  stores_without_query <- sprintf("
    SELECT s.store_id, s.name, s.city
    FROM stores s
    WHERE s.is_active = TRUE
      %s
      %s
      AND s.store_id NOT IN (
        SELECT DISTINCT store_id FROM store_schedules WHERE is_active = TRUE
      )
    ORDER BY s.name
  ", base_online_filter, scene_sql)

  stores_without_schedules <- safe_query(db_pool, stores_without_query, params = scene_params)

  # Build day sections, sorted starting from today
  day_order <- c(today_wday:6, if (today_wday > 0) 0:(today_wday - 1) else integer(0))

  day_sections <- lapply(day_order, function(day_idx) {
    day_name <- WEEKDAY_LABELS[day_idx + 1]
    is_today <- day_idx == today_wday

    day_schedules <- schedules[schedules$day_of_week == day_idx, ]

    # Format time for display (24h to 12h)
    if (nrow(day_schedules) > 0) {
      day_schedules$time_display <- sapply(day_schedules$start_time, function(t) {
        parts <- strsplit(t, ":")[[1]]
        hour <- as.integer(parts[1])
        minute <- parts[2]
        ampm <- if (hour >= 12) "PM" else "AM"
        hour12 <- if (hour == 0) 12 else if (hour > 12) hour - 12 else hour
        sprintf("%d:%s %s", hour12, minute, ampm)
      })
    }

    day_keys <- c("sun", "mon", "tue", "wed", "thu", "fri", "sat")
    day_class <- paste0("schedule-day--", day_keys[day_idx + 1])

    div(
      class = paste("schedule-day-section mb-3", day_class),
      # Day header
      div(
        class = paste("schedule-day-header", if (is_today) "schedule-day-today" else ""),
        style = if (is_today) "font-weight: bold; color: var(--bs-primary);" else "",
        span(day_name),
        if (is_today) span(class = "badge bg-primary ms-2", "Today")
      ),
      # Store list for this day
      if (nrow(day_schedules) > 0) {
        div(
          class = "schedule-day-stores",
          lapply(1:nrow(day_schedules), function(i) {
            sched <- day_schedules[i, ]
            tags$button(
              type = "button",
              class = "schedule-store-item d-flex justify-content-between align-items-center w-100 text-start border-0 p-2 mb-1",
              onclick = sprintf("Shiny.setInputValue('store_clicked', %d, {priority: 'event'})", sched$store_id),
              div(
                span(class = "fw-medium", sched$store_name),
                if (!is.na(sched$city)) span(class = "text-muted small ms-2", sched$city)
              ),
              div(
                class = "d-flex align-items-center gap-2",
                span(
                  class = "text-muted small",
                  title = "Average tournament size",
                  if (sched$avg_players > 0) paste0("~", sched$avg_players, " Average Turnout") else "Turnout Data Unavailable"
                ),
                span(class = "text-muted", sched$time_display)
              )
            )
          })
        )
      } else {
        div(
          class = "text-muted small ps-2 py-1",
          "No scheduled events"
        )
      }
    )
  })

  # Stores without schedules section
  no_schedule_section <- if (nrow(stores_without_schedules) > 0) {
    div(
      class = "mt-4 pt-3 border-top",
      div(
        class = "text-muted small mb-2",
        bsicons::bs_icon("question-circle"),
        sprintf(" %d store%s without regular schedules",
                nrow(stores_without_schedules),
                if (nrow(stores_without_schedules) == 1) "" else "s")
      ),
      div(
        class = "d-flex flex-wrap gap-1",
        lapply(1:nrow(stores_without_schedules), function(i) {
          store <- stores_without_schedules[i, ]
          tags$button(
            type = "button",
            class = "btn btn-sm btn-outline-secondary",
            onclick = sprintf("Shiny.setInputValue('store_clicked', %d, {priority: 'event'})", store$store_id),
            store$name
          )
        })
      )
    )
  } else {
    NULL
  }

  # Combine all sections
  tagList(
    day_sections,
    no_schedule_section
  )
})

# Store list
output$store_list <- renderReactable({
  rv$data_refresh  # Trigger refresh on admin changes
  stores <- stores_data()

  if (is.null(stores) || nrow(stores) == 0) {
    return(reactable(data.frame(Message = "No stores yet"), compact = TRUE))
  }

  # Join with average player ratings per store
  avg_ratings <- store_avg_ratings()
  stores <- merge(stores, avg_ratings, by = "store_id", all.x = TRUE)
  stores$avg_player_rating[is.na(stores$avg_player_rating)] <- 0

  # Format last event date
  stores$last_event_display <- sapply(stores$last_event, function(d) {
    if (is.na(d)) return("-")
    days_ago <- as.integer(Sys.Date() - as.Date(d))
    if (days_ago == 0) "Today"
    else if (days_ago == 1) "Yesterday"
    else if (days_ago <= 7) paste(days_ago, "days ago")
    else if (days_ago <= 30) paste(ceiling(days_ago / 7), "weeks ago")
    else format(as.Date(d), "%b %d")
  })

  # Format for display - sort by events then avg players
  data <- stores[order(-stores$tournament_count, -stores$avg_players, stores$city, stores$name),
                 c("name", "city", "tournament_count", "avg_players", "avg_player_rating", "last_event_display", "store_id")]
  names(data) <- c("Store", "City", "Events", "Avg Event Size", "Avg Rating", "Last Event", "store_id")

  reactable(
    data,
    compact = TRUE,
    striped = TRUE,
    pagination = TRUE,
    defaultPageSize = 32,
    defaultSorted = list(Events = "desc"),
    rowStyle = list(cursor = "pointer"),
    onClick = JS("function(rowInfo, column) {
      if (rowInfo) {
        Shiny.setInputValue('store_clicked', rowInfo.row.store_id, {priority: 'event'})
      }
    }"),
    columns = list(
      Store = colDef(minWidth = 180),
      City = colDef(minWidth = 100),
      Events = colDef(
        minWidth = 70,
        align = "center",
        cell = function(value) {
          if (value == 0) "-" else value
        }
      ),
      `Avg Event Size` = colDef(
        minWidth = 80,
        align = "center",
        cell = function(value) {
          if (value == 0) "-" else value
        }
      ),
      `Avg Rating` = colDef(
        minWidth = 90,
        align = "center",
        cell = function(value) {
          if (value == 0) "-" else value
        }
      ),
      `Last Event` = colDef(minWidth = 100, align = "center"),
      store_id = colDef(show = FALSE)
    )
  )
}) |> bindCache(rv$current_scene, rv$community_filter, rv$data_refresh)

# Store cards view (replaces table for both physical and online)
output$stores_cards_content <- renderUI({
  req("stores" %in% visited_tabs())  # Lazy load: skip until tab visited
  rv$data_refresh
  scene <- rv$current_scene

  # For online scene, show online organizers
  if (!is.null(scene) && scene == "online") {
    online_stores <- safe_query(db_pool, "
      SELECT s.store_id, s.name, s.city as region, s.country, s.website,
             COUNT(t.tournament_id) as tournament_count,
             COALESCE(ROUND(AVG(t.player_count), 1), 0) as avg_players,
             MAX(t.event_date) as last_event
      FROM stores s
      LEFT JOIN tournaments t ON s.store_id = t.store_id
      WHERE s.is_online = TRUE AND s.is_active = TRUE
      GROUP BY s.store_id, s.name, s.city, s.country, s.website
      ORDER BY s.name
    ")

    if (nrow(online_stores) == 0) {
      return(digital_empty_state("No online organizers", "// check back soon", "globe", mascot = "agumon"))
    }

    return(render_store_cards(online_stores, is_online = TRUE))
  }

  # For "All Scenes", show scene summary cards instead of individual stores
  if (is.null(scene) || scene == "" || scene == "all") {
    scene_stats <- safe_query(db_pool, "
      SELECT sc.slug, sc.display_name, sc.name as scene_name,
             COUNT(DISTINCT s.store_id) as store_count,
             COUNT(t.tournament_id) as total_events,
             COALESCE(ROUND(AVG(t.player_count), 1), 0) as avg_players
      FROM scenes sc
      JOIN stores s ON s.scene_id = sc.scene_id
        AND s.is_active = TRUE
        AND (s.is_online = FALSE OR s.is_online IS NULL)
      LEFT JOIN tournaments t ON s.store_id = t.store_id
      WHERE sc.is_active = TRUE
        AND sc.scene_type = 'metro'
      GROUP BY sc.scene_id, sc.slug, sc.display_name, sc.name
      ORDER BY COUNT(t.tournament_id) DESC
    ")

    if (nrow(scene_stats) == 0) {
      return(digital_empty_state("No scenes available", "// check back soon", "geo-alt", mascot = "agumon"))
    }

    return(render_scene_cards(scene_stats))
  }

  # For specific scenes, show physical stores
  stores <- stores_data()

  if (is.null(stores) || nrow(stores) == 0) {
    return(digital_empty_state("No stores found", "// check back soon", "shop", mascot = "agumon"))
  }

  render_store_cards(stores, is_online = FALSE)
}) |> bindCache(rv$current_scene, rv$community_filter, rv$data_refresh)

# Helper: Render store cards grid
render_store_cards <- function(stores, is_online = FALSE) {
  div(
    class = "row g-3",
    lapply(1:nrow(stores), function(i) {
      store <- stores[i, ]
      div(
        class = "col-md-4 col-lg-3",
        tags$button(
          type = "button",
          class = "store-card-item p-3 h-100 w-100 text-start border-0",
          # Always use store_clicked - modal handles both online and physical stores
          onclick = sprintf("Shiny.setInputValue('store_clicked', %d, {priority: 'event'})", store$store_id),
          h6(class = "mb-1 fw-semibold", store$name),
          if (is_online) {
            tagList(
              if (!is.na(store$country)) p(class = "text-muted small mb-1", bsicons::bs_icon("globe"), " ", store$country),
              if (!is.na(store$region) && store$region != "") p(class = "text-muted small mb-1", bsicons::bs_icon("geo"), " ", store$region)
            )
          } else {
            if (!is.na(store$city)) p(class = "text-muted small mb-1", store$city)
          },
          if (store$tournament_count > 0) {
            p(class = "small mb-0 text-primary",
              bsicons::bs_icon("trophy"), " ", store$tournament_count, " events",
              span(class = "text-muted ms-2", paste0("~", store$avg_players, " avg")))
          } else {
            p(class = "small mb-0 text-muted", "No events yet")
          }
        )
      )
    })
  )
}

# Helper: Render scene summary cards for "All Scenes" view
render_scene_cards <- function(scenes) {
  div(
    class = "row g-3",
    lapply(1:nrow(scenes), function(i) {
      sc <- scenes[i, ]
      scene_label <- if (!is.na(sc$display_name) && nchar(sc$display_name) > 0) sc$display_name else sc$scene_name
      stores_label <- if (sc$store_count == 1) "store" else "stores"
      events_label <- if (sc$total_events == 1) "event" else "events"

      div(
        class = "col-md-4 col-lg-3",
        tags$button(
          type = "button",
          class = "store-card-item scene-card-item p-3 h-100 w-100 text-start border-0",
          onclick = sprintf("Shiny.setInputValue('scene_card_clicked', '%s', {priority: 'event'})", sc$slug),
          h6(class = "mb-1 fw-semibold", bsicons::bs_icon("geo-alt-fill", class = "me-1"), scene_label),
          p(class = "small mb-1 text-primary",
            bsicons::bs_icon("shop"), " ", sc$store_count, " ", stores_label,
            span(class = "text-muted ms-2",
              bsicons::bs_icon("trophy"), " ", sc$total_events, " ", events_label)),
          if (sc$avg_players > 0) {
            p(class = "small mb-0 text-muted",
              paste0("~", sc$avg_players, " avg players"))
          }
        )
      )
    })
  )
}

# Handle scene card click - navigate to that scene
observeEvent(input$scene_card_clicked, {
  updateSelectInput(session, "scene_selector", selected = input$scene_card_clicked)
})

# Handle store row click - open detail modal
observeEvent(input$store_clicked, {
  rv$selected_store_id <- input$store_clicked
})

# Handle cross-modal store click (from player modal, tournament modal, etc.)
observeEvent(input$modal_store_clicked, {
  removeModal()  # Close current modal
  rv$selected_store_id <- input$modal_store_clicked
  nav_select("main_content", "stores")
  rv$current_nav <- "stores"
  session$sendCustomMessage("updateSidebarNav", "nav_stores")
})

# Handle cross-modal player click (from deck modal, tournament modal, etc.)
# Note: This navigates to Players tab but is kept here due to physical proximity
observeEvent(input$modal_player_clicked, {
  removeModal()  # Close current modal
  rv$selected_player_id <- input$modal_player_clicked
  nav_select("main_content", "players")
  rv$current_nav <- "players"
  session$sendCustomMessage("updateSidebarNav", "nav_players")
})

# Render store detail modal
output$store_detail_modal <- renderUI({
  req(rv$selected_store_id)

  store_id <- rv$selected_store_id
  stores <- stores_data()
  store <- stores[stores$store_id == store_id, ]

  # If store not found in filtered data (e.g. online store when viewing "all" scene),
  # query directly from the database
  if (nrow(store) == 0) {
    store <- safe_query(db_pool, "
      SELECT s.store_id, s.name, s.address, s.city, s.state, s.zip_code,
             s.latitude, s.longitude, s.website, s.schedule_info, s.slug,
             s.country, s.is_online,
             COUNT(t.tournament_id) as tournament_count,
             COALESCE(ROUND(AVG(t.player_count), 1), 0) as avg_players,
             MAX(t.event_date) as last_event
      FROM stores s
      LEFT JOIN tournaments t ON s.store_id = t.store_id
      WHERE s.store_id = $1
      GROUP BY s.store_id, s.name, s.address, s.city, s.state, s.zip_code,
               s.latitude, s.longitude, s.website, s.schedule_info, s.slug,
               s.country, s.is_online
    ", params = list(store_id))
  }

  if (nrow(store) == 0) return(NULL)

  # Get recent tournaments at this store
  recent_tournaments <- safe_query(db_pool, "
      SELECT t.event_date as \"Date\", t.event_type as \"Type\", t.format as \"Format\",
             t.player_count as \"Players\", p.display_name as \"Winner\",
             da.archetype_name as \"Deck\", r.decklist_url
      FROM tournaments t
      LEFT JOIN LATERAL (
        SELECT r2.player_id, r2.archetype_id, r2.decklist_url
        FROM results r2
        WHERE r2.tournament_id = t.tournament_id AND r2.placement = 1
        ORDER BY r2.result_id
        LIMIT 1
      ) r ON true
      LEFT JOIN players p ON r.player_id = p.player_id
      LEFT JOIN deck_archetypes da ON r.archetype_id = da.archetype_id
      WHERE t.store_id = $1
      ORDER BY t.event_date DESC
      LIMIT 5
    ", params = list(store_id))

  # Get top players at this store
  top_players <- safe_query(db_pool, "
      SELECT p.display_name as \"Player\",
             COUNT(DISTINCT r.tournament_id) as \"Events\",
             COUNT(CASE WHEN r.placement = 1 THEN 1 END) as \"Wins\"
      FROM players p
      JOIN results r ON p.player_id = r.player_id
      JOIN tournaments t ON r.tournament_id = t.tournament_id
      WHERE t.store_id = $1
      GROUP BY p.player_id, p.display_name
      ORDER BY COUNT(CASE WHEN r.placement = 1 THEN 1 END) DESC, COUNT(DISTINCT r.tournament_id) DESC
      LIMIT 5
    ", params = list(store_id))

  # Get average player rating for this store
  avg_ratings <- store_avg_ratings()
  avg_player_rating <- avg_ratings$avg_player_rating[avg_ratings$store_id == store_id]
  if (length(avg_player_rating) == 0) avg_player_rating <- 0

  # Get total unique players
  unique_players_result <- safe_query(db_pool, "
    SELECT COUNT(DISTINCT r.player_id) as cnt
    FROM results r
    JOIN tournaments t ON r.tournament_id = t.tournament_id
    WHERE t.store_id = $1
  ", params = list(store_id), default = data.frame(cnt = 0))
  unique_players <- unique_players_result$cnt

  # Get store schedules
  store_schedules <- safe_query(db_pool, "
    SELECT day_of_week, start_time, frequency, week_of_month, next_occurrence
    FROM store_schedules
    WHERE store_id = $1 AND is_active = TRUE
    ORDER BY day_of_week, start_time
  ", params = list(store_id))

  # Determine if this is an online store

  is_online_store <- !is.null(store$is_online) && !is.na(store$is_online) && store$is_online == TRUE

  # Store coordinates for mini map (used by renderMapboxgl below)
  # For online stores, use region coordinates from geo_utils
  if (is_online_store) {
    region_coords <- get_region_coordinates(store$country, store$city)
    rv$modal_store_coords <- list(
      lat = region_coords$lat,
      lng = region_coords$lng,
      name = store$name,
      is_online = TRUE,
      zoom = 3  # Zoomed out for region view
    )
  } else {
    rv$modal_store_coords <- list(
      lat = store$latitude,
      lng = store$longitude,
      name = store$name,
      is_online = FALSE,
      zoom = 13  # Zoomed in for physical location
    )
  }

  # Build location display for header
  # Online stores: country + region
  # Physical stores: street, city, state zip
  if (is_online_store) {
    location_parts <- c()
    if (!is.na(store$city) && store$city != "") location_parts <- c(location_parts, store$city)
    if (!is.na(store$country) && store$country != "") location_parts <- c(location_parts, store$country)
    address_display <- if (length(location_parts) > 0) paste(location_parts, collapse = ", ") else NULL
  } else {
    address_parts <- c()
    if (!is.na(store$address) && store$address != "") address_parts <- c(address_parts, store$address)
    # City, State ZIP as one unit
    city_state_zip <- c()
    if (!is.na(store$city) && store$city != "") city_state_zip <- c(city_state_zip, store$city)
    if (!is.na(store$state) && store$state != "") city_state_zip <- c(city_state_zip, store$state)
    city_state_part <- paste(city_state_zip, collapse = ", ")
    if (!is.na(store$zip_code) && store$zip_code != "") city_state_part <- paste(city_state_part, store$zip_code)
    if (nchar(city_state_part) > 0) address_parts <- c(address_parts, city_state_part)
    address_display <- if (length(address_parts) > 0) paste(address_parts, collapse = ", ") else NULL
  }
  has_website <- !is.na(store$website) && store$website != ""

  # Update URL for deep linking
  store_slug <- if (!is.null(store$slug) && !is.na(store$slug) && store$slug != "") {
    store$slug
  } else {
    slugify(store$name)  # Fallback to generating from name
  }
  update_url_for_store(session, store_id, store_slug)

  # Build modal content
  showModal(modalDialog(
    title = div(
      class = "d-flex align-items-center gap-2",
      bsicons::bs_icon(if (is_online_store) "globe" else "shop"),
      span(store$name),
      if (!is.null(address_display))
        span(class = "text-muted fw-normal ms-2", style = "font-size: 0.7rem;", address_display),
      if (has_website)
        tags$a(href = store$website, target = "_blank", class = "text-primary ms-1",
               style = "font-size: 0.75rem;", title = "Visit website",
               bsicons::bs_icon("link-45deg"))
    ),
    size = "l",
    easyClose = TRUE,
    footer = tagList(
      tags$button(
        type = "button",
        class = "btn btn-outline-secondary",
        onclick = "copyCurrentUrl()",
        bsicons::bs_icon("link-45deg"), " Copy Link"
      ),
      tags$button(
        type = "button",
        class = "btn btn-outline-primary ms-2",
        onclick = sprintf("copyCommunityUrl('%s')", store_slug),
        bsicons::bs_icon("share"), " Share Community View"
      ),
      modalButton("Close")
    ),

    # Two-column layout: Stats (left) + Mini map (right)
    div(
      class = "row mb-3",
      # Left column: Vertical stats list with box styling
      div(
        class = "col-md-5",
        div(
          class = "modal-stats-box p-3",
          div(
            class = "d-flex justify-content-between py-2 border-bottom",
            span(class = "fw-semibold", "Events"),
            span(store$tournament_count)
          ),
          div(
            class = "d-flex justify-content-between py-2 border-bottom",
            span(class = "fw-semibold", "Avg Event Size"),
            span(if (store$avg_players > 0) store$avg_players else "-")
          ),
          div(
            class = "d-flex justify-content-between py-2 border-bottom",
            span(class = "fw-semibold", "Unique Players"),
            span(unique_players)
          ),
          div(
            class = "d-flex justify-content-between py-2 border-bottom",
            span(class = "fw-semibold", "Avg Player Rating"),
            span(if (avg_player_rating > 0) avg_player_rating else "-")
          ),
          div(
            class = "d-flex justify-content-between py-2",
            span(class = "fw-semibold", "Last Event"),
            span(if (!is.na(store$last_event)) format(as.Date(store$last_event), "%b %d") else "-")
          )
        )
      ),
      # Right column: Mini map (height matched to stats box)
      # For online stores, we use region coordinates; for physical stores, exact location
      div(
        class = "col-md-7",
        if (!is.null(rv$modal_store_coords$lat) && !is.na(rv$modal_store_coords$lat)) {
          div(
            class = "store-mini-map rounded",
            mapboxglOutput("store_modal_map", height = "218px")
          )
        } else {
          div(
            class = "text-muted small p-3 bg-light rounded text-center d-flex align-items-center justify-content-center",
            style = "height: 218px;",
            "Map not available"
          )
        }
      )
    ),

    # Regular Schedule
    if (!is.null(store_schedules) && nrow(store_schedules) > 0) {
      # Format schedules for display
      schedule_rows <- lapply(1:nrow(store_schedules), function(i) {
        sched <- store_schedules[i, ]
        day_name <- WEEKDAY_LABELS[sched$day_of_week + 1]
        # Format time (24h to 12h)
        parts <- strsplit(sched$start_time, ":")[[1]]
        hour <- as.integer(parts[1])
        minute <- parts[2]
        ampm <- if (hour >= 12) "PM" else "AM"
        hour12 <- if (hour == 0) 12 else if (hour > 12) hour - 12 else hour
        time_display <- sprintf("%d:%s %s", hour12, minute, ampm)

        freq_display <- if (sched$frequency == "monthly" && !is.na(sched$week_of_month)) {
          paste0(tools::toTitleCase(sched$week_of_month), " ", day_name, "/mo")
        } else if (sched$frequency == "biweekly" && !is.na(sched$next_occurrence)) {
          paste0("Biweekly (next: ", format(as.Date(sched$next_occurrence), "%b %d"), ")")
        } else {
          tools::toTitleCase(sched$frequency)
        }

        tags$tr(
          tags$td(day_name),
          tags$td(time_display),
          tags$td(freq_display)
        )
      })

      tagList(
        h6(class = "modal-section-header", "Regular Schedule"),
        tags$table(
          class = "table table-sm table-striped mb-3",
          tags$thead(
            tags$tr(
              tags$th("Day"), tags$th("Time"), tags$th("Frequency")
            )
          ),
          tags$tbody(schedule_rows)
        )
      )
    },

    # Recent tournaments
    if (!is.null(recent_tournaments) && nrow(recent_tournaments) > 0) {
      tagList(
        h6(class = "modal-section-header", "Recent Tournaments"),
        tags$table(
          class = "table table-sm table-striped",
          tags$thead(
            tags$tr(
              tags$th("Date"), tags$th("Type"), tags$th("Players"), tags$th("Winner"), tags$th("Deck"), tags$th("")
            )
          ),
          tags$tbody(
            lapply(1:nrow(recent_tournaments), function(i) {
              row <- recent_tournaments[i, ]
              tags$tr(
                tags$td(format(as.Date(row$Date), "%b %d")),
                tags$td(format_event_type(row$Type)),
                tags$td(row$Players),
                tags$td(if (!is.na(row$Winner)) row$Winner else "-"),
                tags$td(if (!is.na(row$Deck)) row$Deck else "-"),
                tags$td(
                  if (!is.na(row$decklist_url) && nchar(row$decklist_url) > 0) {
                    tags$a(
                      href = row$decklist_url,
                      target = "_blank",
                      title = "View decklist",
                      class = "text-primary",
                      bsicons::bs_icon("list-ul")
                    )
                  }
                )
              )
            })
          )
        )
      )
    } else {
      digital_empty_state("No tournaments recorded", "// check back soon", "calendar-x", mascot = "agumon")
    },

    # Top players
    if (!is.null(top_players) && nrow(top_players) > 0) {
      tagList(
        h6(class = "modal-section-header mt-3", "Top Players at This Store"),
        tags$table(
          class = "table table-sm table-striped",
          tags$thead(
            tags$tr(
              tags$th("Player"), tags$th("Events"), tags$th("Wins")
            )
          ),
          tags$tbody(
            lapply(1:nrow(top_players), function(i) {
              row <- top_players[i, ]
              tags$tr(
                tags$td(row$Player),
                tags$td(row$Events),
                tags$td(row$Wins)
              )
            })
          )
        )
      )
    }
  ))
}) |> bindCache(rv$selected_store_id, rv$data_refresh)

# Mini map for store modal
output$store_modal_map <- renderMapboxgl({
  req(rv$modal_store_coords)
  coords <- rv$modal_store_coords

  if (is.null(coords$lat) || is.null(coords$lng) || is.na(coords$lat) || is.na(coords$lng)) {
    return(NULL)
  }

  # Create point for the store
  store_point <- sf::st_sf(
    name = coords$name,
    geometry = sf::st_sfc(sf::st_point(c(coords$lng, coords$lat)), crs = 4326)
  )

  # Use different styling for online vs physical stores
  # Online: green marker, zoomed out for region view
  # Physical: orange marker, zoomed in for precise location
  is_online <- !is.null(coords$is_online) && coords$is_online == TRUE
  marker_color <- if (is_online) "#10B981" else "#F7941D"
  marker_radius <- if (is_online) 14 else 10
  zoom_level <- if (!is.null(coords$zoom)) coords$zoom else 13

  # Build mini map with digital theme
  atom_mapgl(theme = "digital") |>
    mapgl::add_circle_layer(
      id = "store-pin",
      source = store_point,
      circle_color = marker_color,
      circle_radius = marker_radius,
      circle_stroke_color = "#FFFFFF",
      circle_stroke_width = 2,
      circle_opacity = 0.9
    ) |>
    mapgl::set_view(
      center = c(coords$lng, coords$lat),
      zoom = zoom_level
    )
})

# Online Tournament Organizers section
output$online_stores_section <- renderUI({
  req("stores" %in% visited_tabs())  # Lazy load: skip until tab visited

  # Only show online stores section when scene is "all"
  # For regional scenes, we don't show online organizers
  # For "online" scene, the main content area shows online organizers
  scene <- rv$current_scene
  if (is.null(scene) || scene != "all") {
    return(NULL)
  }

  online_stores <- safe_query(db_pool, "
    SELECT s.store_id, s.name, s.city as region, s.website, s.schedule_info,
           COUNT(t.tournament_id) as tournament_count,
           COALESCE(ROUND(AVG(t.player_count), 1), 0) as avg_players,
           MAX(t.event_date) as last_event
    FROM stores s
    LEFT JOIN tournaments t ON s.store_id = t.store_id
    WHERE s.is_online = TRUE AND s.is_active = TRUE
    GROUP BY s.store_id, s.name, s.city, s.website, s.schedule_info
    ORDER BY s.name
  ")

  if (nrow(online_stores) == 0) {
    return(NULL)  # Don't show section if no online stores
  }

  card(
    class = "card-online mt-3",
    card_header(
      class = "d-flex align-items-center gap-2",
      bsicons::bs_icon("globe"),
      span("Online Tournament Organizers"),
      span(class = "small text-muted ms-auto", "Click for details")
    ),
    card_body(
      div(
        class = "row g-3",
        lapply(1:nrow(online_stores), function(i) {
          store <- online_stores[i, ]
          div(
            class = "col-md-4",
            tags$button(
              type = "button",
              class = "online-store-item p-3 h-100 w-100 text-start border-0",
              # Use same handler as physical stores - modal handles both types
              onclick = sprintf("Shiny.setInputValue('store_clicked', %d, {priority: 'event'})", store$store_id),
              h6(class = "mb-1", store$name),
              if (!is.na(store$region) && nchar(store$region) > 0)
                p(class = "text-muted small mb-1", bsicons::bs_icon("geo"), " ", store$region),
              if (!is.na(store$schedule_info) && nchar(store$schedule_info) > 0)
                p(class = "small mb-1", bsicons::bs_icon("calendar"), " ", store$schedule_info),
              if (store$tournament_count > 0)
                p(class = "small mb-0 text-primary",
                  bsicons::bs_icon("trophy"), " ", store$tournament_count, " events")
            )
          )
        })
      )
    )
  )
}) |> bindCache(rv$current_scene, rv$data_refresh)

# Reactive: All stores data with activity metrics (for filtering and map)
stores_data <- reactive({
  req("stores" %in% visited_tabs())  # Lazy load: skip until tab visited
  rv$data_refresh  # Trigger refresh on admin changes

  # Build scene filter for stores table
  scene <- rv$current_scene
  scene_sql <- ""
  scene_params <- list()
  if (!is.null(scene) && scene != "" && scene != "all") {
    if (scene == "online") {
      scene_sql <- "AND s.is_online = TRUE"
    } else {
      scene_sql <- "AND s.scene_id = (SELECT scene_id FROM scenes WHERE slug = $1)"
      scene_params <- list(scene)
    }
  }

  # For non-online scenes, exclude online stores by default
  base_online_filter <- if (is.null(scene) || scene == "" || scene == "all") {
    "AND (s.is_online = FALSE OR s.is_online IS NULL)"
  } else if (scene == "online") {
    ""  # Scene filter already handles is_online = TRUE
  } else {
    "AND (s.is_online = FALSE OR s.is_online IS NULL)"
  }

  query <- sprintf("
    SELECT s.store_id, s.name, s.address, s.city, s.state, s.zip_code,
           s.latitude, s.longitude, s.website, s.schedule_info, s.slug,
           s.country, s.is_online,
           COUNT(t.tournament_id) as tournament_count,
           COALESCE(ROUND(AVG(t.player_count), 1), 0) as avg_players,
           MAX(t.event_date) as last_event
    FROM stores s
    LEFT JOIN tournaments t ON s.store_id = t.store_id
    WHERE s.is_active = TRUE
      %s
      %s
    GROUP BY s.store_id, s.name, s.address, s.city, s.state, s.zip_code,
             s.latitude, s.longitude, s.website, s.schedule_info, s.slug,
             s.country, s.is_online
  ", base_online_filter, scene_sql)

  safe_query(db_pool, query, params = scene_params)
})

# Reset dashboard filters (reset to defaults: all formats + locals)
# Note: This should ideally be in Dashboard server, kept here due to physical proximity
observeEvent(input$reset_dashboard_filters, {
  updateSelectInput(session, "dashboard_format", selected = "")
  updateSelectInput(session, "dashboard_event_type", selected = "locals")
  notify("Filters reset to defaults", type = "message")
})

# Helper: Render world map for online organizers
render_online_organizers_map <- function() {
  # Query online stores with country
  online_stores <- safe_query(db_pool, "
    SELECT s.store_id, s.name, s.city as region, s.country, s.website,
           COUNT(t.tournament_id) as tournament_count,
           COALESCE(ROUND(AVG(t.player_count), 1), 0) as avg_players
    FROM stores s
    LEFT JOIN tournaments t ON s.store_id = t.store_id
    WHERE s.is_online = TRUE AND s.is_active = TRUE
    GROUP BY s.store_id, s.name, s.city, s.country, s.website
  ")

  if (nrow(online_stores) == 0) {
    # Empty world map
    return(
      atom_mapgl(theme = "digital", projection = "mercator") |>
        mapgl::set_view(center = c(-40, 20), zoom = 1.5)
    )
  }

  # Add coordinates based on country/region
  online_stores$lat <- NA_real_
  online_stores$lng <- NA_real_

  for (i in 1:nrow(online_stores)) {
    coords <- get_region_coordinates(
      online_stores$country[i],
      online_stores$region[i]
    )
    if (!is.null(coords)) {
      online_stores$lat[i] <- coords$lat
      online_stores$lng[i] <- coords$lng
    }
  }

  # Filter to stores with coordinates
  stores_with_coords <- online_stores[!is.na(online_stores$lat), ]

  if (nrow(stores_with_coords) == 0) {
    return(
      atom_mapgl(theme = "digital", projection = "mercator") |>
        mapgl::set_view(center = c(-40, 20), zoom = 1.5)
    )
  }

  # Group stores that share the same coordinates into combined markers
  stores_with_coords$coord_key <- paste(stores_with_coords$lat, stores_with_coords$lng)
  grouped <- split(stores_with_coords, stores_with_coords$coord_key)

  grouped_rows <- lapply(grouped, function(grp) {
    data.frame(
      lat = grp$lat[1],
      lng = grp$lng[1],
      tournament_count = sum(grp$tournament_count, na.rm = TRUE),
      store_count = nrow(grp),
      stringsAsFactors = FALSE
    )
  })
  grouped_df <- do.call(rbind, grouped_rows)

  # Convert to sf
  stores_sf <- st_as_sf(grouped_df, coords = c("lng", "lat"), crs = 4326)

  # Bubble size based on total event count at location
  stores_sf$bubble_size <- sapply(grouped_df$tournament_count, function(cnt) {
    if (is.na(cnt) || cnt == 0) return(8)
    if (cnt < 10) return(12)
    if (cnt < 50) return(16)
    if (cnt < 100) return(20)
    return(24)
  })

  # Popup content — combined for stores sharing a location
  stores_sf$popup <- sapply(names(grouped), function(key) {
    grp <- grouped[[key]]
    if (nrow(grp) == 1) {
      # Single store — original popup
      store <- grp[1, ]
      metrics <- c()
      if (!is.na(store$country)) metrics <- c(metrics, "Country" = store$country)
      if (!is.na(store$region) && store$region != "") metrics <- c(metrics, "Region" = store$region)
      if (store$tournament_count > 0) {
        metrics <- c(metrics, "Events" = as.character(store$tournament_count))
        metrics <- c(metrics, "Avg Players" = as.character(store$avg_players))
      }
      atom_popup_html_metrics(
        title = store$name,
        subtitle = "Online Organizer",
        metrics = if (length(metrics) > 0) metrics else NULL,
        theme = "light"
      )
    } else {
      # Multiple stores at same location — combined popup
      store_sections <- sapply(1:nrow(grp), function(j) {
        store <- grp[j, ]
        details <- c()
        if (store$tournament_count > 0) {
          details <- c(details, sprintf("%d events", as.integer(store$tournament_count)))
          details <- c(details, sprintf("%.1f avg players", store$avg_players))
        }
        detail_str <- if (length(details) > 0) paste(details, collapse = " &middot; ") else "No events yet"
        sprintf(
          '<div style="padding:4px 0;%s">
            <div style="font-weight:600;font-size:13px;">%s</div>
            <div style="font-size:11px;opacity:0.7;">%s</div>
          </div>',
          if (j < nrow(grp)) "border-bottom:1px solid rgba(0,0,0,0.08);" else "",
          htmltools::htmlEscape(store$name),
          detail_str
        )
      })
      country_label <- if (!is.na(grp$country[1])) grp$country[1] else ""
      sprintf(
        '<div style="text-align:center;padding:10px 14px;min-width:180px;font-family:system-ui,-apple-system,sans-serif;">
          <div style="font-size:11px;text-transform:uppercase;letter-spacing:0.5px;opacity:0.5;margin-bottom:4px;">%s</div>
          <div style="font-size:14px;font-weight:700;margin-bottom:8px;">%d Online Organizers</div>
          <div style="text-align:left;">%s</div>
        </div>',
        htmltools::htmlEscape(country_label),
        nrow(grp),
        paste(store_sections, collapse = "")
      )
    }
  })

  # Create world map
  atom_mapgl(theme = "digital", projection = "mercator") |>
    add_atom_popup_style(theme = "light") |>
    mapgl::add_circle_layer(
      id = "online-stores-layer",
      source = stores_sf,
      circle_color = "#10B981",
      circle_radius = list("get", "bubble_size"),
      circle_stroke_color = "#FFFFFF",
      circle_stroke_width = 2,
      circle_opacity = 0.85,
      popup = "popup"
    ) |>
    mapgl::set_view(center = c(-40, 20), zoom = 1.5)
}

# Helper: Render combined world map for All Scenes (physical + online)
render_all_scenes_map <- function(physical_stores) {
  # Query online organizers (same query as render_online_organizers_map)
  online_stores <- safe_query(db_pool, "
    SELECT s.store_id, s.name, s.city as region, s.country, s.website,
           COUNT(t.tournament_id) as tournament_count,
           COALESCE(ROUND(AVG(t.player_count), 1), 0) as avg_players
    FROM stores s
    LEFT JOIN tournaments t ON s.store_id = t.store_id
    WHERE s.is_online = TRUE AND s.is_active = TRUE
    GROUP BY s.store_id, s.name, s.city, s.country, s.website
  ")

  # Create base flat world map
  map <- atom_mapgl(theme = "digital", projection = "mercator") |>
    add_atom_popup_style(theme = "light")

  # --- Physical store markers (orange) ---
  if (!is.null(physical_stores) && nrow(physical_stores) > 0) {
    phys_with_coords <- physical_stores[!is.na(physical_stores$latitude) & !is.na(physical_stores$longitude), ]

    if (nrow(phys_with_coords) > 0) {
      phys_sf <- st_as_sf(phys_with_coords, coords = c("longitude", "latitude"), crs = 4326)

      phys_sf$bubble_size <- sapply(phys_with_coords$avg_players, function(avg) {
        if (is.na(avg) || avg == 0) return(5)
        if (avg < 8) return(10)
        if (avg <= 12) return(14)
        if (avg <= 18) return(18)
        if (avg <= 24) return(22)
        return(26)
      })

      phys_sf$popup <- sapply(1:nrow(phys_sf), function(i) {
        store <- phys_with_coords[i, ]
        metrics <- c()
        if (!is.null(store$city) && !is.na(store$city)) {
          metrics <- c(metrics, "City" = store$city)
        }
        if (!is.na(store$tournament_count) && store$tournament_count > 0) {
          metrics <- c(metrics, "Events" = as.character(store$tournament_count))
          metrics <- c(metrics, "Avg Players" = as.character(store$avg_players))
        }
        body_parts <- c()
        if (!is.null(store$address) && !is.na(store$address) && store$address != "") {
          body_parts <- c(body_parts, store$address)
        }
        schedule_text <- parse_schedule_info(store$schedule_info)
        if (!is.null(schedule_text)) {
          body_parts <- c(body_parts, paste("<br><em>", schedule_text, "</em>"))
        }
        if (!is.na(store$last_event)) {
          days_ago <- as.integer(Sys.Date() - as.Date(store$last_event))
          last_event_text <- if (days_ago == 0) "Today" else if (days_ago == 1) "Yesterday" else paste(days_ago, "days ago")
          body_parts <- c(body_parts, paste("<br><small>Last event:", last_event_text, "</small>"))
        }
        body_text <- if (length(body_parts) > 0) paste(body_parts, collapse = "") else NULL
        atom_popup_html_metrics(
          title = store$name,
          subtitle = if (store$tournament_count > 0) "Active Game Store" else "Game Store",
          metrics = if (length(metrics) > 0) metrics else NULL,
          body = body_text,
          theme = "light"
        )
      })

      map <- map |>
        mapgl::add_circle_layer(
          id = "physical-stores-layer",
          source = phys_sf,
          circle_color = "#F7941D",
          circle_radius = list("get", "bubble_size"),
          circle_stroke_color = "#FFFFFF",
          circle_stroke_width = 2,
          circle_opacity = 0.85,
          popup = "popup"
        )
    }
  }

  # --- Online organizer markers (green) ---
  if (nrow(online_stores) > 0) {
    online_stores$lat <- NA_real_
    online_stores$lng <- NA_real_
    for (i in 1:nrow(online_stores)) {
      coords <- get_region_coordinates(online_stores$country[i], online_stores$region[i])
      if (!is.null(coords)) {
        online_stores$lat[i] <- coords$lat
        online_stores$lng[i] <- coords$lng
      }
    }

    stores_with_coords <- online_stores[!is.na(online_stores$lat), ]

    if (nrow(stores_with_coords) > 0) {
      stores_with_coords$coord_key <- paste(stores_with_coords$lat, stores_with_coords$lng)
      grouped <- split(stores_with_coords, stores_with_coords$coord_key)

      grouped_rows <- lapply(grouped, function(grp) {
        data.frame(
          lat = grp$lat[1],
          lng = grp$lng[1],
          tournament_count = sum(grp$tournament_count, na.rm = TRUE),
          store_count = nrow(grp),
          stringsAsFactors = FALSE
        )
      })
      grouped_df <- do.call(rbind, grouped_rows)

      online_sf <- st_as_sf(grouped_df, coords = c("lng", "lat"), crs = 4326)

      online_sf$bubble_size <- sapply(grouped_df$tournament_count, function(cnt) {
        if (is.na(cnt) || cnt == 0) return(8)
        if (cnt < 10) return(12)
        if (cnt < 50) return(16)
        if (cnt < 100) return(20)
        return(24)
      })

      online_sf$popup <- sapply(names(grouped), function(key) {
        grp <- grouped[[key]]
        if (nrow(grp) == 1) {
          store <- grp[1, ]
          metrics <- c()
          if (!is.na(store$country)) metrics <- c(metrics, "Country" = store$country)
          if (!is.na(store$region) && store$region != "") metrics <- c(metrics, "Region" = store$region)
          if (store$tournament_count > 0) {
            metrics <- c(metrics, "Events" = as.character(store$tournament_count))
            metrics <- c(metrics, "Avg Players" = as.character(store$avg_players))
          }
          atom_popup_html_metrics(
            title = store$name,
            subtitle = "Online Organizer",
            metrics = if (length(metrics) > 0) metrics else NULL,
            theme = "light"
          )
        } else {
          store_sections <- sapply(1:nrow(grp), function(j) {
            store <- grp[j, ]
            details <- c()
            if (store$tournament_count > 0) {
              details <- c(details, sprintf("%d events", as.integer(store$tournament_count)))
              details <- c(details, sprintf("%.1f avg players", store$avg_players))
            }
            detail_str <- if (length(details) > 0) paste(details, collapse = " &middot; ") else "No events yet"
            sprintf(
              '<div style="padding:4px 0;%s">
                <div style="font-weight:600;font-size:13px;">%s</div>
                <div style="font-size:11px;opacity:0.7;">%s</div>
              </div>',
              if (j < nrow(grp)) "border-bottom:1px solid rgba(0,0,0,0.08);" else "",
              htmltools::htmlEscape(store$name),
              detail_str
            )
          })
          country_label <- if (!is.na(grp$country[1])) grp$country[1] else ""
          sprintf(
            '<div style="text-align:center;padding:10px 14px;min-width:180px;font-family:system-ui,-apple-system,sans-serif;">
              <div style="font-size:11px;text-transform:uppercase;letter-spacing:0.5px;opacity:0.5;margin-bottom:4px;">%s</div>
              <div style="font-size:14px;font-weight:700;margin-bottom:8px;">%d Online Organizers</div>
              <div style="text-align:left;">%s</div>
            </div>',
            htmltools::htmlEscape(country_label),
            nrow(grp),
            paste(store_sections, collapse = "")
          )
        }
      })

      map <- map |>
        mapgl::add_circle_layer(
          id = "online-stores-layer",
          source = online_sf,
          circle_color = "#10B981",
          circle_radius = list("get", "bubble_size"),
          circle_stroke_color = "#FFFFFF",
          circle_stroke_width = 2,
          circle_opacity = 0.85,
          popup = "popup"
        )
    }
  }

  map |> mapgl::set_view(center = c(-40, 10), zoom = 1.2)
}

# Stores Map
output$stores_map <- renderMapboxgl({
  scene <- rv$current_scene

  # For Online scene, show world map with online organizers
  if (!is.null(scene) && scene == "online") {
    return(render_online_organizers_map())
  }

  # For All Scenes, show combined world map with physical + online markers
  if (is.null(scene) || scene == "" || scene == "all") {
    return(render_all_scenes_map(stores_data()))
  }

  # For other scenes, show regional map with physical stores
  stores <- stores_data()

  # Use minimal theme for map (works in both light/dark app modes)
  # Popup always uses light theme for readability

  # Default DFW center if no stores or no valid coordinates
  if (is.null(stores) || nrow(stores) == 0) {
    return(
      atom_mapgl(theme = "digital") |>
        mapgl::set_view(center = c(-96.8, 32.8), zoom = 9) |>
        add_atom_popup_style(theme = "light")
    )
  }

  # Filter to stores with coordinates
  stores_with_coords <- stores[!is.na(stores$latitude) & !is.na(stores$longitude), ]

  if (nrow(stores_with_coords) == 0) {
    return(
      atom_mapgl(theme = "digital") |>
        mapgl::set_view(center = c(-96.8, 32.8), zoom = 9) |>
        add_atom_popup_style(theme = "light")
    )
  }

  # Convert to sf object
  stores_sf <- st_as_sf(stores_with_coords, coords = c("longitude", "latitude"), crs = 4326)

  # Calculate bubble size based on average event size (tiered)
  # No events: 5px, <8: 10px, 8-12: 14px, 13-18: 18px, 19-24: 22px, 25+: 26px
  stores_sf$bubble_size <- sapply(stores_with_coords$avg_players, function(avg) {
    if (is.na(avg) || avg == 0) return(5)      # No events
    if (avg < 8) return(10)                     # Small/casual
    if (avg <= 12) return(14)                   # Typical locals
    if (avg <= 18) return(18)                   # Active locals
    if (avg <= 24) return(22)                   # Popular store
    return(26)                                  # Major events (25+)
  })

  # Create popup content with activity metrics
  stores_sf$popup <- sapply(1:nrow(stores_sf), function(i) {
    store <- stores_with_coords[i, ]

    # Build metrics list
    metrics <- c()
    if (!is.null(store$city) && !is.na(store$city)) {
      metrics <- c(metrics, "City" = store$city)
    }
    if (!is.na(store$tournament_count) && store$tournament_count > 0) {
      metrics <- c(metrics, "Events" = as.character(store$tournament_count))
      metrics <- c(metrics, "Avg Players" = as.character(store$avg_players))
    }

    body_parts <- c()
    if (!is.null(store$address) && !is.na(store$address) && store$address != "") {
      body_parts <- c(body_parts, store$address)
    }
    schedule_text <- parse_schedule_info(store$schedule_info)
    if (!is.null(schedule_text)) {
      body_parts <- c(body_parts, paste("<br><em>", schedule_text, "</em>"))
    }
    if (!is.na(store$last_event)) {
      days_ago <- as.integer(Sys.Date() - as.Date(store$last_event))
      last_event_text <- if (days_ago == 0) "Today" else if (days_ago == 1) "Yesterday" else paste(days_ago, "days ago")
      body_parts <- c(body_parts, paste("<br><small>Last event:", last_event_text, "</small>"))
    }
    body_text <- if (length(body_parts) > 0) paste(body_parts, collapse = "") else NULL

    atom_popup_html_metrics(
      title = store$name,
      subtitle = if (store$tournament_count > 0) "Active Game Store" else "Game Store",
      metrics = if (length(metrics) > 0) metrics else NULL,
      body = body_text,
      theme = "light"
    )
  })

  # Build bounding box sf that includes stores + scene center
  bounds_sf <- stores_sf
  scene_coords <- safe_query(db_pool,
    "SELECT latitude, longitude FROM scenes WHERE slug = $1 AND latitude IS NOT NULL",
    params = list(scene), default = data.frame())
  if (nrow(scene_coords) > 0) {
    scene_point <- st_sf(
      geometry = st_sfc(st_point(c(scene_coords$longitude[1], scene_coords$latitude[1])), crs = 4326)
    )
    bounds_sf <- rbind(bounds_sf[, "geometry"], scene_point)
  }

  # Create the map
  # Using digital theme for basemap, light theme for popups
  # Bubble size based on average event size
  map <- atom_mapgl(theme = "digital") |>
    add_atom_popup_style(theme = "light") |>
    mapgl::add_circle_layer(
      id = "stores-layer",
      source = stores_sf,
      circle_color = "#F7941D",
      circle_radius = list("get", "bubble_size"),
      circle_stroke_color = "#FFFFFF",
      circle_stroke_width = 2,
      circle_opacity = 0.85,
      popup = "popup"
    ) |>
    mapgl::fit_bounds(bounds_sf, padding = 50, maxZoom = 9)

  map
}) |> bindCache(rv$current_scene, rv$community_filter, input$dark_mode, rv$data_refresh)

# =============================================================================
# Mobile Stores Map (compact 200px)
# =============================================================================
output$mobile_stores_map <- renderMapboxgl({
  req(is_mobile())

  scene <- rv$current_scene

  # For Online scene, show world map with online organizers
  if (!is.null(scene) && scene == "online") {
    return(render_online_organizers_map())
  }

  # For All Scenes, show combined world map with physical + online markers
  if (is.null(scene) || scene == "" || scene == "all") {
    return(render_all_scenes_map(stores_data()))
  }

  # For other scenes, show regional map with physical stores
  stores <- stores_data()

  # Default DFW center if no stores or no valid coordinates
  if (is.null(stores) || nrow(stores) == 0) {
    return(
      atom_mapgl(theme = "digital") |>
        mapgl::set_view(center = c(-96.8, 32.8), zoom = 9)
    )
  }

  # Filter to stores with coordinates
  stores_with_coords <- stores[!is.na(stores$latitude) & !is.na(stores$longitude), ]

  if (nrow(stores_with_coords) == 0) {
    return(
      atom_mapgl(theme = "digital") |>
        mapgl::set_view(center = c(-96.8, 32.8), zoom = 9)
    )
  }

  # Convert to sf object
  stores_sf <- st_as_sf(stores_with_coords, coords = c("longitude", "latitude"), crs = 4326)

  # Bubble size based on average event size (same tiers as desktop)
  stores_sf$bubble_size <- sapply(stores_with_coords$avg_players, function(avg) {
    if (is.na(avg) || avg == 0) return(5)
    if (avg < 8) return(8)
    if (avg <= 12) return(10)
    if (avg <= 18) return(13)
    if (avg <= 24) return(16)
    return(18)
  })

  # Minimal popup for mobile (just store name + city)
  stores_sf$popup <- sapply(1:nrow(stores_sf), function(i) {
    store <- stores_with_coords[i, ]
    city_text <- if (!is.null(store$city) && !is.na(store$city)) store$city else ""
    sprintf(
      '<div style="text-align:center;padding:4px 8px;font-family:system-ui,sans-serif;">
        <div style="font-weight:600;font-size:13px;">%s</div>
        <div style="font-size:11px;opacity:0.7;">%s</div>
      </div>',
      htmltools::htmlEscape(store$name),
      htmltools::htmlEscape(city_text)
    )
  })

  # Build bounding box sf that includes stores + scene center
  bounds_sf <- stores_sf
  scene_coords <- safe_query(db_pool,
    "SELECT latitude, longitude FROM scenes WHERE slug = $1 AND latitude IS NOT NULL",
    params = list(scene), default = data.frame())
  if (nrow(scene_coords) > 0) {
    scene_point <- st_sf(
      geometry = st_sfc(st_point(c(scene_coords$longitude[1], scene_coords$latitude[1])), crs = 4326)
    )
    bounds_sf <- rbind(bounds_sf[, "geometry"], scene_point)
  }


  # Create the map (no popup theme helper needed for compact view)
  atom_mapgl(theme = "digital") |>
    mapgl::add_circle_layer(
      id = "stores-layer",
      source = stores_sf,
      circle_color = "#F7941D",
      circle_radius = list("get", "bubble_size"),
      circle_stroke_color = "#FFFFFF",
      circle_stroke_width = 1.5,
      circle_opacity = 0.85,
      popup = "popup"
    ) |>
    mapgl::fit_bounds(bounds_sf, padding = 30, maxZoom = 9)
}) |> bindCache(rv$current_scene, rv$community_filter, input$dark_mode, rv$data_refresh)

# =============================================================================
# Mobile Store Cards
# =============================================================================

# Pagination limit for mobile store cards
mobile_stores_limit <- reactiveVal(20)

# Reset limit when scene changes
observeEvent(rv$current_scene, {
  mobile_stores_limit(20)
}, ignoreInit = TRUE)

# Load more button
observeEvent(input$load_more_mobile_stores, {
  mobile_stores_limit(mobile_stores_limit() + 20)
})

output$mobile_stores_cards <- renderUI({
  req(is_mobile())
  rv$data_refresh

  scene <- rv$current_scene

  # For online scene, show online organizer cards
  if (!is.null(scene) && scene == "online") {
    online_stores <- safe_query(db_pool, "
      SELECT s.store_id, s.name, s.city as region, s.country, s.website,
             COUNT(t.tournament_id) as tournament_count,
             COALESCE(ROUND(AVG(t.player_count), 1), 0) as avg_players,
             MAX(t.event_date) as last_event
      FROM stores s
      LEFT JOIN tournaments t ON s.store_id = t.store_id
      WHERE s.is_online = TRUE AND s.is_active = TRUE
      GROUP BY s.store_id, s.name, s.city, s.country, s.website
      ORDER BY s.name
    ")

    if (nrow(online_stores) == 0) {
      return(digital_empty_state("No online organizers", "// check back soon", "globe", mascot = "agumon"))
    }

    total_rows <- nrow(online_stores)
    show_n <- min(mobile_stores_limit(), total_rows)
    online_stores <- online_stores[seq_len(show_n), , drop = FALSE]

    cards <- lapply(seq_len(nrow(online_stores)), function(i) {
      store <- online_stores[i, ]

      # Location line
      location_parts <- c()
      if (!is.na(store$region) && nchar(store$region) > 0) location_parts <- c(location_parts, store$region)
      if (!is.na(store$country) && nchar(store$country) > 0) location_parts <- c(location_parts, store$country)
      location_line <- paste(location_parts, collapse = ", ")

      # Stats line
      stats_line <- if (store$tournament_count > 0) {
        paste0(store$tournament_count, " events")
      } else {
        "No events yet"
      }

      # Events badge
      events_badge <- if (store$tournament_count > 0) {
        span(class = "mobile-card-format-badge",
          sprintf("%d events", store$tournament_count))
      }

      div(
        class = "mobile-list-card",
        onclick = sprintf("Shiny.setInputValue('store_clicked', %d, {priority: 'event'})", store$store_id),
        # Row 1: Name + Events badge
        div(class = "mobile-card-row",
          span(class = "mobile-card-primary", store$name),
          events_badge
        ),
        # Row 2: Location
        if (nchar(location_line) > 0) {
          div(class = "mobile-card-row",
            span(class = "mobile-card-meta-stats",
              bsicons::bs_icon("globe", class = "me-1"),
              location_line)
          )
        }
      )
    })

    card_list <- div(class = "mobile-card-list", cards)

    if (show_n < total_rows) {
      remaining <- total_rows - show_n
      return(tagList(
        card_list,
        tags$button(
          class = "mobile-load-more",
          onclick = "Shiny.setInputValue('load_more_mobile_stores', Math.random(), {priority: 'event'})",
          span(class = "mobile-load-more-label", "LOAD MORE"),
          span(class = "mobile-load-more-count", sprintf("%d remaining", remaining))
        )
      ))
    }
    return(card_list)
  }

  # For "All Scenes", show scene summary cards (mobile version)
  if (is.null(scene) || scene == "" || scene == "all") {
    scene_stats <- safe_query(db_pool, "
      SELECT sc.slug, sc.display_name, sc.name as scene_name,
             COUNT(DISTINCT s.store_id) as store_count,
             COUNT(t.tournament_id) as total_events,
             COALESCE(ROUND(AVG(t.player_count), 1), 0) as avg_players
      FROM scenes sc
      JOIN stores s ON s.scene_id = sc.scene_id
        AND s.is_active = TRUE
        AND (s.is_online = FALSE OR s.is_online IS NULL)
      LEFT JOIN tournaments t ON s.store_id = t.store_id
      WHERE sc.is_active = TRUE
        AND sc.scene_type = 'metro'
      GROUP BY sc.scene_id, sc.slug, sc.display_name, sc.name
      ORDER BY COUNT(t.tournament_id) DESC
    ")

    if (nrow(scene_stats) == 0) {
      return(digital_empty_state("No scenes available", "// check back soon", "geo-alt", mascot = "agumon"))
    }

    cards <- lapply(seq_len(nrow(scene_stats)), function(i) {
      sc <- scene_stats[i, ]
      scene_label <- if (!is.na(sc$display_name) && nchar(sc$display_name) > 0) sc$display_name else sc$scene_name
      stores_label <- if (sc$store_count == 1) "store" else "stores"

      div(
        class = "mobile-list-card",
        style = "border-left: 3px solid #0F4C81;",
        onclick = sprintf("Shiny.setInputValue('scene_card_clicked', '%s', {priority: 'event'})", sc$slug),
        div(class = "mobile-card-row",
          span(class = "mobile-card-primary",
            bsicons::bs_icon("geo-alt-fill", class = "me-1"),
            scene_label),
          span(class = "mobile-card-format-badge",
            sprintf("%d %s", sc$store_count, stores_label))
        ),
        div(class = "mobile-card-row",
          span(class = "mobile-card-meta-stats",
            sprintf("%d events", sc$total_events)),
          if (sc$avg_players > 0) {
            span(class = "mobile-card-meta-stats",
              sprintf("~%s avg players", sc$avg_players))
          }
        )
      )
    })

    return(div(class = "mobile-card-list", cards))
  }

  # For physical scenes, show physical store cards
  stores <- stores_data()

  if (is.null(stores) || nrow(stores) == 0) {
    return(digital_empty_state("No stores found", "// check back soon", "shop", mascot = "agumon"))
  }

  # Get store schedules for all stores in one query
  store_ids <- stores$store_id
  if (length(store_ids) > 0) {
    placeholders <- paste0("$", seq_along(store_ids), collapse = ", ")
    schedules_query <- sprintf("
      SELECT store_id, day_of_week, start_time, frequency, week_of_month, next_occurrence
      FROM store_schedules
      WHERE store_id IN (%s) AND is_active = TRUE
      ORDER BY store_id, day_of_week, start_time
    ", placeholders)
    all_schedules <- safe_query(db_pool, schedules_query,
                                params = as.list(store_ids),
                                default = data.frame())
  } else {
    all_schedules <- data.frame()
  }

  # Get average ratings
  avg_ratings <- store_avg_ratings()

  # Sort stores: most events first, then by name
  stores <- stores[order(-stores$tournament_count, stores$name), ]

  total_rows <- nrow(stores)
  show_n <- min(mobile_stores_limit(), total_rows)
  stores_page <- stores[seq_len(show_n), , drop = FALSE]

  day_abbrevs <- c("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")

  cards <- lapply(seq_len(nrow(stores_page)), function(i) {
    store <- stores_page[i, ]

    # Build schedule line from store_schedules table
    store_scheds <- if (nrow(all_schedules) > 0) {
      all_schedules[all_schedules$store_id == store$store_id, , drop = FALSE]
    } else {
      data.frame()
    }

    schedule_line <- NULL
    if (nrow(store_scheds) > 0) {
      sched_parts <- sapply(seq_len(nrow(store_scheds)), function(j) {
        sched <- store_scheds[j, ]
        day_name <- day_abbrevs[sched$day_of_week + 1]
        # Format time (24h to 12h)
        time_parts <- strsplit(sched$start_time, ":")[[1]]
        hour <- as.integer(time_parts[1])
        ampm <- if (hour >= 12) "pm" else "am"
        hour12 <- if (hour == 0) 12 else if (hour > 12) hour - 12 else hour
        freq_label <- if (!is.null(sched$frequency) && !is.na(sched$frequency) && sched$frequency == "monthly" && !is.na(sched$week_of_month)) {
          paste0(" (", sched$week_of_month, "/mo)")
        } else if (!is.null(sched$frequency) && !is.na(sched$frequency) && sched$frequency == "biweekly") {
          " (biweekly)"
        } else if (!is.null(sched$frequency) && !is.na(sched$frequency) && sched$frequency != "weekly") {
          paste0(" (", sched$frequency, ")")
        } else {
          ""
        }
        sprintf("%s %d%s%s", day_name, hour12, ampm, freq_label)
      })
      schedule_line <- paste(sched_parts, collapse = " \u00b7 ")
    } else if (!is.na(store$schedule_info) && nchar(store$schedule_info) > 0) {
      # Fallback to legacy schedule_info JSON
      schedule_line <- parse_schedule_info(store$schedule_info)
    }

    # Location line
    location_parts <- c()
    if (!is.na(store$city) && nchar(store$city) > 0) location_parts <- c(location_parts, store$city)
    if (!is.na(store$state) && nchar(store$state) > 0) location_parts <- c(location_parts, store$state)
    location_line <- paste(location_parts, collapse = ", ")

    # Stats line
    stats_parts <- c()
    if (!is.na(store$tournament_count) && store$tournament_count > 0) {
      stats_parts <- c(stats_parts, paste0(store$tournament_count, " events"))
    }
    # Add store rating if available
    store_rating <- avg_ratings$avg_player_rating[avg_ratings$store_id == store$store_id]
    if (length(store_rating) > 0 && !is.na(store_rating) && store_rating > 0) {
      stats_parts <- c(stats_parts, paste0("\u2605 ", round(store_rating)))
    }
    stats_line <- if (length(stats_parts) > 0) {
      paste(stats_parts, collapse = " \u00b7 ")
    } else {
      "No events yet"
    }

    # Events badge
    events_badge <- if (!is.na(store$tournament_count) && store$tournament_count > 0) {
      span(class = "mobile-card-format-badge",
        sprintf("%d events", store$tournament_count))
    }

    # Rating display
    store_rating <- avg_ratings$avg_player_rating[avg_ratings$store_id == store$store_id]
    rating_tag <- if (length(store_rating) > 0 && !is.na(store_rating) && store_rating > 0) {
      sprintf("\u2605 %d", round(store_rating))
    }

    div(
      class = "mobile-list-card",
      onclick = sprintf("Shiny.setInputValue('store_clicked', %d, {priority: 'event'})", store$store_id),
      # Row 1: Store name + Events badge
      div(class = "mobile-card-row",
        span(class = "mobile-card-primary", store$name),
        events_badge
      ),
      # Row 2: Schedule/Location (left) | Rating (right)
      div(class = "mobile-card-row",
        span(class = "mobile-card-meta-stats",
          if (!is.null(schedule_line)) {
            tagList(schedule_line)
          } else if (nchar(location_line) > 0) {
            tagList(location_line)
          } else {
            "No schedule yet"
          }
        ),
        if (!is.null(rating_tag)) {
          span(class = "mobile-card-meta-stats", rating_tag)
        }
      )
    )
  })


  card_list <- div(class = "mobile-card-list", cards)

  if (show_n < total_rows) {
    remaining <- total_rows - show_n
    tagList(
      card_list,
      tags$button(
        class = "mobile-load-more",
        onclick = "Shiny.setInputValue('load_more_mobile_stores', Math.random(), {priority: 'event'})",
        span(class = "mobile-load-more-label", "LOAD MORE"),
        span(class = "mobile-load-more-count", sprintf("%d remaining", remaining))
      )
    )
  } else {
    card_list
  }
})

# =============================================================================
# Store Request Modal
# =============================================================================

# Open store request modal
observeEvent(input$open_store_request, {
  show_store_request_modal()
})

# Handle store request submission
observeEvent(input$submit_store_request, {
  store_name <- trimws(input$store_req_name)
  city <- trimws(input$store_req_city)
  state <- trimws(input$store_req_state)
  scene_val <- input$store_req_scene
  discord_username <- trimws(input$store_req_discord)

  if (nchar(store_name) == 0) {
    notify("Store name is required", type = "warning")
    return()
  }
  if (nchar(city) == 0) {
    notify("City is required", type = "warning")
    return()
  }
  if (nchar(state) == 0) {
    notify("State / Country is required", type = "warning")
    return()
  }
  if (is.null(scene_val) || nchar(scene_val) == 0) {
    notify("Please select a scene", type = "warning")
    return()
  }
  if (nchar(discord_username) == 0) {
    notify("Discord username is required so we can follow up", type = "warning")
    return()
  }

  # Fuzzy match check
  scene_id <- as.integer(scene_val)
  similar <- find_similar_stores(db_pool, store_name, scene_id)

  if (nrow(similar) > 0) {
    # Stash form values for confirm handler
    rv$pending_store_request <- list(
      store_name = store_name, city = city, state = state,
      scene_id = as.character(scene_id), discord_username = discord_username
    )

    matches_ui <- div(class = "fuzzy-match-list",
      lapply(seq_len(nrow(similar)), function(i) {
        div(class = "fuzzy-match-item d-flex justify-content-between align-items-center p-2 mb-1 rounded",
          span(tags$strong(similar$name[i]),
               if (!is.na(similar$city[i]) && nchar(similar$city[i]) > 0)
                 span(class = "text-muted ms-2", similar$city[i])),
          span(class = "badge bg-warning text-dark",
               paste0(round(similar$sim[i] * 100), "% match"))
        )
      })
    )

    show_fuzzy_match_modal(matches_ui, "submit_store_request", "Similar Stores Found", "shop")
    return()
  }

  submit_store_request_final(store_name, city, state, scene_id, discord_username)
})

# Fuzzy match: go back to edit (restore form values)
observeEvent(input$submit_store_request_cancel_fuzzy, {
  prefill <- rv$pending_store_request
  rv$pending_store_request <- NULL
  removeModal()
  show_store_request_modal(prefill = prefill)
})

# Fuzzy match: confirm submit anyway
observeEvent(input$submit_store_request_confirm_fuzzy, {
  req(rv$pending_store_request)
  p <- rv$pending_store_request
  rv$pending_store_request <- NULL
  submit_store_request_final(p$store_name, p$city, p$state, p$scene_id, p$discord_username)
})

# Extracted submission logic
submit_store_request_final <- function(store_name, city, state, scene_id, discord_username) {
  tryCatch({
    location <- paste(city, state, sep = ", ")

    payload <- list(
      store_name = store_name,
      city = city,
      state = state,
      request_subtype = "new_store"
    )
    safe_execute(db_pool, "
      INSERT INTO admin_requests (request_type, scene_id, payload, discord_username)
      VALUES ($1, $2, $3, $4)
    ", params = list("store_request", scene_id, jsonlite::toJSON(payload, auto_unbox = TRUE), discord_username))

    discord_post_to_scene(scene_id, store_name, location, db_pool)
    removeModal()
    notify("Your store request has been sent to the scene admin! We'll follow up on Discord.", type = "message", duration = 5)

    rv$requests_refresh <- (rv$requests_refresh %||% 0) + 1
  }, error = function(e) {
    warning(paste("Store request error:", e$message))
    removeModal()
    notify("Your request was received but we couldn't send it to Discord. We'll follow up manually.", type = "warning", duration = 5)
  })
}

# Handle scene request submission
observeEvent(input$submit_scene_request, {
  city_name <- trimws(input$scene_req_name)
  state <- trimws(input$scene_req_state)
  stores <- trimws(input$scene_req_stores)
  notes <- trimws(input$scene_req_notes)
  discord_username <- trimws(input$scene_req_discord)

  if (nchar(city_name) == 0) {
    notify("City / Area name is required", type = "warning")
    return()
  }
  if (nchar(state) == 0) {
    notify("State / Country is required", type = "warning")
    return()
  }
  if (nchar(discord_username) == 0) {
    notify("Discord username is required so we can follow up", type = "warning")
    return()
  }

  # Fuzzy match check — combine city + state for better matching against display_name
  search_term <- paste(city_name, state, sep = " ")
  similar <- find_similar_scenes(db_pool, search_term)

  # Also check city alone (display_name often contains just city)
  if (nrow(similar) == 0) {
    similar <- find_similar_scenes(db_pool, city_name)
  }

  if (nrow(similar) > 0) {
    rv$pending_scene_request <- list(
      city_name = city_name, state = state, stores = stores,
      notes = notes, discord_username = discord_username
    )

    matches_ui <- div(class = "fuzzy-match-list",
      lapply(seq_len(nrow(similar)), function(i) {
        div(class = "fuzzy-match-item d-flex justify-content-between align-items-center p-2 mb-1 rounded",
          span(tags$strong(similar$display_name[i])),
          span(class = "badge bg-warning text-dark",
               paste0(round(similar$sim[i] * 100), "% match"))
        )
      })
    )

    show_fuzzy_match_modal(matches_ui, "submit_scene_request", "Similar Scenes Found", "globe2")
    return()
  }

  submit_scene_request_final(city_name, state, stores, notes, discord_username)
})

# Fuzzy match: go back to edit (restore form values)
observeEvent(input$submit_scene_request_cancel_fuzzy, {
  prefill <- rv$pending_scene_request
  rv$pending_scene_request <- NULL
  removeModal()
  show_scene_request_modal(prefill = prefill)
})

# Fuzzy match: confirm submit anyway
observeEvent(input$submit_scene_request_confirm_fuzzy, {
  req(rv$pending_scene_request)
  p <- rv$pending_scene_request
  rv$pending_scene_request <- NULL
  submit_scene_request_final(p$city_name, p$state, p$stores, p$notes, p$discord_username)
})

# Extracted submission logic
submit_scene_request_final <- function(city_name, state, stores, notes, discord_username) {
  tryCatch({
    location <- paste(city_name, state, sep = ", ")

    payload <- list(
      city = city_name,
      state = state,
      request_subtype = "new_scene"
    )
    if (nchar(stores) > 0) payload$suggested_stores <- stores
    if (nchar(notes) > 0) payload$notes <- notes

    safe_execute(db_pool, "
      INSERT INTO admin_requests (request_type, scene_id, payload, discord_username)
      VALUES ($1, NULL, $2, $3)
    ", params = list("scene_request", jsonlite::toJSON(payload, auto_unbox = TRUE), discord_username))

    discord_post_scene_request(city_name, location, discord_username)
    rv$requests_refresh <- (rv$requests_refresh %||% 0) + 1

    removeModal()
    notify("Your scene request has been submitted! We'll follow up on Discord.", type = "message", duration = 5)
  }, error = function(e) {
    warning(paste("Scene request error:", e$message))
    removeModal()
    notify("Your request was received but we couldn't send it to Discord. We'll follow up manually.", type = "warning", duration = 5)
  })
}

