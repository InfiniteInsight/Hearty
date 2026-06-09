# Voice Rebuild — Phase D: On-Device Batch STT as Default (Moonshine), Swappable to Parakeet

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make a single **on-device batch** speech-to-text engine the default capture path — **Moonshine base.en int8** by default (small, fast to load), **Parakeet-TDT swappable via one setting** for higher accuracy — and turn the cloud path **dormant** (kept in code, never selected unless re-enabled). One private, $0, offline engine for all three voice flows.

**Why this shape (from the on-device spike, `2026-06-07-voice-rebuild-whisper-ondevice-spike.md`):** On the Pixel 4a, **Parakeet** cleared the accuracy+latency gate outright (nailed "IQ bar"/digits, ~1–2 s decode) but is **631 MB with a ~20 s cold load**. **Moonshine** is **275 MB, ~3–4 s load, faster decode**, and — with **normalize+pad preprocessing** — went from ~4/8 to ~7/8 on quiet/short clips; its residual failure is an occasional **empty** on the shortest words, which the existing empty-transcript guard already routes to manual re-entry (no corrupt data). Given the size/load gap, **Moonshine is the default**; Parakeet is the accuracy fallback, selectable without a rewrite because both are the same sherpa `OfflineRecognizer` behind one `kind` parameter.

**Architecture:** A new `OnDeviceBatchSttEngine implements SttEngine` — owns the `record` PCM16 mic, buffers (60 s cap, like `CloudSttEngine`), and on `stop()` **normalize+pads** the audio then decodes it via a long-lived **batch ASR isolate** (`OfflineRecognizer`, parameterized by model `kind` + paths — productionizes the spike isolate). `partials` is empty (batch). A pure `OnDeviceModel` registry maps a `useOnDeviceModel` setting → `{kind, dir, filenames, downloadUrl}`. An `AsrModelManager` downloads+caches the selected model on first use and **keeps the recognizer warm** (preload once, reuse across sessions) to hide load time. `SttEngineSelector`/`VoiceNotifier._selectEngine` are rewired: default → on-device batch; cloud only if explicitly re-enabled.

**Tech Stack:** Flutter/Dart, `sherpa_onnx ^1.13.2` (`OfflineRecognizer` + Whisper/Moonshine/transducer configs), `record`, `dio` (model download), `path_provider`, `dart:isolate`. Reuses `SttEngine`, `SilenceDetector`, `SttEngineSelector` from B/C.

**Spec:** Realizes the on-device branch of `2026-06-07-voice-lifecycle-rebuild-design.md` and closes its §14 open question (model choice) with the spike's evidence. Supersedes the earlier informal "Plan D" sketch (settings UI / model download / remove `speech_to_text`), folding those in. Prereq: Plans A/B/C merged.

**Key decisions (settled up front):**
1. **Default = Moonshine base.en int8** (275 MB, ~3–4 s load). **Parakeet-TDT 0.6b int8** (631 MB, ~20 s load) selectable via the `useOnDeviceModel` setting. Both run through ONE engine + ONE isolate (the `kind` param picks the config) — swapping is a setting flip + a model download, **not** a code change.
2. **Batch ⇒ no live partials. DECIDED (user, 2026-06-07): Option A — batch only, no live text preview.** Rationale: a live preview would come from the *Zipformer* while the final comes from Moonshine/Parakeet, so the on-screen text could change/correct itself — worse than no preview. A keeps the displayed transcript **truthful to what was actually transcribed** (shown after `stop()`). The streaming Zipformer (Plan B `OnDeviceSttEngine` + `asr_isolate.dart`) is **retired** (kept dormant in-tree; optional removal in D5 Step 4). The **prism waveform survives** (amplitude-driven) so "I'm listening" feedback remains; only the live text-as-you-speak goes away. (Rejected Option B: run Zipformer alongside for live preview, +122 MB + two resident engines fighting the wake-word service for RAM.)
3. **Cloud kept dormant, not deleted.** `CloudSttEngine` + `/api/transcribe` stay in the codebase; `useCloudWhenOnline` **defaults to false** and the selector skips cloud. Re-enabling is a one-flag change (no re-implementation) — the escape hatch if on-device accuracy disappoints in the field.
4. **Normalize+pad in the engine** (peak-normalize to 0.95 + lead/trail silence to ≥1.5 s) — the spike-proven fix for Moonshine's quiet/short-clip blanks; harmless to Parakeet. **Empty transcript still → manual fallback** (the C-phase `submit()` guard), so a residual blank re-prompts rather than logging nothing.
5. **Keep-warm:** the recognizer is created once (preloaded after first launch / first grant) and reused; per-session cost is just mic + decode, so even Parakeet's 20 s load is paid once, in the background.

