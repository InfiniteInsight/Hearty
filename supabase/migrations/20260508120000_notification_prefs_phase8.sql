-- Phase 8: add FCM token + new notification preference columns

ALTER TABLE notification_preferences
  ADD COLUMN IF NOT EXISTS fcm_token TEXT,
  ADD COLUMN IF NOT EXISTS wake_word_enabled BOOLEAN NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS sync_error_alerts_enabled BOOLEAN NOT NULL DEFAULT true;

ALTER TABLE health_profile
  ADD COLUMN IF NOT EXISTS medications JSONB DEFAULT '[]'::jsonb;
