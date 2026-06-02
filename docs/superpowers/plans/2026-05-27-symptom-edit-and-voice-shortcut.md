# Symptom Structured Edit + Post-Log Shortcut

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three connected improvements — (1) after voice logging, a SnackBar shortcut lets users jump straight to edit; (2) Hearty nudges users to rate symptom severity in voice follow-ups; (3) the symptom edit screen gains a severity slider and onset time field alongside the existing description.

**Architecture:** Backend `PATCH /api/symptoms/{id}` is extended to accept `severity` and `onset_minutes`. The `SymptomLog` Flutter model and `HeartyApiClient.updateSymptom()` are updated to match. `EditSymptomScreen` gains structured fields pre-populated from the existing entry. A new `lastLoggedMealIdProvider` carries the just-logged meal ID from `VoiceNotifier` to the home screen, which shows a SnackBar with an Edit action. The backend system prompt is updated so Hearty asks users to rate symptoms 1–10 when asking how they feel.

**Tech Stack:** FastAPI + Supabase (Python), Dio + Riverpod + GoRouter (Flutter).

**Plan Status:** ⬜ Not Started

---

## Phase Summary

| Phase | Name | Status |
|-------|------|--------|
| 1 | Backend — extend symptom PATCH with severity + onset_minutes | ⬜ Not Started |
| 2 | Flutter — SymptomLog model + HeartyApiClient.updateSymptom() | ⬜ Not Started |
| 3 | Flutter — structured EditSymptomScreen | ⬜ Not Started |
| 4 | Flutter — update routing to pass severity + onset to EditSymptomScreen | ⬜ Not Started |
| 5 | Flutter — post-log edit shortcut SnackBar | ⬜ Not Started |
| 6 | Backend — symptom severity nudge in voice prompt | ⬜ Not Started |

---

## Phase 1: Backend — extend symptom PATCH with severity + onset_minutes

**Status:** ⬜ Not Started
**Goal:** Allow `PATCH /api/symptoms/{id}` to update `severity` and `onset_minutes` in addition to `raw_description`, so the structured Flutter edit screen can save those fields.

**Files:**
- Modify: `hearty-api/app/routers/symptoms.py`
- Modify: `hearty-api/tests/test_api.py`

### Tasks

- [ ] **Step 1: Write the failing test**

Append to `hearty-api/tests/test_api.py`:

```python
def test_update_symptom_structured_fields(api_base, headers):
    # Create a symptom
    r = httpx.post(f"{api_base}/api/symptoms", headers=headers, json={
        "raw_description": "mild bloating"
    }, timeout=30)
    assert r.status_code == 201
    symptom_id = r.json()[0]["id"]

    # Patch with severity and onset_minutes
    r2 = httpx.patch(f"{api_base}/api/symptoms/{symptom_id}", headers=headers, json={
        "description": "mild bloating",
        "severity": 6,
        "onset_minutes": 30,
    }, timeout=30)
    assert r2.status_code == 200
    body = r2.json()
    assert body["severity"] == 6
    assert body["onset_minutes"] == 30

    # cleanup
    httpx.delete(f"{api_base}/api/symptoms/{symptom_id}", headers=headers)
```

- [ ] **Step 2: Run to confirm it fails**

```bash
cd /home/evan/projects/food-journal-assistant/hearty-api
API_BASE_URL=http://localhost:8000 TEST_JWT=$(cat .test_jwt) python -m pytest tests/test_api.py::test_update_symptom_structured_fields -v
```

Expected: FAIL — `severity` and `onset_minutes` not updated.

- [ ] **Step 3: Extend `SymptomUpdateRequest` and the PATCH handler**

In `hearty-api/app/routers/symptoms.py`, replace `SymptomUpdateRequest` and `update_symptom`:

```python
class SymptomUpdateRequest(BaseModel):
    description: str
    severity: Optional[int] = None
    onset_minutes: Optional[int] = None


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

    updates: dict = {"raw_description": body.description}
    if body.severity is not None:
        updates["severity"] = body.severity
    if body.onset_minutes is not None:
        updates["onset_minutes"] = body.onset_minutes

    result = (
        supabase.table("symptoms")
        .update(updates)
        .eq("id", str(symptom_id))
        .execute()
    )
    return SymptomResponse(**result.data[0])
```

- [ ] **Step 4: Run test to confirm it passes**

```bash
cd /home/evan/projects/food-journal-assistant/hearty-api
API_BASE_URL=http://localhost:8000 TEST_JWT=$(cat .test_jwt) python -m pytest tests/test_api.py::test_update_symptom_structured_fields -v
```

Expected: PASS.

