# Follow-Up Listening Ding-Storm Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop the post-meal follow-up flow from playing the Android listening/stop beeps several times when entered via a notification tap, by adding an orientation delay before the mic opens, only restarting the recognizer after speech has begun, and surfacing a tap-to-talk fallback.

**Architecture:** All changes are in the Flutter voice layer. A new `MicPhase` enum on `VoiceState` distinguishes the three follow-up mic visuals (`preparing` / `listening` / `paused`). `primeForSymptomFollowUp` shows the question, then opens the mic after a cancelable delay. The restart hack in `voice_provider.dart` gains a "transcript non-empty" guard so pre-speech silence no longer burns the restart budget (the source of the ding storm); when a window ends with nothing captured it goes to `paused` (tap-to-talk) instead of churning.

**Tech Stack:** Flutter, Riverpod (StateNotifier), `speech_to_text`, `dart:async` Timer.

**Spec:** `docs/superpowers/specs/2026-05-31-followup-listening-ding-fix-design.md`

**Branch note:** Per the user's decision, this lands directly on `voice-nonbinary-tts`. `voice_provider.dart` and `voice_overlay_screen.dart` already have uncommitted WIP in the working tree; committing them will necessarily bundle that WIP — this is accepted. `voice_state.dart` and the two test files are clean.

**Plan Status:** ⬜ Not Started

---

## Phase Summary

| Phase | Name | Status |
|-------|------|--------|
| 1 | `MicPhase` enum + `VoiceState.micPhase` field | ⬜ Not Started |
| 2 | Orientation delay + cancelable start timer | ⬜ Not Started |
| 3 | Restart-only-after-speech + pause/resume | ⬜ Not Started |
| 4 | Overlay: branch follow-up UI on `micPhase` | ⬜ Not Started |

---

## Phase 1: `MicPhase` enum + `VoiceState.micPhase` field

**Status:** ⬜ Not Started
**Goal:** Add an explicit mic-phase value to `VoiceState` so the overlay can tell "Getting ready…" (delay), "listening" (waveform), and "Tap to talk" (paused) apart — they would otherwise all be "mic off + empty transcript".

**Files:**
- Modify: `hearty_app/lib/features/voice/models/voice_state.dart`
- Modify: `hearty_app/test/features/voice/voice_provider_test.dart`

### Tasks

- [ ] **Step 1: Write the failing test**

Append inside the `group('VoiceNotifier state transitions', ...)` block in `hearty_app/test/features/voice/voice_provider_test.dart`:

```dart
    test('initial state has MicPhase.none', () {
      expect(container.read(voiceProvider).micPhase, MicPhase.none);
    });

    test('copyWith updates micPhase', () {
      const s = VoiceState();
      expect(s.copyWith(micPhase: MicPhase.listening).micPhase, MicPhase.listening);
      // unspecified copyWith preserves existing value
      expect(s.copyWith(micPhase: MicPhase.paused).copyWith(transcript: 'x').micPhase,
          MicPhase.paused);
    });
```

- [ ] **Step 2: Run to confirm it fails**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
/home/evan/tools/flutter/bin/flutter test test/features/voice/voice_provider_test.dart
```

Expected: FAIL — `MicPhase` undefined / `micPhase` getter missing.

- [ ] **Step 3: Add the enum and field**

Replace the entire contents of `hearty_app/lib/features/voice/models/voice_state.dart` with:

```dart
enum VoiceStatus { idle, listening, thinking, responding, awaitingFollowUp }

/// Sub-phase of the follow-up microphone, used to drive the overlay between
/// the orientation delay, the active listening session, and the idle
/// (tap-to-talk) state. `none` means not in the follow-up mic flow.
enum MicPhase { none, preparing, listening, paused }

class VoiceState {
  final VoiceStatus status;
  final String transcript;
  final String response;
  final String? pendingMealId;
  final List<Map<String, String>> history;
  final MicPhase micPhase;

  const VoiceState({
    this.status = VoiceStatus.idle,
    this.transcript = '',
    this.response = '',
    this.pendingMealId,
    this.history = const [],
    this.micPhase = MicPhase.none,
  });

