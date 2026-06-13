-- Monthly Trends Conversation — user verdicts on signals (feedback overlay).
-- Separate from food_signals so verdicts survive the signal engine's
-- delete-and-recompute on every analysis run. score_at_verdict stores the
-- unified_score at dispute time so a disputed signal only resurfaces once the
-- evidence has grown materially stronger.

CREATE TABLE signal_feedback (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID REFERENCES auth.users NOT NULL,
  category         TEXT NOT NULL,
  outcome_type     TEXT NOT NULL CHECK (outcome_type IN ('symptom', 'wellbeing')),
  outcome_name     TEXT NOT NULL,
  verdict          TEXT NOT NULL CHECK (verdict IN ('confirmed', 'disputed', 'snoozed')),
  score_at_verdict NUMERIC(5,4),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, category, outcome_type, outcome_name)
);

CREATE INDEX idx_signal_feedback_lookup
  ON signal_feedback (user_id, category, outcome_type, outcome_name);

ALTER TABLE signal_feedback ENABLE ROW LEVEL SECURITY;

CREATE POLICY "signal_feedback_owner_only" ON signal_feedback
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