- [ ] **Step 5: Run full test suite**

```bash
cd /home/evan/projects/food-journal-assistant/hearty-api
API_BASE_URL=http://localhost:8000 TEST_JWT=$(cat .test_jwt) python -m pytest tests/test_api.py -v
```

Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add hearty-api/app/routers/symptoms.py hearty-api/tests/test_api.py
git commit -m "feat: extend symptom PATCH to accept severity and onset_minutes"
```

---

## Phase 2: Flutter — SymptomLog model + HeartyApiClient.updateSymptom()

**Status:** ⬜ Not Started
**Goal:** Add `onsetMinutes` to `SymptomLog` and update `HeartyApiClient.updateSymptom()` to send `severity` and `onsetMinutes` to the backend.

**Files:**
- Modify: `hearty_app/lib/core/api/models/symptom_log.dart`
- Modify: `hearty_app/lib/core/api/hearty_api_client.dart`

### Tasks

- [ ] **Step 1: Add `onsetMinutes` to `SymptomLog`**

Replace `hearty_app/lib/core/api/models/symptom_log.dart` with:

```dart
import '../../offline/offline_database.dart';

class SymptomLog {
  final String id;
  final String description;
  final int severity;
  final int? onsetMinutes;
  final String? linkedMealId;
  final DateTime loggedAt;

  const SymptomLog({
    required this.id,
    required this.description,
    required this.severity,
    this.onsetMinutes,
    this.linkedMealId,
    required this.loggedAt,
  });

  factory SymptomLog.fromLocal(LocalSymptom row) {
    return SymptomLog(
      id: row.serverId ?? row.id,
      description: row.description,
      severity: row.severity,
      linkedMealId: row.linkedMealId,
      loggedAt: DateTime.fromMillisecondsSinceEpoch(row.loggedAt),
    );
  }

