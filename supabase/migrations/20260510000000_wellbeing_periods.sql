-- Phase 10: three-slot wellbeing periods + per-slot notification preferences

ALTER TABLE wellbeing_snapshots
  ADD COLUMN IF NOT EXISTS period TEXT
    CHECK (period IN ('morning', 'midday', 'evening'));

ALTER TABLE notification_preferences
  ADD COLUMN IF NOT EXISTS morning_checkin_enabled  BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS morning_checkin_hour     INT     NOT NULL DEFAULT 8,
  ADD COLUMN IF NOT EXISTS morning_checkin_minute   INT     NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS midday_checkin_enabled   BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS midday_checkin_hour      INT     NOT NULL DEFAULT 13,
  ADD COLUMN IF NOT EXISTS midday_checkin_minute    INT     NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS evening_checkin_enabled  BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS evening_checkin_hour     INT     NOT NULL DEFAULT 20,
  ADD COLUMN IF NOT EXISTS evening_checkin_minute   INT     NOT NULL DEFAULT 0;