---

## File structure

| File | Responsibility |
|---|---|
| `lib/core/stt/pcm_utils.dart` | pure `pcm16ToFloat32` + `normalizeAndPad` (peak-norm + silence pad) |
| `lib/core/stt/on_device_model.dart` | `OnDeviceModel` enum/registry: kind, dir, filenames, download URL/size |
| `lib/core/stt/batch_asr_isolate.dart` | long-lived `OfflineRecognizer` isolate (productionized spike isolate; `kind`-parameterized) |
| `lib/core/stt/on_device_batch_stt_engine.dart` | `OnDeviceBatchSttEngine implements SttEngine` (mic + buffer + normalize+pad + isolate) |
| `lib/core/stt/asr_model_manager.dart` | first-run download + cache + **keep-warm** preload of the selected model |
| `lib/core/stt/stt_engine_selector.dart` | (modify) default to on-device batch; cloud only if re-enabled |
| `lib/features/voice/providers/voice_provider.dart` | (modify) `_selectEngine` builds the batch engine via the manager; read model setting |
| `lib/core/api/models/user_preferences.dart` | (modify) add `useOnDeviceModel` + persist the C-phase voice settings |
| `lib/features/settings/screens/voice_settings_screen.dart` | model picker + auto-submit + (advanced) cloud toggle |
| `test/core/stt/pcm_utils_test.dart` | normalize+pad unit tests |
| `test/core/stt/on_device_model_test.dart` | registry mapping tests |
| `test/core/stt/on_device_batch_stt_engine_test.dart` | buffer/normalize/decode-callback tests (fake decode) |
| `test/core/stt/stt_engine_selector_test.dart` | (extend) on-device-default selection truth table |

---

## D1 — Pure preprocessing + model registry

### Task D1.1: `pcm_utils.dart` (normalize + pad) — TDD

- [ ] **Step 1: failing test** (`test/core/stt/pcm_utils_test.dart`): peak-normalize scales the max sample to ~0.95; quiet input is boosted, full-scale input unchanged; output length ≥ 1.5 s (24000 @ 16 kHz) with leading + trailing zeros; all-silence input returns silence (no divide-by-zero).
- [ ] **Step 2: implement**

```dart
import 'dart:typed_data';

Float32List pcm16ToFloat32(Uint8List bytes) { /* as in CloudSttEngine */ }

/// Peak-normalize to [targetPeak] (SNR-preserving) and pad with [leadMs]+trailing
/// silence to at least [minMs]. Fixes quiet/short-clip blanks (esp. Moonshine).
Float32List normalizeAndPad(Float32List s,
    {double targetPeak = 0.95, int sampleRate = 16000, int leadMs = 100, int minMs = 1500}) {
  var peak = 0.0;
  for (final v in s) { final a = v.abs(); if (a > peak) peak = a; }
  final gain = peak > 1e-4 ? targetPeak / peak : 1.0;
  final lead = leadMs * sampleRate ~/ 1000;
  final minLen = minMs * sampleRate ~/ 1000;
  final total = (lead * 2 + s.length) < minLen ? minLen : lead * 2 + s.length;
  final out = Float32List(total);
  for (var i = 0; i < s.length; i++) out[lead + i] = s[i] * gain;
  return out;
}
```

- [ ] **Step 3: test green; commit.**

