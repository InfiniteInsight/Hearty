# Conversation Style Setting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a user-controlled toggle (Warm & Empathetic / Concise & Quick) that controls how Hearty's AI responds across all interactions, chosen during onboarding and adjustable in Settings.

**Architecture:** The preference is stored in `notification_preferences.conversation_style`, flows through the existing preferences API, and is sent with every chat request so the backend can select the appropriate system prompt persona. A new onboarding screen captures the choice before login; a new settings screen allows later changes.

**Tech Stack:** PostgreSQL/Supabase, FastAPI + Pydantic, Flutter + Riverpod + GoRouter, SharedPreferences, flutter_local_notifications, litellm

---

## File Map

**New files:**
- `supabase/migrations/20260530000000_conversation_style.sql`
- `hearty_app/lib/features/setup/screens/conversation_style_setup_screen.dart`
- `hearty_app/lib/features/settings/screens/conversation_style_screen.dart`

**Modified files:**
- `hearty-api/app/routers/preferences.py` — add `conversation_style` to schema, `_row_to_schema`, and upsert
- `hearty-api/app/routers/chat.py` — refactor system prompt into `_make_system_prompt()`, add concise variant, add `conversation_style` to `ChatRequest`
- `hearty-api/tests/test_api.py` — add preferences and chat style tests
- `hearty_app/lib/core/api/models/user_preferences.dart` — add `conversationStyle` field
- `hearty_app/lib/core/api/hearty_api_client.dart` — add `conversationStyle` param to `chat()`
- `hearty_app/lib/features/voice/providers/voice_provider.dart` — pass `conversationStyle` in both chat calls
- `hearty_app/lib/features/logging/screens/onboarding_screen.dart` — sync `conversation_style` from SharedPreferences in both `_finish()` and `_skipToHome()`
- `hearty_app/lib/features/setup/screens/setup_screen.dart` — add conversation style step to `_runSetup()`
- `hearty_app/lib/features/settings/screens/settings_screen.dart` — add Conversation style nav tile
- `hearty_app/lib/app/router.dart` — add two routes, add `/conversation-style-setup` to auth bypass list

---

## Task 1: Database Migration

**Files:**
- Create: `supabase/migrations/20260530000000_conversation_style.sql`

- [ ] **Step 1: Write the migration**

```sql
-- supabase/migrations/20260530000000_conversation_style.sql
alter table notification_preferences
  add column if not exists conversation_style text not null default 'warm'
  check (conversation_style in ('warm', 'concise'));
```

- [ ] **Step 2: Apply it locally**

```bash
supabase db push
```

Expected: migration applies without error. Verify in the Supabase dashboard (or `psql`) that `notification_preferences` now has a `conversation_style` column defaulting to `'warm'`.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260530000000_conversation_style.sql
git commit -m "feat: add conversation_style column to notification_preferences"
```

---

## Task 2: Backend — Preferences Schema & Endpoint

**Files:**
- Modify: `hearty-api/app/routers/preferences.py`

- [ ] **Step 1: Add the field to `UserPreferencesSchema`**

In `preferences.py`, add after `evening_checkin_minute`:

```python
# Conversation style
conversation_style: str = 'warm'
```

- [ ] **Step 2: Add it to `_row_to_schema`**

In the `return UserPreferencesSchema(...)` block, add after `evening_checkin_minute=...`:

```python
        conversation_style=np.get("conversation_style") or "warm",
```

- [ ] **Step 3: Add it to the upsert in `update_preferences`**

In `notif_row = {...}`, add after `"evening_checkin_minute": body.evening_checkin_minute,`:

```python
        "conversation_style": body.conversation_style,
```

- [ ] **Step 4: Add it to the `notif_row` filter**

The existing filter is:
```python
notif_row = {k: v for k, v in notif_row.items() if v is not None or k == "fcm_token"}
```

`conversation_style` is always non-None (has a default), so no change needed here.

- [ ] **Step 5: Write a failing test**

In `hearty-api/tests/test_api.py`, add:

```python
def test_preferences_includes_conversation_style(api_base, headers):
    r = httpx.get(f"{api_base}/api/preferences", headers=headers, timeout=30)
    assert r.status_code == 200
    body = r.json()
    assert "conversation_style" in body
    assert body["conversation_style"] in ("warm", "concise")

