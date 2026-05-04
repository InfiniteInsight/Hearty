# Hearty — Spec 01: Database

**Version:** 1.0  
**Date:** 2026-05-04  
**Phase:** Phase 1  
**Status:** Active

---

## 1. Overview

All user data lives in Supabase (PostgreSQL). Row Level Security is enabled on every table — users can only access their own rows. The backend FastAPI service and MCP Server use the service role key for admin-level operations; all user-facing queries flow through RLS.

---

## 2. Tables

### 2.1 `meals`

The primary log table. One row per eating event. Raw input is always preserved; structured data is extracted by AI and stored in `foods` JSONB.

```sql
CREATE TABLE meals (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID REFERENCES auth.users NOT NULL,
  logged_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  meal_type       TEXT CHECK (meal_type IN (
                    'breakfast','lunch','dinner','snack',
                    'drink','supplement','other'
                  )),
  description     TEXT NOT NULL,
  -- AI-extracted food items:
  -- [{"name": "grilled salmon", "quantity": "1 fillet", "unit": "fillet",
  --   "estimated_calories": 300, "data_source": "ai_estimate", "confidence": 0.8}]
  foods           JSONB,
  location        TEXT,
  mood_before     INT CHECK (mood_before BETWEEN 1 AND 10),
  hunger_before   INT CHECK (hunger_before BETWEEN 1 AND 10),
  notes           TEXT,
  raw_input       TEXT,                   -- original voice transcript or typed text
  input_method    TEXT CHECK (input_method IN ('voice','text','photo')),
  sync_status     TEXT NOT NULL DEFAULT 'synced'
                    CHECK (sync_status IN ('synced','pending')),
  offline_id      TEXT UNIQUE,             -- client-generated ID for offline deduplication
  created_at      TIMESTAMPTZ DEFAULT now()
);
```

**`foods` JSONB shape (per item):**
```json
{
  "name": "grilled salmon",
  "quantity": "1 fillet",
  "unit": "fillet",
  "estimated_calories": 300,
  "estimated_protein_g": 42,
  "estimated_carbs_g": 0,
  "estimated_fat_g": 14,
  "data_source": "ai_estimate",
  "confidence": 0.8,
  "barcode": null,
  "brand": null
}
```

`data_source` values: `"usda"`, `"open_food_facts"`, `"nutritionix"`, `"web_search"`, `"ai_estimate"`, `"unknown"`

---

### 2.2 `symptoms`

Free-form symptom log. Raw description always stored; AI extracts structured data into `structured_data`. `meal_id` is optional — symptoms can be logged independently of a meal.

```sql
CREATE TABLE symptoms (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID REFERENCES auth.users NOT NULL,
  meal_id          UUID REFERENCES meals(id) ON DELETE SET NULL,
  logged_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  onset_minutes    INT,                   -- minutes after meal symptom appeared
  raw_description  TEXT NOT NULL,         -- "bloated and really gassy, a bit of heartburn too"
  -- AI-extracted structure:
  -- {"types": ["bloating","gas","acid_reflux"], "bathroom_urgency": 2,
  --  "bathroom_visits": 1, "stool_consistency_bss": 5, "duration_minutes": 45}
  structured_data  JSONB,
  severity_overall INT CHECK (severity_overall BETWEEN 1 AND 10),
  notes            TEXT,
  sync_status      TEXT NOT NULL DEFAULT 'synced'
                     CHECK (sync_status IN ('synced','pending')),
  created_at       TIMESTAMPTZ DEFAULT now()
);
```

**`structured_data` JSONB shape:**
```json
{
  "types": ["bloating", "gas", "acid_reflux"],
  "bathroom_urgency": 2,
  "bathroom_visits": 1,
  "stool_consistency_bss": 5,
  "duration_minutes": 45,
  "body_location": "upper abdomen",
  "modifiers": ["worse when lying down"]
}
```

---

### 2.3 `wellbeing_snapshots`

Holistic daily check-in. Raw description allows voice input; structured numeric fields allow charting. Neither is required — AI fills in what it can extract.

