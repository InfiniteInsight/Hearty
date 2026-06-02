# Follow-Up Restart Beep Suppression Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep only the first "I'm listening" beep on a follow-up turn and silence the beeps from the restart (window-extension) sessions, by muting the candidate audio streams natively during the restart window.

**Architecture:** A new Android `com.hearty.app/audio` MethodChannel mutes/restores the candidate beep streams (`STREAM_MUSIC`/`STREAM_SYSTEM`/`STREAM_NOTIFICATION`) via `AudioManager`. A thin Dart `AudioBeepChannel` wraps it. `VoiceNotifier` arms a ~800ms timer when the first follow-up session opens (so the first beep plays, then mute engages before the restarts) and releases the mute through a single idempotent funnel on every exit path.

**Tech Stack:** Flutter, Riverpod (StateNotifier), `speech_to_text`, Kotlin + Android `AudioManager`, `dart:async` Timer.

**Spec:** `docs/superpowers/specs/2026-06-02-followup-beep-suppression-design.md`

**Branch:** `voice-beep-mute` (current).

**Plan Status:** ⬜ Not Started

---

## Phase Summary

| Phase | Name | Status |
|-------|------|--------|
| 1 | Native — `com.hearty.app/audio` mute channel (MainActivity.kt) | ⬜ Not Started |
| 2 | Dart — `AudioBeepChannel` wrapper | ⬜ Not Started |
| 3 | `VoiceNotifier` — suppress timer + release funnel | ⬜ Not Started |
| 4 | On-device verification (Pixel over wifi) | ⬜ Not Started |

---

## Phase 1: Native — `com.hearty.app/audio` mute channel

**Status:** ⬜ Not Started
**Goal:** Add a native channel that mutes/restores the candidate beep streams, idempotently and safely (per-stream try/catch; auto-restore on background).

**Files:**
- Modify: `hearty_app/android/app/src/main/kotlin/com/hearty/app/MainActivity.kt`

### Tasks

- [ ] **Step 1: Add AudioManager imports**

In `hearty_app/android/app/src/main/kotlin/com/hearty/app/MainActivity.kt`, add to the import block (after `import android.content.pm.PackageManager`):

```kotlin
import android.media.AudioManager
import android.util.Log
```

- [ ] **Step 2: Add suppression state + helper + channel + background safety net**

In the `MainActivity` class, add these fields right after the `pendingWakeWord` field (line ~19):

```kotlin
    // Beep suppression: Android's SpeechRecognizer plays start/stop beeps on a
    // device-dependent stream. We can't query which, so we mute the candidate
    // set during follow-up restart sessions and restore them.
    private var beepSuppressed = false
    private val beepStreams = intArrayOf(
        AudioManager.STREAM_MUSIC,
        AudioManager.STREAM_SYSTEM,
        AudioManager.STREAM_NOTIFICATION,
    )

    private fun setBeepSuppressed(suppressed: Boolean) {
        if (suppressed == beepSuppressed) return
        val am = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        val dir = if (suppressed) AudioManager.ADJUST_MUTE else AudioManager.ADJUST_UNMUTE
        for (s in beepStreams) {
            // Per-stream try/catch: muting SYSTEM/NOTIFICATION can throw on some
            // OEMs (DND policy) — that just means that stream isn't suppressed,
            // never a crash. MUSIC (the common beep stream) needs no permission.
            try { am.adjustStreamVolume(s, dir, 0) }
            catch (e: Exception) { Log.w("HeartyAudio", "stream $s adjust($dir) failed", e) }
        }
        beepSuppressed = suppressed
    }
```

Register the channel inside `configureFlutterEngine`, right after the `com.hearty.app/wake_word_control` channel block (before the `// Cold-start` comment near line 85):

```kotlin
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.hearty.app/audio")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setBeepSuppressed" -> {
                        setBeepSuppressed(call.arguments as? Boolean ?: false)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
```

Add an `onStop` override as a safety net (place it after `configureFlutterEngine`, before `applyShowWhenLocked`):

```kotlin
    override fun onStop() {
        super.onStop()
        // Never leave streams muted if the app backgrounds mid-suppression.
        if (beepSuppressed) setBeepSuppressed(false)
    }
```