def test_preferences_update_conversation_style(api_base, headers):
    r = httpx.get(f"{api_base}/api/preferences", headers=headers, timeout=30)
    current = r.json()
    new_style = "concise" if current.get("conversation_style") == "warm" else "warm"
    payload = {**current, "conversation_style": new_style}
    r2 = httpx.put(f"{api_base}/api/preferences", headers=headers, json=payload, timeout=30)
    assert r2.status_code == 200
    assert r2.json()["conversation_style"] == new_style
    # Restore original
    httpx.put(f"{api_base}/api/preferences", headers=headers, json=current, timeout=30)
```

- [ ] **Step 6: Run the tests to verify they fail first**

```bash
cd hearty-api && python -m pytest tests/test_api.py::test_preferences_includes_conversation_style tests/test_api.py::test_preferences_update_conversation_style -v
```

Expected: both tests FAIL (field not in response yet).

- [ ] **Step 7: Run tests again after implementing**

```bash
cd hearty-api && python -m pytest tests/test_api.py::test_preferences_includes_conversation_style tests/test_api.py::test_preferences_update_conversation_style -v
```

Expected: both PASS.

- [ ] **Step 8: Commit**

```bash
git add hearty-api/app/routers/preferences.py hearty-api/tests/test_api.py
git commit -m "feat: add conversation_style to preferences schema and endpoint"
```

---

## Task 3: Backend — Chat System Prompt Refactor + Concise Mode

**Files:**
- Modify: `hearty-api/app/routers/chat.py`

- [ ] **Step 1: Split `_MEAL_CLARIFICATION_RULES` into base + always variants**

Replace the existing `_MEAL_CLARIFICATION_RULES` constant and the two system prompt constants with the following. The base rules are unchanged except the `ALWAYS:` line is removed from the end and defined separately per style.

```python
_MEAL_CLARIFICATION_RULES_BASE = """
Your job has two steps: (1) get a clear enough meal description, (2) learn how the user is feeling. Only ask for what you don't already have, and only if it genuinely matters.

STEP 1 — Is the meal description clear enough to log?

It IS clear enough when any of these are true:
- A brand name is present — brand already identifies the product as commercial; origin and type are known.
- The user listed specific ingredients they combined — clearly homemade and specific enough.
- The user said "homemade" explicitly.
- It's a named item from a named chain or restaurant (e.g. "Big Mac", "Chipotle burrito bowl").
- It's a simple, unambiguous whole food (e.g. apple, banana, hard-boiled egg, glass of milk).
- The food type is specific enough that origin wouldn't meaningfully change its nutritional character (e.g. coffee, green tea, water).

It is NOT clear enough when:
- It's a packaged/commercial food category with no brand named (e.g. "a protein bar", "an energy drink", "a granola bar") — ask for the brand (and flavor if not already mentioned), since nutrition varies widely by product.
- Origin is genuinely ambiguous AND would significantly change what was eaten (e.g. "a burrito", "a sandwich", "pizza") — homemade vs. a restaurant vs. a frozen brand are very different meals.
- The description is too vague to log at all (e.g. "a snack", "some food", "I ate something").

If not clear enough: ask ONE question covering only the missing piece — never ask for information the user already gave.

STEP 2 — Have they said how they're feeling?

Look at everything the user has said in this conversation:
- If they reported a symptom or discomfort but gave no severity rating → ask them to rate it 1–10.
- If they reported a symptom or discomfort AND already gave a number → respond and close.
- If they said they feel fine, good, normal, or similar → that's complete; close without asking for a number.
- If they haven't mentioned how they're feeling at all → ask how they're feeling after eating and invite a 1–10 rating, e.g. "How are you feeling after eating? Any discomfort on a scale of 1–10?" If they reply with "fine" or "good" or similar, that's complete — don't push for a number.

READING THE CONVERSATION STATE

Check Hearty's most recent message before responding:
- Hearty last asked a meal clarification question → the user is answering it. After their answer, go to Step 2. If feelings haven't been covered yet, ask now. Do NOT close early.
- Hearty last asked how they're feeling → the user is answering that. Apply Step 2 rules and close. Ask nothing else.
- This is the first message in the conversation → run Step 1 then Step 2 in order."""

