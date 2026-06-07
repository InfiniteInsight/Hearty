# Voice Rebuild — Phase B: On-Device Engine + Lifecycle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Android `SpeechRecognizer` with on-device sherpa-onnx streaming ASR running on a **background isolate**, fronted by a trailing-silence auto-submit, and rebuild the voice state machine so Flows 1 (wake-word dictation) and 2 (conversation follow-up) keep the mic open through pauses and never truncate.

**Architecture:** A new `core/stt` layer: an `SttEngine` interface, an `OnDeviceSttEngine` that owns a `record` PCM16 mic stream and forwards audio to a long-lived ASR isolate (sherpa `OnlineRecognizer`, endpointing off) while a `SilenceDetector` drives auto-submit. `VoiceNotifier` is refactored to drive this engine via a clean state machine (listening → submit → thinking → responding → awaitingFollowUp), with half-duplex TTS gating, one ding, and the wake-word mic handoff. The pure/logic units are TDD'd with a `FakeSttEngine`; the native isolate/mic/model integration is device-verified.

**Tech Stack:** Flutter/Dart, `sherpa_onnx` (already a dep), `record` (added on the spike branch — re-add here), dart:isolate, dart:ffi (inside sherpa), flutter_test.

**Spec:** `docs/superpowers/specs/2026-06-07-voice-lifecycle-rebuild-design.md`. Prereq: Phase A merged. Follow-ons: Plan C (cloud + `/api/transcribe` + online/offline selection), Plan D (Flow 3 reliability, settings UI, model download, remove `speech_to_text`).

**Scope guards for Phase B:**
- On-device model is read from the device files dir `asr-model` (the 122 MB int8 model). **Bundling/auto-download is deferred to Plan D** — for B, the model is pushed via `adb` (as in the spike) and a missing model surfaces a clear error + the text-input fallback.
- Cloud and the online/offline selector are **Plan C**. Phase B always uses on-device.
- Settings UI is **Plan D**; Phase B reads auto-submit config from constants/defaults (auto-submit on, 2.5 s).
- **All three flows migrate to `SttEngine` in B** — this is unavoidable, not a choice. Every flow funnels through the single shared `_beginStt({isFollowUp})` capture method (`startListening`→`_beginStt()`, `resumeFollowUpListening`/`_beginFollowUpStt`/`primeForSymptomFollowUp` timer/TTS-completion→`_beginStt(isFollowUp:true)`). Replacing `_beginStt` with `_openSession` rewires all of them at once. What **defers to Plan D** is only Flow 3's *reliability polish* (ambient-noise rejection, the notification-spoken-question setting, tap-to-confirm-only default, model auto-download). The capture path itself changes for Flow 3 in B along with the rest.

---

## File structure

| File | Responsibility |
|---|---|
| `lib/core/stt/stt_engine.dart` | `SttEngine` abstract interface + `SttResult` + `SttPhase` |
| `lib/core/stt/silence_detector.dart` | trailing-silence → auto-submit decision (pure, deterministic) |
| `lib/core/stt/asr_isolate.dart` | long-lived ASR isolate: message protocol + sherpa decode loop |
| `lib/core/stt/on_device_stt_engine.dart` | `record` mic + ASR isolate + silence detector → `SttEngine` |
| `lib/core/stt/asr_model_locator.dart` | resolves on-device model dir; reports missing |
| `lib/features/voice/providers/voice_provider.dart` | refactor `VoiceNotifier` to drive `SttEngine` (new state machine) |
| `test/core/stt/silence_detector_test.dart` | unit tests for the detector |
| `test/core/stt/fake_stt_engine.dart` | `FakeSttEngine` test double |
| `test/features/voice/voice_provider_test.dart` | extend: new state machine via `FakeSttEngine` |

---

## P0 — Isolate ASR proof (DEVICE GATE — must pass before P1 native wiring)

Goal: prove sherpa `OnlineRecognizer` loads and decodes a live mic stream **on a background isolate with no ANR** on the Pixel 4a. The spike proved accuracy/real-time but decoded on the UI thread (ANR). This proves the isolate boundary.

### Task B0.1: ASR isolate entrypoint + message protocol

**Files:**
- Create: `hearty_app/lib/core/stt/asr_isolate.dart`

- [ ] **Step 1: Write the isolate** (no unit test — FFI-in-isolate is device-verified in B0.2)

