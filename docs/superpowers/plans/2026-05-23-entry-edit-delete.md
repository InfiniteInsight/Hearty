# Hearty — Entry Edit & Delete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users edit or delete any logged entry (meal, symptom, wellbeing) from both the home timeline (long-press) and the entry detail screen (app bar buttons).

**Architecture:** Five new API endpoints (PATCH + DELETE for meals and symptoms, DELETE for wellbeing) are added to the Python routers. Five matching methods are added to `HeartyApiClient`. Two new Flutter edit screens (`EditMealScreen`, `EditSymptomScreen`) are wired into GoRouter. Long-press on any home-screen card opens an `_EntryActionsSheet`; the existing `LogDetailScreen` gains Edit + Delete app-bar actions for all entry types. Meal edit re-runs AI extraction server-side; all deletes are hard with an AlertDialog confirmation.

**Tech Stack:** FastAPI + Supabase (Python API), Dio + Riverpod (Flutter client), GoRouter `extra` for passing description to edit screens.

**Spec:** [`docs/superpowers/specs/2026-05-23-entry-edit-delete-design.md`](../specs/2026-05-23-entry-edit-delete-design.md)

**Plan Status:** ⬜ Not Started

---

## Phase Summary

| Phase | Name | Status |
|-------|------|--------|
| 1 | API — Meals PATCH + DELETE | ⬜ Not Started |
| 2 | API — Symptoms PATCH + DELETE | ⬜ Not Started |
| 3 | API — Wellbeing DELETE | ⬜ Not Started |
| 4 | Flutter API Client — 5 new methods | ⬜ Not Started |
| 5 | Edit Screens + Routing | ⬜ Not Started |
| 6 | Home Screen Long-press Sheet | ⬜ Not Started |
| 7 | Detail Screen Edit + Delete | ⬜ Not Started |
| 8 | Smoke Test | ⬜ Not Started |

---

## Phase 1: API — Meals PATCH + DELETE

**Status:** ⬜ Not Started
**Goal:** Add `PATCH /api/meals/{id}` (updates description + re-runs AI extraction) and `DELETE /api/meals/{id}` to `hearty-api/app/routers/meals.py`.

### Tasks

- [ ] **Step 1: Write the failing tests**

Append to `hearty-api/tests/test_api.py`:

```python
def test_update_meal(api_base, headers):
    # Create
    r = httpx.post(f"{api_base}/api/meals", headers=headers, json={
        "description": "pancakes with syrup", "offline_id": str(uuid.uuid4())
    }, timeout=30)
    assert r.status_code == 201
    meal_id = r.json()["id"]

    # Patch
    r2 = httpx.patch(f"{api_base}/api/meals/{meal_id}", headers=headers,
                     json={"description": "pancakes with maple syrup"}, timeout=30)
    assert r2.status_code == 200
    body = r2.json()
    assert body["description"] == "pancakes with maple syrup"
    assert isinstance(body["foods"], list)

    # Cleanup
    httpx.delete(f"{api_base}/api/meals/{meal_id}", headers=headers)


def test_delete_meal(api_base, headers):
    r = httpx.post(f"{api_base}/api/meals", headers=headers, json={
        "description": "toast to delete", "offline_id": str(uuid.uuid4())
    }, timeout=30)
    assert r.status_code == 201
    meal_id = r.json()["id"]

    r2 = httpx.delete(f"{api_base}/api/meals/{meal_id}", headers=headers)
    assert r2.status_code == 204

    # Verify gone: PATCH on deleted ID returns 404
    r3 = httpx.patch(f"{api_base}/api/meals/{meal_id}", headers=headers,
                     json={"description": "ghost"}, timeout=30)
    assert r3.status_code == 404


def test_delete_meal_wrong_user(api_base, headers):
    r = httpx.post(f"{api_base}/api/meals", headers=headers, json={
        "description": "private meal", "offline_id": str(uuid.uuid4())
    }, timeout=30)
    assert r.status_code == 201
    meal_id = r.json()["id"]

    # Attempt delete without auth header → 403 or 401
    r2 = httpx.delete(f"{api_base}/api/meals/{meal_id}")
    assert r2.status_code in (401, 403)

    # Cleanup
    httpx.delete(f"{api_base}/api/meals/{meal_id}", headers=headers)
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
cd hearty-api
API_BASE_URL=http://localhost:8080 TEST_JWT=$(cat ../.env | grep TEST_JWT | cut -d= -f2) \
  .venv/bin/pytest tests/test_api.py -v -k "update_meal or delete_meal" 2>&1 | tail -20
```

