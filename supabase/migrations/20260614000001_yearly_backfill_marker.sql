-- Multi-year trends: record which past calendar years have been analyzed into
-- food_signals_yearly, INDEPENDENT of whether that year produced any signal rows.
-- Without this, a past year with zero signals (a gap year, or a sparse early
-- year) never appears in food_signals_yearly and would be re-analyzed on every
-- read — defeating the freeze-past-years guarantee. The current year is never
-- added here (it is always recomputed).
ALTER TABLE health_profile
  ADD COLUMN IF NOT EXISTS yearly_backfilled_years JSONB NOT NULL DEFAULT '[]'::jsonb;