  VoiceState copyWith({
    VoiceStatus? status,
    String? transcript,
    String? response,
    String? pendingMealId,
    List<Map<String, String>>? history,
    MicPhase? micPhase,
  }) =>
      VoiceState(
        status: status ?? this.status,
        transcript: transcript ?? this.transcript,
        response: response ?? this.response,
        pendingMealId: pendingMealId ?? this.pendingMealId,
        history: history ?? this.history,
        micPhase: micPhase ?? this.micPhase,
      );
}
```

- [ ] **Step 4: Run test to confirm it passes**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
/home/evan/tools/flutter/bin/flutter test test/features/voice/voice_provider_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add hearty_app/lib/features/voice/models/voice_state.dart hearty_app/test/features/voice/voice_provider_test.dart
git commit -m "feat: add MicPhase to VoiceState for follow-up mic visuals"
```

---

## Phase 2: Orientation delay + cancelable start timer

**Status:** ⬜ Not Started
**Goal:** On the notification follow-up path, show the question and wait a tunable delay before opening the mic, so Android's silence timeout doesn't fire during orientation. The delay is cancelable (dismiss during it = no mic) and injectable (tests use zero).

**Files:**
- Modify: `hearty_app/lib/features/voice/providers/voice_provider.dart`
- Modify: `hearty_app/test/features/voice/voice_provider_test.dart`

### Tasks

- [ ] **Step 1: Enhance the fake STT to count listens and capture the status callback**

In `hearty_app/test/features/voice/voice_provider_test.dart`, replace the `FakeSpeechToText` class with:

```dart
// Fake SpeechToText for testing
class FakeSpeechToText extends Fake implements SpeechToText {
  bool _isListening = false;
  int listenCount = 0;
  void Function(String)? statusCallback;

  @override
  bool get isListening => _isListening;

  @override
  bool get isNotListening => !_isListening;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #initialize) {
      statusCallback =
          invocation.namedArguments[#onStatus] as void Function(String)?;
      return Future<bool>.value(true);
    }
    if (invocation.memberName == #listen) {
      listenCount++;
      _isListening = true;
      return Future.value();
    }
    if (invocation.memberName == #stop) {
      _isListening = false;
      return Future.value();
    }
    if (invocation.memberName == #cancel) {
      _isListening = false;
      return Future.value();
    }
    return super.noSuchMethod(invocation);
  }
}
```

- [ ] **Step 2: Write the failing tests**

Append inside the `group('VoiceNotifier state transitions', ...)` block:

```dart
    test('primeForSymptomFollowUp does not open mic synchronously; opens after delay', () async {
      final notifier = VoiceNotifier(
        sttForTesting: fakeStt,
        ttsForTesting: fakeTts,
        followUpStartDelay: Duration.zero,
      );
      notifier.primeForSymptomFollowUp(mealId: 'm1');
      // Mic not opened yet; we are in the orientation phase.
      expect(fakeStt.listenCount, 0);
      expect(notifier.state.micPhase, MicPhase.preparing);
      expect(notifier.state.status, VoiceStatus.awaitingFollowUp);
      // Let the zero-delay timer fire.
      await Future<void>.delayed(Duration.zero);
      expect(fakeStt.listenCount, 1);
      expect(notifier.state.micPhase, MicPhase.listening);
      notifier.dispose();
    });

    test('dismiss during the orientation delay cancels the mic start', () async {
      final notifier = VoiceNotifier(
        sttForTesting: fakeStt,
        ttsForTesting: fakeTts,
        followUpStartDelay: const Duration(seconds: 10),
      );
      notifier.primeForSymptomFollowUp(mealId: 'm1');
      notifier.dismiss();
      await Future<void>.delayed(Duration.zero);
      expect(fakeStt.listenCount, 0);
      expect(notifier.state.status, VoiceStatus.idle);
      notifier.dispose();
    });
```

