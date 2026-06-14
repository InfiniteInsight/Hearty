# Tracked Experiments — Design Spec

**Date:** 2026-06-04 (amended 2026-06-14: added the mid-experiment adherence nudge)
**Status:** Design approved (brainstorming). Dependencies (Monthly Trends
Conversation, dictation/voice rework) have since shipped; ready for implementation
planning. Background execution uses **defer-to-tap** (consistent with the daily
check-in and trends notifications) — no WorkManager.

## Goal

Let Hearty turn an observed pattern into a **time-boxed experiment**: propose
cutting a food category for a couple of weeks, quietly track adherence from the
user's normal logging, then report — honestly — whether the target symptom or
wellbeing measure actually changed. A positive, well-adhered result can feed back
into the trends feedback loop as a confirmed signal.

## Why this feature exists

The Monthly Trends Conversation surfaces correlations and lets the user
confirm/dispute them from judgment. Experiments add the missing step: *testing* a
pattern instead of just reacting to it. "Dairy seems to precede your bloating —
let's actually find out" is more convincing than a correlation, and a clean result
is the strongest possible input to the signal feedback overlay.

## Relationship to other features

- **Builds on the Monthly Trends Conversation** (`docs/superpowers/specs/2026-06-04-monthly-trends-conversation-design.md`):
  experiments are *offered from within* that conversation (the originating signal
  supplies category + target outcome), and a positive result writes a `confirmed`
  verdict into that feature's `signal_feedback` overlay. **This feature cannot ship
  before the trends conversation.**
