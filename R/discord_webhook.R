# R/discord_webhook.R
# Discord webhook integration for routing app submissions to Discord Forum channels.
# Fire-and-forget: errors are logged but never block the user.

# Base helper — sends a webhook POST to Discord
# Returns TRUE on success, FALSE on failure
discord_send <- function(webhook_url, body, thread_id = NULL) {
  if (is.null(webhook_url) || is.na(webhook_url) || nchar(webhook_url) == 0) {
    warning("Discord webhook URL not configured")
    return(invisible(FALSE))
  }

  tryCatch({
    url <- webhook_url
    if (!is.null(thread_id) && !is.na(thread_id) && nchar(thread_id) > 0) {
      url <- paste0(url, "?thread_id=", thread_id)
    }

    resp <- httr2::request(url) |>
      httr2::req_body_json(body) |>
      httr2::req_timeout(10) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_perform()

    status <- httr2::resp_status(resp)
    if (status >= 200 && status < 300) {
      invisible(TRUE)
    } else {
      warning(paste("Discord webhook returned status:", status))
      invisible(FALSE)
    }
  }, error = function(e) {
    warning(paste("Discord webhook error:", e$message))
    if (exists("sentry_capture_exception", mode = "function")) {
      try(sentry_capture_exception(e, tags = list(
        component = "discord_webhook",
        webhook_type = if (!is.null(thread_id)) "scene_thread" else "new_post"
      )), silent = TRUE)
    }
    invisible(FALSE)
  })
}

# Create a new forum thread via webhook. Returns thread_id (channel_id) or NULL.
# Generic thread creator — accepts title, content, and optional tags list.
discord_create_action_thread <- function(thread_title, message_content = NULL,
                                         tags = list(), webhook_url = NULL,
                                         embeds = NULL) {
  if (is.null(webhook_url)) {
    webhook_url <- Sys.getenv("DISCORD_WEBHOOK_SCENE_COORDINATION")
  }

  if (is.null(webhook_url) || nchar(webhook_url) == 0) {
    warning("Discord webhook URL not configured for thread creation")
    return(NULL)
  }

  # Append ?wait=true to get the message object back (includes channel_id = thread ID)
  url <- paste0(webhook_url, "?wait=true")

  body <- list(
    thread_name = substr(thread_title, 1, 100)
  )

  # Embeds go in the body if provided
  if (!is.null(embeds)) {
    body$embeds <- embeds
  }

  # Content (used for @mentions) goes alongside embeds
  if (!is.null(message_content) && nchar(message_content) > 0) {
    body$content <- message_content
  }

  # Apply tags (filter out empty strings)
  valid_tags <- Filter(function(t) nchar(t) > 0, tags)
  if (length(valid_tags) > 0) {
    body$applied_tags <- valid_tags
  }

  tryCatch({
    resp <- httr2::request(url) |>
      httr2::req_body_json(body) |>
      httr2::req_timeout(15) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_perform()

    status <- httr2::resp_status(resp)
    if (status >= 200 && status < 300) {
      parsed <- httr2::resp_body_json(resp)
      # Discord returns the message object; channel_id is the thread ID
      return(parsed$channel_id)
    } else {
      warning(paste("Discord webhook returned status:", status))
      return(NULL)
    }
  }, error = function(e) {
    warning(paste("Discord thread creation error:", e$message))
    if (exists("sentry_capture_exception", mode = "function")) {
      try(sentry_capture_exception(e, tags = list(
        component = "discord_webhook",
        webhook_type = "action_thread_create"
      )), silent = TRUE)
    }
    return(NULL)
  })
}

