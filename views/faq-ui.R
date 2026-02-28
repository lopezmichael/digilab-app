# views/faq-ui.R
# FAQ page UI - expandable accordion sections organized by topic

faq_ui <- div(
  class = "content-page",

  # Header
  div(
    class = "content-page-header",
    h1(class = "content-page-title", "Frequently Asked Questions"),
    p(class = "content-page-subtitle", "Learn how to use DigiLab and understand the metrics")
  ),

  # =========================================================================
  # Category 1: Getting Started
  # =========================================================================
  h2(class = "faq-category", bsicons::bs_icon("compass"), "Getting Started"),
  accordion(
    id = "faq_getting_started",
    open = FALSE,
    accordion_panel(
      title = "What is DigiLab?",
      value = "what-is-digilab",
      icon = bsicons::bs_icon("info-circle"),
      p("DigiLab is a ", strong("community-built tournament tracker"), " for the Digimon Trading Card ",
        "Game. It's designed for regional communities, not as a global meta tool. The focus is on ",
        "your local scene: the players you actually sit across from at locals, the stores you frequent, ",
        "and the decks that define your metagame."),
      p("Everything is organized by ", strong("scenes"), " (metro areas or communities), so the data ",
        "you see is relevant to ", em("your"), " competitive experience.")
    ),
    accordion_panel(
      title = "How do I find my scene?",
      value = "find-scene",
      icon = bsicons::bs_icon("geo"),
      p("Use the ", strong("scene selector"), " in the header bar at the top of the page. ",
        "If location services are enabled, DigiLab will auto-detect your area. Otherwise, ",
        "pick your scene manually from the dropdown."),
      p("Scenes are organized as metro areas and communities. The ", strong("\"Online\""),
        " scene covers webcam tournaments run through platforms like Limitless TCG."),
      p("If your area isn't listed, check the ",
        actionLink("faq_to_for_tos_new_scene", "For Organizers page"),
        " to learn how to request a new scene.")
    ),
    accordion_panel(
      title = "How do I find tournaments near me?",
      value = "find-tournaments",
      icon = bsicons::bs_icon("geo-alt"),
      p("Head to the ", strong("Stores"), " tab to see all active tournament locations. ",
        "The map shows store locations, and clicking on a store reveals their tournament schedule ",
        "and history."),
      p("You can also check the ", strong("Tournaments"), " tab for a chronological list of all ",
        "recorded events. Filter by your scene to narrow down to your area."),
      p("Online events appear in the ", strong("Online"), " scene and are synced automatically ",
        "from Limitless TCG.")
    ),
    accordion_panel(
      title = "How do I see my tournament history?",
      value = "my-history",
      icon = bsicons::bs_icon("clock-history"),
      p("Go to the ", strong("Players"), " tab and search for your name. Click on your row to ",
        "open your player profile, which shows:"),
      tags$ul(
        tags$li("All your tournament results"),
        tags$li("Your rating and achievement score"),
        tags$li("Decks you've played"),
        tags$li("Your performance trend over time")
      )
    ),
    accordion_panel(
      title = "What are community links?",
      value = "community-links",
      icon = bsicons::bs_icon("link-45deg"),
      p("Stores and organizers can share a ", strong("filtered view"), " of DigiLab for their ",
        "community. If you arrive via a community link (a URL with ", tags$code("?community=slug"),
        "), all tabs automatically filter to that community's data."),
      p("Look for the ", strong("community badge"), " in the header when viewing a community-filtered ",
        "page. This makes it easy for organizers to share a link that shows only their store's ",
        "players, tournaments, and meta.")
    )
  ),

  # =========================================================================
  # Category 2: Ratings & Scores
  # =========================================================================
  h2(class = "faq-category", bsicons::bs_icon("graph-up"), "Ratings & Scores"),
  accordion(
    id = "faq_ratings",
    open = FALSE,
    accordion_panel(
      title = "How is Competitive Rating calculated?",
      value = "competitive-rating",
      icon = bsicons::bs_icon("calculator"),
      p("Your Competitive Rating uses an ", strong("Elo-style system"), " adapted for Swiss-style ",
        "tournaments. Unlike traditional Elo that only considers wins/losses, our system uses ",
        strong("implied results"), " based on final placements."),
      p("After each tournament, your rating adjusts based on:"),
      tags$ul(
        tags$li("Your placement relative to ", em("every"), " other player in the tournament"),
        tags$li("The current ratings of those players"),
        tags$li("Whether you placed above or below where your rating predicted")
      ),
      div(class = "formula-box",
          "New Rating = Old Rating + K \u00d7 (Actual Score - Expected Score)"),
      p(strong("K-factor:"), " New players (fewer than 10 tournaments) use K=32, which means ",
        "ratings adjust faster while the system learns your skill level. Established players ",
        "use K=16 for more stable ratings."),
      p(strong("Starting rating:"), " All players begin at 1500."),
      p(strong("Why implied results?"), " In Swiss tournaments, you don't play everyone. If you ",
        "place 3rd and another player places 7th, we treat that as a \"win\" for you against them, ",
        "even if you never actually played. This gives a more complete picture of tournament performance.")
    ),
    accordion_panel(
      title = "What is Achievement Score?",
      value = "achievement-score",
      icon = bsicons::bs_icon("trophy"),
      p("Achievement Score is a ", strong("cumulative points system"), " that rewards both ",
        "participation and strong finishes. Unlike Competitive Rating (which can go up or down), ",
        "Achievement Score only grows over time."),
      p(strong("Base points by placement:")),
      tags$table(
        class = "points-table",
        tags$thead(
          tags$tr(tags$th("Placement"), tags$th("Points"))
        ),
        tags$tbody(
          tags$tr(tags$td("1st Place"), tags$td("10")),
          tags$tr(tags$td("2nd Place"), tags$td("7")),
          tags$tr(tags$td("3rd - 4th"), tags$td("5")),
          tags$tr(tags$td("5th - 8th"), tags$td("3")),
          tags$tr(tags$td("9th - 16th"), tags$td("1")),
          tags$tr(tags$td("17th+"), tags$td("1"))
        )
      ),
      p(strong("Tournament size bonus:"), " Larger tournaments (16+ players) award 50% bonus ",
        "points, reflecting the increased difficulty of placing well against more competition."),
      p(strong("What it measures:"), " Achievement Score reflects your overall engagement with ",
        "the competitive scene. A player with a lower Competitive Rating but high Achievement Score ",
        "is someone who shows up consistently and contributes to the community.")
    ),
    accordion_panel(
      title = "How does Store Rating work?",
      value = "store-rating",
      icon = bsicons::bs_icon("shop"),
      p("Store Rating measures the ", strong("competitive strength"), " of a store's player base. ",
        "It helps answer the question: \"How tough is the competition at this store?\""),
      p(strong("How it's calculated:")),
      tags$ul(
        tags$li("We take the Competitive Ratings of all players who have competed at a store"),
        tags$li("Recent attendees are weighted more heavily than players who haven't been in a while"),
        tags$li("Frequent attendees have slightly more influence than one-time visitors")
      ),
      p(strong("What it means:")),
      tags$ul(
        tags$li(strong("Higher Store Rating"), " = Tougher competition, more experienced players"),
        tags$li(strong("Lower Store Rating"), " = More beginner-friendly, good for new players")
      ),
      p("Store Rating isn't a quality judgment - some players prefer casual environments while ",
        "others seek the most competitive fields. Use it to find stores that match your goals.")
    ),
    accordion_panel(
      title = "Why did my rating go down even though I won matches?",
      value = "rating-down",
      icon = bsicons::bs_icon("arrow-down-circle"),
      p("Rating changes are based on ", em("placement"), ", not just wins. If you were expected to ",
        "place higher based on your rating compared to other players in the tournament, your ",
        "rating may decrease even with a positive record."),
      p("For example, if you're the highest-rated player at a tournament and place 3rd, your ",
        "rating will likely decrease because you underperformed relative to expectations.")
    ),
    accordion_panel(
      title = "Are online and in-person ratings the same?",
      value = "online-ratings",
      icon = bsicons::bs_icon("globe"),
      p("Yes. ", strong("All tournaments feed the same Elo rating pool"), " regardless of whether ",
        "they're in-person locals or online webcam events. This means your rating reflects your ",
        "full competitive performance across all formats."),
      p("Online tournaments synced from Limitless TCG and in-person results uploaded via the app ",
        "are treated identically by the rating system.")
    )
  ),

  # =========================================================================
  # Category 3: Scenes & Regions
  # =========================================================================
  h2(class = "faq-category", bsicons::bs_icon("geo-alt"), "Scenes & Regions"),
  accordion(
    id = "faq_scenes",
    open = FALSE,
    accordion_panel(
      title = "What is a scene?",
      value = "what-is-scene",
      icon = bsicons::bs_icon("people"),
      p("A scene is a ", strong("community of players who regularly compete together"), ", usually ",
        "based on a metro area. DigiLab organizes data by scenes so your leaderboards and meta ",
        "analysis reflect the players you actually face."),
      p("Scenes follow a hierarchy:"),
      tags$ul(
        tags$li(strong("Global"), " \u2014 All players across all regions"),
        tags$li(strong("Country"), " \u2014 National-level view (e.g., United States)"),
        tags$li(strong("State"), " \u2014 State or province level"),
        tags$li(strong("Metro"), " \u2014 Your local metro area (e.g., DFW, Houston)")
      ),
      p("Players don't \"belong\" to a single scene. You appear on any leaderboard where you've ",
        "competed, so playing at multiple locations across scenes is fully supported.")
    ),
    accordion_panel(
      title = "What scenes are currently active?",
      value = "active-scenes",
      icon = bsicons::bs_icon("list-ul"),
      p("Use the ", strong("scene selector dropdown"), " in the header to see all available scenes. ",
        "Each scene has its own stores, players, and tournament data."),
      p("New scenes are added as communities join DigiLab. If you don't see your area, you can ",
        "request a new scene.")
    ),
    accordion_panel(
      title = "How do I request a new scene?",
      value = "request-scene",
      icon = bsicons::bs_icon("plus-circle"),
      p("Visit the ", actionLink("faq_to_for_tos2", "For Organizers page"),
        " for details on getting your community added. Generally, you'll need:"),
      tags$ul(
        tags$li("2\u20133 active stores with regular tournament events"),
        tags$li("A community contact who can help gather initial data"),
        tags$li("Players willing to upload results to get things started")
      ),
      p("We're always excited to expand to new communities!")
    ),
    accordion_panel(
      title = "What is the Online scene?",
      value = "online-scene",
      icon = bsicons::bs_icon("webcam"),
      p("The ", strong("Online"), " scene covers webcam tournaments run through platforms like ",
        strong("Limitless TCG"), ". Online tournament data is synced automatically from Limitless ",
        "on a weekly basis."),
      p("Online and in-person results feed the ", strong("same rating system"), ". Online ",
        "organizers appear in the Stores tab as virtual locations, and their tournaments are ",
        "tracked just like in-person events.")
    )
  ),

  # =========================================================================
  # Category 4: Data & Coverage
  # =========================================================================
  h2(class = "faq-category", bsicons::bs_icon("database"), "Data & Coverage"),
  accordion(
    id = "faq_data",
    open = FALSE,
    accordion_panel(
      title = "Where does the data come from?",
      value = "data-source",
      icon = bsicons::bs_icon("cloud-download"),
      p("DigiLab pulls data from three sources:"),
      tags$ul(
        tags$li(strong("Community uploads"), " \u2014 Anyone can submit results via the ",
                actionLink("faq_to_upload", "Upload Results"),
                " tab using Bandai TCG+ screenshots."),
        tags$li(strong("Limitless TCG sync"), " \u2014 Online webcam tournament results are synced ",
                "automatically on a weekly basis."),
        tags$li(strong("Admin contributors"), " \u2014 Community admins can enter results manually ",
                "for events without screenshots.")
      ),
      p("Card data and images come from the community-maintained ",
        strong("DigimonCard.io"), " API, synced monthly.")
    ),
    accordion_panel(
      title = "How do I upload tournament results?",
      value = "upload-results",
      icon = bsicons::bs_icon("upload"),
      p("Go to the ", actionLink("faq_to_upload3", "Upload Results"), " tab and follow these steps:"),
      tags$ul(
        tags$li(strong("Take screenshots"), " of final standings from the Bandai TCG+ app. Make sure ",
                "placements, usernames, and member numbers are visible."),
        tags$li(strong("Fill in tournament details"), " \u2014 store, date, event type, format, ",
                "player count, and number of rounds."),
        tags$li(strong("Upload screenshots"), " \u2014 Our OCR system reads the images and extracts ",
                "data automatically."),
        tags$li(strong("Review results"), " \u2014 Fix any OCR errors and assign deck archetypes ",
                "if known."),
        tags$li(strong("Submit"), " \u2014 Results go live immediately.")
      )
    ),
    accordion_panel(
      title = "How often is data updated?",
      value = "update-frequency",
      icon = bsicons::bs_icon("arrow-repeat"),
      p("It depends on the source:"),
      tags$ul(
        tags$li(strong("Community uploads"), " go live ", strong("immediately")),
        tags$li(strong("Limitless online tournaments"), " sync ", strong("weekly")),
        tags$li(strong("Card data"), " syncs ", strong("monthly"), " from DigimonCard.io")
      ),
      p("Ratings and statistics recalculate automatically when new results are added.")
    ),
    accordion_panel(
      title = "Why isn't my tournament listed?",
      value = "missing-tournament",
      icon = bsicons::bs_icon("question-circle"),
      p("There are a few possible reasons:"),
      tags$ul(
        tags$li("Nobody has uploaded the results yet"),
        tags$li("The store isn't registered in our system"),
        tags$li("The tournament was an unofficial or casual event")
      ),
      p("You can upload results yourself! Go to the ",
        actionLink("faq_to_upload2", "Upload Results"),
        " tab and upload screenshots from Bandai TCG+. See the ",
        actionLink("faq_to_for_tos", "For Organizers page"), " for a step-by-step guide.")
    ),
    accordion_panel(
      title = "Can I request a new deck archetype?",
      value = "request-deck",
      icon = bsicons::bs_icon("plus-square"),
      p("If a deck isn't in the dropdown when assigning archetypes during result submission, ",
        "you can request it be added."),
      p("Use the ", strong("\"Request New Deck\""), " option in the deck selector when uploading ",
        "results. Requests are reviewed and approved by community contributors to keep the ",
        "archetype list clean and consistent.")
    ),
    accordion_panel(
      title = "Can I get my data corrected or removed?",
      value = "data-correction",
      icon = bsicons::bs_icon("pencil-square"),
      p("Yes! If you spot an error in your results or want your data removed, please reach out. ",
        "We want to ensure accuracy and respect player privacy."),
      div(
        class = "contact-links contact-links--centered",
        actionLink("faq_open_data_correction",
          tagList(bsicons::bs_icon("flag"), " Report a Data Error"),
          class = "contact-link"
        ),
        tags$a(
          class = "contact-link",
          href = LINKS$discord,
          target = "_blank",
          bsicons::bs_icon("discord"), "Contact Us on Discord"
        )
      )
    )
  ),

  # =========================================================================
  # Category 5: General
  # =========================================================================
  h2(class = "faq-category", bsicons::bs_icon("chat-dots"), "General"),
  accordion(
    id = "faq_general",
    open = FALSE,
    accordion_panel(
      title = "Is this an official Bandai tool?",
      value = "official",
      icon = bsicons::bs_icon("patch-question"),
      p(strong("No."), " DigiLab is a fan-made community project and is not affiliated with, ",
        "endorsed by, or connected to Bandai Namco, Bandai Card Games, or any official ",
        "Digimon TCG organization.")
    ),
    accordion_panel(
      title = "How can I support DigiLab?",
      value = "support",
      icon = bsicons::bs_icon("heart"),
      p("There are several ways to support the project:"),
      tags$ul(
        tags$li("Submit your tournament results to help grow the database"),
        tags$li("Spread the word to your local community"),
        tags$li("Report bugs or suggest features"),
        tags$li("Join the Discord to connect with other players"),
        tags$li("Support hosting costs via Ko-fi")
      ),
      div(
        class = "contact-links contact-links--centered",
        tags$a(
          class = "contact-link",
          href = LINKS$discord,
          target = "_blank",
          bsicons::bs_icon("discord"), "Join Discord"
        ),
        tags$a(
          class = "contact-link",
          href = LINKS$kofi,
          target = "_blank",
          bsicons::bs_icon("cup-hot"), "Support on Ko-fi"
        )
      )
    ),
    accordion_panel(
      title = "I found a bug! How do I report it?",
      value = "bugs",
      icon = bsicons::bs_icon("bug"),
      p("Thank you for helping improve DigiLab! We appreciate bug reports."),
      p(strong("What to include:")),
      tags$ul(
        tags$li("What you were trying to do"),
        tags$li("What you expected to happen"),
        tags$li("What actually happened"),
        tags$li("Screenshots if possible")
      ),
      div(
        class = "contact-links contact-links--centered",
        actionLink("faq_open_bug_report",
          tagList(bsicons::bs_icon("bug"), " Report a Bug"),
          class = "contact-link"
        )
      )
    ),
    accordion_panel(
      title = "What do the columns in the tables mean?",
      value = "columns",
      icon = bsicons::bs_icon("table"),
      p(strong("Rating"), " \u2014 Your competitive rating (Elo-style score)"),
      p(strong("Score"), " \u2014 Achievement score (points from placements)"),
      p(strong("Record"), " \u2014 Your win-loss-tie record"),
      p(strong("Meta %"), " \u2014 How often a deck appears in tournaments"),
      p(strong("Conv %"), " \u2014 Conversion rate (top finishes / total appearances)")
    ),
    accordion_panel(
      title = "Why does the minimum events filter change between scenes?",
      value = "min-events-filter",
      icon = bsicons::bs_icon("filter"),
      p("The ", strong("Min Events"), " and ", strong("Min Entries"), " filters on the Players and ",
        "Deck Meta tabs adjust their default based on how much tournament data exists in each scene."),
      p(strong("How it works:")),
      tags$ul(
        tags$li(strong("Newer scenes"), " (fewer than 20 tournaments) default to ", strong("\"All\""),
                " so you can see everyone who has competed"),
        tags$li(strong("Growing scenes"), " (20\u2013100 tournaments) default to ", strong("\"5+\""),
                " to highlight returning players"),
        tags$li(strong("Established scenes"), " (100+ tournaments) default to ", strong("\"10+\""),
                " to showcase committed competitors")
      ),
      p("This ensures newer communities don't appear empty while established scenes surface ",
        "meaningful data. You can always change the filter manually to see more or fewer results.")
    )
  )
)