- **Reuses existing analysis infrastructure** (consume, don't rebuild):
  `food_category_service` (classifies logged foods into categories — used for
  adherence) and the counterfactual rate computation style from `signal_engine.py`
  (used for the baseline-vs-experiment comparison).

## Scope

**In scope (v1):** elimination experiments (cut one harmful category), started from
the trends conversation, auto-tracked adherence from normal logs, **a one-time
mid-course nudge if the user drifts off-protocol** (see "Mid-experiment adherence
nudge"), baseline-vs-experiment outcome comparison with honest inconclusive
guardrails, an end-of-window result delivered via notification → result
view/conversation, and an optional write-back of a `confirmed` verdict on a clean
positive result.

**Explicitly NOT in scope:**
- **Addition experiments** ("add ginger to improve energy") — the data model
  reserves a `direction` field so these slot in later **without redesign**, but v1
  implements only `eliminate`.
- **Manual experiment creation** outside the trends conversation — the data model
  does not preclude it, but v1 only starts experiments from the conversation.
- **Daily adherence prompts** — adherence is inferred from logs, not asked daily.
  The single exception is the one-time mid-course nudge below; there is no
  recurring "did you stay off it?" prompting.
- **Multiple concurrent experiments** on the same category/outcome — one active
  experiment per (category, outcome) at a time (see Data model constraint).

---

## Lifecycle

1. **Propose & start.** During the trends conversation, when Hearty discusses a
   harmful pattern, it may offer an experiment. The user accepts via a
   **confirmable chip** ("Test this — cut dairy for 2 weeks?") — never auto-started.
   Acceptance creates an `experiments` row with status `active`.
2. **Run.** Default duration **14 days** (`EXPERIMENT_DAYS`, adjustable). The
   experiment rides on the user's normal logging — no new prompts, no behavior
   change required beyond the elimination itself.
2a. **Mid-course nudge (one-time).** If the running adherence drifts low while the
   experiment is active, Hearty sends exactly **one** gentle nudge so the user can
   course-correct instead of wasting the window (see "Mid-experiment adherence
   nudge"). Options: keep going, restart the clock, or stop.
3. **Evaluate & deliver.** At `experiment_end`, a notification invites the user to
   see the result; tapping opens a short result view / conversation turn.
4. **Feed back.** A clean, positive result offers to write a `confirmed` verdict to
   `signal_feedback`. A null/inconclusive result writes nothing.
5. **Abandon.** The user can stop an experiment early → status `abandoned`
   (excluded from evaluation).

---

## Data model

New table `experiments` (Supabase migration; mirror the RLS/owner pattern of
`food_signals` / `signal_feedback`):

| Field | Type | Notes |
|---|---|---|
| `id` | UUID PK | |
| `user_id` | UUID FK auth.users | |
| `category` | TEXT | the food category under test (matches `food_category_service` categories) |
| `direction` | TEXT CHECK in (`'eliminate'`,`'add'`) | v1 always `'eliminate'`; `'add'` reserved |
| `outcome_type` | TEXT CHECK in (`'symptom'`,`'wellbeing'`) | from the originating signal |
| `outcome_name` | TEXT | e.g. `bloating`, `energy_level` |
| `baseline_start` | TIMESTAMPTZ | |
| `baseline_end` | TIMESTAMPTZ | == `experiment_start` |
| `experiment_start` | TIMESTAMPTZ | |
| `experiment_end` | TIMESTAMPTZ | `experiment_start + EXPERIMENT_DAYS` |
| `status` | TEXT CHECK in (`'active'`,`'completed'`,`'abandoned'`) | |
| `result` | JSONB nullable | the computed evaluation (see below), written at completion |
| `nudged_at` | TIMESTAMPTZ nullable | set when the one-time mid-course nudge fires; guarantees one nudge per active window (cleared by a "restart the clock") |
| `created_at` | TIMESTAMPTZ default now() | |

**Constraint:** a partial unique index on `(user_id, category, outcome_type,
outcome_name)` WHERE `status = 'active'` — at most one active experiment per
pattern at a time.

**Baseline window:** the **matched-length** period immediately before
`experiment_start` (so a 14-day experiment compares against the prior 14 days).
`baseline_start = experiment_start - EXPERIMENT_DAYS`.

---

## Adherence (auto-detected — option A)

No prompts. Adherence is computed from the user's normally-logged meals in
`[experiment_start, experiment_end]`:

- Classify each meal's foods with `food_category_service`.
- A **"clean day"** = a day with at least one logged meal and **no** meal
  containing the eliminated `category`.
- A day with **no meals logged at all** is **"unknown"** (not clean, not a
  violation) — it neither credits nor penalizes adherence, but counts against data
  sufficiency.
- `adherence = clean_days / logged_days` (days with at least one meal).

This rides entirely on existing logged data; it adds no logging burden.

---

## Mid-experiment adherence nudge (one-time)

Adherence is still never *asked* daily, but a drifting experiment shouldn't run two
silent weeks only to end `inconclusive`. While an experiment is `active`, Hearty
sends **exactly one** gentle nudge if the user is clearly off-protocol:

- **Trigger:** running adherence (over logged days so far) `< NUDGE_ADHERENCE`
  (default **0.5** — deliberately looser than the final `ADHERENCE_MIN` of 0.7, so
  it only fires on real drift) **and** at least `NUDGE_MIN_DAYS` logged days have
  elapsed (default **4**, so a single early slip never triggers it) **and**
  `nudged_at IS NULL` (one per active window).
- **Detection:** a meal that contains the eliminated `category` is a violation; this
  is computed from the same `food_category_service` classification used for
  adherence, evaluated on the meal-logging path (no new logging burden, no polling).
- **Delivery:** defer-to-tap (same mechanism as the check-in / trends notifications)
  — a notification → a short prompt. On firing, set `nudged_at = now`.
- **Actions offered (confirmable, never automatic):**
  - **Keep going** — dismiss; no further nudges this window.
  - **Restart the clock** — reset `experiment_start = now`,
    `experiment_end = now + EXPERIMENT_DAYS`, shift the baseline window accordingly,
    and clear `nudged_at` (a fresh window may nudge again if they drift again). The
    drifted days are discarded.
  - **Stop** — abandon the experiment (`status = 'abandoned'`).
- **Tone:** supportive, not scolding — e.g. *"I've noticed dairy in a few meals.
  This test needs you mostly off it to give a clean read — want to keep going,
  restart the two weeks, or stop?"*

If the user ignores the nudge and adherence is still low at `experiment_end`, the
end-of-window evaluation falls through to its existing `inconclusive` guardrail.

---

## Evaluation & honest guardrails

At `experiment_end` (or on-demand re-evaluation), compute the **outcome rate** in
the baseline window vs the experiment window, in the `signal_engine` style:

- **Symptom outcome:** frequency of `outcome_name` occurrences (e.g. days-with-
  bloating per week) in each window.
- **Wellbeing outcome:** mean of `outcome_name` (e.g. `energy_level`) in each
  window.

Report the **delta** in plain language ("bloating went from about 5 days a week to
about 1").

**Guardrails — the result is `inconclusive` (not a win/loss) when:**
1. **Low adherence** — `adherence < ADHERENCE_MIN` (default **0.7**). Message:
   "Hard to say — you weren't really off dairy (clean 5 of 12 logged days)."
2. **Thin data** — fewer than a minimum number of logged days in *either* window
   (`MIN_WINDOW_DAYS`, default **7**) or insufficient outcome observations (reuse
   the spirit of `signal_engine`'s `MIN_*` thresholds). Message: "Not enough logged
   to tell yet."

Only when adherence and data are sufficient does Hearty report `improved`,
`no_change`, or `worse`. The `result` JSONB records: `verdict`
(`improved`/`no_change`/`worse`/`inconclusive`), `reason` (which guardrail, if
any), `adherence`, `baseline_rate`, `experiment_rate`, `logged_days` per window.

---

## Feedback-loop tie-in

- A result of **`improved` with adherence ≥ `ADHERENCE_MIN`** → Hearty offers (via
  a confirmable chip, never silently) to write a **`confirmed`** verdict for that
  signal into `signal_feedback` (the trends feature's overlay). This makes a
  successful experiment the strongest input to the trends loop.
- `no_change` / `worse` / `inconclusive` → **no** automatic verdict (the user may
  still dispute manually in the trends conversation).

---

## Components (for the plan to decompose)

- **`experiments` migration** — table + partial-unique constraint + RLS.
- **Experiment store** — create / get-active / list / mark-abandoned (thin DB layer).
- **Adherence calculator** — pure: `(meals in window, category) → {clean_days,
  logged_days, adherence}` using `food_category_service`. Unit-testable with
  fixture meals. Reused both for the final evaluation and the running mid-course
  adherence check.
- **Nudge trigger** — pure decision: `(running adherence, logged_days_elapsed,
  nudged_at, thresholds) → should_nudge: bool`. Wired on the meal-logging path so a
  violation re-checks it; delivery is defer-to-tap. Unit-testable.
- **Experiment evaluator** — pure: `(baseline meals+symptoms+wellbeing, experiment
  meals+symptoms+wellbeing, adherence, thresholds) → result dict` with the
  guardrails. Unit-testable; reuses the rate-computation style from `signal_engine`.
- **Endpoints:** `POST /api/experiments` (create from a signal), `GET
  /api/experiments/active`, `POST /api/experiments/{id}/evaluate` (compute + store
  result), `POST /api/experiments/{id}/abandon`, `POST /api/experiments/{id}/restart`
  (reset the window + clear `nudged_at` for the "restart the clock" nudge action).
- **Scheduler** — fire the end-of-window evaluation + result notification (shares
  the trends/check-in Android background-execution gate).
- **Flutter (contracts):** the start chip inside the trends conversation; an
  end-of-experiment notification → result view; the result conversation turn that
  offers the confirm-verdict chip. Finalize voice wiring against the reworked
  dictation pipeline.

---

## Testing focus

- **Adherence calculator:** clean vs violation vs no-meal-day classification;
  `adherence` math; uses `food_category_service` classification.
- **Evaluator guardrails:** low adherence → `inconclusive` (not a win); thin data
  in either window → `inconclusive`; sufficient data + good adherence + dropped
  outcome → `improved`; unchanged → `no_change`; risen → `worse`.
- **Rate computation:** symptom-frequency and wellbeing-mean deltas across windows.
- **Active-experiment uniqueness:** creating a second active experiment for the
  same (category, outcome) is rejected.
- **Mid-course nudge trigger:** fires once when running adherence < `NUDGE_ADHERENCE`
  after ≥ `NUDGE_MIN_DAYS` logged days; does NOT fire on a single early slip (too
  few days), when adherence is fine, or twice (`nudged_at` already set); "restart"
  clears `nudged_at` so a re-drift can nudge again.
- **Feedback tie-in:** only `improved` + adherent results offer a verdict; the
  verdict write is never automatic (requires the confirm chip).

---

## Dependencies (status as of 2026-06-14)

1. **Monthly Trends Conversation feature** — ✅ shipped (incl. `signal_feedback`
   overlay with the exact `(category, outcome_type, outcome_name)` identity this
   feature writes to). Experiments launch from it and write a `confirmed` verdict.
2. **Dictation/voice rework** — ✅ shipped. Per the sibling features, the chips and
   result turn are built **text-first**; voice wiring onto the controllers is a
   device-verified follow-up.
3. **Android background-execution mechanism** — ✅ decided: **defer-to-tap** (no
   WorkManager), consistent with the daily check-in and trends notifications. The
   end-of-window evaluation and the mid-course nudge both fire as notifications and
   compute on tap / on the meal-logging path.
4. **`food_category_service` category vocabulary** — in use by `signal_engine`;
   experiment `category` values reuse the originating signal's category (already
   produced by classification), so they align by construction.

---

**Sequencing note:** this was the lowest-priority of the three conversational
features; the daily check-in and the monthly trends conversation have both shipped,
so its prerequisites are met and it is now the next feature to build.
