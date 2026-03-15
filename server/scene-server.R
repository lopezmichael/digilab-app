# =============================================================================
# Scene Selection Server Logic
# Handles scene selection, onboarding modal, and localStorage sync
# =============================================================================

# -----------------------------------------------------------------------------
# Scene Choices Helper
# -----------------------------------------------------------------------------

#' Get FA icon class for a continent value
#' @param continent Character continent code
#' @return Character FA icon name
get_continent_icon <- function(continent) {
  switch(continent,
    "all" = "globe",
    "north_america" = "earth-americas",
    "south_america" = "earth-americas",
    "europe" = "earth-europe",
    "africa" = "earth-africa",
    "asia" = "earth-asia",
    "oceania" = "earth-oceania",
    "online" = "wifi",
    "globe"
  )
}

#' Get available scene choices for dropdown, optionally filtered by continent
#' Returns optgroup-structured list when filtering by continent
#' @param db_con Database connection
#' @param continent Character continent code or "all"
#' @return Named list of scene display names and slugs (with optgroups)
get_scene_choices <- function(db_con, continent = "all") {
  # Online is a special case
  if (continent == "online") {
    return(list("Online / Webcam" = "online"))
  }

  # Check if continent column exists AND has data (migration may not have run yet)
  has_continent <- tryCatch({
    result <- safe_query(db_con,
      "SELECT EXISTS (
         SELECT 1 FROM information_schema.columns
         WHERE table_name = 'scenes' AND column_name = 'continent'
       ) AS col_exists",
      default = data.frame(col_exists = FALSE))
    if (!isTRUE(result$col_exists[1])) {
      FALSE
    } else {
      result2 <- safe_query(db_con,
        "SELECT EXISTS (SELECT 1 FROM scenes WHERE continent IS NOT NULL) AS has_data",
        default = data.frame(has_data = FALSE))
      isTRUE(result2$has_data[1])
    }
  }, error = function(e) FALSE)

  # Query scenes with state_region for US grouping
  base_cols <- "slug, display_name, scene_type, country, state_region, parent_scene_id"
  base_where <- "is_active = TRUE AND scene_type IN ('metro', 'country')"

  if (!has_continent || continent == "all") {
    scenes <- safe_query(db_con,
      sprintf("SELECT %s FROM scenes WHERE %s ORDER BY country, state_region, display_name",
              base_cols, base_where),
      default = data.frame(slug = character(), display_name = character(),
                           scene_type = character(), country = character(),
                           state_region = character(), parent_scene_id = integer()))
  } else {
    scenes <- safe_query(db_con,
      sprintf("SELECT %s FROM scenes WHERE %s AND continent = $1
               ORDER BY country, state_region, display_name", base_cols, base_where),
      params = list(continent),
      default = data.frame(slug = character(), display_name = character(),
                           scene_type = character(), country = character(),
                           state_region = character(), parent_scene_id = integer()))
  }

  if (nrow(scenes) == 0) return(list("All Scenes" = "all"))

  # --- Helper: extract metro name from display_name ---
  # After scene rename (Phase 5), display_name is already the clean metro name.
  # Falls back to parenthetical extraction for legacy "Country (Metro)" format.
  extract_metro <- function(display_name) {
    m <- regmatches(display_name, regexpr("\\(([^)]+)\\)", display_name))
    if (length(m) > 0 && nchar(m) > 0) gsub("^\\(|\\)$", "", m) else display_name
  }

  # --- US state abbreviation map ---
  state_abbrev <- c(
    "Alabama" = "AL", "Alaska" = "AK", "Arizona" = "AZ", "Arkansas" = "AR",
    "California" = "CA", "Colorado" = "CO", "Connecticut" = "CT", "Delaware" = "DE",
    "District of Columbia" = "DC", "Florida" = "FL", "Georgia" = "GA", "Hawaii" = "HI",
    "Idaho" = "ID", "Illinois" = "IL", "Indiana" = "IN", "Iowa" = "IA",
    "Kansas" = "KS", "Kentucky" = "KY", "Louisiana" = "LA", "Maine" = "ME",
    "Maryland" = "MD", "Massachusetts" = "MA", "Michigan" = "MI", "Minnesota" = "MN",
    "Mississippi" = "MS", "Missouri" = "MO", "Montana" = "MT", "Nebraska" = "NE",
    "Nevada" = "NV", "New Hampshire" = "NH", "New Jersey" = "NJ", "New Mexico" = "NM",
    "New York" = "NY", "North Carolina" = "NC", "North Dakota" = "ND", "Ohio" = "OH",
    "Oklahoma" = "OK", "Oregon" = "OR", "Pennsylvania" = "PA", "Rhode Island" = "RI",
    "South Carolina" = "SC", "South Dakota" = "SD", "Tennessee" = "TN", "Texas" = "TX",
    "Utah" = "UT", "Vermont" = "VT", "Virginia" = "VA", "Washington" = "WA",
    "West Virginia" = "WV", "Wisconsin" = "WI", "Wyoming" = "WY"
  )
  get_state_abbrev <- function(state) {
    ab <- state_abbrev[state]
    if (is.na(ab)) substr(state, 1, 2) else ab
  }

  # Separate US vs non-US metros
  us_metros <- scenes[scenes$country == "United States" & scenes$scene_type == "metro", ]
  other_metros <- scenes[(scenes$country != "United States" | is.na(scenes$country)) &
                          scenes$scene_type == "metro", ]

  # --- Build choices using optgroups for visual separation ---
  # Optgroup labels are non-clickable visual headers;
  # first option inside each group is the selectable "all of country/state"
  choices <- list("All Scenes" = "all")

  # Non-US countries
  countries <- unique(other_metros$country[!is.na(other_metros$country)])
  countries <- sort(countries)

  for (cty in countries) {
    metros <- other_metros[other_metros$country == cty, ]
    if (nrow(metros) == 0) next

    group <- list()

    # Selectable "all of country" option
    group[[paste0("All of ", cty)]] <- paste0("country:", cty)

    # Individual metros with clean names
    for (i in seq_len(nrow(metros))) {
      metro_name <- extract_metro(metros$display_name[i])
      group[[metro_name]] <- metros$slug[i]
    }

    choices[[cty]] <- group
  }

  # US scenes grouped by state
  if (nrow(us_metros) > 0) {
    us_group <- list()
    us_group[["All of United States"]] <- "country:United States"

    states <- unique(us_metros$state_region[!is.na(us_metros$state_region)])
    states <- sort(states)

    for (st in states) {
      state_metros <- us_metros[us_metros$state_region == st, ]
      if (nrow(state_metros) == 0) next
      ab <- get_state_abbrev(st)

      if (nrow(state_metros) == 1) {
        # Single metro state — show as "ST · Metro"
        metro_name <- extract_metro(state_metros$display_name[1])
        us_group[[paste0(ab, " \u00B7 ", metro_name)]] <- state_metros$slug[1]
      } else {
        # Multi-metro state: state header + individual metros
        us_group[[paste0("", st)]] <- paste0("state:", st)
        for (i in seq_len(nrow(state_metros))) {
          metro_name <- extract_metro(state_metros$display_name[i])
          us_group[[paste0(ab, " \u00B7 ", metro_name)]] <- state_metros$slug[i]
        }
      }
    }

    choices[["United States"]] <- us_group
  }

  # Online option
  if (continent == "all") {
    choices[["Online / Webcam"]] <- "online"
  }

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
  # Use stored continent + scene preference if available
  stored <- input$scene_from_storage
  continent <- "all"
  scene_selected <- "all"

  if (!is.null(stored)) {
    if (!is.null(stored$continent) && stored$continent != "") {
      continent <- stored$continent
    }
    if (!is.null(stored$scene) && stored$scene != "") {
      scene_selected <- stored$scene
    }
  }

  # Set continent dropdown and reactive value
  rv$current_continent <- continent
  updateSelectInput(session, "continent_selector", selected = continent)
  session$sendCustomMessage("updateContinentIcon", get_continent_icon(continent))

  # Build scene choices for selected continent and set selection
  choices <- get_scene_choices(db_pool, continent)
  if (scene_selected %in% unlist(choices)) {
    updateSelectInput(session, "scene_selector", choices = choices, selected = scene_selected)
  } else {
    updateSelectInput(session, "scene_selector", choices = choices, selected = "all")
  }
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
    # Slug redirect map for stale localStorage values after scene renames
    slug_redirects <- c(
      "dfw" = "dallas-fort-worth"
    )
    scene_slug <- stored$scene
    if (scene_slug %in% names(slug_redirects)) {
      scene_slug <- slug_redirects[[scene_slug]]
    }

    continent <- stored$continent %||% "all"
    rv$current_continent <- continent
    updateSelectInput(session, "continent_selector", selected = continent)
    session$sendCustomMessage("updateContinentIcon", get_continent_icon(continent))

    choices <- get_scene_choices(db_pool, continent)
    if (scene_slug %in% unlist(choices)) {
      rv$current_scene <- scene_slug
      updateSelectInput(session, "scene_selector", choices = choices, selected = scene_slug)
      shinyjs::delay(200, {
        session$sendCustomMessage("resetPillToggle", list(inputId = "players_min_events", value = "0"))
        session$sendCustomMessage("resetPillToggle", list(inputId = "meta_min_entries", value = "0"))
      })
    }
  }
}, once = TRUE)