# Query scene admins (direct + regional) for @mention strings
# Returns "<@id1> <@id2>" string, or "" if none found
get_scene_admin_mentions <- function(scene_id, db_pool) {
  if (is.null(scene_id) || is.na(scene_id)) return("")

  tryCatch({
    mentions <- pool::dbGetQuery(db_pool, "
      SELECT DISTINCT au.discord_user_id FROM admin_user_scenes aus
      JOIN admin_users au ON aus.user_id = au.user_id
      WHERE aus.scene_id = $1 AND au.is_active = TRUE AND au.discord_user_id IS NOT NULL
      UNION
      SELECT DISTINCT au.discord_user_id FROM admin_regions ar
      JOIN admin_users au ON ar.user_id = au.user_id
      JOIN scenes s ON s.scene_id = $1
      WHERE au.is_active = TRUE AND au.discord_user_id IS NOT NULL
        AND ar.country = s.country
        AND (ar.state_region IS NULL OR ar.state_region = s.state_region)
    ", params = list(scene_id))

    if (nrow(mentions) == 0) return("")

    ids <- mentions$discord_user_id[!is.na(mentions$discord_user_id) & nchar(mentions$discord_user_id) > 0]
    if (length(ids) == 0) return("")
    paste0("<@", ids, ">", collapse = " ")
  }, error = function(e) {
    warning(paste("Failed to fetch scene admin mentions:", e$message))
    ""
  })
}

# Query super admins for @mention strings
# Returns "<@id1> <@id2>" string, or "" if none found
get_super_admin_mentions <- function(db_pool) {
  tryCatch({
    mentions <- pool::dbGetQuery(db_pool, "
      SELECT DISTINCT discord_user_id
      FROM admin_users
      WHERE role = 'super_admin'
        AND is_active = TRUE
        AND discord_user_id IS NOT NULL
        AND discord_user_id != ''
    ")

    if (nrow(mentions) == 0) return("")

    ids <- mentions$discord_user_id[!is.na(mentions$discord_user_id) & nchar(mentions$discord_user_id) > 0]
    if (length(ids) == 0) return("")
    paste0("<@", ids, ">", collapse = " ")
  }, error = function(e) {
    warning(paste("Failed to fetch super admin mentions:", e$message))
    ""
  })
}

# Post a store request — creates a NEW forum thread per request (not routed to scene thread)
# Returns thread_id or NULL
discord_post_to_scene <- function(scene_id, store_name, city_state, db_pool,
                                  request_id = NULL) {
  scene <- tryCatch(
    pool::dbGetQuery(db_pool,
      "SELECT display_name, latitude, longitude, country FROM scenes WHERE scene_id = $1",
      params = list(scene_id)),
    error = function(e) data.frame()
  )

  scene_display_name <- if (nrow(scene) > 0) scene$display_name[1] else "Unknown"

  # Build embed
  embed <- list(
    title = "New Store Request",
    color = 5793266L,
    fields = list(
      list(name = "Store", value = store_name, inline = TRUE),
      list(name = "Location", value = city_state, inline = TRUE),
      list(name = "Scene", value = scene_display_name, inline = TRUE)
    ),
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )

  # Add footer with request ID
  footer_text <- "Submitted via DigiLab"
  if (!is.null(request_id)) {
    footer_text <- paste0("Request #", request_id, " \u2022 ", footer_text)
  }
  embed$footer <- list(text = footer_text)

  # Mentions go in content (outside embed) so notifications work
  mentions <- get_scene_admin_mentions(scene_id, db_pool)

  # Build tags: continent + STORE_REQUEST
  tags <- list()
  if (nrow(scene) > 0) {
    continent_tag <- get_continent_tag(scene$latitude[1], scene$longitude[1])
    if (nchar(continent_tag) > 0) tags <- c(tags, continent_tag)
  }
  store_req_tag <- Sys.getenv("DISCORD_TAG_STORE_REQUEST", "")
  if (nchar(store_req_tag) > 0) tags <- c(tags, store_req_tag)

  thread_title <- paste0("Store Request: ", store_name, " - ", city_state)

  discord_create_action_thread(
    thread_title = thread_title,
    message_content = mentions,
    embeds = list(embed),
    tags = tags
  )
}

# Post a new scene/store request to #scene-requests Forum
# Returns thread_id or NULL
discord_post_scene_request <- function(store_name, location, discord_username = NA_character_,
                                       db_pool = NULL, request_id = NULL) {
  webhook_url <- Sys.getenv("DISCORD_WEBHOOK_SCENE_REQUESTS")
  tag_id <- Sys.getenv("DISCORD_TAG_NEW_REQUEST")

  # Build embed
  embed <- list(
    title = "New Scene Request",
    color = 10181046L,
    fields = list(
      list(name = "Store/Community", value = store_name, inline = TRUE),
      list(name = "Location", value = location, inline = TRUE)
    ),
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )

  if (!is.na(discord_username) && nchar(discord_username) > 0) {
    embed$fields <- c(embed$fields, list(list(name = "Discord", value = discord_username, inline = TRUE)))
  }

  footer_text <- "Submitted via DigiLab"
  if (!is.null(request_id)) {
    footer_text <- paste0("Request #", request_id, " \u2022 ", footer_text)
  }
  embed$footer <- list(text = footer_text)

  # Mention super_admins for triage
  mentions <- if (!is.null(db_pool)) get_super_admin_mentions(db_pool) else ""

  thread_title <- paste0("Scene Request: ", location)
  tags <- if (nchar(tag_id) > 0) list(tag_id) else list()

  discord_create_action_thread(
    thread_title = thread_title,
    message_content = mentions,
    embeds = list(embed),
    tags = tags,
    webhook_url = webhook_url
  )
}

# Post a data error report — creates a NEW forum thread per error
# Returns thread_id or NULL. Always posts to SCENE_COORDINATION.
discord_post_data_error <- function(scene_id, item_type, item_name, description,
                                    discord_username = NA_character_, db_pool,
                                    request_id = NULL) {
  scene <- tryCatch(
    pool::dbGetQuery(db_pool,
      "SELECT display_name, latitude, longitude, country FROM scenes WHERE scene_id = $1",
      params = list(scene_id)),
    error = function(e) data.frame()
  )

  scene_display_name <- if (nrow(scene) > 0) scene$display_name[1] else "Unknown"

  # Build embed
  embed <- list(
    title = "Data Error Report",
    color = 15105570L,
    fields = list(
      list(name = "Type", value = item_type, inline = TRUE),
      list(name = "Item", value = item_name, inline = TRUE),
      list(name = "Scene", value = scene_display_name, inline = TRUE),
      list(name = "Description", value = description, inline = FALSE)
    ),
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )

  if (!is.na(discord_username) && nchar(discord_username) > 0) {
    embed$fields <- c(embed$fields, list(list(name = "Discord", value = discord_username, inline = TRUE)))
  }

  footer_text <- "Submitted via DigiLab"
  if (!is.null(request_id)) {
    footer_text <- paste0("Request #", request_id, " \u2022 ", footer_text)
  }
  embed$footer <- list(text = footer_text)

  mentions <- get_scene_admin_mentions(scene_id, db_pool)

  # Build tags: continent + DATA_ERROR
  tags <- list()
  if (nrow(scene) > 0) {
    continent_tag <- get_continent_tag(scene$latitude[1], scene$longitude[1])
    if (nchar(continent_tag) > 0) tags <- c(tags, continent_tag)
  }
  data_error_tag <- Sys.getenv("DISCORD_TAG_DATA_ERROR", "")
  if (nchar(data_error_tag) > 0) tags <- c(tags, data_error_tag)

  thread_title <- paste0("Data Error: ", item_type, " - ", item_name)

  discord_create_action_thread(
    thread_title = thread_title,
    message_content = mentions,
    embeds = list(embed),
    tags = tags
  )
}

# Post a bug report to #bug-reports Forum channel
# Returns thread_id or NULL
discord_post_bug_report <- function(title, description, context = "",
                                    discord_username = NA_character_,
                                    db_pool = NULL, request_id = NULL) {
  webhook_url <- Sys.getenv("DISCORD_WEBHOOK_BUG_REPORTS")
  tag_id <- Sys.getenv("DISCORD_TAG_NEW_BUG")

  # Build embed
  bug_fields <- list(
    list(name = "Description", value = substr(description, 1, 1024), inline = FALSE)
  )
  if (nchar(context) > 0) {
    bug_fields <- c(bug_fields, list(list(name = "Context", value = context, inline = TRUE)))
  }

  embed <- list(
    title = paste0("Bug: ", substr(title, 1, 90)),
    color = 15158332L,
    fields = bug_fields,
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
  )

  if (!is.na(discord_username) && nchar(discord_username) > 0) {
    embed$fields <- c(embed$fields, list(list(name = "Discord", value = discord_username, inline = TRUE)))
  }

  footer_text <- "Submitted via DigiLab"
  if (!is.null(request_id)) {
    footer_text <- paste0("Request #", request_id, " \u2022 ", footer_text)
  }
  embed$footer <- list(text = footer_text)

  # Mention super_admins for triage
  mentions <- if (!is.null(db_pool)) get_super_admin_mentions(db_pool) else ""

  thread_title <- paste0("Bug: ", substr(title, 1, 90))
  tags <- if (nchar(tag_id) > 0) list(tag_id) else list()

  discord_create_action_thread(
    thread_title = thread_title,
    message_content = mentions,
    embeds = list(embed),
    tags = tags,
    webhook_url = webhook_url
  )
}

# Determine continent from lat/lng coordinates and return the Discord tag ID.
# Uses geographic bounding boxes — works for any country without maintaining a list.
# Falls back gracefully: returns "" if coords are missing or no tag is configured.
get_continent_tag <- function(lat, lng) {
  if (is.null(lat) || is.null(lng) || is.na(lat) || is.na(lng)) return("")

  # Determine continent from coordinates
  # Order matters: more specific checks first to handle boundary regions
  tag_env <- if (lat < -10 && lng > -90 && lng < -30) {
    # South America (below ~10°N, between 90°W and 30°W)
    "DISCORD_TAG_SOUTH_AMERICA"
  } else if (lat > 5 && lat < 85 && lng > -170 && lng < -30) {
    # North America (above 5°N, west of 30°W) — includes Central America, Caribbean
    "DISCORD_TAG_NORTH_AMERICA"
  } else if (lat >= -10 && lat <= 5 && lng > -90 && lng < -30) {
    # Northern South America / Central America overlap zone
    # Countries near equator in Americas: Colombia, Ecuador, Venezuela, Panama
    if (lng > -80) "DISCORD_TAG_SOUTH_AMERICA" else "DISCORD_TAG_NORTH_AMERICA"
  } else if (lat > -50 && lat < 75 && lng > -30 && lng < 50) {
    # Europe + Africa share this longitude band
    if (lat > 35) {
      "DISCORD_TAG_EUROPE"
    } else {
      "DISCORD_TAG_AFRICA"
    }
  } else if (lat > 35 && lng >= 50 && lng < 180) {
    # Asia (northern, east of 50°E)
    "DISCORD_TAG_ASIA"
  } else if (lat <= 35 && lat > -10 && lng >= 50 && lng < 150) {
    # South/Southeast Asia
    "DISCORD_TAG_ASIA"
  } else if (lat <= -10 && lng > 100 && lng < 180) {
    # Oceania (Australia, NZ, Pacific Islands)
    "DISCORD_TAG_OCEANIA"
  } else if (lat > -50 && lat <= 35 && lng >= -30 && lng < 50) {
    # Africa (already partially covered above, catch remaining)
    "DISCORD_TAG_AFRICA"
  } else {
    NULL
  }

  if (is.null(tag_env)) return("")
  Sys.getenv(tag_env, "")
}

# Legacy alias — kept for backward compatibility with scene creation flow
discord_create_scene_thread <- function(scene_name, message_content, lat = NULL, lng = NULL) {
  tags <- list()
  tag_id <- get_continent_tag(lat, lng)
  if (nchar(tag_id) > 0) tags <- c(tags, tag_id)

  discord_create_action_thread(
    thread_title = scene_name,
    message_content = message_content,
    tags = tags
  )
}

# Resolve a Discord thread via bot token REST API
# Posts a resolution message and adds the Resolved tag to the thread.
# No-ops gracefully if DISCORD_BOT_TOKEN is not set.
discord_resolve_thread <- function(thread_id, resolved_by, action = "resolved") {
  bot_token <- Sys.getenv("DISCORD_BOT_TOKEN", "")
  if (nchar(bot_token) == 0 || is.null(thread_id) || is.na(thread_id) || nchar(thread_id) == 0) {
    return(invisible(FALSE))
  }

  label <- if (action == "resolved") "Resolved" else "Rejected"
  color <- if (action == "resolved") 3066993L else 9807270L

  tryCatch({
    # 1. Post resolution embed to the thread
    msg_url <- paste0("https://discord.com/api/v10/channels/", thread_id, "/messages")
    msg_body <- list(
      embeds = list(list(
        title = label,
        description = paste0("by ", resolved_by, " via DigiLab"),
        color = color,
        timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
      ))
    )

    httr2::request(msg_url) |>
      httr2::req_headers(
        Authorization = paste("Bot", bot_token),
        `Content-Type` = "application/json"
      ) |>
      httr2::req_body_json(msg_body) |>
      httr2::req_timeout(10) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_perform()

    # 2. Add Resolved tag to the thread (PATCH channel)
    resolved_tag <- Sys.getenv("DISCORD_TAG_RESOLVED", "")
    if (nchar(resolved_tag) > 0) {
      # First get current tags
      thread_url <- paste0("https://discord.com/api/v10/channels/", thread_id)
      thread_resp <- httr2::request(thread_url) |>
        httr2::req_headers(Authorization = paste("Bot", bot_token)) |>
        httr2::req_timeout(10) |>
        httr2::req_error(is_error = function(resp) FALSE) |>
        httr2::req_perform()

      if (httr2::resp_status(thread_resp) >= 200 && httr2::resp_status(thread_resp) < 300) {
        thread_data <- httr2::resp_body_json(thread_resp)
        current_tags <- thread_data$applied_tags %||% list()
        new_tags <- unique(c(unlist(current_tags), resolved_tag))

        httr2::request(thread_url) |>
          httr2::req_method("PATCH") |>
          httr2::req_headers(
            Authorization = paste("Bot", bot_token),
            `Content-Type` = "application/json"
          ) |>
          httr2::req_body_json(list(applied_tags = as.list(new_tags))) |>
          httr2::req_timeout(10) |>
          httr2::req_error(is_error = function(resp) FALSE) |>
          httr2::req_perform()
      }
    }

    invisible(TRUE)
  }, error = function(e) {
    warning(paste("Discord resolve thread error:", e$message))
    if (exists("sentry_capture_exception", mode = "function")) {
      try(sentry_capture_exception(e, tags = list(
        component = "discord_webhook",
        webhook_type = "resolve_thread"
      )), silent = TRUE)
    }
    invisible(FALSE)
  })
}

# Send a welcome DM to a Discord user via bot token REST API
# Returns TRUE on success, FALSE on failure. No-ops if no bot token.
discord_send_welcome_dm <- function(discord_user_id, message) {
  bot_token <- Sys.getenv("DISCORD_BOT_TOKEN", "")
  if (nchar(bot_token) == 0 || is.null(discord_user_id) || is.na(discord_user_id) || nchar(discord_user_id) == 0) {
    return(invisible(FALSE))
  }

  tryCatch({
    # 1. Create DM channel
    dm_url <- "https://discord.com/api/v10/users/@me/channels"
    dm_resp <- httr2::request(dm_url) |>
      httr2::req_headers(
        Authorization = paste("Bot", bot_token),
        `Content-Type` = "application/json"
      ) |>
      httr2::req_body_json(list(recipient_id = discord_user_id)) |>
      httr2::req_timeout(10) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_perform()

    if (httr2::resp_status(dm_resp) < 200 || httr2::resp_status(dm_resp) >= 300) {
      warning("Failed to create DM channel")
      return(FALSE)
    }

    dm_channel <- httr2::resp_body_json(dm_resp)
    channel_id <- dm_channel$id

    # 2. Send message
    msg_url <- paste0("https://discord.com/api/v10/channels/", channel_id, "/messages")
    msg_resp <- httr2::request(msg_url) |>
      httr2::req_headers(
        Authorization = paste("Bot", bot_token),
        `Content-Type` = "application/json"
      ) |>
      httr2::req_body_json(list(content = message)) |>
      httr2::req_timeout(10) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_perform()

    httr2::resp_status(msg_resp) >= 200 && httr2::resp_status(msg_resp) < 300
  }, error = function(e) {
    warning(paste("Discord DM error:", e$message))
    if (exists("sentry_capture_exception", mode = "function")) {
      try(sentry_capture_exception(e, tags = list(
        component = "discord_webhook",
        webhook_type = "welcome_dm"
      )), silent = TRUE)
    }
    FALSE
  })
}

# Post a short announcement to #scene-updates
# Randomly selects from a pool of message templates for variety
discord_post_scene_update <- function(scene_name, country = NULL, state_region = NULL, continent = NULL) {
  webhook_url <- Sys.getenv("DISCORD_WEBHOOK_SCENE_UPDATES", "")
  if (nchar(webhook_url) == 0) return(invisible(FALSE))

  templates <- c(
    paste0("**", scene_name, "** just joined DigiLab! Check out their local leaderboard and tournament history."),
    paste0("Welcome to the family, **", scene_name, "**! Your scene is now live."),
    paste0("**", scene_name, "** is officially on the map! Local players can now find their stats and standings."),
    paste0("A new scene has arrived! **", scene_name, "** is ready to track tournaments, players, and meta."),
    paste0("The DigiLab network grows! Welcome **", scene_name, "** to the community."),
    paste0("**", scene_name, "** has entered the arena! Another scene joins the DigiLab family.")
  )

  embed <- list(
    title = paste0("New Scene: ", scene_name),
    description = sample(templates, 1),
    color = 5763719L,
    timestamp = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    footer = list(text = "DigiLab")
  )

  # Add location fields if available
  fields <- list()
  if (!is.null(country) && !is.na(country) && nchar(country) > 0) {
    location <- country
    if (!is.null(state_region) && !is.na(state_region) && nchar(state_region) > 0) {
      location <- paste0(state_region, ", ", country)
    }
    fields <- c(fields, list(list(name = "Location", value = location, inline = TRUE)))
  }
  if (!is.null(continent) && !is.na(continent) && nchar(continent) > 0) {
    continent_label <- gsub("_", " ", continent)
    continent_label <- paste0(toupper(substr(continent_label, 1, 1)), substr(continent_label, 2, nchar(continent_label)))
    fields <- c(fields, list(list(name = "Continent", value = continent_label, inline = TRUE)))
  }
  if (length(fields) > 0) {
    embed$fields <- fields
  }

  body <- list(embeds = list(embed))
  discord_send(webhook_url, body)
}
