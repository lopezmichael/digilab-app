-- Migration 011: Add tiebreaker stats and memo from Bandai TCG+ CSV exports
-- These fields are stored for reference but not displayed in results tables.

ALTER TABLE results ADD COLUMN IF NOT EXISTS omw_pct NUMERIC(5,2);
ALTER TABLE results ADD COLUMN IF NOT EXISTS oomw_pct NUMERIC(5,2);
ALTER TABLE results ADD COLUMN IF NOT EXISTS memo TEXT;
