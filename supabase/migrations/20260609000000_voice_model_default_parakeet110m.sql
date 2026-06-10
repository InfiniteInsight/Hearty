-- Finalize the on-device transcription model to Parakeet-110m (D5 device gate,
-- 2026-06-09). The earlier 20260607000000 migration created
-- notification_preferences.use_on_device_model with DEFAULT 'moonshine' and a
-- CHECK of ('moonshine','parakeet'); the gate dropped Moonshine and chose
-- Parakeet-110m, keeping the 0.6b as the heavy option. This brings the
-- already-created column to the final lineup.
--
-- Safe in both states: on a DB where 20260607 already ran (column exists with
-- the old default/CHECK) it corrects them; on a fresh DB where 20260607 ran in
-- its edited form (already parakeetCtc110m) every statement below is a no-op.
--
-- ORDER MATTERS: drop the old CHECK BEFORE backfilling, or the UPDATE to
-- 'parakeetCtc110m' violates the still-active old constraint.

-- 1. Drop the old CHECK first (Postgres auto-named the inline constraint
--    <table>_<column>_check) so the backfill below isn't blocked by it.
ALTER TABLE notification_preferences
  DROP CONSTRAINT IF EXISTS notification_preferences_use_on_device_model_check;

-- 2. Migrate rows holding dropped/legacy values (e.g. 'moonshine') to the new
--    default so the tightened CHECK can be re-added without violation.
UPDATE notification_preferences
  SET use_on_device_model = 'parakeetCtc110m'
  WHERE use_on_device_model IS NULL
     OR use_on_device_model NOT IN ('parakeetCtc110m', 'parakeet');

-- 3. New default for rows created from here on.
ALTER TABLE notification_preferences
  ALTER COLUMN use_on_device_model SET DEFAULT 'parakeetCtc110m';

-- 4. Re-add the CHECK with the final allowed set.
ALTER TABLE notification_preferences
  ADD CONSTRAINT notification_preferences_use_on_device_model_check
  CHECK (use_on_device_model IN ('parakeetCtc110m', 'parakeet'));