### Task D1.2: `OnDeviceModel` registry — TDD

- [ ] **Step 1: failing test** (`on_device_model_test.dart`): `OnDeviceModel.moonshine` is the default; each value resolves to the correct `kind` (`'moonshine'`/`'transducer'`), dir name, expected filenames, and a download URL + approx size; `fromPrefString`/`toPrefString` round-trip (unknown → moonshine).
- [ ] **Step 2: implement** — an enum with a const data table:

```dart
enum OnDeviceModel { moonshine, parakeet }

class OnDeviceModelSpec {
  const OnDeviceModelSpec({required this.kind, required this.dir,
    required this.files, required this.downloadUrl, required this.approxMb});
  final String kind; // 'moonshine' | 'transducer'
  final String dir;  // <externalFiles>/<dir>
  final Map<String, String> files; // logical key -> filename
  final String downloadUrl; // sherpa-onnx release .tar.bz2
  final int approxMb;
}

const onDeviceModelSpecs = <OnDeviceModel, OnDeviceModelSpec>{
  OnDeviceModel.moonshine: OnDeviceModelSpec(
    kind: 'moonshine', dir: 'asr-moonshine-base', approxMb: 275,
    downloadUrl: 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-moonshine-base-en-int8.tar.bz2',
    files: {'preprocessor': 'preprocess.onnx', 'encoder': 'encode.int8.onnx',
      'uncachedDecoder': 'uncached_decode.int8.onnx', 'cachedDecoder': 'cached_decode.int8.onnx',
      'tokens': 'tokens.txt'}),
  OnDeviceModel.parakeet: OnDeviceModelSpec(
    kind: 'transducer', dir: 'asr-parakeet-tdt', approxMb: 631,
    downloadUrl: 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8.tar.bz2',
    files: {'encoder': 'encoder.int8.onnx', 'decoder': 'decoder.int8.onnx',
      'joiner': 'joiner.int8.onnx', 'tokens': 'tokens.txt'}),
};
```

> Filenames verified against the pushed spike models. Hosting note: pulling the .tar.bz2 straight from the sherpa-onnx GitHub release is fine for v1; mirror to our own storage later if release churn is a concern.

- [ ] **Step 3: test green; commit.**

---

## D2 — Batch engine + model manager (keep-warm)

### Task D2.1: `batch_asr_isolate.dart` (productionize the spike isolate)

- [ ] **Step 1: write** the isolate from `whisper_spike_isolate.dart` (already `kind`-parameterized for whisper/moonshine/transducer). Protocol: `['init', kind, paths, numThreads] → ['ready']`; `['decode', Float32List] → ['result', text]`; `['dispose']`. Keep the recognizer warm across decodes (created once on init). (Drop the whisper branch if only moonshine/parakeet ship, or keep it — harmless.)
- [ ] **Step 2: analyze.** (FFI-in-isolate is device-verified, not unit-tested.)
- [ ] **Step 3: commit.**

### Task D2.2: `OnDeviceBatchSttEngine` — TDD (logic) + device (native)

Mirror `CloudSttEngine` exactly, but decode locally via the isolate instead of POSTing. Reuse the buffer + 60 s cap + `SilenceDetector` auto-submit. On `stop()`: `normalizeAndPad` the buffer, send to the (already-warm) isolate, await `['result']`.

