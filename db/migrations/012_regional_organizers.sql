-- Migration 012: Add regional organizer flag to stores
-- Regional TOs (e.g., Olli Baba) are similar to online organizers but for in-person regionals.
-- They have no fixed address but are categorized by country/continent.

ALTER TABLE stores ADD COLUMN IF NOT EXISTS is_regional_organizer BOOLEAN DEFAULT FALSE;

-- Venue name on tournaments for regionals where venue ≠ organizer
ALTER TABLE tournaments ADD COLUMN IF NOT EXISTS venue_name TEXT;
