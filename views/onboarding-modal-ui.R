# =============================================================================
# Onboarding Modal UI
# 3-step carousel: Pick Your Scene, Find Yourself, Your Scene at a Glance
# =============================================================================

#' Onboarding carousel with 3 steps
onboarding_ui <- function() {
  tagList(
    # --- Progress bar (thin, fills per step) ---
    div(class = "onboarding-progress-bar",
      div(id = "onboarding_progress_fill", class = "onboarding-progress-fill",
          style = "width: 33%;")
    ),

    # --- Dot indicators (pill-shaped active) ---
    div(
      class = "onboarding-dots",
      span(id = "onboarding_dot_1", class = "onboarding-dot active"),
      span(id = "onboarding_dot_2", class = "onboarding-dot upcoming"),
      span(id = "onboarding_dot_3", class = "onboarding-dot upcoming")
    ),

    # ===================== Step 1: Pick Your Scene =====================
    div(
      id = "onboarding_step_1",
      class = "onboarding-step",

      # Step label
      div(class = "onboarding-step-label", "STEP 1 OF 3"),

      # Hero unit: Agumon mascot + title side by side
      div(
        class = "onboarding-hero",
        div(class = "onboarding-hero-mascot", agumon_svg(size = "48px", color = "#F7941D")),
        div(class = "onboarding-hero-text",
          h2(class = "onboarding-title", "Where do you play?")
        )
      ),

      # Subtitle
      p(class = "onboarding-subtitle",
        "Select your local scene to see tournaments, players, and meta data from your area."
      ),

      # Full-width map
      div(
        class = "onboarding-map-wrapper",
        div(
          class = "onboarding-map-container",
          mapgl::mapboxglOutput("onboarding_map", height = "300px")
        )
      ),

      # Find My Scene button (full width)
      div(
        class = "onboarding-find-scene",
        actionButton("find_my_scene",
                     tagList(bsicons::bs_icon("crosshair"), " Find My Scene"),
                     class = "btn-primary btn-sm w-100")
      ),

      # Divider
      div(class = "onboarding-divider",
          span("or choose")),

      # Two equal buttons
      div(
        class = "onboarding-scene-buttons",
        actionButton("select_scene_online",
                     tagList(bsicons::bs_icon("camera-video-fill"), " Online / Webcam"),
                     class = "btn-outline-secondary btn-sm"),
        actionButton("select_scene_all",
                     tagList(bsicons::bs_icon("globe2"), " All Scenes"),
                     class = "btn-outline-secondary btn-sm")
      ),

      # Confirmation (hidden by default, shown after selection)
      shinyjs::hidden(
        div(
          id = "onboarding_scene_confirmed",
          class = "onboarding-scene-confirmation",
          bsicons::bs_icon("check-circle-fill"),
          span(id = "onboarding_scene_label", "")
        )
      ),

      # Reassurance note
      p(class = "onboarding-muted-note",
        "You can change your scene anytime from the dropdown in the header."
      )
    ),

    # ===================== Step 2: Find Yourself =====================
    shinyjs::hidden(
      div(
        id = "onboarding_step_2",
        class = "onboarding-step",

        # Step label
        div(class = "onboarding-step-label", "STEP 2 OF 3"),

        # Title + description
        h2(class = "onboarding-title", "Are you already on DigiLab?"),
        p(class = "onboarding-subtitle",
          "Search by player name or Bandai Member ID to find your stats."
        ),

        # Search row
        div(
          class = "onboarding-search-row",
          textInput("onboarding_player_search", NULL,
                    placeholder = "Player name or Bandai ID",
                    width = "100%"),
          actionButton("onboarding_player_search_btn",
                       tagList(bsicons::bs_icon("search"), " Search"),
                       class = "btn-primary btn-sm")
        ),

        # Hint box
        div(
          class = "onboarding-hint-box",
          bsicons::bs_icon("phone"),
          span("Your Bandai ID is on your TCG+ app profile")
        ),

        # Search results (dynamic)
        uiOutput("onboarding_player_result")
      )
    ),

    # ===================== Step 3: Your Scene at a Glance =====================
    shinyjs::hidden(
      div(
        id = "onboarding_step_3",
        class = "onboarding-step",

        # Step label
        div(class = "onboarding-step-label", "STEP 3 OF 3"),

        # Dynamic scene title
        h2(class = "onboarding-title", textOutput("onboarding_scene_title", inline = TRUE)),
        p(class = "onboarding-subtitle",
          HTML("Here&rsquo;s what&rsquo;s happening in your scene")
        ),

        # Stats grid (dynamic)
        uiOutput("onboarding_stats_grid"),

        # Rank banner (conditional, only if player found)
        uiOutput("onboarding_rank_banner"),

        # Full-width CTA
        actionButton("onboarding_enter",
                     tagList("Enter DigiLab ", bsicons::bs_icon("arrow-right")),
                     class = "onboarding-cta-btn")
      )
    ),

    # ===================== Navigation Buttons =====================
    div(
      class = "onboarding-nav-buttons",
      div(
        class = "onboarding-nav-left",
        # Step 1: Skip for now
        actionButton("onboarding_skip", "Skip for now",
                     class = "onboarding-skip-btn"),
        # Steps 2-3: Back
        shinyjs::hidden(
          actionButton("onboarding_back",
                       tagList(bsicons::bs_icon("arrow-left"), " Back"),
                       class = "btn-outline-secondary btn-sm")
        )
      ),
      div(
        class = "onboarding-nav-center",
        # Step 2 only: Skip (ghost)
        shinyjs::hidden(
          actionButton("onboarding_skip_2", "Skip",
                       class = "onboarding-skip-btn")
        )
      ),
      div(
        class = "onboarding-nav-right",
        # Step 1: Next
        actionButton("onboarding_next",
                     tagList("Next ", bsicons::bs_icon("arrow-right")),
                     class = "btn-primary btn-sm"),
        # Step 2: Almost Done
        shinyjs::hidden(
          actionButton("onboarding_next_2",
                       tagList("Almost Done ", bsicons::bs_icon("arrow-right")),
                       class = "btn-primary btn-sm")
        )
      )
    )
  )
}
