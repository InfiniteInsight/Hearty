-- Photo retention: timestamp when the raw image was deleted from Storage.
-- NULL = image still stored; non-null = purged (derived data is unaffected).
alter table food_log_photos add column if not exists image_purged_at timestamptz;
