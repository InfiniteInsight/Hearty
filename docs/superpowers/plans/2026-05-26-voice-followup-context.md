# Voice Follow-Up Conversation Context

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix voice follow-up turns so clarifications refine the existing entry instead of creating a duplicate, and symptom responses create symptom entries instead of stray meals.

**Architecture:** Two-part fix. Backend: `/api/chat` returns the created `meal_id` on first turn; a follow-up request carrying `meal_id` + `history` skips the auto-insert, updates the existing meal with a combined description, and extracts any symptoms from the follow-up text. Flutter: `VoiceState` gains `pendingMealId` and `originalTranscript`; `VoiceNotifier` stores these on first-turn response, passes them as history + `meal_id` on the follow-up API call.

**Tech Stack:** FastAPI + litellm + Supabase (Python backend), Dio + Riverpod (Flutter client).

**Spec:** N/A — design settled in conversation.

**Plan Status:** ⬜ Not Started

---

## Phase Summary

| Phase | Name | Status |
|-------|------|--------|
| 1 | Backend — return `meal_id` in `ChatResponse` | ⬜ Not Started |
| 2 | Backend — follow-up handling (update meal + extract symptoms) | ⬜ Not Started |
| 3 | Flutter — `ChatResult` model | ⬜ Not Started |
| 4 | Flutter — `VoiceState` conversation context fields | ⬜ Not Started |
| 5 | Flutter — wire `VoiceNotifier` + `HeartyApiClient` | ⬜ Not Started |

---

## Phase 1: Backend — return `meal_id` in `ChatResponse`

**Status:** ⬜ Not Started
**Goal:** Make the first-turn `/api/chat` call return the `meal_id` of the row it inserted, so the Flutter client can reference it in a follow-up.

**Files:**
- Modify: `hearty-api/app/routers/chat.py`
- Modify: `hearty-api/tests/test_api.py`

### Tasks

- [ ] **Step 1: Write the failing test**

Append to `hearty-api/tests/test_api.py`:

```python
def test_chat_returns_meal_id(api_base, headers):
    r = httpx.post(f"{api_base}/api/chat", headers=headers, json={
        "message": "I had oatmeal for breakfast"
    }, timeout=30)
    assert r.status_code == 200
    body = r.json()
    assert "reply" in body
    assert "meal_id" in body
    assert body["meal_id"] is not None
    # cleanup
    httpx.delete(f"{api_base}/api/meals/{body['meal_id']}", headers=headers)
```

- [ ] **Step 2: Run to confirm it fails**

```bash
cd /home/evan/projects/food-journal-assistant/hearty-api
API_BASE_URL=http://localhost:8000 TEST_JWT=$(cat .test_jwt) python -m pytest tests/test_api.py::test_chat_returns_meal_id -v
```

Expected: FAIL — `meal_id` key missing from response.

- [ ] **Step 3: Add `meal_id` to `ChatResponse` and populate it**

In `hearty-api/app/routers/chat.py`, change `ChatResponse` and the meal-insert block:

```python
class ChatResponse(BaseModel):
    reply: str
    meal_id: Optional[str] = None
```

In `@router.post("/api/chat")`, capture the inserted ID:

```python
    # Log the message as a meal entry in the background (best-effort).
    meal_id: Optional[str] = None
    try:
        foods = None
        inferred_meal_type = None
        try:
            extracted = ai_extraction.extract_meal(body.message)
            foods = extracted.get("foods") or None
            inferred_meal_type = extracted.get("inferred_meal_type")
        except Exception as extract_err:
            logger.warning("Meal extraction failed (inserting raw): %s", extract_err)

        row = {
            "user_id": user["id"],
            "description": body.message,
            "meal_type": inferred_meal_type,
            "foods": foods,
            "logged_at": (body.logged_at or datetime.now(timezone.utc)).isoformat(),
            "input_method": "voice",
        }
        row = {k: v for k, v in row.items() if v is not None}
        result = supabase.table("meals").insert(row).execute()
        meal_id = result.data[0]["id"] if result.data else None
        logger.info("Meal inserted: %s", result.data)
    except Exception as e:
        logger.error("Meal insert failed: %s", e, exc_info=True)
```

Return it at the bottom of the handler:

```python
    return ChatResponse(reply=reply, meal_id=meal_id)
```

- [ ] **Step 4: Run test to confirm it passes**

```bash
cd /home/evan/projects/food-journal-assistant/hearty-api
API_BASE_URL=http://localhost:8000 TEST_JWT=$(cat .test_jwt) python -m pytest tests/test_api.py::test_chat_returns_meal_id -v
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/routers/chat.py hearty-api/tests/test_api.py
git commit -m "feat: return meal_id from POST /api/chat response"
```

