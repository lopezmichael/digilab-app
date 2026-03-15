# =============================================================================
# Admin: Edit Formats Server Logic
# =============================================================================

# Format list table
output$admin_format_list <- renderReactable({


  # Trigger refresh
  input$add_format
  input$update_format
  input$confirm_delete_format

  data <- safe_query(db_pool, "
    SELECT format_id as \"Set Code\",
           set_name as \"Set Name\",
           release_date as \"Release Date\",
           is_active as \"Active\"
    FROM formats
    ORDER BY release_date DESC
  ", default = data.frame())

  if (nrow(data) == 0) {
    return(admin_empty_state("No formats added yet", "// add one using the form", "calendar3"))
  }

  # Format date for display
  data$`Release Date` <- as.character(data$`Release Date`)

  reactable(
    data,
    searchable = TRUE,
    selection = "single",
    onClick = "select",
    highlight = TRUE,
    compact = TRUE,
    pagination = TRUE,
    defaultPageSize = 20,
    columns = list(
      `Set Code` = colDef(width = 90),
      `Set Name` = colDef(minWidth = 120, style = list(whiteSpace = "normal")),
      `Release Date` = colDef(name = "Released", width = 105),
      Active = colDef(width = 60, align = "center", cell = function(value) {
        if (value) "\u2705" else "\u274c"
      })
    )
  )
})

# Click row to edit
observeEvent(input$admin_format_list__reactable__selected, {

  selected_idx <- input$admin_format_list__reactable__selected

  if (is.null(selected_idx)) return()

  # Get the format_id from the selected row
  data <- safe_query(db_pool, "
    SELECT format_id, set_name, release_date, is_active
    FROM formats
    ORDER BY release_date DESC
  ", default = data.frame())

  if (selected_idx > nrow(data)) return()

  format <- data[selected_idx, ]

  # Fill form
  updateTextInput(session, "editing_format_id", value = format$format_id)
  updateTextInput(session, "format_id", value = format$format_id)
  updateTextInput(session, "format_set_name", value = format$set_name)
  updateDateInput(session, "format_release_date", value = format$release_date)
  updateCheckboxInput(session, "format_is_active", value = format$is_active)

  # Show/hide buttons
  shinyjs::hide("add_format")
  shinyjs::show("update_format")
  shinyjs::show("delete_format")

  notify(sprintf("Editing: %s", format$set_name), type = "message", duration = 2)
})

# Add format
observeEvent(input$add_format, {
  req(rv$is_superadmin, db_pool)

  clear_all_field_errors(session)

  format_id <- trimws(input$format_id)
  set_name <- trimws(input$format_set_name)
  release_date <- input$format_release_date
  is_active <- input$format_is_active

  if (format_id == "" || set_name == "") {
    if (format_id == "") show_field_error(session, "format_id")
    if (set_name == "") show_field_error(session, "format_set_name")
    notify("Set Code and Set Name are required", type = "error")
    return()
  }

  # Auto-generate display_name
  display_name <- sprintf("%s (%s)", format_id, set_name)

  tryCatch({
    safe_execute(db_pool, "
      INSERT INTO formats (format_id, set_name, display_name, release_date, sort_order, is_active)
      VALUES ($1, $2, $3, $4, 0, $5)
    ", params = list(format_id, set_name, display_name, release_date, is_active))

    notify(sprintf("Added format: %s", display_name), type = "message")

    # Clear form
    updateTextInput(session, "format_id", value = "")
    updateTextInput(session, "format_set_name", value = "")
    updateDateInput(session, "format_release_date", value = Sys.Date())
    updateCheckboxInput(session, "format_is_active", value = TRUE)

    # Refresh format choices and public tables
    rv$format_refresh <- (rv$format_refresh %||% 0) + 1
    rv$refresh_formats <- rv$refresh_formats + 1

  }, error = function(e) {
    if (grepl("unique|duplicate|primary key", e$message, ignore.case = TRUE)) {
      notify("A format with this Set Code already exists", type = "error")
    } else {
      notify(paste("Error:", e$message), type = "error")
    }
  })
})

# Update format
observeEvent(input$update_format, {
  req(rv$is_superadmin, db_pool, input$editing_format_id)

  clear_all_field_errors(session)

  original_id <- input$editing_format_id
  format_id <- trimws(input$format_id)
  set_name <- trimws(input$format_set_name)
  release_date <- input$format_release_date
  is_active <- input$format_is_active

  if (format_id == "" || set_name == "") {
    if (format_id == "") show_field_error(session, "format_id")
    if (set_name == "") show_field_error(session, "format_set_name")
    notify("Set Code and Set Name are required", type = "error")
    return()
  }

  # Auto-generate display_name
  display_name <- sprintf("%s (%s)", format_id, set_name)

  tryCatch({
    # If format_id changed, we need to update related tournaments
    if (format_id != original_id) {
      # Update tournaments that reference this format
      safe_execute(db_pool, "
        UPDATE tournaments SET format = $1 WHERE format = $2
      ", params = list(format_id, original_id))

      # Delete old and insert new (since format_id is primary key)
      safe_execute(db_pool, "DELETE FROM formats WHERE format_id = $1", params = list(original_id))
      safe_execute(db_pool, "
        INSERT INTO formats (format_id, set_name, display_name, release_date, sort_order, is_active)
        VALUES ($1, $2, $3, $4, 0, $5)
      ", params = list(format_id, set_name, display_name, release_date, is_active))
    } else {
      safe_execute(db_pool, "
        UPDATE formats
        SET set_name = $1, display_name = $2, release_date = $3, is_active = $4, updated_at = CURRENT_TIMESTAMP
        WHERE format_id = $5
      ", params = list(set_name, display_name, release_date, is_active, format_id))
    }

    notify(sprintf("Updated format: %s", display_name), type = "message")

    # Reset form
    updateTextInput(session, "editing_format_id", value = "")
    updateTextInput(session, "format_id", value = "")
    updateTextInput(session, "format_set_name", value = "")
    updateDateInput(session, "format_release_date", value = Sys.Date())
    updateCheckboxInput(session, "format_is_active", value = TRUE)

    shinyjs::show("add_format")
    shinyjs::hide("update_format")
    shinyjs::hide("delete_format")

    # Refresh format choices and public tables
    rv$format_refresh <- (rv$format_refresh %||% 0) + 1
    rv$refresh_formats <- rv$refresh_formats + 1

  }, error = function(e) {
    notify(paste("Error:", e$message), type = "error")
  })
})

# Cancel edit format
observeEvent(input$cancel_edit_format, {
  updateTextInput(session, "editing_format_id", value = "")
  updateTextInput(session, "format_id", value = "")
  updateTextInput(session, "format_set_name", value = "")
  updateDateInput(session, "format_release_date", value = Sys.Date())
  updateCheckboxInput(session, "format_is_active", value = TRUE)

  shinyjs::show("add_format")
  shinyjs::hide("update_format")
  shinyjs::hide("delete_format")
})

# Check if format can be deleted (no related tournaments)
observe({
  req(input$editing_format_id)

  count <- safe_query(db_pool, "
    SELECT COUNT(*) as cnt FROM tournaments WHERE format = $1
  ", params = list(input$editing_format_id),
     default = data.frame(cnt = 0))$cnt

  rv$format_tournament_count <- count
  rv$can_delete_format <- count == 0
})

# Delete button click - show modal
observeEvent(input$delete_format, {
  req(rv$is_superadmin, input$editing_format_id)

  format <- safe_query(db_pool, "SELECT set_name, display_name FROM formats WHERE format_id = $1",
                       params = list(input$editing_format_id),
                       default = data.frame(set_name = character(), display_name = character()))

  if (rv$can_delete_format) {
    showModal(modalDialog(
      title = "Confirm Delete",
      div(
        p(sprintf("Are you sure you want to delete '%s'?", format$display_name)),
        p(class = "text-danger", "This action cannot be undone.")
      ),
      footer = tagList(
        actionButton("confirm_delete_format", "Delete", class = "btn-danger"),
        modalButton("Cancel")
      ),
      easyClose = TRUE
    ))
  } else {
    notify(
      sprintf("Cannot delete: %d tournament(s) use this format", as.integer(rv$format_tournament_count)),
      type = "error"
    )
  }
})

# Confirm delete format
observeEvent(input$confirm_delete_format, {
  req(rv$is_superadmin, db_pool, input$editing_format_id)

  tryCatch({
    safe_execute(db_pool, "DELETE FROM formats WHERE format_id = $1",
              params = list(input$editing_format_id))
    notify("Format deleted", type = "message")

    # Hide modal and reset form
    removeModal()

    updateTextInput(session, "editing_format_id", value = "")
    updateTextInput(session, "format_id", value = "")
    updateTextInput(session, "format_set_name", value = "")
    updateTextInput(session, "format_display_name", value = "")
    updateDateInput(session, "format_release_date", value = Sys.Date())
    updateNumericInput(session, "format_sort_order", value = 1)
    updateCheckboxInput(session, "format_is_active", value = TRUE)

    shinyjs::show("add_format")
    shinyjs::hide("update_format")
    shinyjs::hide("delete_format")

    # Refresh format choices and public tables
    rv$format_refresh <- (rv$format_refresh %||% 0) + 1
    rv$refresh_formats <- rv$refresh_formats + 1

  }, error = function(e) {
    notify(paste("Error:", e$message), type = "error")
  })
})
