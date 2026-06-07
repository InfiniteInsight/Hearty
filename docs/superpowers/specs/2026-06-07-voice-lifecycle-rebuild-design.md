# Voice Dictation Lifecycle Rebuild — Design Spec

**Date:** 2026-06-07
**Status:** Draft for review
**Author:** Evan + Claude
**Related:** supersedes the patch-on-patch history in
`2026-05-31-followup-listening-ding-fix-design.md`,
`2026-06-02-followup-beep-suppression-design.md`; builds on the prism waveform
(`2026-06-01-prism-waveform-voice-visualizer.md`).

---

## 1. Background & problem

Hearty has three voice flows, all driven by one `VoiceNotifier`
(`lib/features/voice/providers/voice_provider.dart`) + `VoiceOverlayScreen`:

1. **Wake-word dictation** — "Hey Hearty" → log a meal by voice.
2. **Conversation follow-up** — the AI asks a question, speaks it, reopens the
   mic, and listens for the answer (multi-turn until it closes).
3. **Post-meal notification check-in** — a scheduled notification opens the same
   listening UI to capture how the user feels.

All three are unreliable. On-device logcat repro (2026-06-06) confirmed the
**root cause is the STT engine**: Android's `SpeechRecognizer` (via the
`speech_to_text` plugin) is documented for "commands and short phrases, not
continuous spoken conversion," and **endpoints on any mid-sentence pause with
"no way to change that behaviour."** It truncates ("I had heartburn about a 2" →
"I had heartburn"), which makes the AI re-ask, which compounds into the
restart-beep churn and mic-handoff patches accreted over prior sessions. No
state-machine rework fixes truncation while on that engine.

Confirmed bugs the rebuild must fix:
1. **Truncation on pause** → re-asks / "doesn't pay attention."
2. **TTS/mic overlap** — the mic reopens while the AI is still speaking, so the
   recognizer transcribes the TTS audio.
3. **Mic contention** — the always-on wake-word foreground service holds the mic.
4. **Restart churn** — the "restart-and-accumulate" workaround beeps repeatedly
   and drops/duplicates words.
5. **Notification check-in mic never reliably opens** (stuck on "Getting ready…");
   tap-to-talk doesn't recover.
6. **"1–10" spoken as "one ten"** (TTS reads the en-dash literally).
7. **Screen sleeps** mid-dictation.

## 2. Goals / non-goals