---

## Phase 2: Backend — follow-up handling

**Status:** ⬜ Not Started
**Goal:** When a follow-up request arrives (`meal_id` + `history` provided), skip auto-insert, update the existing meal using a combined description, extract any symptoms from the follow-up text, and pass full conversation history to the LLM for a contextual reply.

**Files:**
- Modify: `hearty-api/app/routers/chat.py`
- Modify: `hearty-api/tests/test_api.py`

### Tasks

- [ ] **Step 1: Write the failing tests**

Append to `hearty-api/tests/test_api.py`:

```python
def test_chat_followup_updates_meal_not_inserts(api_base, headers):
    # First turn: create meal
    r1 = httpx.post(f"{api_base}/api/chat", headers=headers, json={
        "message": "I ate a protein bar"
    }, timeout=30)
    assert r1.status_code == 200
    meal_id = r1.json()["meal_id"]
    assert meal_id is not None

    # Count meals before follow-up
    meals_before = httpx.get(f"{api_base}/api/meals", headers=headers).json()["total"]

    # Follow-up with clarification
    r2 = httpx.post(f"{api_base}/api/chat", headers=headers, json={
        "message": "Aloha brand chocolate chip",
        "meal_id": meal_id,
        "history": [
            {"role": "user", "content": "I ate a protein bar"},
            {"role": "assistant", "content": "What brand and flavor was it?"},
        ],
    }, timeout=30)
    assert r2.status_code == 200
    assert "reply" in r2.json()

    # No new meal created
    meals_after = httpx.get(f"{api_base}/api/meals", headers=headers).json()["total"]
    assert meals_after == meals_before

    # Existing meal updated with combined description
    updated = httpx.get(f"{api_base}/api/meals/{meal_id}", headers=headers).json()
    assert "aloha" in updated["description"].lower() or any(
        "aloha" in str(f).lower() for f in (updated.get("foods") or [])
    )

    # cleanup
    httpx.delete(f"{api_base}/api/meals/{meal_id}", headers=headers)


def test_chat_followup_symptom_creates_symptom_not_meal(api_base, headers):
    # First turn
    r1 = httpx.post(f"{api_base}/api/chat", headers=headers, json={
        "message": "I ate a protein bar"
    }, timeout=30)
    assert r1.status_code == 200
    meal_id = r1.json()["meal_id"]

    meals_before = httpx.get(f"{api_base}/api/meals", headers=headers).json()["total"]
    symptoms_before = httpx.get(f"{api_base}/api/symptoms", headers=headers).json()

    # Follow-up with symptom
    r2 = httpx.post(f"{api_base}/api/chat", headers=headers, json={
        "message": "I'm feeling bloated",
        "meal_id": meal_id,
        "history": [
            {"role": "user", "content": "I ate a protein bar"},
            {"role": "assistant", "content": "How are you feeling?"},
        ],
    }, timeout=30)
    assert r2.status_code == 200

    # No new meal
    meals_after = httpx.get(f"{api_base}/api/meals", headers=headers).json()["total"]
    assert meals_after == meals_before

    # Symptom created
    symptoms_after = httpx.get(f"{api_base}/api/symptoms", headers=headers).json()
    assert len(symptoms_after) > len(symptoms_before)

    # cleanup
    httpx.delete(f"{api_base}/api/meals/{meal_id}", headers=headers)
    if symptoms_after:
        new_ids = {s["id"] for s in symptoms_after} - {s["id"] for s in symptoms_before}
        for sid in new_ids:
            httpx.delete(f"{api_base}/api/symptoms/{sid}", headers=headers)
```

- [ ] **Step 2: Run to confirm they fail**

```bash
cd /home/evan/projects/food-journal-assistant/hearty-api
API_BASE_URL=http://localhost:8000 TEST_JWT=$(cat .test_jwt) python -m pytest tests/test_api.py::test_chat_followup_updates_meal_not_inserts tests/test_api.py::test_chat_followup_symptom_creates_symptom_not_meal -v
```

Expected: both FAIL (follow-up currently inserts a new meal instead of updating).

- [ ] **Step 3: Add `meal_id` and `history` to `ChatRequest` and implement follow-up branch**

Replace the `ChatRequest` class and the `@router.post("/api/chat")` handler body in `hearty-api/app/routers/chat.py`:

