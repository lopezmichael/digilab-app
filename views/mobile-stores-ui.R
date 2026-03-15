# views/mobile-stores-ui.R
# Mobile-optimized Stores view with compact map and stacked store cards.
# Sourced inside output$stores_page when is_mobile() is TRUE.
# Returns a bare tagList (no assignment) so source(...)$value works.

tagList(
  # -- Title strip (simplified — no view toggle buttons) ----------------------
  div(
    class = "page-title-strip mb-2",
    div(
      class = "title-strip-content",
      div(
        class = "title-strip-context",
        bsicons::bs_icon("geo-alt-fill", class = "title-strip-icon"),
        tags$span(class = "title-strip-text", "Store Directory")
      ),
      div(
        class = "title-strip-actions",
        actionButton("open_store_request",
                     tagList(bsicons::bs_icon("plus-circle"), " Request"),
                     class = "btn btn-sm btn-outline-light")
      )
    )
  ),

  # -- Compact map (200px) ----------------------------------------------------
  div(
    class = "mobile-map-compact",
    div(
      class = "map-loading-container",
      div(class = "map-loading-placeholder",
        div(class = "spinner-border", role = "status",
          tags$span(class = "visually-hidden", "Loading map...")
        )
      ),
      mapgl::mapboxglOutput("mobile_stores_map", height = "200px")
    )
  ),

  # Skeleton loading state (auto-hidden when cards render)
  skeleton_cards(n = 3, id_prefix = "mobile_stores_cards"),

  # -- Store cards (rendered by server) ---------------------------------------
  uiOutput("mobile_stores_cards"),

  # -- Store detail modal (reuse existing) ------------------------------------
  uiOutput("store_detail_modal"),

  # -- Online stores section (reuse existing) ---------------------------------
  uiOutput("online_stores_section")
)
