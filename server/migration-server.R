# server/migration-server.R
# Persistent non-dismissible banner announcing migration to digilab.cards
# The one-time announcement modal uses the existing announcements table in scene-server.R

output$migration_banner <- renderUI({
  migration_banner_ui()
})
