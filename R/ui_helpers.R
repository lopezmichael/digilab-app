# R/ui_helpers.R
# Shared UI helper functions

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