  factory SymptomLog.fromJson(Map<String, dynamic> json) {
    return SymptomLog(
      id: json['id'] as String,
      description: (json['symptom_type'] as String?) ??
          (json['raw_description'] as String?) ??
          '',
      severity: (json['severity'] as int?) ?? 1,
      onsetMinutes: json['onset_minutes'] as int?,
      linkedMealId: json['meal_id'] as String?,
      loggedAt: DateTime.parse(json['logged_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'symptom_type': description,
        'severity': severity,
        if (onsetMinutes != null) 'onset_minutes': onsetMinutes,
        if (linkedMealId != null) 'meal_id': linkedMealId,
        'logged_at': loggedAt.toIso8601String(),
      };
}
```

- [ ] **Step 2: Update `HeartyApiClient.updateSymptom()`**

In `hearty_app/lib/core/api/hearty_api_client.dart`, replace the existing `updateSymptom` method:

```dart
  Future<SymptomLog> updateSymptom(
    String id,
    String description, {
    int? severity,
    int? onsetMinutes,
  }) async {
    return _call(() async {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/api/symptoms/$id',
        data: <String, dynamic>{
          'description': description,
          if (severity != null) 'severity': severity,
          if (onsetMinutes != null) 'onset_minutes': onsetMinutes,
        },
      );
      return SymptomLog.fromJson(response.data!);
    });
  }
```

- [ ] **Step 3: Run flutter analyze**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
flutter analyze
```

Expected: no issues.

- [ ] **Step 4: Commit**

```bash
git add hearty_app/lib/core/api/models/symptom_log.dart hearty_app/lib/core/api/hearty_api_client.dart
git commit -m "feat: add onsetMinutes to SymptomLog and extend updateSymptom API call"
```

---

## Phase 3: Flutter — structured EditSymptomScreen

**Status:** ⬜ Not Started
**Goal:** Add severity slider (1–10) and onset minutes field to `EditSymptomScreen`, below the existing description text field. Pre-populate from the symptom's current values.

**Files:**
- Modify: `hearty_app/lib/features/logging/screens/edit_symptom_screen.dart`

### Tasks

- [ ] **Step 1: Rewrite `EditSymptomScreen`**

Replace `hearty_app/lib/features/logging/screens/edit_symptom_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/hearty_api_client.dart';
import '../../../core/offline/local_symptom_dao.dart';

class EditSymptomScreen extends ConsumerStatefulWidget {
  final String id;
  final String initialDescription;
  final int? initialSeverity;
  final int? initialOnsetMinutes;

  const EditSymptomScreen({
    super.key,
    required this.id,
    required this.initialDescription,
    this.initialSeverity,
    this.initialOnsetMinutes,
  });

  @override
  ConsumerState<EditSymptomScreen> createState() => _EditSymptomScreenState();
}

class _EditSymptomScreenState extends ConsumerState<EditSymptomScreen> {
  late final TextEditingController _descController;
  late final TextEditingController _onsetController;
  late double _severity;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _descController = TextEditingController(text: widget.initialDescription);
    _severity = (widget.initialSeverity ?? 5).toDouble().clamp(1, 10);
    _onsetController = TextEditingController(
      text: widget.initialOnsetMinutes?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _descController.dispose();
    _onsetController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final text = _descController.text.trim();
    if (text.isEmpty) return;
    setState(() => _saving = true);
    try {
      final onsetText = _onsetController.text.trim();
      final onsetMinutes = onsetText.isEmpty ? null : int.tryParse(onsetText);
      final updated = await ref.read(heartyApiClientProvider).updateSymptom(
            widget.id,
            text,
            severity: _severity.round(),
            onsetMinutes: onsetMinutes,
          );
      await ref.read(localSymptomDaoProvider).upsertFromServer(updated);
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _descController,
              autofocus: true,
              minLines: 3,
              maxLines: null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Description',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Severity: ${_severity.round()} / 10',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            Slider(
              value: _severity,
              min: 1,
              max: 10,
              divisions: 9,
              label: _severity.round().toString(),
              onChanged: (v) => setState(() => _severity = v),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _onsetController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Onset after eating (minutes)',
                hintText: 'e.g. 30',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Run flutter analyze**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
flutter analyze
```

Expected: no issues.

- [ ] **Step 3: Commit**

```bash
git add hearty_app/lib/features/logging/screens/edit_symptom_screen.dart
git commit -m "feat: add severity slider and onset field to EditSymptomScreen"
```

---

## Phase 4: Flutter — update routing to pass severity + onset to EditSymptomScreen

**Status:** ⬜ Not Started
**Goal:** Update the two places that navigate to `/symptoms/edit` — `home_screen.dart` and `log_detail_screen.dart` — to pass `severity` and `onsetMinutes` through the `extra` map. Update the router to extract and forward them.

**Files:**
- Modify: `hearty_app/lib/app/router.dart`
- Modify: `hearty_app/lib/features/logging/screens/home_screen.dart`
- Modify: `hearty_app/lib/features/logging/screens/log_detail_screen.dart`

### Tasks

- [ ] **Step 1: Update the router to extract severity and onsetMinutes**

In `hearty_app/lib/app/router.dart`, find the `/symptoms/edit` route builder and replace it:

```dart
      GoRoute(
        path: '/symptoms/edit',
        name: Routes.editSymptom,
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return EditSymptomScreen(
            id: extra['id'] as String,
            initialDescription: extra['description'] as String,
            initialSeverity: extra['severity'] as int?,
            initialOnsetMinutes: extra['onsetMinutes'] as int?,
          );
        },
      ),
```

- [ ] **Step 2: Update `home_screen.dart` to include severity and onsetMinutes**

In `hearty_app/lib/features/logging/screens/home_screen.dart`, find the line:

```dart
        editExtra: {'id': symptom.id, 'description': symptom.description},
```

Replace with:

```dart
        editExtra: {
          'id': symptom.id,
          'description': symptom.description,
          'severity': symptom.severity,
          'onsetMinutes': symptom.onsetMinutes,
        },
```

- [ ] **Step 3: Update `log_detail_screen.dart` to include severity and onsetMinutes**

In `hearty_app/lib/features/logging/screens/log_detail_screen.dart`, find the symptom edit push:

```dart
                  await context.push(
                    '/symptoms/edit',
                    extra: {'id': s.id, 'description': s.description},
                  );
```

Replace with:

```dart
                  await context.push(
                    '/symptoms/edit',
                    extra: {
                      'id': s.id,
                      'description': s.description,
                      'severity': s.severity,
                      'onsetMinutes': s.onsetMinutes,
                    },
                  );
```

- [ ] **Step 4: Run flutter analyze**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
flutter analyze
```

Expected: no issues.

- [ ] **Step 5: Commit**

```bash
git add hearty_app/lib/app/router.dart hearty_app/lib/features/logging/screens/home_screen.dart hearty_app/lib/features/logging/screens/log_detail_screen.dart
git commit -m "feat: pass severity and onsetMinutes to EditSymptomScreen via router"
```

---

## Phase 5: Flutter — post-log edit shortcut SnackBar

**Status:** ⬜ Not Started
**Goal:** After the voice overlay closes following a successful meal log, show a SnackBar on the home screen with an "Edit" action that navigates directly to `/meals/edit` for the just-logged entry.

**Files:**
- Create: `hearty_app/lib/core/api/providers/last_logged_provider.dart`
- Modify: `hearty_app/lib/features/voice/providers/voice_provider.dart`
- Modify: `hearty_app/lib/app/router.dart`

### Tasks

- [ ] **Step 1: Create `lastLoggedProvider`**

Create `hearty_app/lib/core/api/providers/last_logged_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the meal ID of the most recently voice-logged meal.
/// Set by VoiceNotifier after a successful first-turn log.
/// Cleared by the home screen after showing the edit shortcut SnackBar.
final lastLoggedMealIdProvider = StateProvider<String?>((ref) => null);
```

- [ ] **Step 2: Set `lastLoggedMealIdProvider` in `VoiceNotifier.sendToChat()`**

In `hearty_app/lib/features/voice/providers/voice_provider.dart`, add the import:

```dart
import '../../../core/api/providers/last_logged_provider.dart';
```

In `sendToChat()`, after the successful API call, add one line to set the provider (after `setResponse()`, before the sync trigger):

```dart
      final result = await client.chat(message: transcript);
      if (!mounted) return;
      setResponse(
        result.reply.isNotEmpty ? result.reply : 'Got it! How are you feeling?',
        mealId: result.mealId,
      );
      if (result.mealId != null) {
        ref.read(lastLoggedMealIdProvider.notifier).state = result.mealId;
      }
      ref.read(syncTriggerProvider).schedule();
```

- [ ] **Step 3: Show SnackBar in the wake-word listener in `router.dart`**

In `hearty_app/lib/app/router.dart`, add the import:

```dart
import '../core/api/providers/last_logged_provider.dart';
```

In the wake-word listener block, after the `await showModalBottomSheet(...)` and before `ref.invalidate(mealsProvider)`, add the SnackBar:

```dart
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const VoiceOverlayScreen(),
      );

