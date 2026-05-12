-- Phase 11: Unified Signal Engine — food_signals table + analysis state tracking

-- New table: food_signals (replaces food_triggers for new signal engine)
CREATE TABLE food_signals (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID REFERENCES auth.users NOT NULL,
  category            TEXT NOT NULL,
  outcome_type        TEXT NOT NULL CHECK (outcome_type IN ('symptom', 'wellbeing')),
  outcome_name        TEXT NOT NULL,
  direction           TEXT NOT NULL CHECK (direction IN ('harmful', 'beneficial')),
  peak_window_minutes INT,
  meal_slot           TEXT,
  wellbeing_slot      TEXT,
  relative_risk       NUMERIC(6,3),
  score_delta         NUMERIC(6,3),
  unified_score       NUMERIC(5,4),
  evidence_count      INT NOT NULL DEFAULT 0,
  analyzed_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_food_signals_ranking
  ON food_signals (user_id, unified_score DESC);

ALTER TABLE food_signals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "signals_owner_only" ON food_signals
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- Track when each user's analysis last ran
ALTER TABLE health_profile
  ADD COLUMN IF NOT EXISTS last_analyzed_at TIMESTAMPTZ;

-- DEPRECATED: food_triggers is superseded by food_signals (Phase 11).
-- Kept for backward compatibility until Phase 11 Phase 7 cleanup.
COMMENT ON TABLE food_triggers IS 'DEPRECATED — superseded by food_signals (Plan 11). Do not write new data here.';
