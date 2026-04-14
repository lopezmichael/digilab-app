# =============================================================================
# Admin: Archetype Families Server Logic
# =============================================================================

# ---------------------------------------------------------------------------
# Slug Helper
# ---------------------------------------------------------------------------

#' Generate unique family slug, appending suffix if needed
#' @param db_pool Database connection pool
#' @param text Family name to slugify
#' @param exclude_family_id Family ID to exclude from uniqueness check (for updates)
#' @return Unique slug string, or NA if text is empty
generate_unique_family_slug <- function(db_pool, text, exclude_family_id = NULL) {
  base_slug <- generate_slug(text)
  if (is.na(base_slug)) return(NA_character_)

  if (!is.null(exclude_family_id)) {
    existing <- safe_query(db_pool,
      "SELECT COUNT(*) as n FROM archetype_families WHERE slug = $1 AND family_id != $2",
      params = list(base_slug, as.integer(exclude_family_id)), default = data.frame(n = 1))
  } else {
    existing <- safe_query(db_pool,
      "SELECT COUNT(*) as n FROM archetype_families WHERE slug = $1",
      params = list(base_slug), default = data.frame(n = 1))
  }

  if (existing$n[1] == 0) return(base_slug)

  for (i in 2:100) {
    candidate <- paste0(base_slug, "-", i)
    check <- safe_query(db_pool,
      "SELECT COUNT(*) as n FROM archetype_families WHERE slug = $1",
      params = list(candidate), default = data.frame(n = 1))
    if (check$n[1] == 0) return(candidate)
  }

  return(paste0(base_slug, "-", as.integer(Sys.time())))
}

# ---------------------------------------------------------------------------
# Family Card Search
# ---------------------------------------------------------------------------

observeEvent(input$search_family_card_btn, {
  req(input$family_card_search)

  # Reset pagination
  rv$family_card_search_page <- 1

  # Show searching indicator
  output$family_card_search_results <- renderUI({
    div(class = "text-muted", bsicons::bs_icon("hourglass-split"), " Searching...")
  })

  cards <- tryCatch({
    search_cards_local(db_pool, input$family_card_search)
  }, error = function(e) {
    if (sentry_enabled) tryCatch(sentryR::capture_exception(e, tags = sentry_context_tags()), error = function(se) NULL)
    message("Family card search error: ", e$message)
    NULL
  })

  if (is.null(cards) || nrow(cards) == 0) {
    output$family_card_search_results <- renderUI({
      div(class = "alert alert-warning", "No cards found for '", input$family_card_search, "'")
    })
    rv$family_card_search_results <- NULL
    return()
  }

  # Deduplicate by card ID (removes duplicate listings of same card)
  cards <- cards[!duplicated(cards$id), ]

  # Store ALL cards in reactive for pagination
  rv$family_card_search_results <- cards

  # Render first page
  render_family_card_search_page()
})

# Pagination handlers
observeEvent(input$family_card_search_prev, {
  if (rv$family_card_search_page > 1) {
    rv$family_card_search_page <- rv$family_card_search_page - 1
    render_family_card_search_page()
  }
})

observeEvent(input$family_card_search_next, {
  req(rv$family_card_search_results)
  total_pages <- ceiling(nrow(rv$family_card_search_results) / 8)
  if (rv$family_card_search_page < total_pages) {
    rv$family_card_search_page <- rv$family_card_search_page + 1
    render_family_card_search_page()
  }
})

