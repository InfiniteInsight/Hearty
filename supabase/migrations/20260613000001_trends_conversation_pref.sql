-- Monthly Trends Conversation preference. Mirrors daily_checkin_enabled: a
-- single boolean on notification_preferences gating the monthly trends
-- notification (scheduled at startup, defer-to-tap). Default TRUE must match
-- the Flutter UserPreferences default exactly — a fresh install bootstraps from
-- GET /api/preferences, so a mismatched server default would silently override
-- the local one.

ALTER TABLE notification_preferences
  ADD COLUMN IF NOT EXISTS trends_conversation_enabled BOOLEAN NOT NULL DEFAULT true;
