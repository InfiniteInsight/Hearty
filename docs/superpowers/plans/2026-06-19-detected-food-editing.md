# Detected-Food Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Let the user correct *what a food photo detected* — rename a wrong item, remove a spurious one, add a missed one — before the meal is logged. Tracking-only: **no nutrition, no calories, no food-intelligence lookup.** The corrected food names are saved verbatim on the meal.

**Architecture:** Mirror the just-merged meal-**PATCH**-accepts-foods behavior on meal **CREATE**: `POST /api/meals` gains an optional `foods: list[str]` that is stored verbatim (`[{"name": n}]`, skip AI extraction). Flutter: extract a shared `EditableFoodList` widget (per-food text field + remove + add) from the EditMealScreen pattern, use it on the **photo result screen** so detected foods are editable, and have that screen create the meal with the corrected foods.

**Tech Stack:** FastAPI + Pydantic; Flutter/Riverpod/Dio. Backend runner: `cd hearty-api && set -a && . ../.env && set +a && .venv/bin/python -m pytest <file> -v`. Flutter: `cd hearty_app && flutter test`.

**Verified facts (current code):**
- Merged PATCH (`routers/meals.py` `update_meal`): `if body.foods is not None:` stores `[{"name": n.strip()} for n in body.foods if n and n.strip()]`, skips extraction. `MealUpdateRequest.foods` is `List[str]`.
- `POST /api/meals` `log_meal` always runs `ai_extraction.extract_meal(body.description)`. `MealRequest` has NO `foods` field.
- Client `logMeal({description, mealType})` → POST `/api/meals` with `{description, meal_type, input_method:'voice'}`, returns `MealLog`. No foods sent.
- `EditMealScreen` (`features/logging/screens/edit_meal_screen.dart`) has the editable-foods UI: `_foodControllers` (per-food `TextEditingController`), `_removeFood`, add, `_currentFoods()`.
- `PhotoReviewScreen` (`features/photos/screens/photo_review_screen.dart`): shows `analysis.foods` **read-only**; `_save()` calls `mealsProvider.notifier.logMeal(description)` then `context.go('/home')`.

---

## Task 1: `POST /api/meals` accepts verbatim foods (TDD)

**Files:** Modify `hearty-api/app/models/schemas.py`, `hearty-api/app/routers/meals.py`; Test: extend `hearty-api/tests/` meal-create tests (find the existing meals endpoint test; else add `tests/test_meals_create_foods_unit.py`).

- [ ] **Step 1:** Add `foods: Optional[List[str]] = None` to `MealRequest` (schemas.py).
- [ ] **Step 2:** In `log_meal` (`routers/meals.py`), BEFORE the `ai_extraction.extract_meal(...)` call, branch: if `body.foods is not None`, build the foods verbatim exactly like the PATCH does — `foods = [{"name": n.strip()} for n in body.foods if n and n.strip()]` — and skip extraction; else keep the existing extraction path. Make sure the inserted meal row uses these foods and still sets `input_method` from the request (so a photo create can be `'photo'`).
- [ ] **Step 3: Failing test** (mirror the meals-endpoint test style: TestClient + `app.dependency_overrides[get_current_user]`, monkeypatch `supabase` insert + monkeypatch/patch `ai_extraction.extract_meal` to assert it is NOT called when foods are supplied):

```python
def test_create_with_foods_skips_extraction(monkeypatch):
    # foods provided -> stored verbatim as [{"name":...}], extract_meal NOT called
    ...
    r = client.post("/api/meals", json={"description": "lunch", "foods": ["grilled salmon", "broccoli"], "input_method": "photo"})
    assert r.status_code == 201
    # assert stored foods == [{"name":"grilled salmon"},{"name":"broccoli"}] and extract_meal uncalled

def test_create_without_foods_still_extracts(monkeypatch):
    # no foods -> existing AI extraction path runs
    ...
```
(Read the existing meals endpoint test to match exact mocking; reuse its fakes.)
- [ ] **Step 4:** Run the test file + full suite (`--ignore=tests/test_api.py`) → all pass.
- [ ] **Step 5: Commit** (`feat(meals): POST /api/meals accepts verbatim foods (skip extraction)`).

---

## Task 2: Flutter client `logMeal` sends foods (TDD)

**Files:** Modify `hearty_app/lib/core/api/hearty_api_client.dart`; Test: extend the client test (`test/core/api/...`).

