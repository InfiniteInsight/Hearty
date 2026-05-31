# Hearty Non-Binary Voice — Full Generation Recipe

**Date:** 2026-05-31
**Name:** **hearty-neutral-voice** (official name for this voice; internal build id was `blend_older`).
**Status:** Voice CHOSEN. This document records every step to reproduce it.
**Chosen voice:** the aged blend of two VoiceDesign descriptions, cloned to a stable speaker embedding.
**Measured:** avg F0 median ≈ **166 Hz** (in the 145–175 Hz gender-neutral target band), F2 ≈ 1830–1925 Hz (intermediate).

---

## TL;DR — what the final voice IS

`hearty_voice = (b3_centroid + b4_centroid) / 2  +  1.0 × age_vec`

where each term is a **2048-dim float32 speaker embedding** extracted by the Qwen3-TTS **Base** model's
speaker encoder. The voice is reproduced by feeding this single embedding into
`generate_voice_clone(...)` for any text — which is what makes it consistent across utterances.

**Locked artifacts:**
- pkix: `/data/hearty-voice/LOCKED/hearty_voice_embedding.pt` (key `"hearty_voice"`, shape (2048,), float32) + `sample_wavs/`
- repo: `voice-final/hearty_voice_embedding.pt` + `hearty_voice_sample_{1,2,3}.wav`
- intermediate embeddings: pkix `/data/hearty-voice/design/aged/aged_embeddings.pt` (`blend`, `age_vec`, `older_blend`) and `/data/hearty-voice/design/blend/embeddings.pt` (`b3_centroid`, `b4_centroid`, `blend`)

---

## Environment (pkix workstation)

- Host: pkix `192.168.1.220`, GPU NVIDIA RTX PRO 4000 Blackwell (sm_120), 24 GB, driver 580, CUDA 13 capable.
- conda env `hearty-voice` (Python 3.12.13): `torch 2.11.0+cu128` (sm_120 verified), `qwen-tts 0.1.1`,
  `transformers 4.57.3`, `torchaudio 2.11.0+cu128`, `praat-parselmouth 0.4.7`, `soundfile`, `numpy 2.4.6`.
- **GPU contention:** before runs, `docker stop llama-server ollama` (they hold ~19.5 GB); restart after.
- pkix shell is **fish** — run remote scripts via `ssh -i ~/.ssh/pkix_training evan@192.168.1.220 'bash -s' < localfile`.
- Models downloaded with `huggingface-cli download` into `/data/hearty-voice/models/`:
  - `Qwen/Qwen3-TTS-12Hz-1.7B-VoiceDesign` (4.3 G) — design voices from text descriptions
  - `Qwen/Qwen3-TTS-Tokenizer-12Hz` (651 M)
  - `Qwen/Qwen3-TTS-12Hz-1.7B-Base` (4.3 G) — voice cloning / speaker-embedding extraction

---

## Step-by-step history (how we got here)

### Research grounding
CHI 2023 "Creating Inclusive Voices…" (DOI 10.1145/3544548.3581281): gender-neutral F0 band ≈ **145–175 Hz**,
but perceived neutrality also depends on **formants (esp. F2)** and spectral quality — so the human ear is
the real gate, not the Hz alone. Target: androgynous *but distinctive*.

### Batch 1 — initial descriptions (VoiceDesign `generate_voice_design(text, language, instruct)`)
4 candidates (warm-neutral / breathy-soft / clear-steady / bright-androgynous). All read too feminine or
child-like except **c2 (breathy_soft)** which read most neutral to the user — *despite* being below band
(~116 Hz). Lesson: neutrality is driven by quality/formants more than raw pitch.

### Batch 2 — refined, anti-breathy + explicit pitch language
4 candidates (b1–b4). **USER shortlisted b3_steady_lowered + b4_warm_androgynous** ("really close").
Verbatim instructs:
- **b3:** "A calm, clear, gender-ambiguous adult voice pitched noticeably lower than a typical female
  voice, settling into a neutral mid-low range. Steady and even, warm but composed, smooth and solid
  without breathiness. Neither clearly male nor female."
- **b4:** "A warm, soothing, gender-neutral voice at a medium-low pitch, relaxed and reassuring like a
  caring nurse. Clear and natural, not breathy. Sits between masculine and feminine so it is hard to
  tell the speaker's gender."

### Batch 3 — iterations (NOT used)
5 variations of b3/b4. User chose to ignore and iterate on the batch-2 picks instead.