# Helper function to render family card search page
render_family_card_search_page <- function() {
  req(rv$family_card_search_results)
  cards <- rv$family_card_search_results
  page <- rv$family_card_search_page
  per_page <- 8

  total_cards <- nrow(cards)
  total_pages <- ceiling(total_cards / per_page)
  start_idx <- (page - 1) * per_page + 1
  end_idx <- min(page * per_page, total_cards)

  # Get cards for current page
  page_cards <- cards[start_idx:end_idx, ]

  output$family_card_search_results <- renderUI({
    div(
      # Header with count and pagination
      div(
        class = "d-flex justify-content-between align-items-center mb-2",
        p(class = "text-muted small mb-0", sprintf("Found %d cards (showing %d-%d):", total_cards, start_idx, end_idx)),
        if (total_pages > 1) {
          div(
            class = "d-flex align-items-center gap-1",
            actionButton("family_card_search_prev", bsicons::bs_icon("chevron-left"),
                         class = paste("btn-sm btn-outline-secondary card-search-pagination", if (page == 1) "disabled" else "")),
            span(class = "small mx-1", sprintf("%d/%d", page, total_pages)),
            actionButton("family_card_search_next", bsicons::bs_icon("chevron-right"),
                         class = paste("btn-sm btn-outline-secondary card-search-pagination", if (page == total_pages) "disabled" else ""))
          )
        }
      ),
      # Card grid
      div(
        class = "card-search-grid",
        lapply(1:nrow(page_cards), function(i) {
          card_data <- page_cards[i, ]
          abs_idx <- start_idx + i - 1
          card_num <- if ("id" %in% names(card_data)) card_data$id else card_data$cardnumber
          card_name <- if ("name" %in% names(card_data)) card_data$name else "Unknown"
          card_color <- if ("color" %in% names(card_data) && !is.na(card_data$color)) card_data$color else ""

          # Use .webp format - server returns WebP regardless of extension
          img_url <- paste0("https://images.digimoncard.io/images/cards/", card_num, ".webp")

          actionButton(
            inputId = paste0("family_card_select_", abs_idx),
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

# Handle family card selection buttons (1-100 to support pagination)
lapply(1:100, function(i) {
  observeEvent(input[[paste0("family_card_select_", i)]], {
    req(rv$family_card_search_results)
    if (i <= nrow(rv$family_card_search_results)) {
      card_num <- if ("id" %in% names(rv$family_card_search_results)) {
        rv$family_card_search_results$id[i]
      } else {
        rv$family_card_search_results$cardnumber[i]
      }
      updateTextInput(session, "family_selected_card_id", value = card_num)
      notify(paste("Selected:", card_num), type = "message", duration = 2)
    }
  }, ignoreInit = TRUE)
})

# Preview selected family card
output$family_selected_card_preview <- renderUI({
  card_id <- trimws(input$family_selected_card_id %||% "")

  if (nchar(card_id) < 3) {
    return(div(
      class = "text-muted",
      style = "font-size: 0.85rem;",
      bsicons::bs_icon("image", size = "2rem"),
      div(class = "mt-2", "No card selected")
    ))
  }

  img_url <- paste0("https://images.digimoncard.io/images/cards/", card_id, ".webp")

  div(
    class = "text-center",
    tags$img(src = img_url, class = "deck-modal-image",
             onerror = "this.onerror=null; this.src=''; this.alt='Image not found'; this.style.height='60px'; this.style.background='#ddd';"),
    div(class = "mt-1 small text-muted", paste("Selected:", card_id))
  )
})

# ---------------------------------------------------------------------------
# Family count text
# ---------------------------------------------------------------------------

output$family_count_text <- renderText({
  rv$refresh_decks
  count <- safe_query(db_pool, "SELECT COUNT(*) as n FROM archetype_families WHERE is_active = TRUE",
                      default = data.frame(n = 0))$n
  sprintf("%s families", count)
})

# ---------------------------------------------------------------------------
# Family List (reactable)
# ---------------------------------------------------------------------------

output$family_list <- renderReactable({

  # Trigger refresh (all successful CRUD operations increment rv$refresh_decks)
  rv$refresh_decks

  data <- safe_query(db_pool, "
    SELECT
      af.family_id,
      af.family_name AS \"Family\",
      af.primary_color,
      af.secondary_color,
      af.display_card_id AS \"Card ID\",
      COUNT(da.archetype_id) AS \"Members\"
    FROM archetype_families af
    LEFT JOIN deck_archetypes da ON da.family_id = af.family_id AND da.is_active = TRUE
    WHERE af.is_active = TRUE
    GROUP BY af.family_id, af.family_name, af.primary_color, af.secondary_color, af.display_card_id
    ORDER BY af.family_name
  ")

  # Fetch member archetypes for row details expansion
  members <- safe_query(db_pool, "
    SELECT da.family_id, da.archetype_name, da.primary_color, da.secondary_color
    FROM deck_archetypes da
    WHERE da.family_id IS NOT NULL AND da.is_active = TRUE
    ORDER BY da.archetype_name
  ")

  if (nrow(data) == 0) {
    return(reactable(data.frame(Message = "No archetype families yet"), compact = TRUE))
  }

  reactable(data, compact = TRUE, striped = FALSE, searchable = TRUE,
    highlight = TRUE,
    onClick = JS("function(rowInfo, column) {
      if (rowInfo) {
        Shiny.setInputValue('family_list_clicked', {
          family_id: rowInfo.row['family_id'],
          nonce: Math.random()
        }, {priority: 'event'});
      }
    }"),
    rowStyle = list(cursor = "pointer"),
    defaultPageSize = 20,
    showPageSizeOptions = TRUE,
    pageSizeOptions = c(10, 20, 50),
    details = function(index) {
      fam_id <- data$family_id[index]
      fam_members <- members[members$family_id == fam_id, ]
      if (nrow(fam_members) == 0) {
        return(div(class = "text-muted small p-2", "No archetypes assigned"))
      }
      div(class = "p-2",
        tags$strong(class = "small", "Member Archetypes:"),
        div(class = "d-flex flex-wrap gap-1 mt-1",
          lapply(seq_len(nrow(fam_members)), function(i) {
            deck_name_badge(fam_members$archetype_name[i],
                           fam_members$primary_color[i],
                           fam_members$secondary_color[i])
          })
        )
      )
    },
    columns = list(
      family_id = colDef(show = FALSE),
      Family = colDef(minWidth = 140, style = list(whiteSpace = "normal")),
      primary_color = colDef(
        name = "Color",
        cell = function(value, index) {
          secondary <- data$secondary_color[index]
          deck_color_badge_dual(value, secondary)
        }
      ),
      secondary_color = colDef(show = FALSE),
      `Card ID` = colDef(
        cell = function(value) {
          if (is.na(value) || value == "") {
            span(class = "badge bg-warning text-dark", "Needs Card")
          } else {
            span(value)
          }
        }
      ),
      Members = colDef(
        align = "center",
        cell = function(value) {
          if (value == 0) {
            span(class = "text-muted", "0")
          } else {
            span(class = "badge bg-primary", value)
          }
        }
      )
    )
  )
})

# ---------------------------------------------------------------------------
# Add Family
# ---------------------------------------------------------------------------

observeEvent(input$add_family, {
  req(rv$is_superadmin, db_pool)

  clear_all_field_errors(session)

  name <- trimws(input$family_name)
  primary_color <- input$family_primary_color
  secondary_color <- if (input$family_secondary_color == "") NA_character_ else input$family_secondary_color
  card_id <- if (!is.null(input$family_selected_card_id) && nchar(input$family_selected_card_id) > 0) input$family_selected_card_id else NA_character_
  notes <- if (!is.null(input$family_notes) && nchar(trimws(input$family_notes)) > 0) trimws(input$family_notes) else NA_character_

  # Validation
  if (is.null(name) || nchar(name) == 0) {
    show_field_error(session, "family_name")
    notify("Please enter a family name", type = "error")
    return()
  }

  if (nchar(name) < 2) {
    show_field_error(session, "family_name")
    notify("Family name must be at least 2 characters", type = "error")
    return()
  }

  # Check for duplicate family name
  existing <- safe_query(db_pool, "
    SELECT family_id FROM archetype_families
    WHERE LOWER(family_name) = LOWER($1)
  ", params = list(name), default = data.frame(family_id = 0L))

  if (nrow(existing) > 0) {
    notify(sprintf("Family '%s' already exists", name), type = "error")
    return()
  }

  # Validate card ID format if provided
  if (!is.na(card_id) && nchar(card_id) > 0) {
    if (!grepl("^[A-Z0-9]+-[0-9]+$", card_id)) {
      show_field_error(session, "family_selected_card_id")
      notify("Card ID format should be like BT17-042 or EX6-001", type = "warning")
    }
  }

  tryCatch({
    slug <- generate_unique_family_slug(db_pool, name)
    result <- safe_query(db_pool, "
      INSERT INTO archetype_families (family_name, slug, display_card_id, primary_color, secondary_color, notes, updated_by)
      VALUES ($1, $2, $3, $4, $5, $6, $7)
      RETURNING family_id
    ", params = list(name, slug, card_id, primary_color, secondary_color, notes, current_admin_username(rv)),
    default = data.frame(family_id = integer()))

    notify(paste("Added family:", name), type = "message")

    # Clear form
    updateTextInput(session, "family_name", value = "")
    updateSelectInput(session, "family_primary_color", selected = "Red")
    updateSelectInput(session, "family_secondary_color", selected = "")
    updateTextInput(session, "family_selected_card_id", value = "")
    updateTextInput(session, "family_card_search", value = "")
    updateTextAreaInput(session, "family_notes", value = "")
    output$family_card_search_results <- renderUI({ NULL })

    # Trigger refresh
    rv$refresh_decks <- rv$refresh_decks + 1

  }, error = function(e) {
    if (sentry_enabled) tryCatch(sentryR::capture_exception(e, tags = sentry_context_tags()), error = function(se) NULL)
    notify(paste("Error:", e$message), type = "error")
  })
})

# ---------------------------------------------------------------------------
# Edit Family Click
# ---------------------------------------------------------------------------

observeEvent(input$family_list_clicked, {

  family_id <- input$family_list_clicked$family_id

  if (is.null(family_id)) return()

  # Look up family by ID
  fam <- safe_query(db_pool, "
    SELECT family_id, family_name, primary_color, secondary_color, display_card_id, notes
    FROM archetype_families
    WHERE family_id = $1
  ", params = list(as.integer(family_id)),
  default = data.frame(family_id = integer(), family_name = character(), primary_color = character(),
                       secondary_color = character(), display_card_id = character(), notes = character()))

  if (nrow(fam) == 0) return()

  # Populate form for editing
  updateTextInput(session, "editing_family_id", value = as.character(fam$family_id))
  updateTextInput(session, "family_name", value = fam$family_name)
  updateSelectInput(session, "family_primary_color", selected = fam$primary_color)
  updateSelectInput(session, "family_secondary_color",
                    selected = if (is.na(fam$secondary_color)) "" else fam$secondary_color)
  updateTextInput(session, "family_selected_card_id",
                  value = if (is.na(fam$display_card_id)) "" else fam$display_card_id)
  updateTextAreaInput(session, "family_notes",
                      value = if (is.na(fam$notes)) "" else fam$notes)

  # Show/hide buttons
  shinyjs::hide("add_family")
  shinyjs::show("update_family")
  shinyjs::show("delete_family")

  notify(sprintf("Editing: %s", fam$family_name), type = "message", duration = 2)
})

# ---------------------------------------------------------------------------
# Update Family
# ---------------------------------------------------------------------------

observeEvent(input$update_family, {
  req(rv$is_superadmin, db_pool)
  req(input$editing_family_id)

  clear_all_field_errors(session)

  family_id <- as.integer(input$editing_family_id)
  name <- trimws(input$family_name)
  primary_color <- input$family_primary_color
  secondary_color <- if (input$family_secondary_color == "") NA_character_ else input$family_secondary_color
  card_id <- if (!is.null(input$family_selected_card_id) && nchar(input$family_selected_card_id) > 0) input$family_selected_card_id else NA_character_
  notes <- if (!is.null(input$family_notes) && nchar(trimws(input$family_notes)) > 0) trimws(input$family_notes) else NA_character_

  # Validation
  if (is.null(name) || nchar(name) == 0) {
    show_field_error(session, "family_name")
    notify("Please enter a family name", type = "error")
    return()
  }

  if (nchar(name) < 2) {
    show_field_error(session, "family_name")
    notify("Family name must be at least 2 characters", type = "error")
    return()
  }

  # Check for duplicate family name (excluding self)
  existing <- safe_query(db_pool, "
    SELECT family_id FROM archetype_families
    WHERE LOWER(family_name) = LOWER($1) AND family_id != $2
  ", params = list(name, family_id), default = data.frame(family_id = 0L))

  if (nrow(existing) > 0) {
    notify(sprintf("Family '%s' already exists", name), type = "error")
    return()
  }

  tryCatch({
    slug <- generate_unique_family_slug(db_pool, name, exclude_family_id = family_id)
    safe_execute(db_pool, "
      UPDATE archetype_families
      SET family_name = $1, slug = $2, primary_color = $3, secondary_color = $4, display_card_id = $5,
          notes = $6, updated_at = CURRENT_TIMESTAMP, updated_by = $7
      WHERE family_id = $8
    ", params = list(name, slug, primary_color, secondary_color, card_id, notes, current_admin_username(rv), family_id))

    notify(sprintf("Updated family: %s", name), type = "message")

    # Clear form and reset to add mode
    updateTextInput(session, "editing_family_id", value = "")
    updateTextInput(session, "family_name", value = "")
    updateSelectInput(session, "family_primary_color", selected = "Red")
    updateSelectInput(session, "family_secondary_color", selected = "")
    updateTextInput(session, "family_selected_card_id", value = "")
    updateTextInput(session, "family_card_search", value = "")
    updateTextAreaInput(session, "family_notes", value = "")
    output$family_card_search_results <- renderUI({ NULL })

    shinyjs::show("add_family")
    shinyjs::hide("update_family")
    shinyjs::hide("delete_family")

    # Trigger refresh
    rv$refresh_decks <- rv$refresh_decks + 1

  }, error = function(e) {
    if (sentry_enabled) tryCatch(sentryR::capture_exception(e, tags = sentry_context_tags()), error = function(se) NULL)
    notify(paste("Error:", e$message), type = "error")
  })
})

# ---------------------------------------------------------------------------
# Cancel Edit Family
# ---------------------------------------------------------------------------

observeEvent(input$cancel_edit_family, {
  updateTextInput(session, "editing_family_id", value = "")
  updateTextInput(session, "family_name", value = "")
  updateSelectInput(session, "family_primary_color", selected = "Red")
  updateSelectInput(session, "family_secondary_color", selected = "")
  updateTextInput(session, "family_selected_card_id", value = "")
  updateTextInput(session, "family_card_search", value = "")
  updateTextAreaInput(session, "family_notes", value = "")
  output$family_card_search_results <- renderUI({ NULL })

  shinyjs::show("add_family")
  shinyjs::hide("update_family")
  shinyjs::hide("delete_family")
})

# ---------------------------------------------------------------------------
# Delete Family
# ---------------------------------------------------------------------------

observeEvent(input$delete_family, {
  req(rv$is_superadmin, input$editing_family_id)

  family_id <- as.integer(input$editing_family_id)
  fam <- safe_query(db_pool, "SELECT family_name FROM archetype_families WHERE family_id = $1",
                    params = list(family_id), default = data.frame(family_name = character()))

  # Check if any archetypes assigned
  count <- safe_query(db_pool, "
    SELECT COUNT(*) as cnt FROM deck_archetypes WHERE family_id = $1 AND is_active = TRUE
  ", params = list(family_id), default = data.frame(cnt = 1L))$cnt

  if (count > 0) {
    notify(
      sprintf("Cannot delete: %d archetype(s) assigned to this family", as.integer(count)),
      type = "error"
    )
  } else {
    showModal(modalDialog(
      title = "Confirm Delete",
      div(
        p(sprintf("Are you sure you want to delete '%s'?", fam$family_name)),
        p(class = "text-danger", "This action cannot be undone.")
      ),
      footer = tagList(
        actionButton("confirm_delete_family", "Delete", class = "btn-danger"),
        modalButton("Cancel")
      ),
      easyClose = TRUE
    ))
  }
})

# ---------------------------------------------------------------------------
# Confirm Delete Family
# ---------------------------------------------------------------------------

observeEvent(input$confirm_delete_family, {
  req(rv$is_superadmin, db_pool, input$editing_family_id)
  family_id <- as.integer(input$editing_family_id)

  # Re-check referential integrity before delete
  count <- safe_query(db_pool, "
    SELECT COUNT(*) as cnt FROM deck_archetypes WHERE family_id = $1 AND is_active = TRUE
  ", params = list(family_id), default = data.frame(cnt = 1L))$cnt

  if (count > 0) {
    removeModal()
    notify(sprintf("Cannot delete: %d archetype(s) assigned to this family", as.integer(count)), type = "error")
    return()
  }

  tryCatch({
    safe_execute(db_pool, "DELETE FROM archetype_families WHERE family_id = $1",
                 params = list(family_id))
    notify("Family deleted", type = "message")

    # Hide modal and reset form
    removeModal()

    # Clear form
    updateTextInput(session, "editing_family_id", value = "")
    updateTextInput(session, "family_name", value = "")
    updateSelectInput(session, "family_primary_color", selected = "Red")
    updateSelectInput(session, "family_secondary_color", selected = "")
    updateTextInput(session, "family_selected_card_id", value = "")
    updateTextInput(session, "family_card_search", value = "")
    updateTextAreaInput(session, "family_notes", value = "")
    output$family_card_search_results <- renderUI({ NULL })

    shinyjs::show("add_family")
    shinyjs::hide("update_family")
    shinyjs::hide("delete_family")

    # Trigger refresh
    rv$refresh_decks <- rv$refresh_decks + 1

  }, error = function(e) {
    if (sentry_enabled) tryCatch(sentryR::capture_exception(e, tags = sentry_context_tags()), error = function(se) NULL)
    notify(paste("Error:", e$message), type = "error")
  })
})
