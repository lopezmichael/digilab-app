# =============================================================================
# DigimonCard.io API Integration
# DigiLab - https://app.digilab.cards/
#
# API Documentation: https://digimoncard.io/index.php/api-documentation
# Rate Limit: 15 requests per 10 seconds per IP
#
# Note: httr is loaded on-demand via namespacing (httr::) to avoid loading
# at app startup. This API is rarely called since cards are cached in DB.
# =============================================================================

library(jsonlite)

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

DIGIMONCARD_API_BASE <- "https://digimoncard.io/index.php/api-public"
DIGIMONCARD_IMAGE_BASE <- "https://images.digimoncard.io/images/cards"

# Simple rate limiter - track last request time
.api_state <- new.env(parent = emptyenv())
.api_state$last_request <- Sys.time() - 1  # Allow immediate first request
.api_state$request_count <- 0
.api_state$window_start <- Sys.time()

# -----------------------------------------------------------------------------
# Rate Limiting
# -----------------------------------------------------------------------------

#' Wait if necessary to respect rate limits (15 req / 10 sec)
rate_limit_wait <- function() {
  now <- Sys.time()

 # Reset window if more than 10 seconds have passed
  if (as.numeric(difftime(now, .api_state$window_start, units = "secs")) > 10) {
    .api_state$request_count <- 0
    .api_state$window_start <- now
  }

  # If we've made 15 requests in this window, wait
 if (.api_state$request_count >= 15) {
    wait_time <- 10 - as.numeric(difftime(now, .api_state$window_start, units = "secs"))
    if (wait_time > 0) {
      message("Rate limit: waiting ", round(wait_time, 1), " seconds...")
      Sys.sleep(wait_time + 0.1)
    }
    .api_state$request_count <- 0
    .api_state$window_start <- Sys.time()
  }

  .api_state$request_count <- .api_state$request_count + 1
}

# -----------------------------------------------------------------------------
# Core API Functions
# -----------------------------------------------------------------------------

#' Search for cards using the DigimonCard.io API
#'
#' @param card_number Card number (e.g., "BT12-070")
#' @param name Card name (partial match)
#' @param color Card color (Red, Blue, Yellow, Green, Purple, Black, White)
#' @param type Card type (Digimon, Tamer, Option)
#' @param series Series name
#' @param pack Booster pack name
#' @param digi_type Digimon type (e.g., "Dragon", "Wizard")
#' @param sort Sort field (name, cardnumber, color, etc.)
#' @param sort_direction Sort direction ("asc" or "desc")
#' @param limit Maximum number of results to return (default 100)
#' @return Data frame of matching cards, or NULL if error/no results
#' @export
search_cards <- function(card_number = NULL,
                         name = NULL,
                         color = NULL,
                         type = NULL,
                         series = NULL,
                         pack = NULL,
                         digi_type = NULL,
                         sort = NULL,
                         sort_direction = NULL,
                         limit = 100) {

  # Build query parameters
  params <- list()
  if (!is.null(card_number)) params$card <- card_number
  if (!is.null(name)) params$n <- name
  if (!is.null(color)) params$color <- color
  if (!is.null(type)) params$type <- type
  if (!is.null(series)) params$series <- series
  if (!is.null(pack)) params$pack <- pack
  if (!is.null(digi_type)) params$digitype <- digi_type
  if (!is.null(sort)) params$sort <- sort
  if (!is.null(sort_direction)) params$sortdirection <- sort_direction
  if (!is.null(limit)) params$limit <- limit

  if (length(params) == 0) {
    warning("At least one search parameter is required")
    return(NULL)
  }

  # Rate limit
  rate_limit_wait()

  # Make request
  url <- paste0(DIGIMONCARD_API_BASE, "/search")

  tryCatch({
    response <- httr::GET(
      url,
      query = params,
      httr::add_headers(
        `User-Agent` = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        `Accept` = "application/json, text/plain, */*",
        `Accept-Language` = "en-US,en;q=0.9",
        `Referer` = "https://digimoncard.io/"
      )
    )

    if (httr::status_code(response) == 429) {
      warning("Rate limited by API. Waiting 60 seconds...")
      Sys.sleep(60)
      response <- httr::GET(url, query = params)
    }

    if (httr::status_code(response) == 400) {
      # No results found
      return(NULL)
    }

    if (httr::status_code(response) != 200) {
      warning("API error: HTTP ", httr::status_code(response))
      return(NULL)
    }

    # Parse response
    resp_content <- httr::content(response, as = "text", encoding = "UTF-8")
    cards <- fromJSON(resp_content, flatten = TRUE)

    if (length(cards) == 0) {
      return(NULL)
    }

    return(as.data.frame(cards))

  }, error = function(e) {
    message("DigimonCard API request failed: ", e$message)
    message("URL: ", url)
    message("Params: ", paste(names(params), params, sep = "=", collapse = ", "))
    return(NULL)
  })
}