Expected: 3 failures — `405 Method Not Allowed`.

- [ ] **Step 3: Add PATCH + DELETE to `meals.py`**

Add these imports at the top of `hearty-api/app/routers/meals.py` (alongside existing imports):

```python
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import BaseModel
```

Then append to the bottom of the file:

```python
class MealUpdateRequest(BaseModel):
    description: str


@router.patch("/api/meals/{meal_id}", status_code=200)
async def update_meal(
    meal_id: UUID,
    body: MealUpdateRequest,
    user=Depends(get_current_user),
) -> MealResponse:
    existing = (
        supabase.table("meals")
        .select("id,user_id")
        .eq("id", str(meal_id))
        .eq("user_id", user["id"])
        .execute()
    )
    if not existing.data:
        raise HTTPException(status_code=404, detail="Meal not found")

    extracted = ai_extraction.extract_meal(body.description)
    foods = extracted.get("foods", [])
    inferred_meal_type = extracted.get("inferred_meal_type")

    updates: dict = {"description": body.description, "foods": foods}
    if inferred_meal_type:
        updates["meal_type"] = inferred_meal_type

    result = (
        supabase.table("meals")
        .update(updates)
        .eq("id", str(meal_id))
        .execute()
    )
    return MealResponse(**result.data[0])


@router.delete("/api/meals/{meal_id}", status_code=204)
async def delete_meal(
    meal_id: UUID,
    user=Depends(get_current_user),
):
    existing = (
        supabase.table("meals")
        .select("id,user_id")
        .eq("id", str(meal_id))
        .eq("user_id", user["id"])
        .execute()
    )
    if not existing.data:
        raise HTTPException(status_code=404, detail="Meal not found")
    supabase.table("meals").delete().eq("id", str(meal_id)).execute()
```

Note: `HTTPException` and `UUID` may already be imported if they were added for another reason — check the import block and avoid duplicates.

- [ ] **Step 4: Run the tests to confirm they pass**

```bash
cd hearty-api
API_BASE_URL=http://localhost:8080 TEST_JWT=$(cat ../.env | grep TEST_JWT | cut -d= -f2) \
  .venv/bin/pytest tests/test_api.py -v -k "update_meal or delete_meal"
```

Expected: all 3 pass.

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/routers/meals.py hearty-api/tests/test_api.py
git commit -m "feat: add PATCH + DELETE endpoints for meals"
```

---

## Phase 2: API — Symptoms PATCH + DELETE

**Status:** ⬜ Not Started
**Goal:** Add `PATCH /api/symptoms/{id}` and `DELETE /api/symptoms/{id}` to `hearty-api/app/routers/symptoms.py`.

### Tasks

- [ ] **Step 1: Write the failing tests**

Append to `hearty-api/tests/test_api.py`:

```python
def test_update_symptom(api_base, headers):
    r = httpx.post(f"{api_base}/api/symptoms", headers=headers, json={
        "raw_description": "mild bloating"
    }, timeout=30)
    assert r.status_code == 201
    symptom_id = r.json()[0]["id"]

    r2 = httpx.patch(f"{api_base}/api/symptoms/{symptom_id}", headers=headers,
                     json={"description": "moderate bloating after eating"}, timeout=30)
    assert r2.status_code == 200
    assert r2.json()["id"] == symptom_id

    httpx.delete(f"{api_base}/api/symptoms/{symptom_id}", headers=headers)


def test_delete_symptom(api_base, headers):
    r = httpx.post(f"{api_base}/api/symptoms", headers=headers, json={
        "raw_description": "symptom to delete"
    }, timeout=30)
    assert r.status_code == 201
    symptom_id = r.json()[0]["id"]

    r2 = httpx.delete(f"{api_base}/api/symptoms/{symptom_id}", headers=headers)
    assert r2.status_code == 204

    r3 = httpx.patch(f"{api_base}/api/symptoms/{symptom_id}", headers=headers,
                     json={"description": "ghost"}, timeout=30)
    assert r3.status_code == 404
```

- [ ] **Step 2: Run the tests to confirm they fail**

```bash
cd hearty-api
API_BASE_URL=http://localhost:8080 TEST_JWT=$(cat ../.env | grep TEST_JWT | cut -d= -f2) \
  .venv/bin/pytest tests/test_api.py -v -k "update_symptom or delete_symptom"