- [ ] **Step 1:** Extend `logMeal` to `Future<MealLog> logMeal({required String description, String? mealType, List<String>? foods, String inputMethod = 'voice'})`. Add `'foods': foods` and `'input_method': inputMethod` to the body (keep the `removeWhere null` so foods omitted when null). Preserve existing callers (default `inputMethod:'voice'`, foods null) → unchanged behavior.
- [ ] **Step 2: Failing test** (interceptor-based, mirror existing client tests): `logMeal(description:'x', foods:['a','b'], inputMethod:'photo')` posts `/api/meals` with body containing `foods:['a','b']` and `input_method:'photo'`; and a call without foods omits the key.
- [ ] **Step 3:** Implement; run `flutter test test/core/api/`; `flutter analyze lib/core/api/`.
- [ ] **Step 4: Commit** (`feat(meals): logMeal can send verbatim foods + input_method`).

---

## Task 3: Shared `EditableFoodList` widget (TDD)

**Files:** Create `hearty_app/lib/features/logging/widgets/editable_food_list.dart`; refactor `hearty_app/lib/features/logging/screens/edit_meal_screen.dart` to use it (behavior-preserving — its existing widget tests must still pass); Test: `hearty_app/test/features/logging/editable_food_list_test.dart`.

- [ ] **Step 1:** Extract a reusable widget that takes `initialFoods: List<String>` and exposes the current list via a controller/callback, rendering one editable `TextField` per food with a remove button and an "Add food" affordance. Match EditMealScreen's existing behavior (the source of truth). Keep it stateless about persistence — it just edits a list of names.
- [ ] **Step 2:** Refactor `EditMealScreen` to render `EditableFoodList` for its foods section instead of its inline `_foodControllers` block, wiring `_currentFoods()` to the widget. RUN `flutter test test/features/logging/` — the existing EditMealScreen tests must stay green (this proves the refactor is behavior-preserving). If extraction is awkward, keep EditMealScreen as-is and make `EditableFoodList` standalone for Task 4 only, and note the duplication as a follow-up.
- [ ] **Step 3: Widget test** for `EditableFoodList`: renders initial foods; typing edits a name; remove drops a row; add appends an empty editable row; the exposed current-foods reflects edits.
- [ ] **Step 4:** `flutter test test/features/logging/`; `flutter analyze lib/`.
- [ ] **Step 5: Commit** (`refactor(logging): extract EditableFoodList widget`).

---

## Task 4: Editable detected foods on the photo result screen (CONTRACT — device-verified)

**Files:** Modify `hearty_app/lib/features/photos/screens/photo_review_screen.dart`; Test: extend `hearty_app/test/features/photos/photo_review_screen_test.dart`.

- [ ] Replace the read-only detected-food rows with the `EditableFoodList` (seeded from `analysis.foods.map((f) => f.name)`). On `_save()`, call `logMeal(description: <desc>, foods: <current edited foods>, inputMethod: 'photo')` instead of the description-only call, then `context.go('/home')`. Keep the description field. Keep the failure SnackBar. Portion/confidence are vision metadata — show them as hints if easy, but the editable source of truth is the names.
- [ ] Widget tests: a `complete` analysis renders the detected foods as **editable**; editing a name + removing one + adding one, then Save, calls `logMeal` once with the corrected `foods` list and `inputMethod:'photo'` (fake client). Run full `flutter test` + `flutter analyze lib/`.
- [ ] **GATE:** the live camera→detect→correct→log flow is **device-verified** (wireless adb). Contract + widget tests + analyze are the bar here.
- [ ] **Commit** (`feat(photos): correct detected foods before logging (editable list, verbatim save)`).

---

## Self-review
- **Scope:** tracking-only correction of detected foods (rename/remove/add) — NO nutrition/lookup. Backend create mirrors the merged PATCH-foods verbatim format (`[{"name": n}]`, skip extraction). Reuses the editable-foods UI via a shared widget.
- **Backward compat:** `MealRequest.foods` and `logMeal(foods:)` are additive/optional — existing create callers (voice/text) keep AI extraction. EditMealScreen refactor guarded by its existing tests.
- **Consistency:** create now matches PATCH for verbatim foods; both store `[{"name": ...}]`.
- **No placeholders:** backend + client tasks have concrete code/contracts; the widget + photo-screen tasks specify exact behavior + tests (Flutter UI is device-verified per the established pattern).
