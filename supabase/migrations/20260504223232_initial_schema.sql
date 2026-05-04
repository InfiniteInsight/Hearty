-- Migration: 20260504223232_initial_schema.sql

CREATE TABLE meals (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID REFERENCES auth.users NOT NULL,
  logged_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  meal_type       TEXT CHECK (meal_type IN (
                    'breakfast','lunch','dinner','snack','drink','supplement','other')),
  description     TEXT NOT NULL,
  foods           JSONB,
  location        TEXT,
  mood_before     INT CHECK (mood_before BETWEEN 1 AND 10),
  hunger_before   INT CHECK (hunger_before BETWEEN 1 AND 10),
  notes           TEXT,
  raw_input       TEXT,
  input_method    TEXT CHECK (input_method IN ('voice','text','photo')),
  sync_status     TEXT NOT NULL DEFAULT 'synced' CHECK (sync_status IN ('synced','pending')),
  offline_id      TEXT UNIQUE,
  created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE symptoms (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID REFERENCES auth.users NOT NULL,
  meal_id          UUID REFERENCES meals(id) ON DELETE SET NULL,
  logged_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  onset_minutes    INT,
  raw_description  TEXT NOT NULL,
  structured_data  JSONB,
  severity_overall INT CHECK (severity_overall BETWEEN 1 AND 10),
  notes            TEXT,
  sync_status      TEXT NOT NULL DEFAULT 'synced' CHECK (sync_status IN ('synced','pending')),
  created_at       TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE wellbeing_snapshots (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID REFERENCES auth.users NOT NULL,
  logged_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  raw_description  TEXT,
  structured_data  JSONB,
  energy_level     INT CHECK (energy_level BETWEEN 1 AND 10),
  mood             INT CHECK (mood BETWEEN 1 AND 10),
  stress_level     INT CHECK (stress_level BETWEEN 1 AND 10),
  sleep_hours      NUMERIC(4,1),
  sleep_quality    INT CHECK (sleep_quality BETWEEN 1 AND 10),
  hydration        INT CHECK (hydration BETWEEN 1 AND 10),
  exercise_minutes INT DEFAULT 0,
  notes            TEXT,
  sync_status      TEXT NOT NULL DEFAULT 'synced' CHECK (sync_status IN ('synced','pending')),
  created_at       TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE food_triggers (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID REFERENCES auth.users NOT NULL,
  food_name         TEXT NOT NULL,
  symptom_type      TEXT NOT NULL,
  confidence_score  NUMERIC(4,2) CHECK (confidence_score BETWEEN 0 AND 1),
  occurrence_count  INT DEFAULT 1,
  avg_onset_minutes INT,
  avg_severity      NUMERIC(4,2),
  last_updated      TIMESTAMPTZ DEFAULT now(),
  is_confirmed      BOOLEAN DEFAULT false,
  notes             TEXT,
  created_at        TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE health_profile (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            UUID REFERENCES auth.users NOT NULL UNIQUE,
  allergens          JSONB DEFAULT '[]'::jsonb,
  intolerances       JSONB DEFAULT '[]'::jsonb,
  conditions         JSONB DEFAULT '[]'::jsonb,
  dietary_protocols  JSONB DEFAULT '[]'::jsonb,
  notes              TEXT,
  created_at         TIMESTAMPTZ DEFAULT now(),
  updated_at         TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE food_log_photos (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  meal_id           UUID REFERENCES meals(id) ON DELETE CASCADE,
  user_id           UUID REFERENCES auth.users NOT NULL,
  photo_url         TEXT NOT NULL,
  photo_type        TEXT CHECK (photo_type IN (
                      'food_plate','barcode','nutrition_label','food_label')),
  processing_status TEXT NOT NULL DEFAULT 'pending'
                      CHECK (processing_status IN ('pending','processing','complete','failed','needs_input')),
  extracted_data    JSONB,
  created_at        TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE offline_queue (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID REFERENCES auth.users NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  action_type TEXT NOT NULL CHECK (action_type IN (
                'log_meal','log_symptoms','log_wellbeing',
                'update_meal','update_symptoms','delete_meal')),
  payload     JSONB NOT NULL,
  synced_at   TIMESTAMPTZ
);

CREATE TABLE notification_preferences (
  id                         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                    UUID REFERENCES auth.users NOT NULL UNIQUE,
  post_meal_enabled          BOOLEAN NOT NULL DEFAULT true,
  post_meal_delay_minutes    INT NOT NULL DEFAULT 60
                               CHECK (post_meal_delay_minutes BETWEEN 15 AND 180),
  daily_checkin_enabled      BOOLEAN NOT NULL DEFAULT false,
  daily_checkin_time         TIME DEFAULT '08:00:00',
  weekly_digest_enabled      BOOLEAN NOT NULL DEFAULT false,
  weekly_digest_day          INT DEFAULT 0 CHECK (weekly_digest_day BETWEEN 0 AND 6),
  quiet_hours_start          TIME,
  quiet_hours_end            TIME,
  custom_triggers            JSONB DEFAULT '[]'::jsonb,
  ai_recommendations_enabled BOOLEAN NOT NULL DEFAULT false,
  created_at                 TIMESTAMPTZ DEFAULT now(),
  updated_at                 TIMESTAMPTZ DEFAULT now()
);

-- Indexes
CREATE INDEX idx_meals_user_logged ON meals (user_id, logged_at DESC);
CREATE INDEX idx_meals_sync_status ON meals (user_id, sync_status) WHERE sync_status = 'pending';
CREATE INDEX idx_symptoms_user_logged ON symptoms (user_id, logged_at DESC);
CREATE INDEX idx_symptoms_meal ON symptoms (meal_id);
CREATE INDEX idx_symptoms_user_meal ON symptoms (user_id, meal_id);
CREATE INDEX idx_wellbeing_user_logged ON wellbeing_snapshots (user_id, logged_at DESC);
CREATE INDEX idx_triggers_user_confidence ON food_triggers (user_id, confidence_score DESC);
CREATE INDEX idx_triggers_food ON food_triggers (user_id, food_name);
CREATE INDEX idx_photos_meal ON food_log_photos (meal_id);
CREATE INDEX idx_photos_processing ON food_log_photos (processing_status)
  WHERE processing_status IN ('pending', 'processing');
CREATE INDEX idx_queue_user_unsynced ON offline_queue (user_id, created_at ASC)
  WHERE synced_at IS NULL;

-- RLS
ALTER TABLE meals                    ENABLE ROW LEVEL SECURITY;
ALTER TABLE symptoms                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE wellbeing_snapshots      ENABLE ROW LEVEL SECURITY;
ALTER TABLE food_triggers            ENABLE ROW LEVEL SECURITY;
ALTER TABLE health_profile           ENABLE ROW LEVEL SECURITY;
ALTER TABLE food_log_photos          ENABLE ROW LEVEL SECURITY;
ALTER TABLE offline_queue            ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "meals_owner_only"       ON meals
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "symptoms_owner_only"    ON symptoms
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "wellbeing_owner_only"   ON wellbeing_snapshots
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "triggers_owner_only"    ON food_triggers
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "profile_owner_only"     ON health_profile
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "photos_owner_only"      ON food_log_photos
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "queue_owner_only"       ON offline_queue
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "notif_prefs_owner_only" ON notification_preferences
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
