# =============================================================================
# Admin Notification Bar
# Shows pending request counts with clickable navigation to relevant admin tabs
# =============================================================================

# 5-minute background refresh timer
admin_refresh_timer <- reactiveTimer(300000)

# ---------------------------------------------------------------------------
# Query: Get pending request counts from admin_requests table
# ---------------------------------------------------------------------------

get_pending_request_counts <- function(pool, scene_id, is_superadmin) {
  # Base query: count pending requests grouped by type
  if (is_superadmin) {
    counts <- safe_query(pool, "
      SELECT request_type, COUNT(*) as n
      FROM admin_requests
      WHERE status = 'pending'
      GROUP BY request_type
    ", default = data.frame(request_type = character(), n = integer()))
  } else {
    # Scene admins only see requests for their scene
    counts <- safe_query(pool, "
      SELECT request_type, COUNT(*) as n
      FROM admin_requests
      WHERE status = 'pending' AND scene_id = $1
      GROUP BY request_type
    ", params = list(scene_id), default = data.frame(request_type = character(), n = integer()))
  }

  # Convert to named list with defaults
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
# Notification Bar UI
# ---------------------------------------------------------------------------

output$admin_notification_bar <- renderUI({
  req(rv$is_admin)

  # Reactive dependencies: timer + manual refresh
  admin_refresh_timer()
  rv$requests_refresh

  # Get scene_id for scene admins
  scene_id <- if (!rv$is_superadmin && !is.null(rv$admin_user)) {
    rv$admin_user$scene_id
  } else {
    NULL
  }

  counts <- get_pending_request_counts(db_pool, scene_id, rv$is_superadmin)
  total <- sum(unlist(counts))

  if (total == 0) return(NULL)

  # Build notification items as clickable links
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

  # Join items with separator
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