**Goals**
- Keep the mic open through natural pauses and capture the *full* answer.
- One coherent, testable lifecycle shared by all three flows.
- Accuracy good enough that voice-logged foods/symptoms feed reliable insights.
- Preserve the app's privacy/offline posture (offline queue already exists).
- Behaviors the user confirmed: **auto-submit after 2.5 s of trailing silence by
  default** (tunable 2–5 s) with an **"always tap to submit"** opt-out; the
  **notification check-in always uses tap-to-confirm** (ambient safety); exactly
  one "mic hot" ding; half-duplex (don't listen while speaking).

**Non-goals**
- Hotword/keyword biasing — **rejected**: food/brand names are an open vocabulary,
  so a curated list is impractical to maintain (and tested poorly).
- Real-time streaming *to the cloud* — batch (record → submit) is enough for the
  record-then-submit lifecycle, and it's cheaper/simpler.
- Changing the chat/extraction backend logic (only a small TTS-text cleanup).

## 3. Engine decision — HYBRID (validated by spike, 2026-06-06)

A throwaway spike (`spike/sherpa-streaming-asr`) compared three engines on the
same phrases (see `memory/project-voice-stt-engine-research`):

| Engine | Accuracy | Notes |
|---|---|---|
| On-device sherpa 20M int8 | terrible | too small; rejected |
| On-device sherpa 67MB int8 (2023-06-26) | good, fumbles brands ("I KEU BAR") | real-time on Pixel 4a |
| On-device sherpa 122MB int8 (2023-02-21) | "a lot better" | real-time; chosen on-device model |
| Cloud Google STT (latest_long, batch) | best — nailed "IQ bar", digits | needs network |

**Decision: hybrid.**
- **Cloud (Google Cloud Speech-to-Text, batch) when online** — best accuracy on
  open food/brand vocab. Audio is sent to the **Hearty backend**, which proxies to
  Google (API key stays server-side; data-logging disabled). Pricing (verified
  2026): 60 free min/month per project; batch ~$0.004/min, streaming ~$0.016/min
  → effectively free at small scale, ~$120/mo at ~1000 users (batch). Google does
  not retain/train on audio unless data-logging is opted in (transient transit).
- **On-device (sherpa-onnx streaming Zipformer, 122 MB int8, 2023-02-21) when
  offline** — private, $0, fits the offline queue. Runs on a **background isolate**
  (mandatory — see §4.2 / §11).
- **Selection:** online → cloud; offline → on-device. User setting
  *"Use cloud transcription when online"* (default **on**).

Truncation is solved on both paths: on-device feeds a continuous stream with
endpointing disabled (we decide when the turn ends); cloud records the whole
utterance and sends it as one blob.

## 4. Architecture

### 4.1 `SttEngine` abstraction
A single interface so the lifecycle is engine-agnostic:

```
abstract class SttEngine {
  Future<void> start();                 // begin capturing
  Future<SttResult> stop();             // stop + return final transcript
  Stream<String> get partials;          // live interim text ('' if unsupported)
  Future<void> dispose();
}
class SttResult { final String transcript; final bool ok; final String? error; }
```

- **`OnDeviceSttEngine`** — owns the mic stream (`record`, PCM16 @ 16 kHz),
  forwards PCM to a **background isolate** running sherpa `OnlineRecognizer`
  (endpointing off), streams partials back via `SendPort`. `stop()` flushes and
  returns the final text. Model loaded once and kept warm.
- **`CloudSttEngine`** — owns the mic stream, buffers PCM to memory; `partials`
  is empty (show "Listening…/Transcribing…"); `stop()` POSTs the buffered audio
  to `POST /api/transcribe` and returns the transcript.

A `SttEngineFactory` picks the impl from connectivity + the user setting.

### 4.2 Background isolate (on-device) — the #1 risk
FFI pointers can't cross isolates, so the recognizer is **created and used
entirely inside one long-lived isolate**. The UI isolate sends PCM chunks and a
"finish" message; the worker sends back partials and the final transcript. This
removes the ANR the spike exhibited (8.4 s synchronous load + per-chunk decode on
the UI thread). **Verified first in implementation** before building the rest.

The 122 MB model is **not bundled** in the APK (keeps it lean). It is
**downloaded on first offline-need** (or first launch) into the app files dir and
cached; show a one-time progress indicator. (Cloud is the default online path, so
the on-device model is only required when offline.)

### 4.3 Mic ownership & wake-word handoff
Single mic owner at a time. Before any STT session: `WakeWordChannel.stopListening()`
+ a short settle delay; on session end (overlay dispose — the single chokepoint):
`WakeWordChannel.startListening()` to re-arm. Both engines share this.

### 4.4 Trailing-silence detection (drives the default auto-submit)
Because auto-submit (2.5 s trailing silence) is the **default** for dictation, a
**client-side silence detector runs on the mic PCM stream for BOTH engines** — it
fires the auto-submit when speech is followed by ≥ `autoSubmitSilenceSeconds` of
silence. Implementation: Silero VAD (via sherpa-onnx) or a lightweight RMS-energy
detector; it must only fire on **trailing** silence (after speech has started), so
pre-speech silence never submits. The same signal can drive a light ambient gate.
For the **notification check-in** (always tap-to-confirm) the detector is not used
to submit. When the user sets **"always tap to submit,"** the detector is disabled.

### 4.5 Half-duplex TTS gating
The mic never opens while TTS is playing. The lifecycle opens the mic only on the
TTS completion edge (`NeuralTtsEngine` already edge-detects completion). No AEC
(the Android hardware-AEC claim was refuted; half-duplex is the verified path).

## 5. The unified lifecycle (state machine)

```
idle
  → listening        (mic open; on-device shows live partials, cloud records;
                      ONE ding on entry; "MIC LIVE" indicator; transcript shown
                      live + editable; stays open through pauses shorter than the
                      auto-submit threshold; safety cap ~2 min → review)
  → submit           DEFAULT (dictation): AUTO-SUBMIT after
                      `autoSubmitSilenceSeconds` (2.5 s) of TRAILING silence.
                      ALSO always available: user taps **Send**.
                      EXCEPTIONS — require an explicit tap (no auto-submit):
                      (a) the notification check-in, (b) `autoSubmit = off`.
                      Re-record + "Or type here…" text fallback always available.
  → thinking         (POST /api/chat)
  → responding       (TTS speaks reply; mic stays closed — half-duplex)
  → awaitingFollowUp (only if the reply ends with '?'; loops back to listening
                      via the TTS-completion edge)
  → idle             (reply was not a question → dismiss after speaking)
```

**Flow mapping:**
- **Flow 1 (wake word):** wake → listening → review → thinking → responding.
  Reopen mic for a follow-up **only when the reply is a question** (fixes the
  always-reopen bug).
- **Flow 2 (conversation):** the awaitingFollowUp ↔ listening loop above. Pauses
  no longer truncate; submission is user-driven (or auto-submit).
- **Flow 3 (notification check-in):** notification → opens overlay directly in
  `listening` for the symptom check-in (meal locked, `symptom_followup=true`).
  Question shown on screen; **spoken aloud only if the user enabled it** (default
  off). One ding. tap-to-confirm guards against ambient pickup. Never invent a
  meal if the meal id is missing (backend guard).

## 6. UI / UX (VoiceOverlayScreen)
- **One ding** when the mic goes hot; never a per-restart beep.
- **"MIC LIVE"** indicator so the user knows it's listening (the prism waveform
  drives off live level on-device; cloud shows a recording indicator).
- **Transcript is live + editable while listening**; a **Send** button is always
  present (primary action), plus **Re-record** and the existing **"Or type here…"**
  text field (full manual fallback). Auto-submit (when active) sends after the
  silence threshold; otherwise the user taps Send.