```

Expected: 2 failures — `405 Method Not Allowed`.

- [ ] **Step 3: Add PATCH + DELETE to `symptoms.py`**

Add these imports at the top of `hearty-api/app/routers/symptoms.py` (alongside existing imports):

```python
from uuid import UUID
from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
```

Append to the bottom of the file:

```python
class SymptomUpdateRequest(BaseModel):
    description: str


@router.patch("/api/symptoms/{symptom_id}", status_code=200)
async def update_symptom(
    symptom_id: UUID,
    body: SymptomUpdateRequest,
    user=Depends(get_current_user),
) -> SymptomResponse:
    existing = (
        supabase.table("symptoms")
        .select("id,user_id")
        .eq("id", str(symptom_id))
        .eq("user_id", user["id"])
        .execute()
    )
    if not existing.data:
        raise HTTPException(status_code=404, detail="Symptom not found")

    result = (
        supabase.table("symptoms")
        .update({
            "symptom_type": body.description,
            "raw_description": body.description,
        })
        .eq("id", str(symptom_id))
        .execute()
    )
    return SymptomResponse(**result.data[0])


@router.delete("/api/symptoms/{symptom_id}", status_code=204)
async def delete_symptom(
    symptom_id: UUID,
    user=Depends(get_current_user),
):
    existing = (
        supabase.table("symptoms")
        .select("id,user_id")
        .eq("id", str(symptom_id))
        .eq("user_id", user["id"])
        .execute()
    )
    if not existing.data:
        raise HTTPException(status_code=404, detail="Symptom not found")
    supabase.table("symptoms").delete().eq("id", str(symptom_id)).execute()
```

- [ ] **Step 4: Run the tests to confirm they pass**

```bash
cd hearty-api
API_BASE_URL=http://localhost:8080 TEST_JWT=$(cat ../.env | grep TEST_JWT | cut -d= -f2) \
  .venv/bin/pytest tests/test_api.py -v -k "update_symptom or delete_symptom"
```

Expected: both pass.

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/routers/symptoms.py hearty-api/tests/test_api.py
git commit -m "feat: add PATCH + DELETE endpoints for symptoms"
```

---

## Phase 3: API — Wellbeing DELETE

**Status:** ⬜ Not Started
**Goal:** Add `DELETE /api/wellbeing/{id}` to `hearty-api/app/routers/wellbeing.py`. PATCH already exists from Phase 10.

### Tasks

- [ ] **Step 1: Write the failing test**

Append to `hearty-api/tests/test_api.py`:

```python
def test_delete_wellbeing(api_base, headers):
    r = httpx.post(f"{api_base}/api/wellbeing", headers=headers, json={
        "energy_level": 3, "mood": 4
    })
    assert r.status_code == 201
    entry_id = r.json()["id"]

    r2 = httpx.delete(f"{api_base}/api/wellbeing/{entry_id}", headers=headers)
    assert r2.status_code == 204
```

- [ ] **Step 2: Run to confirm it fails**

```bash
cd hearty-api
API_BASE_URL=http://localhost:8080 TEST_JWT=$(cat ../.env | grep TEST_JWT | cut -d= -f2) \
  .venv/bin/pytest tests/test_api.py -v -k "delete_wellbeing"
```

Expected: failure — `405 Method Not Allowed`.

- [ ] **Step 3: Add DELETE to `wellbeing.py`**

Append to the bottom of `hearty-api/app/routers/wellbeing.py`:

```python
@router.delete("/api/wellbeing/{entry_id}", status_code=204)
async def delete_wellbeing(
    entry_id: UUID,
    user=Depends(get_current_user),
):
    existing = (
        supabase.table("wellbeing_snapshots")
        .select("id,user_id")
        .eq("id", str(entry_id))
        .eq("user_id", user["id"])
        .execute()
    )
    if not existing.data:
        raise HTTPException(status_code=404, detail="Entry not found")
    supabase.table("wellbeing_snapshots").delete().eq("id", str(entry_id)).execute()
```

`UUID`, `HTTPException`, and `Depends` are already imported in `wellbeing.py` — no new imports needed.

- [ ] **Step 4: Run the test to confirm it passes**