- [ ] **Step 3: Run to confirm they fail**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
/home/evan/tools/flutter/bin/flutter test test/features/voice/voice_provider_test.dart
```

Expected: FAIL — `followUpStartDelay` is not a constructor parameter; mic opens synchronously; `micPhase` not set.

- [ ] **Step 4: Add the import, constructor param, timer field, and delay logic**

In `hearty_app/lib/features/voice/providers/voice_provider.dart`:

(a) Add the `dart:async` import at the top of the import block (after the existing imports, before `const _uuid`):

```dart
import 'dart:async';
```

(b) Replace the constructor and the field declarations down to `_useDictation` with:

```dart
  VoiceNotifier({
    Ref? ref,
    SpeechToText? sttForTesting,
    TtsEngine? ttsForTesting,
    Duration? followUpStartDelay,
  })  : _ref = ref,
        _stt = sttForTesting ?? SpeechToText(),
        _injectedTts = ttsForTesting,
        _followUpStartDelay =
            followUpStartDelay ?? const Duration(milliseconds: 2500),
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
```

(c) Replace the body of `primeForSymptomFollowUp` (the `state = VoiceState(...)` assignment and the trailing `_beginStt(isFollowUp: true);`) so it sets `preparing` and schedules the delayed start instead of starting immediately:

```dart
  void primeForSymptomFollowUp({String? mealId}) {
    // Stop any in-progress audio from a previous session. Calling
    // _stt.listen() while already listening silently fails on Android.
    if (_stt.isListening) _stt.stop();
    _stopTts();

    // Reset follow-up STT accumulators. If a previous session hit the
    // max-restart limit, the counter would stay at 3 and prevent retries.
    _inFollowUpListen = false;
    _followUpRestarts = 0;
    _followUpAccumulated = '';
    _useDictation = true;

    const question =
        'How are you feeling after your last meal? Let me know about any discomfort — you can rate it 1–10, or just say you\'re feeling good.';
    state = VoiceState(
      status: VoiceStatus.awaitingFollowUp,
      response: question,
      pendingMealId: mealId,
      micPhase: MicPhase.preparing,
      history: const [
        {'role': 'assistant', 'content': question}
      ],
    );

    // Wait a beat so the user can orient before the mic opens — otherwise
    // Android times out on the orientation silence and the restart loop
    // plays a storm of beeps.
    _followUpStartTimer?.cancel();
    _followUpStartTimer = Timer(_followUpStartDelay, () {
      if (mounted && state.status == VoiceStatus.awaitingFollowUp) {
        _beginStt(isFollowUp: true);
      }
    });
  }
