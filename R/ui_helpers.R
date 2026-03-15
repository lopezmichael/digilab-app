# =============================================================================
# UI Helper Functions
# =============================================================================
# Shared UI patterns extracted from admin views to reduce duplication.

#' Hidden Edit Field
#'
#' Creates a textInput hidden via inline JS — used in admin forms to track
#' which record is being edited.
#'
#' @param id Character. The Shiny input ID for the hidden field.
#' @return A tagList containing the hidden textInput.
hidden_edit_field <- function(id) {
  tagList(
    textInput(id, NULL, value = ""),
    tags$script(sprintf(
      "document.getElementById('%s').parentElement.style.display = 'none';",
      id
    ))
  )
}

#' Admin Form Section
#'
#' Wraps content in the standard admin form section layout with an icon label.
#'
#' @param icon Character. A bsicons icon name (e.g., "person-fill").
#' @param label Character. The section heading text.
#' @param ... UI elements to include inside the section body.
#' @return A div with class "admin-form-section".
admin_section <- function(icon, label, ...) {
  div(class = "admin-form-section",
    div(class = "admin-form-section-label",
      bsicons::bs_icon(icon),
      label
    ),
    ...
  )
}

#' Color Filter Pills
#'
#' Generates the standard set of color filter pill elements used in
#' meta analysis advanced filters (desktop and mobile).
#'
#' @return A div with class "color-filter-pills" containing all color options.
color_filter_pills <- function() {
  colors <- c("Red", "Blue", "Yellow", "Green", "Black", "Purple", "White")
  div(id = "meta_color_pills", class = "color-filter-pills",
    lapply(colors, function(color) {
      tags$span(class = "color-pill", `data-color` = color,
        tags$span(class = "color-dot"), color)
    })
  )
}

#' Create skeleton card placeholders for mobile loading states
#'
#' @param n Number of skeleton cards to render (default 3)
#' @param id_prefix If provided, container gets id "{id_prefix}_skeleton"
#'   so JavaScript can auto-hide it when the real output renders.
#' @return A shiny div tag
skeleton_cards <- function(n = 3, id_prefix = NULL) {
  id <- if (!is.null(id_prefix)) paste0(id_prefix, "_skeleton") else NULL
  div(
    id = id,
    class = "skeleton-cards-container",
    lapply(seq_len(n), function(i) {
      div(class = "skeleton-card",
        div(class = "skeleton-line skeleton-line-title"),
        div(class = "skeleton-line skeleton-line-short"),
        div(class = "skeleton-line skeleton-line-medium")
      )
    })
  )
}
