# Hearty Non-Binary On-Device Voice — Design Spec

**Date:** 2026-05-30
**Status:** Approved design, ready for implementation planning
**Scope:** Replace Hearty's spoken voice (currently the phone's built-in TTS) with a
custom, distinctive, gender-neutral neural voice that runs fully on-device with no
API calls, falling back to system TTS where the neural engine can't run.

---

## 1. Goal & Motivation

Hearty speaks aloud during its hands-free voice-mode flow. Today it uses the phone's
built-in OS text-to-speech (via `flutter_tts`), so the voice is whatever Google/Android
ships. We want a voice that is:

- **Non-binary / gender-ambiguous** — most listeners cannot confidently call it male or
  female. Target persona is "androgynous but distinctive": a memorable voice with its own
  character, not a statistically-averaged blur.
- **On-device & offline** — synthesis runs on the phone, no network round-trip, no third
  party sees the user's spoken food/symptom data. (For a health journal this is a privacy
  requirement, not just a nicety — system "network" voices send text to Google's servers.)
- **Lightweight** — must run on a real mid-range Android without melting the battery.

### Background research

Grounded in CHI 2023, *"Creating Inclusive Voices for the 21st Century: A Non-Binary
Text-to-Speech for Conversational Assistants"* (ACM DOI 10.1145/3544548.3581281), and
the earlier "Q" / SAM gender-neutral voice projects.

Key findings that shape the acoustic targets:

- **Fundamental frequency (F0 / pitch):** the gender-neutral band is ~**145–175 Hz**.
  Necessary but **not sufficient** — the perceptual male/female crossover is
  *speaker-specific*, so a fixed pitch number alone never guarantees neutrality.
- **Formant frequencies (esp. F2):** encode perceived vocal-tract length. After pitch,
  this is the strongest lever; two voices at identical pitch can read as different genders
  based on formants.
- **Spectral cues** (center of gravity / spectral tilt, breathiness): also shift the
  judgment.

Implication: the recipe is **neutral F0 + intermediate formants + tuned spectral tilt**,
**validated by perceptual testing** — not by acoustic numbers alone. A naive pitch-shift of
a system voice can't do this (it drags formants along, producing the chipmunk/Vader
effect), which is why a trainable model is required and why "just pick a neutral system
voice" is only a stopgap.

Note: "Q" was a research/awareness project that produced sample audio and findings, **not a
deployable model** — which is why it disappeared. The reusable asset is the *recipe*, not
any software. This spec applies that recipe to a phone-runnable model.

---

## 2. Decisions (locked during brainstorming)

| Decision | Choice |
| --- | --- |
| Where Hearty speaks | **Voice-mode only** (the existing wake-word / overlay flow). Silent elsewhere. No scope expansion. |
| Persona | **Adapts to the conversation-style setting** (Warm vs. Concise) the user already picks. |
| Neutrality target | **Androgynous but distinctive** — a designed voice with character, sitting in the neutral zone; validated perceptually rather than chasing perfect statistical neutrality. |
| Relationship to existing TTS | **Custom neural voice is the default; system TTS (`flutter_tts`) is the fallback.** Settings→Voice picker kept as an advanced override. |
| Voice source | **Design synthetically, then distill** — author the timbre with a large model, generate a synthetic corpus, distill into a small on-device model. |
| Build ordering | **Approach A — spike runtime first, then build the voice** (risk-ordered). |
| Training hardware | **pkix workstation** — RTX PRO 4000 Blackwell, 24 GB VRAM (see `reference-pkix-server` memory). |

---

## 3. Architecture

Two tracks meet at a single artifact: the `.onnx` voice file.