```dart
import 'dart:isolate';
import 'dart:typed_data';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// Messages UI->isolate: ['init', encoderPath, decoderPath, joinerPath, tokensPath, numThreads]
///                       ['pcm', Float32List]
///                       ['finish']  (flush + return final, keep recognizer warm)
///                       ['dispose']
/// Messages isolate->UI: ['ready']                      (init done)
///                       ['partial', String]            (live hypothesis)
///                       ['final', String]              (after 'finish')
///                       ['error', String]
class AsrIsolate {
  /// Entry point. [mainSendPort] receives the isolate's SendPort first, then
  /// the messages above.
  static void entry(SendPort mainSendPort) {
    final port = ReceivePort();
    mainSendPort.send(port.sendPort);

    sherpa.OnlineRecognizer? recognizer;
    sherpa.OnlineStream? stream;

    port.listen((msg) {
      final m = msg as List;
      switch (m[0] as String) {
        case 'init':
          try {
            sherpa.initBindings();
            recognizer = sherpa.OnlineRecognizer(sherpa.OnlineRecognizerConfig(
              model: sherpa.OnlineModelConfig(
                transducer: sherpa.OnlineTransducerModelConfig(
                  encoder: m[1] as String,
                  decoder: m[2] as String,
                  joiner: m[3] as String,
                ),
                tokens: m[4] as String,
                numThreads: m[5] as int,
                debug: false,
              ),
              enableEndpoint: false, // WE decide turn-end (silence detector)
            ));
            stream = recognizer!.createStream();
            mainSendPort.send(['ready']);
          } catch (e) {
            mainSendPort.send(['error', 'init: $e']);
          }
          break;
        case 'pcm':
          final r = recognizer, s = stream;
          if (r == null || s == null) break;
          try {
            s.acceptWaveform(samples: m[1] as Float32List, sampleRate: 16000);
            while (r.isReady(s)) {
              r.decode(s);
            }
            mainSendPort.send(['partial', r.getResult(s).text]);
          } catch (e) {
            mainSendPort.send(['error', 'pcm: $e']);
          }
          break;
        case 'finish':
          final r = recognizer, s = stream;
          if (r == null || s == null) {
            mainSendPort.send(['final', '']);
            break;
          }
          try {
            final text = r.getResult(s).text;
            r.reset(s); // ready for the next turn; recognizer stays warm
            mainSendPort.send(['final', text]);
          } catch (e) {
            mainSendPort.send(['error', 'finish: $e']);
          }
          break;
        case 'dispose':
          stream?.free();
          recognizer?.free();
          recognizer = null;
          stream = null;
          break;
      }
    });
  }
}
```

- [ ] **Step 2: Analyze**

Run: `cd hearty_app && flutter analyze lib/core/stt/asr_isolate.dart`
Expected: clean (sherpa types resolve).

- [ ] **Step 3: Commit**

```bash
git add hearty_app/lib/core/stt/asr_isolate.dart
git commit -m "feat(stt): ASR isolate entrypoint + message protocol (P0)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task B0.2: Device PoC — drive the isolate from the spike screen, verify no ANR

> Reuse the spike screen on `spike/sherpa-streaming-asr` as the harness, OR add a temporary debug button on `voice-lifecycle-rebuild`. The point is a **device run**, not a unit test.

- [ ] **Step 1: Minimal driver** — spawn the isolate, push the model paths (use the already-pushed `/sdcard/Android/data/com.hearty.app/files/asr-model` 122 MB model), stream `record` PCM in, render partials.

```dart
// Sketch (temporary, in a debug screen):
final rx = ReceivePort();
await Isolate.spawn(AsrIsolate.entry, rx.sendPort);
final SendPort tx = await rx.first as SendPort; // first message is the isolate's port
// then listen rx for ['ready'|'partial'|'final'|'error'], send ['init', ...paths..., 4]
// on each record PCM chunk: tx.send(['pcm', pcm16ToFloat32(bytes)])
// on stop: tx.send(['finish'])
```

- [ ] **Step 2: DEVICE VERIFY (gate).** `make run`, speak the spike phrases, confirm:
  - **No ANR** ("isn't responding") at model load or during decode.
  - Live partials render; final transcript matches the spike's 122 MB accuracy.
  - UI stays responsive (scroll/tap) while speaking.

  **If ANR persists:** the isolate boundary isn't the issue — STOP and reassess (model load time, message volume, or main-isolate work elsewhere). Do not proceed to P1 until this gate passes.

- [ ] **Step 3: Remove the temporary driver** (no commit needed if it was never committed; otherwise revert it). The proven isolate code (`asr_isolate.dart`) stays.

---

## P1 — Abstraction, silence detector, engine, and state machine

### Task B1.1: `SttEngine` interface + `SttResult`

**Files:**
- Create: `hearty_app/lib/core/stt/stt_engine.dart`
- Create: `hearty_app/test/core/stt/fake_stt_engine.dart`

- [ ] **Step 1: Write the interface**

```dart
import 'dart:async';