```python
class ChatRequest(BaseModel):
    message: str
    health_context: Optional[dict] = None
    logged_at: Optional[datetime] = None
    meal_id: Optional[str] = None
    history: Optional[list[dict]] = None
```

Replace the meal-insert block at the top of the handler with this branching logic:

```python
    meal_id: Optional[str] = body.meal_id

    if meal_id:
        # ── Follow-up turn: update existing meal, maybe log symptoms ──────────
        try:
            # Build combined description from original user message + follow-up
            original = next(
                (m["content"] for m in (body.history or []) if m.get("role") == "user"),
                "",
            )
            combined = f"{original}. {body.message}" if original else body.message

            # Re-extract and update the meal row
            try:
                extracted = ai_extraction.extract_meal(combined)
                foods = extracted.get("foods") or None
                inferred_meal_type = extracted.get("inferred_meal_type")
            except Exception as extract_err:
                logger.warning("Follow-up meal extraction failed: %s", extract_err)
                foods = None
                inferred_meal_type = None

            updates: dict = {"description": combined}
            if foods is not None:
                updates["foods"] = foods
            if inferred_meal_type:
                updates["meal_type"] = inferred_meal_type

            supabase.table("meals").update(updates).eq("id", meal_id).eq(
                "user_id", user["id"]
            ).execute()
        except Exception as e:
            logger.error("Follow-up meal update failed: %s", e, exc_info=True)

        # Try to extract and log symptoms from the follow-up text
        try:
            symptoms = ai_extraction.extract_symptoms(body.message)
            if symptoms:
                rows = [
                    {
                        "user_id": user["id"],
                        "symptom_type": s.get("symptom_type", "other"),
                        "severity": s.get("severity"),
                        "onset_minutes": s.get("onset_minutes"),
                        "duration_minutes": s.get("duration_minutes"),
                        "bathroom_urgency": s.get("bathroom_urgency"),
                        "bathroom_visits": s.get("bathroom_visits"),
                        "stool_consistency": s.get("stool_consistency"),
                        "raw_description": body.message,
                        "logged_at": datetime.now(timezone.utc).isoformat(),
                    }
                    for s in symptoms
                ]
                rows = [{k: v for k, v in r.items() if v is not None} for r in rows]
                supabase.table("symptom_logs").insert(rows).execute()
        except Exception as e:
            logger.error("Follow-up symptom extraction failed: %s", e, exc_info=True)

    else:
        # ── First turn: insert new meal ────────────────────────────────────────
        try:
            foods = None
            inferred_meal_type = None
            try:
                extracted = ai_extraction.extract_meal(body.message)
                foods = extracted.get("foods") or None
                inferred_meal_type = extracted.get("inferred_meal_type")
            except Exception as extract_err:
                logger.warning("Meal extraction failed (inserting raw): %s", extract_err)

            row = {
                "user_id": user["id"],
                "description": body.message,
                "meal_type": inferred_meal_type,
                "foods": foods,
                "logged_at": (body.logged_at or datetime.now(timezone.utc)).isoformat(),
                "input_method": "voice",
            }
            row = {k: v for k, v in row.items() if v is not None}
            result = supabase.table("meals").insert(row).execute()
            meal_id = result.data[0]["id"] if result.data else None
            logger.info("Meal inserted: %s", result.data)
        except Exception as e:
            logger.error("Meal insert failed: %s", e, exc_info=True)
```

Build the messages list for the LLM using history if provided:

```python
    # Build LLM messages — include conversation history for follow-ups
    lm_messages: list[dict] = []
    if body.history:
        lm_messages.extend(body.history)
    lm_messages.append({"role": "user", "content": body.message})
```

Replace the LLM completion block:

```python
    try:
        response = litellm.completion(
            model=_MODEL,
            messages=lm_messages,
            system=system_prompt,
            max_tokens=100,
        )
        reply = response.choices[0].message.content or "Got it! How are you feeling?"
    except Exception:
        reply = f'Got it! I logged "{body.message}". How are you feeling?'

    return ChatResponse(reply=reply, meal_id=meal_id)
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
cd /home/evan/projects/food-journal-assistant/hearty-api
API_BASE_URL=http://localhost:8000 TEST_JWT=$(cat .test_jwt) python -m pytest tests/test_api.py::test_chat_followup_updates_meal_not_inserts tests/test_api.py::test_chat_followup_symptom_creates_symptom_not_meal -v
```

Expected: both PASS.

- [ ] **Step 5: Run full test suite to check for regressions**

```bash
cd /home/evan/projects/food-journal-assistant/hearty-api
API_BASE_URL=http://localhost:8000 TEST_JWT=$(cat .test_jwt) python -m pytest tests/test_api.py -v
```