### Batch 4 — seed experiment (FAILED, instructive)
Ran b3/b4 instructs × seeds {42,123,777}, `torch.manual_seed` reset before each call. A research agent
had verified VoiceDesign randomness is pure LM sampling, so seeding *should* lock a voice. **But on
listening, the 3 sentences within one seeded voice did NOT sound like the same person.** Root cause:
VoiceDesign stores **no speaker vector** — identity is re-improvised from `instruct` + *the text being
spoken*, so same seed + different text → different person. **Seeds cannot give corpus consistency.**

### PIVOT — voice cloning (the fix)
The Base model has a real, storable speaker embedding. Pipeline that DID work:
1. `items = base.create_voice_clone_prompt(ref_audio=PATH, x_vector_only_mode=True)`
   → `items[0].ref_spk_embedding` = **(2048,) bf16** vector (ECAPA-style speaker encoder).
2. Average embeddings across a voice's clips → a **centroid** (smooths per-sample wobble).
3. Synthesize any text from an embedding via
   `base.generate_voice_clone(text=…, voice_clone_prompt=[VoiceClonePromptItem(ref_code=None,
   ref_spk_embedding=emb, x_vector_only_mode=True, icl_mode=False)], language="English")`.
   **This holds timbre across sentences** — confirmed: `b3_centroid` spread = **5 Hz** across 3 sentences.

### Blend (user request: "average the two voices")
- `b3_centroid` = mean of embeddings from b3's 3 batch-2 clips.
- `b4_centroid` = mean of embeddings from b4's 3 batch-2 clips.
- `blend = (b3_centroid + b4_centroid) / 2`  → avg F0 ≈ 186–189 Hz (slightly above band), pleasant.
- Script: `/data/hearty-voice/design/voice_blend.py`; embeddings saved to `…/design/blend/embeddings.pt`.

### Age tuning (user request: "make it a little older")
Embedding arithmetic to add maturity (and, helpfully, lower pitch into band):
1. With VoiceDesign, regenerate b3 & b4 with an appended age clause:
   *"The speaker sounds clearly older and mature, around their late fifties, with a little extra weight,
   warmth and gentle gravel of age in the voice, slightly lower and more settled."*
2. Clone those → `older_b3`, `older_b4` centroids → `older_blend = (older_b3 + older_b4)/2`.
3. `age_vec = older_blend − blend`. Apply to the blend:
   - `blend_a_bit_older = blend + 0.5 × age_vec` → avg F0 **171 Hz** (in band)
   - **`blend_older = blend + 1.0 × age_vec` = `older_blend`** → avg F0 **166 Hz** (in band, centered) ← **CHOSEN**
- Script: `/data/hearty-voice/design/voice_age.py`; embeddings saved to `…/design/aged/aged_embeddings.pt`.

**USER CHOSE `blend_older`** (2026-05-31).

---

## Reproduce / regenerate the chosen voice (any new text)

Run on pkix in the `hearty-voice` env (stop llama-server+ollama first to free GPU):

```python
import torch, soundfile as sf
from qwen_tts import Qwen3TTSModel
from qwen_tts.inference.qwen3_tts_model import VoiceClonePromptItem

base = Qwen3TTSModel.from_pretrained(
    "/data/hearty-voice/models/Qwen3-TTS-12Hz-1.7B-Base",
    device_map="cuda:0", dtype=torch.bfloat16, attn_implementation="sdpa")

emb = torch.load("/data/hearty-voice/LOCKED/hearty_voice_embedding.pt")["hearty_voice"]  # (2048,) float32
item = VoiceClonePromptItem(ref_code=None, ref_spk_embedding=emb,
                            x_vector_only_mode=True, icl_mode=False)

wavs, sr = base.generate_voice_clone(
    text="Hi, I'm Hearty. How are you feeling today?",
    voice_clone_prompt=[item], language="English")
sf.write("out.wav", wavs[0], sr)   # sr = 24000
```

(If `emb` dtype/device needs to match: `emb = emb.to(torch.bfloat16).cuda()` before building the item.)

---

## Next phase (Task 2.3+)

This embedding is the **locked source voice**. Remaining pipeline:
1. **Corpus (2.3):** generate ~3–5 h of speech from this embedding over a phonetically balanced script
   (LJSpeech/ARCTIC) → `(audio, transcript)` pairs at 24 kHz.
2. **Distill (2.4):** train a Piper/VITS voice on that corpus (fits in 24 GB) — the small, phone-runnable model.
3. **Validate (2.5):** blind listening panel (male/female/neutral) — the real success gate.
4. **Export (2.6):** to ONNX, opset matched to sherpa-onnx ORT 1.24.3 → drop into `hearty_app/assets/tts/`.

`hearty-neutral-voice` (the Qwen-cloned embedding) is the source/reference voice; the shipped on-device voice is the small Piper model distilled from it.
