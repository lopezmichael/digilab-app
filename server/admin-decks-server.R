# =============================================================================
# Admin: Edit Decks Server Logic
# =============================================================================

# Card search
observeEvent(input$search_card_btn, {
  req(input$card_search)

  # Reset pagination
  rv$card_search_page <- 1

  # Show searching indicator
  output$card_search_results <- renderUI({
    div(class = "text-muted", bsicons::bs_icon("hourglass-split"), " Searching...")
  })

  cards <- tryCatch({
    search_cards_local(db_pool, input$card_search)
  }, error = function(e) {
    message("Card search error: ", e$message)
    NULL
  })

  if (is.null(cards) || nrow(cards) == 0) {
    output$card_search_results <- renderUI({
      div(class = "alert alert-warning", "No cards found for '", input$card_search, "'")
    })
    rv$card_search_results <- NULL
    return()
  }

  # Deduplicate by card ID (removes duplicate listings of same card)
  # Keep all different cards even if they share the same name (alternate arts)
  cards <- cards[!duplicated(cards$id), ]

  # Store ALL cards in reactive for pagination
  rv$card_search_results <- cards

  # Render first page
  render_card_search_page()
})

# Pagination handlers
observeEvent(input$card_search_prev, {
  if (rv$card_search_page > 1) {
    rv$card_search_page <- rv$card_search_page - 1
    render_card_search_page()
  }
})

observeEvent(input$card_search_next, {
  req(rv$card_search_results)
  total_pages <- ceiling(nrow(rv$card_search_results) / 8)
  if (rv$card_search_page < total_pages) {
    rv$card_search_page <- rv$card_search_page + 1
    render_card_search_page()
  }
})

# Helper function to render card search page
render_card_search_page <- function() {
  req(rv$card_search_results)
  cards <- rv$card_search_results
  page <- rv$card_search_page
  per_page <- 8

  total_cards <- nrow(cards)
  total_pages <- ceiling(total_cards / per_page)
  start_idx <- (page - 1) * per_page + 1
  end_idx <- min(page * per_page, total_cards)

  # Get cards for current page
  page_cards <- cards[start_idx:end_idx, ]

  output$card_search_results <- renderUI({
    div(
      # Header with count and pagination
      div(
        class = "d-flex justify-content-between align-items-center mb-2",
        p(class = "text-muted small mb-0", sprintf("Found %d cards (showing %d-%d):", total_cards, start_idx, end_idx)),
        if (total_pages > 1) {
          div(
            class = "d-flex align-items-center gap-1",
            actionButton("card_search_prev", bsicons::bs_icon("chevron-left"),
                         class = paste("btn-sm btn-outline-secondary card-search-pagination", if (page == 1) "disabled" else "")),
            span(class = "small mx-1", sprintf("%d/%d", page, total_pages)),
            actionButton("card_search_next", bsicons::bs_icon("chevron-right"),
                         class = paste("btn-sm btn-outline-secondary card-search-pagination", if (page == total_pages) "disabled" else ""))
          )
        }
      ),
      # Card grid
      div(
        class = "card-search-grid",
        lapply(1:nrow(page_cards), function(i) {
          card_data <- page_cards[i, ]
          # Calculate absolute index for button ID
          abs_idx <- start_idx + i - 1
          # API returns card number in 'id' field, not 'cardnumber'
          card_num <- if ("id" %in% names(card_data)) card_data$id else card_data$cardnumber
          card_name <- if ("name" %in% names(card_data)) card_data$name else "Unknown"
          card_color <- if ("color" %in% names(card_data) && !is.na(card_data$color)) card_data$color else ""

          # Use .webp format - server returns WebP regardless of extension
          img_url <- paste0("https://images.digimoncard.io/images/cards/", card_num, ".webp")

          actionButton(
            inputId = paste0("card_select_", abs_idx),
            label = tagList(
              tags$img(src = img_url,
                       class = "card-search-thumbnail",
                       onerror = "this.style.display='none'; this.nextElementSibling.style.display='block';"),
              tags$div(class = "card-search-no-image", "No image"),
              tags$div(class = "card-search-text-id", card_num),
              tags$div(class = "card-search-text-name", title = card_name, substr(card_name, 1, 15)),
              if (nchar(card_color) > 0) tags$div(class = "card-search-text-color", card_color)
            ),
            class = "card-search-btn card-search-item p-2"
          )
        })
      )
    )
  })
}

# Handle card selection buttons (1-100 to support pagination)
lapply(1:100, function(i) {
  observeEvent(input[[paste0("card_select_", i)]], {
    req(rv$card_search_results)
    if (i <= nrow(rv$card_search_results)) {
      # API returns card number in 'id' field
      card_num <- if ("id" %in% names(rv$card_search_results)) {
        rv$card_search_results$id[i]
      } else {
        rv$card_search_results$cardnumber[i]
      }
      updateTextInput(session, "selected_card_id", value = card_num)
      notify(paste("Selected:", card_num), type = "message", duration = 2)
    }
  }, ignoreInit = TRUE)
})

# Preview selected card
output$selected_card_preview <- renderUI({
  card_id <- trimws(input$selected_card_id %||% "")

  # Show placeholder if no card selected
  if (nchar(card_id) < 3) {
    return(div(
      class = "text-muted",
      style = "font-size: 0.85rem;",
      bsicons::bs_icon("image", size = "2rem"),
      div(class = "mt-2", "No card selected")
    ))
  }

  # Construct image URL directly using the card ID (.webp format)
  img_url <- paste0("https://images.digimoncard.io/images/cards/", card_id, ".webp")

  div(
    class = "text-center",
    tags$img(src = img_url, class = "deck-modal-image",
             onerror = "this.onerror=null; this.src=''; this.alt='Image not found'; this.style.height='60px'; this.style.background='#ddd';"),
    div(class = "mt-1 small text-muted", paste("Selected:", card_id))
  )
})