- [ ] **Step 3: Verify it compiles (gradle/native has no Dart unit test)**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
/home/evan/tools/flutter/bin/flutter build apk --debug --dart-define-from-file=../.env 2>&1 | tail -6
```

Expected: `✓ Built build/app/outputs/flutter-apk/app-debug.apk` (Kotlin compiles).

- [ ] **Step 4: Commit**

```bash
git add hearty_app/android/app/src/main/kotlin/com/hearty/app/MainActivity.kt
git commit -m "feat(android): com.hearty.app/audio channel to mute recognizer beep streams"
```

---

## Phase 2: Dart — `AudioBeepChannel` wrapper

**Status:** ⬜ Not Started
**Goal:** A thin, error-swallowing Dart wrapper over the native channel, injectable for tests.

**Files:**
- Create: `hearty_app/lib/core/audio/audio_beep_channel.dart`
- Create: `hearty_app/test/core/audio/audio_beep_channel_test.dart`

### Tasks

- [ ] **Step 1: Write the failing test**

Create `hearty_app/test/core/audio/audio_beep_channel_test.dart`:

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/audio/audio_beep_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.hearty.app/audio');
  final calls = <MethodCall>[];

  void mock(Future<dynamic> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
  }

  setUp(() {
    calls.clear();
    mock((call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() => mock((_) async => null));

  test('suppress invokes setBeepSuppressed(true)', () async {
    await AudioBeepChannel().suppress();
    expect(calls.single.method, 'setBeepSuppressed');
    expect(calls.single.arguments, true);
  });

  test('restore invokes setBeepSuppressed(false)', () async {
    await AudioBeepChannel().restore();
    expect(calls.single.method, 'setBeepSuppressed');
    expect(calls.single.arguments, false);
  });

  test('platform exceptions are swallowed (no throw)', () async {
    mock((_) async => throw PlatformException(code: 'boom'));
    await AudioBeepChannel().suppress(); // must not throw
    await AudioBeepChannel().restore(); // must not throw
  });
}
```

- [ ] **Step 2: Run to confirm it fails**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
/home/evan/tools/flutter/bin/flutter test test/core/audio/audio_beep_channel_test.dart
```

Expected: FAIL — `audio_beep_channel.dart` / `AudioBeepChannel` doesn't exist.

- [ ] **Step 3: Create the wrapper**

Create `hearty_app/lib/core/audio/audio_beep_channel.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Mutes/restores the candidate Android audio streams that the system
/// SpeechRecognizer plays its start/stop beeps on, so follow-up restart
/// sessions don't beep. Backed by the native `com.hearty.app/audio` channel.
/// Errors (incl. non-Android platforms with no handler) are swallowed —
/// callers never need try/catch; worst case is an un-suppressed beep.
class AudioBeepChannel {
  static const MethodChannel _channel = MethodChannel('com.hearty.app/audio');

  Future<void> suppress() => _set(true);
  Future<void> restore() => _set(false);

  Future<void> _set(bool suppressed) async {
    try {
      await _channel.invokeMethod('setBeepSuppressed', suppressed);
    } catch (e) {
      debugPrint('AudioBeepChannel.setBeepSuppressed($suppressed) failed: $e');
    }
  }
}
```

- [ ] **Step 4: Run test to confirm it passes**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
/home/evan/tools/flutter/bin/flutter test test/core/audio/audio_beep_channel_test.dart
```

Expected: PASS.

- [ ] **Step 5: Analyze**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
/home/evan/tools/flutter/bin/flutter analyze lib/core/audio/audio_beep_channel.dart
```

Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add hearty_app/lib/core/audio/audio_beep_channel.dart hearty_app/test/core/audio/audio_beep_channel_test.dart
git commit -m "feat: AudioBeepChannel Dart wrapper for native beep-stream muting"
```

---

## Phase 3: `VoiceNotifier` — suppress timer + release funnel

**Status:** ⬜ Not Started
**Goal:** Arm beep suppression ~800ms after the first follow-up session opens; release it through one idempotent funnel on every exit path.

**Files:**
- Modify: `hearty_app/lib/features/voice/providers/voice_provider.dart`
- Modify: `hearty_app/test/features/voice/voice_provider_test.dart`

### Tasks

- [ ] **Step 1: Add a fake beep channel + failing tests**

In `hearty_app/test/features/voice/voice_provider_test.dart`, add this fake class at the top level (after the existing `FakeSpeechToText` class) — add the import `import 'package:hearty_app/core/audio/audio_beep_channel.dart';` to the file's imports first:

```dart
class FakeBeepChannel implements AudioBeepChannel {
  int suppressCount = 0;
  int restoreCount = 0;
  @override
  Future<void> suppress() async => suppressCount++;
  @override
  Future<void> restore() async => restoreCount++;
}
```

Append these tests inside the `group('VoiceNotifier state transitions', ...)` block:

```dart
    test('first follow-up suppresses beep after the delay, dismiss restores', () async {
      final beep = FakeBeepChannel();
      final notifier = VoiceNotifier(
        sttForTesting: fakeStt,
        ttsForTesting: fakeTts,
        followUpStartDelay: Duration.zero,
        beepChannelForTesting: beep,
        beepSuppressDelay: Duration.zero,
      );
      notifier.primeForSymptomFollowUp(mealId: 'm1');
      // Orientation timer -> _beginStt -> arms the beep-suppress timer -> fires.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(beep.suppressCount, 1);
      notifier.dismiss();
      expect(beep.restoreCount, 1);
      notifier.dispose();
    });

    test('dismiss before the suppress delay never suppresses', () async {
      final beep = FakeBeepChannel();
      final notifier = VoiceNotifier(
        sttForTesting: fakeStt,
        ttsForTesting: fakeTts,
        followUpStartDelay: Duration.zero,
        beepChannelForTesting: beep,
        beepSuppressDelay: const Duration(seconds: 10),
      );
      notifier.primeForSymptomFollowUp(mealId: 'm1');
      await Future<void>.delayed(const Duration(milliseconds: 30)); // beginStt arms 10s timer
      notifier.dismiss(); // cancels it
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(beep.suppressCount, 0);
      notifier.dispose();
    });

    test('beep restore is idempotent across multiple exits', () async {
      final beep = FakeBeepChannel();
      final notifier = VoiceNotifier(
        sttForTesting: fakeStt,
        ttsForTesting: fakeTts,
        followUpStartDelay: Duration.zero,
        beepChannelForTesting: beep,
        beepSuppressDelay: Duration.zero,
      );
      notifier.primeForSymptomFollowUp(mealId: 'm1');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(beep.suppressCount, 1);
      notifier.setThinking(); // releases
      notifier.dismiss(); // releases again -> no-op
      expect(beep.restoreCount, 1);
      notifier.dispose();
    });
```

