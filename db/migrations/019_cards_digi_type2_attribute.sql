-- Migration 019: Add digi_type2, digi_type3, digi_type4, and attribute columns to cards table
-- These fields come from the DigimonCard.io API but were previously not stored.
-- After running this migration, do a full card sync: python scripts/sync_cards.py --by-set

ALTER TABLE cards ADD COLUMN IF NOT EXISTS digi_type2 VARCHAR;
ALTER TABLE cards ADD COLUMN IF NOT EXISTS digi_type3 VARCHAR;
ALTER TABLE cards ADD COLUMN IF NOT EXISTS digi_type4 VARCHAR;
ALTER TABLE cards ADD COLUMN IF NOT EXISTS attribute VARCHAR;