# -----------------------------------------------------------------------------
# Continent Selector Cascade
# -----------------------------------------------------------------------------

# When continent changes, update scene dropdown choices and reset to "all"
observeEvent(input$continent_selector, {
  continent <- input$continent_selector
  if (is.null(continent)) return()

  # Update icon
  session$sendCustomMessage("updateContinentIcon", get_continent_icon(continent))

  # Store continent in reactive value
  rv$current_continent <- continent

  # Rebuild scene choices for this continent
  choices <- get_scene_choices(db_pool, continent)

  # For Online continent, auto-select "online" scene
  if (continent == "online") {
    updateSelectInput(session, "scene_selector", choices = choices, selected = "online")
  } else {
    updateSelectInput(session, "scene_selector", choices = choices, selected = "all")
    # When scene stays "all", the scene observer won't fire (same value),
    # so trigger data refresh here for continent-level filtering
    rv$current_scene <- "all"
    rv$data_refresh <- Sys.time()
  }

  # Save preference
  session$sendCustomMessage("saveScenePreference", list(
    scene = if (continent == "online") "online" else "all",
    continent = continent
  ))

  # Reset pill toggles and advanced filters
  session$sendCustomMessage("resetPillToggle", list(inputId = "players_min_events", value = "0"))
  session$sendCustomMessage("resetPillToggle", list(inputId = "meta_min_entries", value = "0"))
  updateSelectInput(session, "players_store_filter", selected = "")
  updateSelectInput(session, "tournaments_store_filter", selected = "")
  updateSelectInput(session, "players_win_pct_filter", selected = "0")
  updateSelectInput(session, "meta_conversion_filter", selected = "0")
  updateSelectInput(session, "tournaments_size_filter", selected = "0")
  updateCheckboxInput(session, "players_top3_toggle", value = FALSE)
  updateCheckboxInput(session, "players_decklist_toggle", value = FALSE)
  updateCheckboxInput(session, "meta_top3_toggle", value = FALSE)
  updateCheckboxInput(session, "meta_decklist_toggle", value = FALSE)
  updateDateInput(session, "tournaments_date_from", value = NA)
  updateDateInput(session, "tournaments_date_to", value = NA)
}, ignoreInit = TRUE)

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

  # Save both continent and scene to localStorage
  session$sendCustomMessage("saveScenePreference", list(
    scene = new_scene,
    continent = input$continent_selector %||% "all"
  ))

  # Trigger data refresh
  rv$data_refresh <- Sys.time()

  # Reset pill toggles and advanced filters on scene change
  session$sendCustomMessage("resetPillToggle", list(inputId = "players_min_events", value = "0"))
  session$sendCustomMessage("resetPillToggle", list(inputId = "meta_min_entries", value = "0"))
  updateSelectInput(session, "players_store_filter", selected = "")
  updateSelectInput(session, "tournaments_store_filter", selected = "")
  updateSelectInput(session, "players_win_pct_filter", selected = "0")
  updateSelectInput(session, "meta_conversion_filter", selected = "0")
  updateSelectInput(session, "tournaments_size_filter", selected = "0")
  updateCheckboxInput(session, "players_top3_toggle", value = FALSE)
  updateCheckboxInput(session, "players_decklist_toggle", value = FALSE)
  updateCheckboxInput(session, "meta_top3_toggle", value = FALSE)
  updateCheckboxInput(session, "meta_decklist_toggle", value = FALSE)
  updateDateInput(session, "tournaments_date_from", value = NA)
  updateDateInput(session, "tournaments_date_to", value = NA)
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
  session$sendCustomMessage("saveScenePreference", list(scene = "all", continent = "all"))
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
  session$sendCustomMessage("saveScenePreference", list(
    scene = scene_slug,
    continent = input$continent_selector %||% "all"
  ))
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
        bsicons::bs_icon("globe-americas", class = "text-primary"),
        span("Cascading scene selector — pick continent then scene, with country groupings")
      ),
      div(class = "version-changelog-item",
        bsicons::bs_icon("funnel", class = "text-success"),
        span("Advanced filters on every tab — store, win %, date range, color, size, and more")
      ),
      div(class = "version-changelog-item",
        bsicons::bs_icon("toggle-on", class = "text-info"),
        span("Ranked/Unranked toggle replaces the old event threshold pills")
      ),
      div(class = "version-changelog-item",
        bsicons::bs_icon("phone", class = "text-warning"),
        span("Mobile filter panels — search always visible, filters behind a compact toggle")
      ),
      div(class = "version-changelog-item",
        bsicons::bs_icon("incognito", class = "text-danger"),
        span("Player anonymization — players can request to hide their name from public views")
      ),
      div(class = "version-changelog-item",
        bsicons::bs_icon("table", class = "text-success"),
        span("Reactable tables in player and deck modals for richer match history")
      ),
      div(class = "version-changelog-item",
        bsicons::bs_icon("search", class = "text-warning"),
        span("Find decks with decklists or top 3 finishes using the new advanced filters")
      ),
      div(class = "version-changelog-item",
        bsicons::bs_icon("shield-check", class = "text-info"),
        span("Admin-scene junction table for multi-scene regional admin access")
      )
    )
  )
}