```bash
cd hearty-api
API_BASE_URL=http://localhost:8080 TEST_JWT=$(cat ../.env | grep TEST_JWT | cut -d= -f2) \
  .venv/bin/pytest tests/test_api.py -v -k "delete_wellbeing"
```

Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/routers/wellbeing.py hearty-api/tests/test_api.py
git commit -m "feat: add DELETE endpoint for wellbeing snapshots"
```

---

## Phase 4: Flutter API Client — 5 New Methods

**Status:** ⬜ Not Started
**Goal:** Add `updateMeal`, `deleteMeal`, `updateSymptom`, `deleteSymptom`, `deleteWellbeing` to `HeartyApiClient`.

**File:** `hearty_app/lib/core/api/hearty_api_client.dart`

### Tasks

- [ ] **Step 1: Add the two meal methods**

In `hearty_app/lib/core/api/hearty_api_client.dart`, after `fetchMealById` (around line 94), add:

```dart
  Future<MealLog> updateMeal(String id, String description) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/api/meals/$id',
      data: {'description': description},
    );
    return MealLog.fromJson(response.data!);
  }

  Future<void> deleteMeal(String id) async {
    await _dio.delete<void>('/api/meals/$id');
  }
```

- [ ] **Step 2: Add the two symptom methods**

After `fetchSymptoms` (around line 137), add:

```dart
  Future<SymptomLog> updateSymptom(String id, String description) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/api/symptoms/$id',
      data: {'description': description},
    );
    return SymptomLog.fromJson(response.data!);
  }

  Future<void> deleteSymptom(String id) async {
    await _dio.delete<void>('/api/symptoms/$id');
  }
```

- [ ] **Step 3: Add the wellbeing delete method**

After `updateWellbeing` (around line 179), add:

```dart
  Future<void> deleteWellbeing(String id) async {
    await _dio.delete<void>('/api/wellbeing/$id');
  }
```

- [ ] **Step 4: Verify it compiles**

```bash
cd hearty_app && flutter analyze lib/core/api/hearty_api_client.dart
```

Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add hearty_app/lib/core/api/hearty_api_client.dart
git commit -m "feat: add updateMeal, deleteMeal, updateSymptom, deleteSymptom, deleteWellbeing to API client"
```

---

## Phase 5: Edit Screens + Routing

**Status:** ⬜ Not Started
**Goal:** Create `EditMealScreen` and `EditSymptomScreen`; wire new routes into GoRouter.

### Tasks

- [ ] **Step 1: Create `EditMealScreen`**

Create `hearty_app/lib/features/logging/screens/edit_meal_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/hearty_api_client.dart';
import '../../../core/api/providers/meals_provider.dart';

class EditMealScreen extends ConsumerStatefulWidget {
  final String id;
  final String initialDescription;

  const EditMealScreen({
    super.key,
    required this.id,
    required this.initialDescription,
  });

  @override
  ConsumerState<EditMealScreen> createState() => _EditMealScreenState();
}

class _EditMealScreenState extends ConsumerState<EditMealScreen> {
  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialDescription);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(heartyApiClientProvider).updateMeal(widget.id, text);
      ref.invalidate(mealsProvider);
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save — try again')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Meal'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 3,
          maxLines: null,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Description',
            border: OutlineInputBorder(),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Create `EditSymptomScreen`**

Create `hearty_app/lib/features/logging/screens/edit_symptom_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/hearty_api_client.dart';
import '../../../core/api/providers/symptoms_provider.dart';

class EditSymptomScreen extends ConsumerStatefulWidget {
  final String id;
  final String initialDescription;

  const EditSymptomScreen({
    super.key,
    required this.id,
    required this.initialDescription,
  });

  @override
  ConsumerState<EditSymptomScreen> createState() => _EditSymptomScreenState();
}

class _EditSymptomScreenState extends ConsumerState<EditSymptomScreen> {
  late final TextEditingController _controller;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialDescription);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ref.read(heartyApiClientProvider).updateSymptom(widget.id, text);
      ref.invalidate(symptomsProvider);
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save — try again')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit Symptom'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            TextButton(onPressed: _save, child: const Text('Save')),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _controller,
          autofocus: true,
          minLines: 3,
          maxLines: null,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Description',
            border: OutlineInputBorder(),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Wire routes in `router.dart`**

In `hearty_app/lib/app/router.dart`, add two imports:

```dart
import '../features/logging/screens/edit_meal_screen.dart';
import '../features/logging/screens/edit_symptom_screen.dart';
```

Add two route name constants in the `Routes` class:

```dart
  static const String editMeal = 'edit-meal';
  static const String editSymptom = 'edit-symptom';
```

Add two `GoRoute` entries alongside the existing `/settings/voice` route:

```dart
      GoRoute(
        path: '/meals/edit',
        name: Routes.editMeal,
        builder: (context, state) {
          final extra = state.extra as Map<String, String>;
          return EditMealScreen(
            id: extra['id']!,
            initialDescription: extra['description']!,
          );
        },
      ),
      GoRoute(
        path: '/symptoms/edit',
        name: Routes.editSymptom,
        builder: (context, state) {
          final extra = state.extra as Map<String, String>;
          return EditSymptomScreen(
            id: extra['id']!,
            initialDescription: extra['description']!,
          );
        },
      ),
```

- [ ] **Step 4: Verify it compiles**

```bash
cd hearty_app && flutter analyze lib/features/logging/screens/edit_meal_screen.dart \
  lib/features/logging/screens/edit_symptom_screen.dart lib/app/router.dart
```

Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add hearty_app/lib/features/logging/screens/edit_meal_screen.dart \
        hearty_app/lib/features/logging/screens/edit_symptom_screen.dart \
        hearty_app/lib/app/router.dart
git commit -m "feat: add EditMealScreen and EditSymptomScreen with routes"
```

---

## Phase 6: Home Screen Long-press Sheet

**Status:** ⬜ Not Started
**Goal:** Long-pressing any entry card on the home screen opens a bottom sheet with Edit and Delete actions.

**File:** `hearty_app/lib/features/logging/screens/home_screen.dart`

### Tasks

- [ ] **Step 1: Convert `_MealCard`, `_SymptomRow`, `_WellbeingRow` to `ConsumerWidget`**

`_MealCard`: change `extends StatelessWidget` → `extends ConsumerWidget`, change `Widget build(BuildContext context)` → `Widget build(BuildContext context, WidgetRef ref)`.

`_SymptomRow`: same change.

`_WellbeingRow`: same change.

- [ ] **Step 2: Add the `_showEntryActions` and `_confirmDelete` helpers**

Add these two top-level functions at the bottom of `home_screen.dart` (after the `_VoiceQueueCard` class):

```dart
// ---------------------------------------------------------------------------
// Entry action helpers (long-press sheet + delete confirmation)
// ---------------------------------------------------------------------------

void _showEntryActions(
  BuildContext context,
  WidgetRef ref, {
  required String editRoute,
  required Map<String, String> editExtra,
  required Future<void> Function() onDelete,
  required Future<void> Function() onInvalidate,
}) {
  showModalBottomSheet<void>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Edit'),
            onTap: () {
              Navigator.of(ctx).pop();
              context.push(editRoute, extra: editExtra);
            },
          ),
          ListTile(
            leading: Icon(
              Icons.delete_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(
              'Delete',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () {
              Navigator.of(ctx).pop();
              _confirmDelete(context, onDelete, onInvalidate);
            },
          ),
        ],
      ),
    ),
  );
}

Future<void> _confirmDelete(
  BuildContext context,
  Future<void> Function() onDelete,
  Future<void> Function() onInvalidate,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Delete this entry?'),
      content: const Text("This can't be undone."),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(
            'Delete',
            style: TextStyle(color: Theme.of(ctx).colorScheme.error),
          ),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await onDelete();
    await onInvalidate();
  }
}
```

- [ ] **Step 3: Add `onLongPress` to `_MealCard`**

In `_MealCard.build`, the `ListTile` currently has `onTap`. Add `onLongPress`:

```dart
          onTap: () => context.push('/log/${meal.id}'),
          onLongPress: () => _showEntryActions(
            context, ref,
            editRoute: '/meals/edit',
            editExtra: {'id': meal.id, 'description': meal.description},
            onDelete: () => ref.read(heartyApiClientProvider).deleteMeal(meal.id),
            onInvalidate: () async => ref.invalidate(mealsProvider),
          ),
```

Add the missing imports to `home_screen.dart` if not already present:

```dart
import '../../../core/api/hearty_api_client.dart';
import '../../../core/api/providers/meals_provider.dart';
import '../../../core/api/providers/symptoms_provider.dart';
```

- [ ] **Step 4: Add `onLongPress` to `_SymptomRow`**

In `_SymptomRow.build`, the `ListTile` currently has `onTap`. Add:

```dart
          onTap: () => context.push('/log/${symptom.id}'),
          onLongPress: () => _showEntryActions(
            context, ref,
            editRoute: '/symptoms/edit',
            editExtra: {'id': symptom.id, 'description': symptom.description},
            onDelete: () => ref.read(heartyApiClientProvider).deleteSymptom(symptom.id),
            onInvalidate: () async => ref.invalidate(symptomsProvider),
          ),