_ALWAYS_WARM = "ALWAYS: One question per turn. Under 2 sentences. Warm but concise. Never repeat a question already answered. When closing, end with a brief warm statement — not a question."
_ALWAYS_CONCISE = "ALWAYS: One question per turn. Under 2 sentences. Never repeat a question already answered. When closing, confirm with one short statement."

_OFF_TOPIC_WARM = 'If the message is not about food, eating, symptoms, or wellbeing, decline warmly in one sentence and redirect, e.g. "I\'m just a food and health journal — I can\'t help with that, but I can log what you ate or how you\'re feeling."'
_OFF_TOPIC_CONCISE = 'If the message is not about food, eating, symptoms, or wellbeing, decline in one sentence and redirect, e.g. "I\'m just a food and health journal — I can\'t help with that, but I can log what you ate or how you\'re feeling."'


def _make_system_prompt(signal_context: Optional[str], style: str) -> str:
    if style == "concise":
        preamble = (
            "You are Hearty, a health and food journal assistant.\n"
            "The user is logging what they ate or how they're feeling.\n"
            "Do not comment on the user's food choices, lifestyle, or emotional state. "
            "When they report symptoms or wellbeing, log without adding commentary or empathy."
        )
        always = _ALWAYS_CONCISE
        off_topic = _OFF_TOPIC_CONCISE
    else:
        preamble = (
            "You are Hearty, a friendly health and food journal assistant.\n"
            "The user is logging what they ate or how they're feeling.\n"
            "When they describe symptoms or wellbeing, respond with brief empathy."
        )
        always = _ALWAYS_WARM
        off_topic = _OFF_TOPIC_WARM

    parts = [preamble, _MEAL_CLARIFICATION_RULES_BASE, always, off_topic]
    if signal_context:
        parts.append(f"\n{signal_context}")
    return "\n".join(parts)
```

- [ ] **Step 2: Delete the old constants and update `ChatRequest`**

Remove `_MEAL_CLARIFICATION_RULES`, `_BASE_SYSTEM_PROMPT`, and `_SIGNAL_SYSTEM_PROMPT_TEMPLATE`.

In `ChatRequest`, add:

```python
class ChatRequest(BaseModel):
    message: str
    health_context: Optional[dict] = None
    logged_at: Optional[datetime] = None
    meal_id: Optional[str] = None
    history: Optional[list[dict]] = None
    conversation_style: Optional[str] = "warm"
```

- [ ] **Step 3: Update the prompt-building block in the `chat` handler**

Replace the block that currently reads:

```python
    signal_context = _build_signal_context(user["id"])
    if signal_context:
        system_prompt = _SIGNAL_SYSTEM_PROMPT_TEMPLATE.replace(
            "{signal_context}", signal_context
        )
    else:
        system_prompt = _BASE_SYSTEM_PROMPT
```

With:

```python
    signal_context = _build_signal_context(user["id"])
    system_prompt = _make_system_prompt(signal_context, body.conversation_style or "warm")
```

- [ ] **Step 4: Write failing unit tests for `_make_system_prompt`**

Create `hearty-api/tests/test_chat_prompts.py`:

```python
import pytest

def test_make_system_prompt_warm_has_empathy_instruction():
    from app.routers.chat import _make_system_prompt
    prompt = _make_system_prompt(None, "warm")
    assert "respond with brief empathy" in prompt
    assert "Warm but concise" in prompt

def test_make_system_prompt_concise_has_no_empathy():
    from app.routers.chat import _make_system_prompt
    prompt = _make_system_prompt(None, "concise")
    assert "respond with brief empathy" not in prompt
    assert "Warm but concise" not in prompt
    assert "Do not comment" in prompt

def test_make_system_prompt_concise_closes_without_warmth():
    from app.routers.chat import _make_system_prompt
    prompt = _make_system_prompt(None, "concise")
    assert "brief warm statement" not in prompt
    assert "confirm with one short statement" in prompt

def test_make_system_prompt_defaults_to_warm():
    from app.routers.chat import _make_system_prompt
    warm = _make_system_prompt(None, "warm")
    default = _make_system_prompt(None, "unknown_value")
    assert warm == default

