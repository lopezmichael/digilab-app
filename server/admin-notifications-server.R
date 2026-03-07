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

  # Build detail lines from payload
  details <- list()
  for (key in names(payload)) {
    if (key == "request_subtype") next
    label <- gsub("_", " ", key)
    label <- paste0(toupper(substring(label, 1, 1)), substring(label, 2))
    val <- payload[[key]]
    if (!is.null(val) && nchar(as.character(val)) > 0) {
      details <- c(details, list(
        div(class = "req-detail",
          tags$span(class = "req-label", paste0(label, ":")),
          tags$span(val)
        )
      ))
    }
  }

  time_ago <- format(as.POSIXct(req_row$submitted_at), "%b %d, %Y %I:%M %p")

  div(
    class = "request-card",
    div(class = "request-card-header",
      div(
        tags$span(class = "req-discord", paste0("@", req_row$discord_username)),
        tags$span(class = "req-time text-muted", time_ago)
      ),
      div(class = "request-card-actions",
        actionButton(
          paste0("resolve_req_", req_row$id),
          "Resolve",
          class = "btn btn-sm btn-outline-success",
          onclick = sprintf("Shiny.setInputValue('resolve_request', {id: %d, action: 'resolved', ts: Date.now()}, {priority: 'event'})", req_row$id)
        ),
        actionButton(
          paste0("reject_req_", req_row$id),
          "Reject",
          class = "btn btn-sm btn-outline-danger",
          onclick = sprintf("Shiny.setInputValue('resolve_request', {id: %d, action: 'rejected', ts: Date.now()}, {priority: 'event'})", req_row$id)
        )
      )
    ),
    div(class = "request-card-body", details)
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
  total <- sum(unlist(counts))

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

  if (counts$bug_report > 0 && rv$is_superadmin) {
    items <- c(items, list(
      actionLink("notif_bugs", paste0(counts$bug_report, " bug ",
        if (counts$bug_report == 1) "report" else "reports"),
        class = "notif-link")
    ))
  }

  separated <- list()
  for (i in seq_along(items)) {
    if (i > 1) separated <- c(separated, list(span(class = "notif-sep", "\u00b7")))
    separated <- c(separated, list(items[[i]]))
  }

  div(
    class = "admin-notification-bar",
    bsicons::bs_icon("bell-fill", class = "notif-icon"),
    div(class = "notif-items", separated)
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

observeEvent(input$notif_bugs, {
  nav_select("main_content", "admin_results")
  session$sendCustomMessage("updateSidebarNav", "nav_admin_results")
})
