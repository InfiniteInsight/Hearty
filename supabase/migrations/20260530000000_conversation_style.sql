-- Add user-selectable AI conversation style preference (warm / concise)
ALTER TABLE notification_preferences
  ADD COLUMN IF NOT EXISTS conversation_style TEXT NOT NULL DEFAULT 'warm'
  CHECK (conversation_style IN ('warm', 'concise'));
