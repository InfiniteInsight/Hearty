-- Plan D: on-device voice dictation preferences.
-- Defaults mirror the Flutter UserPreferences defaults exactly (a fresh install
-- bootstraps from GET /api/preferences, so a mismatched server default would
-- silently override the local one): cloud dormant, auto-submit on at 2.5s,
-- Parakeet-110m (NeMo TDT-CTC) is the default on-device model (D5 device gate,
-- 2026-06-09): it matched Parakeet-0.6b accuracy on short symptom words at
-- ~half the warm RAM. The 0.6b stays selectable as the heavier max-accuracy
-- option. (Moonshine and Zipformer-GigaSpeech were trialled and dropped.)

ALTER TABLE notification_preferences
  ADD COLUMN IF NOT EXISTS use_cloud_when_online       BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS auto_submit                 BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS auto_submit_silence_seconds REAL    NOT NULL DEFAULT 2.5,
  ADD COLUMN IF NOT EXISTS use_on_device_model         TEXT    NOT NULL DEFAULT 'parakeetCtc110m'
    CHECK (use_on_device_model IN ('parakeetCtc110m', 'parakeet'));