def test_make_system_prompt_includes_signal_context():
    from app.routers.chat import _make_system_prompt
    prompt = _make_system_prompt("Known food signals: dairy → bloating", "warm")
    assert "dairy" in prompt
```

- [ ] **Step 5: Run the tests to verify they fail**

```bash
cd hearty-api && python -m pytest tests/test_chat_prompts.py -v
```

Expected: all 5 FAIL with `ImportError: cannot import name '_make_system_prompt'` (function doesn't exist yet).

- [ ] **Step 6: Run tests again after implementing Steps 1–3**

```bash
cd hearty-api && python -m pytest tests/test_chat_prompts.py -v
```

Expected: all 5 PASS.

- [ ] **Step 7: Run the full test suite**

```bash
cd hearty-api && python -m pytest tests/test_api.py -v
```

Expected: all tests pass.

- [ ] **Step 8: Commit**

```bash
git add hearty-api/app/routers/chat.py hearty-api/tests/test_chat_prompts.py
git commit -m "feat: add concise conversation style to chat endpoint"
```

---

## Task 4: Flutter — `UserPreferences` Model

**Files:**
- Modify: `hearty_app/lib/core/api/models/user_preferences.dart`

- [ ] **Step 1: Add the field to the class**

After `eveningCheckinMinute`:

```dart
  final String conversationStyle;
```

- [ ] **Step 2: Add to the constructor**

In the `const UserPreferences({...})` constructor, add after `this.eveningCheckinMinute = 0,`:

```dart
    this.conversationStyle = 'warm',
```

- [ ] **Step 3: Add to `fromJson`**

After `eveningCheckinMinute: ...`:

```dart
      conversationStyle: (json['conversation_style'] as String?) ?? 'warm',
```

- [ ] **Step 4: Add to `toJson`**

After `'evening_checkin_minute': eveningCheckinMinute,`:

```dart
        'conversation_style': conversationStyle,
```

- [ ] **Step 5: Add to `copyWith`**

Parameter list — after `int? eveningCheckinMinute,`:

```dart
    String? conversationStyle,
```

Return statement — after `eveningCheckinMinute: eveningCheckinMinute ?? this.eveningCheckinMinute,`:

```dart
      conversationStyle: conversationStyle ?? this.conversationStyle,
```

- [ ] **Step 6: Verify no analysis errors**

```bash
cd hearty_app && flutter analyze lib/core/api/models/user_preferences.dart
```

Expected: No issues found.

- [ ] **Step 7: Commit**

```bash
git add hearty_app/lib/core/api/models/user_preferences.dart
git commit -m "feat: add conversationStyle to UserPreferences model"
```

---

## Task 5: Flutter — API Client + Voice Provider

**Files:**
- Modify: `hearty_app/lib/core/api/hearty_api_client.dart:252-272`
- Modify: `hearty_app/lib/features/voice/providers/voice_provider.dart`

- [ ] **Step 1: Add `conversationStyle` to `HeartyApiClient.chat()`**

Replace the existing `chat()` method:

```dart
  Future<ChatResult> chat({
    required String message,
    String? mealId,
    List<Map<String, String>>? history,
    Map<String, dynamic>? healthContext,
    DateTime? loggedAt,
    String conversationStyle = 'warm',
  }) {
    return _call(() async {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/chat',
        data: <String, dynamic>{
          'message': message,
          'meal_id': ?mealId,
          'history': ?history,
          'health_context': healthContext,
          'logged_at': loggedAt?.toUtc().toIso8601String(),
          'conversation_style': conversationStyle,
        }..removeWhere((_, v) => v == null),
      );
      return ChatResult.fromJson(response.data!);
    });
  }
```

- [ ] **Step 2: Update `sendToChat()` in `voice_provider.dart`**

In `sendToChat()`, the existing call is:
```dart
      final result = await client.chat(message: transcript);
