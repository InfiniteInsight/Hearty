-- Daily check-in: persist the per-meal symptom follow-up outcome so the evening
-- check-in can resurface dismissed follow-ups (gap A). 'resurfaced' marks that
-- the evening check-in has already offered its one retry.
--
-- Existing rows stay NULL (no follow-up recorded), which the gap detector treats
-- as "eligible by the time rule alone" — the intended backward-compatible default.
-- The write that sets this column (answered/dismissed/pending) is wired with the
-- voice/chat follow-up path (GATE-3) in a follow-on change.

ALTER TABLE meals
  ADD COLUMN IF NOT EXISTS followup_status TEXT
    CHECK (followup_status IN ('pending', 'answered', 'dismissed', 'resurfaced'));