```
┌─ ON DEVICE (Flutter / Hearty app) ────────────┐    ┌─ WORKSTATION (pkix, RTX PRO 4000) ────┐
│                                                │    │                                        │
│  voice_provider.dart                           │    │  Voice design + distill pipeline       │
│    └─ TtsEngine (new interface)                │    │    1. Qwen3-TTS VoiceDesign → target    │
│         ├─ NeuralTtsEngine (sherpa-onnx) ◀─────┼────┼─ 2. Generate synthetic corpus           │
│         │    runs hearty_voice.onnx (default)  │    │    3. Distill → Piper (VITS) voice      │
│         └─ SystemTtsEngine (flutter_tts)       │    │    4. Export hearty_voice.onnx + tokens │
│              = fallback (today's behavior)     │    │                                        │
└────────────────────────────────────────────────┘    └────────────────────────────────────────┘
              ▲ hearty_voice.onnx is the ONLY hand-off artifact between tracks
```

**Core principle:** the `.onnx` voice file is the only contract between the two tracks. The
app doesn't care how the voice was made; the workstation doesn't care how it's played. Each
side is independently testable.

### Why not VibeVoice / Qwen-TTS *as the runtime*

These are desktop/server models (VibeVoice 0.5B–7B wants 12–20 GB VRAM; Qwen3-TTS 0.6B–1.7B
wants 4–8 GB and a real GPU). They are excellent **design-lab** tools but cannot run on a
phone. The on-device runtime is a small VITS-class model (Piper) or Kokoro (82M params,
CPU-capable), executed via **sherpa-onnx** (has Dart/Flutter bindings + Android/iOS support).

---

## 4. Phasing (risk-ordered)

### Phase 0 — Runtime spike (de-risk before any voice investment)
Wire `sherpa-onnx` into Hearty behind a new `TtsEngine` abstraction, ship a **stock Kokoro
voice**, and measure real on-device latency + battery on the actual test device.
**Gate:** is on-device neural TTS acceptable?
- No → stop; keep system TTS. Days spent, not weeks.
- Yes → proceed.
Also resolved here: whether `just_audio` (already a dependency) is the cleanest path for raw
PCM playback from sherpa-onnx, or whether sherpa-onnx's own audio output is simpler.

### Phase 1 — Engine integration
Refactor `voice_provider.dart` to depend on `TtsEngine` instead of `FlutterTts` directly.
Implement `NeuralTtsEngine` + `SystemTtsEngine` fallback. Bundle the voice as an app asset.
Keep the Settings→Voice picker as an advanced override.

### Phase 2 — Voice creation (pkix)
Run the design → corpus → distill pipeline (Section 6) to produce the real androgynous
Hearty voice. Validate perceptually. Drop `hearty_voice.onnx` into app assets.

### Phase 3 — Style adaptation
Map the Warm/Concise conversation-style toggle to delivery (Section 7).

---

## 5. On-device engine design

Introduce a small interface so `voice_provider.dart` no longer calls `FlutterTts` directly.

```dart
abstract class TtsEngine {
  Future<void> init({String? voiceName});
  Future<void> speak(String text);          // resolves when audio finishes
  Future<void> stop();
  void setCompletionHandler(void Function() onDone);
  Future<void> setStyle(TtsStyle style);    // warm | concise → rate/pitch/contour
}
```

Two implementations:

- **`NeuralTtsEngine`** — wraps `sherpa-onnx`; loads bundled `hearty_voice.onnx` + tokens,
  synthesizes to a PCM buffer, plays via `just_audio`. **Default.**
- **`SystemTtsEngine`** — today's `flutter_tts` code lifted nearly verbatim into the
  interface. **Fallback**, and preserves the existing Settings→Voice picker.

### Selection logic (priority order)
1. Neural engine available + voice asset loads + device not blocklisted → **NeuralTtsEngine**.
2. Init throws / asset missing / synthesis errors at runtime → **fall back to
   SystemTtsEngine** for the rest of the session; log the fallback.
3. User explicitly picked a system voice in advanced settings → respect it (system engine).

### Changes to `voice_provider.dart`
- `FlutterTts _tts` field becomes `TtsEngine _tts`, injected (preserves the existing
  `ttsForTesting` test seam — there are existing tests).
- Completion-handler logic driving `setAwaitingFollowUp()` / `dismiss()` is unchanged — it
  listens to the interface instead of `FlutterTts` directly.
- `_prepareForSpeech` and its helpers (`_stripEmojis`, `"4/10" → "4 out of 10"`) stay and
  apply to **both** engines — they are engine-agnostic text prep.