```

(d) In `_beginStt`, set `micPhase: MicPhase.listening` for follow-up sessions right before calling `_stt.listen`. Replace the start of `_beginStt` up to the `await _stt.listen(` call:

```dart
  Future<void> _beginStt({bool isFollowUp = false}) async {
    _inFollowUpListen = isFollowUp;
    if (!await _ensureSttInitialized()) return;
    if (isFollowUp && mounted) {
      state = state.copyWith(micPhase: MicPhase.listening);
    }
    final mode = isFollowUp && _useDictation
        ? ListenMode.dictation
        : ListenMode.confirmation;
    await _stt.listen(
```

(e) In `dismiss()`, cancel the pending start timer. Replace `dismiss()`:

```dart
  void dismiss() {
    _followUpStartTimer?.cancel();
    if (_stt.isListening) _stt.stop();
    _stopTts();
    state = const VoiceState();
  }
```

(f) The in-app conversation path (`setAwaitingFollowUp` → `_beginFollowUpStt`, which has its own 350ms teardown delay) must also reflect `preparing` so the overlay (Phase 4) doesn't show a stale phase during that window. In `setAwaitingFollowUp`, add `micPhase: MicPhase.preparing` to its `copyWith`. Replace the `state = state.copyWith(...)` call inside `setAwaitingFollowUp` with:

```dart
    state = state.copyWith(
      status: VoiceStatus.awaitingFollowUp,
      history: updatedHistory,
      transcript: '',
      micPhase: MicPhase.preparing,
    );
```

- [ ] **Step 5: Run tests to confirm they pass**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
/home/evan/tools/flutter/bin/flutter test test/features/voice/voice_provider_test.dart
```

Expected: PASS (all tests in the file).

- [ ] **Step 6: Analyze**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
/home/evan/tools/flutter/bin/flutter analyze lib/features/voice/providers/voice_provider.dart
```

Expected: No issues found.

- [ ] **Step 7: Commit**

```bash
git add hearty_app/lib/features/voice/providers/voice_provider.dart hearty_app/test/features/voice/voice_provider_test.dart
git commit -m "feat: orientation delay before follow-up mic opens (cancelable)"
```

---

## Phase 3: Restart-only-after-speech + pause/resume

**Status:** ⬜ Not Started
**Goal:** Stop burning the restart budget (and beeping) on pre-speech silence. Restart only when a transcript has been captured; otherwise go to `paused` (tap-to-talk). Add `resumeFollowUpListening()` for the tap-to-talk button.

**Files:**
- Modify: `hearty_app/lib/features/voice/providers/voice_provider.dart`
- Modify: `hearty_app/test/features/voice/voice_provider_test.dart`

### Tasks

- [ ] **Step 1: Write the failing tests**

Append inside the `group('VoiceNotifier state transitions', ...)` block:

```dart
    test('premature notListening with empty transcript does NOT restart; goes paused', () async {
      final notifier = VoiceNotifier(
        sttForTesting: fakeStt,
        ttsForTesting: fakeTts,
        followUpStartDelay: Duration.zero,
      );
      notifier.primeForSymptomFollowUp(mealId: 'm1');
      await Future<void>.delayed(Duration.zero); // mic opens (listenCount == 1)
      expect(fakeStt.listenCount, 1);

      // Android ends the session before the user said anything.
      fakeStt.statusCallback!(SpeechToText.notListeningStatus);
      await Future<void>.delayed(Duration.zero);

      expect(fakeStt.listenCount, 1); // no restart
      expect(notifier.state.micPhase, MicPhase.paused);
      notifier.dispose();
    });

    test('premature notListening with non-empty transcript DOES restart', () async {
      final notifier = VoiceNotifier(
        sttForTesting: fakeStt,
        ttsForTesting: fakeTts,
        followUpStartDelay: Duration.zero,
      );
      notifier.primeForSymptomFollowUp(mealId: 'm1');
      await Future<void>.delayed(Duration.zero); // listenCount == 1
      notifier.setTranscript('I feel a bit bloated');

      fakeStt.statusCallback!(SpeechToText.notListeningStatus);
      await Future<void>.delayed(Duration.zero);

      expect(fakeStt.listenCount, 2); // restarted to let them finish
      notifier.dispose();
    });

    test('resumeFollowUpListening opens a session and sets listening', () async {
      final notifier = VoiceNotifier(
        sttForTesting: fakeStt,
        ttsForTesting: fakeTts,
        followUpStartDelay: Duration.zero,
      );
      notifier.primeForSymptomFollowUp(mealId: 'm1');
      await Future<void>.delayed(Duration.zero);
      fakeStt.statusCallback!(SpeechToText.notListeningStatus); // -> paused
      expect(notifier.state.micPhase, MicPhase.paused);

      notifier.resumeFollowUpListening();
      await Future<void>.delayed(Duration.zero);
      expect(fakeStt.listenCount, 2);
      expect(notifier.state.micPhase, MicPhase.listening);
      notifier.dispose();
    });
```

- [ ] **Step 2: Run to confirm they fail**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
/home/evan/tools/flutter/bin/flutter test test/features/voice/voice_provider_test.dart
```

Expected: FAIL — empty-transcript case currently restarts (listenCount becomes 2) and never sets `paused`; `resumeFollowUpListening` is undefined.

- [ ] **Step 3: Add the speech guard, pause helper, and resume method**

In `hearty_app/lib/features/voice/providers/voice_provider.dart`:

(a) Replace `_onSttStatus` with:

```dart
  void _onSttStatus(String status) {
    if (status == SpeechToText.notListeningStatus || status == SpeechToText.doneStatus) {
      if (_inFollowUpListen &&
          state.transcript.isNotEmpty &&
          _followUpRestarts < _maxFollowUpRestarts &&
          mounted &&
          state.status == VoiceStatus.awaitingFollowUp) {
        // The user started talking and Android ended the session early —
        // restart so they can finish. Accumulate what was captured so far.
        _followUpAccumulated = state.transcript;
        _followUpRestarts++;
        _beginStt(isFollowUp: true);
        return;
      }
      if (_inFollowUpListen &&
          state.transcript.isEmpty &&
          mounted &&
          state.status == VoiceStatus.awaitingFollowUp) {
        // Nothing captured yet — don't churn through restarts (each restart
        // beeps). Go idle and let the user tap to talk when ready.
        _pauseFollowUpMic();
        return;
      }
      _autoSubmitIfPending();
    }
  }
```

(b) Add the `_pauseFollowUpMic` helper and the public `resumeFollowUpListening` method immediately after `_onSttStatus`:

```dart
  void _pauseFollowUpMic() {
    _inFollowUpListen = false;
    if (mounted) state = state.copyWith(micPhase: MicPhase.paused);
  }

  /// Re-opens one follow-up listen session — wired to the overlay's
  /// "Tap to talk" button after the mic went idle on pre-speech silence.
  void resumeFollowUpListening() {
    if (state.status != VoiceStatus.awaitingFollowUp) return;
    _beginStt(isFollowUp: true);
  }
```

(c) In the `onResult` callback inside `_beginStt`, guard the `finalResult` restart the same way. Replace the `if (result.finalResult) { ... }` block with:

```dart
        if (result.finalResult) {
          if (_inFollowUpListen &&
              state.transcript.isNotEmpty &&
              _followUpRestarts < _maxFollowUpRestarts) {
            // Android fired finalResult early — save what we have and restart.
            _followUpAccumulated = state.transcript;
            _followUpRestarts++;
            _inFollowUpListen = false;
            Future.delayed(const Duration(milliseconds: 200), () {
              if (mounted && state.status == VoiceStatus.awaitingFollowUp) {
                _beginStt(isFollowUp: true);
              }
            });
          } else if (_inFollowUpListen && state.transcript.isEmpty) {
            // finalResult with nothing captured — go idle (tap-to-talk).
            _pauseFollowUpMic();
          } else {
            setThinking();
          }
        }
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
/home/evan/tools/flutter/bin/flutter test test/features/voice/voice_provider_test.dart
```

Expected: PASS (all tests).

- [ ] **Step 5: Analyze**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
/home/evan/tools/flutter/bin/flutter analyze lib/features/voice/providers/voice_provider.dart
```

Expected: No issues found.

- [ ] **Step 6: Commit**

```bash
git add hearty_app/lib/features/voice/providers/voice_provider.dart hearty_app/test/features/voice/voice_provider_test.dart
git commit -m "feat: restart follow-up mic only after speech; pause to tap-to-talk otherwise"
```

---

## Phase 4: Overlay — branch follow-up UI on `micPhase`

**Status:** ⬜ Not Started
**Goal:** Render the three follow-up phases distinctly: `preparing` → "Getting ready…" (no active waveform), `listening` → waveform (as today), `paused` → a "Tap to talk" mic button wired to `resumeFollowUpListening()`.

**Files:**
- Modify: `hearty_app/lib/features/voice/screens/voice_overlay_screen.dart`
- Modify: `hearty_app/test/features/voice/voice_overlay_screen_test.dart`

### Tasks

- [ ] **Step 1: Write the failing widget tests**

Append inside the `group('VoiceOverlayScreen', ...)` block in `hearty_app/test/features/voice/voice_overlay_screen_test.dart`:

```dart
    testWidgets('preparing phase shows Getting ready hint, no waveform', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            voiceProvider.overrideWith(
              (_) => _StubVoiceNotifier(const VoiceState(
                status: VoiceStatus.awaitingFollowUp,
                response: 'How are you feeling?',
                micPhase: MicPhase.preparing,
              )),
            ),
          ],
          child: const MaterialApp(home: VoiceOverlayScreen()),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('getting_ready_hint')), findsOneWidget);
      expect(find.byKey(const Key('waveform_animation')), findsNothing);
    });

    testWidgets('paused phase shows Tap to talk button', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            voiceProvider.overrideWith(
              (_) => _StubVoiceNotifier(const VoiceState(
                status: VoiceStatus.awaitingFollowUp,
                response: 'How are you feeling?',
                micPhase: MicPhase.paused,
              )),
            ),
          ],
          child: const MaterialApp(home: VoiceOverlayScreen()),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('tap_to_talk_button')), findsOneWidget);
      expect(find.byKey(const Key('waveform_animation')), findsNothing);
    });

    testWidgets('listening phase shows waveform', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            voiceProvider.overrideWith(
              (_) => _StubVoiceNotifier(const VoiceState(
                status: VoiceStatus.awaitingFollowUp,
                response: 'How are you feeling?',
                micPhase: MicPhase.listening,
              )),
            ),
          ],
          child: const MaterialApp(home: VoiceOverlayScreen()),
        ),
      );
      await tester.pump();
      expect(find.byKey(const Key('waveform_animation')), findsOneWidget);
      expect(find.byKey(const Key('getting_ready_hint')), findsNothing);
      expect(find.byKey(const Key('tap_to_talk_button')), findsNothing);
    });
