-- Migration 014: Add CHECK constraints to match_type and source columns
-- Prevents arbitrary strings from being stored in these fields.

ALTER TABLE matches DROP CONSTRAINT IF EXISTS matches_match_type_check;
ALTER TABLE matches ADD CONSTRAINT matches_match_type_check
  CHECK (match_type IN ('normal', 'bye', 'default'));

ALTER TABLE matches DROP CONSTRAINT IF EXISTS matches_source_check;
ALTER TABLE matches ADD CONSTRAINT matches_source_check
  CHECK (source IN ('limitless', 'ocr', 'manual'));