---

## 6. Voice-creation pipeline (pkix)

Produces one `hearty_voice.onnx` that hits the acoustic targets and sounds like Hearty.

1. **Design** — Qwen3-TTS VoiceDesign (1.7B) authors the target voice from a text
   description (e.g. "warm, androgynous, mid-range, slight breathiness"). Iterate on short
   samples until the timbre is right.
2. **Target-check (GATE)** — measure F0 + F2 + spectral tilt of samples
   (praat / parselmouth). Gate: median F0 in **145–175 Hz**, intermediate formants. Tune
   the description and repeat. *Necessary, not sufficient.*
3. **Corpus** — generate a synthetic training corpus from the locked voice: ~3–5 hrs over a
   phonetically balanced script (LJSpeech transcripts or CMU ARCTIC prompts), consistent
   prosody.
4. **Distill** — train a Piper (VITS) voice on that corpus. Fits comfortably in 24 GB. This
   is the small, phone-runnable model.
5. **Perceptual validation (GATE — the real success metric)** — blind listening test: N
   listeners categorize each sample male / female / neutral. Gate: target "neutral" or a
   near-even split, while remaining natural/pleasant. Humans are the final word; step-2
   numbers are only a prerequisite.
6. **Export** — convert to ONNX with the **opset pinned to sherpa-onnx's bundled ORT**
   (cf. the wake-word lesson: Android ORT 1.19.2 needed opset12 — verify on-device, not
   just on desktop). Output `hearty_voice.onnx` + `tokens.txt`, sftp to the dev machine,
   drop into app assets.

### Risks & mitigations
- **Synthetic-corpus artifacts** — the distilled student inherits teacher artifacts.
  Mitigation: keep corpus prosody clean/consistent; audition raw teacher samples before
  generating the full set. Fallback if quality disappoints: **record a real voice actor**
  whose natural voice sits in the androgynous zone — the rest of the pipeline is unchanged.
- **Opset mismatch** — pin export opset to sherpa-onnx's ORT and verify on a real device.

---

## 7. Style adaptation (Phase 3)

The persona adapts to `prefs.conversationStyle` (`'warm'` / `'concise'`), already read in
`voice_provider.dart` and passed to the chat API.

- **v1 — parameter modulation (start here):** one voice, two deliveries via `setStyle()`.
  Warm = slightly slower rate, marginally warmer contour; Concise = slightly faster,
  flatter, clipped. No extra model weight.
- **v2 — two voice variants (only if v1 too flat):** train a second distilled voice with
  warmer prosody baked into the corpus. Doubles asset size (a few MB each for Piper —
  acceptable) and training work. Defer unless the listening panel says warm/concise don't
  feel distinct.

Decision: **start with v1**, treat v2 as a fast-follow only if needed.

---

## 8. Testing

- **Unit/widget (dev machine):** extend the existing `ttsForTesting` seam to a fake
  `TtsEngine`, covering both the neural path and the fallback path — including the
  **fallback trigger** (neural init throws → system engine takes over). Existing voice
  tests must stay green.
- **On-device (real phone):** latency, battery, and fallback verified manually on the
  actual test device. This is the Phase 0 gate, re-checked after the real voice lands.
- **Voice quality:** the blind listening panel (Section 6, step 5).

**Overall success metric:** a blind listening panel where the voice is *not* reliably
gendered, while still rated natural/pleasant — measured, not asserted.

---

## 9. Rollout & safety

- Custom voice ships **behind the fallback** from day one: a bad device experience degrades
  to today's behavior rather than breaking voice mode.
- Settings→Voice picker stays as an advanced override (user can force a system voice).
- **No backend/API changes** — entirely client-side plus an asset file. Nothing touches the
  chat API, food database, or sync.

---

## 10. Out of scope (YAGNI)

- Speaking outside voice mode.
- Multilingual voices (English only first).
- Voice cloning of the user.
- iOS-specific tuning beyond "it works" — Android is the primary target (consistent with
  where the wake-word work lives).