```sql
CREATE TABLE wellbeing_snapshots (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID REFERENCES auth.users NOT NULL,
  logged_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  raw_description TEXT,                  -- "slept badly, energy is terrible, stressed about work"
  -- AI-extracted or directly entered:
  structured_data JSONB,
  energy_level    INT CHECK (energy_level BETWEEN 1 AND 10),
  mood            INT CHECK (mood BETWEEN 1 AND 10),
  stress_level    INT CHECK (stress_level BETWEEN 1 AND 10),
  sleep_hours     NUMERIC(4,1),
  sleep_quality   INT CHECK (sleep_quality BETWEEN 1 AND 10),
  hydration       INT CHECK (hydration BETWEEN 1 AND 10),
  exercise_minutes INT DEFAULT 0,
  notes           TEXT,
  sync_status     TEXT NOT NULL DEFAULT 'synced'
                    CHECK (sync_status IN ('synced','pending')),
  created_at      TIMESTAMPTZ DEFAULT now()
);
```

---

### 2.4 `food_triggers`

Derived/curated table. Populated by the trend analysis engine; can also be manually confirmed by the user. Not written directly by logging flows.

```sql
CREATE TABLE food_triggers (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID REFERENCES auth.users NOT NULL,
  food_name         TEXT NOT NULL,
  symptom_type      TEXT NOT NULL,        -- e.g. "bloating", "acid_reflux"
  confidence_score  NUMERIC(4,2) CHECK (confidence_score BETWEEN 0 AND 1),
  occurrence_count  INT DEFAULT 1,
  avg_onset_minutes INT,
  avg_severity      NUMERIC(4,2),
  last_updated      TIMESTAMPTZ DEFAULT now(),
  is_confirmed      BOOLEAN DEFAULT false,  -- user manually confirmed
  notes             TEXT,
  created_at        TIMESTAMPTZ DEFAULT now()
);
```

---

### 2.5 `health_profile`

One row per user. Stores allergen/intolerance/condition/protocol context used to enrich AI analysis. JSONB arrays allow flexible free-form additions alongside well-known defaults.

```sql
CREATE TABLE health_profile (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            UUID REFERENCES auth.users NOT NULL UNIQUE,
  -- See Section 3 for JSONB shapes
  allergens          JSONB DEFAULT '[]'::jsonb,
  intolerances       JSONB DEFAULT '[]'::jsonb,
  conditions         JSONB DEFAULT '[]'::jsonb,
  dietary_protocols  JSONB DEFAULT '[]'::jsonb,
  notes              TEXT,
  created_at         TIMESTAMPTZ DEFAULT now(),
  updated_at         TIMESTAMPTZ DEFAULT now()
);
```

See Spec 08 (`hearty-08-health-profile.md`) for full JSONB shapes and enumerated values.

---

### 2.6 `food_log_photos`

One row per photo attached to a meal. Processing is async; `processing_status` tracks progress.

```sql
CREATE TABLE food_log_photos (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  meal_id           UUID REFERENCES meals(id) ON DELETE CASCADE,
  user_id           UUID REFERENCES auth.users NOT NULL,
  photo_url         TEXT NOT NULL,        -- Supabase Storage URL
  photo_type        TEXT CHECK (photo_type IN (
                      'food_plate','barcode','nutrition_label','food_label'
                    )),
  processing_status TEXT NOT NULL DEFAULT 'pending'
                      CHECK (processing_status IN (
                        'pending','processing','complete','failed','needs_input'
                      )),
  -- Extracted data varies by photo_type:
  -- food_plate: [{"name": "...", "estimated_calories": ..., ...}]
  -- barcode: {"barcode": "...", "product_name": "...", "brand": "...", ...}
  -- nutrition_label: {"serving_size": "...", "calories": ..., "protein_g": ..., ...}
  -- food_label: {"product_name": "...", "brand": "...", "ingredients": [...], ...}
  extracted_data    JSONB,
  created_at        TIMESTAMPTZ DEFAULT now()
);
```

---

### 2.7 `offline_queue`

Client-side writes while offline are queued here as soon as connectivity is restored. The queue is append-only; rows are not deleted after sync — `synced_at` is set instead, and a cleanup job purges rows older than 30 days.