/// Outcome of a finished STT turn.
class SttResult {
  const SttResult({required this.transcript, this.ok = true, this.error});
  final String transcript;
  final bool ok;
  final String? error;
}

/// Engine-agnostic streaming speech-to-text for one capture session.
abstract class SttEngine {
  /// Begin capturing. Partials (if any) arrive on [partials]. If
  /// [onAutoSubmit] is provided, the engine calls it when its silence policy
  /// says the turn is over (the caller then calls [stop]); pass null to disable
  /// auto-submit (manual/tap-to-confirm only).
  Future<void> start({void Function()? onAutoSubmit});

  /// Live interim transcript ('' empties allowed; never null).
  Stream<String> get partials;

  /// Stop capturing and return the final transcript.
  Future<SttResult> stop();

  /// Release all resources (mic, isolate). Safe to call repeatedly.
  Future<void> dispose();
}
```

- [ ] **Step 2: Write the fake** (used by state-machine tests)

```dart
import 'dart:async';
import 'package:hearty_app/core/stt/stt_engine.dart';

class FakeSttEngine implements SttEngine {
  final _partials = StreamController<String>.broadcast();
  String nextTranscript = '';
  bool started = false;
  int startCount = 0;
  void Function()? autoSubmit;

  @override
  Future<void> start({void Function()? onAutoSubmit}) async {
    started = true;
    startCount++;
    autoSubmit = onAutoSubmit;
  }

  /// Test helper: push a live partial.
  void emitPartial(String text) => _partials.add(text);

  /// Test helper: simulate the engine's silence policy firing.
  void fireAutoSubmit() => autoSubmit?.call();

  @override
  Stream<String> get partials => _partials.stream;

  @override
  Future<SttResult> stop() async {
    started = false;
    return SttResult(transcript: nextTranscript);
  }

  @override
  Future<void> dispose() async {
    await _partials.close();
  }
}
```

- [ ] **Step 3: Analyze + commit**

Run: `cd hearty_app && flutter analyze lib/core/stt/stt_engine.dart test/core/stt/fake_stt_engine.dart`
Expected: clean.

```bash
git add hearty_app/lib/core/stt/stt_engine.dart hearty_app/test/core/stt/fake_stt_engine.dart
git commit -m "feat(stt): SttEngine interface + SttResult + FakeSttEngine

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task B1.2: `SilenceDetector` (drives auto-submit) — TDD

**Files:**
- Create: `hearty_app/lib/core/stt/silence_detector.dart`
- Test: `hearty_app/test/core/stt/silence_detector_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/stt/silence_detector.dart';

Float32List _tone(int samples, double amp) =>
    Float32List.fromList(List.filled(samples, amp));

void main() {
  group('SilenceDetector', () {
    test('does not fire on pre-speech silence', () {
      final d = SilenceDetector(sampleRate: 16000, silenceSeconds: 2.5);
      // 5s of silence before any speech → never fires
      for (var i = 0; i < 50; i++) {
        expect(d.addPcm(_tone(1600, 0.0)), isFalse); // 0.1s chunks
      }
    });

    test('fires after trailing silence once speech has occurred', () {
      final d = SilenceDetector(sampleRate: 16000, silenceSeconds: 2.5);
      // speech
      expect(d.addPcm(_tone(1600, 0.3)), isFalse);
      // 2.4s silence → not yet
      for (var i = 0; i < 24; i++) {
        expect(d.addPcm(_tone(1600, 0.0)), isFalse);
      }
      // crossing 2.5s → fires
      expect(d.addPcm(_tone(1600, 0.0)), isTrue);
    });

    test('resets trailing silence when speech resumes', () {
      final d = SilenceDetector(sampleRate: 16000, silenceSeconds: 2.5);
      d.addPcm(_tone(1600, 0.3));
      for (var i = 0; i < 20; i++) {
        d.addPcm(_tone(1600, 0.0)); // 2.0s silence
      }
      d.addPcm(_tone(1600, 0.3)); // speech again → reset
      for (var i = 0; i < 24; i++) {
        expect(d.addPcm(_tone(1600, 0.0)), isFalse); // 2.4s
      }
      expect(d.addPcm(_tone(1600, 0.0)), isTrue); // 2.5s from the reset
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty_app && flutter test test/core/stt/silence_detector_test.dart`
Expected: FAIL — `SilenceDetector` undefined.

