# Multi-Year Trends — Persistence & Year-over-Year — Design Spec

**Date:** 2026-06-14
**Status:** Design approved (brainstorming). Ready for implementation planning.

## Goal

Stop the trend engine from only ever seeing the last 90 days. Evaluate **all** of a
user's data, bucketed by year so cost stays bounded, and compare conclusions across
years so **recurring patterns (persistence) raise confidence**. A pattern that shows
up three years running is far more trustworthy than a one-year blip, and that should
be visible to the user.

## Why

The signal engine runs over a fixed trailing 90-day window (`run_analysis(period_days=90)`).
Anything older is invisible. For a user with a year or more of history that means:
- **Rare/infrequent triggers** never accumulate enough exposures in 90 days.
- **Recurrence** — the strongest real-world confidence cue for a food journal — is
  invisible, because the engine has no memory across years.
- The growing data pile raised a performance worry: re-analyzing everything on every
  read does not scale.

The key structural insight that makes this cheap: **past calendar years are immutable.**
No new data lands in 2024 after 2024 ends, so each past year is computed **once and
frozen**; only the current year and the live window are ever recomputed. Cost stays
flat no matter how many years accumulate.

## Decisions (settled in brainstorming)

1. **Bucketing — hybrid.** A rolling 12-month window is the live "now" lens; calendar
   years are the frozen buckets for the year-over-year comparison.
2. **Live lens — rolling 12 months replaces the 90-day window.** The Trends screen
   default and the conversation grounding now come from the last 365 days. (Fixes
   "90 days is too short" for rare/seasonal-ish triggers.)
3. **Comparison goal — persistence = confidence.** Emphasize patterns that *recur*
   across years; `new-this-year` is a secondary flag. (`resolved` deferred — see Scope.)
4. **First surface — the Trends screen.** Per-signal recurrence badges; conversation
   integration is a later pass.
5. **Architecture — Approach B (separate history table).** `food_signals` stays the
   live set; a new `food_signals_yearly` holds the frozen per-year sets; a pure
   persistence layer annotates the live signals. The just-shipped live path and the
   monthly conversation are untouched.

## Architecture & data flow

A thin multi-year layer on the existing engine; the live path keeps its shape.

- **Live signals** (`food_signals`): unchanged structure; window 90 → 365 days.
  `get_signals` and the conversation's `signal_presenter` keep reading it as-is.
- **Frozen history** (`food_signals_yearly`): one immutable signal set per calendar year.
- **Pure module** `app/services/signal_persistence.py`: joins live signals against the
  yearly rows → annotates each with `years_seen`, `recurring`, `is_new`,
  `strength_by_year`.
- **Orchestration** `ensure_yearly_backfill(user_id)`: computes any missing past years
  once, recomputes the current year.

**Flow on refresh:**
```
refresh → recompute live (365d, food_signals)
        → ensure_yearly_backfill (backfill missing past years once; recompute current year)
        → GET /api/trends reads live + yearly rows
        → compute_persistence(live, yearly, current_year)
        → annotated signals → Trends cards render badges
```

## Data model — `food_signals_yearly`

Slim per-(category × outcome) row, one per calendar year:

```sql
CREATE TABLE food_signals_yearly (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       UUID REFERENCES auth.users NOT NULL,
  year          INTEGER NOT NULL,
  category      TEXT NOT NULL,
  outcome_type  TEXT NOT NULL CHECK (outcome_type IN ('symptom','wellbeing')),
  outcome_name  TEXT NOT NULL,
  direction     TEXT NOT NULL,
  unified_score NUMERIC,
  relative_risk NUMERIC,
  evidence_count INTEGER NOT NULL DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, year, category, outcome_type, outcome_name)
);
CREATE INDEX idx_food_signals_yearly_lookup ON food_signals_yearly (user_id, year);
ALTER TABLE food_signals_yearly ENABLE ROW LEVEL SECURITY;
CREATE POLICY "food_signals_yearly_owner_only" ON food_signals_yearly
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
```

- Identity `(category, outcome_type, outcome_name)` matches what `signal_feedback`
  already keys on, so persistence and the user's confirm/dispute verdicts line up.
- Only signals the engine already deems real get a row, so **"a row exists for year Y"
  == "this was a conclusion in year Y."**
