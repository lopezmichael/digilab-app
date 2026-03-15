# =============================================================================
# DigiLab - Digimon TCG Tournament Tracker
# Main Shiny Application
# https://app.digilab.cards/
# =============================================================================

library(shiny)
library(shinyjs)
library(bslib)
library(brand.yml)
library(bsicons)
library(DBI)
library(pool)
library(RPostgres)
library(jsonlite)
library(reactable)
library(htmltools)
library(atomtemplates)
library(mapgl)
library(sf)
library(highcharter)
library(bcrypt)

# Removed after audit (unused or optional atomtemplates dependencies):
# - tidygeocoder: Not used (custom Mapbox geocoding in admin-stores-server.R)
# - sysfonts/showtext: Optional deps of atomtemplates, not directly used
# - brand.yml: Optional dep of atomtemplates, not directly used
# - httr: Lazy-loaded via namespacing in R/digimoncard_api.R (rarely used, cards cached)

# App version (update with each release)
APP_VERSION <- "1.7.3"

# Load modules
source("R/db_connection.R")
source("R/safe_db.R")
source("R/admin_grid.R")
source("R/digimoncard_api.R")
source("R/ratings.R")
source("R/geo_utils.R")
source("R/constants.R")
source("R/ui_helpers.R")
source("R/discord_webhook.R")
source("R/ui_helpers.R")

# Load environment variables
if (file.exists(".env")) {
  readRenviron(".env")
}

# Set MAPBOX_PUBLIC_TOKEN from MAPBOX_ACCESS_TOKEN if needed
# (atomtemplates uses MAPBOX_PUBLIC_TOKEN, but we have MAPBOX_ACCESS_TOKEN in .env)
if (Sys.getenv("MAPBOX_PUBLIC_TOKEN") == "" && Sys.getenv("MAPBOX_ACCESS_TOKEN") != "") {
  Sys.setenv(MAPBOX_PUBLIC_TOKEN = Sys.getenv("MAPBOX_ACCESS_TOKEN"))
}

# Patch mapgl 0.4.4 trailing slash bug (causes 404 on Mapbox CDN)
# See: https://github.com/walkerke/mapgl/issues/176
mapgl_yaml <- system.file("htmlwidgets/mapboxgl.yaml", package = "mapgl")
if (nzchar(mapgl_yaml)) {
  yaml_text <- readLines(mapgl_yaml, warn = FALSE)
  if (any(grepl('api.mapbox.com.*/"$', yaml_text))) {
    yaml_text <- gsub('(api\\.mapbox\\.com[^"]*)/(")', '\\1\\2', yaml_text)
    writeLines(yaml_text, mapgl_yaml)
    message("[STARTUP] Patched mapgl trailing slash bug in mapboxgl.yaml")
  }
}

# Create database connection pool
db_pool <- create_db_pool()

# Setup Atom Google Fonts
setup_atom_google_fonts()

# =============================================================================
# Helper: Parse Schedule Info JSON
# =============================================================================

parse_schedule_info <- function(schedule_json) {

  if (is.null(schedule_json) || is.na(schedule_json) || schedule_json == "") {
    return(NULL)
  }

  tryCatch({
    info <- jsonlite::fromJSON(schedule_json)
    parts <- c()

    # Format days
    if (!is.null(info$digimon_days)) {
      days <- paste(info$digimon_days, collapse = ", ")
      parts <- c(parts, days)
    }

    # Add time if available
    if (!is.null(info$friday_time)) {
      parts <- c(parts, paste("Fri:", info$friday_time))
    }
    if (!is.null(info$saturday_time)) {
      parts <- c(parts, paste("Sat:", info$saturday_time))
    }
    if (!is.null(info$time)) {
      parts <- c(parts, info$time)
    }

    # Add entry fee if available
    if (!is.null(info$entry_fee)) {
      parts <- c(parts, paste("Entry:", info$entry_fee))
    }

    # Add notes if available
    if (!is.null(info$notes)) {
      parts <- c(parts, info$notes)
    }

    if (length(parts) > 0) {
      return(paste(parts, collapse = " | "))
    }
    NULL
  }, error = function(e) {
    NULL
  })
}

# =============================================================================
# Helper: Deck Color Badge Renderer
# =============================================================================

# Get badge class for a single color
get_color_class <- function(color) {
  color_lower <- tolower(trimws(color))
  switch(color_lower,
    "red" = "deck-badge deck-badge-red",
    "blue" = "deck-badge deck-badge-blue",
    "yellow" = "deck-badge deck-badge-yellow",
    "green" = "deck-badge deck-badge-green",
    "black" = "deck-badge deck-badge-black",
    "purple" = "deck-badge deck-badge-purple",
    "white" = "deck-badge deck-badge-white",
    "multi" = "deck-badge deck-badge-multi-color",
    "deck-badge"
  )
}

# Render single color badge (shows full color name)
deck_color_badge <- function(color) {
  if (is.null(color) || is.na(color) || color == "") {
    return(htmltools::span(class = "deck-badge", "-"))
  }
  # Capitalize first letter
  display_name <- paste0(toupper(substr(color, 1, 1)), tolower(substr(color, 2, nchar(color))))
  htmltools::span(class = get_color_class(color), display_name)
}

# Render dual color badge (for decks with primary + secondary color)
deck_color_badge_dual <- function(primary, secondary = NULL) {
  if (is.null(primary) || is.na(primary) || primary == "") {
    return(htmltools::span(class = "deck-badge", "-"))
  }

  if (is.null(secondary) || is.na(secondary) || secondary == "") {
    # Single color - show full name
    display_name <- paste0(toupper(substr(primary, 1, 1)), tolower(substr(primary, 2, nchar(primary))))
    return(htmltools::span(class = get_color_class(primary), display_name))
  }

  # Dual color - show as split badge with initials
  # Use "U" for Blue to distinguish from Black ("B")
  get_color_initial <- function(color) {
    color_lower <- tolower(trimws(color))
    if (color_lower == "blue") return("U")
    toupper(substr(color, 1, 1))
  }

  htmltools::div(
    class = "deck-badge-multi",
    htmltools::span(class = get_color_class(primary), get_color_initial(primary)),
    htmltools::span(class = get_color_class(secondary), get_color_initial(secondary))
  )
}

# Map color name to hex (for inline gradient styles)
get_color_hex <- function(color) {
  if (is.null(color) || is.na(color) || color == "") return("#9CA3AF")
  switch(tolower(trimws(color)),
    "red" = "#E5383B", "blue" = "#2D7DD2", "yellow" = "#F5B700",
    "green" = "#38A169", "black" = "#2D3748", "purple" = "#805AD5",
    "white" = "#E2E8F0", "multi" = "#EC4899", "#9CA3AF"
  )
}

# Render deck name with color badge (dual-color aware)
# For single-color: deck name inside colored badge
# For dual-color: deck name with gradient background spanning both colors
deck_name_badge <- function(name, primary, secondary = NULL) {
  if (is.null(name) || is.na(name) || name == "" || name == "-") return(htmltools::span("-"))

  has_secondary <- !is.null(secondary) && !is.na(secondary) && secondary != ""

  if (has_secondary) {
    hex1 <- get_color_hex(primary)
    hex2 <- get_color_hex(secondary)
    # Use dark text only if both colors are light (yellow/white)
    light_colors <- c("yellow", "white")
    text_color <- if (tolower(primary) %in% light_colors && tolower(secondary) %in% light_colors) {
      "#1A1A1A"
    } else {
      "#FFFFFF"
    }
    htmltools::span(
      class = "deck-badge deck-badge-dual",
      style = sprintf("background: linear-gradient(135deg, %s 0%%, %s 100%%); color: %s;",
                       hex1, hex2, text_color),
      name
    )
  } else {
    htmltools::span(class = get_color_class(primary), name)
  }
}