- [ ] **Step 3: Implement**

```dart
import 'dart:math' as math;
import 'dart:typed_data';

/// Decides when a turn should auto-submit: fires once trailing silence (after
/// speech has started) reaches [silenceSeconds]. Deterministic — duration is
/// derived from sample counts, not wall-clock, so it is unit-testable.
class SilenceDetector {
  SilenceDetector({
    required this.sampleRate,
    required this.silenceSeconds,
    this.rmsThreshold = 0.015,
  });

  final int sampleRate;
  final double silenceSeconds;
  final double rmsThreshold;

  bool _spoke = false;
  double _trailingSilence = 0;

  /// Feed a PCM chunk (Float32, -1..1). Returns true exactly when the turn
  /// should auto-submit. After it returns true the caller should stop feeding.
  bool addPcm(Float32List samples) {
    if (samples.isEmpty) return false;
    final seconds = samples.length / sampleRate;
    if (_rms(samples) >= rmsThreshold) {
      _spoke = true;
      _trailingSilence = 0;
      return false;
    }
    if (!_spoke) return false; // ignore pre-speech silence
    _trailingSilence += seconds;
    return _trailingSilence >= silenceSeconds;
  }

  void reset() {
    _spoke = false;
    _trailingSilence = 0;
  }

  static double _rms(Float32List s) {
    var sum = 0.0;
    for (final v in s) {
      sum += v * v;
    }
    return math.sqrt(sum / s.length);
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd hearty_app && flutter test test/core/stt/silence_detector_test.dart`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add hearty_app/lib/core/stt/silence_detector.dart hearty_app/test/core/stt/silence_detector_test.dart
git commit -m "feat(stt): trailing-silence detector for auto-submit

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task B1.3: `AsrModelLocator`

**Files:**
- Create: `hearty_app/lib/core/stt/asr_model_locator.dart`

- [ ] **Step 1: Implement** (download deferred to Plan D; B reads the pushed dir)

```dart
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class AsrModelPaths {
  const AsrModelPaths(this.encoder, this.decoder, this.joiner, this.tokens);
  final String encoder, decoder, joiner, tokens;
}

/// Resolves the on-device streaming model directory. Phase B expects the model
/// to be present at <externalFiles>/asr-model (pushed via adb during dev;
/// Plan D adds first-run download). Returns null if any file is missing.
class AsrModelLocator {
  static Future<AsrModelPaths?> resolve() async {
    final ext = await getExternalStorageDirectory();
    if (ext == null) return null;
    final dir = '${ext.path}/asr-model';
    final p = AsrModelPaths(
      '$dir/encoder.int8.onnx',
      '$dir/decoder.int8.onnx',
      '$dir/joiner.int8.onnx',
      '$dir/tokens.txt',
    );
    for (final f in [p.encoder, p.decoder, p.joiner, p.tokens]) {
      if (!File(f).existsSync()) return null;
    }
    return p;
  }
}
```

> Dev setup before device-verifying B1.5: push the 122 MB model with the file names above:
> `adb push <model>/encoder.int8.onnx /sdcard/Android/data/com.hearty.app/files/asr-model/encoder.int8.onnx` (and decoder/joiner/tokens). (The spike pushed the 122 MB set to `asr-model-122`; copy it to `asr-model` or re-push.)

- [ ] **Step 2: Analyze + commit**

Run: `cd hearty_app && flutter analyze lib/core/stt/asr_model_locator.dart`

```bash
git add hearty_app/lib/core/stt/asr_model_locator.dart
git commit -m "feat(stt): on-device ASR model locator (download deferred to Plan D)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task B1.4: `OnDeviceSttEngine` (record mic + isolate + silence detector)

**Files:**
- Create: `hearty_app/lib/core/stt/on_device_stt_engine.dart`
- Re-add `record` to `hearty_app/pubspec.yaml` (it was added on the spike branch; not on this branch).

- [ ] **Step 1: Re-add the mic dependency**

In `pubspec.yaml` under `# Audio / Voice`:

```yaml
  record: ^6.1.1 # raw PCM16 mic stream for on-device ASR
```

Run: `cd hearty_app && flutter pub get`
Expected: `Got dependencies!` (resolves record 6.x — a consistent federated set).

- [ ] **Step 2: Implement the engine**

```dart
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'asr_isolate.dart';
import 'asr_model_locator.dart';
import 'silence_detector.dart';
import 'stt_engine.dart';

const _kSampleRate = 16000;

class OnDeviceSttEngine implements SttEngine {
  OnDeviceSttEngine({required this.silenceSeconds});
  final double silenceSeconds;

  final _recorder = AudioRecorder();
  final _partials = StreamController<String>.broadcast();
  final _readyOrError = Completer<String?>(); // null=ready, else error

  Isolate? _isolate;
  SendPort? _tx;
  ReceivePort? _rx;
  StreamSubscription? _micSub;
  SilenceDetector? _silence;
  final _finalCompleter = Completer<String>();
  bool _finishing = false;

  @override
  Stream<String> get partials => _partials.stream;

  @override
  Future<void> start({void Function()? onAutoSubmit}) async {
    final model = await AsrModelLocator.resolve();
    if (model == null) {
      throw StateError('on-device ASR model not found');
    }
    _silence = onAutoSubmit == null
        ? null
        : SilenceDetector(sampleRate: _kSampleRate, silenceSeconds: silenceSeconds);

    _rx = ReceivePort();
    _isolate = await Isolate.spawn(AsrIsolate.entry, _rx!.sendPort);
    _rx!.listen((msg) {
      if (msg is SendPort) {
        _tx = msg;
        _tx!.send(['init', model.encoder, model.decoder, model.joiner, model.tokens, 4]);
        return;
      }
      final m = msg as List;
      switch (m[0] as String) {
        case 'ready':
          if (!_readyOrError.isCompleted) _readyOrError.complete(null);
          break;
        case 'partial':
          if (!_partials.isClosed) _partials.add(m[1] as String);
          break;
        case 'final':
          if (!_finalCompleter.isCompleted) _finalCompleter.complete(m[1] as String);
          break;
        case 'error':
          if (!_readyOrError.isCompleted) _readyOrError.complete(m[1] as String);
          if (!_finalCompleter.isCompleted) _finalCompleter.complete('');
          break;
      }
    });

    final err = await _readyOrError.future;
    if (err != null) throw StateError('ASR init failed: $err');

    final mic = await _recorder.startStream(const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: _kSampleRate,
      numChannels: 1,
      androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.voiceRecognition),
    ));
    _micSub = mic.listen((bytes) {
      if (_finishing) return;
      final samples = _pcm16ToFloat32(bytes);
      _tx?.send(['pcm', samples]);
      if (_silence != null && _silence!.addPcm(samples)) {
        onAutoSubmit?.call();
      }
    });
  }

  @override
  Future<SttResult> stop() async {
    _finishing = true;
    await _micSub?.cancel();
    _micSub = null;
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (_) {}
    _tx?.send(['finish']);
    final text = await _finalCompleter.future
        .timeout(const Duration(seconds: 2), onTimeout: () => '');
    return SttResult(transcript: text.trim());
  }

  @override
  Future<void> dispose() async {
    _tx?.send(['dispose']);
    await _micSub?.cancel();
    _rx?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    if (!_partials.isClosed) await _partials.close();
    _recorder.dispose();
  }

  static Float32List _pcm16ToFloat32(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
    final n = bytes.length ~/ 2;
    final out = Float32List(n);
    for (var i = 0; i < n; i++) {
      out[i] = bd.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return out;
  }
}
```

- [ ] **Step 3: Analyze**

Run: `cd hearty_app && flutter analyze lib/core/stt/on_device_stt_engine.dart`
Expected: clean.