      // Show edit shortcut if a meal was just logged.
      final loggedMealId = ref.read(lastLoggedMealIdProvider);
      if (loggedMealId != null && context.mounted) {
        ref.read(lastLoggedMealIdProvider.notifier).state = null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Logged! Want to add more detail?'),
            action: SnackBarAction(
              label: 'Edit',
              onPressed: () {
                if (context.mounted) {
                  context.push(
                    '/meals/edit',
                    extra: {'id': loggedMealId, 'description': ''},
                  );
                }
              },
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }

      // Refresh timeline so newly logged entries appear immediately.
      ref.invalidate(mealsProvider);
```

Note: the `description` field in the extra is `''` because `EditMealScreen` pre-populates from the text field's initial value and we're navigating by ID — but check how `EditMealScreen` works first. If it requires a non-empty initial description, fetch the meal description from `mealsProvider` by ID before pushing.

- [ ] **Step 4: Verify EditMealScreen handles empty or missing initial description**

Read `hearty_app/lib/features/logging/screens/edit_meal_screen.dart` to confirm whether `initialDescription` can be empty or should be pre-populated. If EditMealScreen fetches by ID from a provider, pass `''`. If it requires the description for display, look up `mealsProvider` by `loggedMealId` to get the description before calling `context.push`.

Update Step 3 accordingly.

- [ ] **Step 5: Run flutter analyze**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
flutter analyze
```

Expected: no issues.

- [ ] **Step 6: Commit**

```bash
git add hearty_app/lib/core/api/providers/last_logged_provider.dart hearty_app/lib/features/voice/providers/voice_provider.dart hearty_app/lib/app/router.dart
git commit -m "feat: show edit shortcut SnackBar after voice meal log"
```

---

## Phase 6: Backend — symptom severity nudge in voice prompt

**Status:** ⬜ Not Started
**Goal:** Update the system prompts so when Hearty asks "How are you feeling?" after logging a meal, it encourages the user to rate any discomfort 1–10. This increases the likelihood that `extract_symptoms` gets a usable severity value from the follow-up response.

**Files:**
- Modify: `hearty-api/app/routers/chat.py`

### Tasks

- [ ] **Step 1: Update both system prompts**

In `hearty-api/app/routers/chat.py`, in the meal follow-up bullet of both `_BASE_SYSTEM_PROMPT` and `_SIGNAL_SYSTEM_PROMPT_TEMPLATE`, change:

```
- If the description is reasonably specific, acknowledge it warmly and ask how they're feeling.
```

To:

```
- If the description is reasonably specific, acknowledge it warmly and ask how they're feeling — if they mention any discomfort, ask them to rate it 1–10.
```

- [ ] **Step 2: Commit**

```bash
git add hearty-api/app/routers/chat.py
git commit -m "feat: nudge users to rate symptom severity in voice follow-up"
```