- `unified_score` is per-category in the engine (duplicated across a category's rows);
  any of a category's rows yields that category's score for a given year.

## Recompute strategy (the performance answer)

- **Past calendar years are frozen.** `ensure_yearly_backfill(user_id)` finds the
  earliest year with meals; for each year from then through *last* year that is
  **missing** from `food_signals_yearly`, it computes + inserts that year and never
  recomputes it again. The **current** year is always recomputed (its data is growing
  — delete-its-rows-and-recompute, scoped to `year = current`).
- **Live (rolling 12mo)** recomputes on refresh, **gated by a debounce**: skip the
  recompute if the last analysis ran within ~N minutes (config; default ~10), in
  addition to the existing `has_new_data` check. This kills the "recompute on every
  Trends open / every tap" pathology flagged earlier.
- The same debounce guards the current-year recompute.
- **Steady-state cost = two windows** (current calendar year + rolling-12mo),
  independent of how many years of history exist. Old-year backfill is one-time.
- Implementation: the existing `compute_symptom_signals` / `compute_wellbeing_signals`
  run over a **date-bounded data load** — `load_data` gains a `period_start` / `period_end`
  slice (calendar-year bounds, or a 365-day rolling bound) instead of only `period_days`.

## Persistence layer (pure)

`compute_persistence(live_signals, yearly_rows, current_year) -> annotated`, keyed at
the **category** level (matching `unified_score` granularity):

- **`years_seen`** — sorted list of years with a stored row for the category (years it
  was a real conclusion).
- **`recurring`** — `len(years_seen) >= 2`.
- **`is_new`** — present live but in no *prior* calendar year (first appearance).
- **`strength_by_year`** — `{year: unified_score}` for a future sparkline.
- **Graceful with little data:** fewer than 2 years → no badges.

## API surface

Extend the existing `GET /api/trends` response (no new endpoint). Each returned signal
(category-level) gains: `years_seen`, `recurring`, `is_new`, `strength_by_year`.
`get_signals` runs the refresh — the existing live recompute (`ensure_fresh_signals`,
now 365-day) **and** `ensure_yearly_backfill`, both debounced — then reads live +
yearly rows, runs `compute_persistence`, and returns the annotated signals. The
conversation can consume the same data in a later pass.

## Trends screen UI

Minimal additions per signal card:
- **Recurring badge** when `recurring`: e.g. "Seen 3 years · ’24 · ’25 · ’26".
- **"New this year" chip** when `is_new`.
- Single-year, non-recurring → no badge (no noise).
- Existing `unified_score` sort unchanged. A `strength_by_year` sparkline is deferred.

## Testing

**Backend (unit, mocked):**
- `signal_persistence` pure: recurring / new / years_seen / strength_by_year; <2-year
  graceful; identity join correctness.
- `ensure_yearly_backfill`: computes missing past years, recomputes the current year,
  **skips** already-frozen past years (engine + table mocked).
- The date-bounded `load_data` slice (calendar-year + rolling-365 bounds).
- `GET /api/trends` returns the persistence fields (mocked supabase).
- Debounce: recompute skipped within the window, runs after it.
- Migration applies cleanly.

**Frontend:**
- Badge widget test: recurring → years badge; new → chip; single-year → nothing.
- Model parsing of the new fields.

**Device-verify (flagged, not unit-testable):** real multi-year backfill + Trends card
rendering on device.

## Scope

**In (v1):**
- `food_signals_yearly` migration.
- Live window 90 → 365 in `run_analysis`.
- `ensure_yearly_backfill` + date-bounded `load_data` slice.
- `signal_persistence` pure layer.
- `GET /api/trends` persistence annotation.
- Trends card recurring / new badges.
- Debounce guard on the live + current-year recompute.

**Out (later passes):**
- Conversation integration (Hearty citing persistence/recurrence).
- "Resolved" list (patterns strong in past years, absent now).
- `strength_by_year` sparkline UI.
- Trajectory / improvement metrics, seasonality detection.
- Moving recompute off the request path (background job) — only if the debounce proves
  insufficient on device.

## Consistency notes

- Persistence identity `(category, outcome_type, outcome_name)` is the same tuple
  `signal_feedback` uses — recurrence + a user verdict can later combine into a
  highest-confidence state.
- Category slugs are stable (`classify_foods_cached`), so the cross-year join is sound.
- The live-window change (90 → 365) is the only modification to the existing hot path;
  `food_signals`' shape and its readers are otherwise untouched.