# =============================================================================
# Helper: Custom Notification
# =============================================================================

notify <- function(message, type = "message", duration = NULL, ...) {
  # Smart duration defaults:
  # - Errors: sticky until dismissed (duration = NULL)
  # - Warnings: 8 seconds
  # - Messages: 4 seconds
  # Custom durations can still be passed to override
  if (is.null(duration)) {
    duration <- switch(type,
      "error" = NULL,
      "warning" = 8,
      "message" = 4,
      5
    )
  }

  # Map type to icon and class
  icon_name <- switch(type,
    "message" = "check-circle",
    "warning" = "triangle-exclamation",
    "error" = "circle-xmark",
    "check-circle"
  )

  type_class <- switch(type,
    "message" = "notify-success",
    "warning" = "notify-warning",
    "error" = "notify-error",
    "notify-success"
  )

  # Build notification UI with icon
  ui <- tags$div(
    class = paste("custom-notification", type_class),
    tags$span(class = "notify-icon", icon(icon_name)),
    tags$span(class = "notify-message", message)
  )

  # Log errors and warnings to stderr so they appear in Posit Connect logs
  if (type %in% c("error", "warning")) {
    message("[notify:", type, "] ", message)
  }

  showNotification(
    ui = ui,
    duration = duration,
    closeButton = TRUE,
    type = type,
    ...
  )
}

# =============================================================================
# Helper: Inline Form Validation
# =============================================================================

# Highlight a field as invalid (red border)
show_field_error <- function(session, inputId) {
  shinyjs::runjs(sprintf(
    "var el = document.getElementById('%s');
     if (el) el.closest('.shiny-input-container').classList.add('input-invalid');",
    inputId
  ))
}

# Clear invalid highlighting from a field
clear_field_error <- function(session, inputId) {
  shinyjs::runjs(sprintf(
    "var el = document.getElementById('%s');
     if (el) el.closest('.shiny-input-container').classList.remove('input-invalid');",
    inputId
  ))
}

# Clear all invalid fields in a container
clear_all_field_errors <- function(session) {
  shinyjs::runjs(
    "document.querySelectorAll('.input-invalid').forEach(function(el) {
       el.classList.remove('input-invalid');
     });"
  )
}

# =============================================================================
# Helper: Agumon SVG Mascot
# =============================================================================

# Read Agumon SVG content from file at startup (avoids inline path data)
.agumon_svg_template <- local({
  svg_content <- readLines("www/agumon.svg", warn = FALSE)
  svg_text <- paste(svg_content, collapse = "\n")
  # Strip the original width/height/viewBox so we can inject our own
  svg_text <- sub('width="[^"]*"', 'width="%s"', svg_text)
  svg_text <- sub('height="[^"]*"', 'height="%s"', svg_text)
  # Add style attribute for color override (currentColor picks it up)
  svg_text <- sub("<svg ", "<svg style=\"color:%s\" ", svg_text)
  svg_text
})

agumon_svg <- function(size = "48px", color = "#F7941D") {
  # Template placeholder order: style="color:%s" width="%s" height="%s"
  HTML(sprintf(.agumon_svg_template, color, size, size))
}

# =============================================================================
# Helper: Digital Empty State
# =============================================================================

digital_empty_state <- function(title = "No signal detected",
                                 subtitle = "// awaiting data",
                                 icon = "reception-0",
                                 mascot = NULL) {
  icon_el <- if (!is.null(mascot) && mascot == "agumon") {
    div(class = "empty-state-icon empty-state-mascot", agumon_svg(size = "56px"))
  } else {
    div(class = "empty-state-icon", bsicons::bs_icon(icon))
  }

  div(
    class = "empty-state-digital",
    div(class = "empty-state-corners"),
    icon_el,
    div(class = "empty-state-title", title),
    div(class = "empty-state-subtitle", subtitle)
  )
}

# Skeleton loader for table cards
skeleton_table <- function(rows = 6) {
  div(
    class = "skeleton-container",
    lapply(seq_len(rows), function(i) {
      widths <- c("w-40", "w-75", "w-60", "w-50", "w-90")
      div(
        class = "skeleton-table-row",
        div(class = paste("skeleton-line", widths[((i - 1) %% 5) + 1])),
        div(class = paste("skeleton-line", widths[((i + 1) %% 5) + 1])),
        div(class = paste("skeleton-line", widths[((i + 2) %% 5) + 1]))
      )
    })
  )
}

# Skeleton loader for chart cards
skeleton_chart <- function(bars = 8, height = "180px") {
  div(
    class = "skeleton-container",
    div(
      class = "skeleton-chart",
      style = paste0("height:", height),
      lapply(seq_len(bars), function(i) {
        bar_height <- paste0(sample(30:95, 1), "%")
        div(class = "skeleton-bar", style = paste0("height:", bar_height))
      })
    )
  )
}

# Lightweight empty state for admin tables
admin_empty_state <- function(title = "No records found",
                               subtitle = NULL,
                               icon = "inbox") {
  div(
    class = "empty-state-digital",
    style = "padding: 1.5rem 1rem; min-height: 80px;",
    div(class = "empty-state-icon", style = "font-size: 1.8rem;",
        bsicons::bs_icon(icon)),
    div(class = "empty-state-title", title),
    if (!is.null(subtitle)) div(class = "empty-state-subtitle", subtitle)
  )
}

# =============================================================================
# Configuration
# =============================================================================

# Event type choices
EVENT_TYPES <- c(
  "Locals" = "locals",
  "Online Tournament" = "online",
  "Evolution Cup" = "evo_cup",
  "Store Championship" = "store_championship",
  "Regionals" = "regionals",
  "Casuals" = "casuals",
  "Regulation Battle" = "regulation_battle",
  "Release Event" = "release_event",
  "Other" = "other"
)

# Event types that do NOT affect competitive rating calculations
UNRATED_EVENT_TYPES <- c("casuals", "regulation_battle", "release_event", "other")

# External links (single source of truth)
LINKS <- list(
  discord = "https://discord.gg/ABcjha7bHk",
  kofi    = "https://ko-fi.com/digilab",
  github  = "https://github.com/lopezmichael/digimon-tcg-standings"
)

# Sentry error tracking (no-op if DSN not set)
sentry_enabled <- FALSE
if (nzchar(Sys.getenv("SENTRY_DSN", ""))) {
  tryCatch({
    sentryR::configure_sentry(
      dsn = Sys.getenv("SENTRY_DSN"),
      app_name = "digilab",
      app_version = APP_VERSION,
      environment = ifelse(.Platform$OS.type == "unix", "production", "development")
    )
    sentry_enabled <- TRUE
    message("[sentry] Initialized successfully")
  }, error = function(e) {
    message("[sentry] Failed to initialize: ", conditionMessage(e))
  })
}

# =============================================================================
# Source Views
# =============================================================================

