# Voice Rebuild — Phase A: Independent Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the confirmed, low-risk voice-flow fixes that are independent of the STT-engine rebuild — correct "1–10" speech, only re-ask when the reply is a question, an informative check-in notification, a backend guard against fabricating meals, and keep-screen-on during dictation.

**Architecture:** Surgical edits to the existing `VoiceNotifier`/TTS path, the notification service, and the backend chat router. No change to the live STT engine or state machine (those land in Phase B+). Pure-function helpers are exposed `@visibleForTesting` so behavior is unit-tested deterministically.

**Tech Stack:** Flutter/Dart (flutter_test, flutter_riverpod), Python/FastAPI backend (pytest), `wakelock_plus`.

**Scope note:** This is plan **A** of the rebuild (spec: `docs/superpowers/specs/2026-06-07-voice-lifecycle-rebuild-design.md`). Follow-on plans, each device/key-dependent and produced when reached:
- **B** — on-device engine: background-isolate sherpa ASR + `record` mic + trailing-silence auto-submit + new state machine (Flows 1 & 2).
- **C** — cloud engine + `/api/transcribe` backend + online/offline selection.
- **D** — Flow 3 notification reliability, settings UI (`autoSubmit`, `autoSubmitSilenceSeconds`, `useCloudWhenOnline`, `speakCheckInQuestion`), remove `speech_to_text`.

---

### Task 1: TTS speaks digit ranges as "N to M" (fix "1–10" → "one ten")

**Files:**
- Modify: `hearty_app/lib/features/voice/providers/voice_provider.dart` (the `_prepareForSpeech` static; expose it for testing)
- Test: `hearty_app/test/features/voice/voice_provider_test.dart`

- [ ] **Step 1: Write the failing test**

Add to `voice_provider_test.dart` inside the top-level `main()`'s group set:

```dart
  group('prepareForSpeech', () {
    test('reads digit ranges with dash as "to", not the dash', () {
      expect(
        VoiceNotifier.prepareForSpeech('Any discomfort on a scale of 1–10?'),
        'Any discomfort on a scale of 1 to 10?',
      );
      // hyphen and em-dash variants too
      expect(VoiceNotifier.prepareForSpeech('rate it 1-10'), 'rate it 1 to 10');
      expect(VoiceNotifier.prepareForSpeech('1—10'), '1 to 10');
    });

    test('still reads slash ratings as "out of"', () {
      expect(VoiceNotifier.prepareForSpeech('about a 4/10'), 'about a 4 out of 10');
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd hearty_app && flutter test test/features/voice/voice_provider_test.dart --plain-name prepareForSpeech`
Expected: FAIL — `prepareForSpeech` is undefined (it's currently the private `_prepareForSpeech`).

- [ ] **Step 3: Expose the helper and add the range rule**

In `voice_provider.dart`, replace the `_prepareForSpeech` definition with a `@visibleForTesting` public method that also converts dash ranges. Add `import 'package:flutter/foundation.dart';` if not already imported (it is, via `package:flutter/foundation.dart` at the top).

```dart
  /// Normalizes text for natural TTS. Exposed for unit testing.
  @visibleForTesting
  static String prepareForSpeech(String text) {
    text = _stripEmojis(text);
    // "4/10" → "4 out of 10" (rating as a fraction)
    text = text.replaceAllMapped(
      RegExp(r'(\d+)/(\d+)'),
      (m) => '${m[1]} out of ${m[2]}',
    );
    // "1-10" / "1–10" / "1—10" → "1 to 10" (a range, not a fraction) so TTS
    // doesn't read the dash literally ("one ten").
    text = text.replaceAllMapped(
      RegExp(r'(\d+)\s*[-–—]\s*(\d+)'),
      (m) => '${m[1]} to ${m[2]}',
    );
    return text;
  }
```

Then update the single caller in `_speakResponse`:

```dart
    await _tts.speak(prepareForSpeech(response));
```

Delete the old private `_prepareForSpeech` (now replaced by `prepareForSpeech`).

- [ ] **Step 4: Run test to verify it passes**

Run: `cd hearty_app && flutter test test/features/voice/voice_provider_test.dart --plain-name prepareForSpeech`
Expected: PASS (both tests).

- [ ] **Step 5: Verify nothing else broke + commit**

Run: `cd hearty_app && flutter test test/features/voice/voice_provider_test.dart && flutter analyze lib/features/voice/providers/voice_provider.dart`
Expected: all pass, no analyzer issues.

```bash
git add hearty_app/lib/features/voice/providers/voice_provider.dart hearty_app/test/features/voice/voice_provider_test.dart
git commit -m "fix(voice): speak digit ranges as 'N to M' so TTS doesn't read '1-10' as 'one ten'

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Only re-open the follow-up mic when Hearty's reply is a question

**Files:**
- Modify: `hearty_app/lib/features/voice/providers/voice_provider.dart` (add `replyIsQuestion` helper; use it in `sendToChat` and `sendFollowUpToApi`)
- Test: `hearty_app/test/features/voice/voice_provider_test.dart`

Background: today `sendToChat` always re-arms a follow-up (`askFollowUp` defaults `true`), while `sendFollowUpToApi` already gates on `reply.trimRight().endsWith('?')`. Unify both on one helper. (User decision: reopen the mic only when the reply is actually a question.)

- [ ] **Step 1: Write the failing test**

Add to `voice_provider_test.dart`:

```dart
  group('replyIsQuestion', () {
    test('true only when the reply ends with a question mark', () {
      expect(VoiceNotifier.replyIsQuestion('How are you feeling?'), isTrue);
      expect(VoiceNotifier.replyIsQuestion('Logged it.  '), isFalse);
      expect(VoiceNotifier.replyIsQuestion('Got it, enjoy!'), isFalse);
      expect(VoiceNotifier.replyIsQuestion('Any discomfort 1 to 10? '), isTrue);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd hearty_app && flutter test test/features/voice/voice_provider_test.dart --plain-name replyIsQuestion`
Expected: FAIL — `replyIsQuestion` undefined.

- [ ] **Step 3: Add the helper and use it in both send paths**

In `voice_provider.dart` add the helper near `prepareForSpeech`:

```dart
  /// True when Hearty's reply is itself a question (keeps the conversation open
  /// for one more turn). Exposed for unit testing.
  @visibleForTesting
  static bool replyIsQuestion(String reply) => reply.trimRight().endsWith('?');
```

In `sendToChat`, change the success `setResponse` so the follow-up is gated:

```dart
      setResponse(
        result.reply.isNotEmpty ? result.reply : 'Got it! How are you feeling?',
        askFollowUp: replyIsQuestion(
            result.reply.isNotEmpty ? result.reply : 'Got it! How are you feeling?'),
        mealId: result.mealId,
      );
```

In `sendFollowUpToApi`, replace the inline check with the helper:

```dart
      final reply = result.reply.isNotEmpty ? result.reply : 'Got it, thanks!';
      final keepGoing = replyIsQuestion(reply);
      setResponse(reply, askFollowUp: keepGoing);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd hearty_app && flutter test test/features/voice/voice_provider_test.dart --plain-name replyIsQuestion`
Expected: PASS.

- [ ] **Step 5: Full suite + analyze + commit**

Run: `cd hearty_app && flutter test test/features/voice/voice_provider_test.dart && flutter analyze lib/features/voice/providers/voice_provider.dart`
Expected: pass, clean.

```bash
git add hearty_app/lib/features/voice/providers/voice_provider.dart hearty_app/test/features/voice/voice_provider_test.dart
git commit -m "fix(voice): only re-open follow-up mic when the reply is a question

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 3: Post-meal notification tells the user it will listen for a reply

**Files:**
- Modify: `hearty_app/lib/core/notifications/notification_service.dart` (extract title/body to named constants; new body copy)
- Test: `hearty_app/test/core/notifications/notification_copy_test.dart` (create)

- [ ] **Step 1: Write the failing test**

Create `hearty_app/test/core/notifications/notification_copy_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/notifications/notification_service.dart';

void main() {
  test('follow-up notification body tells the user it will listen', () {
    final body = NotificationService.followUpBody.toLowerCase();
    expect(body, contains('listen'));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd hearty_app && flutter test test/core/notifications/notification_copy_test.dart`
Expected: FAIL — `followUpBody` undefined.

- [ ] **Step 3: Add constants and use them**

In `notification_service.dart`, add public constants on `NotificationService` and use them in `scheduleFollowUpNotification`:

```dart
  static const String followUpTitle = 'How are you feeling?';
  static const String followUpBody =
      "Tap to check in on your last meal — I'll listen for your reply.";
```

Replace the inline strings in the `zonedSchedule(...)` call:

```dart
    await _localNotifs.zonedSchedule(
      _kFollowUpNotifId,
      followUpTitle,
      followUpBody,
      scheduled,
      // ...unchanged NotificationDetails / scheduleMode / payload...
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd hearty_app && flutter test test/core/notifications/notification_copy_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze + commit**

Run: `cd hearty_app && flutter analyze lib/core/notifications/notification_service.dart`
Expected: clean.

```bash
git add hearty_app/lib/core/notifications/notification_service.dart hearty_app/test/core/notifications/notification_copy_test.dart
git commit -m "feat(notifications): tell the user the check-in will listen for a reply

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 4: Backend never fabricates a meal on a symptom check-in without a meal id

**Files:**
- Modify: `hearty-api/app/routers/chat.py` (guard the first-turn insert branch)
- Test: `hearty-api/tests/test_chat_followup_unit.py` (add a case)

Background: if a check-in turn arrives with `symptom_followup=true` but no `meal_id` (e.g. local key cleared), the code falls into the first-turn `else` branch and inserts a brand-new meal from the symptom answer ("I feel fine" → a meal). Guard it.

- [ ] **Step 1: Write the failing test**

Add to `hearty-api/tests/test_chat_followup_unit.py` (reuses the file's existing mocked Supabase/litellm fixtures — mirror an existing test's setup):

```python
def test_symptom_followup_without_meal_id_never_inserts_a_meal(monkeypatch):
    rec = {"insert": [], "update": []}
    _install_fakes(monkeypatch, rec, meal_desc=None)  # same helper other tests use

    client = TestClient(app)
    resp = client.post("/api/chat", json={
        "message": "I feel fine",
        "symptom_followup": True,
        # no meal_id
    })
    assert resp.status_code == 200
    # No meal row may be inserted from a no-meal-id check-in.
    assert not any(name == "meals" for (name, _rows) in rec["insert"])
```

> If the existing tests don't expose a shared `_install_fakes` helper, replicate the monkeypatch setup block from the nearest existing test in this file verbatim (mock `chat_module.supabase`, `get_current_user`, `litellm.completion`, and `ai_extraction`).

- [ ] **Step 2: Run test to verify it fails**

Run: `cd hearty-api && .venv/bin/python -m pytest tests/test_chat_followup_unit.py -k symptom_followup_without_meal_id -q`
Expected: FAIL — a meal insert happens.

- [ ] **Step 3: Add the guard**

In `chat.py`, at the very top of the first-turn `else:` insert branch (the `# ── First turn: insert new meal ─` block), add:

```python
    else:
        # A symptom check-in that lost its meal reference must never fabricate a
        # meal from the user's feelings answer. Acknowledge without inserting.
        if body.symptom_followup:
            logger.info("symptom_followup with no meal_id; skipping meal insert")
        else:
            # ... existing first-turn meal-insert code, unchanged ...
```

(Indent the existing insert body under the new `else`.)

- [ ] **Step 4: Run test to verify it passes**

Run: `cd hearty-api && .venv/bin/python -m pytest tests/test_chat_followup_unit.py -q`
Expected: PASS (new test + existing 3).

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/routers/chat.py hearty-api/tests/test_chat_followup_unit.py
git commit -m "fix(chat): never insert a meal on a symptom check-in lacking a meal_id

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 5: Keep the screen on while the voice overlay is active

**Files:**
- Modify: `hearty_app/pubspec.yaml` (add `wakelock_plus`)
- Modify: `hearty_app/lib/features/voice/screens/voice_overlay_screen.dart` (enable on init, disable on dispose)

> Native plugin + screen behavior → **device-verify** this task (no meaningful unit test). Code change is small and isolated.

- [ ] **Step 1: Add the dependency**

In `pubspec.yaml` under `# Audio / Voice` (near `just_audio`):

```yaml
  wakelock_plus: ^1.2.8
```

Run: `cd hearty_app && flutter pub get`
Expected: resolves; `Got dependencies!`.

- [ ] **Step 2: Enable/disable the wakelock with the overlay lifecycle**

In `voice_overlay_screen.dart`, add the import:

```dart
import 'package:wakelock_plus/wakelock_plus.dart';
```

In `_VoiceOverlayScreenState`, add `initState` (the class currently has no `initState`) and extend `dispose`:

```dart
  @override
  void initState() {
    super.initState();
    WakelockPlus.enable(); // keep screen awake during a voice session
  }
```

In the existing `dispose()`, before `super.dispose()`:

```dart
    WakelockPlus.disable();
```

- [ ] **Step 3: Analyze**

Run: `cd hearty_app && flutter analyze lib/features/voice/screens/voice_overlay_screen.dart`
Expected: clean.

- [ ] **Step 4: Device-verify (manual)**

`make run`, trigger a voice session, confirm the screen does not dim/sleep while the overlay is open and returns to normal timeout after it closes.

- [ ] **Step 5: Commit**

```bash
git add hearty_app/pubspec.yaml hearty_app/pubspec.lock hearty_app/lib/features/voice/screens/voice_overlay_screen.dart
git commit -m "feat(voice): keep the screen on while the voice overlay is active

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-review

- **Spec coverage (Phase-A items):** "1 to 10" TTS (Task 1 ✓), Flow-1 question-gated follow-up (Task 2 ✓), Flow-3 notification copy (Task 3 ✓), null-meal-id backend guard (Task 4 ✓), keep-screen-on (Task 5 ✓). Engine/lifecycle/cloud/settings are intentionally deferred to plans B–D.
- **Placeholders:** none — every code step shows the code. Task 4 Step 1 notes the one conditional (replicate the existing fixture block) because the helper name in that test file is unverified; the instruction is explicit about what to copy.
- **Type/name consistency:** `prepareForSpeech` and `replyIsQuestion` are defined in Tasks 1–2 and reused consistently; `followUpTitle`/`followUpBody` defined and used in Task 3.