```

The `prefs` variable is read later in the same method. Move the read up and use it for both `conversationStyle` and the existing `postMealNudgeEnabled` check. Replace the existing code from the `client.chat(...)` call through the prefs read:

```dart
      final prefs = ref.read(preferencesProvider).valueOrNull;
      final result = await client.chat(
        message: transcript,
        conversationStyle: prefs?.conversationStyle ?? 'warm',
      );
      if (!mounted) return;
      setResponse(
        result.reply.isNotEmpty ? result.reply : 'Got it! How are you feeling?',
        mealId: result.mealId,
      );
      if (result.mealId != null) {
        ref.read(lastLoggedMealIdProvider.notifier).state = result.mealId;
        final sharedPrefs = await SharedPreferences.getInstance();
        await sharedPrefs.setString('hearty_last_meal_id', result.mealId!);
        if (prefs != null && prefs.postMealNudgeEnabled) {
          await NotificationService.scheduleFollowUpNotification(prefs.nudgeDelayMinutes);
        }
      }
```

(Remove the now-redundant second `ref.read(preferencesProvider).valueOrNull` that was previously below the `client.chat()` call.)

- [ ] **Step 3: Update `sendFollowUpToApi()` in `voice_provider.dart`**

Replace the existing `client.chat(...)` call in `sendFollowUpToApi()`:

```dart
      final result = await client.chat(
        message: transcript,
        mealId: state.pendingMealId,
        history: state.history.isEmpty ? null : state.history,
        conversationStyle: ref.read(preferencesProvider).valueOrNull?.conversationStyle ?? 'warm',
      );
```

- [ ] **Step 4: Verify no analysis errors**

```bash
cd hearty_app && flutter analyze lib/core/api/hearty_api_client.dart lib/features/voice/providers/voice_provider.dart
```

Expected: No issues found.

- [ ] **Step 5: Commit**

```bash
git add hearty_app/lib/core/api/hearty_api_client.dart hearty_app/lib/features/voice/providers/voice_provider.dart
git commit -m "feat: pass conversationStyle through chat API calls"
```

---

## Task 6: Flutter — Onboarding Sync

**Files:**
- Modify: `hearty_app/lib/features/logging/screens/onboarding_screen.dart`

- [ ] **Step 1: Add `conversation_style` read to `_finish()`**

In `_finish()`, the existing `save()` call is:

```dart
      await ref.read(preferencesProvider.notifier).save(
            existing.copyWith(
              allergens: _allergens,
              conditions: _conditions,
              dietaryProtocols: _protocols,
              medications: _medications,
              postMealNudgeEnabled:
                  prefs.getBool('notification_post_meal_enabled') ?? true,
              dailyCheckinEnabled:
                  prefs.getBool('notification_checkin_enabled') ?? true,
            ),
          );
```

Add `conversationStyle` to the `copyWith`:

```dart
      await ref.read(preferencesProvider.notifier).save(
            existing.copyWith(
              allergens: _allergens,
              conditions: _conditions,
              dietaryProtocols: _protocols,
              medications: _medications,
              postMealNudgeEnabled:
                  prefs.getBool('notification_post_meal_enabled') ?? true,
              dailyCheckinEnabled:
                  prefs.getBool('notification_checkin_enabled') ?? true,
              conversationStyle:
                  prefs.getString('conversation_style') ?? 'warm',
            ),
          );
```

- [ ] **Step 2: Add `conversation_style` read to `_skipToHome()`**

In `_skipToHome()`, the existing `save()` call is:

```dart
      await ref.read(preferencesProvider.notifier).save(
            existing.copyWith(
              postMealNudgeEnabled:
                  prefs.getBool('notification_post_meal_enabled') ?? true,
              dailyCheckinEnabled:
                  prefs.getBool('notification_checkin_enabled') ?? true,
            ),
          );
```

Add `conversationStyle`:

```dart
      await ref.read(preferencesProvider.notifier).save(
            existing.copyWith(
              postMealNudgeEnabled:
                  prefs.getBool('notification_post_meal_enabled') ?? true,
              dailyCheckinEnabled:
                  prefs.getBool('notification_checkin_enabled') ?? true,
              conversationStyle:
                  prefs.getString('conversation_style') ?? 'warm',
            ),
          );
```

- [ ] **Step 3: Verify no analysis errors**

```bash
cd hearty_app && flutter analyze lib/features/logging/screens/onboarding_screen.dart
```

Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add hearty_app/lib/features/logging/screens/onboarding_screen.dart
git commit -m "feat: sync conversation_style from SharedPreferences in onboarding"
```

---

## Task 7: Flutter — `ConversationStyleSetupScreen` (Onboarding)

