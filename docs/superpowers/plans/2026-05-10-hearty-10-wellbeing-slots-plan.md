# Hearty — Plan 10: Multi-Period Wellbeing Check-ins & Edit

**Spec:** [`hearty-10-wellbeing-slots.md`](../specs/2026-05-10-hearty-10-wellbeing-slots.md)
**Plan Status:** 🟢 Completed
**Last Updated:** 2026-05-10

---

## Phase Summary

| Phase | Name | Status |
|-------|------|--------|
| 1 | DB Migration | 🟢 Completed |
| 2 | API — period field + PATCH endpoint + preferences | 🟢 Completed |
| 3 | Flutter models + API client | 🟢 Completed |
| 4 | Home screen three-column card | 🟢 Completed |
| 5 | WellbeingLogScreen (period selector + edit mode) | 🟢 Completed |
| 6 | Notification service (3 slots) | 🟢 Completed |
| 7 | Notification preferences screen (3 time pickers) | 🟢 Completed |

---

## Phase 1: DB Migration

**Status:** 🟢 Completed
**Goal:** Add `period` column to `wellbeing_snapshots`; add 9 new columns to `notification_preferences`.

### Tasks
- [x] Create `supabase/migrations/20260510000000_wellbeing_periods.sql`
- [x] Add `period TEXT CHECK (period IN ('morning','midday','evening'))` to `wellbeing_snapshots`
- [x] Add `morning_checkin_enabled`, `morning_checkin_hour`, `morning_checkin_minute` to `notification_preferences` (defaults: TRUE, 8, 0)
- [x] Add `midday_checkin_enabled`, `midday_checkin_hour`, `midday_checkin_minute` (defaults: TRUE, 13, 0)
- [x] Add `evening_checkin_enabled`, `evening_checkin_hour`, `evening_checkin_minute` (defaults: TRUE, 20, 0)

---

## Phase 2: API

**Status:** 🟢 Completed
**Goal:** Add `period` to wellbeing POST/GET; add PATCH endpoint; expose new pref fields.

### Tasks
- [x] Add `period: Optional[Literal['morning','midday','evening']] = None` to `WellbeingRequest` and `WellbeingResponse` in `schemas.py`
- [x] Update `POST /api/wellbeing` to store `period`
- [x] Add `PATCH /api/wellbeing/{id}` — verify ownership, update fields, return updated row
- [x] Add 9 new fields to `UserPreferences` Pydantic model in `schemas.py`
- [x] Update `GET /api/preferences` to read new columns
- [x] Update `PUT /api/preferences` to write new columns

---

## Phase 3: Flutter Models + API Client

**Status:** 🟢 Completed
**Goal:** Add `WellbeingPeriod` enum; update `WellbeingLog`, `UserPreferences`; add API client methods.

### Tasks
- [x] Create `lib/core/api/models/wellbeing_period.dart` with `WellbeingPeriod` enum and `inferFromLocalHour()` helper
- [x] Add `period: WellbeingPeriod?` to `WellbeingLog` model (nullable, parsed from JSON)
- [x] Add 9 new fields to `UserPreferences` Dart model; update `fromJson`/`toJson`/`copyWith`
- [x] Add `period` param to `logWellbeing()` in `HeartyApiClient`
- [x] Add `updateWellbeing(String id, {...})` PATCH method to `HeartyApiClient`
- [x] Update `UserPreferences` serialization in `HeartyApiClient.updatePreferences()`

---

## Phase 4: Home Screen Three-Column Card

**Status:** 🟢 Completed
**Goal:** Replace the single-row wellbeing prompt card with a three-column card showing filled/empty state per period.

### Tasks
- [x] Replace `_WellbeingSnapshotCard` with three-column layout
- [x] Compute latest entry per period from `wellbeingEntries` list
- [x] Filled slot: show ⚡ energy and 😊 mood values; tap → navigate to edit form with `entryId` + `initialPeriod`
- [x] Empty slot: show "+ Log"; tap → navigate to log form with `initialPeriod`
- [x] Route args: `/wellbeing/log?period=morning&id=<uuid>` for edit, `/wellbeing/log?period=morning` for new

---

## Phase 5: WellbeingLogScreen — Period Selector + Edit Mode

**Status:** 🟢 Completed
**Goal:** Add period segmented button to log screen; support edit (pre-fill + PATCH).

### Tasks
- [x] Accept `initialPeriod` query param from GoRouter; infer from time if absent
- [x] Accept optional `id` query param; when present, fetch entry and pre-fill sliders
- [x] Add `SegmentedButton<WellbeingPeriod>` below the app bar
- [x] When `id` present: title = "Edit Wellbeing", save calls `updateWellbeing(id, ...)`
- [x] When `id` absent: title = "Log Wellbeing", save calls `logWellbeing(...)`
- [x] Update GoRouter route for `/wellbeing/log` to accept `period` and `id` query params

---

## Phase 6: Notification Service — Three Slots

**Status:** 🟢 Completed
**Goal:** Replace single daily notification with three independent scheduled notifications.

### Tasks
- [x] Add `scheduleCheckinNotification({required WellbeingPeriod period, required int hour, required int minute, required bool enabled})` method to `NotificationService`
- [x] Cancel old notification ID `1000` on first run (one-time migration)
- [x] Schedule/cancel morning (ID 1001), midday (ID 1002), evening (ID 1003) based on prefs
- [x] Each body: "Tap to log your [morning/midday/evening] wellbeing."
- [x] Deep link payload: `/wellbeing/log?period=[period]`
- [x] Call all three from `NotificationSetupProvider` after preferences are loaded

---

## Phase 7: Notification Preferences Screen — Three Time Pickers

**Status:** 🟢 Completed
**Goal:** Replace single time-picker row with three rows, one per slot.

### Tasks
- [x] Replace single "Daily check-in" row with three rows: Morning / Midday / Evening
- [x] Each row: toggle (enabled/disabled) + time picker
- [x] On change: update `UserPreferences`, call `PUT /api/preferences`, reschedule all three notifications
- [x] Defaults shown: 8:00 AM / 1:00 PM / 8:00 PM

---

## Deviation Log

*(append deviations here as they are found)*
