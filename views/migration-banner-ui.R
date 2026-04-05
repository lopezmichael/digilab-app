# views/migration-banner-ui.R
# Persistent non-dismissible banner announcing migration to digilab.cards

migration_banner_ui <- function() {
  div(
    class = "migration-banner",
    div(
      class = "migration-banner-content",
      div(
        class = "migration-banner-text",
        bsicons::bs_icon("megaphone-fill", class = "migration-banner-icon"),
        span(
          HTML("<strong>DigiLab 2.0 is here!</strong> We've rebuilt player profiles, meta analysis, tournaments & store pages from the ground up with way more depth. Starting May 1st, all data views move exclusively to "),
          tags$a(href = "https://digilab.cards", target = "_blank", rel = "noopener", "digilab.cards"),
          HTML(". This app will become <strong>submission-only</strong> for uploading results, decklists & match data.")
        )
      ),
      tags$a(
        href = "https://digilab.cards",
        target = "_blank",
        rel = "noopener",
        class = "migration-banner-btn",
        bsicons::bs_icon("box-arrow-up-right"),
        "Visit digilab.cards"
      )
    )
  )
}