- [ ] **Step 2: Run to confirm they fail**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
/home/evan/tools/flutter/bin/flutter test test/features/voice/voice_provider_test.dart
```

Expected: FAIL — `beepChannelForTesting`/`beepSuppressDelay` are not constructor params; no suppress/restore wired.

- [ ] **Step 3: Add the import**

In `hearty_app/lib/features/voice/providers/voice_provider.dart`, add to the import block (after `import '../../../core/notifications/notification_service.dart';`):

```dart
import '../../../core/audio/audio_beep_channel.dart';
```

- [ ] **Step 4: Add constructor params + fields**

Replace the constructor and the field block (from `VoiceNotifier({` through `Timer? _followUpStartTimer;`) with:

```dart
  VoiceNotifier({
    Ref? ref,
    SpeechToText? sttForTesting,
    TtsEngine? ttsForTesting,
    Duration? followUpStartDelay,
    AudioBeepChannel? beepChannelForTesting,
    Duration? beepSuppressDelay,
  })  : _ref = ref,
        _stt = sttForTesting ?? SpeechToText(),
        _injectedTts = ttsForTesting,
        _followUpStartDelay =
            followUpStartDelay ?? const Duration(milliseconds: 2500),
        _beep = beepChannelForTesting ?? AudioBeepChannel(),
        _beepSuppressDelay =
            beepSuppressDelay ?? const Duration(milliseconds: 800),
        super(const VoiceState()) {
    _ready = _initTts();
  }

  final Ref? _ref;
  final SpeechToText _stt;
  final TtsEngine? _injectedTts;
  late TtsEngine _tts;
  late final Future<void> _ready;
  bool _sttInitialized = false;
  bool _askFollowUp = true;
  // Follow-up STT state — Android fires notListening after its own short
  // silence timeout, ignoring pauseFor. We restart up to _maxFollowUpRestarts
  // times and accumulate the transcript across sessions — but only once the
  // user has actually started speaking (see _onSttStatus), so pre-speech
  // silence does not churn through restarts (each restart plays a beep).
  bool _inFollowUpListen = false;
  int _followUpRestarts = 0;
  String _followUpAccumulated = '';
  static const int _maxFollowUpRestarts = 3;
  bool _useDictation = true; // try dictation mode first; falls back on error
  // Orientation delay before the follow-up mic opens, so the user can read the
  // question first. Cancelable via dismiss(); injectable for tests.
  final Duration _followUpStartDelay;
  Timer? _followUpStartTimer;
  // Beep suppression: let the first follow-up beep play, then mute the
  // recognizer beep streams so the restart sessions are silent. Released via
  // _releaseBeepSuppression() on every exit path so it can never leak.
  final AudioBeepChannel _beep;
  final Duration _beepSuppressDelay;
  Timer? _beepSuppressTimer;
  bool _beepSuppressed = false;
```

- [ ] **Step 5: Arm the suppress timer in `_beginStt`**

In `_beginStt`, the follow-up `micPhase` block currently reads:

```dart
    if (isFollowUp && mounted) {
      state = state.copyWith(micPhase: MicPhase.listening);
    }
```

Replace it with:

```dart
    if (isFollowUp && mounted) {
      state = state.copyWith(micPhase: MicPhase.listening);
    }
    if (isFollowUp && _followUpRestarts == 0) {
      // Let this first session's beep play, then mute the candidate streams so
      // the restart sessions' beeps are silenced. Released on any exit.
      _beepSuppressTimer?.cancel();
      _beepSuppressTimer = Timer(_beepSuppressDelay, () {
        if (mounted && state.status == VoiceStatus.awaitingFollowUp) {
          _beep.suppress();
          _beepSuppressed = true;
        }
      });
    }
```

- [ ] **Step 6: Add the release funnel and wire it into every exit path**

Add this method immediately after `_pauseFollowUpMic` (so it sits with the other follow-up helpers):

```dart
  void _releaseBeepSuppression() {
    _beepSuppressTimer?.cancel();
    if (_beepSuppressed) {
      _beep.restore();
      _beepSuppressed = false;
    }
  }
```

Now call `_releaseBeepSuppression();` as the first line of each of these:

(a) `setThinking` — replace its body's first line:
```dart
  void setThinking() {
    _releaseBeepSuppression();
    _inFollowUpListen = false;
```

(b) `_pauseFollowUpMic`:
```dart
  void _pauseFollowUpMic() {
    _releaseBeepSuppression();
    _inFollowUpListen = false;
    if (mounted) state = state.copyWith(micPhase: MicPhase.paused);
  }
```

(c) `dismiss`:
```dart
  void dismiss() {
    _releaseBeepSuppression();
    _followUpStartTimer?.cancel();
    if (_stt.isListening) _stt.stop();
    _stopTts();
    state = const VoiceState();
  }
```

(d) `_onSttError` — add it to the terminal (`else`) branch:
```dart
    } else {
      _releaseBeepSuppression();
      _autoSubmitIfPending();
    }
```

(e) `dispose`:
```dart
  void dispose() {
    _releaseBeepSuppression();
    _followUpStartTimer?.cancel();
    _stt.stop();
    _ready.then((_) => _tts.dispose());
    super.dispose();
  }
```

- [ ] **Step 7: Run the voice tests**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
/home/evan/tools/flutter/bin/flutter test test/features/voice/voice_provider_test.dart
```

Expected: PASS (all, including the three new beep tests).

- [ ] **Step 8: Analyze**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
/home/evan/tools/flutter/bin/flutter analyze lib/features/voice/providers/voice_provider.dart
```

Expected: No issues found.

- [ ] **Step 9: Commit**

```bash
git add hearty_app/lib/features/voice/providers/voice_provider.dart hearty_app/test/features/voice/voice_provider_test.dart
git commit -m "feat: suppress follow-up restart beeps (mute after first beep, release on every exit)"
```

---

## Phase 4: On-device verification (Pixel over wifi)

**Status:** ⬜ Not Started
**Goal:** Confirm on the real device that only the first beep is audible, restart beeps are silent, multi-pause answers still transcribe, and media audio is unaffected afterward.

**Files:** none (manual verification).

### Tasks

- [ ] **Step 1: Build + install over wifi**

(Wifi adb per `reference_wifi_debug.md`: device `192.168.0.159:<port>` — find the port with `adb mdns services` / `adb devices` if not connected.)

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
/home/evan/tools/flutter/bin/flutter build apk --debug --dart-define-from-file=../.env
adb -s 192.168.0.159:<port> install -r build/app/outputs/flutter-apk/app-debug.apk
```

- [ ] **Step 2: Exercise the follow-up path**

Backend up (`make api`) + reverse tunnel (`adb -s 192.168.0.159:<port> reverse tcp:8080 tcp:8080`). Log a meal, set the post-meal nudge delay to 5 min, tap the notification when it fires (or use an in-app reply that asks "how are you feeling?"). Answer **with a deliberate pause** so restart sessions occur.

- [ ] **Step 3: Confirm by ear + by stream which candidate carries the beep**

Listen: exactly **one** beep when the mic first opens, then silence through the restarts. Then confirm media audio works normally after the turn (play something).

If beeps still occur, narrow the stream: temporarily reduce `beepStreams` in `MainActivity.kt` to a single stream and re-test to learn which one the Pixel uses — but keep the full candidate set in the shipped code for cross-device coverage (note the finding in the commit message).

- [ ] **Step 4: Note the result**

Record in the PR/commit: which stream(s) carried the beep on the Pixel, and that media audio restored cleanly. No code change unless Step 3 revealed the mute didn't take (then revisit the `AudioManager` call, e.g. save/restore volume instead of `ADJUST_MUTE`).
