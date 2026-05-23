# Entry Edit & Delete — Design Spec

**Date:** 2026-05-23
**Status:** Approved

---

## Goal

Allow users to edit or delete any logged entry (meal, symptom, wellbeing) from both the home timeline and entry detail screens.

---

## Scope

All three entry types: meals, symptoms, wellbeing snapshots.

---

## Entry Points

### Long-press (quick access)
Long-pressing any `_MealCard`, `_SymptomRow`, or `_WellbeingRow` on the home screen opens `_EntryActionsSheet` — a modal bottom sheet with two actions: **Edit** and **Delete**.

### Tap → detail screen
- **Meal** → existing `LogDetailScreen` — gains Edit and Delete buttons in the app bar.
- **Symptom** → new `SymptomDetailScreen` — shows description, timestamp, and linked meal (if any). Has Edit and Delete buttons in the app bar.
- **Wellbeing** → existing `WellbeingLogScreen` in edit mode (already wired via `id` query param) — gains a Delete button.

Both entry points share the same `_confirmDelete()` helper and navigate to the same edit screens.

---

## Edit Screens

### EditMealScreen (`/meals/edit?id=<uuid>`)
- Fetches the existing meal by ID on load; pre-fills a single description `TextField`.
- Save calls `PATCH /api/meals/{id}` with the new description.
- Server re-runs AI food extraction and returns the updated meal row.
- No client-side foods list editing — the server derives foods from the description.

### EditSymptomScreen (`/symptoms/edit?id=<uuid>`)
- Pre-fills description from the existing symptom entry.
- Save calls `PATCH /api/symptoms/{id}` with the new description.

### Wellbeing edit
- Reuses `WellbeingLogScreen` in edit mode (navigate to `/wellbeing/log?id=<uuid>`).
- Adds a Delete button to the app bar of that screen.

---

## Delete Flow

1. User taps Delete (from bottom sheet or detail screen app bar).
2. `AlertDialog` shown: title "Delete this entry?", body "This can't be undone.", actions Cancel and Delete.
3. On confirm: call the appropriate DELETE endpoint, then invalidate the provider.
4. Hard delete — no soft-delete or undo.

---

## API Changes

### Meals (`hearty-api/app/routers/meals.py`)

**`PATCH /api/meals/{id}`**
- Request body: `{ "description": str }`
- Verifies `user_id` ownership.
- Re-runs `ai_extraction.extract_meal(description)` to update `foods` and `meal_type`.
- Returns updated meal row.

**`DELETE /api/meals/{id}`**
- Verifies `user_id` ownership.
- Hard deletes the row.
- Returns 204 No Content.

### Symptoms (`hearty-api/app/routers/symptoms.py`)

**`PATCH /api/symptoms/{id}`**
- Request body: `{ "description": str }`
- Verifies `user_id` ownership.
- Updates `description` field only.
- Returns updated symptom row.

**`DELETE /api/symptoms/{id}`**
- Verifies `user_id` ownership.
- Hard deletes.
- Returns 204 No Content.

### Wellbeing (`hearty-api/app/routers/wellbeing.py`)

**`DELETE /api/wellbeing/{id}`**
- Verifies `user_id` ownership.
- Hard deletes.
- Returns 204 No Content.
- (`PATCH /api/wellbeing/{id}` already exists from Phase 10.)

---

## Flutter API Client (`lib/core/api/hearty_api_client.dart`)

Five new methods:

```dart
Future<MealLog> updateMeal(String id, String description);
Future<void> deleteMeal(String id);
Future<SymptomLog> updateSymptom(String id, String description);
Future<void> deleteSymptom(String id);
Future<void> deleteWellbeing(String id);
```

---

## State Refresh

After any successful edit or delete, invalidate the relevant Riverpod provider:
- Meals → `ref.invalidate(mealsProvider)`
- Symptoms → `ref.invalidate(symptomsProvider)`
- Wellbeing → `ref.invalidate(wellbeingProvider)`

This refreshes both the home timeline and the history screen automatically.

---

## Routing

New routes added to `lib/app/router.dart`:
- `/meals/edit` — `EditMealScreen`, accepts `id` query param
- `/symptoms/edit` — `EditSymptomScreen`, accepts `id` query param
- `/symptoms/:id` — `SymptomDetailScreen`

Existing routes used:
- `/log/:id` — `LogDetailScreen` (meals detail, gets Edit + Delete added)
- `/wellbeing/log?id=<uuid>` — `WellbeingLogScreen` in edit mode (gets Delete button added)

---

## Files

**Create:**
- `hearty_app/lib/features/logging/screens/edit_meal_screen.dart`
- `hearty_app/lib/features/logging/screens/edit_symptom_screen.dart`
- `hearty_app/lib/features/logging/screens/symptom_detail_screen.dart`

**Modify:**
- `hearty-api/app/routers/meals.py` — add PATCH + DELETE
- `hearty-api/app/routers/symptoms.py` — add PATCH + DELETE
- `hearty-api/app/routers/wellbeing.py` — add DELETE
- `hearty_app/lib/core/api/hearty_api_client.dart` — add 5 methods
- `hearty_app/lib/features/logging/screens/home_screen.dart` — long-press bottom sheet on all cards
- `hearty_app/lib/features/logging/screens/log_detail_screen.dart` — Edit + Delete in app bar
- `hearty_app/lib/features/wellbeing/screens/wellbeing_log_screen.dart` — Delete button
- `hearty_app/lib/app/router.dart` — new routes