```

- [ ] **Step 2: Run to confirm they fail**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
/home/evan/tools/flutter/bin/flutter test test/features/voice/voice_overlay_screen_test.dart
```

Expected: FAIL — the keyed widgets don't exist; `awaitingFollowUp` always renders the waveform today.

- [ ] **Step 3: Branch the animation slot on `micPhase`**

In `hearty_app/lib/features/voice/screens/voice_overlay_screen.dart`, replace `_buildAnimation` so the follow-up animation slot reflects `micPhase`. The method currently takes a `VoiceStatus`; change it to take the full `VoiceState` and update its call site.

Replace the call site in `build` (currently `Center(child: _buildAnimation(voiceState.status))`) with:

```dart
                Center(child: _buildAnimation(voiceState)),
```

Replace the `_buildAnimation` method with:

```dart
  Widget _buildAnimation(VoiceState state) {
    switch (state.status) {
      case VoiceStatus.listening:
        return const WaveformAnimation();
      case VoiceStatus.awaitingFollowUp:
        switch (state.micPhase) {
          case MicPhase.listening:
            return const WaveformAnimation();
          case MicPhase.paused:
            return IconButton(
              key: const Key('tap_to_talk_button'),
              iconSize: 56,
              icon: const Icon(Icons.mic_none, color: Colors.white),
              tooltip: 'Tap to talk',
              onPressed: () =>
                  ref.read(voiceProvider.notifier).resumeFollowUpListening(),
            );
          case MicPhase.preparing:
          case MicPhase.none:
            return const SizedBox(
              key: Key('getting_ready_hint'),
              height: 56,
              width: 56,
              child: CircularProgressIndicator(color: Colors.white70),
            );
        }
      case VoiceStatus.thinking:
        return const ThinkingAnimation();
      case VoiceStatus.responding:
        return const Icon(Icons.volume_up, color: Colors.white, size: 48);
      case VoiceStatus.idle:
        return const SizedBox.shrink();
    }
  }
```

