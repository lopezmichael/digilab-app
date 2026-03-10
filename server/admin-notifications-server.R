# =============================================================================
# Admin Notification Bar + Request Queue
# Shows pending request counts with clickable navigation to relevant admin tabs
# Renders pending request cards on admin tabs with approve/reject actions
# =============================================================================

# 5-minute background refresh timer
admin_refresh_timer <- reactiveTimer(300000)

# ---------------------------------------------------------------------------
# Query: Get pending request counts from admin_requests table
# ---------------------------------------------------------------------------

get_pending_request_counts <- function(pool, scene_id, is_superadmin) {
  if (is_superadmin) {
    counts <- safe_query(pool, "
      SELECT request_type, COUNT(*) as n
      FROM admin_requests
      WHERE status = 'pending'
      GROUP BY request_type
    ", default = data.frame(request_type = character(), n = integer()))
  } else {
    counts <- safe_query(pool, "
      SELECT request_type, COUNT(*) as n
      FROM admin_requests
      WHERE status = 'pending' AND scene_id = $1
      GROUP BY request_type
    ", params = list(scene_id), default = data.frame(request_type = character(), n = integer()))
  }

  type_counts <- list(
    store_request = 0,
    scene_request = 0,
    data_error = 0,
    bug_report = 0
  )
  for (i in seq_len(nrow(counts))) {
    type_counts[[counts$request_type[i]]] <- counts$n[i]
  }

  # Deck requests use a separate table (deck_requests)
  if (is_superadmin) {
    deck_count <- safe_query(pool, "
      SELECT COUNT(*) as n FROM deck_requests WHERE status = 'pending'
    ", default = data.frame(n = 0))
    type_counts$deck_request <- deck_count$n[1]
  } else {
    type_counts$deck_request <- 0
  }

  # Suggested player merges (Limitless → Local)
  if (is_superadmin) {
    merge_count <- safe_query(pool, "
      SELECT COUNT(*) as n
      FROM players l
      JOIN players loc ON LOWER(l.display_name) = LOWER(loc.display_name)
        AND l.player_id != loc.player_id
      WHERE l.limitless_username IS NOT NULL AND l.limitless_username != ''
        AND (l.member_number IS NULL OR l.member_number = '')
        AND loc.member_number IS NOT NULL AND loc.member_number != ''
        AND l.is_active IS NOT FALSE AND loc.is_active IS NOT FALSE
    ", default = data.frame(n = 0))
    type_counts$suggested_merge <- merge_count$n[1]
  } else {
    type_counts$suggested_merge <- 0
  }

  # Stores missing schedules
  if (is_superadmin) {
    missing <- safe_query(pool, "
      SELECT COUNT(*) as n FROM stores s
      WHERE s.is_active = TRUE AND s.is_online = FALSE
        AND NOT EXISTS (SELECT 1 FROM store_schedules ss WHERE ss.store_id = s.store_id AND ss.is_active = TRUE)
    ", default = data.frame(n = 0))
    type_counts$missing_schedule <- missing$n[1]
  } else {
    missing <- safe_query(pool, "
      SELECT COUNT(*) as n FROM stores s
      JOIN scenes sc ON s.scene_id = sc.scene_id
      WHERE s.is_active = TRUE AND s.is_online = FALSE AND sc.scene_id = $1
        AND NOT EXISTS (SELECT 1 FROM store_schedules ss WHERE ss.store_id = s.store_id AND ss.is_active = TRUE)
    ", params = list(scene_id), default = data.frame(n = 0))
    type_counts$missing_schedule <- missing$n[1]
  }

  type_counts
}

# ---------------------------------------------------------------------------
# Query: Get pending requests by type
# ---------------------------------------------------------------------------

get_pending_requests <- function(pool, request_type, scene_id = NULL, is_superadmin = TRUE) {
  if (is_superadmin || is.null(scene_id)) {
    safe_query(pool, "
      SELECT id, request_type, scene_id, payload, discord_username, submitted_at
      FROM admin_requests
      WHERE status = 'pending' AND request_type = $1
      ORDER BY submitted_at DESC
    ", params = list(request_type), default = data.frame())
  } else {
    safe_query(pool, "
      SELECT id, request_type, scene_id, payload, discord_username, submitted_at
      FROM admin_requests
      WHERE status = 'pending' AND request_type = $1 AND scene_id = $2
      ORDER BY submitted_at DESC
    ", params = list(request_type, scene_id), default = data.frame())
  }
}

# ---------------------------------------------------------------------------
# Helper: Render a single request card
# ---------------------------------------------------------------------------

render_request_card <- function(req_row) {
  payload <- tryCatch(
    jsonlite::fromJSON(req_row$payload),
    error = function(e) list()
  )

  # Build labeled detail tags based on request type
  details <- switch(req_row$request_type,
    store_request = {
      tagList(
        if (!is.null(payload$store_name)) span(class = "req-field", span(class = "req-label", "Store:"), payload$store_name),
        if (!is.null(payload$city) || !is.null(payload$state))
          span(class = "req-field", span(class = "req-label", "Location:"), paste(c(payload$city, payload$state), collapse = ", "))
      )
    },
    scene_request = {
      location <- paste(c(payload$city, payload$state), collapse = ", ")
      tagList(
        span(class = "req-field", span(class = "req-label", "Area:"), location),
        if (!is.null(payload$suggested_stores) && nchar(payload$suggested_stores) > 0)
          span(class = "req-field", span(class = "req-label", "Stores:"), payload$suggested_stores)
      )
    },
    data_error = {
      desc <- payload$description %||% ""
      if (nchar(desc) > 100) desc <- paste0(substr(desc, 1, 97), "...")
      tagList(
        if (!is.null(payload$context)) span(class = "req-field", span(class = "req-label", "Item:"), payload$context),
        span(class = "req-field", span(class = "req-label", "Issue:"), desc)
      )
    },
    bug_report = {
      desc <- payload$description %||% ""
      if (nchar(desc) > 100) desc <- paste0(substr(desc, 1, 97), "...")
      tagList(
        if (!is.null(payload$title)) span(class = "req-field", span(class = "req-label", "Bug:"), payload$title),
        span(class = "req-field", span(class = "req-label", "Details:"), desc)
      )
    },
    tagList()
  )

  time_ago <- format(as.POSIXct(req_row$submitted_at), "%b %d")

  # Extra details for scene requests (notes)
  extra <- NULL
  if (req_row$request_type == "scene_request" && !is.null(payload$notes) && nchar(payload$notes) > 0) {
    extra <- div(class = "req-notes", span(class = "req-label", "Notes:"), " ", payload$notes)
  }

  div(
    class = "request-card",
    div(class = "request-card-row",
      div(class = "request-card-info",
        div(class = "req-details", details),
        tags$span(class = "req-meta",
          tags$span(class = "req-discord", paste0("@", req_row$discord_username)),
          tags$span(class = "req-time", time_ago)
        )
      ),
      div(class = "request-card-actions",
        tags$button(
          class = "btn btn-sm btn-outline-success",
          title = "Mark as Done",
          onclick = sprintf("Shiny.setInputValue('resolve_request', {id: %d, action: 'resolved', ts: Date.now()}, {priority: 'event'})", req_row$id),
          bsicons::bs_icon("check-lg"), " Done"
        ),
        tags$button(
          class = "btn btn-sm btn-outline-danger",
          title = "Reject",
          onclick = sprintf("Shiny.setInputValue('resolve_request', {id: %d, action: 'rejected', ts: Date.now()}, {priority: 'event'})", req_row$id),
          bsicons::bs_icon("x-lg"), " Reject"
        )
      )
    ),
    extra
  )
}

# ---------------------------------------------------------------------------
# Notification Bar UI
# ---------------------------------------------------------------------------

output$admin_notification_bar <- renderUI({
  req(rv$is_admin)

  admin_refresh_timer()
  rv$requests_refresh

  scene_id <- if (!rv$is_superadmin && !is.null(rv$admin_user)) {
    rv$admin_user$scene_id
  } else {
    NULL
  }

  counts <- get_pending_request_counts(db_pool, scene_id, rv$is_superadmin)
  # Exclude bug_report from total — bugs are Discord-only, not shown in-app
  total <- sum(unlist(counts)) - (counts$bug_report %||% 0)

  if (total == 0) return(NULL)

  items <- list()

  if (counts$store_request > 0) {
    items <- c(items, list(
      actionLink("notif_stores", paste0(counts$store_request, " store ",
        if (counts$store_request == 1) "request" else "requests"),
        class = "notif-link")
    ))
  }

  if (counts$scene_request > 0 && rv$is_superadmin) {
    items <- c(items, list(
      actionLink("notif_scenes", paste0(counts$scene_request, " scene ",
        if (counts$scene_request == 1) "request" else "requests"),
        class = "notif-link")
    ))
  }

  if (counts$data_error > 0) {
    items <- c(items, list(
      actionLink("notif_data_errors", paste0(counts$data_error, " data ",
        if (counts$data_error == 1) "error" else "errors"),
        class = "notif-link")
    ))
  }

  if (counts$deck_request > 0 && rv$is_superadmin) {
    items <- c(items, list(
      actionLink("notif_decks", paste0(counts$deck_request, " deck ",
        if (counts$deck_request == 1) "request" else "requests"),
        class = "notif-link")
    ))
  }

  if ((counts$suggested_merge %||% 0) > 0 && rv$is_superadmin) {
    items <- c(items, list(
      actionLink("notif_merges", paste0(counts$suggested_merge, " merge ",
        if (counts$suggested_merge == 1) "suggestion" else "suggestions"),
        class = "notif-link")
    ))
  }

  if ((counts$missing_schedule %||% 0) > 0) {
    items <- c(items, list(
      actionLink("notif_missing_schedules", paste0(counts$missing_schedule, " missing ",
        if (counts$missing_schedule == 1) "schedule" else "schedules"),
        class = "notif-link")
    ))
  }

  div(
    class = "admin-notification-bar",
    bsicons::bs_icon("bell-fill", class = "notif-icon"),
    div(class = "notif-items", items)
  )
})

# ---------------------------------------------------------------------------
# Pending Request Panels (rendered on admin tabs)
# ---------------------------------------------------------------------------

output$pending_store_requests <- renderUI({
  req(rv$is_admin)
  rv$requests_refresh

  scene_id <- if (!rv$is_superadmin && !is.null(rv$admin_user)) {
    rv$admin_user$scene_id
  } else {
    NULL
  }

  reqs <- get_pending_requests(db_pool, "store_request", scene_id, rv$is_superadmin)
  if (nrow(reqs) == 0) return(NULL)

  div(class = "pending-requests-panel",
    h4(class = "pending-requests-title",
      bsicons::bs_icon("inbox-fill", class = "me-2"),
      paste0("Pending Store Requests (", nrow(reqs), ")")
    ),
    div(class = "pending-requests-hint",
      "These are community requests \u2014 they don't add anything automatically.",
      "Use the form below to add the store, then mark the request as done."
    ),
    lapply(seq_len(nrow(reqs)), function(i) render_request_card(reqs[i, ])),
    tags$hr()
  )
})

output$pending_scene_requests <- renderUI({
  req(rv$is_superadmin)
  rv$requests_refresh

  reqs <- get_pending_requests(db_pool, "scene_request")
  if (nrow(reqs) == 0) return(NULL)

  div(class = "pending-requests-panel",
    h4(class = "pending-requests-title",
      bsicons::bs_icon("inbox-fill", class = "me-2"),
      paste0("Pending Scene Requests (", nrow(reqs), ")")
    ),
    div(class = "pending-requests-hint",
      "These are community requests \u2014 they don't add anything automatically.",
      "Use the form below to add the scene, then mark the request as done."
    ),
    lapply(seq_len(nrow(reqs)), function(i) render_request_card(reqs[i, ])),
    tags$hr()
  )
})

output$pending_data_errors <- renderUI({
  req(rv$is_admin)
  rv$requests_refresh

  scene_id <- if (!rv$is_superadmin && !is.null(rv$admin_user)) {
    rv$admin_user$scene_id
  } else {
    NULL
  }

  reqs <- get_pending_requests(db_pool, "data_error", scene_id, rv$is_superadmin)
  if (nrow(reqs) == 0) return(NULL)

  div(class = "pending-requests-panel",
    h4(class = "pending-requests-title",
      bsicons::bs_icon("inbox-fill", class = "me-2"),
      paste0("Pending Data Errors (", nrow(reqs), ")")
    ),
    div(class = "pending-requests-hint",
      "Community-reported data errors. Review each issue, fix it in the data, then mark as done."
    ),
    lapply(seq_len(nrow(reqs)), function(i) render_request_card(reqs[i, ])),
    tags$hr()
  )
})

# ---------------------------------------------------------------------------
# Resolution handler: approve/reject requests
# ---------------------------------------------------------------------------

observeEvent(input$resolve_request, {
  req(rv$is_admin)

  req_id <- input$resolve_request$id
  action <- input$resolve_request$action
  req(req_id, action %in% c("resolved", "rejected"))

  admin_name <- current_admin_username(rv)

  tryCatch({
    safe_execute(db_pool, "
      UPDATE admin_requests
      SET status = $1, resolved_at = NOW(), resolved_by = $2
      WHERE id = $3 AND status = 'pending'
    ", params = list(action, admin_name, req_id))

    rv$requests_refresh <- (rv$requests_refresh %||% 0) + 1

    label <- if (action == "resolved") "resolved" else "rejected"
    notify(paste("Request", label), type = "message")
  }, error = function(e) {
    warning(paste("Failed to resolve request:", e$message))
    notify("Failed to update request", type = "warning")
  })
})

# ---------------------------------------------------------------------------
# Navigation handlers: click notification link -> navigate to admin tab
# ---------------------------------------------------------------------------

observeEvent(input$notif_stores, {
  nav_select("main_content", "admin_stores")
  session$sendCustomMessage("updateSidebarNav", "nav_admin_stores")
})

observeEvent(input$notif_scenes, {
  nav_select("main_content", "admin_scenes")
  session$sendCustomMessage("updateSidebarNav", "nav_admin_scenes")
})

observeEvent(input$notif_data_errors, {
  nav_select("main_content", "admin_tournaments")
  session$sendCustomMessage("updateSidebarNav", "nav_admin_tournaments")
})

observeEvent(input$notif_decks, {
  nav_select("main_content", "admin_decks")
  session$sendCustomMessage("updateSidebarNav", "nav_admin_decks")
})

observeEvent(input$notif_merges, {
  nav_select("main_content", "admin_players")
  session$sendCustomMessage("updateSidebarNav", "nav_admin_players")
})

observeEvent(input$notif_missing_schedules, {
  nav_select("main_content", "admin_stores")
  session$sendCustomMessage("updateSidebarNav", "nav_admin_stores")
})
