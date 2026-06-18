-- Tracked Experiments: a time-boxed elimination test of a harmful food pattern.
-- One active experiment per (category, outcome) at a time. nudged_at gates the
-- one-time mid-course adherence nudge. Mirrors the RLS/owner pattern of food_signals.
CREATE TABLE experiments (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID REFERENCES auth.users NOT NULL,
  category         TEXT NOT NULL,
  direction        TEXT NOT NULL DEFAULT 'eliminate' CHECK (direction IN ('eliminate', 'add')),
  outcome_type     TEXT NOT NULL CHECK (outcome_type IN ('symptom', 'wellbeing')),
  outcome_name     TEXT NOT NULL,
  baseline_start   TIMESTAMPTZ NOT NULL,
  baseline_end     TIMESTAMPTZ NOT NULL,
  experiment_start TIMESTAMPTZ NOT NULL,
  experiment_end   TIMESTAMPTZ NOT NULL,
  status           TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'abandoned')),
  result           JSONB,
  nudged_at        TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- At most one ACTIVE experiment per pattern.
CREATE UNIQUE INDEX uniq_active_experiment
  ON experiments (user_id, category, outcome_type, outcome_name)
  WHERE status = 'active';

CREATE INDEX idx_experiments_user_status ON experiments (user_id, status);

ALTER TABLE experiments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "experiments_owner_only" ON experiments
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