```

- [ ] **Step 5: Add `onLongPress` to `_WellbeingRow`**

In `_WellbeingRow.build`, the `ListTile` currently has `onTap`. Add:

```dart
          onTap: () => context.push('/log/${wellbeing.id}'),
          onLongPress: () => _showEntryActions(
            context, ref,
            editRoute: '/wellbeing/log',
            editExtra: {'id': wellbeing.id},
            onDelete: () => ref.read(heartyApiClientProvider).deleteWellbeing(wellbeing.id),
            onInvalidate: () async => ref.invalidate(wellbeingProvider),
          ),
```

Note: For wellbeing, the edit route is `/wellbeing/log` (existing screen in edit mode). `editExtra` only needs `id` — the router already handles `?id=` as a query param. Update the GoRouter entry for `/wellbeing/log` to accept the extra map or keep passing `context.push('/wellbeing/log?id=${wellbeing.id}')` instead of the extra pattern. Use the existing query param pattern for consistency:

```dart
          onLongPress: () => _showEntryActions(
            context, ref,
            editRoute: '/wellbeing/log?id=${wellbeing.id}',
            editExtra: {},
            onDelete: () => ref.read(heartyApiClientProvider).deleteWellbeing(wellbeing.id),
            onInvalidate: () async => ref.invalidate(wellbeingProvider),
          ),
```

And update `_showEntryActions` to call `context.push(editRoute)` (no `extra`) when `editExtra` is empty, or simplify by always using `context.push(editRoute)` and ignoring the extra parameter for wellbeing. The cleanest fix: change the `editRoute` for wellbeing to already include the query string, and remove `extra` from the navigation call in `_showEntryActions` when it's empty:

```dart
// In _showEntryActions, replace the Edit onTap:
            onTap: () {
              Navigator.of(ctx).pop();
              if (editExtra.isEmpty) {
                context.push(editRoute);
              } else {
                context.push(editRoute, extra: editExtra);
              }
            },
```

- [ ] **Step 6: Verify it compiles**

```bash
cd hearty_app && flutter analyze lib/features/logging/screens/home_screen.dart
```

Expected: No issues.

- [ ] **Step 7: Run all Flutter tests**

```bash
cd hearty_app && flutter test
```

Expected: All tests pass.

- [ ] **Step 8: Commit**

```bash
git add hearty_app/lib/features/logging/screens/home_screen.dart
git commit -m "feat: add long-press edit/delete sheet to home timeline cards"
```

---

## Phase 7: Detail Screen Edit + Delete

**Status:** ⬜ Not Started
**Goal:** Add Edit + Delete app-bar actions to `LogDetailScreen` for all entry types; add Delete button to `WellbeingLogScreen`.

### Tasks

- [ ] **Step 1: Add `_confirmDelete` to `log_detail_screen.dart`**

In `hearty_app/lib/features/logging/screens/log_detail_screen.dart`, add this method to `_LogDetailScreenState`:

```dart
  Future<void> _confirmDelete(
    Future<void> Function() onDelete,
    Future<void> Function() onInvalidate,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text("This can't be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await onDelete();
      await onInvalidate();
      if (mounted) context.pop();
    }
  }