**Files:**
- Create: `hearty_app/lib/features/setup/screens/conversation_style_setup_screen.dart`

- [ ] **Step 1: Create the screen**

```dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ConversationStyleSetupScreen extends StatefulWidget {
  const ConversationStyleSetupScreen({super.key});

  @override
  State<ConversationStyleSetupScreen> createState() =>
      _ConversationStyleSetupScreenState();
}

class _ConversationStyleSetupScreenState
    extends State<ConversationStyleSetupScreen> {
  String _selected = 'warm';
  bool _saving = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('conversation_style', _selected);
    await prefs.setBool('conversation_style_configured', true);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _skip() async {
    if (_saving) return;
    setState(() => _saving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('conversation_style', 'warm');
    await prefs.setBool('conversation_style_configured', true);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('💬', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 16),
              Text(
                'How should Hearty talk to you?',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'You can change this anytime in Settings.',
                style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              _StyleCard(
                value: 'warm',
                selected: _selected,
                icon: '❤️',
                title: 'Warm & Empathetic',
                subtitle: 'Supportive responses with context and warmth.',
                exampleReply: 'Comfort food evening! 🍝 Was that homemade or from a restaurant?',
                onTap: () => setState(() => _selected = 'warm'),
              ),
              const SizedBox(height: 12),
              _StyleCard(
                value: 'concise',
                selected: _selected,
                icon: '⚡',
                title: 'Concise & Quick',
                subtitle: 'Just the essentials — log it and move on.',
                exampleReply: 'Logged. Homemade or restaurant?',
                onTap: () => setState(() => _selected = 'concise'),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Looks good →'),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _saving ? null : _skip,
                child: const Text(
                  'Skip for now',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StyleCard extends StatelessWidget {
  final String value;
  final String selected;
  final String icon;
  final String title;
  final String subtitle;
  final String exampleReply;
  final VoidCallback onTap;

  const _StyleCard({
    required this.value,
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.exampleReply,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selected;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.primary
                : Colors.white24,
            width: 2,
          ),
          color: isSelected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.05),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$icon $title',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  // Mini example exchange
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(12),
                          topRight: Radius.circular(12),
                          bottomLeft: Radius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Had pasta for dinner',
                        style: TextStyle(color: Colors.white, fontSize: 11),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: const BorderRadius.only(
                        topRight: Radius.circular(12),
                        bottomLeft: Radius.circular(12),
                        bottomRight: Radius.circular(12),
                      ),
                    ),
                    child: Text(
                      exampleReply,
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white30,
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify no analysis errors**

```bash
cd hearty_app && flutter analyze lib/features/setup/screens/conversation_style_setup_screen.dart
```

Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add hearty_app/lib/features/setup/screens/conversation_style_setup_screen.dart
git commit -m "feat: add ConversationStyleSetupScreen for onboarding"
```

---

## Task 8: Flutter — Wire Onboarding Step into `SetupScreen`

**Files:**
- Modify: `hearty_app/lib/features/setup/screens/setup_screen.dart`
- Modify: `hearty_app/lib/app/router.dart`

- [ ] **Step 1: Add import to `setup_screen.dart`**

At the top of the file, the existing imports include `notification_setup_screen.dart` implicitly via the route push. No direct import needed — the route is `/conversation-style-setup` which will be registered in the router.

- [ ] **Step 2: Add the third step to `_runSetup()`**

In `setup_screen.dart`, after the `notifPrefsConfigured` block:

```dart
    // --- Conversation style ---
    final styleConfigured =
        prefs.getBool('conversation_style_configured') ?? false;
    if (!styleConfigured) {
      if (!mounted) return;
      await context.push('/conversation-style-setup');
    }
```

The full `_runSetup()` method after this change:

