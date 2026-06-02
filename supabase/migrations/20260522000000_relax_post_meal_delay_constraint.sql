-- Relax post_meal_delay_minutes check constraint from BETWEEN 15 AND 180 to BETWEEN 1 AND 180.
-- The UI allows values as low as 5 minutes, which the original constraint rejected.
ALTER TABLE notification_preferences
  DROP CONSTRAINT IF EXISTS notification_preferences_post_meal_delay_minutes_check;

ALTER TABLE notification_preferences
  ADD CONSTRAINT notification_preferences_post_meal_delay_minutes_check
    CHECK (post_meal_delay_minutes BETWEEN 1 AND 180);