- [ ] **Step 4: Add a "Getting ready…" caption under the question during preparing**

In `_buildFollowUpDisplay`, add a caption when `state.micPhase == MicPhase.preparing`. Replace the `if (hasTranscript) ...` trailing section by inserting the caption before it — i.e. replace the whole `_buildFollowUpDisplay` return Column children list with:

```dart
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.response.isNotEmpty)
          Text(
            state.response,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 16,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        if (state.micPhase == MicPhase.preparing) ...[
          const SizedBox(height: 12),
          Text(
            'Getting ready…',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
          ),
        ],
        if (state.micPhase == MicPhase.paused) ...[
          const SizedBox(height: 12),
          Text(
            'Tap the mic when you’re ready',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
          ),
        ],
        if (hasTranscript) ...[
          const SizedBox(height: 12),
          Text(
            state.transcript,
            style: const TextStyle(color: Colors.white, fontSize: 18, height: 1.5),
            textAlign: TextAlign.center,
          ),
          _buildSubmitRow(canRetry: false),
        ],
      ],
    );
```

- [ ] **Step 5: Run tests to confirm they pass**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
/home/evan/tools/flutter/bin/flutter test test/features/voice/voice_overlay_screen_test.dart
```

Expected: PASS.

- [ ] **Step 6: Analyze**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
/home/evan/tools/flutter/bin/flutter analyze lib/features/voice/screens/voice_overlay_screen.dart
```

Expected: No issues found.

- [ ] **Step 7: Run the full voice test suite**

```bash
cd /home/evan/projects/food-journal-assistant/hearty_app
/home/evan/tools/flutter/bin/flutter test test/features/voice/
```

Expected: all pass.

- [ ] **Step 8: Commit**

```bash
git add hearty_app/lib/features/voice/screens/voice_overlay_screen.dart hearty_app/test/features/voice/voice_overlay_screen_test.dart
git commit -m "feat: follow-up overlay shows getting-ready / waveform / tap-to-talk by mic phase"
```

- [ ] **Step 9: On-device tuning (manual — not unit-testable)**

After this lands, on the dev phone tap a real follow-up notification and confirm the ding storm is gone and the pause feels natural; tune `_followUpStartDelay` (default 2.5s) if needed. The native beeps and Android's real silence timing can only be verified on-device — the unit tests cover the restart/phase logic, not the audio.