```dart
  Future<void> _runSetup() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();

    // --- Permission wizard ---
    final optedOut = prefs.getBool('wake_word_setup_opted_out') ?? false;
    final micGranted = await Permission.microphone.isGranted;
    final overlayGranted = await Permission.systemAlertWindow.isGranted;
    final batteryExempt = await Permission.ignoreBatteryOptimizations.isGranted;
    final wizardDone =
        optedOut || (micGranted && overlayGranted && batteryExempt);

    if (!wizardDone) {
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.black87,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        isDismissible: false,
        enableDrag: false,
        builder: (_) => const AppSetupSheet(),
      );
    }

    if (!mounted) return;

    // --- Notification preferences ---
    final notifPrefsConfigured =
        prefs.getBool('notification_prefs_configured') ?? false;
    if (!notifPrefsConfigured) {
      await context.push('/notification-setup');
    }

    if (!mounted) return;

    // --- Conversation style ---
    final styleConfigured =
        prefs.getBool('conversation_style_configured') ?? false;
    if (!styleConfigured) {
      await context.push('/conversation-style-setup');
    }

    if (!mounted) return;
    // Forward to normal auth flow — router redirect handles the rest.
    context.go('/home');
  }
```

- [ ] **Step 3: Register the route in `router.dart`**

Add the import at the top of `router.dart`:

```dart
import '../features/setup/screens/conversation_style_setup_screen.dart';
```

In the `Routes` class, add:

```dart
  static const String conversationStyleSetup = 'conversation-style-setup';
```

Add the route to the routes list (near the other setup routes):

```dart
      GoRoute(
        path: '/conversation-style-setup',
        name: Routes.conversationStyleSetup,
        builder: (context, state) => const ConversationStyleSetupScreen(),
      ),
```

Add `/conversation-style-setup` to the auth redirect bypass in the redirect function. Currently:

```dart
      if (!isAuthenticated && !isOnSignIn && !isOnSetup && !isOnNotificationSetup) {
```

Change to:

```dart
      final isOnConversationStyleSetup = location == '/conversation-style-setup';
      if (!isAuthenticated && !isOnSignIn && !isOnSetup && !isOnNotificationSetup && !isOnConversationStyleSetup) {
```

- [ ] **Step 4: Verify no analysis errors**

```bash
cd hearty_app && flutter analyze lib/features/setup/screens/setup_screen.dart lib/app/router.dart
```

Expected: No issues found.

- [ ] **Step 5: Commit**

```bash
git add hearty_app/lib/features/setup/screens/setup_screen.dart hearty_app/lib/app/router.dart
git commit -m "feat: add conversation style step to onboarding setup flow"
```

---

## Task 9: Flutter — `ConversationStyleScreen` (Settings)

**Files:**
- Create: `hearty_app/lib/features/settings/screens/conversation_style_screen.dart`

- [ ] **Step 1: Create the screen**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers/preferences_provider.dart';

class ConversationStyleScreen extends ConsumerStatefulWidget {
  const ConversationStyleScreen({super.key});

  @override
  ConsumerState<ConversationStyleScreen> createState() =>
      _ConversationStyleScreenState();
}

