# Hearty — Spec 10: Multi-Period Wellbeing Check-ins & Edit

**Document:** `hearty-10-wellbeing-slots.md`
**Date:** 2026-05-10
**Status:** Active

---

## 1. Overview

### Purpose

Replace the single daily "morning wellbeing" prompt with three named time-of-day slots (morning, midday, evening), each independently loggable, and add the ability to edit any wellbeing entry after it has been saved.

### Motivation

A single daily check-in misses how wellbeing shifts through the day — especially relevant for GI symptom correlation, where energy and mood before lunch can differ sharply from after dinner. Three slots give a richer baseline without requiring the user to remember a specific time.

---

## 2. Period Model

### 2.1 Periods

Three named periods:

| Period  | Default prompt time | Local-hour inference range |
|---------|--------------------|-----------------------------|
| morning | 8:00 AM            | 5:00–10:59                  |
| midday  | 1:00 PM            | 11:00–16:59                 |
| evening | 8:00 PM            | 17:00–4:59 (next day)       |

The inference range is a client-side default only. The user can change the period before saving. No assumptions are made about what a period "means" (e.g. midday ≠ start of work day).

### 2.2 Enforcement

- **DB:** No unique constraint. Multiple entries per period per day are allowed.
- **UI:** The home card shows the **most recent** entry per slot. If a slot has an entry, the card shows it and tapping opens the edit form. If empty, tapping opens the log form with that period pre-selected.
- **Server:** Accepts any period value; never rejects a duplicate.

---

## 3. Database Changes

### 3.1 `wellbeing_snapshots` table

```sql
ALTER TABLE wellbeing_snapshots
  ADD COLUMN IF NOT EXISTS period TEXT
    CHECK (period IN ('morning', 'midday', 'evening'));
```

Existing rows get `period = NULL`. The API and UI treat NULL as unperioded (backward compatible).

### 3.2 `notification_preferences` table

Six new flat columns, one pair per slot:

```sql
ALTER TABLE notification_preferences
  ADD COLUMN IF NOT EXISTS morning_checkin_enabled  BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS morning_checkin_hour     INT     NOT NULL DEFAULT 8,
  ADD COLUMN IF NOT EXISTS morning_checkin_minute   INT     NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS midday_checkin_enabled   BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS midday_checkin_hour      INT     NOT NULL DEFAULT 13,
  ADD COLUMN IF NOT EXISTS midday_checkin_minute    INT     NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS evening_checkin_enabled  BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS evening_checkin_hour     INT     NOT NULL DEFAULT 20,
  ADD COLUMN IF NOT EXISTS evening_checkin_minute   INT     NOT NULL DEFAULT 0;
```

The old `daily_checkin_enabled`, `daily_checkin_hour`, `daily_checkin_minute` columns are superseded but left in place for backward compatibility.

---

## 4. API Changes

### 4.1 POST /api/wellbeing

Add optional `period` field to `WellbeingRequest`:

```python
period: Optional[Literal['morning', 'midday', 'evening']] = None
```

Stored as-is. No server-side inference.

### 4.2 PATCH /api/wellbeing/{id}

New endpoint for editing an existing entry. Accepts the same optional fields as POST. Returns the updated `WellbeingResponse`.

```
PATCH /api/wellbeing/{id}
Body: { energy_level?, mood?, stress_level?, notes?, period? }
Auth: Bearer token (user must own the entry)
```

### 4.3 GET /api/wellbeing

No change. `period` is already returned via `SELECT *`.

### 4.4 UserPreferences / GET+PUT /api/preferences

Add six new fields mirroring the DB columns:

```
morningCheckinEnabled / morningCheckinHour / morningCheckinMinute
middayCheckinEnabled  / middayCheckinHour  / middayCheckinMinute
eveningCheckinEnabled / eveningCheckinHour / eveningCheckinMinute
```

---

## 5. Flutter Changes

### 5.1 Models

**`WellbeingPeriod` enum** (new file `lib/core/api/models/wellbeing_period.dart`):

```dart
enum WellbeingPeriod { morning, midday, evening }
```

Client-side inference from local hour:
- 5–10  → morning
- 11–16 → midday
- 17–4  → evening

**`WellbeingLog`** — add `period: WellbeingPeriod?`

**`UserPreferences`** — add nine new fields (one enabled bool + hour + minute per slot, replacing the old single `dailyCheckin*` fields in the Dart model while keeping backward-compat JSON parsing).

### 5.2 API Client

- `logWellbeing(...)` — add `period` parameter
- `updateWellbeing(id, {...})` — new PATCH method
- `updatePreferences(...)` — pass through new checkin fields

### 5.3 Home Screen Snapshot Card

Replace the single-row prompt card with a three-column card:

```
┌─────────────────────────────────────────────────┐
│ Today's Wellbeing                               │
├─────────────────┬─────────────┬─────────────────┤
│    Morning      │   Midday    │    Evening      │
│   ⚡4   😊3    │  + Log      │   + Log         │
└─────────────────┴─────────────┴─────────────────┘
```

- Filled slots: show energy (⚡) and mood (😊) values; tap → edit form
- Empty slots: show "+ Log" label; tap → log form with period pre-selected
- Uses `wellbeingProvider`; reacts to invalidation

### 5.4 WellbeingLogScreen

- Accepts optional `initialPeriod: WellbeingPeriod?` and `entryId: String?` parameters
- When `entryId` is set: screen title = "Edit Wellbeing", save calls PATCH instead of POST
- Shows a `SegmentedButton<WellbeingPeriod>` selector, pre-set to `initialPeriod` (or inferred from time when null)
- Existing sliders (energy, mood) and notes field unchanged

### 5.5 Notification Service

Replace the single `scheduleDailyCheckin()` call with three independent calls:

```dart
scheduleCheckin(period: WellbeingPeriod.morning,  hour: prefs.morningCheckinHour, ...)
scheduleCheckin(period: WellbeingPeriod.midday,   hour: prefs.middayCheckinHour,  ...)
scheduleCheckin(period: WellbeingPeriod.evening,  hour: prefs.eveningCheckinHour, ...)
```

Each notification:
- Notification ID: `1001` / `1002` / `1003` (morning / midday / evening)
- Channel: existing `hearty_daily_checkin`
- Body: "Tap to log your [period] wellbeing."
- Deep link: `/wellbeing/log?period=[period]`

### 5.6 Notification Preferences Screen

Replace the single time-picker row with three expandable rows, one per slot:

```
Morning check-in     [●] enabled    [ 8:00 AM ▾ ]
Midday check-in      [●] enabled    [ 1:00 PM ▾ ]
Evening check-in     [●] enabled    [ 8:00 PM ▾ ]
```

Saves to `UserPreferences` and re-schedules all three notifications on change.

---

## 6. Deep Link

`WellbeingLogScreen` accepts a `period` query parameter via GoRouter:

```
/wellbeing/log?period=morning
/wellbeing/log?period=midday
/wellbeing/log?period=evening
```

When present, it pre-selects the period in the form. Notification taps use these URLs.

---

## 7. Backward Compatibility

- `period = NULL` in existing rows is valid; the home card treats them as unslotted (not shown in any period column).
- The old `dailyCheckinEnabled`/`Hour`/`Minute` columns in `notification_preferences` remain but are no longer written by the app. The new columns drive scheduling.
- The old single notification (ID `1000`) is cancelled and replaced on first app launch after update.