Expected: all existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add hearty-api/app/routers/chat.py hearty-api/tests/test_api.py
git commit -m "feat: follow-up chat turn updates existing meal and extracts symptoms"
```

---

## Phase 3: Flutter — `ChatResult` model

**Status:** ⬜ Not Started
**Goal:** Replace the bare `String` return type from `HeartyApiClient.chat()` with a typed model that carries both `reply` and `mealId`.

**Files:**
- Create: `hearty_app/lib/core/api/models/chat_result.dart`

### Tasks

- [ ] **Step 1: Create the model file**

Create `hearty_app/lib/core/api/models/chat_result.dart`:

```dart
class ChatResult {
  final String reply;
  final String? mealId;

  const ChatResult({required this.reply, this.mealId});

  factory ChatResult.fromJson(Map<String, dynamic> json) => ChatResult(
        reply: (json['reply'] as String?) ??
            (json['response'] as String?) ??
            (json['message'] as String?) ??
            '',
        mealId: json['meal_id'] as String?,
      );
}
```

- [ ] **Step 2: Run `flutter analyze` to confirm no issues**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
flutter analyze lib/core/api/models/chat_result.dart
```

Expected: no issues.

- [ ] **Step 3: Commit**

```bash
git add hearty_app/lib/core/api/models/chat_result.dart
git commit -m "feat: add ChatResult model for typed chat API response"
```

---

## Phase 4: Flutter — `VoiceState` conversation context fields

**Status:** ⬜ Not Started
**Goal:** Store the original user message and pending meal ID in `VoiceState` so `sendFollowUpToApi()` can reference them.

**Files:**
- Modify: `hearty_app/lib/features/voice/models/voice_state.dart`

### Tasks

- [ ] **Step 1: Add fields to `VoiceState`**

Replace `hearty_app/lib/features/voice/models/voice_state.dart` with:

```dart
enum VoiceStatus { idle, listening, thinking, responding, awaitingFollowUp }

class VoiceState {
  final VoiceStatus status;
  final String transcript;
  final String response;
  final String? pendingMealId;
  final String? originalTranscript;

  const VoiceState({
    this.status = VoiceStatus.idle,
    this.transcript = '',
    this.response = '',
    this.pendingMealId,
    this.originalTranscript,
  });

  VoiceState copyWith({
    VoiceStatus? status,
    String? transcript,
    String? response,
    String? pendingMealId,
    String? originalTranscript,
  }) =>
      VoiceState(
        status: status ?? this.status,
        transcript: transcript ?? this.transcript,
        response: response ?? this.response,
        pendingMealId: pendingMealId ?? this.pendingMealId,
        originalTranscript: originalTranscript ?? this.originalTranscript,
      );
}
```

- [ ] **Step 2: Run `flutter analyze` to confirm no issues**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
flutter analyze lib/features/voice/models/voice_state.dart
```

Expected: no issues.

- [ ] **Step 3: Commit**

```bash
git add hearty_app/lib/features/voice/models/voice_state.dart
git commit -m "feat: add pendingMealId and originalTranscript to VoiceState"
```

---

## Phase 5: Flutter — wire `VoiceNotifier` + `HeartyApiClient`

**Status:** ⬜ Not Started
**Goal:** Update `HeartyApiClient.chat()` to send/receive history and `meal_id`, then update `VoiceNotifier` to store the returned `mealId` on first turn and pass conversation history on the follow-up.

**Files:**
- Modify: `hearty_app/lib/core/api/hearty_api_client.dart`
- Modify: `hearty_app/lib/features/voice/providers/voice_provider.dart`

### Tasks

- [ ] **Step 1: Update `HeartyApiClient.chat()` to use `ChatResult`**

In `hearty_app/lib/core/api/hearty_api_client.dart`:

Add import at top:

```dart
import 'models/chat_result.dart';
```

Replace the `chat()` method:

```dart
  Future<ChatResult> chat({
    required String message,
    String? mealId,
    List<Map<String, String>>? history,
    Map<String, dynamic>? healthContext,
    DateTime? loggedAt,
  }) {
    return _call(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/chat',
        data: <String, dynamic>{
          'message': message,
          if (mealId != null) 'meal_id': mealId,
          if (history != null) 'history': history,
          'health_context': healthContext,
          'logged_at': loggedAt?.toUtc().toIso8601String(),
        }..removeWhere((_, v) => v == null),
      );
      return ChatResult.fromJson(response.data!);
    });
  }