```

- [ ] **Step 2: Replace the plain `AppBar` with one that has Edit + Delete actions**

In `_LogDetailScreenState.build`, find the resolved-entry Scaffold (line ~188):

```dart
    return Scaffold(
      appBar: AppBar(title: const Text('Log Entry')),
```

Replace with:

```dart
    return Scaffold(
      appBar: AppBar(
        title: const Text('Log Entry'),
        actions: [
          switch (_entry) {
            MealLog m => IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit',
                onPressed: () => context.push(
                  '/meals/edit',
                  extra: {'id': m.id, 'description': m.description},
                ),
              ),
            SymptomLog s => IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit',
                onPressed: () => context.push(
                  '/symptoms/edit',
                  extra: {'id': s.id, 'description': s.description},
                ),
              ),
            WellbeingLog w => IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit',
                onPressed: () => context.push('/wellbeing/log?id=${w.id}'),
              ),
            _ => const SizedBox.shrink(),
          },
          IconButton(
            icon: Icon(Icons.delete_outline,
                color: Theme.of(context).colorScheme.error),
            tooltip: 'Delete',
            onPressed: () => switch (_entry) {
              MealLog m => _confirmDelete(
                  () => ref.read(heartyApiClientProvider).deleteMeal(m.id),
                  () async => ref.invalidate(mealsProvider),
                ),
              SymptomLog s => _confirmDelete(
                  () => ref.read(heartyApiClientProvider).deleteSymptom(s.id),
                  () async => ref.invalidate(symptomsProvider),
                ),
              WellbeingLog w => _confirmDelete(
                  () => ref.read(heartyApiClientProvider).deleteWellbeing(w.id),
                  () async => ref.invalidate(wellbeingProvider),
                ),
              _ => Future.value(),
            },
          ),
        ],
      ),
```

- [ ] **Step 3: Add Delete button to `WellbeingLogScreen`**

In `hearty_app/lib/features/wellbeing/screens/wellbeing_log_screen.dart`, find the AppBar (around line 92). The screen is already in edit mode when `widget.entryId != null`. Add a delete action that only appears in edit mode:

```dart
      appBar: AppBar(
        title: Text(widget.entryId != null ? 'Edit Wellbeing' : 'Log Wellbeing'),
        actions: [
          if (widget.entryId != null)
            IconButton(
              icon: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              tooltip: 'Delete',
              onPressed: _deleteEntry,
            ),
        ],
      ),
```

Add the `_deleteEntry` method to the screen's `State` class:

```dart
  Future<void> _deleteEntry() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this entry?'),
        content: const Text("This can't be undone."),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(heartyApiClientProvider).deleteWellbeing(widget.entryId!);
      ref.invalidate(wellbeingProvider);
      if (mounted) context.pop();
    }
  }
```

Add the missing imports to `wellbeing_log_screen.dart` if not already present:

```dart
import '../../../core/api/hearty_api_client.dart';
import '../../../core/api/providers/wellbeing_provider.dart';
```

- [ ] **Step 4: Verify both files compile**

```bash
cd hearty_app && flutter analyze \
  lib/features/logging/screens/log_detail_screen.dart \
  lib/features/wellbeing/screens/wellbeing_log_screen.dart
```

Expected: No issues.

- [ ] **Step 5: Run all Flutter tests**

```bash
cd hearty_app && flutter test
```

Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add hearty_app/lib/features/logging/screens/log_detail_screen.dart \
        hearty_app/lib/features/wellbeing/screens/wellbeing_log_screen.dart
git commit -m "feat: add edit and delete actions to detail screens"
```

---

## Phase 8: Smoke Test

**Status:** ⬜ Not Started
**Goal:** Verify end-to-end that edit and delete work from both entry points for all three entry types.

### Tasks

- [ ] **Step 1: Build and run**

```bash
make run
```

- [ ] **Step 2: Test meal edit from long-press**

1. Log a voice entry: "I had pancakes with syrup."
2. Long-press the meal card on the home timeline.
3. Tap **Edit** in the bottom sheet.
4. Change "syrup" to "maple syrup", tap **Save**.
5. Confirm the card updates to show "maple syrup".

- [ ] **Step 3: Test meal edit from detail screen**

1. Tap the meal card to open `LogDetailScreen`.
2. Tap the edit (pencil) icon in the app bar.
3. Edit and save.
4. Confirm the detail screen updates after popping back.

- [ ] **Step 4: Test meal delete from long-press**

1. Long-press a meal card, tap **Delete**.
2. Confirm the "Delete this entry?" dialog appears.
3. Tap **Delete** — card should disappear from the timeline.

- [ ] **Step 5: Test symptom edit and delete**

Repeat Steps 2–4 for a symptom entry.

- [ ] **Step 6: Test wellbeing edit and delete**

1. Tap a wellbeing period slot to open `WellbeingLogScreen` in edit mode.
2. Confirm the Delete button (trash icon) appears in the app bar.
3. Tap Delete, confirm dialog, confirm entry disappears from the wellbeing snapshot card.

- [ ] **Step 7: Commit any smoke-test fixes**

```bash
git add -p
git commit -m "fix: smoke test corrections for entry edit and delete"
```

---

## Deviation Log

*(append deviations here as they are discovered)*
