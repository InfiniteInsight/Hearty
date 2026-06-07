# Voice Rebuild — On-Device Whisper / STT Spike (throwaway)

> **For agentic workers:** This is a **measurement-only, throwaway** spike — NOT a production plan. No production wiring, no lifecycle changes. Steps use checkbox (`- [ ]`) syntax for tracking. The deliverable is a filled-in results table + a decision, not shipped code. Throw the harness away when the decision is made (like `spike/sherpa-streaming-asr`).

**Goal:** Decide whether an **on-device** speech-to-text engine can match or beat **both** the current on-device sherpa streaming Zipformer (122 MB int8) **and** the cloud Google STT path on a **Pixel 4a (Snapdragon 730G, no usable GPU/NNAPI)** — well enough to **delete the cloud path** from the hybrid built in Plans B/C. Concretely: benchmark a short shortlist of on-device candidates on the exact §3 phrase set, on the real device, for **WER and stop→final latency**, against a hard decision gate.

**The decision this informs:** The hybrid (cloud when online for best open-vocab/brand accuracy; on-device sherpa Zipformer when offline) works but cloud costs per-minute and sends health-journal audio off-device. If a single on-device engine clears the gate, we can collapse to one private, $0, offline-capable path and delete Plan C's `/api/transcribe` + `CloudSttEngine`. If not, we keep the hybrid (or keep the current setup unchanged).

**Pre-spike research verdict (the hypothesis the device run must confirm or refute):** Whisper is **architecturally a poor fit for the 730G**. Its autoregressive decoder (the int8 *decoder* is the large component — 105 MB even for tiny.en) makes decode scale with output tokens, not just audio. The only on-device sherpa-onnx primary-source latency number we have — Whisper **tiny.en int8 = 0.386 RTF on a Raspberry Pi 4B (4 threads)** — extrapolates to **~4 s for a 10 s clip** on a Pi4-class CPU, and the 730G gives us only **2 big cores (A76)** + 6 little (A55). tiny.en is the *fastest* Whisper and still barely misses a 3 s gate — and tiny won't approach cloud's brand accuracy. The **accuracy-viable** Whisper sizes (small.en) will be **far** over real-time; the **speed-viable** sizes (tiny) won't beat cloud on brands. **Therefore the most likely outcome is "keep the hybrid."** The genuine wildcards that only the device can arbitrate: **base.en** (middle of the speed/accuracy curve), **Moonshine base** (a much faster encoder-decoder built for edge — and a v2 streaming variant exists), and **a fast-decoding transducer (Parakeet-TDT)** which is the architecture *actually proven real-time on this class of hardware* (today's Zipformer). This plan benchmarks those wildcards rather than assuming Whisper wins.

**Architecture (spike harness only):** A temporary debug probe screen (modeled on `lib/features/voice/screens/asr_isolate_probe_screen.dart`) that, for each candidate model, runs a sherpa-onnx **`OfflineRecognizer`** (Whisper / Moonshine / Parakeet are all **batch** offline ONNX) inside a background isolate, feeds it **identical pre-recorded WAV bytes** for each §3 phrase, and logs `{model, phrase, transcript, stop→final wall-clock ms}` to `<externalFiles>/whisper_spike_log.txt`. WER is scored manually against the known phrase text. Results drop straight into the §3 comparison table.

