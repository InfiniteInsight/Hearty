-- Plan D: on-device voice dictation preferences.
-- Defaults mirror the Flutter UserPreferences defaults exactly (a fresh install
-- bootstraps from GET /api/preferences, so a mismatched server default would
-- silently override the local one): cloud dormant, auto-submit on at 2.5s,
-- Moonshine as the default on-device model.

ALTER TABLE notification_preferences
  ADD COLUMN IF NOT EXISTS use_cloud_when_online       BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS auto_submit                 BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS auto_submit_silence_seconds REAL    NOT NULL DEFAULT 2.5,
  ADD COLUMN IF NOT EXISTS use_on_device_model         TEXT    NOT NULL DEFAULT 'moonshine'
    CHECK (use_on_device_model IN ('moonshine', 'parakeet'));