```sql
CREATE TABLE offline_queue (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID REFERENCES auth.users NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),  -- when the action was taken offline
  action_type TEXT NOT NULL CHECK (action_type IN (
                'log_meal','log_symptoms','log_wellbeing',
                'update_meal','update_symptoms','delete_meal'
              )),
  -- Full serialized payload for the action, e.g. the complete meal object
  payload     JSONB NOT NULL,
  synced_at   TIMESTAMPTZ                          -- null = not yet synced
);
```

**Relationship to `sync_status`:**  
When a meal is written offline, it is saved to local device storage with `sync_status = 'pending'`. On reconnect, the app processes the offline queue in chronological order, creates/updates the Supabase rows, and flips `sync_status` to `'synced'`. The `offline_queue` row gets `synced_at` stamped. The two mechanisms are complementary: `sync_status` on the entity rows is the truth state; `offline_queue` is the work list.

---

### 2.8 `notification_preferences`

One row per user. Created on first login with defaults. All fields can be updated by the user at any time.

```sql
CREATE TABLE notification_preferences (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                 UUID REFERENCES auth.users NOT NULL UNIQUE,
  post_meal_enabled       BOOLEAN NOT NULL DEFAULT true,
  post_meal_delay_minutes INT NOT NULL DEFAULT 60
                            CHECK (post_meal_delay_minutes BETWEEN 15 AND 180),
  daily_checkin_enabled   BOOLEAN NOT NULL DEFAULT false,
  daily_checkin_time      TIME DEFAULT '08:00:00',
  weekly_digest_enabled   BOOLEAN NOT NULL DEFAULT false,
  weekly_digest_day       INT DEFAULT 0   -- 0=Sunday
                            CHECK (weekly_digest_day BETWEEN 0 AND 6),
  quiet_hours_start       TIME,           -- null = no quiet hours
  quiet_hours_end         TIME,
  -- Arbitrary additional rules: [{"label": "after dinner only", "meal_type": "dinner"}]
  custom_triggers         JSONB DEFAULT '[]'::jsonb,
  ai_recommendations_enabled BOOLEAN NOT NULL DEFAULT false,
  created_at              TIMESTAMPTZ DEFAULT now(),
  updated_at              TIMESTAMPTZ DEFAULT now()
);
```

---

## 3. Indexes

```sql
-- meals
CREATE INDEX idx_meals_user_logged ON meals (user_id, logged_at DESC);
CREATE INDEX idx_meals_sync_status ON meals (user_id, sync_status)
  WHERE sync_status = 'pending';

-- symptoms
CREATE INDEX idx_symptoms_user_logged ON symptoms (user_id, logged_at DESC);
CREATE INDEX idx_symptoms_meal ON symptoms (meal_id);
CREATE INDEX idx_symptoms_user_meal ON symptoms (user_id, meal_id);

-- wellbeing_snapshots
CREATE INDEX idx_wellbeing_user_logged ON wellbeing_snapshots (user_id, logged_at DESC);

-- food_triggers
CREATE INDEX idx_triggers_user_confidence ON food_triggers (user_id, confidence_score DESC);
CREATE INDEX idx_triggers_food ON food_triggers (user_id, food_name);

-- food_log_photos
CREATE INDEX idx_photos_meal ON food_log_photos (meal_id);
CREATE INDEX idx_photos_processing ON food_log_photos (processing_status)
  WHERE processing_status IN ('pending', 'processing');

-- offline_queue
CREATE INDEX idx_queue_user_unsynced ON offline_queue (user_id, created_at ASC)
  WHERE synced_at IS NULL;
```

---

## 4. Row Level Security Policies

RLS is enabled on all tables. Each table gets an owner-only policy. The backend uses the service role key and bypasses RLS for trend analysis and admin operations — this key is never sent to clients.

