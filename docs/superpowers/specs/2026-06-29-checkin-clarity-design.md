# Daily Check-in Clarity — Design

**Date:** 2026-06-29
**Status:** Approved (brainstorming)

## Problem

The Daily Check-in surfaces "gaps" the backend detects in a day's logs. Each gap
ships a pre-written `prompt` string the screen renders verbatim. Two problems:

1. **Vague referents.** The symptom prompt says *"How did your stomach feel after
   that meal?"* — "that meal" is never named, even though the gap carries a
   `meal_id` and the detector has the full meal row in hand. The missing-chunk
   prompt says *"a stretch there"* without naming the actual time window.
2. **Misleading title.** The screen is titled "Daily check-in", which doesn't
   convey that it's a short set of clarifying questions about gaps in today's log.

## Key facts (verified in code)

- `meals.description` stores the **raw user utterance** (e.g. "had a grilled
  chicken salad for lunch"), not a clean summary — unusable as an inline label.
- `meals.foods` stores structured `[{name: "grilled chicken salad"}, …]` — clean
  noun phrases. The detector **already selects `foods`**.
- `meals.logged_at` is **UTC**. A local clock time ("around 12:30 PM") can only be
  rendered on the device, so the question sentence must be composed on the
  frontend.
- `HomeCheckinBanner` already renders nothing when the gap list is empty/expired —
  the entry point is already gated on "there's something to review."

## Approach

Backend supplies **structured context**; the **frontend composes** the sentence
(local-time formatting lives on-device).

### Backend (`hearty-api`)

- `routers/checkin.py`: add `meal_type` to the meals `.select(...)` (`foods`,
  `logged_at`, `followup_status` already selected).
- `services/checkin_detector.py`:
  - Derive `meal_label` from `foods[].name`: one name → that name; 2–3 → comma
    join; >3 → first three + " +N more"; **null** when the meal has no foods.
  - `symptom_gap` and `low_confidence` gaps gain: `meal_label` (str|null),
    `meal_time` (the meal's `logged_at`, ISO str), `meal_type` (str|null).
  - `missing_chunk` already carries `window_start` / `window_end`.
  - The existing `prompt` string **stays** as a fallback (used when `meal_label`
    is null, or for unknown gap types).
- `models/schemas.py` `CheckinGap`: add `meal_label`, `meal_time`, `meal_type`
  optional fields.

### Frontend (`hearty_app`)

- `models/checkin_gap.dart` `CheckinGap`: add `mealLabel`, `mealTime`
  (DateTime?), `mealType` from JSON.
- New pure helper `checkinQuestionText(CheckinGap, {DateTime Function() now})`:
  - **symptom_gap** → "How did your stomach feel after your {label} — {type},
    around {h:mm a}?" (drop " — {type}" when type null; fall back to `gap.prompt`
    when label null).
  - **low_confidence** → "On your {type} around {h:mm a}, I logged \"{food}\" —
    did I get that right?" (fall back to `gap.prompt` when meal_time null).
  - **missing_chunk** → "I don't see anything logged between about {start} and
    {end} — did you eat then?" (fall back to `gap.prompt` when window missing).
  - Times formatted in **local** time (`toLocal()`), `h:mm a`.
- `checkin_preview_view.dart` and `checkin_cycle_view.dart`: render
  `checkinQuestionText(gap)` instead of `gap.prompt`.
- `daily_checkin_screen.dart`: AppBar title → **"A few quick questions about your
  day"** (shorten to "A few quick questions" only if it overflows the bar —
  verified on-device).
- Home banner: **no change** (already self-hiding when empty).

## Testing

- Backend: update `test_checkin_detector_unit.py` for the new gap fields; assert
  `meal_label` derivation (single / multi / >3 / no-foods→null) and that
  `meal_time`/`meal_type` are emitted.
- Frontend: new unit test for `checkinQuestionText` covering all three gap types,
  the null-label / null-window fallbacks to `prompt`, and local-time formatting
  (inject a fixed `now`/timezone-independent assertion on a known instant).

## Out of scope

- Voice answering of gaps (already a deferred TODO in the cycle view).
- Changing which gaps are detected, their priority, or the resolve endpoints.
