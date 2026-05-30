# Phase 0 Runtime Spike — Results & Go/No-Go

**Date:** 2026-05-30
**Device:** Pixel 4a (`0B161JEC205801`), Android, physical device (not emulator)
**Build:** debug APK, sherpa_onnx 1.13.2 + bundled stock Piper VITS voice `en_US-libritts_r-medium`
**Plan:** `docs/superpowers/plans/2026-05-30-hearty-nonbinary-voice.md` (Task 0.3)

---

## Latency (measured on-device via the spike screen)

| Run | Synthesis time | Audio duration | Real-time factor |
|-----|---------------:|---------------:|-----------------:|
| Cold (first, incl. model load path) | 532 ms | 2891 ms | 0.184 |
| Warm #1 | 504 ms | 2601 ms | 0.194 |
| Warm #2 | 513 ms | 2763 ms | 0.186 |
| Warm #3 | 530 ms | 3030 ms | 0.175 |
| Long (~40 words, incl. a verse of "Do-Re-Mi") | 1243 ms | 7012 ms | 0.177 |

Test sentence (short): "Hi, I'm Hearty. I'll help you track how food makes you feel."
Test sentence (long): the short line + "Doe a deer a female deer, Ray a drop of golden sun. Me, a name I call myself."

**Real-time factor ≈ 0.18 consistently** → synthesizes ~5.5× faster than playback, stable across
cold/warm/long. **Warm short-utterance latency ~500–530 ms**, under the ~700 ms gate target. Cold
run (532 ms) also clears it — no significant first-use penalty. Long utterance scales linearly (no
blowup).

## Audio / quality
- Audio **plays out of the device speaker** correctly (PCM → WAV → just_audio path confirmed working
  on real hardware — this was the key Phase 0 integration unknown).
- User judged the stock voice **noticeably better than the system TTS voices currently available**.
  (This is only the stock Piper voice; the custom non-binary voice from Phase 2 will improve on it.)

## App size
- Debug APK ≈ **372 MB** (bundled 78 MB voice model + espeak-ng data + full debug symbols +
  validation layers). NOT representative of ship size — a release `--split-per-abi` build drops debug
  symbols, the Vulkan validation layer (~15 MB), and non-target ABIs, and will be far smaller. Record
  the real delta from a release build before launch.

## Battery / thermal
- ~25+ synthesis runs back-to-back during testing; no perceptible device heat or UI jank reported.
  (Qualitative — formal battery profiling deferred; RTF 0.18 implies low CPU duty cycle per utterance.)

## Integration issue found & resolved (the spike's main payoff)
sherpa_onnx (TTS) and the existing wake-word feature both ship `libonnxruntime.so`, causing a
`mergeDebugNativeLibs` duplicate conflict, then — after `pickFirst` — an
`UnsatisfiedLinkError: cannot locate symbol "OrtGetApiBase"` crash on launch. Root cause: ELF
version-tagged symbols — sherpa bundles ORT **1.24.3** (`OrtGetApiBase@@VERS_1.24.3`); the wake
word's Microsoft `onnxruntime-android` JNI shim imported `OrtGetApiBase@VERS_<its-version>`.
**Fix:** bump `onnxruntime-android` 1.19.2 → **1.24.3** (match sherpa) + keep
`packaging { jniLibs { pickFirsts += "**/libonnxruntime.so" } }` in `android/app/build.gradle.kts`.
Verified in the built APK (core exports & shim imports both `@VERS_1.24.3`) and on device: **no crash,
and the user confirmed the wake word still triggers on ORT 1.24.3** (its model was validated on 1.19.2
— the bump did not regress detection).

Hardening follow-up (non-blocking): `pickFirst` leaves which `libonnxruntime.so` wins arbitrary;
long-term, resolve to a single ORT runtime explicitly.

---

## GO / NO-GO: **GO** ✅

On-device neural TTS is viable for Hearty:
- Latency comfortably under target (warm ~0.5 s, RTF ~0.18, stable).
- Audio plays on real hardware via the chosen playback path.
- Quality already beats the current system voices.
- The one real integration risk (ORT conflict + wake-word regression) is resolved and verified.

**Proceed past the Phase 0 gate** → Phase 0R (delete the spike, keep the stock voice asset for now)
and Phase 1's remaining device check (Task 1.6), then the custom-voice work (Phase 2) and
conversation-style adaptation (Phase 3). Open item before ship: measure the **release** APK size delta.