- **Keep screen on** while the overlay is active (`wakelock_plus`); released on
  dispose.
- No more stuck "Getting ready…": if an engine fails to start, surface an error +
  the tap-to-talk / text fallback, never a dead spinner.

## 7. Backend changes
- **New: `POST /api/transcribe`** — accepts audio (LINEAR16 16 kHz, base64 or
  multipart), proxies to Google Cloud STT (`latest_long`, punctuation on,
  data-logging off), returns `{ transcript }`. Key stored server-side. Auth via
  the existing JWT. Errors → JSON error so the client can fall back.
- **Minor: chat prompt cleanup** — stop emitting en-dash ranges ("1–10") in the
  assistant text where avoidable (defense-in-depth alongside the client TTS fix).
- `/api/chat` logic otherwise unchanged. Add the **null-meal-id guard** so a
  `symptom_followup` turn never inserts a new meal.

## 8. New settings (UserPreferences)
- `useCloudWhenOnline: bool` (default **true**).
- `autoSubmit: bool` (default **true**). Off = "always tap to submit" (manual).
- `autoSubmitSilenceSeconds: double` (default **2.5**, range **2.0–5.0**).
- `speakCheckInQuestion: bool` (default **false**).
(These persist via the existing preferences provider/endpoint.)

**NOTE:** the post-meal **notification check-in always uses tap-to-confirm**
regardless of `autoSubmit` (ambient-pickup safety in an unknown environment).
Auto-submit applies only to wake-word / in-app dictation. There is also a ~2-min
**safety cap** on any open mic so a forgotten session can't run indefinitely.

## 9. Independent fixes folded in
- `_prepareForSpeech`: convert "1–10" / "1-10" → "1 to 10" (range), keeping the
  existing "4/10" → "4 out of 10" (rating).
- Wakelock while overlay active.
- Flow 1 `sendToChat` uses `reply.endsWith('?')` to gate the follow-up.
- Flow 3 notification body tells the user it will listen for a reply.

## 10. Error handling & fallbacks
- **Cloud network failure/timeout** → fall back to on-device for that turn, or
  queue the audio if both unavailable (reuse the offline voice queue).
- **Isolate/model load failure** (on-device) → error + text-entry fallback.
- **Mic acquisition failure** → release/retry the wake-word handoff once, then
  surface tap-to-talk.
- **Empty/garbage transcript** → stay in `review`; never auto-submit nothing.

## 11. Risks & verify-early
1. **Background-isolate ASR with FFI** — prove a no-ANR PoC first (load in isolate,
   stream PCM, get partials). Highest risk.
2. **On-device model download/caching** (125 MB) — size, progress UX, retry.
3. **Cloud latency/UX** — batch transcription happens after Stop; keep the
   "transcribing…" state snappy; set a timeout + fallback.
4. **Mic handoff** with the wake-word service across both engines.
5. **Pixel 4a perf** running on-device ASR + (optional) VAD concurrently.

## 12. Suggested phasing (for the implementation plan)
- **P0 — Isolate PoC:** sherpa streaming on a background isolate, no ANR. Gate.
- **P1 — Lifecycle + on-device engine:** new state machine, `SttEngine`,
  `OnDeviceSttEngine`, **auto-submit (2.5 s trailing-silence detection) + manual
  Send**, one ding, half-duplex, wakelock, mic handoff. Wire Flows 1 & 2. Retire
  the truncation/restart patches.
- **P2 — Cloud engine + backend:** `/api/transcribe`, `CloudSttEngine`, selection
  policy + `useCloudWhenOnline`, network fallback.
- **P3 — Flow 3 + settings + polish:** notification reliability, configurable
  spoken question, auto-submit setting, "1 to 10" + prompt cleanup, ambient
  rejection, null-meal-id guard.
- **P4 — Remove `speech_to_text`** once both engines are proven.

## 13. Testing
- Unit: state-machine transitions; selection policy (online/offline × setting);
  "1 to 10" conversion; endsWith('?') gating; null-meal-id backend guard.
- Widget: overlay states (listening / review / responding / error); tap-to-confirm;
  text fallback.
- Integration/device: full Flow 1/2/3 on the Pixel 4a, online + airplane-mode
  (forces on-device), pause-mid-sentence, ambient noise, wake-word re-arm.

## 14. Open questions
- On-device model: ship the 122 MB int8, or evaluate a newer/better streaming
  model before P1? (122 MB validated; revisit only if a clearly better one exists.)
- Cloud: Google STT **v1 recognize** (used in spike) vs **v2** for production
  (v2 has newer models / per-second billing) — decide in P2.
- Auto-submit default is 2.5 s (range 2–5 s); fine-tune the exact feel on device.
  The notification check-in is tap-only for now — could add a per-check-in
  auto-submit opt-in later if users ask.

## 15. Out of scope / cleanup
- The spike branch `spike/sherpa-streaming-asr` and its throwaway screen / routes /
  Settings entry are reference-only; production code is built fresh (likely a new
  feature branch off master). Remove the spike artifacts when P1 lands.
- On-device test models pushed to the device (`asr-model`, `asr-model-122`) are
  spike-only.