#' Get a specific card by its card number
#'
#' @param card_number Card number (e.g., "BT12-070")
#' @return Single-row data frame with card details, or NULL if not found
#' @export
get_card <- function(card_number) {
  result <- search_cards(card_number = card_number)

  if (is.null(result) || nrow(result) == 0) {
    return(NULL)
  }

  # Return exact match if multiple results
  exact <- result[result$cardnumber == card_number, ]
  if (nrow(exact) > 0) {
    return(exact[1, ])
  }

  return(result[1, ])
}

#' Search cards by name
#'
#' @param name Card name (partial match supported)
#' @param color Optional color filter
#' @param limit Maximum results to return (default 100)
#' @return Data frame of matching cards, sorted by newest set first
#' @export
search_by_name <- function(name, color = NULL, limit = 100) {
  # Sort by card number descending so newer sets (BT24, EX10) appear first
  search_cards(name = name, color = color, sort = "cardnumber", sort_direction = "desc", limit = limit)
}

#' Get all cards of a specific color
#'
#' @param color Card color
#' @param type Optional type filter (Digimon, Tamer, Option)
#' @return Data frame of matching cards
#' @export
search_by_color <- function(color, type = NULL) {
  search_cards(color = color, type = type)
}

# -----------------------------------------------------------------------------
# Image URL Helpers
# -----------------------------------------------------------------------------
#' Get the image URL for a card
#'
#' @param card_number Card number (e.g., "BT12-070")
#' @return URL string for the card image
#' @export
get_card_image_url <- function(card_number) {
  # DigimonCard.io image URL format
  # https://images.digimoncard.io/images/cards/EX10-074.webp

  paste0(DIGIMONCARD_IMAGE_BASE, "/", card_number, ".webp")
}

#' Get image URLs for multiple cards
#'
#' @param card_numbers Vector of card numbers
#' @return Named vector of URLs
#' @export
get_card_image_urls <- function(card_numbers) {
  urls <- sapply(card_numbers, get_card_image_url)
  names(urls) <- card_numbers
  return(urls)
}

# -----------------------------------------------------------------------------
# Local Database Search (uses cached cards table)
# -----------------------------------------------------------------------------

#' Search cards from local database cache
#'
#' @param con Database connection
#' @param name Card name (partial match)
#' @param card_types Vector of types to include (default: Digimon, Tamer)
#' @param limit Max results
#' @return Data frame of matching cards
#' @export
search_cards_local <- function(con, name, card_types = c("Digimon", "Tamer"), limit = 100) {
  # Build types filter
  types_sql <- paste0("'", card_types, "'", collapse = ", ")

  # Escape single quotes in search term
  name_escaped <- gsub("'", "''", name)

  sql <- sprintf("
    SELECT card_id, name, display_name, card_type, color, color2,
           level, dp, digi_type, stage, set_code
    FROM cards
    WHERE LOWER(name) LIKE LOWER('%%%s%%')
      AND card_type IN (%s)
    ORDER BY set_code DESC, name
    LIMIT %d
  ", name_escaped, types_sql, limit)

  tryCatch({
    result <- DBI::dbGetQuery(con, sql)
    if (nrow(result) == 0) return(NULL)

    # Add id column for compatibility with existing code
    result$id <- result$card_id

    return(result)
  }, error = function(e) {
    message("Local card search failed: ", e$message)
    return(NULL)
  })
}

# -----------------------------------------------------------------------------
# Utility Functions
# -----------------------------------------------------------------------------

#' Get all available colors
#' @return Character vector of valid colors
#' @export
get_colors <- function() {
  c("Red", "Blue", "Yellow", "Green", "Purple", "Black", "White")
}

#' Get all card types
#' @return Character vector of valid card types
#' @export
get_card_types <- function() {
  c("Digimon", "Tamer", "Option", "Digi-Egg")
}

#' Extract key card info into a simplified data frame
#'
#' @param cards Data frame from search_cards()
#' @return Simplified data frame with key columns
#' @export
simplify_cards <- function(cards) {
  if (is.null(cards) || nrow(cards) == 0) {
    return(NULL)
  }

  # Select and rename key columns (handle missing columns gracefully)
  cols_to_keep <- c("cardnumber", "name", "color", "type", "dp", "play_cost",
                    "evolution_cost", "level", "digi_type", "stage", "rarity")

  available_cols <- intersect(cols_to_keep, names(cards))
  result <- cards[, available_cols, drop = FALSE]

  # Add image URL
  result$image_url <- get_card_image_url(result$cardnumber)

  return(result)
}

#' Test the API connection
#'
#' @return TRUE if API is accessible, FALSE otherwise
#' @export
test_api_connection <- function() {
  cat("Testing DigimonCard.io API connection...\n")

  # Try to fetch a known card
  result <- get_card("BT1-001")

  if (!is.null(result)) {
    cat("Success! Retrieved:", result$name, "(", result$cardnumber, ")\n")
    cat("Image URL:", get_card_image_url(result$cardnumber), "\n")
    return(TRUE)
  } else {
    cat("Failed to connect to API.\n")
    return(FALSE)
  }
}
