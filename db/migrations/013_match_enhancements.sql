-- Migration 013: Match History Enhancements
-- Allow byes/defaults (NULL opponent), track match type and source

-- Allow NULL opponent_id for byes/defaults
ALTER TABLE matches ALTER COLUMN opponent_id DROP NOT NULL;

-- Match type: normal, bye, default
ALTER TABLE matches ADD COLUMN IF NOT EXISTS match_type VARCHAR(10) DEFAULT 'normal';

-- Source tracking: limitless, ocr, manual
ALTER TABLE matches ADD COLUMN IF NOT EXISTS source VARCHAR(20) DEFAULT 'manual';

-- Backfill existing data
UPDATE matches SET source = 'limitless'
WHERE tournament_id IN (SELECT tournament_id FROM tournaments WHERE limitless_id IS NOT NULL);

UPDATE matches SET source = 'ocr'
WHERE source = 'manual'
  AND tournament_id NOT IN (SELECT tournament_id FROM tournaments WHERE limitless_id IS NOT NULL);