```sql
-- Enable RLS
ALTER TABLE meals                   ENABLE ROW LEVEL SECURITY;
ALTER TABLE symptoms                ENABLE ROW LEVEL SECURITY;
ALTER TABLE wellbeing_snapshots     ENABLE ROW LEVEL SECURITY;
ALTER TABLE food_triggers           ENABLE ROW LEVEL SECURITY;
ALTER TABLE health_profile          ENABLE ROW LEVEL SECURITY;
ALTER TABLE food_log_photos         ENABLE ROW LEVEL SECURITY;
ALTER TABLE offline_queue           ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_preferences ENABLE ROW LEVEL SECURITY;

-- meals
CREATE POLICY "meals_owner_only" ON meals
  FOR ALL USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- symptoms
CREATE POLICY "symptoms_owner_only" ON symptoms
  FOR ALL USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- wellbeing_snapshots
CREATE POLICY "wellbeing_owner_only" ON wellbeing_snapshots
  FOR ALL USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- food_triggers
CREATE POLICY "triggers_owner_only" ON food_triggers
  FOR ALL USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- health_profile
CREATE POLICY "profile_owner_only" ON health_profile
  FOR ALL USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- food_log_photos (has its own user_id column — policy does not go through meal_id)
CREATE POLICY "photos_owner_only" ON food_log_photos
  FOR ALL USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- offline_queue
CREATE POLICY "queue_owner_only" ON offline_queue
  FOR ALL USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- notification_preferences
CREATE POLICY "notif_prefs_owner_only" ON notification_preferences
  FOR ALL USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
```

---

## 5. Auth Setup Notes

### 5.1 Google OAuth (Android)

1. In Supabase Dashboard → Authentication → Providers → Google: enable and add OAuth credentials
2. Add SHA-1 fingerprint of Android signing key to the Google Cloud Console OAuth client
3. Flutter uses `supabase_flutter` + `google_sign_in` packages
4. On sign-in, exchange Google ID token for Supabase session: `supabase.auth.signInWithIdToken(...)`

### 5.2 Magic Link (Web)

1. In Supabase Dashboard → Authentication → Providers → Email: enable "Magic links"
2. Disable password sign-in (magic link only)
3. React app calls `supabase.auth.signInWithOtp({ email })` and handles the callback URL

### 5.3 JWT Usage

- All FastAPI endpoints verify the JWT via Supabase's JWKS endpoint
- All MCP Server tool calls verify the JWT before executing database operations
- Token expiry: default 1 hour access token; 7-day refresh token
- Flutter and React both use `supabase_flutter` / `@supabase/supabase-js` for automatic token refresh

---

## 6. Seed Data / Bootstrap

On first login, the backend automatically creates:
- A blank `health_profile` row for the user
- A `notification_preferences` row with defaults

These are created via FastAPI on the `/auth/on-login` webhook from Supabase Auth, not by the client.

---

## 7. Migration Strategy

- All schema changes tracked as timestamped SQL migration files in `supabase/migrations/`
- Supabase CLI (`supabase db push`) used for deployments
- Breaking changes (dropping columns, changing types) require explicit migration with backfill step documented in the migration file
- JSONB columns are intentionally schema-flexible — adding new fields to JSONB shapes does not require a migration, only documentation updates in this spec
- `offline_id` on `meals` enables idempotent upsert: `INSERT ... ON CONFLICT (offline_id) DO NOTHING` prevents duplicate rows from retry logic

---

## 8. Full Migration File (Initial)

```sql
-- Migration: 20260504000001_initial_schema.sql

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
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                 UUID REFERENCES auth.users NOT NULL UNIQUE,
  post_meal_enabled       BOOLEAN NOT NULL DEFAULT true,
  post_meal_delay_minutes INT NOT NULL DEFAULT 60
                            CHECK (post_meal_delay_minutes BETWEEN 15 AND 180),
  daily_checkin_enabled   BOOLEAN NOT NULL DEFAULT false,
  daily_checkin_time      TIME DEFAULT '08:00:00',
  weekly_digest_enabled   BOOLEAN NOT NULL DEFAULT false,
  weekly_digest_day       INT DEFAULT 0 CHECK (weekly_digest_day BETWEEN 0 AND 6),
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

CREATE POLICY "meals_owner_only"    ON meals
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "symptoms_owner_only" ON symptoms
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "wellbeing_owner_only" ON wellbeing_snapshots
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "triggers_owner_only" ON food_triggers
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "profile_owner_only"  ON health_profile
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "photos_owner_only"   ON food_log_photos
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "queue_owner_only"    ON offline_queue
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
CREATE POLICY "notif_prefs_owner_only" ON notification_preferences
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
```
