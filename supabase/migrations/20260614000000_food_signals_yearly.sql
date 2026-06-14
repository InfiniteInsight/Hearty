-- Multi-year trends: one immutable signal set per calendar year. Past years are
-- computed once and frozen; the current year is recomputed as data lands. The
-- pure signal_persistence layer joins these against the live food_signals to
-- annotate recurrence. Identity (category, outcome_type, outcome_name) matches
-- signal_feedback so verdicts and persistence line up.
CREATE TABLE food_signals_yearly (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID REFERENCES auth.users NOT NULL,
  year           INTEGER NOT NULL,
  category       TEXT NOT NULL,
  outcome_type   TEXT NOT NULL CHECK (outcome_type IN ('symptom', 'wellbeing')),
  outcome_name   TEXT NOT NULL,
  direction      TEXT NOT NULL,
  unified_score  NUMERIC,
  relative_risk  NUMERIC,
  evidence_count INTEGER NOT NULL DEFAULT 0,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, year, category, outcome_type, outcome_name)
);

CREATE INDEX idx_food_signals_yearly_lookup ON food_signals_yearly (user_id, year);

ALTER TABLE food_signals_yearly ENABLE ROW LEVEL SECURITY;

CREATE POLICY "food_signals_yearly_owner_only" ON food_signals_yearly
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
