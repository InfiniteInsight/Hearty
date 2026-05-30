# Hearty Non-Binary On-Device Voice — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Hearty's spoken voice (currently the phone's built-in TTS) with a custom, distinctive, gender-neutral neural voice that runs fully on-device via sherpa-onnx, falling back to system TTS where the neural engine can't run.

**Architecture:** A new `TtsEngine` interface decouples `voice_provider.dart` from `FlutterTts`. `NeuralTtsEngine` (sherpa-onnx running a bundled `.onnx` voice) is the default; `SystemTtsEngine` (today's `flutter_tts`) is the fallback. The custom voice is created on the pkix workstation by designing a timbre with Qwen3-TTS VoiceDesign, generating a synthetic corpus, distilling it into a Piper/VITS model, and exporting to ONNX. The `.onnx` file is the only artifact crossing between the app track and the workstation track.

**Tech Stack:** Flutter (Riverpod, GoRouter), `sherpa_onnx ^1.13.2` (Apache-2.0), `just_audio` (already a dep), `flutter_tts` (kept for fallback). Workstation: Python, Qwen3-TTS (1.7B), Piper training, ONNX export. Training on pkix (RTX PRO 4000 Blackwell 24 GB).

**Spec:** `docs/superpowers/specs/2026-05-30-hearty-nonbinary-voice-design.md`

---

## How to use this plan (Living State + Realignment protocol)

This plan is **self-tracking**. It is designed to resist bugs and goal drift across a long, multi-session build. Three rules:

1. **Every task has a `Living State` block.** When you (the executing agent) start a task, set its status to 🟡 In Progress. When done, set it to ✅ Done. If you deviate from the written steps for ANY reason — a wrong assumption in the plan, a missing dependency, an API that differs from what's documented here — you MUST record it under **Deviations** in that task's Living State block, with *what* changed and *why*. Do not silently "fix" the plan by doing something different; write it down.

2. **Every phase ends with a Realignment Checkpoint.** Before moving to the next phase, complete the checkpoint: re-read the deviations logged in the phase, confirm the phase actually delivered its goal, and **propagate consequences forward** — if a deviation invalidates an assumption in a later phase/task, edit that later task now and note the edit in the checkpoint. This is the anti-drift mechanism. A phase is not "done" until its checkpoint passes.

3. **The spec is the source of truth for *goals*; this plan is the source of truth for *steps*.** If a deviation changes a goal (not just a step), update the spec too and flag it to the user at the checkpoint.

**Status legend:** ⬜ Not Started · 🟡 In Progress · ✅ Done · ⚠️ Done-with-deviations (see Living State) · 🛑 Blocked

---

## Phase Summary

| Phase | Name | Track | Status |
|-------|------|-------|--------|
| 0 | Runtime spike — prove sherpa-onnx TTS works on-device | App | ⬜ Not Started |
| 0R | Realignment Checkpoint | — | ⬜ Not Started |
| 1 | `TtsEngine` abstraction + neural/system fallback integration | App | ⬜ Not Started |
| 1R | Realignment Checkpoint | — | ⬜ Not Started |
| 2 | Voice creation pipeline (design → corpus → distill → export) | Workstation | ⬜ Not Started |
| 2R | Realignment Checkpoint | — | ⬜ Not Started |
| 3 | Real voice integration + conversation-style adaptation | App | ⬜ Not Started |
| 3R | Realignment Checkpoint | — | ⬜ Not Started |
| F | Final Project Realignment | — | ⬜ Not Started |

**Gating:** Phase 0 is a hard gate. If its checkpoint concludes on-device neural TTS is not acceptable (latency/battery/size), STOP and escalate to the user — do not proceed to Phase 1. Phases 1 and 2 are independent and may run in either order or in parallel (different tracks). Phase 3 requires both 1 and 2 complete.

---

## Phase 0: Runtime spike — prove sherpa-onnx TTS works on-device

**Status:** ⬜ Not Started
**Goal:** Establish, on a real Android device, that sherpa-onnx can synthesize speech from a stock voice with acceptable latency, battery, and app-size cost — and that PCM output can be played through the app's audio stack. This is a measurement spike, not production code; it lives on a throwaway branch and TDD is relaxed in favor of measurement.

**Why first:** The single biggest risk is runtime viability on a mid-range phone, not the voice itself. Spend days here, not weeks downstream.

**Files:**
- Create: `hearty_app/lib/features/voice/spike/sherpa_spike_screen.dart` (throwaway, deleted in 0R)
- Modify: `hearty_app/pubspec.yaml` (add `sherpa_onnx`, bundle a stock model under `assets/tts/`)
- Create: `docs/superpowers/notes/2026-05-30-tts-spike-results.md` (measurements)

### Task 0.1: Add sherpa_onnx and bundle a stock Kokoro voice

**Prompt:** Add the `sherpa_onnx` package and bundle one stock voice as an asset so we can synthesize on-device. Use Kokoro (en) for the spike because it is the candidate runtime voice class and is small. Do not wire it into `voice_provider` yet — this is isolated spike code.

**Files:**
- Modify: `hearty_app/pubspec.yaml`

- [ ] **Step 1: Add the dependency.** In `hearty_app/pubspec.yaml`, under `dependencies:` (near the `# Audio / Voice` block), add:

```yaml
  sherpa_onnx: ^1.13.2
```

- [ ] **Step 2: Download a stock voice on the dev machine.** A Kokoro model for sherpa-onnx (`kokoro-en-v0_19` or current equivalent from the sherpa-onnx `tts-models` release page). Extract into `hearty_app/assets/tts/kokoro-en/` so it contains `model.onnx`, `voices.bin`, `tokens.txt`, and the `espeak-ng-data/` directory.

```bash
cd hearty_app/assets/tts
wget https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-en-v0_19.tar.bz2
tar xf kokoro-en-v0_19.tar.bz2 && mv kokoro-en-v0_19 kokoro-en && rm kokoro-en-v0_19.tar.bz2
```

- [ ] **Step 3: Register the assets.** In `hearty_app/pubspec.yaml` under `flutter: assets:`, add every subdirectory (Flutter does not recurse automatically; list each dir that holds files):

```yaml
    - assets/tts/kokoro-en/
    - assets/tts/kokoro-en/espeak-ng-data/
```

> Note: `espeak-ng-data/` has many nested dirs. If `flutter` complains about missing nested asset dirs, use the sherpa-onnx `generate-asset-list.py` helper (from their flutter-examples/tts) to emit the full list, or copy a flattened model that ships a single `dict/` dir. Record which approach you used in Living State.

- [ ] **Step 4: Fetch packages.** Run: `cd hearty_app && make run` is overkill here; just run `flutter pub get`. Expected: resolves `sherpa_onnx` with no version conflict against existing deps.

**Living State — Task 0.1**
- Status: ⬜ Not Started
- Deviations:
- Notes for later phases (e.g. final model dir layout, asset-listing approach chosen):

---

### Task 0.2: Minimal synth-and-play spike screen

**Prompt:** Build a single throwaway screen with a text field, a "Speak" button, and on-screen timing readouts. Use the verified sherpa-onnx Dart API to load the bundled Kokoro model, synthesize the text to PCM samples, and play them. This screen exists only to take measurements; it will be deleted in the realignment checkpoint.

**Verified sherpa-onnx API (from k2-fsa/sherpa-onnx dart examples, do not guess):**
```dart
// init once at app start:
await sherpa_onnx.initBindings(); // or the package's documented init
final kokoro = sherpa_onnx.OfflineTtsKokoroModelConfig(
  model: '<path>/model.onnx', voices: '<path>/voices.bin',
  tokens: '<path>/tokens.txt', dataDir: '<path>/espeak-ng-data');
final modelConfig = sherpa_onnx.OfflineTtsModelConfig(kokoro: kokoro, numThreads: 2);
final config = sherpa_onnx.OfflineTtsConfig(model: modelConfig, maxNumSenetences: 1);
final tts = sherpa_onnx.OfflineTts(config);
final genConfig = sherpa_onnx.OfflineTtsGenerationConfig(sid: 0, speed: 1.0);
final audio = tts.generateWithConfig(text: text, config: genConfig);
// audio.samples -> Float32List PCM, audio.sampleRate -> int
tts.free();
```

**Files:**
- Create: `hearty_app/lib/features/voice/spike/sherpa_spike_screen.dart`

- [ ] **Step 1: Copy model assets to a readable path.** sherpa-onnx reads files from disk, not Flutter asset bundles directly. Write a helper that, on first run, copies each bundled asset out of `rootBundle` into the app's documents directory (`path_provider`) and returns the on-disk model dir. (This same copy-on-first-run helper graduates into Phase 1 — note it in Living State.)

- [ ] **Step 2: Build the spike screen.** A `StatefulWidget` with: a `TextEditingController` pre-filled with `"Hi, I'm Hearty. I'll help you track how food makes you feel."`, a Speak button, and `Text` widgets showing: (a) ms from button press → first samples, (b) ms → synthesis complete, (c) total audio duration, (d) real-time factor (synth time ÷ audio duration). Use a `Stopwatch`.

- [ ] **Step 3: Play the PCM.** Convert `audio.samples` (Float32List) + `audio.sampleRate` into a WAV byte buffer in memory (16-bit PCM WAV header + samples), write to a temp file, and play via `just_audio` (`AudioPlayer().setFilePath(...)..play()`). Confirm audible output. Record whether in-memory WAV + just_audio worked, or whether you fell back to `audioplayers` / sherpa-onnx file output, in Living State. **This is the key integration unknown the spike exists to resolve.**

- [ ] **Step 4: Temporarily route to the spike.** Add a debug-only entry to reach `SherpaSpikeScreen` (e.g. a temporary button on the voice settings screen, or a hardcoded route). Mark it clearly with `// SPIKE — remove in 0R`.

- [ ] **Step 5: Run on a real device.** Run: `cd hearty_app && make run` (per project rule — never bare `flutter run`). Deploy to a physical mid-range Android, not an emulator (emulator perf is not representative).

**Living State — Task 0.2**
- Status: ⬜ Not Started
- Deviations (esp. actual API names if they differ from the snippet above, and the playback path that actually worked):
- Notes for later phases (the asset-copy helper, the WAV-wrap helper — both reused in Phase 1):

---

### Task 0.3: Measure and record the gate decision

**Prompt:** Take real measurements on the target device and write them down. Then make an explicit go/no-go recommendation against the gate criteria. Do not proceed past Phase 0 without this written.

**Files:**
- Create: `docs/superpowers/notes/2026-05-30-tts-spike-results.md`

- [ ] **Step 1: Measure latency.** On the physical device, record cold-start synth latency (first speak after app launch) and warm latency (subsequent speaks) for a short (~12 word) and a medium (~40 word) utterance. Record the real-time factor. **Gate target:** warm latency for a short utterance under ~700 ms feels acceptable in the conversational voice flow; flag if much higher.

- [ ] **Step 2: Measure size.** Record the `.apk`/`.aab` size delta from adding the package + bundled model (`flutter build apk --split-per-abi`, compare to a pre-spike build). **Gate note:** Kokoro model is ~tens of MB; record actual.

- [ ] **Step 3: Spot-check battery/thermal.** Synthesize ~20 utterances back-to-back; note any device heat or jank. Qualitative is fine.

- [ ] **Step 4: Write the results doc** with sections: Device, Latency (cold/warm/RTF), Size delta, Battery/thermal notes, Playback path that worked, and a **Go/No-Go recommendation** with one paragraph of reasoning.

**Living State — Task 0.3**
- Status: ⬜ Not Started
- Deviations:
- Go/No-Go recommendation (copy the conclusion here):

---

## Phase 0R: Realignment Checkpoint

**Status:** ⬜ Not Started

- [ ] **Gate decision.** Read `tts-spike-results.md`. Is on-device neural TTS acceptable? If **No** → set Phase 1/2/3 to 🛑 Blocked, update the spec's risk section, and escalate to the user with the numbers. Stop here.
- [ ] **Harvest reusable code.** Confirm the asset-copy helper and PCM→WAV→playback helper are documented in Living State (they are inputs to Phase 1). Move any code worth keeping out of `spike/` mentally — Phase 1 will reimplement cleanly under TDD.
- [ ] **Delete the spike.** Remove `hearty_app/lib/features/voice/spike/`, the temporary route/button, and any `// SPIKE` markers. Keep the bundled stock model asset (Phase 1 uses it until the real voice arrives in Phase 3). Commit: `chore: remove TTS runtime spike, keep measurements`.
- [ ] **Propagate forward.** Re-read deviations in 0.1–0.3. If the real sherpa-onnx API names differ from this plan's snippets, **edit Phase 1 Task 1.3 now** to match, and note the edit here.
- [ ] **Checkpoint result (write one line):**

---

## Phase 1: `TtsEngine` abstraction + neural/system fallback integration

**Status:** ⬜ Not Started
**Goal:** Decouple `voice_provider.dart` from `FlutterTts` behind a `TtsEngine` interface; implement `NeuralTtsEngine` (sherpa-onnx, default, using the stock voice for now) and `SystemTtsEngine` (today's behavior, fallback); migrate existing tests; ship with the neural engine active and graceful fallback. TDD from here on.

**Files:**
- Create: `hearty_app/lib/core/tts/tts_engine.dart` (interface + `TtsStyle`)
- Create: `hearty_app/lib/core/tts/system_tts_engine.dart`
- Create: `hearty_app/lib/core/tts/neural_tts_engine.dart`
- Create: `hearty_app/lib/core/tts/tts_audio_utils.dart` (asset-copy + PCM→WAV helpers from spike)
- Modify: `hearty_app/lib/features/voice/providers/voice_provider.dart`
- Modify: `hearty_app/test/features/voice/voice_provider_test.dart`
- Modify: `hearty_app/test/features/voice/voice_followup_test.dart`
- Modify: `hearty_app/test/features/voice/voice_offline_test.dart`
- Modify: `hearty_app/test/features/voice/symptom_followup_test.dart`
- Create: `hearty_app/test/core/tts/tts_engine_test.dart`

### Task 1.1: Define the `TtsEngine` interface and `TtsStyle`

**Prompt:** Define the abstraction that hides synthesis behind one seam. Keep it minimal — only what `voice_provider.dart` actually calls today (`speak`, `stop`, `setCompletionHandler`) plus `init` and `setStyle` for later. The completion-handler contract must match how `voice_provider` uses it: the callback fires when audio finishes playing (this drives `setAwaitingFollowUp`/`dismiss`).

**Files:**
- Create: `hearty_app/lib/core/tts/tts_engine.dart`

- [ ] **Step 1: Write the interface.**

```dart
import 'package:flutter/foundation.dart';

enum TtsStyle { warm, concise }

/// Engine-agnostic text-to-speech seam used by VoiceNotifier.
/// Implementations: NeuralTtsEngine (sherpa-onnx, default),
/// SystemTtsEngine (flutter_tts, fallback).
abstract class TtsEngine {
  /// Prepare the engine. [voiceName] is an optional system-voice override
  /// (honored only by SystemTtsEngine). Must not throw; return false on
  /// unrecoverable init failure so the caller can fall back.
  Future<bool> init({String? voiceName});

  /// Speak [text]. Resolves when playback finishes. The completion handler
  /// (if set) also fires on finish.
  Future<void> speak(String text);

  /// Stop any in-progress speech immediately.
  Future<void> stop();

  /// Register a callback invoked when an utterance finishes playing.
  void setCompletionHandler(VoidCallback onDone);

  /// Apply delivery style (rate/pitch/contour). No-op until Phase 3.
  Future<void> setStyle(TtsStyle style);

  /// Release native resources.
  Future<void> dispose();
}
```

- [ ] **Step 2: Analyze.** Run: `cd hearty_app && flutter analyze lib/core/tts/tts_engine.dart`. Expected: no issues.
- [ ] **Step 3: Commit.** `git add hearty_app/lib/core/tts/tts_engine.dart && git commit -m "feat: add TtsEngine interface + TtsStyle"`

**Living State — Task 1.1**
- Status: ⬜ Not Started
- Deviations:
- Notes for later phases:

---

### Task 1.2: `SystemTtsEngine` — wrap today's behavior behind the interface

**Prompt:** Port the existing `flutter_tts` usage from `voice_provider.dart` (lines ~47–64 init, `speak`, `stop`, completion handler, saved-voice load) into `SystemTtsEngine implements TtsEngine` verbatim in behavior. This is the fallback and must reproduce current behavior exactly, including reading the saved `tts_voice_name` pref and the `setSpeechRate(0.7)` / `setPitch(1.0)` settings.

**Files:**
- Create: `hearty_app/lib/core/tts/system_tts_engine.dart`
- Test: `hearty_app/test/core/tts/tts_engine_test.dart`

- [ ] **Step 1: Write the failing test** (`tts_engine_test.dart`):

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:hearty_app/core/tts/system_tts_engine.dart';
import 'package:mockito/mockito.dart';

class _FakeFlutterTts extends Mock implements FlutterTts {
  String? spokenText;
  VoidCallback? completion;
  @override
  Future<dynamic> setLanguage(String? l) async => 1;
  @override
  Future<dynamic> setSpeechRate(double? r) async => 1;
  @override
  Future<dynamic> setPitch(double? p) async => 1;
  @override
  Future<dynamic> setVoice(Map<String?, String?>? v) async => 1;
  @override
  Future<dynamic> speak(String? t) async { spokenText = t; completion?.call(); return 1; }
  @override
  Future<dynamic> stop() async => 1;
  @override
  void setCompletionHandler(VoidCallback c) { completion = c; }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('SystemTtsEngine speaks text and fires completion', () async {
    final fake = _FakeFlutterTts();
    final engine = SystemTtsEngine(ttsForTesting: fake);
    var done = false;
    engine.setCompletionHandler(() => done = true);
    await engine.init();
    await engine.speak('hello');
    expect(fake.spokenText, 'hello');
    expect(done, true);
  });
}
```

- [ ] **Step 2: Run to confirm it fails.** Run: `cd hearty_app && flutter test test/core/tts/tts_engine_test.dart`. Expected: FAIL — `SystemTtsEngine` undefined.

- [ ] **Step 3: Implement `SystemTtsEngine`.**

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'tts_engine.dart';

class SystemTtsEngine implements TtsEngine {
  SystemTtsEngine({FlutterTts? ttsForTesting})
      : _tts = ttsForTesting ?? FlutterTts();
  final FlutterTts _tts;

  @override
  Future<bool> init({String? voiceName}) async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.7);
    await _tts.setPitch(1.0);
    final prefs = await SharedPreferences.getInstance();
    final saved = voiceName ?? prefs.getString('tts_voice_name');
    if (saved != null) {
      await _tts.setVoice({'name': saved, 'locale': 'en-US'});
    }
    return true;
  }

  @override
  Future<void> speak(String text) => _tts.speak(text);

  @override
  Future<void> stop() => _tts.stop();

  @override
  void setCompletionHandler(VoidCallback onDone) =>
      _tts.setCompletionHandler(onDone);

  @override
  Future<void> setStyle(TtsStyle style) async {
    // System engine: map style to rate only (pitch shift distorts formants).
    await _tts.setSpeechRate(style == TtsStyle.concise ? 0.8 : 0.7);
  }

  @override
  Future<void> dispose() => _tts.stop();
}
```

- [ ] **Step 4: Run to confirm it passes.** Run: `cd hearty_app && flutter test test/core/tts/tts_engine_test.dart`. Expected: PASS.
- [ ] **Step 5: Commit.** `git add hearty_app/lib/core/tts/system_tts_engine.dart hearty_app/test/core/tts/tts_engine_test.dart && git commit -m "feat: SystemTtsEngine fallback wrapping flutter_tts"`

**Living State — Task 1.2**
- Status: ⬜ Not Started
- Deviations:
- Notes for later phases:

---

### Task 1.3: `NeuralTtsEngine` + audio utils (sherpa-onnx)

**Prompt:** Implement the default engine using sherpa-onnx and the bundled stock voice (the real voice arrives in Phase 3). Reuse the asset-copy and PCM→WAV→playback approach proven in the Phase 0 spike. `init()` must return `false` (never throw) if the model can't load, so the caller falls back. The completion handler fires when `just_audio` reports playback complete.

**IMPORTANT:** If Phase 0R recorded that the real sherpa-onnx API names differ from the snippet below, use the real names recorded there.

**Files:**
- Create: `hearty_app/lib/core/tts/tts_audio_utils.dart`
- Create: `hearty_app/lib/core/tts/neural_tts_engine.dart`

- [ ] **Step 1: Implement `tts_audio_utils.dart`** — two helpers harvested from the spike: `Future<String> copyModelAssets(String assetDir)` (copies bundled model files to a documents-dir path on first run, returns the on-disk dir) and `Uint8List pcmToWav(Float32List samples, int sampleRate)` (wraps Float32 PCM as 16-bit WAV). Paste the exact working versions from the spike. (No standalone unit test for the WAV header here — it is validated end-to-end by the spike and by manual device playback in 1.6; note this choice in Living State.)

- [ ] **Step 2: Write the failing test** for fallback behavior (the part that is testable without native libs — that a load failure yields `init() == false`):

```dart
// add to test/core/tts/tts_engine_test.dart
test('NeuralTtsEngine.init returns false when model dir is missing', () async {
  final engine = NeuralTtsEngine(modelAssetDir: 'assets/tts/does-not-exist');
  final ok = await engine.init();
  expect(ok, false);
});
```

- [ ] **Step 3: Run to confirm it fails.** Run: `cd hearty_app && flutter test test/core/tts/tts_engine_test.dart`. Expected: FAIL — `NeuralTtsEngine` undefined.

- [ ] **Step 4: Implement `neural_tts_engine.dart`** using the verified API (adjust names per 0R if needed):

```dart
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'tts_engine.dart';
import 'tts_audio_utils.dart';

class NeuralTtsEngine implements TtsEngine {
  NeuralTtsEngine({this.modelAssetDir = 'assets/tts/kokoro-en'});
  final String modelAssetDir;

  sherpa.OfflineTts? _tts;
  final AudioPlayer _player = AudioPlayer();
  VoidCallback? _onDone;
  TtsStyle _style = TtsStyle.warm;

  @override
  Future<bool> init({String? voiceName}) async {
    try {
      final dir = await copyModelAssets(modelAssetDir);
      if (!Directory(dir).existsSync()) return false;
      sherpa.initBindings();
      final kokoro = sherpa.OfflineTtsKokoroModelConfig(
        model: '$dir/model.onnx',
        voices: '$dir/voices.bin',
        tokens: '$dir/tokens.txt',
        dataDir: '$dir/espeak-ng-data',
      );
      final model = sherpa.OfflineTtsModelConfig(kokoro: kokoro, numThreads: 2);
      _tts = sherpa.OfflineTts(
        sherpa.OfflineTtsConfig(model: model, maxNumSenetences: 1));
      _player.playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed) _onDone?.call();
      });
      return true;
    } catch (e) {
      debugPrint('NeuralTtsEngine init failed: $e');
      return false;
    }
  }

  @override
  Future<void> speak(String text) async {
    final tts = _tts;
    if (tts == null) return;
    final speed = _style == TtsStyle.concise ? 1.1 : 0.95;
    final audio = tts.generateWithConfig(
      text: text,
      config: sherpa.OfflineTtsGenerationConfig(sid: 0, speed: speed),
    );
    final wav = pcmToWav(audio.samples, audio.sampleRate);
    final tmp = File('${Directory.systemTemp.path}/hearty_tts.wav');
    await tmp.writeAsBytes(wav, flush: true);
    await _player.setFilePath(tmp.path);
    await _player.play();
  }

  @override
  Future<void> stop() => _player.stop();

  @override
  void setCompletionHandler(VoidCallback onDone) => _onDone = onDone;

  @override
  Future<void> setStyle(TtsStyle style) async => _style = style;

  @override
  Future<void> dispose() async {
    await _player.dispose();
    _tts?.free();
  }
}
```

- [ ] **Step 5: Run to confirm it passes.** Run: `cd hearty_app && flutter test test/core/tts/tts_engine_test.dart`. Expected: PASS (the missing-dir test; the happy path is device-validated in 1.6).
- [ ] **Step 6: Commit.** `git add hearty_app/lib/core/tts/ hearty_app/test/core/tts/tts_engine_test.dart && git commit -m "feat: NeuralTtsEngine (sherpa-onnx) + audio utils"`

**Living State — Task 1.3**
- Status: ⬜ Not Started
- Deviations (esp. real sherpa-onnx API names, completion-detection mechanism):
- Notes for later phases (Phase 3 swaps `modelAssetDir` to the real voice and may switch to `OfflineTtsVitsModelConfig` if the distilled voice is Piper, not Kokoro — flag that here):

---

### Task 1.4: Engine selection + factory with fallback

**Prompt:** Add a factory that picks the engine: try `NeuralTtsEngine` first; if `init()` returns false (or a user has explicitly chosen a system voice via the advanced picker), use `SystemTtsEngine`. The factory returns an initialized, ready `TtsEngine`.

**Files:**
- Create: `hearty_app/lib/core/tts/tts_engine_factory.dart`
- Test: `hearty_app/test/core/tts/tts_engine_test.dart` (append)

- [ ] **Step 1: Write the failing test.**

```dart
test('factory falls back to system engine when neural init fails', () async {
  final engine = await createTtsEngine(
    neuralBuilder: () => _AlwaysFailNeural(),
    systemBuilder: () => _OkSystem(),
  );
  expect(engine, isA<_OkSystem>());
});
```

(Define tiny `_AlwaysFailNeural`/`_OkSystem` test doubles implementing `TtsEngine`, with `init` returning false/true respectively.)

- [ ] **Step 2: Run to confirm it fails.** Run: `cd hearty_app && flutter test test/core/tts/tts_engine_test.dart`. Expected: FAIL — `createTtsEngine` undefined.

- [ ] **Step 3: Implement the factory.**

```dart
import 'tts_engine.dart';
import 'neural_tts_engine.dart';
import 'system_tts_engine.dart';

typedef _Builder = TtsEngine Function();

Future<TtsEngine> createTtsEngine({
  String? systemVoiceOverride,
  _Builder? neuralBuilder,
  _Builder? systemBuilder,
}) async {
  // Explicit system-voice override → skip neural entirely.
  if (systemVoiceOverride != null) {
    final sys = (systemBuilder ?? () => SystemTtsEngine())();
    await sys.init(voiceName: systemVoiceOverride);
    return sys;
  }
  final neural = (neuralBuilder ?? () => NeuralTtsEngine())();
  if (await neural.init()) return neural;
  final sys = (systemBuilder ?? () => SystemTtsEngine())();
  await sys.init();
  return sys;
}
```

- [ ] **Step 4: Run to confirm it passes.** Run: `cd hearty_app && flutter test test/core/tts/tts_engine_test.dart`. Expected: PASS.
- [ ] **Step 5: Commit.** `git add hearty_app/lib/core/tts/tts_engine_factory.dart hearty_app/test/core/tts/tts_engine_test.dart && git commit -m "feat: TTS engine factory with neural→system fallback"`

**Living State — Task 1.4**
- Status: ⬜ Not Started
- Deviations:
- Notes for later phases:

---

### Task 1.5: Migrate `voice_provider.dart` to `TtsEngine`

**Prompt:** Replace the `FlutterTts _tts` field in `VoiceNotifier` with `TtsEngine _tts`. The constructor's `ttsForTesting` parameter changes type from `FlutterTts?` to `TtsEngine?`. All call sites (`_initTts`, `_speakResponse`, `stopSpeaking`, `dismiss`, `primeForSymptomFollowUp`, `dispose`) call the interface instead. Behavior — including the completion handler driving `setAwaitingFollowUp`/`dismiss` and the `_prepareForSpeech` text prep — stays identical. Then migrate all four voice test files to inject a fake `TtsEngine`.

**Files:**
- Modify: `hearty_app/lib/features/voice/providers/voice_provider.dart`
- Modify: `hearty_app/test/features/voice/voice_provider_test.dart`
- Modify: `hearty_app/test/features/voice/voice_followup_test.dart`
- Modify: `hearty_app/test/features/voice/voice_offline_test.dart`
- Modify: `hearty_app/test/features/voice/symptom_followup_test.dart`

- [ ] **Step 1: Add a shared fake engine to the test tree.** Create `hearty_app/test/features/voice/fake_tts_engine.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:hearty_app/core/tts/tts_engine.dart';

class FakeTtsEngine implements TtsEngine {
  String? spokenText;
  VoidCallback? _onDone;
  bool fireCompletionOnSpeak;
  FakeTtsEngine({this.fireCompletionOnSpeak = true});

  @override
  Future<bool> init({String? voiceName}) async => true;
  @override
  Future<void> speak(String text) async {
    spokenText = text;
    if (fireCompletionOnSpeak) _onDone?.call();
  }
  @override
  Future<void> stop() async {}
  @override
  void setCompletionHandler(VoidCallback onDone) => _onDone = onDone;
  @override
  Future<void> setStyle(TtsStyle style) async {}
  @override
  Future<void> dispose() async {}
}
```

- [ ] **Step 2: Run the existing voice tests to capture the green baseline.** Run: `cd hearty_app && flutter test test/features/voice/`. Expected: PASS (records pre-refactor state). Note the count in Living State.

- [ ] **Step 3: Refactor `voice_provider.dart`.** Change imports and the field/constructor:

```dart
// remove: import 'package:flutter_tts/flutter_tts.dart';
import '../../../core/tts/tts_engine.dart';
import '../../../core/tts/tts_engine_factory.dart';
```

Replace the constructor TTS wiring (currently lines ~22–35) so it accepts `TtsEngine? ttsForTesting` and stores `TtsEngine _tts`. Because engine creation is async (factory does init), build the engine lazily: keep a `Future<void> _ready` that resolves once the engine is created and the completion handler attached. Replace `_initTts()`:

```dart
  final TtsEngine? _injectedTts;
  late TtsEngine _tts;
  late final Future<void> _ready;

  // in constructor body:
  _injectedTts = ttsForTesting;
  _ready = _initTts();

  Future<void> _initTts() async {
    _tts = _injectedTts ?? await createTtsEngine();
    _tts.setCompletionHandler(() {
      if (!mounted) return;
      if (_askFollowUp) {
        setAwaitingFollowUp();
      } else {
        dismiss();
      }
    });
  }
```

Update every `_tts.` call site to `await _ready` first where it must be ready (`_speakResponse`), and guard `stop()` calls (which may run before init) with a null/ready check. `_speakResponse` becomes:

```dart
  Future<void> _speakResponse(String response, bool askFollowUp) async {
    _askFollowUp = askFollowUp;
    await _ready;
    await _tts.speak(_prepareForSpeech(response));
  }
```

For `stopSpeaking`, `dismiss`, `primeForSymptomFollowUp`, `dispose`: call `_tts.stop()` only if `_ready` has completed; otherwise schedule after `_ready`. Keep `_prepareForSpeech`, `_stripEmojis`, and the `"4/10 → 4 out of 10"` logic untouched.

- [ ] **Step 4: Migrate the four test files.** In each, replace `class _FakeTts extends Mock implements FlutterTts {...}` and the `ttsForTesting: _FakeTts()` injection with `import 'fake_tts_engine.dart';` and `ttsForTesting: FakeTtsEngine()`. Remove now-unused `flutter_tts`/`mockito` imports where they were only for the TTS fake. Where a test asserts on spoken text, assert on `fake.spokenText`.

- [ ] **Step 5: Run the migrated tests.** Run: `cd hearty_app && flutter test test/features/voice/`. Expected: PASS, same count as the Step-2 baseline. If any test depended on synchronous TTS init, add `await Future.microtask(() {})` / pump as needed and note it.

- [ ] **Step 6: Run the full Flutter suite.** Run: `cd hearty_app && flutter test`. Expected: all pass.
- [ ] **Step 7: Commit.** `git add hearty_app/lib/features/voice/providers/voice_provider.dart hearty_app/test/features/voice/ && git commit -m "refactor: VoiceNotifier uses TtsEngine (neural default, system fallback)"`

**Living State — Task 1.5**
- Status: ⬜ Not Started
- Deviations (esp. any async-init test adjustments):
- Baseline test count / post-refactor count:
- Notes for later phases:

---

### Task 1.6: On-device verification of the integrated path

**Prompt:** Verify on a real Android device that the full voice flow now speaks through the neural engine, and that forcing a neural failure cleanly falls back to system TTS without breaking voice mode.

**Files:** none (manual verification + notes)

- [ ] **Step 1: Happy path.** Run: `cd hearty_app && make run` on a physical device. Trigger voice mode, speak a meal, confirm Hearty replies **in the stock neural voice** and that the follow-up listen still starts after speech ends (completion handler works end-to-end).
- [ ] **Step 2: Fallback path.** Temporarily rename the bundled model file (or point `modelAssetDir` at a bad path) to force `NeuralTtsEngine.init()` to fail; relaunch; confirm voice mode still works via system TTS. Restore the model.
- [ ] **Step 3: Record results** in `docs/superpowers/notes/2026-05-30-tts-spike-results.md` (append a "Phase 1 device verification" section).

**Living State — Task 1.6**
- Status: ⬜ Not Started
- Deviations:
- Notes for later phases:

---

## Phase 1R: Realignment Checkpoint

**Status:** ⬜ Not Started

- [ ] Re-read deviations across 1.1–1.6. Did Phase 1 deliver: neural default + working fallback + green tests + device-verified flow? If not, list the gap and fix before proceeding.
- [ ] If Task 1.3 deviations changed the model config class (Kokoro vs VITS) or API names, confirm **Phase 3 Task 3.1** still matches reality; edit it now if not.
- [ ] Confirm the spec's Section 5 (engine design) still describes what was actually built. Update the spec if the interface drifted.
- [ ] Confirm `flutter analyze` is clean across `lib/core/tts/`. Run: `cd hearty_app && flutter analyze`.
- [ ] **Checkpoint result (write one line):**

---

## Phase 2: Voice creation pipeline (workstation / pkix)

**Status:** ⬜ Not Started
**Goal:** Produce one `hearty_voice.onnx` (+ `tokens.txt`, + any `voices.bin`/`espeak-ng-data`) that hits the non-binary acoustic targets and sounds like Hearty, validated by a blind listening panel. This phase is independent of Phases 0/1 and runs on pkix.

**Environment:** pkix (RTX PRO 4000 Blackwell 24 GB). SSH/sftp + conda details in the `reference-pkix-server` memory. Work under `/data/hearty-voice/`. Activate the training env or create a dedicated one.

**Files (on pkix unless noted):**
- Create: `/data/hearty-voice/design/` (Qwen3-TTS design scripts + samples)
- Create: `/data/hearty-voice/corpus/` (synthetic corpus + transcripts)
- Create: `/data/hearty-voice/piper-train/` (training run)
- Create: `/data/hearty-voice/export/hearty_voice.onnx` (+ tokens)
- Create (repo): `docs/superpowers/notes/2026-05-30-voice-pipeline-log.md` (decisions, measurements, listening-panel results)

### Task 2.1: Stand up the design environment on pkix

**Prompt:** SSH to pkix, create a working dir and a conda env, install Qwen3-TTS (1.7B) and audio-analysis tooling (parselmouth/praat), and confirm the GPU is visible. Do not train anything yet.

- [ ] **Step 1: Connect.** `ssh -i ~/.ssh/pkix_training evan@192.168.1.220`. Confirm `nvidia-smi` shows the RTX PRO 4000 with 24 GB.
- [ ] **Step 2: Create env + dirs.**
```bash
mkdir -p /data/hearty-voice/{design,corpus,piper-train,export}
conda create -y -n hearty-voice python=3.10 && conda activate hearty-voice
pip install -U qwen-tts praat-parselmouth soundfile numpy
```
- [ ] **Step 3: Smoke-test Qwen3-TTS.** Generate one short sample with any built-in voice; confirm it writes a wav and uses the GPU (watch `nvidia-smi`). Record VRAM use.

**Living State — Task 2.1**
- Status: ⬜ Not Started
- Deviations (esp. actual package name/version for Qwen3-TTS, any CUDA/driver issues on Blackwell):
- Notes for later phases:

---

### Task 2.2: Design the target timbre + acoustic target-check gate

**Prompt:** Use Qwen3-TTS VoiceDesign to author candidate voices from text descriptions aimed at "warm, androgynous, mid-range, slight breathiness." For each candidate, generate ~5 varied sentences and **measure F0 (median) and F2** with parselmouth. Iterate the description until a candidate sits with median F0 in **145–175 Hz** with intermediate formants. This is a GATE — do not proceed to corpus generation until a candidate passes and you (and ideally the user) like how it sounds.

- [ ] **Step 1: Write `design/measure.py`** — loads a wav, prints median F0 (Praat autocorrelation, floor 75/ceil 300 Hz) and mean F1–F3 over voiced frames.
- [ ] **Step 2: Generate ≥4 candidate descriptions**, ~5 sentences each, into `design/cand_<n>/`.
- [ ] **Step 3: Measure all candidates** with `measure.py`; tabulate F0/F2 per candidate in the pipeline log.
- [ ] **Step 4: Gate check.** Pick the candidate(s) with median F0 in 145–175 Hz AND intermediate F2. If none qualify, refine descriptions and repeat. Record the winning description verbatim.
- [ ] **Step 5: User audition.** Send 2–3 winning samples to the user (sftp to dev machine, then surface). Get a thumbs-up on character before locking. (This honors "androgynous but distinctive" — the human ear, not just the numbers.)

**Living State — Task 2.2**
- Status: ⬜ Not Started
- Deviations:
- Winning voice description (paste verbatim) + measured F0/F2:
- Notes for later phases:

---

### Task 2.3: Generate the synthetic training corpus

**Prompt:** Using the locked voice from 2.2, synthesize a phonetically balanced corpus (~3–5 hours) with consistent prosody for distillation. Use a standard prompt set (LJSpeech transcript lines or CMU ARCTIC). Audition a handful of raw clips before generating the full set to catch teacher artifacts early (per the spec's synthetic-corpus risk).

- [ ] **Step 1: Fetch a transcript set** (LJSpeech metadata lines or ARCTIC prompts) into `corpus/transcripts.txt` (target ~3–5 h at the chosen speed → roughly 3,000–6,000 short utterances).
- [ ] **Step 2: Spot-generate 20 clips**, listen, confirm quality/consistency. If artifacts appear, adjust generation params or revisit 2.2. Record the decision.
- [ ] **Step 3: Batch-generate the full corpus** to `corpus/wavs/` with a matching `corpus/metadata.csv` in Piper/LJSpeech format (`id|transcript`). Resample to the rate Piper training expects (commonly 22.05 kHz) with soundfile.
- [ ] **Step 4: Validate corpus** — total duration, no clipped/empty files, transcript/audio counts match. Record totals.

**Living State — Task 2.3**
- Status: ⬜ Not Started
- Deviations:
- Corpus stats (hours, #utterances, sample rate):
- Notes for later phases:

---

### Task 2.4: Distill into a Piper/VITS voice

**Prompt:** Train a Piper (VITS) voice on the synthetic corpus. Piper→sherpa-onnx is the canonical, low-risk path (verified). Fits in 24 GB. Fine-tune from a Piper base checkpoint (e.g. an en_US medium voice) rather than training from scratch to save time and improve quality on a few hours of data.

- [ ] **Step 1: Preprocess** the corpus into Piper's training format (`python -m piper_train.preprocess ...` with the corpus dir, output dir, sample rate, single speaker).
- [ ] **Step 2: Fine-tune** from a base checkpoint (`python -m piper_train ... --resume_from_checkpoint <base.ckpt>`), batch size tuned to 24 GB VRAM. Monitor with `nvidia-smi`/logs.
- [ ] **Step 3: Periodically synthesize** a fixed validation sentence from checkpoints; stop when quality plateaus and the voice still measures in the neutral F0/F2 band (re-run `measure.py` on the student — distillation can shift the timbre; this is a checkpoint, not an afterthought).
- [ ] **Step 4: Pick the best checkpoint**; record step count and validation notes.

**Living State — Task 2.4**
- Status: ⬜ Not Started
- Deviations (esp. base checkpoint used, batch size, any Blackwell/CUDA build issues with piper-train):
- Student F0/F2 re-measurement:
- Notes for later phases:

---

### Task 2.5: Perceptual validation (blind listening panel) — GATE

**Prompt:** Run the real success test: a blind listening panel categorizes samples as male / female / neutral, and rates naturalness. This is the sufficient condition the spec defines; acoustic numbers were only necessary. Do not export/ship a voice that fails this gate.

- [ ] **Step 1: Render a test set** — ~10 varied sentences from the distilled voice (use real Hearty utterances, e.g. "Logged your lunch. How are you feeling?").
- [ ] **Step 2: Build a simple blind form** (e.g. samples + a 3-way gender choice + a 1–5 naturalness rating). Recruit N listeners (the co-launch collaborators + a few others is fine for an early panel; record N).
- [ ] **Step 3: Collect + tabulate.** **Gate:** gender judgments are roughly even / majority "neutral", AND mean naturalness is acceptable (define the bar in the log, e.g. ≥3.5/5). If it fails on neutrality → return to 2.2 (re-design). If it fails on naturalness only → return to 2.4 (more training / different base).
- [ ] **Step 4: Record panel results** in the pipeline log with the explicit pass/fail call.

**Living State — Task 2.5**
- Status: ⬜ Not Started
- Deviations:
- Panel N, results, pass/fail:
- Notes for later phases:

---

### Task 2.6: Export to ONNX and hand off

**Prompt:** Export the winning checkpoint to ONNX in the format sherpa-onnx consumes, pin the opset to sherpa-onnx's bundled ORT, verify it loads and synthesizes via the sherpa-onnx Python runtime on pkix (proves the artifact before it reaches the app), then sftp the artifact bundle to the dev machine.

- [ ] **Step 1: Export** the Piper checkpoint to ONNX (`python -m piper_train.export_onnx ...`), producing `hearty_voice.onnx` + the model's `tokens.txt`/config. Pin/verify the opset against sherpa-onnx's ORT (cf. wake-word opset12 lesson — verify, don't assume).
- [ ] **Step 2: Verify with sherpa-onnx Python** on pkix: `pip install sherpa-onnx`, load the exported model with `OfflineTtsVitsModelConfig`, synthesize a sentence to a wav, listen. This is the same runtime class the app uses — if it works here it will load on device.
- [ ] **Step 3: Re-measure** the exported voice's F0/F2 one last time (export should not change it, but confirm).
- [ ] **Step 4: Bundle + transfer.** `tar` the model dir (onnx + tokens + espeak-ng-data if Piper uses it) and sftp to the dev machine into `hearty_app/assets/tts/hearty-voice/`.
- [ ] **Step 5: Commit the pipeline log** (repo): `git add docs/superpowers/notes/2026-05-30-voice-pipeline-log.md && git commit -m "docs: voice creation pipeline log + listening-panel results"`. (The `.onnx` itself is committed in Phase 3.)

**Living State — Task 2.6**
- Status: ⬜ Not Started
- Deviations (esp. opset chosen, VITS vs Kokoro config class needed by sherpa-onnx for this export):
- Final artifact layout (file names/paths):
- Notes for later phases (Phase 3 Task 3.1 must point at THIS layout):

---

## Phase 2R: Realignment Checkpoint

**Status:** ⬜ Not Started

- [ ] Confirm the artifact passed BOTH gates (2.2 acoustic + 2.5 perceptual). If it shipped despite a soft fail, document why and get user sign-off.
- [ ] **Critical cross-track sync:** the exported voice's config class (VITS vs Kokoro) and file layout determine Phase 3 Task 3.1's code. Update Task 3.1 now to match 2.6's recorded layout. If the voice is Piper/VITS (expected), Task 3.1 uses `OfflineTtsVitsModelConfig`, NOT the Kokoro config used for the stock spike voice — make sure 3.1 reflects that.
- [ ] Confirm the spec's Section 6 still matches the pipeline actually run; update if steps changed.
- [ ] **Checkpoint result (write one line):**

---

## Phase 3: Real voice integration + conversation-style adaptation

**Status:** ⬜ Not Started
**Goal:** Swap the stock spike voice for the real `hearty_voice.onnx`, wire the Warm/Concise conversation-style toggle to delivery, and verify end-to-end on device. Requires Phases 1 and 2 complete.

**Files:**
- Modify: `hearty_app/pubspec.yaml` (bundle real voice, optionally drop stock voice)
- Modify: `hearty_app/lib/core/tts/neural_tts_engine.dart` (point at real voice; correct config class)
- Modify: `hearty_app/lib/features/voice/providers/voice_provider.dart` (apply style from prefs)
- Test: `hearty_app/test/features/voice/voice_provider_test.dart` (style propagation)

### Task 3.1: Point `NeuralTtsEngine` at the real voice

**Prompt:** Bundle the real voice from Phase 2 and update `NeuralTtsEngine` to load it. Use the model config class matching the exported model (per Phase 2R: VITS for a Piper-distilled voice). Keep the stock-voice fallback path only if useful; otherwise the system engine remains the sole fallback.

**Files:**
- Modify: `hearty_app/pubspec.yaml`
- Modify: `hearty_app/lib/core/tts/neural_tts_engine.dart`

- [ ] **Step 1: Register the real asset** in `pubspec.yaml` (`assets/tts/hearty-voice/` + any nested `espeak-ng-data/`). Remove the stock `kokoro-en` asset if no longer needed (smaller app).
- [ ] **Step 2: Update the default `modelAssetDir`** to `assets/tts/hearty-voice` and switch the config builder to match the export. For a Piper/VITS voice:

```dart
final vits = sherpa.OfflineTtsVitsModelConfig(
  model: '$dir/hearty_voice.onnx',
  tokens: '$dir/tokens.txt',
  dataDir: '$dir/espeak-ng-data',
);
final model = sherpa.OfflineTtsModelConfig(vits: vits, numThreads: 2);
```

- [ ] **Step 3: Run the engine tests.** Run: `cd hearty_app && flutter test test/core/tts/tts_engine_test.dart`. Expected: PASS (missing-dir/fallback tests unaffected).
- [ ] **Step 4: Commit** (includes the voice artifact). `git add hearty_app/assets/tts/hearty-voice hearty_app/lib/core/tts/neural_tts_engine.dart hearty_app/pubspec.yaml && git commit -m "feat: ship Hearty's custom non-binary voice"`

**Living State — Task 3.1**
- Status: ⬜ Not Started
- Deviations (config class actually used, artifact size):
- Notes for later phases:

---

### Task 3.2: Wire conversation style into delivery

**Prompt:** Apply the user's `conversationStyle` pref ('warm' / 'concise') to the engine before speaking, mapping it to `TtsStyle`. This is the v1 parameter-modulation approach (rate/speed), one voice. `voice_provider` already reads `prefs.conversationStyle` for the chat API call — reuse it.

**Files:**
- Modify: `hearty_app/lib/features/voice/providers/voice_provider.dart`
- Test: `hearty_app/test/features/voice/voice_provider_test.dart`

- [ ] **Step 1: Write the failing test** — that speaking with `conversationStyle: 'concise'` calls `setStyle(TtsStyle.concise)` on the engine. Extend `FakeTtsEngine` with a captured `TtsStyle? lastStyle` (set in `setStyle`). Construct `VoiceNotifier` with a `ref` whose `preferencesProvider` yields `conversationStyle: 'concise'`, drive a response, assert `fake.lastStyle == TtsStyle.concise`.
- [ ] **Step 2: Run to confirm it fails.** Run: `cd hearty_app && flutter test test/features/voice/voice_provider_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.** In `_speakResponse`, before `_tts.speak(...)`:

```dart
    final style = (_ref?.read(preferencesProvider).valueOrNull?.conversationStyle
            == 'concise')
        ? TtsStyle.concise
        : TtsStyle.warm;
    await _tts.setStyle(style);
```

- [ ] **Step 4: Run to confirm it passes.** Run: `cd hearty_app && flutter test test/features/voice/voice_provider_test.dart`. Expected: PASS.
- [ ] **Step 5: Full suite.** Run: `cd hearty_app && flutter test`. Expected: all pass.
- [ ] **Step 6: Commit.** `git add hearty_app/lib/features/voice/providers/voice_provider.dart hearty_app/test/features/voice/ && git commit -m "feat: map conversation style to TTS delivery"`

**Living State — Task 3.2**
- Status: ⬜ Not Started
- Deviations:
- Notes for later phases (if v1 rate-only modulation feels too flat in 3.3, that triggers spec Section 7 v2 = a second distilled voice; flag here):

---

### Task 3.3: End-to-end device verification

**Prompt:** Confirm on a real device that Hearty speaks in the custom voice, that Warm vs Concise sound distinct, and that fallback still works. Re-confirm the perceptual quality holds on phone speakers (not just studio playback).

**Files:** none (manual + notes)

- [ ] **Step 1:** `cd hearty_app && make run` on a physical device. Run the full voice flow; confirm the custom voice speaks and the follow-up loop still works.
- [ ] **Step 2:** Toggle conversation style in settings; confirm Warm vs Concise are audibly distinct. If indistinct, record it (triggers v2 decision per 3.2 notes).
- [ ] **Step 3:** Force neural failure (bad asset path); confirm system-TTS fallback; restore.
- [ ] **Step 4:** Append "Phase 3 device verification" to the notes doc with results.

**Living State — Task 3.3**
- Status: ⬜ Not Started
- Deviations:
- Notes:

---

## Phase 3R: Realignment Checkpoint

**Status:** ⬜ Not Started

- [ ] Confirm the shipped voice = the panel-validated voice from Phase 2 (no last-minute unvalidated swap).
- [ ] Confirm all gates honored end-to-end: privacy (no network synth), fallback works, tests green, device-verified.
- [ ] If Warm/Concise were indistinct (3.3), decide with the user: accept v1, or schedule v2 (second distilled voice). Record the decision.
- [ ] Update spec status to "Implemented"; reconcile any drift between spec and final build.
- [ ] **Checkpoint result (write one line):**

---

## Phase F: Final Project Realignment

**Status:** ⬜ Not Started

- [ ] **Walk every phase's Living State.** Collect all logged deviations into a single "what actually changed vs. plan" summary at the bottom of this file.
- [ ] **Goal check against the spec.** For each spec goal (non-binary timbre, on-device/offline, lightweight, style-adaptive, neural-default-with-fallback), point to the task that delivered it and the evidence (measurement/panel/device note). List any unmet goal and propose follow-up.
- [ ] **Cleanup.** No leftover spike code, no `// SPIKE`/`// TEMP` markers (`grep -rn "SPIKE\|TEMP" hearty_app/lib`), no orphaned stock-voice assets if unused, no debug routes.
- [ ] **Docs.** Spec marked Implemented; pipeline log + device-verification notes committed; memory updated (`project-nonbinary-voice`).
- [ ] **Finish the branch.** Invoke superpowers:finishing-a-development-branch to decide merge/PR.
- [ ] **Final result (write one line):**

---

## Deviation Summary (filled in during Phase F)

_(Running list of all deviations from this plan and why — populated as phases complete.)_
