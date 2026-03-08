# R/discord_webhook.R
# Discord webhook integration for routing app submissions to Discord Forum channels.
# Fire-and-forget: errors are logged but never block the user.

# Base helper — sends a webhook POST to Discord
discord_send <- function(webhook_url, body, thread_id = NULL) {
  if (is.null(webhook_url) || nchar(webhook_url) == 0) {
    warning("Discord webhook URL not configured")
    return(invisible(FALSE))
  }

  tryCatch({
    url <- webhook_url
    if (!is.null(thread_id) && nchar(thread_id) > 0) {
      url <- paste0(url, "?thread_id=", thread_id)
    }

    httr2::request(url) |>
      httr2::req_body_json(body) |>
      httr2::req_timeout(10) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_perform()

    invisible(TRUE)
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

# Post a store request to an existing scene's #scene-coordination thread
discord_post_to_scene <- function(scene_id, store_name, city_state, db_pool) {
  scene <- tryCatch(
    pool::dbGetQuery(db_pool,
      "SELECT discord_thread_id, display_name FROM scenes WHERE scene_id = $1",
      params = list(scene_id)),
    error = function(e) data.frame()
  )

  if (nrow(scene) == 0) {
    warning(paste("Scene not found:", scene_id))
    return(invisible(FALSE))
  }

  thread_id <- scene$discord_thread_id[1]
  webhook_url <- Sys.getenv("DISCORD_WEBHOOK_SCENE_COORDINATION")

  if (is.null(thread_id) || is.na(thread_id) || nchar(thread_id) == 0) {
    return(discord_post_scene_request(store_name, city_state, discord_username = NA_character_))
  }

  timestamp <- format(Sys.time(), "%m/%d/%Y %I:%M %p %Z")

  body <- list(
    content = paste0(
      "**New Store Request**\n",
      "**Store:** ", store_name, "\n",
      "**Location:** ", city_state, "\n",
      "**Submitted:** ", timestamp, "\n",
      "*Submitted via DigiLab*"
    )
  )

  discord_send(webhook_url, body, thread_id = thread_id)
}

# Post a new scene/store request to #scene-requests Forum
discord_post_scene_request <- function(store_name, location, discord_username = NA_character_) {
  webhook_url <- Sys.getenv("DISCORD_WEBHOOK_SCENE_REQUESTS")
  tag_id <- Sys.getenv("DISCORD_TAG_NEW_REQUEST")

  timestamp <- format(Sys.time(), "%m/%d/%Y %I:%M %p %Z")

  content_lines <- c(
    paste0("**New Scene Request**"),
    paste0("**Store/Community:** ", store_name),
    paste0("**Location:** ", location)
  )

  if (!is.na(discord_username) && nchar(discord_username) > 0) {
    content_lines <- c(content_lines, paste0("**Discord:** ", discord_username))
  }

  content_lines <- c(content_lines,
    paste0("**Submitted:** ", timestamp),
    "*Submitted via DigiLab*"
  )

  body <- list(
    thread_name = paste0("Scene Request: ", location),
    content = paste(content_lines, collapse = "\n")
  )

  if (nchar(tag_id) > 0) {
    body$applied_tags <- list(tag_id)
  }

  discord_send(webhook_url, body)
}

# Post a data error report to a scene's coordination thread
discord_post_data_error <- function(scene_id, item_type, item_name, description,
                                    discord_username = NA_character_, db_pool) {
  scene <- tryCatch(
    pool::dbGetQuery(db_pool,
      "SELECT discord_thread_id, display_name FROM scenes WHERE scene_id = $1",
      params = list(scene_id)),
    error = function(e) data.frame()
  )

  timestamp <- format(Sys.time(), "%m/%d/%Y %I:%M %p %Z")

  content_lines <- c(
    "**Data Error Report**",
    paste0("**Type:** ", item_type),
    paste0("**Item:** ", item_name)
  )

  if (nrow(scene) > 0) {
    content_lines <- c(content_lines, paste0("**Scene:** ", scene$display_name[1]))
  }

  content_lines <- c(content_lines, paste0("**Description:** ", description))

  if (!is.na(discord_username) && nchar(discord_username) > 0) {
    content_lines <- c(content_lines, paste0("**Discord:** ", discord_username))
  }

  content_lines <- c(content_lines,
    paste0("**Submitted:** ", timestamp),
    "*Submitted via DigiLab*"
  )

  body <- list(content = paste(content_lines, collapse = "\n"))

  # Route to scene thread if available, otherwise fall back to bug reports
  if (nrow(scene) > 0) {
    thread_id <- scene$discord_thread_id[1]
    if (!is.null(thread_id) && !is.na(thread_id) && nchar(thread_id) > 0) {
      webhook_url <- Sys.getenv("DISCORD_WEBHOOK_SCENE_COORDINATION")
      return(discord_send(webhook_url, body, thread_id = thread_id))
    }
  }

  # Fallback: post as bug report
  discord_post_bug_report(
    title = paste("Data Error:", item_type, "-", item_name),
    description = description,
    context = if (nrow(scene) > 0) paste("Scene:", scene$display_name[1]) else "",
    discord_username = discord_username
  )
}

# Post a bug report to #bug-reports Forum channel
discord_post_bug_report <- function(title, description, context = "",
                                    discord_username = NA_character_) {
  webhook_url <- Sys.getenv("DISCORD_WEBHOOK_BUG_REPORTS")
  tag_id <- Sys.getenv("DISCORD_TAG_NEW_BUG")

  timestamp <- format(Sys.time(), "%m/%d/%Y %I:%M %p %Z")

  content_lines <- c(
    paste0("**Description:** ", description)
  )

  if (nchar(context) > 0) {
    content_lines <- c(content_lines, paste0("**Context:** ", context))
  }

  if (!is.na(discord_username) && nchar(discord_username) > 0) {
    content_lines <- c(content_lines, paste0("**Discord:** ", discord_username))
  }

  content_lines <- c(content_lines,
    paste0("**Submitted:** ", timestamp),
    "*Submitted via DigiLab*"
  )

  body <- list(
    thread_name = paste0("Bug: ", substr(title, 1, 90)),
    content = paste(content_lines, collapse = "\n")
  )

  if (nchar(tag_id) > 0) {
    body$applied_tags <- list(tag_id)
  }

  discord_send(webhook_url, body)
}

# Post a welcome message to #scene-coordination Forum, creating a new thread
# Returns the channel_id (thread ID) from Discord's response, or NULL on failure
discord_create_scene_thread <- function(scene_name, message_content) {
  webhook_url <- Sys.getenv("DISCORD_WEBHOOK_SCENE_COORDINATION")

  if (is.null(webhook_url) || nchar(webhook_url) == 0) {
    warning("DISCORD_WEBHOOK_SCENE_COORDINATION not configured")
    return(NULL)
  }

  # Append ?wait=true to get the message object back (includes channel_id = thread ID)
  url <- paste0(webhook_url, "?wait=true")

  tryCatch({
    resp <- httr2::request(url) |>
      httr2::req_body_json(list(
        thread_name = scene_name,
        content = message_content
      )) |>
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
    warning(paste("Discord scene thread creation error:", e$message))
    if (exists("sentry_capture_exception", mode = "function")) {
      try(sentry_capture_exception(e, tags = list(
        component = "discord_webhook",
        webhook_type = "scene_thread_create"
      )), silent = TRUE)
    }
    return(NULL)
  })
}

# Post a short announcement to #scene-updates
discord_post_scene_update <- function(scene_name) {
  webhook_url <- Sys.getenv("DISCORD_WEBHOOK_SCENE_REQUESTS")

  if (is.null(webhook_url) || nchar(webhook_url) == 0) return(invisible(FALSE))

  body <- list(
    content = paste0(
      "**New Scene:** ", scene_name, " is now live on DigiLab! ",
      "Check out the local leaderboard and tournament history at https://app.digilab.cards"
    )
  )

  discord_send(webhook_url, body)
}