# Public page UIs (dashboard, stores, players, meta, tournaments) are sourced
# at render time inside each page's renderUI so format choices can be populated
# from the database. See server/public-*-server.R files.
source("views/submit-ui.R", local = TRUE)
source("views/onboarding-modal-ui.R", local = TRUE)
source("views/community-banner-ui.R", local = TRUE)

# =============================================================================
# UI
# =============================================================================

ui <- page_fillable(
  theme = atom_dashboard_theme(),

  # Enable busy indicators (shows spinner when app is processing)
  useBusyIndicators(),

  # Enable shinyjs for show/hide functionality
  useShinyjs(),

  # Custom CSS and JavaScript
  tags$head(
    # Open Graph meta tags for link previews (Discord, Twitter, etc.)
    tags$meta(property = "og:title", content = "DigiLab - Digimon TCG Locals Tracker"),
    tags$meta(property = "og:description", content = "Track your local Digimon TCG tournament results, player standings, deck meta, and store events."),
    tags$meta(property = "og:type", content = "website"),
    tags$meta(property = "og:url", content = "https://app.digilab.cards/"),
    tags$meta(property = "og:site_name", content = "DigiLab"),
    tags$meta(property = "og:image", content = "https://app.digilab.cards/og-image.png"),
    tags$meta(property = "og:image:width", content = "1200"),
    tags$meta(property = "og:image:height", content = "630"),
    # Twitter Card tags
    tags$meta(name = "twitter:card", content = "summary_large_image"),
    tags$meta(name = "twitter:title", content = "DigiLab - Digimon TCG Locals Tracker"),
    tags$meta(name = "twitter:description", content = "Track your local Digimon TCG tournament results, player standings, deck meta, and store events."),
    tags$meta(name = "twitter:image", content = "https://app.digilab.cards/og-image.png"),
    # Standard meta description
    tags$meta(name = "description", content = "Track your local Digimon TCG tournament results, player standings, deck meta, and store events."),
    # PWA manifest and theme
    tags$link(rel = "manifest", href = "manifest.json"),
    tags$meta(name = "theme-color", content = "#1a1a2e"),
    # Favicon and app icons
    tags$link(rel = "icon", type = "image/x-icon", href = "favicon.ico"),
    tags$link(rel = "apple-touch-icon", href = "apple-touch-icon.png"),
    # Viewport with safe area support for iPhone X+ PWA mode
    tags$meta(name = "viewport",
              content = "width=device-width, initial-scale=1, viewport-fit=cover"),
    # Standalone mode (iOS + Android)
    tags$meta(name = "mobile-web-app-capable", content = "yes"),
    tags$meta(name = "apple-mobile-web-app-status-bar-style", content = "black-translucent"),
    tags$meta(name = "apple-mobile-web-app-title", content = "DigiLab"),
    # Google Analytics
    tags$script(async = NA, src = "https://www.googletagmanager.com/gtag/js?id=G-NJ3SMG8HGG"),
    tags$script(HTML("
      window.dataLayer = window.dataLayer || [];
      function gtag(){dataLayer.push(arguments);}
      gtag('js', new Date());
      gtag('config', 'G-NJ3SMG8HGG');

      // Custom GA4 event handler (called from Shiny server)
      Shiny.addCustomMessageHandler('trackEvent', function(data) {
        if (typeof gtag === 'function') {
          gtag('event', data.event, data.params || {});
        }
      });
    ")),
    # Flag icons CSS for country flags in tables
    tags$link(rel = "stylesheet", href = "https://cdn.jsdelivr.net/npm/flag-icons@7.2.3/css/flag-icons.min.css"),
    # Righteous font now loaded via _brand.yml (bslib headings font)
    tags$link(rel = "stylesheet", type = "text/css", href = "custom.css"),
    tags$link(rel = "stylesheet", type = "text/css", href = "mobile.css"),
    # Deep linking URL routing
    tags$script(src = "url-routing.js"),
    # Scene selection and localStorage
    tags$script(src = "scene-selector.js"),
    # Pill toggle segmented controls
    tags$script(src = "pill-toggle.js"),
    # Skeleton loader auto-hide
    tags$script(src = "skeleton-loader.js"),
    # PWA service worker registration
    tags$script(HTML("if('serviceWorker' in navigator){navigator.serviceWorker.register('sw.js');}")),
    # JavaScript to handle active nav state and loading screen
    tags$script(HTML("
      // Device detection - send device info to Shiny on connect
      var _deviceInfo = {
        type: window.innerWidth <= 768 ? 'mobile' : 'desktop',
        width: window.innerWidth,
        touch: 'ontouchstart' in window,
        standalone: window.matchMedia('(display-mode: standalone)').matches
      };
      $(document).on('shiny:connected', function() {
        Shiny.setInputValue('device_info', _deviceInfo);
      });

      $(document).on('click', '.nav-link-sidebar', function() {
        $('.nav-link-sidebar').removeClass('active');
        $(this).addClass('active');
      });

      // Bottom tab bar - click handler
      $(document).on('click', '.tab-bar-item', function() {
        $('.tab-bar-item').removeClass('active');
        $(this).addClass('active');
      });

      // Map sidebar nav IDs to bottom bar IDs
      var navToTab = {
        'nav_dashboard': 'mob_dashboard',
        'nav_players': 'mob_players',
        'nav_meta': 'mob_meta',
        'nav_tournaments': 'mob_tournaments',
        'nav_stores': 'mob_stores'
      };

      // Custom handler to update sidebar and bottom bar when programmatically navigating
      Shiny.addCustomMessageHandler('updateSidebarNav', function(navId) {
        // Update sidebar
        $('.nav-link-sidebar').removeClass('active');
        $('#' + navId).addClass('active');

        // Update bottom tab bar
        $('.tab-bar-item').removeClass('active');
        var tabId = navToTab[navId];
        if (tabId) {
          $('#' + tabId + ' .tab-bar-item').addClass('active');
        }
      });

      // Loading screen message cycling
      var loadingMessages = [
        { main: 'Opening Digital Gate...', sub: 'Establishing connection' },
        { main: 'Scanning Local Meta...', sub: 'Loading tournament data' },
        { main: 'Synchronizing...', sub: 'Preparing tool' }
      ];
      var currentMessage = 0;

      function cycleLoadingMessage() {
        if (currentMessage < loadingMessages.length) {
          var msg = loadingMessages[currentMessage];
          $('.loading-message').text(msg.main);
          $('.loading-submessage').text(msg.sub);
          currentMessage++;
        }
      }

      // Function to hide loading screen (called from Shiny server)
      Shiny.addCustomMessageHandler('hideLoading', function(message) {
        setTimeout(function() {
          $('.app-loading-overlay').addClass('loaded');
        }, 200);
      });

      // Agumon SVG string (shared by loading overlay and disconnect overlay)
      var agumonSvg = '<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"56\" height=\"56\" viewBox=\"0 0 24 24\">' +
              '<g transform=\"matrix(0.83 0 0 0.83 12 12)\"><g>' +
                '<g transform=\"matrix(1 0 0 1 -1.37 -5.11)\"><path style=\"stroke: #F7941D; stroke-width: 1.5; stroke-linecap: round; stroke-linejoin: round; fill: none;\" transform=\" translate(-10.63, -6.89)\" d=\"M 11.7644 9.4961 L 9.18799 10.7838 C 8.91075 10.9225 8.60501 10.9948 8.29501 10.9948 L 4.24725 10.9948 C 3.80632 10.9948 3.37002 10.905 2.96493 10.7308 C 2.55985 10.5567 2.19447 10.3018 1.89107 9.98189 C 1.58767 9.66195 1.3526 9.28356 1.20018 8.86981 C 1.04777 8.45606 0.981209 8.01561 1.00456 7.57529 C 1.07944 6.7239 1.47496 5.93274 2.11109 5.36191 C 2.74721 4.79109 3.57642 4.48324 4.43093 4.50064 L 7.99897 4.50064 C 8.45142 3.62999 9.09522 2.87314 9.88204 2.28691 C 10.6689 1.70068 11.5783 1.3003 12.542 1.11583 C 13.5057 0.931367 14.4986 0.967605 15.4463 1.22183 C 16.394 1.47605 17.2718 1.94164 18.0138 2.58367 C 18.7558 3.22569 19.3427 4.02746 19.7305 4.92877 C 20.1183 5.83009 20.2969 6.80755 20.2528 7.78776 C 20.2088 8.76797 19.9433 9.72547 19.4762 10.5884 C 19.0091 11.4513 18.3527 12.1972 17.5561 12.7701\"/></g>' +
                '<g transform=\"matrix(1 0 0 1 1.54 -6.6)\"><path style=\"stroke: #F7941D; stroke-width: 1.5; fill: none;\" transform=\" translate(-13.54, -5.4)\" d=\"M 13.7203 5.76587 C 13.518 5.76587 13.3539 5.60184 13.3539 5.39949 C 13.3539 5.19714 13.518 5.03311 13.7203 5.03311\"/></g>' +
                '<g transform=\"matrix(1 0 0 1 1.9 -6.6)\"><path style=\"stroke: #F7941D; stroke-width: 1.5; fill: none;\" transform=\" translate(-13.9, -5.4)\" d=\"M 13.7203 5.76587 C 13.9227 5.76587 14.0867 5.60184 14.0867 5.39949 C 14.0867 5.19714 13.9227 5.03311 13.7203 5.03311\"/></g>' +
                '<g transform=\"matrix(1 0 0 1 -5.73 -1.75)\"><path style=\"stroke: #F7941D; stroke-width: 1.5; stroke-linecap: round; stroke-linejoin: round; fill: none;\" transform=\" translate(-6.27, -10.25)\" d=\"M 6.26871 10.9948 L 6.26871 9.49609\"/></g>' +
                '<g transform=\"matrix(1 0 0 1 -2.96 -0.54)\"><path style=\"stroke: #F7941D; stroke-width: 1.5; stroke-linecap: round; stroke-linejoin: round; fill: none;\" transform=\" translate(-9.04, -11.46)\" d=\"M 8.80695 10.9284 L 9.26614 11.9943\"/></g>' +
                '<g transform=\"matrix(1 0 0 1 -4.31 8.75)\"><path style=\"stroke: #F7941D; stroke-width: 1.5; stroke-linecap: round; stroke-linejoin: round; fill: none;\" transform=\" translate(-7.69, -20.75)\" d=\"M 9.72048 18.51 C 8.13265 18.9942 6.76427 20.0187 5.8525 21.4058 C 5.74594 21.5552 5.68258 21.7311 5.66935 21.9141 C 5.65612 22.0972 5.69353 22.2803 5.77749 22.4435 C 5.86145 22.6066 5.98871 22.7436 6.14533 22.8392 C 6.30194 22.9348 6.48186 22.9855 6.66537 22.9857 L 9.65502 22.9857\"/></g>' +
                '<g transform=\"matrix(1 0 0 1 -5.23 0.49)\"><path style=\"stroke: #F7941D; stroke-width: 1.5; stroke-linecap: round; stroke-linejoin: round; fill: none;\" transform=\" translate(-6.77, -12.49)\" d=\"M 10.2657 13.9923 L 5.26923 13.9923 C 5.00681 13.9924 4.74694 13.9408 4.50448 13.8405 C 4.26201 13.7401 4.04171 13.5929 3.85615 13.4074 C 3.6706 13.2218 3.52343 13.0015 3.42307 12.7591 C 3.3227 12.5166 3.27111 12.2567 3.27124 11.9943 L 3.27124 11.9943 C 3.27111 11.8631 3.29684 11.7332 3.34697 11.6119 C 3.39709 11.4906 3.47062 11.3805 3.56335 11.2876 C 3.65608 11.1948 3.7662 11.1212 3.88741 11.0709 C 4.00862 11.0207 4.13854 10.9948 4.26974 10.9948\"/></g>' +
                '<g transform=\"matrix(1 0 0 1 3.78 5.88)\"><path style=\"stroke: #F7941D; stroke-width: 1.5; stroke-linecap: round; stroke-linejoin: round; fill: none;\" transform=\" translate(-15.78, -17.88)\" d=\"M 17.5561 12.7701 L 18.2918 14.1799 C 18.4788 14.5382 18.7379 14.854 19.0528 15.1073 C 19.3677 15.3607 19.7316 15.5462 20.1217 15.6522 C 20.5117 15.7582 20.9195 15.7823 21.3193 15.7231 C 21.7192 15.664 22.1024 15.5227 22.4451 15.3083 L 23 14.9615 C 23 18.51 21.7299 20.335 19.7583 20.4875 L 19.7583 21.9862 C 19.7583 22.2513 19.653 22.5055 19.4655 22.6929 C 19.2781 22.8804 19.0239 22.9857 18.7588 22.9857 L 13.2191 22.9857 C 13.0356 22.9855 12.8557 22.9348 12.6991 22.8392 C 12.5425 22.7436 12.4152 22.6066 12.3313 22.4435 C 12.2473 22.2803 12.2099 22.0972 12.2231 21.9141 C 12.2364 21.7311 12.2997 21.5552 12.4063 21.4058 L 12.758 20.9173 C 12.9076 20.7108 13.0768 20.519 13.2631 20.3448 C 11.5494 19.8944 8.57346 18.3488 8.57346 16.4934 L 8.56076 13.9952\"/></g>' +
                '<g transform=\"matrix(1 0 0 1 3.05 3.98)\"><path style=\"stroke: #F7941D; stroke-width: 1.5; stroke-linecap: round; stroke-linejoin: round; fill: none;\" transform=\" translate(-15.05, -15.98)\" d=\"M 16.8282 16.4641 L 15.5581 17.2614 C 15.3913 17.3659 15.2056 17.4366 15.0115 17.4694 C 14.8173 17.5022 14.6187 17.4964 14.4268 17.4524 C 14.2349 17.4084 14.0536 17.327 13.8931 17.213 C 13.7327 17.0989 13.5963 16.9543 13.4917 16.7875 C 13.3872 16.6207 13.3165 16.435 13.2837 16.2409 C 13.2509 16.0467 13.2567 15.8481 13.3007 15.6562 C 13.3447 15.4643 13.4261 15.283 13.5402 15.1225 C 13.6542 14.9621 13.7988 14.8257 13.9656 14.7211 L 14.3564 14.4779\"/></g>' +
              '</g></g>' +
            '</svg>';

      // Inject loading overlay into body on document ready (avoids prependContent warning)
      $(document).ready(function() {
        // Set initial active tab on mobile bar
        $('#mob_dashboard .tab-bar-item').addClass('active');

        var loadingHTML = '<div class=\"app-loading-overlay\">' +
          '<div class=\"loading-scanline\"></div>' +
          '<div class=\"loading-gate\">' +
            '<div class=\"loading-gate-center\">' + agumonSvg + '</div>' +
          '</div>' +
          '<div class=\"loading-message\">Opening Digital Gate...</div>' +
          '<div class=\"loading-submessage\">Establishing connection</div>' +
        '</div>';
        $('body').prepend(loadingHTML);
        setInterval(cycleLoadingMessage, 1200);
      });

      // Visibility-aware keepalive - ping server only when tab is visible
      (function() {
        var KEEPALIVE_INTERVAL = 30000; // 30 seconds
        var keepaliveTimer = null;

        function sendKeepalive() {
          if (Shiny && Shiny.shinyapp && Shiny.shinyapp.$socket) {
            // Send a no-op message to keep connection alive
            Shiny.setInputValue('keepalive_ping', Date.now(), {priority: 'event'});
          }
        }

        function startKeepalive() {
          if (!keepaliveTimer) {
            keepaliveTimer = setInterval(sendKeepalive, KEEPALIVE_INTERVAL);
          }
        }

        function stopKeepalive() {
          if (keepaliveTimer) {
            clearInterval(keepaliveTimer);
            keepaliveTimer = null;
          }
        }

        // Start/stop based on visibility
        document.addEventListener('visibilitychange', function() {
          if (document.hidden) {
            stopKeepalive();
          } else {
            startKeepalive();
            sendKeepalive(); // Send immediately when tab becomes visible
          }
        });

        // Start keepalive when Shiny connects
        $(document).on('shiny:connected', function() {
          if (!document.hidden) {
            startKeepalive();
          }
        });

        // Stop on disconnect
        $(document).on('shiny:disconnected', stopKeepalive);
      })();

      // Custom disconnect overlay
      (function() {
        var disconnectHTML = '<div class=\"disconnect-overlay\" id=\"custom-disconnect\">' +
          '<div class=\"disconnect-icon\">' + agumonSvg + '</div>' +
          '<div class=\"disconnect-title\">Connection Lost</div>' +
          '<div class=\"disconnect-message\">The Digital Gate has closed. Click below to reconnect.</div>' +
          '<button class=\"disconnect-btn\" onclick=\"location.reload()\">Reconnect</button>' +
        '</div>';

        $(document).ready(function() {
          $('body').append(disconnectHTML);
        });

        $(document).on('shiny:disconnected', function() {
          $('#custom-disconnect').addClass('active');
        });
      })();
    ")),
    # Auto-fit deck name text in value boxes
    tags$script(HTML("
      function fitDeckText() {
        document.querySelectorAll('.vb-value-deck').forEach(function(el) {
          var parent = el.parentElement;
          if (!parent) return;
          var maxWidth = parent.offsetWidth;
          if (maxWidth === 0) return;
          var fontSize = 1.1;
          el.style.fontSize = fontSize + 'rem';
          while (el.scrollWidth > maxWidth && fontSize > 0.6) {
            fontSize -= 0.05;
            el.style.fontSize = fontSize + 'rem';
          }
        });
      }

      // Auto-clear validation styling when user interacts with invalid fields
      $(document).on('change input focus', '.input-invalid .form-control, .input-invalid select, .input-invalid .selectize-input input', function() {
        $(this).closest('.input-invalid').removeClass('input-invalid');
      });

      $(document).on('shiny:value', function(e) {
        if (e.name === 'hot_deck_name' || e.name === 'most_popular_deck_val') {
          setTimeout(fitDeckText, 50);
        }

        // Count-up animation for numeric value boxes
        var numericBoxes = ['total_tournaments_val', 'total_players_val'];
        if (numericBoxes.indexOf(e.name) !== -1) {
          setTimeout(function() {
            var el = document.getElementById(e.name);
            if (!el) return;
            var newVal = parseInt(el.textContent, 10);
            if (isNaN(newVal)) return;
            var oldVal = parseInt(el.getAttribute('data-prev') || '0', 10);
            el.setAttribute('data-prev', newVal);
            if (oldVal === newVal || oldVal === 0) {
              el.classList.add('vb-value-updating');
              setTimeout(function() { el.classList.remove('vb-value-updating'); }, 400);
              return;
            }
            var duration = 600;
            var start = performance.now();
            function step(now) {
              var progress = Math.min((now - start) / duration, 1);
              var eased = 1 - Math.pow(1 - progress, 3);
              el.textContent = Math.round(oldVal + (newVal - oldVal) * eased);
              if (progress < 1) requestAnimationFrame(step);
            }
            requestAnimationFrame(step);
          }, 50);
        }

        // Fade-in animation for deck value boxes
        var deckBoxes = ['hot_deck_name', 'most_popular_deck_val', 'hot_deck_trend', 'top_deck_meta_share'];
        if (deckBoxes.indexOf(e.name) !== -1) {
          setTimeout(function() {
            var el = document.getElementById(e.name);
            if (!el) return;
            el.classList.add('vb-value-updating');
            setTimeout(function() { el.classList.remove('vb-value-updating'); }, 400);
          }, 50);
        }

        // Hide skeleton loaders once Shiny outputs render
        var skeletonId = e.name + '_skeleton';
        var skeleton = document.getElementById(skeletonId);
        if (skeleton) {
          skeleton.style.display = 'none';
        }
      });
      $(window).on('resize', function() { setTimeout(fitDeckText, 100); });

      // Auto-show/hide admin notification bar based on whether it has real content
      $(document).ready(function() {
        var notifBar = document.getElementById('admin_notification_bar');
        if (notifBar) {
          var observer = new MutationObserver(function() {
            if (notifBar.querySelector('.admin-notification-bar')) {
              notifBar.style.display = 'block';
            } else {
              notifBar.style.display = 'none';
            }
          });
          observer.observe(notifBar, { childList: true, subtree: true });
        }
      });
    "))
  ),

  # Header Bar
  div(
    class = "app-header",
    tags$a(
      href = "https://digilab.cards/",
      target = "_blank",
      rel = "noopener noreferrer",
      class = "header-title",
      style = "text-decoration: none; color: inherit;",
      # Digivice icon
      span(
        class = "header-icon",
        HTML('<svg xmlns="http://www.w3.org/2000/svg" width="26" height="26" viewBox="0 0 24 24"><g transform="matrix(0.83 0 0 0.83 12 12)"><g><g transform="matrix(1 0 0 1 -7.85 0)"><path style="stroke: currentColor; stroke-width: 1.5; fill: none;" transform=" translate(-4.15, -12)" d="M 4.33798 12.3775 C 4.13088 12.3775 3.96298 12.2096 3.96298 12.0025 C 3.96298 11.7953 4.13088 11.6275 4.33798 11.6275" stroke-linecap="round"/></g><g transform="matrix(1 0 0 1 -7.47 0)"><path style="stroke: currentColor; stroke-width: 1.5; fill: none;" transform=" translate(-4.53, -12)" d="M 4.33798 12.3775 C 4.54509 12.3775 4.71298 12.2096 4.71298 12.0025 C 4.71298 11.7953 4.54509 11.6275 4.33798 11.6275" stroke-linecap="round"/></g><g transform="matrix(1 0 0 1 6.88 -1.64)"><path style="stroke: currentColor; stroke-width: 1.5; fill: none;" transform=" translate(-18.88, -10.36)" d="M 19.067 10.73 C 18.8599 10.73 18.692 10.5621 18.692 10.355 C 18.692 10.1479 18.8599 9.98 19.067 9.98" stroke-linecap="round"/></g><g transform="matrix(1 0 0 1 7.25 -1.64)"><path style="stroke: currentColor; stroke-width: 1.5; fill: none;" transform=" translate(-19.25, -10.36)" d="M 19.067 10.73 C 19.2741 10.73 19.442 10.5621 19.442 10.355 C 19.442 10.1479 19.2741 9.98 19.067 9.98" stroke-linecap="round"/></g><g transform="matrix(1 0 0 1 6.88 1.88)"><path style="stroke: currentColor; stroke-width: 1.5; fill: none;" transform=" translate(-18.88, -13.88)" d="M 19.067 14.254 C 18.8599 14.254 18.692 14.0861 18.692 13.879 C 18.692 13.6719 18.8599 13.504 19.067 13.504" stroke-linecap="round"/></g><g transform="matrix(1 0 0 1 7.25 1.88)"><path style="stroke: currentColor; stroke-width: 1.5; fill: none;" transform=" translate(-19.25, -13.88)" d="M 19.067 14.254 C 19.2741 14.254 19.442 14.0861 19.442 13.879 C 19.442 13.6719 19.2741 13.504 19.067 13.504" stroke-linecap="round"/></g><g transform="matrix(1 0 0 1 0 0)"><path style="stroke: currentColor; stroke-width: 1.5; stroke-linecap: round; stroke-linejoin: round; fill: none;" transform=" translate(-12, -12)" d="M 23.25 12 C 23.2495 13.135 23.1492 14.2677 22.95 15.385 C 22.9142 15.5861 22.8177 15.7715 22.6734 15.9161 C 22.5291 16.0608 22.344 16.1577 22.143 16.194 C 21.099 16.3854 20.1225 16.8442 19.3087 17.5256 C 18.495 18.2071 17.8718 19.0879 17.5 20.082 C 17.4416 20.2395 17.3445 20.3798 17.2176 20.49 C 17.0908 20.6001 16.9382 20.6764 16.774 20.712 C 15.2045 21.0445 13.6043 21.2097 12 21.205 C 10.3957 21.2097 8.79544 21.0445 7.22599 20.712 C 7.0618 20.6764 6.90921 20.6001 6.78233 20.49 C 6.65544 20.3798 6.55834 20.2395 6.49999 20.082 C 6.12786 19.0873 5.50407 18.2062 4.68956 17.5248 C 3.87506 16.8433 2.8977 16.3848 1.85299 16.194 C 1.65194 16.1577 1.46683 16.0608 1.32255 15.9161 C 1.17828 15.7715 1.08176 15.5861 1.04599 15.385 C 0.651256 13.1456 0.651256 10.8544 1.04599 8.615 C 1.08176 8.41387 1.17828 8.22851 1.32255 8.08388 C 1.46683 7.93925 1.65194 7.84227 1.85299 7.806 C 2.8977 7.61523 3.87506 7.15671 4.68956 6.47524 C 5.50407 5.79377 6.12786 4.91266 6.49999 3.918 C 6.55834 3.76046 6.65544 3.62016 6.78233 3.51005 C 6.90921 3.39994 7.0618 3.32357 7.22599 3.288 C 8.79562 2.9572 10.3959 2.79362 12 2.8 C 13.6043 2.79526 15.2045 2.96052 16.774 3.293 C 16.9382 3.32857 17.0908 3.40494 17.2176 3.51505 C 17.3445 3.62516 17.4416 3.76546 17.5 3.923 C 17.8721 4.91766 18.4959 5.79877 19.3104 6.48024 C 20.1249 7.16171 21.1023 7.62023 22.147 7.811 C 22.348 7.84727 22.5331 7.94425 22.6774 8.08888 C 22.8217 8.23351 22.9182 8.41887 22.954 8.62 C 23.1515 9.73581 23.2506 10.8668 23.25 12 L 23.25 12 Z" stroke-linecap="round"/></g><g transform="matrix(1 0 0 1 0 0)"><path style="stroke: currentColor; stroke-width: 1.5; stroke-linecap: round; stroke-linejoin: round; fill: none;" transform=" translate(-12, -12)" d="M 14.974 9.5 L 9.02499 9.5 L 9.02499 14.5 L 14.974 14.5 L 14.974 9.5 Z" stroke-linecap="round"/></g><g transform="matrix(1 0 0 1 -8.37 -6.85)"><path style="stroke: currentColor; stroke-width: 1.5; stroke-linecap: round; stroke-linejoin: round; fill: none;" transform=" translate(-3.63, -5.15)" d="M 2.53799 3.846 L 4.71299 6.456" stroke-linecap="round"/></g><g transform="matrix(1 0 0 1 0 5.34)"><path style="stroke: currentColor; stroke-width: 1.5; stroke-linecap: round; stroke-linejoin: round; fill: none;" transform=" translate(-12, -17.34)" d="M 15.873 16.634 C 14.7865 17.5417 13.4158 18.0389 12 18.0389 C 10.5843 18.0389 9.21351 17.5417 8.12701 16.634" stroke-linecap="round"/></g><g transform="matrix(1 0 0 1 0 -5.34)"><path style="stroke: currentColor; stroke-width: 1.5; stroke-linecap: round; stroke-linejoin: round; fill: none;" transform=" translate(-12, -6.66)" d="M 15.873 7.366 C 14.7865 6.45834 13.4158 5.96111 12 5.96111 C 10.5843 5.96111 9.21351 6.45834 8.12701 7.366" stroke-linecap="round"/></g></g></g></svg>')
      ),
      span("DigiLab", class = "header-title-text"),
      span(class = "header-badge", paste0("v", APP_VERSION)),
      span(class = "header-circuit-line")
    ),
    # Admin + help icons + dark mode toggle (separate div for mobile row 1)
    div(
      class = "header-actions",
      actionLink("admin_login_link",
                 bsicons::bs_icon("lock"),
                 class = "header-action-btn",
                 title = "Admin Login"),
      actionLink("help_menu_link",
                 bsicons::bs_icon("three-dots-vertical"),
                 class = "header-action-btn",
                 title = "Help & Resources"),
      input_dark_mode(id = "dark_mode", mode = "light")
    ),
    # Cascading scene selector: continent + scene dropdowns
    div(
      class = "header-scene-selector",
      div(
        class = "continent-selector-wrapper",
        tags$i(class = "fas fa-globe continent-icon", id = "continent_icon"),
        selectInput("continent_selector", NULL,
                    choices = list(
                      "ALL" = "all",
                      "NAM" = "north_america",
                      "SAM" = "south_america",
                      "EUR" = "europe",
                      "AFR" = "africa",
                      "ASI" = "asia",
                      "OCE" = "oceania",
                      "ONL" = "online"
                    ),
                    selected = "all",
                    selectize = FALSE)
      ),
      selectInput("scene_selector", NULL,
                  choices = list("All Scenes" = "all"),
                  selected = "all",
                  selectize = FALSE)
    )
  ),

  # Main Layout with Sidebar
  layout_sidebar(
    fillable = TRUE,

    sidebar = sidebar(
      id = "main_sidebar",
      title = NULL,  # Remove the "Menu" title
      width = 230,
      bg = "#0A3055",
      open = "desktop",  # Closed on mobile by default

      # Digimon TCG Logo (saved locally in www/)
      div(
        class = "sidebar-logo-container",
        tags$img(
          src = "digimon-logo.png",
          class = "sidebar-logo",
          alt = "Digimon TCG"
        )
      ),

      # Navigation
      tags$nav(
        class = "sidebar-nav",

        # Public tabs (ordered by engagement: overview, rankings, meta, history, reference)
        actionLink("nav_dashboard",
                   tagList(bsicons::bs_icon("graph-up"), " Overview"),
                   class = "nav-link-sidebar active"),
        actionLink("nav_players",
                   tagList(bsicons::bs_icon("people"), " Players"),
                   class = "nav-link-sidebar"),
        actionLink("nav_meta",
                   tagList(bsicons::bs_icon("stack"), " Deck Meta"),
                   class = "nav-link-sidebar"),
        actionLink("nav_tournaments",
                   tagList(bsicons::bs_icon("trophy"), " Tournaments"),
                   class = "nav-link-sidebar"),
        actionLink("nav_stores",
                   tagList(bsicons::bs_icon("geo-alt"), " Stores"),
                   class = "nav-link-sidebar"),
        actionLink("nav_submit",
                   tagList(bsicons::bs_icon("cloud-upload"), " Upload Results"),
                   class = "nav-link-sidebar"),

        # Admin Section (conditionally shown, ordered by frequency of use)
        conditionalPanel(
          condition = "output.is_admin",
          tags$div(class = "nav-section-label", "Admin"),
          actionLink("nav_admin_results",
                     tagList(bsicons::bs_icon("pencil-square"), " Enter Results"),
                     class = "nav-link-sidebar"),
          actionLink("nav_admin_tournaments",
                     tagList(bsicons::bs_icon("trophy"), " Edit Tournaments"),
                     class = "nav-link-sidebar"),
          actionLink("nav_admin_players",
                     tagList(bsicons::bs_icon("people"), " Edit Players"),
                     class = "nav-link-sidebar"),
          actionLink("nav_admin_stores",
                     tagList(bsicons::bs_icon("shop"), " Edit Stores"),
                     class = "nav-link-sidebar")
        ),

        # Super Admin Section (superadmin only)
        conditionalPanel(
          condition = "output.is_superadmin",
          tags$div(class = "nav-section-label", "Super Admin"),
          actionLink("nav_admin_decks",
                     tagList(bsicons::bs_icon("collection"), " Edit Decks"),
                     class = "nav-link-sidebar"),
          actionLink("nav_admin_formats",
                     tagList(bsicons::bs_icon("calendar3"), " Edit Formats"),
                     class = "nav-link-sidebar"),
          actionLink("nav_admin_users",
                     tagList(bsicons::bs_icon("person-gear"), " Manage Admins"),
                     class = "nav-link-sidebar"),
          actionLink("nav_admin_scenes",
                     tagList(bsicons::bs_icon("globe2"), " Manage Scenes"),
                     class = "nav-link-sidebar")
        )
      )
    ),

    # Main Content Area
    div(
      class = "main-content",

      # Admin notification bar (pending requests — shown only to admins)
      uiOutput("admin_notification_bar"),

      # Community filter banner (shown when filtering by store)
      uiOutput("community_banner"),

      # Hidden navset for content switching
      navset_hidden(
        id = "main_content",

        nav_panel_hidden(value = "dashboard", uiOutput("dashboard_page")),
        nav_panel_hidden(value = "stores", uiOutput("stores_page")),
        nav_panel_hidden(value = "players", uiOutput("players_page")),
        nav_panel_hidden(value = "meta", uiOutput("meta_page")),
        nav_panel_hidden(value = "tournaments", uiOutput("tournaments_page")),
        nav_panel_hidden(value = "submit", submit_ui),
        nav_panel_hidden(value = "admin_results", uiOutput("admin_results_ui")),
        nav_panel_hidden(value = "admin_tournaments", uiOutput("admin_tournaments_ui")),
        nav_panel_hidden(value = "admin_decks", uiOutput("admin_decks_ui")),
        nav_panel_hidden(value = "admin_stores", uiOutput("admin_stores_ui")),
        nav_panel_hidden(value = "admin_formats", uiOutput("admin_formats_ui")),
        nav_panel_hidden(value = "admin_players", uiOutput("admin_players_ui")),
        nav_panel_hidden(value = "admin_users", uiOutput("admin_users_ui")),
        nav_panel_hidden(value = "admin_scenes", uiOutput("admin_scenes_ui"))
      )
    )
  ),

  # Footer (minimal layout for iframe embedding)
  tags$footer(
    class = "app-footer",
    # Left: Version + Welcome Guide
    tags$div(
      class = "footer-left",
      tags$span(class = "footer-version", paste0("v", APP_VERSION)),
      actionLink("open_welcome_guide",
                 bsicons::bs_icon("lightbulb"),
                 class = "footer-guide-btn",
                 title = "Welcome Guide")
    ),
    # Center: Social icons
    tags$div(
      class = "footer-social",
      tags$a(
        href = LINKS$github,
        target = "_blank",
        rel = "noopener noreferrer",
        class = "footer-icon-btn",
        title = "View on GitHub",
        bsicons::bs_icon("github")
      ),
      tags$a(
        href = LINKS$discord,
        target = "_blank",
        rel = "noopener noreferrer",
        class = "footer-icon-btn",
        title = "Join Discord",
        bsicons::bs_icon("discord")
      ),
      tags$a(
        href = LINKS$kofi,
        target = "_blank",
        rel = "noopener noreferrer",
        class = "footer-icon-btn",
        title = "Support on Ko-fi",
        bsicons::bs_icon("cup-hot")
      )
    ),
    # Right: Copyright + Privacy
    tags$div(
      class = "footer-right",
      tags$span(class = "footer-copyright", "\u00A9 2026 DigiLab"),
      tags$a(
        href = "https://digilab.cards/privacy",
        target = "_blank",
        rel = "noopener noreferrer",
        class = "footer-link",
        "Privacy"
      )
    )
  ),

  # Mobile bottom tab bar (hidden on desktop via CSS)
  div(
    id = "mobile_tab_bar",
    class = "mobile-tab-bar",

    actionLink("mob_dashboard", div(
      class = "tab-bar-item",
      bsicons::bs_icon("graph-up"),
      span(class = "tab-bar-label", "Overview")
    )),
    actionLink("mob_players", div(
      class = "tab-bar-item",
      bsicons::bs_icon("people"),
      span(class = "tab-bar-label", "Players")
    )),
    actionLink("mob_meta", div(
      class = "tab-bar-item",
      bsicons::bs_icon("stack"),
      span(class = "tab-bar-label", "Meta")
    )),
    actionLink("mob_tournaments", div(
      class = "tab-bar-item",
      bsicons::bs_icon("trophy"),
      span(class = "tab-bar-label", "Tournaments")
    )),
    actionLink("mob_stores", div(
      class = "tab-bar-item",
      bsicons::bs_icon("geo-alt"),
      span(class = "tab-bar-label", "Stores")
    )),
  )
)

# =============================================================================
# Server
# =============================================================================

server <- function(input, output, session) {

  # Global error handler for Sentry (with context tags)
  if (sentry_enabled) {
    options(shiny.error = function() {
      tryCatch(
        sentryR::capture_exception(geterrmessage(), tags = sentry_context_tags()),
        error = function(se) NULL
      )
    })
  }

  # ---------------------------------------------------------------------------
  # Reactive Values
  # See ARCHITECTURE.md for full documentation of each value
  # ---------------------------------------------------------------------------

  rv <- reactiveValues(
    # === CORE ===
    is_admin = FALSE,
    is_superadmin = FALSE,
    admin_user = NULL,          # List: user_id, username, discord_user_id, role, scene_id
    needs_bootstrap = FALSE,    # TRUE when admin_users table is empty

    # === NAVIGATION ===
    current_nav = "dashboard",
    current_scene = "all",             # Scene filter - defaults to "all" for initial load (e.g., "dfw")
    current_continent = "all",          # Continent filter - "all", "north_america", "europe", etc.
    community_filter = NULL,           # Store slug for community-filtered view (e.g., "eagles-nest")
    navigate_to_tournament_id = NULL,

    # === MODAL STATE ===
    # Pattern: selected_{entity}_id (singular)
    selected_store_id = NULL,
    selected_online_store_id = NULL,
    selected_player_id = NULL,
    selected_archetype_id = NULL,
    selected_tournament_id = NULL,

    # === ONBOARDING STATE ===
    onboarding_step = 1,

    # === FORM/WIZARD STATE ===
    wizard_step = 1,
    active_tournament_id = NULL,
    current_results = data.frame(),
    duplicate_tournament = NULL,
    editing_store = NULL,
    editing_archetype = NULL,
    card_search_results = NULL,
    card_search_page = 1,

    # === REFRESH TRIGGERS ===
    # Pattern: {scope}_refresh - increment to trigger reactive invalidation
    data_refresh = 0,          # Global refresh (scene selection changes only)
    results_refresh = 0,
    format_refresh = 0,
    tournament_refresh = 0,
    schedules_refresh = 0,
    requests_refresh = 0,

    # Domain-specific refresh triggers (admin writes)
    refresh_tournaments = 0,
    refresh_players = 0,
    refresh_stores = 0,
    refresh_decks = 0,
    refresh_formats = 0,
    refresh_scenes = 0,
    refresh_users = 0,

    # === STORE FORM STATE ===
    pending_schedules = list(),  # Schedules to add when creating new store

    # === DELETE PERMISSION STATE ===
    # Pattern: can_delete_{entity} + {entity}_{related}_count
    can_delete_store = FALSE,
    can_delete_format = FALSE,
    can_delete_player = FALSE,
    can_delete_archetype = FALSE,
    store_tournament_count = 0,
    format_tournament_count = 0,
    player_result_count = 0,
    archetype_result_count = 0
  )

  # Helper function for ordinal numbers (1st, 2nd, 3rd, etc.)
  ordinal <- function(n) {
    if (is.na(n)) return("-")
    suffix <- c("th", "st", "nd", "rd", rep("th", 6))
    if (n %% 100 >= 11 && n %% 100 <= 13) {
      paste0(n, "th")
    } else {
      paste0(n, suffix[(n %% 10) + 1])
    }
  }

  # ---------------------------------------------------------------------------
  # Source Server Modules
  # ---------------------------------------------------------------------------

  source("server/shared-server.R", local = TRUE)
  source("server/url-routing-server.R", local = TRUE)
  source("server/scene-server.R", local = TRUE)

  # Public page server modules (loaded immediately for all users)
  source("server/public-meta-server.R", local = TRUE)
  source("server/public-stores-server.R", local = TRUE)
  source("server/public-tournaments-server.R", local = TRUE)
  source("server/public-players-server.R", local = TRUE)
  source("server/public-dashboard-server.R", local = TRUE)
  source("server/public-submit-server.R", local = TRUE)

  # ---------------------------------------------------------------------------
  # Lazy-load Admin Modules (only when user logs in as admin)
  # ---------------------------------------------------------------------------
  admin_modules_loaded <- reactiveVal(FALSE)

  observeEvent(rv$is_admin, {
    if (rv$is_admin && !admin_modules_loaded()) {
      # Source admin UI views (defines admin_*_ui variables)
      source("views/admin-results-ui.R", local = TRUE)
      source("views/admin-tournaments-ui.R", local = TRUE)
      source("views/admin-decks-ui.R", local = TRUE)
      source("views/admin-stores-ui.R", local = TRUE)
      source("views/admin-formats-ui.R", local = TRUE)
      source("views/admin-players-ui.R", local = TRUE)
      source("views/admin-users-ui.R", local = TRUE)
      source("views/admin-scenes-ui.R", local = TRUE)

      # Render admin UI into placeholders
      output$admin_results_ui <- renderUI(admin_results_ui)
      output$admin_tournaments_ui <- renderUI(admin_tournaments_ui)
      output$admin_decks_ui <- renderUI(admin_decks_ui)
      output$admin_stores_ui <- renderUI(admin_stores_ui)
      output$admin_formats_ui <- renderUI(admin_formats_ui)
      output$admin_players_ui <- renderUI(admin_players_ui)
      output$admin_users_ui <- renderUI(admin_users_ui)
      output$admin_scenes_ui <- renderUI(admin_scenes_ui)

      # Source admin server modules
      source("server/admin-results-server.R", local = TRUE)
      source("server/admin-tournaments-server.R", local = TRUE)
      source("server/admin-decks-server.R", local = TRUE)
      source("server/admin-stores-server.R", local = TRUE)
      source("server/admin-formats-server.R", local = TRUE)
      source("server/admin-players-server.R", local = TRUE)
      source("server/admin-users-server.R", local = TRUE)
      source("server/admin-scenes-server.R", local = TRUE)
      source("server/admin-notifications-server.R", local = TRUE)
      admin_modules_loaded(TRUE)
    }
  }, ignoreInit = TRUE)

  # ---------------------------------------------------------------------------
  # Rating Cache Queries (reactive)
  # Ratings are pre-computed and stored in cache tables for performance.
  # Cache is refreshed when results are entered/modified.
  # ---------------------------------------------------------------------------

  # Reactive: Get cached competitive ratings for all players
  player_competitive_ratings <- reactive({
    rv$data_refresh  # Invalidate on scene change (global)
    rv$refresh_tournaments  # Invalidate when results change (triggers rating recalc)
    rv$refresh_players  # Invalidate when players change
    safe_query(db_pool,
      "SELECT player_id, competitive_rating FROM player_ratings_cache",
      default = data.frame(player_id = integer(), competitive_rating = numeric()))
  })

  # Reactive: Get cached achievement scores for all players
  player_achievement_scores <- reactive({
    rv$data_refresh
    rv$refresh_tournaments
    rv$refresh_players
    safe_query(db_pool,
      "SELECT player_id, achievement_score FROM player_ratings_cache",
      default = data.frame(player_id = integer(), achievement_score = numeric()))
  })

  # Reactive: Get cached average player rating per store
  store_avg_ratings <- reactive({
    rv$data_refresh
    rv$refresh_tournaments
    rv$refresh_stores
    safe_query(db_pool,
      "SELECT store_id, avg_player_rating FROM store_ratings_cache",
      default = data.frame(store_id = integer(), avg_player_rating = numeric()))
  })


}

# =============================================================================
# Run App
# =============================================================================

onStop(function() { close_db_pool(db_pool) })

shinyApp(ui = ui, server = server)