- [ ] **Step 1: failing test** (`on_device_batch_stt_engine_test.dart`) — inject a fake `decode` callback (the test seam, like Cloud's `transcribe`): `ingestForTest` PCM → `stop()` returns the decoded text; the buffered samples passed to decode are normalize+padded; empty decode → `SttResult(transcript:'')` (the lifecycle guard handles empty). Lazy `AudioRecorder` (constructed in `start`) so logic is unit-testable.
- [ ] **Step 2: implement** — constructor takes a warm `decode` function (from the manager) + `silenceSeconds`; `record` mic in `start`; `stop()` = stop mic → `normalizeAndPad(buffer)` → `decode(samples)` → `SttResult`.
- [ ] **Step 3: test green; analyze; commit.**

### Task D2.3: `AsrModelManager` — download, cache, keep-warm

- [ ] **Step 1: implement**
  - `ensureModel(OnDeviceModel)`: if the spec's files exist under `<externalFiles>/<dir>`, return paths; else download the `.tar.bz2` (dio, progress callback), extract, verify files, cache. **Validate before use** — checksum (or at minimum a size check + a try/catch around recognizer init that deletes and re-downloads on failure) so a partial/corrupt `.tar.bz2` re-downloads instead of crashing on load. Returns resolved paths or a typed failure.
  - `warmRecognizer(OnDeviceModel)`: spawn `batch_asr_isolate`, `init` once, hold the `SendPort`; expose `decode(Float32List) → Future<String>` and `warmDecodeOrNull(model)` (non-null only when that model is warm). Idempotent; on model change, dispose the old isolate and warm the new one.
  - **Ownership:** the **manager owns the warm isolate**, NOT the engine. `OnDeviceBatchSttEngine.dispose()` tears down only its mic + partials — it must **never kill the manager's isolate**, or keep-warm is defeated every session. State this in D2.2.
  - **RAM-aware keep-warm (the warm isolate holds ~275 MB Moonshine / ~600 MB+ Parakeet resident):** on a 6 GB Pixel 4a this coexists with the always-on wake-word foreground service. Prefer **warm-on-first-session + release after an idle timeout** (e.g. a few minutes), rather than permanent residency — especially for Parakeet. Re-warm lazily on the next session (out-of-band, not in `_openSession`).
- [ ] **Step 2:** unit-test the path-resolution/validation/extraction-decision logic (mock filesystem presence); download + isolate are device-verified.
- [ ] **Step 3: commit.**

> **Download UX:** first run shows a one-time "Setting up on-device voice (≈275 MB)…" progress; until done, capture falls back to text entry (or cloud if a user re-enabled it). Moonshine's 275 MB keeps this short; Parakeet's 631 MB is only paid if the user opts into it.

---

## D3 — Selection rewire (on-device batch default; cloud dormant)

### Task D3.1: settings field + selector

- [ ] **Step 1:** add `useOnDeviceModel` (default `OnDeviceModel.moonshine`) to `UserPreferences` (+ persist the C-phase `useCloudWhenOnline` (default **false**), `autoSubmit`, `autoSubmitSilenceSeconds`). Backend `preferences` model + a migration for the new columns.
- [ ] **Step 2:** extend `SttEngineSelector` test: with `useCloudWhenOnline=false` (default) → always on-device regardless of connectivity; cloud only when a user set it true AND online. Keep `useCloud(online, useCloudWhenOnline)` pure.
- [ ] **Step 3:** rewire `VoiceNotifier._selectEngine`. **CRITICAL: never download inside the capture path.** `_selectEngine` only ever consumes an **already-ready, already-warm** model; if it isn't ready it **fast-fails to `_pauseForManual`** (text entry) — it must not `await` a 275–631 MB download while the user is staring at "preparing". Downloading + warming happen out-of-band (app start / settings change, Task D2.3 preload), with their own progress UI.

```dart
Future<SttEngine> _selectEngine() async {
  if (_useCloudWhenOnline && await _isOnline()) {
    return CloudSttEngine(silenceSeconds: _silenceSeconds, transcribe: ...); // dormant by default
  }
  final decode = _modelManager.warmDecodeOrNull(_onDeviceModel); // null if not ready
  if (decode == null) {
    _modelManager.ensureAndWarm(_onDeviceModel); // kick off in background, don't await
    throw const SttNotReadyException(); // _openSession catch → _pauseForManual (text entry)
  }
  return OnDeviceBatchSttEngine(silenceSeconds: _silenceSeconds, decode: decode);
}
```

> `_openSession`'s existing engine-start `catch` already drops to `_pauseForManual`; route `SttNotReadyException` there too so a not-yet-downloaded model degrades to text entry, never a hung spinner.

- [ ] **Step 4:** voice-provider tests still green (injected `engineFactory` bypasses selection); add tests: default prefs → on-device batch chosen; **model-not-ready → `_pauseForManual`, no download awaited in `_openSession`**. Commit.

---

## D4 — Settings UI

### Task D4.1: `dictation_settings_screen.dart`

> Built as a **new** `dictation_settings_screen.dart` at `/settings/dictation`,
> kept separate from the existing TTS-output picker at `/settings/voice`.

- [x] **Step 1:** a real Settings screen with:
  - **Transcription model:** Moonshine (default, "smaller & faster") · Parakeet ("larger, most accurate — ~631 MB download"). Switching downloads + warms via the shared `asrModelManagerProvider`; **persist-after-ready** so a failed download keeps the working model selected (snackbar + tiles disabled mid-switch + "limited until ready" progress row).
  - **Auto-submit:** on/off + the 2–5 s silence slider (default 2.5).
  - **Advanced → Use cloud when online:** default off; on = re-enable the dormant `CloudSttEngine`.
- [x] **Step 1b (advisor — close the dead-UI gap):** wire *consumption* — `_selectEngine` reads `prefs.autoSubmitSilenceSeconds` (was hardcoded); `_openSession` gates `onAutoSubmit` on `_effectiveAutoSubmit` (`prefs.autoSubmit`), constructor values as no-prefs/test fallback. `asrModelManagerProvider` is keepAlive; `voiceProvider` shares it.
- [x] **Step 2:** widget tests (toggles/persistence/model-switch success+failure, fake manager) + voice_provider auto-submit-consumption tests. 138 green. Committed.

---

## D5 — Device verify, teardown, cleanup

> **RESOLVED 2026-06-08/09 (Pixel 4a).** Gate outcome: Moonshine FAILED the
> short-word blank gate (blanked "bloating"/"eight"/"nausea" — seq2seq greedy
> early-EOS, no sherpa config fix). Parakeet-0.6b was accurate but ~2.9 GB total
> PSS warm → OOM-reaped under multitasking. The fix turned out to be the
> **transducer/CTC architecture, not size** → trialled lighter models and shipped
> **Parakeet-110m (`nemo-ctc`) as the default**: 0.6b-grade accuracy (casing +
> punctuation, nailed bloating/nausea/brands), ~1.29 GB total PSS (1.83 GB free,
> no swap, no reap), faster decode. 0.6b kept as the heavy max-accuracy option;
> Moonshine + Zipformer-GigaSpeech dropped. Bugs surfaced (tracked separately):
> prism waveform flat during dictation, off-topic refusal still logs a meal,
> wake-word misbehaves after app reap/restart.

- [x] **Step 1: DEVICE VERIFY (gate)** — done; see resolution above (preload fires
  on launch + coalesces; RAM measured per-model; gate flipped default by data).
  - **Moonshine default, first run:** model downloads (~275 MB), then Flows 1/2/3 transcribe; keep-warm hides load after first launch.
  - **Proactive preload (wired in `_ScaffoldWithNavBar._prewarmDictation`, advisor pt 1):** confirm the background `ensureAndWarm(defaultModel)` actually fires on launch (mic-granted) so the **first** voice tap finds Moonshine ready (or, if the user beats the download, that it cleanly drops to manual — not a dead spinner). Watch logs to confirm the capture-path `ensureAndWarm` *coalesces* with the preload (no double 275 MB download) — this is the in-flight-guard path.
  - **BLANK-RATE GATE (default-flipping, measured on the REAL capture path — not replayed clips):** the spike's worst case was short symptom words — Moonshine blanked on "acid reflux"/"bloating" ~25% of takes *with* normalize+pad. Those are core journal utterances, so measure it for real: speak the short symptom set (**"bloating", "acid reflux", "nausea", "cramps", "a 2"**) **≥10 takes each across both household voices** through the actual Flow-1 mic path, and count empties. **If Moonshine's blank rate >10%, ship Parakeet as the default instead** (flip `OnDeviceModel.defaultModel` to `parakeet`; Moonshine becomes the selectable option). **When you flip it, also swap the two `OnDeviceModel.blurb` strings** — Moonshine's currently says "recommended" and Parakeet's "~631 MB download", which read backwards once Parakeet is the default. (The backend migration default + Pydantic Literal default would also need flipping to keep client/server parity.) *Counterweight to check:* production clips run until the 2.5 s trailing-silence auto-submit, so real audio is speech + ≥2.5 s — never the sub-second fragments the spike fast-tapped, so the real rate may be far below 25%. The gate decides it with data instead of assuming.
  - **Switch to Parakeet** in Settings: downloads (~631 MB), re-warms; confirm the ~20 s load is paid **once, in the background** (not per session) and accuracy improves on brands.
  - **Keep-warm vs wake-word (RAM):** with the recognizer warm AND the wake-word foreground service running, confirm neither is killed under memory pressure (background the app, open a few others, return) — especially for Parakeet. If it gets killed, switch to warm-on-session + idle-release (D2.3).
  - **Steady-state launch burst (advisor pt 1):** the preload spawns the isolate + loads the model into RAM on **every** launch (a fresh process = a fresh keepAlive `AsrModelManager`), even sessions where voice is never used — and that burst coincides with the wake-word service. Verify an **everyday launch with voice unused** survives the 275 MB Moonshine warm (and the 631 MB Parakeet warm) without either being killed; the 3-min idle timer reclaims it but the launch-time spike is the risk. If it gets killed, that's the trigger for warm-on-session + idle-release (don't pre-empt — it's a device-data call).
  - No ANR; one ding; half-duplex; auto-submit ~2.5 s — all still hold.
- [x] **Step 2: teardown the spike** — deleted `whisper_spike_screen.dart`, `whisper_spike_isolate.dart`, `asr_isolate_probe_screen.dart`, the `/whisper-spike` + `/isolate-probe` routes, the debug Settings tiles, `scripts/spike-download-push-models.sh`, and the on-device `spike-*` + `spike-wavs` dirs + logs.
- [x] **Step 3: remove `speech_to_text`** from `pubspec.yaml` (fully unused). `flutter analyze` clean + 138 tests green.
- [x] **Step 4: retire the streaming Zipformer** (Option A decided — no live partials) — deleted `on_device_stt_engine.dart` + `asr_isolate.dart` + `asr_model_locator.dart` (already orphaned, no importers) and the on-device `asr-model`/`asr-model-122` dirs.

---

## Self-review

- **Honors the brief:** Moonshine is the **default** (size/load win the user called out); Parakeet is a **one-setting swap** (same engine + isolate, `kind`-parameterized — no rewrite), enabled by the `OnDeviceModel` registry + `AsrModelManager`; cloud is **dormant** (code kept, `useCloudWhenOnline` default false), re-enabled by a flag.
- **Moonshine's weakness mitigated, not ignored:** normalize+pad (spike-proven ~4/8→7/8) in the engine; residual empties route to manual re-entry via the existing `submit()` guard (no corrupt data); if blanks still annoy in the field, Settings → Parakeet is one tap.
- **Reuses the abstractions:** `SttEngine`, `SilenceDetector`, `SttEngineSelector`, the `CloudSttEngine` shape (buffer→stop), and the spike isolate — minimal new surface; the batch engine is the Cloud engine with a local decode.
- **No-partials tradeoff stated** (batch), consistent with the already-shipped cloud path; Zipformer retirement is explicit and reversible.
- **Type/name consistency:** `decode(Float32List)→Future<String>` is the engine's injected seam (mirrors Cloud's `transcribe`); `normalizeAndPad`/`pcm16ToFloat32` shared in `pcm_utils`; isolate protocol matches the spike's; `useCloud(online,useCloudWhenOnline)` unchanged.
- **Risk/uncertainty:** real-world blank rate for Moonshine across voices is the thing only field use settles (the spike was 8 phrases) — hence Parakeet kept one tap away and cloud one flag away. First-run download size/UX and keep-warm timing are device-verified in D5.
