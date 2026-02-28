# views/about-ui.R
# About page UI - introduction to DigiLab

about_ui <- div(
class = "content-page",

  # Header
  div(
    class = "content-page-header",
    h1(class = "content-page-title", "About DigiLab"),
    p(class = "content-page-subtitle", "Tournament tracking for the Digimon TCG community")
  ),

  # Hero section
  div(
    class = "about-hero",
    div(
      class = "about-mascot-walkway",
      div(class = "about-mascot-walker",
        div(class = "about-mascot-dust"),
        agumon_svg(size = "64px")
      )
    ),
    p(class = "about-tagline", "Track. Compete. Connect."),
    p(class = "about-description",
      "DigiLab is a community-built platform for tracking Digimon TCG tournament results, ",
      "player ratings, and deck meta across local and online scenes."
    )
  ),

  # What is DigiLab
  div(
    class = "content-section",
    h2(class = "content-section-title",
       bsicons::bs_icon("info-circle"), "What is DigiLab?"),
    p("DigiLab brings tournament data to your Digimon TCG community. Unlike global meta trackers, ",
      "DigiLab is scene-based \u2014 it helps you understand how you stack up against the players ",
      "you actually compete with, whether that's at your local game store or in online webcam tournaments."),
    tags$ul(
      tags$li("Track your tournament history and rating progression"),
      tags$li("See what decks are performing in your scene's meta"),
      tags$li("Compare performance across stores and online events"),
      tags$li("Discover active tournament locations and communities")
    )
  ),

  # Who is it for
  div(
    class = "content-section",
    h2(class = "content-section-title",
       bsicons::bs_icon("people"), "Who is it For?"),
    p(strong("Players"), " \u2014 Track your results, see your rating, and follow your local meta"),
    p(strong("Tournament Organizers"), " \u2014 Upload results via Bandai TCG+ screenshots or get contributor access"),
    p(strong("Online Competitors"), " \u2014 Limitless and webcam tournament data syncs automatically"),
    p(strong("Community Builders"), " \u2014 Share community links, build store pages, and grow your scene")
  ),

  # Active Scenes with live stats
  div(
    class = "content-section",
    h2(class = "content-section-title",
       bsicons::bs_icon("globe"), "Active Scenes"),
    p("DigiLab tracks Digimon TCG communities across multiple scenes. ",
      "Each scene has its own stores, players, and meta data. ",
      "Want your area added? See the ",
      actionLink("about_to_for_tos", "For Organizers page"), "."),

    # Live stats (populated by server)
    div(
      class = "about-stats-grid",
      div(
        class = "about-stat-item",
        div(class = "about-stat-value", textOutput("about_scene_count", inline = TRUE)),
        div(class = "about-stat-label", "Active Scenes")
      ),
      div(
        class = "about-stat-item",
        div(class = "about-stat-value", textOutput("about_store_count", inline = TRUE)),
        div(class = "about-stat-label", "Active Stores")
      ),
      div(
        class = "about-stat-item",
        div(class = "about-stat-value", textOutput("about_player_count", inline = TRUE)),
        div(class = "about-stat-label", "Players Tracked")
      ),
      div(
        class = "about-stat-item",
        div(class = "about-stat-value", textOutput("about_tournament_count", inline = TRUE)),
        div(class = "about-stat-label", "Tournaments")
      )
    )
  ),

  # The team / Built by
  div(
    class = "content-section",
    h2(class = "content-section-title",
       bsicons::bs_icon("code-slash"), "Built By"),
    p("DigiLab was created by a Digimon TCG community member who wanted better tools for tracking ",
      "local tournament performance. The project is open source and community-driven."),
    div(
      class = "contact-links contact-links--centered",
      tags$a(
        class = "contact-link",
        href = LINKS$discord,
        target = "_blank",
        bsicons::bs_icon("discord"), "Discord"
      ),
      tags$a(
        class = "contact-link",
        href = LINKS$github,
        target = "_blank",
        bsicons::bs_icon("github"), "View on GitHub"
      ),
      tags$a(
        class = "contact-link",
        href = LINKS$kofi,
        target = "_blank",
        bsicons::bs_icon("cup-hot"), "Support on Ko-fi"
      ),
      tags$a(
        class = "contact-link",
        href = LINKS$discord,
        target = "_blank",
        bsicons::bs_icon("discord"), "Join Discord"
      )
    )
  ),

  # Disclaimer
  div(
    class = "content-section",
    h2(class = "content-section-title",
       bsicons::bs_icon("exclamation-triangle"), "Disclaimer"),
    p(class = "text-muted",
      "DigiLab is a fan-made community tool and is not affiliated with, endorsed by, or ",
      "connected to Bandai Namco, Bandai Card Games, or any official Digimon TCG organization. ",
      "All Digimon-related trademarks and copyrights belong to their respective owners.")
  )
)
