-- Plan D: on-device voice dictation preferences.
-- Defaults mirror the Flutter UserPreferences defaults exactly (a fresh install
-- bootstraps from GET /api/preferences, so a mismatched server default would
-- silently override the local one): cloud dormant, auto-submit on at 2.5s,
-- Parakeet as the default on-device model (D5 device verify, 2026-06-08:
-- Moonshine blanked/mis-heard short symptom words like "bloating"; Parakeet
-- transcribed them cleanly. Moonshine stays selectable).

ALTER TABLE notification_preferences
  ADD COLUMN IF NOT EXISTS use_cloud_when_online       BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS auto_submit                 BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS auto_submit_silence_seconds REAL    NOT NULL DEFAULT 2.5,
  ADD COLUMN IF NOT EXISTS use_on_device_model         TEXT    NOT NULL DEFAULT 'parakeet'
    CHECK (use_on_device_model IN ('moonshine', 'parakeet'));