class _ConversationStyleScreenState
    extends ConsumerState<ConversationStyleScreen> {
  late String _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = ref.read(preferencesProvider).valueOrNull?.conversationStyle ?? 'warm';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final existing = ref.read(preferencesProvider).valueOrNull;
    if (existing == null) {
      setState(() => _saving = false);
      return;
    }
    await ref.read(preferencesProvider.notifier).save(
          existing.copyWith(conversationStyle: _selected),
        );
    if (!mounted) return;
    final result = ref.read(preferencesProvider);
    if (result.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save — please try again')),
      );
    }
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conversation Style')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Choose how Hearty talks to you during logging and check-ins.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          _StyleCard(
            value: 'warm',
            selected: _selected,
            icon: '❤️',
            title: 'Warm & Empathetic',
            subtitle: 'Hearty adds warmth and context to responses. Great if you want to feel supported.',
            exampleExchanges: const [
              ('Had a big bowl of pasta for dinner',
               'Comfort food evening! 🍝 I\'ve noted that. Since pasta can vary quite a bit — was it homemade or from a restaurant?'),
              ('Feeling really tired and bloated',
               'I\'m sorry you\'re not feeling your best 💙 I\'ve logged that for you.'),
            ],
            onTap: () => setState(() => _selected = 'warm'),
          ),
          const SizedBox(height: 12),
          _StyleCard(
            value: 'concise',
            selected: _selected,
            icon: '⚡',
            title: 'Concise & Quick',
            subtitle: 'Just the facts. Hearty logs and confirms without commentary or added warmth.',
            exampleExchanges: const [
              ('Had a big bowl of pasta for dinner', 'Logged. Homemade or restaurant?'),
              ('Feeling really tired and bloated', 'Logged.'),
            ],
            onTap: () => setState(() => _selected = 'concise'),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _StyleCard extends StatelessWidget {
  final String value;
  final String selected;
  final String icon;
  final String title;
  final String subtitle;
  final List<(String user, String hearty)> exampleExchanges;
  final VoidCallback onTap;

  const _StyleCard({
    required this.value,
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.exampleExchanges,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selected;
    final colorScheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
            width: 2,
          ),
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.05)
              : colorScheme.surface,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$icon $title',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                Icon(
                  isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: isSelected ? colorScheme.primary : colorScheme.outline,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: isSelected
                    ? colorScheme.primaryContainer.withValues(alpha: 0.4)
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'EXAMPLE',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          letterSpacing: 0.5,
                        ),
                  ),
                  const SizedBox(height: 8),
                  for (final (userMsg, heartyMsg) in exampleExchanges) ...[
                    Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 6, left: 32),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(12),
                            topRight: Radius.circular(12),
                            bottomLeft: Radius.circular(12),
                          ),
                        ),
                        child: Text(
                          userMsg,
                          style: TextStyle(
                              color: colorScheme.onPrimary, fontSize: 12),
                        ),
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(bottom: 8, right: 32),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        border: Border.all(color: colorScheme.outlineVariant),
                        borderRadius: const BorderRadius.only(
                          topRight: Radius.circular(12),
                          bottomLeft: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                      ),
                      child: Text(
                        heartyMsg,
                        style: TextStyle(
                            color: colorScheme.onSurface, fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: Verify no analysis errors**

```bash
cd hearty_app && flutter analyze lib/features/settings/screens/conversation_style_screen.dart
```

Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add hearty_app/lib/features/settings/screens/conversation_style_screen.dart
git commit -m "feat: add ConversationStyleScreen for settings"
```

---

## Task 10: Flutter — Wire Settings Nav + Router

**Files:**
- Modify: `hearty_app/lib/features/settings/screens/settings_screen.dart`
- Modify: `hearty_app/lib/app/router.dart`

- [ ] **Step 1: Add import to `router.dart`**

```dart
import '../features/settings/screens/conversation_style_screen.dart';
```

- [ ] **Step 2: Add route name to `Routes` class in `router.dart`**

```dart
  static const String conversationStyle = 'conversation-style';
```

- [ ] **Step 3: Add the route to the routes list in `router.dart`**

Near the other settings routes:

```dart
      GoRoute(
        path: '/settings/conversation',
        name: Routes.conversationStyle,
        builder: (context, state) => const ConversationStyleScreen(),
      ),
```

- [ ] **Step 4: Add the nav tile to `settings_screen.dart`**

After the Voice tile and before the `const Divider()` that precedes Health Profile:

```dart
          ListTile(
            leading: const Icon(Icons.chat_bubble_outline),
            title: const Text('Conversation style'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/conversation'),
          ),
```

- [ ] **Step 5: Verify no analysis errors**

```bash
cd hearty_app && flutter analyze lib/features/settings/screens/settings_screen.dart lib/app/router.dart
```

Expected: No issues found.

- [ ] **Step 6: Run full Flutter analyze**

```bash
cd hearty_app && flutter analyze
```

Expected: No issues found.

- [ ] **Step 7: Commit**

```bash
git add hearty_app/lib/features/settings/screens/settings_screen.dart hearty_app/lib/app/router.dart
git commit -m "feat: wire conversation style into settings nav and router"
```

---

## Manual Smoke Test Checklist

After all tasks are committed, verify end-to-end:

- [ ] Fresh install (clear app data): onboarding shows conversation style step as the last setup step; "Looks good →" and "Skip for now" both work
- [ ] Settings → Conversation style shows both cards with examples; saving persists across app restarts
- [ ] Voice log in Warm mode: AI response includes contextual warmth / empathy
- [ ] Voice log in Concise mode: AI reply is short, no commentary, clarification question has no preamble
- [ ] Wellbeing check-in in Concise mode: "Logged." with no empathetic follow-on
- [ ] Existing users (who already completed onboarding): do not see the onboarding step; default in settings is Warm