- [ ] **Step 4: DEVICE VERIFY (gate)** — done together with B1.5 wiring (an engine with no UI can't be exercised). Defer the device run to B1.6.

- [ ] **Step 5: Commit**

```bash
git add hearty_app/pubspec.yaml hearty_app/pubspec.lock hearty_app/lib/core/stt/on_device_stt_engine.dart
git commit -m "feat(stt): OnDeviceSttEngine (record mic + ASR isolate + silence auto-submit)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task B1.5: Refactor `VoiceNotifier` onto `SttEngine` (new state machine)

This is the core behavioral change. Replace the `speech_to_text` machinery (`_beginStt`, `_onSttStatus`, `_onSttError`, restart/accumulate, beep suppression) with an `SttEngine`-driven flow. Keep `VoiceState`/`VoiceStatus`, TTS, `sendToChat`/`sendFollowUpToApi`, `prepareForSpeech`, `replyIsQuestion` (from Phase A).

**Files:**
- Modify: `hearty_app/lib/features/voice/providers/voice_provider.dart`
- Modify: `hearty_app/test/features/voice/voice_provider_test.dart`

Design (new internal flow):
- Constructor takes `SttEngine Function()? engineFactory` (defaults to `() => OnDeviceSttEngine(silenceSeconds: 2.5)`); tests inject a factory returning `FakeSttEngine`.
- `startListening()` / follow-up open a session: create engine, `state = listening`, **one ding**, subscribe to `partials` → `setTranscript`, call `engine.start(onAutoSubmit: _autoSubmit ? _submit : null)`.
- `_submit()` → `engine.stop()` → `setTranscript(result.transcript)` → `setThinking()`. The overlay's existing `thinking` listener then calls `sendToChat`/`sendFollowUpToApi` (unchanged).
- **Half-duplex:** the engine is only ever started after TTS completion (existing completion-handler edge) — never during `responding`.
- **Manual submit / tap-to-confirm:** the overlay "Send" button calls `notifier.submit()`. When `_autoSubmit` is false (or the check-in case, Plan D), no `onAutoSubmit` is passed.
- Wake-word mic handoff stays (release before `engine.start`, re-arm in overlay dispose).

- [ ] **Step 1: Write failing tests** (state machine via FakeSttEngine)

Add to `voice_provider_test.dart`:

```dart
  group('SttEngine-driven lifecycle', () {
    late FakeSttEngine fake;
    ProviderContainer makeContainer() {
      fake = FakeSttEngine();
      return ProviderContainer(overrides: [
        voiceProvider.overrideWith((ref) => VoiceNotifier(
              ref: ref,
              ttsForTesting: FakeTtsEngine(fireCompletionOnSpeak: false),
              engineFactory: () => fake,
            )),
      ]);
    }

    test('startListening opens the engine and shows partials', () async {
      final c = makeContainer();
      final n = c.read(voiceProvider.notifier);
      n.startListening();
      await Future<void>.delayed(Duration.zero);
      expect(fake.started, isTrue);
      fake.emitPartial('i had a');
      await Future<void>.delayed(Duration.zero);
      expect(c.read(voiceProvider).transcript, 'i had a');
    });

    test('auto-submit stops the engine and moves to thinking', () async {
      final c = makeContainer();
      final n = c.read(voiceProvider.notifier);
      n.startListening();
      await Future<void>.delayed(Duration.zero);
      fake.nextTranscript = 'i had a turkey sandwich';
      fake.fireAutoSubmit();
      await Future<void>.delayed(Duration.zero);
      expect(c.read(voiceProvider).transcript, 'i had a turkey sandwich');
      expect(c.read(voiceProvider).status, VoiceStatus.thinking);
    });

    test('manual submit() works when auto-submit disabled', () async {
      final c = makeContainer();
      final n = c.read(voiceProvider.notifier);
      n.startListening();
      await Future<void>.delayed(Duration.zero);
      fake.nextTranscript = 'bloating';
      await n.submit();
      expect(c.read(voiceProvider).status, VoiceStatus.thinking);
      expect(c.read(voiceProvider).transcript, 'bloating');
    });

    // Regression guard for the dispatch-routing bug: a follow-up session must
    // stay in awaitingFollowUp right up until submit, so the overlay routes the
    // answer to sendFollowUpToApi (history/mealId/symptom_followup) — not
    // sendToChat. _openSession must NOT blanket the status to listening.
    test('follow-up session stays awaitingFollowUp until submit', () async {
      final c = makeContainer();
      final n = c.read(voiceProvider.notifier);
      n.resumeFollowUpListening(); // any follow-up entry point
      await Future<void>.delayed(Duration.zero);
      expect(c.read(voiceProvider).status, VoiceStatus.awaitingFollowUp);
      fake.emitPartial('a little nauseous');
      await Future<void>.delayed(Duration.zero);
      // still a follow-up while capturing — not downgraded to listening
      expect(c.read(voiceProvider).status, VoiceStatus.awaitingFollowUp);
    });
  });
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd hearty_app && flutter test test/features/voice/voice_provider_test.dart --plain-name "SttEngine-driven"`
Expected: FAIL — `engineFactory` / `submit` undefined.

- [ ] **Step 3: Implement the refactor**

Add the constructor param and engine plumbing; replace the old STT methods. Key additions to `VoiceNotifier`:

```dart
  VoiceNotifier({
    Ref? ref,
    TtsEngine? ttsForTesting,
    SttEngine Function()? engineFactory,
    Future<void> Function()? releaseWakeWordMic,
    bool autoSubmit = true,
    double autoSubmitSilenceSeconds = 2.5,
  })  : _ref = ref,
        _injectedTts = ttsForTesting,
        _engineFactory = engineFactory ??
            (() => OnDeviceSttEngine(silenceSeconds: autoSubmitSilenceSeconds)),
        _autoSubmit = autoSubmit,
        _releaseWakeWordMic = releaseWakeWordMic ?? WakeWordChannel.stopListening,
        super(const VoiceState()) {
    _ready = _initTts();
  }

  final SttEngine Function() _engineFactory;
  final bool _autoSubmit;
  SttEngine? _engine;
  StreamSubscription<String>? _partialSub;

  Future<void> _openSession({required bool isFollowUp}) async {
    await _closeEngine();
    state = state.copyWith(
      // CRITICAL: preserve the listening vs awaitingFollowUp distinction. The
      // overlay dispatches on the pre-submit status (awaitingFollowUp →
      // sendFollowUpToApi, else → sendToChat). A blanket `listening` here would
      // route every follow-up answer to sendToChat, dropping history/mealId and
      // the symptom_followup flag. Fresh capture = listening; any follow-up
      // (conversation turn OR notification check-in) = awaitingFollowUp.
      status: isFollowUp ? VoiceStatus.awaitingFollowUp : VoiceStatus.listening,
      micPhase: MicPhase.listening,
      transcript: '',
    );
    _beep.ding(); // exactly one ding per session  (see AudioBeepChannel)
    try {
      await _releaseWakeWordMic();
    } catch (_) {}
    final engine = _engineFactory();
    _engine = engine;
    _partialSub = engine.partials.listen(setTranscript);
    try {
      await engine.start(onAutoSubmit: _autoSubmit ? submit : null);
    } catch (e) {
      _pauseForManual(); // surface tap-to-talk + text fallback, no dead spinner
    }
  }

  /// Stop capture, ship the transcript, move to thinking.
  Future<void> submit() async {
    final engine = _engine;
    if (engine == null) return;
    final result = await engine.stop();
    await _closeEngine();
    if (!mounted) return;
    if (result.transcript.isNotEmpty) setTranscript(result.transcript);
    setThinking();
  }

  Future<void> _closeEngine() async {
    await _partialSub?.cancel();
    _partialSub = null;
    final e = _engine;
    _engine = null;
    await e?.dispose();
  }
```

- Rewrite `startListening()` → `_openSession(isFollowUp: false)` (after the existing `_symptomCheckIn=false` reset).
- Rewrite `setAwaitingFollowUp()` to call `_openSession(isFollowUp: true)` instead of `_beginFollowUpStt`.
- Delete: `_beginStt`, `_beginFollowUpStt`, `_onSttStatus`, `_onSttError`, `_autoSubmitIfPending`, `_pauseFollowUpMic` (replace usage with `_pauseForManual`), the beep-suppression timer logic, and the `speech_to_text` import/field. Keep `dismiss()`/`setThinking()`/`setResponse()`/TTS.
- Add `_pauseForManual()` → `state = state.copyWith(micPhase: MicPhase.paused)` and keep `resumeFollowUpListening()` → `_openSession(isFollowUp: true)`.
- `dispose()` / `dismiss()` must `await _closeEngine()`.
- Add a `ding()` to `AudioBeepChannel` (single beep) if not present; the `FakeBeepChannel` in tests already records calls.

> Because this deletes the `speech_to_text` field, the old `FakeSpeechToText` in the test file becomes unused — remove it and the tests that exercised the old restart/accumulate behavior (they describe behavior that no longer exists). Keep the Phase-A `prepareForSpeech`/`replyIsQuestion` groups and the new `SttEngine-driven` group.

- [ ] **Step 4: Run the voice suite to verify pass**

Run: `cd hearty_app && flutter test test/features/voice/voice_provider_test.dart`
Expected: PASS (Phase-A groups + new lifecycle group; old STT-restart tests removed).

- [ ] **Step 5: Analyze + commit**

Run: `cd hearty_app && flutter analyze lib/features/voice/providers/voice_provider.dart`
Expected: clean (no `speech_to_text` references remain in this file).

```bash
git add hearty_app/lib/features/voice/providers/voice_provider.dart hearty_app/test/features/voice/voice_provider_test.dart
git commit -m "refactor(voice): drive the lifecycle via SttEngine (kills truncation/restart churn)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

### Task B1.6: Wire the overlay + device-verify Flows 1 & 2

**Files:**
- Modify: `hearty_app/lib/features/voice/screens/voice_overlay_screen.dart` (Send button → `notifier.submit()`; review/listening UI per spec §6)

- [ ] **Step 1: Add the Send action**

In the listening/review UI, ensure a **Send** button calls `ref.read(voiceProvider.notifier).submit()`, and the existing "Or type here…" field + Re-record remain. (Auto-submit will usually fire first; Send is the manual path / when auto-submit is off.)

- [ ] **Step 2: Analyze + widget tests**

Run: `cd hearty_app && flutter test test/features/voice/voice_overlay_screen_test.dart && flutter analyze lib/features/voice/screens/voice_overlay_screen.dart`
Expected: pass/clean (update any overlay tests that referenced removed states).

- [ ] **Step 3: DEVICE VERIFY (gate).** Push the 122 MB model to `asr-model` (see B1.3 note), `make run`, then on the Pixel 4a:
  - **Flow 1:** "Hey Hearty" → "I had a turkey sandwich" with a **mid-sentence pause** → confirm the full phrase is captured (no truncation), one ding only, auto-submits ~2.5 s after you stop, logs correctly.
  - **Flow 2:** answer Hearty's follow-up question with a pause → confirm it stays open and captures the full answer; conversation continues only when Hearty asks a question.
  - **Half-duplex:** confirm the mic does NOT capture Hearty's own TTS.
  - **No ANR** throughout.

- [ ] **Step 4: Commit**

```bash
git add hearty_app/lib/features/voice/screens/voice_overlay_screen.dart hearty_app/test/features/voice/voice_overlay_screen_test.dart
git commit -m "feat(voice): wire overlay Send to SttEngine submit; device-verified Flows 1 & 2

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Self-review

- **Spec coverage (B scope):** on-device sherpa streaming (B0.1/B1.4 ✓), background isolate / no-ANR (B0.2 gate ✓), endpointing-off + WE decide turn-end (B0.1 `enableEndpoint:false` + B1.2 detector ✓), auto-submit 2.5 s default + manual Send (B1.2/B1.5 ✓), one ding (B1.5 ✓), half-duplex (B1.5 — engine only starts post-TTS ✓), mic handoff (B1.5 ✓), Flows 1 & 2 device-verified (B1.6 ✓). All three flows' capture paths migrate to `SttEngine` in B (single shared `_beginStt`→`_openSession`), with the follow-up/check-in status distinction preserved (B1.5 — `awaitingFollowUp` vs `listening`, regression-tested). Deferred-by-design: cloud/selection (Plan C); Flow 3 *reliability polish* (ambient rejection, spoken-question setting, tap-to-confirm-only default), settings UI, model download, and removing `speech_to_text` (Plan D).
- **Placeholders:** none — full code in every code step. Native isolate/mic steps are real code gated by explicit DEVICE-VERIFY checks (FFI-in-isolate cannot be unit-tested).
- **Type/name consistency:** `SttEngine.start({onAutoSubmit})`/`stop()→SttResult`/`partials`/`dispose()` are defined in B1.1 and used identically in `FakeSttEngine` (B1.1), `OnDeviceSttEngine` (B1.4), and `VoiceNotifier` (B1.5). `SilenceDetector.addPcm(Float32List)→bool` defined B1.2, used B1.4. `submit()` defined B1.5, called B1.6. Isolate message tags (`init`/`pcm`/`finish`/`dispose` ↔ `ready`/`partial`/`final`/`error`) match between B0.1 and B1.4.
- **Risk note carried from spec:** B0.2 is a hard gate — if the isolate doesn't clear the ANR, stop and reassess before P1 native wiring.