**Critical architecture nuance (don't oversell "reuse existing plumbing"):** A sherpa-onnx Whisper/Moonshine/Parakeet engine **reuses the `sherpa_onnx` package, its bundled native lib, and the FFI build** (already a dep at `^1.13.2`, already powering Piper TTS) — so **zero new native integration**. But it does **NOT** reuse `core/stt/asr_isolate.dart` as-is: that isolate is **streaming** (`OnlineRecognizer`, incremental `acceptWaveform` + `isReady`/`decode` loop, per-chunk **partials**). Offline recognizers are **batch**: feed the whole utterance, decode once, get one result, **no live partials**. So a local Whisper engine's lifecycle is **`CloudSttEngine`'s shape** (buffer → transcribe-on-stop, empty `partials`) running in an isolate — a *new* batch isolate, not the streaming one. **Consequence for the decision: switching the offline path from streaming Zipformer to batch Whisper/Moonshine/Parakeet loses live partials** (same limitation cloud already has). That is a UX regression vs today and belongs in the rubric even if the gates pass.

**Tech Stack:** Flutter/Dart, `sherpa_onnx ^1.13.2` (already a dep — `OfflineRecognizer` + Whisper/Moonshine/transducer configs), `record ^6.x` (re-add as in Plan B for the one-time WAV capture; the benchmark itself replays bytes), `dart:isolate`, `path_provider`. pkix (RTX PRO 4000 Blackwell, see `reference-pkix-server`) only if a candidate variant is **not** pre-built by sherpa-onnx.

**Spec:** Informs the open question in `docs/superpowers/specs/2026-06-07-voice-lifecycle-rebuild-design.md` §14 ("ship the 122 MB int8, or evaluate a newer/better model before P1?") and tests whether Plan C (`2026-06-07-voice-rebuild-phase-c-cloud-engine.md`) can later be deleted. **Reuse the §3 results-table methodology** so rows are directly comparable. Prereq: none (spike runs independently of B/C landing; needs only the `sherpa_onnx` dep, which exists).

**Scope guards (throwaway / measurement-only):**
- **No production wiring.** No `WhisperSttEngine` in `lib/core/stt/`, no `SttEngineFactory`/selection change, no `VoiceNotifier` change, no lifecycle/state-machine change. The probe screen is a `kDebugMode`-gated temporary route, deleted when the decision lands.
- **Reuse the abstractions as *patterns*, not by editing them:** the harness mirrors the `SttEngine` shape (`start`/`stop→SttResult`/`partials`/`dispose`), reuses `SilenceDetector` (`core/stt/silence_detector.dart`) only to note where auto-submit *would* fire (latency is measured stop→final, not auto-submit→final), and reuses the **isolate pattern** from `asr_isolate.dart` (new batch variant). It does **not** modify any file under `lib/core/stt/` or `lib/features/voice/`.
- **On-device-only outcome implications for Plan C are noted, NOT acted on.** If on-device wins, this spike's output is a *recommendation* to write a production plan that adds `WhisperSttEngine` and deletes Plan C — writing that plan and deleting cloud is **out of scope here**.
- **Models are pushed via `adb push`, not bundled** (as the sherpa spike did). No APK size change.
- **No backend, no cloud calls.** Cloud's numbers come from the §3 table (reference rows), not re-measured.

---

## Research findings — on-device STT candidates as of 2026 (with citations)

**Bottom line:** sherpa-onnx is the decisive integration fact. It wraps Whisper (tiny/base/small/medium/distil-small.en), Moonshine (tiny/base, incl. a 2026 v2 streaming variant), and NVIDIA Parakeet-TDT/Canary as **offline ONNX**, all runnable through the **`sherpa_onnx` runtime Hearty already bundles** ([sherpa-onnx repo](https://github.com/k2-fsa/sherpa-onnx); [sherpa Whisper export](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/whisper/export-onnx.html); [sherpa Moonshine](https://k2-fsa.github.io/sherpa/onnx/moonshine/index.html)). So the integration cost of *any* of these is "new Dart batch isolate," not "new native dependency." The hard question is purely **WER vs latency on the 730G**, which the device run settles.

| Candidate | Size (int8) | Open-vocab/brand accuracy | Pixel-4a latency outlook (10 s utt) | License | Flutter feasibility | Verdict for Pixel 4a |
|---|---|---|---|---|---|---|
| **whisper.cpp** tiny/base/small/medium (+ q5_0/q8_0) | tiny ~75 MB, base ~142 MB; q5/q8 ~2–4× smaller | tiny/base weak on brands; small (3.4% WER) good; medium (2.9%) best | Android **batch** ~1–2 s per 5 s audio for *small models*; **streaming ~5–7 s per 1 s** (busts real-time). Autoregressive decoder is the bottleneck. | MIT | Needs **new C/C++ FFI** (extra native dep) — higher friction than sherpa | Tiny/base only marginally real-time and weak on brands; small/medium too slow. **Plus a native dep we'd avoid.** Reject vs the sherpa path. |
| **sherpa-onnx Whisper tiny.en** int8 | enc 12 MB + dec 105 MB ≈ **~120 MB** | tiny ≈ 12.7% avg WER; **will fumble brands** (worse than current Zipformer on open vocab) | **~0.386 RTF on Pi4B → ~4 s** extrapolated; 730G has only 2 big cores → likely **≥3–4 s** | Apache-2.0 (runtime) | **Reuses existing `sherpa_onnx`** dep; new batch isolate only | **Benchmark, but low hope:** too inaccurate to replace cloud even if fast. |
| **sherpa-onnx Whisper base.en** int8 | **~140–160 MB** | better than tiny; still below small | ~2–3× tiny compute → **likely 6–10 s** (busts a 3 s gate) | Apache-2.0 | Reuses `sherpa_onnx` | **Wildcard — benchmark.** Middle of the curve; probably too slow but only device confirms. |
| **sherpa-onnx Whisper small.en** int8 | **~250 MB** | small ≈ 3.4% WER, **good** open-vocab | encoder + autoregressive decoder on 2×A76 → **far over real-time (10s+)** | Apache-2.0 | Reuses `sherpa_onnx` | **Accuracy contender / speed loser.** Benchmark to quantify the gap; expect it busts latency. |
| **distil-whisper** distil-small.en (166M) / distil-medium.en | distil-small ~166M params | within ~4% WER of large-v3 (small); English-only | 6× faster than equivalent Whisper, but base architecture still autoregressive → small.en-class compute | MIT | Exportable to ONNX (sherpa lists `distil-small.en` as a drop-in) | **Possible faster-than-small contender**, but distil-small ≈ small.en size/compute class — likely still slow on 730G. Optional swap if base.en is borderline. |
| **whisper-large-v3-turbo** (809M, 4 decoder layers) | ~1.6 GB fp; int8 still huge | ~large-v3 (<1% WER drop), **best brand accuracy** | 8× faster than large-v3 but **~2 GB working set, 809M params** → **infeasible on the 6 GB-RAM 730G under app+OS+wake-word pressure** | MIT | Technically ONNX-able | **Reject — too big for Pixel 4a RAM/CPU.** Out of scope. |
| **Moonshine tiny / base (en)** — incl. **v2 quantized 2026-02-27 (streaming, Android)** | tiny 27M params; base larger; both int8 | tiny ≈ Whisper-tiny WER but ~48% lower error than Whisper-tiny on Moonshine's sets; **variable-length encoder, strong noise robustness** | **~5× faster than Whisper-tiny** (50 ms latency v2 tiny); no 30 s zero-pad → big win on short utts | MIT | **Reuses `sherpa_onnx`** (Moonshine supported); v2 streaming variant could even restore partials | **Strongest latency contender; benchmark base for brand accuracy.** Likely fast enough; question is whether it beats cloud on brands (probably not) → likely "fast but not a cloud replacement." |
| **NVIDIA Parakeet-TDT-0.6b-v2** int8 (sherpa-onnx) | enc ~622 MB + dec 6.9 MB + joiner 1.7 MB ≈ **~630 MB int8** (tarball/dir reported ~1.3 GB — **verify the real on-disk int8 size at download**) | Top of open ASR leaderboards; **fast TDT decoder**, strong on open vocab | Transducer decode is cheap (decoder 6.9 MB); ~630 MB on a **6 GB** device is plausibly fine — load/CPU time is the open question | NVIDIA OSS (CC-BY-4.0 model) | **Reuses `sherpa_onnx`** (Parakeet TDT offline supported) | **Strong wildcard — benchmark it.** The only *high-accuracy* candidate whose **decoder** is fast (unlike Whisper); the transducer architecture is the one proven real-time on this hardware. Whether it fits/loads acceptably on the 730G is exactly what the **device decides** — do not pre-reject. |
| **NVIDIA Canary** (sherpa-onnx) | large | high accuracy, multilingual | attention decoder; large | NVIDIA OSS | sherpa Dart API supports it | **Reject for Pixel 4a** — too heavy; flagged for completeness. |
| **Vosk** (Kaldi) | small EN models ~50 MB | dated acoustic models; weaker than Zipformer on open vocab | real-time on ARM | Apache-2.0 | separate plugin (new dep) | **Reject** — worse accuracy than the current Zipformer + a new dep; no upside. |
| **Current: sherpa Zipformer streaming 122 MB int8 (2023-02-21)** | 122 MB | "a lot better" than 67 MB; fumbles brands ("IQ bar"), gets digits | **real-time** (~26–29 ms/chunk, RTF ≪1) on Pixel 4a; **live partials** | Apache-2.0 | already in production-design (Plan B) | **The incumbent baseline.** It is essentially the **newest English *streaming* Zipformer** — research found no clearly-better newer English streaming model. Beating *this* is what an offline Whisper/Moonshine must do. |
| **Cloud Google STT v1 `latest_long` (batch)** | n/a | **best** — nailed "IQ bar", digits | needs network; batch (no partials) | commercial | Plan C `/api/transcribe` | **The bar to beat to delete cloud.** Reference rows from §3. |

**Key research conclusions:**
1. **Architecture, not size, is the trap.** Whisper/distil-whisper/turbo are all autoregressive encoder-decoders; decode cost scales with tokens and the int8 *decoder* dominates even tiny. That is why the current **transducer** Zipformer is real-time and Whisper-small won't be on a 730G. ([Moonshine paper](https://arxiv.org/html/2410.15608v1) on Whisper's fixed 30 s padding + autoregressive cost; [whisper.cpp Android discussion](https://github.com/ggml-org/whisper.cpp/discussions/3567) on streaming busting real-time.)
2. **The lowest-friction path is sherpa-onnx offline (Whisper/Moonshine/Parakeet), not whisper.cpp.** whisper.cpp needs a new C/C++ FFI native dep; sherpa-onnx reuses Hearty's existing `sherpa_onnx` package. ([sherpa Whisper](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/whisper/tiny.en.html); [sherpa-onnx repo feature list](https://github.com/k2-fsa/sherpa-onnx).)
3. **No clearly-better newer *streaming* English Zipformer exists** — the 2023-02-21 model is still the frontier for streaming English in sherpa-onnx ([zipformer-transducer models](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/online-transducer/zipformer-transducer-models.html)). So "swap to a newer streaming model" is not an available answer; the real alternatives are batch (Whisper/Moonshine/Parakeet).
4. **Whisper hallucinates on silent/near-silent clips** — a known failure mode; Hearty's existing `SilenceDetector` (trailing-silence gating, only feeds after speech) mitigates feeding silent audio. Note for any production `WhisperSttEngine`.

Sources:
- sherpa-onnx repo + feature list — https://github.com/k2-fsa/sherpa-onnx
- sherpa Whisper export / tiny.en (sizes + Pi4 RTF + base/small/medium/distil-small.en variants) — https://k2-fsa.github.io/sherpa/onnx/pretrained_models/whisper/tiny.en.html and https://k2-fsa.github.io/sherpa/onnx/pretrained_models/whisper/export-onnx.html
- sherpa Moonshine — https://k2-fsa.github.io/sherpa/onnx/moonshine/index.html
- sherpa Parakeet-TDT-0.6b-v2-int8 (size: enc 622M, dec 6.9M, joiner 1.7M, ~1.3 GB) — https://huggingface.co/csukuangfj/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8 and https://k2-fsa.github.io/sherpa/onnx/pretrained_models/offline-transducer/nemo-transducer-models.html
- Moonshine (5× faster than Whisper-tiny, edge design, noise robustness) — https://arxiv.org/html/2410.15608v1 and https://github.com/moonshine-ai/moonshine
- distil-whisper (6× faster, 49% smaller, within 1% WER; distil-small.en 166M) — https://github.com/huggingface/distil-whisper and https://huggingface.co/distil-whisper/distil-small.en
- whisper-large-v3-turbo (809M, 4 decoder layers, ~2 GB) — https://huggingface.co/openai/whisper-large-v3-turbo and https://simonwillison.net/2024/Oct/1/whisper-large-v3-turbo-model/
- whisper.cpp model sizes / quantization / Android RTF — https://github.com/ggml-org/whisper.cpp/discussions/859 and https://github.com/ggml-org/whisper.cpp/discussions/3567 and https://openwhispr.com/blog/whisper-model-sizes-explained
- sherpa zipformer streaming English models (no newer English streaming model) — https://k2-fsa.github.io/sherpa/onnx/pretrained_models/online-transducer/zipformer-transducer-models.html
- sherpa_onnx Flutter package (OfflineRecognizer, Whisper config, already a Hearty dep) — https://pub.dev/packages/sherpa_onnx

---

## Decision gate (set the numbers before running, so the result isn't argued post-hoc)

A candidate **clears the gate to justify deleting cloud** only if **both** hold on the §3 phrase set, on the Pixel 4a:

1. **Accuracy (operationalized — §3 gives cloud's WER only qualitatively, and we don't re-run cloud):** the candidate is **transcript-correct on all P1–P8 including the decision-gating brand/digit cases** — **"IQ bar"** (P6, the brand the on-device Zipformer fumbled), **"1 to 10"** and **"a 2"** (P7/P1 digits) — **AND** its overall WER is **no worse than the incumbent 122 MB Zipformer's** on the set. (Cloud "nailed IQ bar + digits" per §3, so matching cloud = nailing those cases; the incumbent-WER floor makes the rest measurable without a cloud re-run.) Missing any brand/digit case = fail even if average WER looks fine.
2. **Latency:** **p50 stop→final ≤ ~3 s** and **p90 ≤ ~5 s**, measured **on the ~10 s-class phrases (P2, P6, P8)** — NOT averaged across the short ones. (Short phrases P3/P4 pull a blended p50 down and would flatter the length-scaling candidates — see the asymmetry note below.) This is pure batch dead-time after the user stops — the same UX *class* as cloud, but **worse** than today's streaming Zipformer, which shows partials live.

**Why these numbers:** 3 s p50 keeps post-stop dead time tolerable for a record-then-submit lifecycle; cloud already imposes a network round-trip of a similar order, so an on-device engine that matches it (and is private + free + offline) is a real win. Below the accuracy bar, on-device cannot replace cloud for a health journal where brand/quantity errors corrupt insights.

**Latency asymmetry (a finding in itself):** Whisper decode is **~constant regardless of clip length** (fixed 30 s zero-padding), so its latency on P3/P4 ≈ its latency on P2/P6. Moonshine (variable-length encoder) and Parakeet (transducer) **scale with utterance length**, so their short-phrase latency is much lower than their 10 s latency. Judging the gate on the 10 s-class phrases keeps the comparison honest for the length-scaling candidates; report per-phrase decodeMs so this asymmetry is visible.

---

## Candidate shortlist (what to actually benchmark — and why)

Benchmark **4 contenders + 2 reference rows**. Prefer lowest integration friction (all 4 reuse `sherpa_onnx`). Most are **pre-exported by sherpa-onnx** → download tarball + `adb push`; pkix conversion is only for a non-prebuilt variant.

1. **Whisper base.en int8** — the middle of the Whisper speed/accuracy curve; the most likely Whisper size to *almost* clear both gates. Pre-built.
2. **Whisper small.en int8** — the Whisper *accuracy* contender. Same harness, **just swap the model files** (cheap to run both base + small). Expected to bust latency — measure the gap so the rubric is evidence-based. Pre-built.
3. **Moonshine base.en int8** — the *latency* contender (edge-built, ~5× faster than Whisper-tiny, variable-length encoder). Tests "fast enough, but does it beat cloud on brands?" Pre-built. (If available, also note the **v2 streaming** variant, which could restore live partials — flag for the rubric.)
4. **Parakeet-TDT-0.6b-v2 int8** — the only *high-accuracy* candidate with a **fast (transducer) decoder**, i.e. the architecture proven real-time on this hardware class. The int8 model is **~630 MB** (verify at download — the tarball/dir is reported ~1.3 GB), which on a **6 GB** Pixel 4a is plausibly fine; the open question is **load time + CPU** on the 730G, not RAM. The device run resolves it (if it loads too slow or is too heavy under app+wake-word pressure, record that as the finding and move on — don't pre-reject).

**Reference rows (not re-measured):** current **sherpa Zipformer 122 MB streaming** (incumbent baseline, has partials) and **cloud Google STT** — both from §3.

*Explicitly NOT benchmarked (with reason):* whisper.cpp tiny/base (needs a new native FFI dep; no accuracy upside over sherpa Whisper of the same size), whisper-large-v3-turbo & Canary (too big for 4 GB RAM), distil-medium.en (small.en-class compute, redundant with small.en), Vosk (worse than the incumbent). Whisper **tiny.en** is optional — only run it if base.en's latency is borderline and you want the floor.

---

## The fixed test phrase set (verbatim from the §3 spike, so rows compare directly)

Reuse the exact spike phrases (see `memory/project-voice-stt-engine-research`), each recorded **once** and replayed to every engine:

| # | Phrase (spoken) | What it tests |
|---|---|---|
| P1 | "I had heartburn about a 2" | digit-after-pause; the case Android truncated |
| P2 | "For lunch I had a turkey sandwich and a cold brew coffee" | multi-noun meal log (Zipformer got this perfect) |
| P3 | "acid reflux" | short symptom |
| P4 | "bloating" | single-word symptom |
| P5 | "Aloha oatmeal chocolate chip protein bar" | brand ("Aloha") + "protein"→"routine" miss case |
| P6 | "I had an IQ bar cookies and cream" | **the decision-gating brand** ("IQ bar"); Zipformer got "I KEU BAR", cloud nailed it |
| P7 | "rate it 1 to 10" / "a level of 2" | digit ranges / rating (the "one ten" TTS case's STT counterpart) |
| P8 | **Noise pass:** P2 + P6 replayed with background audio (video playing) | brand + meal log under noise (matches the §3 noise round) |

> **Methodology upgrade over the original spike (deliberate):** the §3 spike used a **live mic**, so speaker/prosody varied between engines. Here, record each phrase **once to a 16 kHz mono WAV**, push the WAVs, and feed **identical bytes** to every candidate. This makes WER deterministic and the cross-engine comparison true apples-to-apples. (P8 noise = mix once, replay once.)

---

## Harness tasks

### Task S0: Download the pre-built models on the dev box, push to device

**Files:** `scripts/spike-download-push-models.sh` (throwaway helper; delete on teardown).

> **No pkix, no GPU, no conversion.** All four candidates are **pre-exported** by sherpa-onnx — published as ready-to-use `.tar.bz2` assets on the `asr-models` GitHub release (all four URLs verified live). So S0 is just `wget → extract → adb push`, done **on this dev box** (which already has wifi-adb to the Pixel). pkix would only matter *later*, if the spike concludes we want a model variant sherpa does **not** pre-ship and we must export it ourselves via `export-onnx.py` (that needs a GPU). It is irrelevant to running this spike.

- [ ] **Step 1: Run the helper** — `bash scripts/spike-download-push-models.sh`. It downloads the four tarballs (into `${TMPDIR:-/tmp}/hearty-spike-models`, ~2 GB total — skips any already present), extracts them, `adb push`es each into its own device dir, and prints each model's on-disk size for the results table. Verified release assets:
  - `sherpa-onnx-whisper-base.en.tar.bz2` → `spike-whisper-base`
  - `sherpa-onnx-whisper-small.en.tar.bz2` → `spike-whisper-small`
  - `sherpa-onnx-moonshine-base-en-int8.tar.bz2` → `spike-moonshine-base`
  - `sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8.tar.bz2` → `spike-parakeet-tdt`
  (base = `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/`)
- [ ] **Step 2: Confirm the push** — the script lists the pushed dirs; verify Parakeet (~1.3 GB tarball) actually fit. If a model's internal filenames differ from what `whisper_spike_screen.dart`'s `_candidates` expects, the probe screen prints the dir's actual contents on "Run" so you can correct the constant (or rename on device).

### Task S1: Record the §3 phrase WAVs once and push them

**Files:**
- Create (temporary): a tiny capture path in the probe screen, OR record externally and push.

- [ ] **Step 1: Record P1–P8 as 16 kHz mono PCM WAVs** (one take each; P8 is P2/P6 mixed with background audio). Either use the probe screen's `record` capture (re-add `record ^6.x` as Plan B does) writing to `<externalFiles>/spike-wavs/`, or record on desktop and `adb push` to `/sdcard/Android/data/com.hearty.app/files/spike-wavs/p1.wav` … `p8.wav`. Keep them ~10 s where natural (pad P3/P4 with the natural utterance only — do NOT pad with silence, to avoid Whisper's silent-clip hallucination skewing results).
- [ ] **Step 2: Verify** the WAVs exist on device: `adb shell ls /sdcard/Android/data/com.hearty.app/files/spike-wavs/`.

### Task S2: Batch ASR isolate (offline recognizer) — the harness engine

**Files:**
- Create (temporary): `hearty_app/lib/features/voice/screens/whisper_spike_isolate.dart` (throwaway; deleted with the screen).

- [ ] **Step 1: Write a batch isolate** modeled on `core/stt/asr_isolate.dart` but using **`OfflineRecognizer`** with a **per-candidate config** (Whisper vs Moonshine vs transducer differ only in the model-config block). Message protocol: `['init', kind, paths..., numThreads]` → `['ready']`; `['decode', Float32List wholeUtterance]` → `['result', text, decodeMs]`; `['dispose']`. The isolate creates the recognizer once per model, then decodes each phrase's full samples in one `OfflineStream` (no streaming loop, no partials).
  ```dart
  // Sketch — sherpa OfflineRecognizer, batch. kind selects the config block:
  //   whisper:  OfflineModelConfig(whisper: OfflineWhisperModelConfig(encoder, decoder), tokens: ...)
  //   moonshine: OfflineModelConfig(moonshine: OfflineMoonshineModelConfig(preprocessor, encoder, uncachedDecoder, cachedDecoder), tokens: ...)
  //   transducer: OfflineModelConfig(transducer: OfflineTransducerModelConfig(encoder, decoder, joiner), tokens: ...)
  // On ['decode', samples]:
  //   final t0 = DateTime.now();
  //   final s = recognizer.createStream();
  //   s.acceptWaveform(samples: samples, sampleRate: 16000);
  //   recognizer.decode(s);
  //   final text = recognizer.getResult(s).text;
  //   send(['result', text, DateTime.now().difference(t0).inMilliseconds]);
  ```
  (Confirm exact field names against `sherpa_onnx ^1.13.2`'s `OfflineRecognizer` API — the package exposes `OfflineRecognizerResult` with Whisper/Moonshine/transducer configs.)
- [ ] **Step 2: Analyze:** `cd hearty_app && flutter analyze lib/features/voice/screens/whisper_spike_isolate.dart`. Expected: sherpa types resolve.

### Task S3: Temporary probe screen — run every model on every WAV, log results

**Files:**
- Create (temporary): `hearty_app/lib/features/voice/screens/whisper_spike_screen.dart` (modeled on `asr_isolate_probe_screen.dart`; same `[SPIKE]`-tagged file logging).

- [ ] **Step 1: Build the screen.** A `kDebugMode`-gated screen with: a model picker (the 4 candidate dirs), a "Run all phrases" button, a live transcript view, and a **responsiveness tap counter** (same no-ANR check as the probe). On "Run all": spawn the batch isolate, `init` the selected model (time the load), then for each WAV p1..p8: read the file → decode WAV header → Float32 samples → `['decode', samples]` → on `['result', text, ms]` append a log line. Reuse `SilenceDetector` only to annotate where auto-submit *would* have fired (informational; the measured latency is **stop→final = decodeMs**, i.e. the post-stop dead time the user feels).
  ```dart
  // Log line (one per model×phrase) to <externalFiles>/whisper_spike_log.txt:
  //   <iso8601>  [SPIKE] model=spike-whisper-base phrase=P6 loadMs=4200 decodeMs=3100 text="i had an iq bar cookies and cream"
  ```
  Wire it as a temporary debug route + Settings tile (delete on teardown), exactly as the existing probe is wired.
- [ ] **Step 2: Analyze + (no unit test — device-only by nature).** `cd hearty_app && flutter analyze lib/features/voice/screens/whisper_spike_screen.dart`.

### Task S4: Run on the Pixel 4a, collect, score

> Device: **Pixel 4a over wifi adb** — use the pair/connect/build recipe in `reference-wifi-debug` (do not reproduce keys). Run via **`make run`** (never bare `flutter run` — drops Supabase creds, see `feedback-run-command`).

- [ ] **Step 1: `make run`**, open the spike screen, and for **each of the 4 models** tap "Run all phrases". Watch the tap counter stays live (no ANR) during decode. If a model fails to load (e.g. Parakeet OOM on the 730G), record "load failed / OOM" as its result and continue.
- [ ] **Step 2: Pull the log** — **use `adb shell cat`, NOT `adb pull`** (the spike found `adb pull` returns a stale cached copy):
  ```
  adb shell cat /sdcard/Android/data/com.hearty.app/files/whisper_spike_log.txt
  ```
- [ ] **Step 3: Score WER manually** for each model×phrase against the known phrase text (P1–P8). Record `decodeMs` **per phrase**, then compute **p50/p90 over the ~10 s-class phrases (P2, P6, P8) only** for the latency gate (the short phrases P3/P4 would flatter the length-scaling candidates — see the gate's asymmetry note). Note brand/digit hits/misses explicitly (P5 "Aloha"/"protein", P6 "IQ bar", P1/P7 digits). Note any silent-clip hallucination on P3/P4.
- [ ] **Step 4: Fill in the results table** (below).
- [ ] **Step 5: Tear down** — delete `whisper_spike_screen.dart`, `whisper_spike_isolate.dart`, the temporary route + Settings tile, and the pushed `spike-*` model dirs + `spike-wavs` on device. Nothing from this spike ships.

---

## Results table (fill in on device)

> Latency columns = p50/p90 of decodeMs **over the 10 s-class phrases P2/P6/P8** (per the gate). Keep per-phrase decodeMs in the raw log so the length-scaling asymmetry (Whisper ≈ constant; Moonshine/Parakeet scale with length) is visible.

| Model | On-disk size | Load (ms) | WER on P1–P8 | Brand/digit cases (P5 P6 P1/P7) | p50 decode 10s (ms) | p90 decode 10s (ms) | Partials? | Notes |
|---|---|---|---|---|---|---|---|---|
| Whisper base.en int8 | ~?MB | | | | | | No (batch) | |
| Whisper small.en int8 | ~?MB | | | | | | No (batch) | |
| Moonshine base.en int8 | ~?MB | | | | | | No (batch; v2 may stream) | |
| Parakeet-TDT-0.6b int8 | ~630MB (verify) | | | | | | No (batch) | 6GB device — load/CPU is the risk, not RAM |
| *ref:* Zipformer 122MB (incumbent) | 122 MB | ~5000 | (from §3: good, fumbles brands) | IQ bar ✗ / digits ✓ | ~real-time | ~real-time | **Yes (live)** | offline, $0, private |
| *ref:* Cloud Google STT (§3) | n/a | n/a | (from §3: best) | IQ bar ✓ / digits ✓ | network RTT | network RTT | No (batch) | costs $; off-device |

---

## Decision rubric (map outcomes → next step)

- **A candidate clears BOTH gates (brand/digit cases correct + WER ≤ incumbent Zipformer, p50 ≤ 3 s & p90 ≤ 5 s on the 10 s-class phrases):**
  → Write a **production plan** to add `WhisperSttEngine` (or `MoonshineSttEngine`/`ParakeetSttEngine`) implementing `SttEngine` as a **batch isolate** (CloudSttEngine shape, empty `partials`), wire it via `SttEngineFactory`, and **evaluate deleting Plan C's cloud path** (`/api/transcribe` + `CloudSttEngine`). **Caveat to surface in that plan:** switching offline to batch **loses live partials** vs today's streaming Zipformer — confirm that UX regression is acceptable (it matches cloud's behavior, which the user already accepted for the online path).
- **Only an accuracy candidate clears WER but busts latency (expected for Whisper small.en):**
  → **Keep the hybrid.** On-device can't replace cloud on the 730G. Note the result in §14 of the spec; the 122 MB Zipformer stays the offline engine.
- **Moonshine (or base.en) is fast enough but misses the brand/digit cases (likely):**
  → **Reject as a cloud replacement.** Optionally consider Moonshine as a *better offline* engine than the 122 MB Zipformer **only if** its WER on P1–P8 beats the incumbent's AND it keeps real-time — otherwise no change.
- **A transducer (Parakeet) clears both gates:**
  → Best outcome — high accuracy *and* a fast decoder *and* (potentially) restorable partials via a streaming transducer. Write the production plan as above; this is the strongest case for deleting cloud. (Flag: only if it loads/runs acceptably on the 730G — if it loads too slowly or is too heavy under app+wake-word pressure, it's out.)
- **Nothing beats the 122 MB Zipformer + cloud combo (the predicted outcome):**
  → **Keep the current setup unchanged.** Record the benchmark in the spec as the evidence that closes the §14 open question; do not pursue an on-device Whisper engine. Plan C (cloud) stays.

---

## Self-review

- **Deliverable coverage:** research findings with the full candidate matrix + citations (above), an executable device spike (S0–S4), explicit decision gate (concrete WER/latency numbers), a 4-candidate shortlist with rationale + the lowest-friction (sherpa-onnx) ordering, the verbatim §3 phrase set with a deterministic-replay methodology upgrade, harness tasks (obtain/convert on pkix → push → batch isolate → probe screen → run/pull/score), a fill-in results table mirroring §3, and an outcome→next-step rubric.
- **Honest about the verdict:** the pre-spike hypothesis is stated up front as **"likely keep the hybrid"** — the latency math from sherpa's own Pi4 RTF (0.386 → ~4 s for *tiny*) plus Whisper's autoregressive-decoder bottleneck means the accuracy-viable sizes are too slow and the fast sizes won't beat cloud on brands. The "reuse existing plumbing" point is qualified precisely: reuses the **package/FFI/build**, **not** the streaming isolate (batch ⇒ new isolate ⇒ **no partials**), and that partials loss is carried into the rubric.
- **Gate made executable & un-gameable:** accuracy gate operationalized to "brand/digit cases correct + WER ≤ incumbent Zipformer" (§3 gives cloud's WER only qualitatively and the guard forbids re-running cloud); latency gate scoped to the **10 s-class phrases** so the length-scaling candidates (Moonshine/Parakeet) can't be flattered by short clips — with the Whisper-constant-vs-others-scale asymmetry called out as its own finding.
- **Device facts verified, not invented:** Pixel 4a = **6 GB** RAM (corrected from an earlier 4 GB slip); Parakeet int8 ≈ **630 MB** (enc 622 + dec 6.9 + joiner 1.7), so it is **not** pre-rejected — load/CPU on the 730G is the device-resolved risk, not RAM.
- **Architecture blind-spot addressed:** included a **fast-decoding transducer (Parakeet-TDT)** — the architecture actually proven real-time on this hardware — not only encoder-decoders, with its ~1.3 GB/622M-encoder size flagged as the device-resolved risk.
- **Required notes carried:** Whisper batch = no live partials (same as cloud); Whisper silent-clip hallucination + `SilenceDetector` mitigation; brand/digit gating cases (IQ bar, 1-to-10, "a 2"); `adb shell cat` (not `adb pull`) gotcha; `make run` not bare `flutter run`; pkix GPU only if a non-prebuilt variant is needed (most candidates are pre-exported).
- **Scope guards honored:** measurement-only/throwaway, `kDebugMode` probe deleted on teardown, no edits under `lib/core/stt/` or `lib/features/voice/providers/`, reuses `SttEngine`/`SilenceDetector`/isolate as **patterns**, models `adb push`ed not bundled, Plan C deletion is a *recommendation only* — not acted on here.
- **Format match:** mirrors Plan B's header block (Goal/Architecture/Tech Stack/Spec/Scope guards), file-structure-style task layout, `### Task` + `- [ ]` steps, and a Self-review section.
- **Uncertainty flagged for the device:** every latency figure is a Pi4→730G extrapolation (approximate — the 730G's 2-big-core layout could go either way); Parakeet may OOM; Moonshine-v2-streaming partials are unconfirmed on this package version; exact `sherpa_onnx ^1.13.2` `OfflineRecognizer` field names must be checked at code time. **Only the device run arbitrates.**