```

- [ ] **Step 2: Run `flutter analyze` on the client file**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
flutter analyze lib/core/api/hearty_api_client.dart
```

Expected: no issues.

- [ ] **Step 3: Update `VoiceNotifier` to pass and store conversation context**

In `hearty_app/lib/features/voice/providers/voice_provider.dart`:

Update `setResponse()` to accept and store `mealId`:

```dart
  void setResponse(String response, {bool askFollowUp = true, String? mealId}) {
    state = state.copyWith(
      status: VoiceStatus.responding,
      response: response,
      pendingMealId: mealId ?? state.pendingMealId,
    );
    _speakResponse(response, askFollowUp);
  }
```

Update `setAwaitingFollowUp()` to save `transcript` as `originalTranscript` before clearing:

```dart
  void setAwaitingFollowUp() {
    if (!mounted) return;
    state = state.copyWith(
      status: VoiceStatus.awaitingFollowUp,
      originalTranscript: state.transcript,
      transcript: '',
    );
    _beginFollowUpStt();
  }
```

Update `sendToChat()` to store the returned `mealId`:

```dart
  Future<void> sendToChat() async {
    final transcript = state.transcript;
    if (transcript.isEmpty) return;

    const nonHealthKeywords = ['weather', 'news', 'music', 'sports', 'stock', 'remind'];
    if (nonHealthKeywords.any((k) => transcript.toLowerCase().contains(k))) {
      setResponse("That's outside what I track. I focus on food, symptoms, and wellbeing.", askFollowUp: false);
      return;
    }

    final ref = _ref;
    if (ref == null) {
      setResponse('Got it! I logged "$transcript". How are you feeling?');
      return;
    }

    try {
      final client = ref.read(heartyApiClientProvider);
      final result = await client.chat(message: transcript);
      if (!mounted) return;
      setResponse(
        result.reply.isNotEmpty ? result.reply : 'Got it! How are you feeling?',
        mealId: result.mealId,
      );
      ref.read(syncTriggerProvider).schedule();
    } on OfflineException {
      if (!mounted) return;
      final ref = _ref;
      if (ref != null) {
        final dao = ref.read(localVoiceQueueDaoProvider);
        await dao.insertPending(
          id: _uuid.v4(),
          transcript: transcript,
          loggedAt: DateTime.now(),
        );
      }
      setResponse(
        "You're offline or Hearty is down. I'll save that and log it when you reconnect.",
        askFollowUp: false,
      );
    } catch (_) {
      if (!mounted) return;
      setResponse('Got it! I logged "$transcript". How are you feeling?');
    }
  }
```

Update `sendFollowUpToApi()` to pass conversation history and `mealId`:

```dart
  Future<void> sendFollowUpToApi() async {
    final transcript = state.transcript;
    if (transcript.isEmpty) {
      dismiss();
      return;
    }
    final ref = _ref;
    if (ref == null) {
      setResponse('Got it, thanks!', askFollowUp: false);
      return;
    }
    try {
      final client = ref.read(heartyApiClientProvider);
      final history = <Map<String, String>>[
        if (state.originalTranscript?.isNotEmpty == true)
          {'role': 'user', 'content': state.originalTranscript!},
        if (state.response.isNotEmpty)
          {'role': 'assistant', 'content': state.response},
      ];
      final result = await client.chat(
        message: transcript,
        mealId: state.pendingMealId,
        history: history.isEmpty ? null : history,
      );
      if (!mounted) return;
      setResponse(result.reply.isNotEmpty ? result.reply : 'Got it, thanks!', askFollowUp: false);
      ref.read(syncTriggerProvider).schedule();
    } catch (_) {
      if (!mounted) return;
      setResponse('Got it, thanks!', askFollowUp: false);
    }
  }
```

Also reset `pendingMealId` and `originalTranscript` in `dismiss()`:

```dart
  void dismiss() {
    if (_stt.isListening) _stt.stop();
    _tts.stop();
    state = const VoiceState();
  }
```

`state = const VoiceState()` already resets all fields since the new fields default to `null`. No change needed here.

- [ ] **Step 4: Run `flutter analyze` on the provider**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
flutter analyze lib/features/voice/providers/voice_provider.dart
```

Expected: no issues.

- [ ] **Step 5: Run full Flutter analyze**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
flutter analyze
```

Expected: no issues.

- [ ] **Step 6: Commit**

```bash
git add hearty_app/lib/core/api/hearty_api_client.dart hearty_app/lib/features/voice/providers/voice_provider.dart
git commit -m "feat: pass conversation history and meal_id on follow-up voice turns"
```