# Add archetype
observeEvent(input$add_archetype, {
  req(rv$is_superadmin, db_pool)

  clear_all_field_errors(session)

  name <- trimws(input$deck_name)
  primary_color <- input$deck_primary_color
  secondary_color <- if (input$deck_secondary_color == "") NA_character_ else input$deck_secondary_color
  card_id <- if (!is.null(input$selected_card_id) && nchar(input$selected_card_id) > 0) input$selected_card_id else NA_character_

  # Validation
  if (is.null(name) || nchar(name) == 0) {
    show_field_error(session, "deck_name")
    notify("Please enter an archetype name", type = "error")
    return()
  }

  if (nchar(name) < 2) {
    show_field_error(session, "deck_name")
    notify("Archetype name must be at least 2 characters", type = "error")
    return()
  }

  # Check for duplicate archetype name
  existing <- safe_query(db_pool, "
    SELECT archetype_id FROM deck_archetypes
    WHERE LOWER(archetype_name) = LOWER($1)
  ", params = list(name), default = data.frame(archetype_id = integer()))

  if (nrow(existing) > 0) {
    notify(
      sprintf("Archetype '%s' already exists", name),
      type = "error"
    )
    return()
  }

  # Validate card ID format if provided
  if (!is.null(card_id) && nchar(card_id) > 0) {
    if (!grepl("^[A-Z0-9]+-[0-9]+$", card_id)) {
      show_field_error(session, "selected_card_id")
      notify(
        "Card ID format should be like BT17-042 or EX6-001",
        type = "warning"
      )
    }
  }

  tryCatch({
    safe_execute(db_pool, "
      INSERT INTO deck_archetypes (archetype_name, display_card_id, primary_color, secondary_color, is_multi_color)
      VALUES ($1, $2, $3, $4, $5)
    ", params = list(name, card_id, primary_color, secondary_color, isTRUE(input$deck_multi_color)))

    notify(paste("Added archetype:", name), type = "message")

    # Clear form
    updateTextInput(session, "deck_name", value = "")
    updateSelectInput(session, "deck_primary_color", selected = "Red")
    updateSelectInput(session, "deck_secondary_color", selected = "")
    updateTextInput(session, "selected_card_id", value = "")
    updateTextInput(session, "card_search", value = "")
    updateCheckboxInput(session, "deck_multi_color", value = FALSE)
    output$card_search_results <- renderUI({ NULL })

    # Trigger refresh of public tables
    rv$data_refresh <- (rv$data_refresh %||% 0) + 1

  }, error = function(e) {
    notify(paste("Error:", e$message), type = "error")
  })
})

# Color filter for archetype list
rv$deck_color_filter <- "All"

set_deck_filter <- function(color, input_id) {
  rv$deck_color_filter <- color
  shinyjs::runjs(sprintf(
    "$('.deck-filter-chip').removeClass('active'); $('#%s').addClass('active');",
    input_id
  ))
}

observeEvent(input$deck_filter_all, { set_deck_filter("All", "deck_filter_all") })
observeEvent(input$deck_filter_red, { set_deck_filter("Red", "deck_filter_red") })
observeEvent(input$deck_filter_blue, { set_deck_filter("Blue", "deck_filter_blue") })
observeEvent(input$deck_filter_yellow, { set_deck_filter("Yellow", "deck_filter_yellow") })
observeEvent(input$deck_filter_green, { set_deck_filter("Green", "deck_filter_green") })
observeEvent(input$deck_filter_purple, { set_deck_filter("Purple", "deck_filter_purple") })
observeEvent(input$deck_filter_black, { set_deck_filter("Black", "deck_filter_black") })
observeEvent(input$deck_filter_white, { set_deck_filter("White", "deck_filter_white") })

# Archetype list
output$archetype_list <- renderReactable({

  rv$deck_color_filter

  # Trigger refresh when archetype added/updated/deleted/merged
  input$add_archetype
  input$update_archetype
  input$confirm_delete_archetype
  input$confirm_merge_decks
  # Also refresh when deck requests are approved
  input$deck_request_approve_click
  input$confirm_edit_approve_deck
  rv$data_refresh

  # Sort by Card ID with NULLs first (decks needing review), then alphabetically
  data <- safe_query(db_pool, "
    SELECT archetype_id, archetype_name as \"Deck\", primary_color, secondary_color, is_multi_color, display_card_id as \"Card ID\"
    FROM deck_archetypes
    WHERE is_active = TRUE
    ORDER BY
      CASE WHEN display_card_id IS NULL OR display_card_id = '' THEN 0 ELSE 1 END,
      display_card_id,
      archetype_name
  ")
  # Apply color filter
  color_filter <- rv$deck_color_filter %||% "All"
  if (color_filter != "All") {
    data <- data[data$primary_color == color_filter | (!is.na(data$secondary_color) & data$secondary_color == color_filter), ]
  }

  if (nrow(data) == 0) {
    return(reactable(data.frame(Message = "No archetypes yet"), compact = TRUE))
  }
  reactable(data, compact = TRUE, striped = TRUE, searchable = TRUE,
    highlight = TRUE,
    onClick = JS("function(rowInfo, column) {
      if (rowInfo) {
        Shiny.setInputValue('archetype_list_clicked', {
          archetype_id: rowInfo.row['archetype_id'],
          nonce: Math.random()
        }, {priority: 'event'});
      }
    }"),
    rowStyle = function(index) {
      # Highlight rows without Card ID
      if (is.na(data$`Card ID`[index]) || data$`Card ID`[index] == "") {
        list(cursor = "pointer", backgroundColor = "rgba(247, 148, 29, 0.1)")
      } else {
        list(cursor = "pointer")
      }
    },
    defaultPageSize = 20,
    showPageSizeOptions = TRUE,
    pageSizeOptions = c(10, 20, 50, 100),
    columns = list(
      archetype_id = colDef(show = FALSE),
      Deck = colDef(minWidth = 120),
      primary_color = colDef(
        name = "Color",
        cell = function(value, index) {
          if (isTRUE(data$is_multi_color[index])) {
            span(class = "badge", style = "background-color: #E91E8C; color: white;", "Multi")
          } else {
            secondary <- data$secondary_color[index]
            deck_color_badge_dual(value, secondary)
          }
        }
      ),
      secondary_color = colDef(show = FALSE),
      is_multi_color = colDef(show = FALSE),
      `Card ID` = colDef(
        cell = function(value) {
          if (is.na(value) || value == "") {
            span(class = "badge bg-warning text-dark", "Needs Card")
          } else {
            span(value)
          }
        }
      )
    )
  )
})

# Handle archetype selection for editing
observeEvent(input$archetype_list_clicked, {

  archetype_id <- input$archetype_list_clicked$archetype_id

  if (is.null(archetype_id)) return()

  # Look up archetype directly by ID
  arch <- safe_query(db_pool, "
    SELECT archetype_id, archetype_name, primary_color, secondary_color, display_card_id, is_multi_color
    FROM deck_archetypes
    WHERE archetype_id = $1
  ", params = list(as.integer(archetype_id)), default = data.frame(archetype_id = integer(), archetype_name = character(), primary_color = character(), secondary_color = character(), display_card_id = character(), is_multi_color = logical()))

  if (nrow(arch) == 0) return()

  # Populate form for editing
  updateTextInput(session, "editing_archetype_id", value = as.character(arch$archetype_id))
  updateTextInput(session, "deck_name", value = arch$archetype_name)
  updateSelectInput(session, "deck_primary_color", selected = arch$primary_color)
  updateSelectInput(session, "deck_secondary_color",
                    selected = if (is.na(arch$secondary_color)) "" else arch$secondary_color)
  updateTextInput(session, "selected_card_id",
                  value = if (is.na(arch$display_card_id)) "" else arch$display_card_id)
  updateCheckboxInput(session, "deck_multi_color", value = isTRUE(arch$is_multi_color))

  # Show/hide buttons
  shinyjs::hide("add_archetype")
  shinyjs::show("update_archetype")
  shinyjs::show("delete_archetype")

  notify(sprintf("Editing: %s", arch$archetype_name), type = "message", duration = 2)
})

# Update archetype
observeEvent(input$update_archetype, {
  req(rv$is_superadmin, db_pool)
  req(input$editing_archetype_id)

  clear_all_field_errors(session)

  archetype_id <- as.integer(input$editing_archetype_id)
  name <- trimws(input$deck_name)
  primary_color <- input$deck_primary_color
  secondary_color <- if (input$deck_secondary_color == "") NA_character_ else input$deck_secondary_color
  card_id <- if (!is.null(input$selected_card_id) && nchar(input$selected_card_id) > 0) input$selected_card_id else NA_character_

  if (is.null(name) || nchar(name) == 0) {
    show_field_error(session, "deck_name")
    notify("Please enter an archetype name", type = "error")
    return()
  }

  tryCatch({
    safe_execute(db_pool, "
      UPDATE deck_archetypes
      SET archetype_name = $1, primary_color = $2, secondary_color = $3, display_card_id = $4, is_multi_color = $5,
          updated_at = CURRENT_TIMESTAMP, updated_by = $6
      WHERE archetype_id = $7
    ", params = list(name, primary_color, secondary_color, card_id, isTRUE(input$deck_multi_color), current_admin_username(rv), archetype_id))

    notify(sprintf("Updated archetype: %s", name), type = "message")

    # Clear form and reset to add mode
    updateTextInput(session, "editing_archetype_id", value = "")
    updateTextInput(session, "deck_name", value = "")
    updateSelectInput(session, "deck_primary_color", selected = "Red")
    updateSelectInput(session, "deck_secondary_color", selected = "")
    updateTextInput(session, "selected_card_id", value = "")
    updateTextInput(session, "card_search", value = "")
    updateCheckboxInput(session, "deck_multi_color", value = FALSE)
    output$card_search_results <- renderUI({ NULL })

    shinyjs::show("add_archetype")
    shinyjs::hide("update_archetype")
    shinyjs::hide("delete_archetype")

    # Trigger refresh of public tables
    rv$data_refresh <- (rv$data_refresh %||% 0) + 1

  }, error = function(e) {
    notify(paste("Error:", e$message), type = "error")
  })
})

# Cancel edit archetype
observeEvent(input$cancel_edit_archetype, {
  updateTextInput(session, "editing_archetype_id", value = "")
  updateTextInput(session, "deck_name", value = "")
  updateSelectInput(session, "deck_primary_color", selected = "Red")
  updateSelectInput(session, "deck_secondary_color", selected = "")
  updateTextInput(session, "selected_card_id", value = "")
  updateTextInput(session, "card_search", value = "")
  updateCheckboxInput(session, "deck_multi_color", value = FALSE)
  output$card_search_results <- renderUI({ NULL })

  shinyjs::show("add_archetype")
  shinyjs::hide("update_archetype")
  shinyjs::hide("delete_archetype")
})

# Check if archetype can be deleted (no related results)
observe({
  req(input$editing_archetype_id, db_pool)
  archetype_id <- as.integer(input$editing_archetype_id)

  count <- safe_query(db_pool, "
    SELECT COUNT(*) as cnt FROM results WHERE archetype_id = $1
  ", params = list(archetype_id), default = data.frame(cnt = 0L))$cnt

  rv$archetype_result_count <- count
  rv$can_delete_archetype <- count == 0
})

# Delete button click - show modal
observeEvent(input$delete_archetype, {
  req(rv$is_superadmin, input$editing_archetype_id)

  archetype_id <- as.integer(input$editing_archetype_id)
  arch <- safe_query(db_pool, "SELECT archetype_name FROM deck_archetypes WHERE archetype_id = $1",
                     params = list(archetype_id), default = data.frame(archetype_name = character()))

  if (rv$can_delete_archetype) {
    showModal(modalDialog(
      title = "Confirm Delete",
      div(
        p(sprintf("Are you sure you want to delete '%s'?", arch$archetype_name)),
        p(class = "text-danger", "This action cannot be undone.")
      ),
      footer = tagList(
        actionButton("confirm_delete_archetype", "Delete", class = "btn-danger"),
        modalButton("Cancel")
      ),
      easyClose = TRUE
    ))
  } else {
    notify(
      sprintf("Cannot delete: used in %d result(s)", as.integer(rv$archetype_result_count)),
      type = "error"
    )
  }
})

# Confirm delete
observeEvent(input$confirm_delete_archetype, {
  req(rv$is_superadmin, db_pool, input$editing_archetype_id)
  archetype_id <- as.integer(input$editing_archetype_id)

  # Re-check for referential integrity before delete
  count <- safe_query(db_pool, "
    SELECT COUNT(*) as cnt FROM results WHERE archetype_id = $1
  ", params = list(archetype_id), default = data.frame(cnt = 0L))$cnt

  if (count > 0) {
    removeModal()
    notify(sprintf("Cannot delete: used in %d result(s)", as.integer(count)), type = "error")
    return()
  }

  tryCatch({
    safe_execute(db_pool, "DELETE FROM deck_archetypes WHERE archetype_id = $1",
              params = list(archetype_id))
    notify("Archetype deleted", type = "message")

    # Hide modal and reset form
    removeModal()

    # Clear form
    updateTextInput(session, "editing_archetype_id", value = "")
    updateTextInput(session, "deck_name", value = "")
    updateSelectInput(session, "deck_primary_color", selected = "Red")
    updateSelectInput(session, "deck_secondary_color", selected = "")
    updateTextInput(session, "selected_card_id", value = "")
    updateTextInput(session, "card_search", value = "")
    updateCheckboxInput(session, "deck_multi_color", value = FALSE)
    output$card_search_results <- renderUI({ NULL })

    shinyjs::show("add_archetype")
    shinyjs::hide("update_archetype")
    shinyjs::hide("delete_archetype")

    # Trigger refresh of public tables
    rv$data_refresh <- (rv$data_refresh %||% 0) + 1

  }, error = function(e) {
    notify(paste("Error:", e$message), type = "error")
  })
})

# =============================================================================
# Pending Deck Requests Section
# =============================================================================

# Initialize refresh trigger
rv$deck_requests_refresh <- NULL
rv$editing_deck_request_id <- NULL
rv$rejecting_deck_request_id <- NULL

# Render pending deck requests section
output$deck_requests_section <- renderUI({



  # Trigger refresh after approve/reject actions
  rv$deck_requests_refresh
  input$deck_request_approve_click
  input$confirm_edit_approve_deck
  input$confirm_reject_deck

  pending <- tryCatch({
    safe_query(db_pool, "
      SELECT request_id, deck_name, primary_color, secondary_color, display_card_id,
             submitted_at, status, suggested_archetype_name, decklist_json, source, result_id
      FROM deck_requests
      WHERE status IN ('pending', 'needs_classification')
      ORDER BY submitted_at DESC
    ")
  }, error = function(e) {
    data.frame()
  })

  if (nrow(pending) == 0) {
    return(NULL)  # Don't show section if no pending requests
  }

  # Count by status for header
  pending_count <- sum(pending$status == "pending")
  needs_class_count <- sum(pending$status == "needs_classification")

  # Collapsible card with pending requests
  card(
    class = "mb-3 border-warning",
    card_header(
      class = "bg-warning-subtle d-flex justify-content-between align-items-center",
      div(
        bsicons::bs_icon("exclamation-triangle-fill", class = "text-warning me-2"),
        tags$strong(sprintf("Deck Requests (%d)", nrow(pending))),
        if (needs_class_count > 0) {
          tags$span(class = "badge bg-info ms-2", sprintf("%d need classification", needs_class_count))
        }
      ),
      tags$small(class = "text-muted", "Review and approve new deck submissions")
    ),
    card_body(
      class = "p-2",
      lapply(seq_len(nrow(pending)), function(i) {
        req <- pending[i, ]
        color_display <- if (!is.na(req$secondary_color) && req$secondary_color != "") {
          paste(req$primary_color, "/", req$secondary_color)
        } else {
          req$primary_color
        }

        # Source badge
        source_badge <- if (!is.na(req$source) && req$source != "manual") {
          source_class <- switch(req$source,
            "classification" = "bg-info",
            "limitless_sync" = "bg-primary",
            "bg-secondary"
          )
          tags$span(class = paste("badge", source_class, "ms-2"), req$source)
        }

        # Suggested archetype indicator
        suggested_info <- if (!is.na(req$suggested_archetype_name) && req$suggested_archetype_name != "") {
          tags$span(class = "text-info ms-2",
            bsicons::bs_icon("lightbulb", class = "me-1"),
            paste("Suggested:", req$suggested_archetype_name)
          )
        }

        # Decklist indicator
        has_decklist <- !is.na(req$decklist_json) && nchar(req$decklist_json) > 2

        # Status badge for needs_classification
        status_badge <- if (req$status == "needs_classification") {
          tags$span(class = "badge bg-warning text-dark ms-2", "Needs Classification")
        }

        div(
          class = "d-flex justify-content-between align-items-center p-2 border-bottom",
          div(
            div(
              class = "d-flex align-items-center flex-wrap",
              tags$strong(req$deck_name),
              tags$span(class = "text-muted ms-2", paste0("(", color_display, ")")),
              if (!is.na(req$display_card_id) && req$display_card_id != "") {
                tags$span(class = "badge bg-secondary ms-2", req$display_card_id)
              },
              source_badge,
              status_badge
            ),
            div(
              class = "mt-1",
              suggested_info,
              tags$small(class = "text-muted", paste("Requested:", format(as.Date(req$submitted_at), "%b %d, %Y")))
            )
          ),
          div(
            class = "d-flex gap-2 flex-wrap",
            if (has_decklist) {
              tags$button(
                type = "button",
                class = "btn btn-sm btn-outline-secondary",
                onclick = sprintf("Shiny.setInputValue('deck_request_view_decklist', %d, {priority: 'event'})", req$request_id),
                bsicons::bs_icon("list-ul"), " View Decklist"
              )
            },
            tags$button(
              type = "button",
              class = "btn btn-sm btn-success",
              onclick = sprintf("Shiny.setInputValue('deck_request_approve_click', %d, {priority: 'event'})", req$request_id),
              "Approve"
            ),
            tags$button(
              type = "button",
              class = "btn btn-sm btn-outline-primary",
              onclick = sprintf("Shiny.setInputValue('deck_request_edit_click', %d, {priority: 'event'})", req$request_id),
              "Edit & Approve"
            ),
            tags$button(
              type = "button",
              class = "btn btn-sm btn-outline-danger",
              onclick = sprintf("Shiny.setInputValue('deck_request_reject_click', %d, {priority: 'event'})", req$request_id),
              "Reject"
            )
          )
        )
      })
    )
  )
})

# Handle approve button clicks (using Shiny.setInputValue from onclick)
observeEvent(input$deck_request_approve_click, {
  req(db_pool, rv$is_superadmin)
  req_id <- input$deck_request_approve_click
  approve_deck_request(req_id, session, rv)
})

# Handle view decklist button clicks
observeEvent(input$deck_request_view_decklist, {
  req(db_pool, rv$is_superadmin)
  req_id <- input$deck_request_view_decklist

  req_data <- safe_query(db_pool, "SELECT deck_name, decklist_json, suggested_archetype_name FROM deck_requests WHERE request_id = $1",
                         params = list(req_id), default = data.frame(deck_name = character(), decklist_json = character(), suggested_archetype_name = character()))
  if (nrow(req_data) == 0 || is.na(req_data$decklist_json[1])) return()

  # Parse the decklist JSON
  decklist <- tryCatch({
    jsonlite::fromJSON(req_data$decklist_json[1])
  }, error = function(e) {
    NULL
  })

  if (is.null(decklist)) {
    showNotification("Could not parse decklist", type = "error")
    return()
  }

  # Helper to render card list
  render_card_list <- function(cards, category_name) {
    if (is.null(cards) || length(cards) == 0) return(NULL)
    tags$div(
      class = "mb-3",
      tags$h6(class = "text-muted border-bottom pb-1", category_name),
      tags$ul(
        class = "list-unstyled mb-0",
        lapply(seq_len(nrow(cards)), function(i) {
          card <- cards[i, ]
          tags$li(
            class = "d-flex justify-content-between py-1",
            tags$span(card$name),
            tags$span(class = "badge bg-secondary", paste0(card$count, "x"))
          )
        })
      )
    )
  }

  showModal(modalDialog(
    title = paste("Decklist:", req_data$deck_name[1]),
    if (!is.na(req_data$suggested_archetype_name[1]) && req_data$suggested_archetype_name[1] != "") {
      div(
        class = "alert alert-info",
        bsicons::bs_icon("lightbulb", class = "me-2"),
        tags$strong("Classification suggested: "), req_data$suggested_archetype_name[1]
      )
    },
    div(
      class = "decklist-view",
      style = "max-height: 400px; overflow-y: auto;",
      render_card_list(decklist$egg, "Digi-Eggs"),
      render_card_list(decklist$digimon, "Digimon"),
      render_card_list(decklist$tamer, "Tamers"),
      render_card_list(decklist$option, "Options")
    ),
    footer = modalButton("Close"),
    size = "m",
    easyClose = TRUE
  ))
})

# Handle edit & approve button clicks
observeEvent(input$deck_request_edit_click, {
  req(db_pool, rv$is_superadmin)
  req_id <- input$deck_request_edit_click

  req_data <- safe_query(db_pool, "SELECT * FROM deck_requests WHERE request_id = $1",
                         params = list(req_id))
  if (nrow(req_data) == 0) return()
  req_data <- req_data[1, ]

  rv$editing_deck_request_id <- req_id

  # Use suggested archetype name as default if deck_name is auto-generated
  default_name <- req_data$deck_name
  if (grepl("^\\[Auto\\]", default_name) && !is.na(req_data$suggested_archetype_name) && req_data$suggested_archetype_name != "") {
    default_name <- req_data$suggested_archetype_name
  }

  # Check for existing decks to offer as alternatives
  existing_decks <- safe_query(db_pool, "
    SELECT archetype_id, archetype_name FROM deck_archetypes
    WHERE is_active = TRUE
    ORDER BY archetype_name
  ", default = data.frame(archetype_id = integer(), archetype_name = character()))
  deck_choices <- c("Create New Archetype" = "", setNames(existing_decks$archetype_id, existing_decks$archetype_name))

  showModal(modalDialog(
    title = "Edit & Approve Deck Request",
    if (!is.na(req_data$suggested_archetype_name) && req_data$suggested_archetype_name != "") {
      div(
        class = "alert alert-info mb-3",
        bsicons::bs_icon("lightbulb", class = "me-2"),
        tags$strong("Classification suggested: "), req_data$suggested_archetype_name
      )
    },
    selectInput("edit_deck_request_existing", "Assign to Existing Archetype",
                choices = deck_choices,
                selectize = FALSE),
    tags$hr(),
    tags$p(class = "text-muted small", "Or create a new archetype:"),
    textInput("edit_deck_request_name", "Deck Name", value = default_name),
    layout_columns(
      col_widths = c(6, 6),
      class = "deck-request-colors",
      selectInput("edit_deck_request_color", "Primary Color",
                  choices = c("Red", "Blue", "Yellow", "Green", "Purple", "Black", "White"),
                  selected = req_data$primary_color,
                  selectize = FALSE),
      selectInput("edit_deck_request_color2", "Secondary Color",
                  choices = c("None" = "", "Red", "Blue", "Yellow", "Green", "Purple", "Black", "White"),
                  selected = if (!is.na(req_data$secondary_color)) req_data$secondary_color else "",
                  selectize = FALSE)
    ),
    textInput("edit_deck_request_card_id", "Card ID",
              value = if (!is.na(req_data$display_card_id)) req_data$display_card_id else ""),
    footer = tagList(
      modalButton("Cancel"),
      actionButton("confirm_edit_approve_deck", "Approve", class = "btn-success")
    ),
    size = "m",
    easyClose = TRUE
  ))
})

# Handle confirm edit & approve
observeEvent(input$confirm_edit_approve_deck, {
  req(db_pool, rv$is_superadmin, rv$editing_deck_request_id)

  req_id <- rv$editing_deck_request_id
  existing_archetype_id <- input$edit_deck_request_existing

  # Check if user selected an existing archetype
  if (!is.null(existing_archetype_id) && existing_archetype_id != "") {
    # Assign to existing archetype instead of creating new one
    assign_request_to_existing_archetype(req_id, as.integer(existing_archetype_id), session, rv)
  } else {
    # Create new archetype
    deck_name <- trimws(input$edit_deck_request_name)
    primary_color <- input$edit_deck_request_color
    secondary_color <- if (!is.null(input$edit_deck_request_color2) && input$edit_deck_request_color2 != "") {
      input$edit_deck_request_color2
    } else {
      NA_character_
    }
    card_id <- if (!is.null(input$edit_deck_request_card_id) && trimws(input$edit_deck_request_card_id) != "") {
      trimws(input$edit_deck_request_card_id)
    } else {
      NA_character_
    }

    create_deck_from_request(req_id, deck_name, primary_color, secondary_color, card_id, session, rv)
  }

  removeModal()
  rv$editing_deck_request_id <- NULL
})

# Handle reject button clicks - show modal to select replacement deck
observeEvent(input$deck_request_reject_click, {
  req(db_pool, rv$is_superadmin)
  req_id <- input$deck_request_reject_click

  req_data <- safe_query(db_pool, "SELECT * FROM deck_requests WHERE request_id = $1",
                         params = list(req_id))
  if (nrow(req_data) == 0) return()
  req_data <- req_data[1, ]

  rv$rejecting_deck_request_id <- req_id

  # Get existing decks for dropdown
  decks <- safe_query(db_pool, "
    SELECT archetype_id, archetype_name FROM deck_archetypes
    WHERE is_active = TRUE
    ORDER BY archetype_name
  ", default = data.frame(archetype_id = integer(), archetype_name = character()))
  deck_choices <- setNames(decks$archetype_id, decks$archetype_name)

  # Count how many results use this pending request
  result_count <- safe_query(db_pool, "
    SELECT COUNT(*) as cnt FROM results WHERE pending_deck_request_id = $1
  ", params = list(req_id), default = data.frame(cnt = 0L))$cnt

  showModal(modalDialog(
    title = "Reject Deck Request",
    div(
      class = "alert alert-warning",
      bsicons::bs_icon("exclamation-triangle-fill", class = "me-2"),
      sprintf("Rejecting request for '%s'", req_data$deck_name)
    ),
    if (result_count > 0) {
      div(
        p(sprintf("This deck is used in %d result(s). Select an existing deck to assign them to:", as.integer(result_count))),
        selectInput("reject_replacement_deck", "Replace with:",
                    choices = c("Unknown" = "", deck_choices),
                    selectize = FALSE)
      )
    } else {
      p(class = "text-muted", "No results are using this pending deck.")
    },
    footer = tagList(
      modalButton("Cancel"),
      actionButton("confirm_reject_deck", "Reject", class = "btn-danger")
    ),
    size = "m",
    easyClose = TRUE
  ))
})

# Handle confirm reject
observeEvent(input$confirm_reject_deck, {
  req(db_pool, rv$is_superadmin, rv$rejecting_deck_request_id)

  req_id <- rv$rejecting_deck_request_id
  replacement_id <- if (!is.null(input$reject_replacement_deck) && input$reject_replacement_deck != "") {
    as.integer(input$reject_replacement_deck)
  } else {
    NULL
  }

  reject_deck_request(req_id, replacement_id, session, rv)
  removeModal()
  rv$rejecting_deck_request_id <- NULL
})

# Helper function to approve a deck request (uses original values)
approve_deck_request <- function(req_id, session, rv) {
  req_data <- safe_query(db_pool, "SELECT * FROM deck_requests WHERE request_id = $1",
                         params = list(req_id))
  if (nrow(req_data) == 0) {
    notify("Request not found", type = "error")
    return()
  }
  req_data <- req_data[1, ]

  create_deck_from_request(
    req_id,
    req_data$deck_name,
    req_data$primary_color,
    req_data$secondary_color,
    req_data$display_card_id,
    session, rv
  )
}

# Helper function to assign a deck request to an existing archetype
assign_request_to_existing_archetype <- function(req_id, archetype_id, session, rv) {
  # Get archetype name for message
  archetype_name <- safe_query(db_pool, "SELECT archetype_name FROM deck_archetypes WHERE archetype_id = $1",
                               params = list(archetype_id), default = data.frame(archetype_name = character()))$archetype_name[1]

  tryCatch({
    # Update the deck request
    safe_execute(db_pool, "
      UPDATE deck_requests
      SET status = 'approved', approved_archetype_id = $1, reviewed_at = CURRENT_TIMESTAMP
      WHERE request_id = $2
    ", params = list(archetype_id, req_id))

    # Auto-update any results that used this pending request
    updated_count <- safe_execute(db_pool, "
      UPDATE results
      SET archetype_id = $1, pending_deck_request_id = NULL
      WHERE pending_deck_request_id = $2
    ", params = list(archetype_id, req_id))

    msg <- sprintf("Assigned to '%s'", archetype_name)
    if (updated_count > 0) {
      msg <- paste0(msg, sprintf(" and updated %d result(s)", as.integer(updated_count)))
    }
    notify(msg, type = "message")

    rv$decks_refresh <- Sys.time()
    rv$deck_requests_refresh <- Sys.time()

  }, error = function(e) {
    notify(paste("Error assigning archetype:", e$message), type = "error")
  })
}

# Helper function to create deck and update request/results
create_deck_from_request <- function(req_id, deck_name, primary_color, secondary_color, card_id, session, rv) {
  # Check if deck already exists
  existing <- safe_query(db_pool, "
    SELECT archetype_id FROM deck_archetypes WHERE LOWER(archetype_name) = LOWER($1)
  ", params = list(deck_name), default = data.frame(archetype_id = integer()))

  if (nrow(existing) > 0) {
    notify(paste0("Deck '", deck_name, "' already exists"), type = "warning")
    return()
  }

  tryCatch({
    # Create new archetype
    archetype_result <- safe_query(db_pool, "
      INSERT INTO deck_archetypes (archetype_name, primary_color, secondary_color, display_card_id)
      VALUES ($1, $2, $3, $4)
      RETURNING archetype_id
    ", params = list(deck_name, primary_color, secondary_color, card_id),
       default = data.frame())
    new_archetype_id <- archetype_result$archetype_id[1]

    # Update the deck request
    safe_execute(db_pool, "
      UPDATE deck_requests
      SET status = 'approved', approved_archetype_id = $1, reviewed_at = CURRENT_TIMESTAMP
      WHERE request_id = $2
    ", params = list(new_archetype_id, req_id))

    # Auto-update any results that used this pending request
    updated_count <- safe_execute(db_pool, "
      UPDATE results
      SET archetype_id = $1, pending_deck_request_id = NULL
      WHERE pending_deck_request_id = $2
    ", params = list(new_archetype_id, req_id))

    msg <- sprintf("Approved '%s'", deck_name)
    if (updated_count > 0) {
      msg <- paste0(msg, sprintf(" and updated %d result(s)", as.integer(updated_count)))
    }
    notify(msg, type = "message")

    # Remind admin to set card image if not provided
    if (is.na(card_id) || card_id == "") {
      notify(
        "Remember to set a card image in the deck table below (decks without images are highlighted).",
        type = "warning",
        duration = 8
      )
    }

    # Refresh
    rv$deck_requests_refresh <- Sys.time()
    rv$data_refresh <- (rv$data_refresh %||% 0) + 1

  }, error = function(e) {
    notify(paste("Error approving deck:", e$message), type = "error")
  })
}

# Helper function to reject a deck request
# replacement_archetype_id: ID of deck to assign results to, or NULL for UNKNOWN
reject_deck_request <- function(req_id, replacement_archetype_id, session, rv) {
  tryCatch({
    req_data <- safe_query(db_pool, "SELECT deck_name FROM deck_requests WHERE request_id = $1",
                           params = list(req_id), default = data.frame(deck_name = character()))

    safe_execute(db_pool, "
      UPDATE deck_requests SET status = 'rejected', reviewed_at = CURRENT_TIMESTAMP WHERE request_id = $1
    ", params = list(req_id))

    # Determine replacement deck ID
    if (is.null(replacement_archetype_id)) {
      # Fall back to UNKNOWN
      unknown_result <- safe_query(db_pool, "SELECT archetype_id FROM deck_archetypes WHERE archetype_name = 'UNKNOWN'", default = data.frame(archetype_id = integer()))
      if (nrow(unknown_result) > 0) {
        replacement_archetype_id <- unknown_result$archetype_id[1]
      }
    }

    # Update any results that used this pending request
    updated_count <- 0
    if (!is.null(replacement_archetype_id)) {
      updated_count <- safe_execute(db_pool, "
        UPDATE results SET archetype_id = $1, pending_deck_request_id = NULL WHERE pending_deck_request_id = $2
      ", params = list(replacement_archetype_id, req_id))
    }

    # Build notification message
    msg <- sprintf("Rejected request for '%s'", req_data$deck_name[1])
    if (updated_count > 0) {
      # Get replacement deck name for message
      replacement_name <- safe_query(db_pool, "SELECT archetype_name FROM deck_archetypes WHERE archetype_id = $1",
                                     params = list(replacement_archetype_id), default = data.frame(archetype_name = character()))$archetype_name[1]
      msg <- paste0(msg, sprintf(" - %d result(s) reassigned to '%s'", as.integer(updated_count), replacement_name))
    }
    notify(msg, type = "message")
    rv$deck_requests_refresh <- Sys.time()
    rv$data_refresh <- (rv$data_refresh %||% 0) + 1

  }, error = function(e) {
    notify(paste("Error rejecting request:", e$message), type = "error")
  })
}

# =============================================================================
# Merge Deck Archetypes
# =============================================================================

# Helper function to get deck choices for merge dropdowns
get_deck_choices <- function(con) {
  decks <- safe_query(con, "
    SELECT archetype_id, archetype_name, primary_color,
           (SELECT COUNT(*) FROM results WHERE archetype_id = da.archetype_id) as result_count
    FROM deck_archetypes da
    WHERE is_active = TRUE
    ORDER BY archetype_name
  ")
  if (nrow(decks) == 0) return(c())
  # Format: "Deck Name (Color) - X results"
  labels <- sprintf("%s (%s) - %d results", decks$archetype_name, decks$primary_color, as.integer(decks$result_count))
  setNames(decks$archetype_id, labels)
}

# Show merge modal - populate choices when modal opens
observeEvent(input$show_merge_deck_modal, {
  # Fetch deck choices when modal opens
  deck_choices <- get_deck_choices(db_pool)

  showModal(modalDialog(
    title = tagList(bsicons::bs_icon("arrow-left-right"), " Merge Deck Archetypes"),
    p("Merge two deck archetypes into one. The source deck will be deleted and all its results will be reassigned to the target deck."),
    selectizeInput("merge_source_deck", "Source Deck (will be deleted)",
                   choices = deck_choices,
                   options = list(placeholder = "Select deck to merge away...")),
    selectizeInput("merge_target_deck", "Target Deck (will keep)",
                   choices = deck_choices,
                   options = list(placeholder = "Select deck to keep...")),
    hr(),
    uiOutput("merge_deck_preview"),
    footer = tagList(
      actionButton("confirm_merge_decks", "Merge Decks", class = "btn-warning"),
      modalButton("Cancel")
    ),
    size = "m",
    easyClose = TRUE
  ))
})

# Preview merge impact
output$merge_deck_preview <- renderUI({


  source_id <- input$merge_source_deck
  target_id <- input$merge_target_deck

  if (is.null(source_id) || source_id == "" || is.null(target_id) || target_id == "") {
    return(div(class = "text-muted", "Select both decks to see merge preview"))
  }

  source_id <- as.integer(source_id)
  target_id <- as.integer(target_id)

  if (source_id == target_id) {
    return(div(class = "alert alert-danger", "Source and target must be different decks"))
  }

  # Get deck info
  source_deck <- safe_query(db_pool, "SELECT archetype_name FROM deck_archetypes WHERE archetype_id = $1",
                            params = list(source_id), default = data.frame(archetype_name = character()))
  target_deck <- safe_query(db_pool, "SELECT archetype_name FROM deck_archetypes WHERE archetype_id = $1",
                            params = list(target_id), default = data.frame(archetype_name = character()))

  # Count results to be moved
  source_results <- safe_query(db_pool, "SELECT COUNT(*) as cnt FROM results WHERE archetype_id = $1",
                               params = list(source_id), default = data.frame(cnt = 0L))$cnt

  # Count limitless mappings to be updated
  limitless_mappings <- safe_query(db_pool, "SELECT COUNT(*) as cnt FROM limitless_deck_map WHERE archetype_id = $1",
                                   params = list(source_id), default = data.frame(cnt = 0L))$cnt

  div(
    div(class = "alert alert-warning",
        tags$strong("Merge Preview:"),
        tags$ul(
          tags$li(sprintf("Source: %s", source_deck$archetype_name)),
          tags$li(sprintf("Target: %s", target_deck$archetype_name)),
          tags$li(sprintf("%d result(s) will be reassigned", as.integer(source_results))),
          if (limitless_mappings > 0) tags$li(sprintf("%d Limitless mapping(s) will be updated", as.integer(limitless_mappings)))
        )
    ),
    if (source_results > 0) {
      div(class = "alert alert-info",
          bsicons::bs_icon("info-circle"),
          sprintf(" All %d results currently assigned to '%s' will be moved to '%s'.",
                  as.integer(source_results), source_deck$archetype_name, target_deck$archetype_name))
    }
  )
})

# Confirm merge
observeEvent(input$confirm_merge_decks, {
  req(rv$is_superadmin, db_pool)
  req(input$merge_source_deck, input$merge_target_deck)

  source_id <- as.integer(input$merge_source_deck)
  target_id <- as.integer(input$merge_target_deck)

  if (source_id == target_id) {
    notify("Source and target must be different", type = "error")
    return()
  }

  # Get deck names for notification
  source_name <- safe_query(db_pool, "SELECT archetype_name FROM deck_archetypes WHERE archetype_id = $1",
                            params = list(source_id), default = data.frame(archetype_name = character()))$archetype_name
  target_name <- safe_query(db_pool, "SELECT archetype_name FROM deck_archetypes WHERE archetype_id = $1",
                            params = list(target_id), default = data.frame(archetype_name = character()))$archetype_name

  tryCatch({
    # 1. Move all results from source to target
    results_moved <- safe_execute(db_pool, "
      UPDATE results SET archetype_id = $1 WHERE archetype_id = $2
    ", params = list(target_id, source_id))

    # 2. Update limitless_deck_map entries to point to target
    mappings_updated <- safe_execute(db_pool, "
      UPDATE limitless_deck_map SET archetype_id = $1 WHERE archetype_id = $2
    ", params = list(target_id, source_id))

    # 3. Delete the source archetype
    safe_execute(db_pool, "DELETE FROM deck_archetypes WHERE archetype_id = $1",
                 params = list(source_id))

    # Hide modal
    removeModal()

    # Clear selections
    updateSelectizeInput(session, "merge_source_deck", selected = "")
    updateSelectizeInput(session, "merge_target_deck", selected = "")

    # Show success notification
    msg <- sprintf("Merged '%s' into '%s': %d result(s) moved", source_name, target_name, as.integer(results_moved))
    if (mappings_updated > 0) {
      msg <- paste0(msg, sprintf(", %d mapping(s) updated", as.integer(mappings_updated)))
    }
    notify(msg, type = "message", duration = 5)

    # Refresh data
    rv$data_refresh <- (rv$data_refresh %||% 0) + 1

  }, error = function(e) {
    notify(paste("Error merging decks:", e$message), type = "error")
  })
})
