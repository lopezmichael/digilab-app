-- Migration 006: Add record_format to tournaments and points to results
-- Stores the original entry format and raw points value alongside W-L-T.
--
-- record_format: 'points' (TCG+ default) or 'wlt' (manual W-L-T entry)
-- points: original points value as entered; NULL for WLT-entered results
--
-- Backfill: All existing tournaments default to 'points'.
-- All existing results get points = (wins * 3) + ties.

-- 1. Add record_format to tournaments
ALTER TABLE tournaments ADD COLUMN IF NOT EXISTS record_format TEXT DEFAULT 'points';

-- 2. Add points to results
ALTER TABLE results ADD COLUMN IF NOT EXISTS points INTEGER;

-- 3. Backfill points for all existing results
UPDATE results SET points = (wins * 3) + ties WHERE points IS NULL;
