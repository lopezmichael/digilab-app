-- =============================================================================
-- Migration 015: Submission Tracking
-- Date: 2026-03-30
-- Adds submission_method to tournaments and reviewed_by to deck_requests
-- for usage analytics and audit trail.
-- =============================================================================

-- 1. Track how tournament data was entered
ALTER TABLE tournaments ADD COLUMN IF NOT EXISTS submission_method VARCHAR(30);

-- Enforce valid values (consistent with match_type/source CHECK constraints in migration 014)
ALTER TABLE tournaments ADD CONSTRAINT chk_submission_method
  CHECK (submission_method IS NULL OR submission_method IN ('screenshot_ocr', 'csv_upload', 'manual_grid', 'paste_grid', 'limitless_sync'));

-- Backfill: Limitless-synced tournaments have limitless_id set
UPDATE tournaments SET submission_method = 'limitless_sync' WHERE limitless_id IS NOT NULL AND submission_method IS NULL;

-- 2. Track who approved/rejected deck requests
ALTER TABLE deck_requests ADD COLUMN IF NOT EXISTS reviewed_by TEXT;
