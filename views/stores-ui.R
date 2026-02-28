# views/stores-ui.R
# Stores tab UI with interactive map

stores_ui <- tagList(
  # Title strip
  div(
    class = "page-title-strip mb-3",
    div(
      class = "title-strip-content",
      # Left side: page title
      div(
        class = "title-strip-context",
        bsicons::bs_icon("geo-alt-fill", class = "title-strip-icon"),
        tags$span(class = "title-strip-text", "Store Directory")
      ),
      # Right side: request button
      div(
        class = "title-strip-actions",
        actionButton("open_store_request",
                     tagList(bsicons::bs_icon("plus-circle"), " Request a Store"),
                     class = "btn btn-sm btn-outline-primary")
      )
    )
  ),

  # Help text
  div(class = "page-help-text",
    div(class = "info-hint-box text-center",
      bsicons::bs_icon("info-circle", class = "info-hint-icon"),
      "Find local game stores hosting Digimon TCG events. Click a store on the map or list for schedules and tournament history."
    )
  ),

  # Map card with digital scanner styling
  card(
    class = "card-map mb-3",
    card_header(
      class = "d-flex justify-content-between align-items-center",
      div(
        class = "d-flex align-items-center gap-2 map-circuit-node",
        bsicons::bs_icon("map"),
        span("Location Scanner"),
        span(class = "small text-muted", "(larger nodes = bigger events)")
      )
    ),
    card_body(
      class = "map-container-flush",
      mapboxglOutput("stores_map", height = "475px")
    )
  ),
  card(
    card_header(
      class = "d-flex justify-content-between align-items-center",
      # View toggle buttons
      div(
        class = "btn-group btn-group-sm",
        role = "group",
        `aria-label` = "Store view toggle",
        actionButton(
          "stores_view_schedule",
          tagList(bsicons::bs_icon("calendar-week"), " Schedule"),
          class = "btn-outline-primary"
        ),
        actionButton(
          "stores_view_all",
          tagList(bsicons::bs_icon("grid-3x3-gap"), " Cards"),
          class = "btn-outline-primary active"
        )
      ),
      uiOutput("stores_view_hint")
    ),
    card_body(
      # Schedule view (shown when explicitly selected)
      conditionalPanel(
        condition = "input.stores_view_mode == 'schedule'",
        id = "stores_schedule_view",
        uiOutput("stores_schedule_content")
      ),
      # Cards view (default)
      conditionalPanel(
        condition = "input.stores_view_mode != 'schedule'",
        id = "stores_cards_view",
        uiOutput("stores_cards_content")
      )
    )
  ),
  # Hidden input to track view mode
  tags$input(type = "hidden", id = "stores_view_mode", value = "all", class = "shiny-input-text"),

  # Store detail modal (rendered dynamically)
  # Handles both physical stores and online organizers
  uiOutput("store_detail_modal"),

  # Online Tournament Organizers section
  uiOutput("online_stores_section")
)
