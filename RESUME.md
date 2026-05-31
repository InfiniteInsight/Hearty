# RESUME — Hearty non-binary voice (Phase 2 training)

**Last updated:** 2026-05-31 (~epoch 269 of Piper fine-tune)
**Branch:** `voice-nonbinary-tts`

This is a durable, plain-text resume pointer so the voice-training work can be picked up by any
session (including after a context compaction). The training itself runs **detached on the pkix
workstation and does not depend on any Claude session** — it keeps training + checkpointing
regardless of what happens to the chat. Only the live progress monitors are fragile.

---

## TL;DR state
- **hearty-neutral-voice** chosen + locked (≈166 Hz, gender-neutral). Source embedding:
  repo `voice-final/hearty_voice_embedding.pt` + pkix `/data/hearty-voice/LOCKED/`.
- **Corpus done:** 5.0h / ~2950 in-band utterances at `/data/hearty-voice/training/preprocessed`.
- **Training (Task 2.4) RUNNING** on pkix: fine-tuning a Piper/VITS voice from the libritts_r medium
  base. ~50 epochs/hr. Checkpoints every 5 epochs.
- **Whole pipeline proven end-to-end** incl. ONNX load in sherpa-onnx 1.13.2 (the app runtime) and the
  wake word still working alongside the new TTS.

## pkix access
- `ssh -i ~/.ssh/pkix_training evan@192.168.1.220` — host RTX PRO 4000 Blackwell (sm_120) 24GB.
- pkix shell is **fish** → run remote commands by piping a bash script:
  `ssh -i ~/.ssh/pkix_training evan@192.168.1.220 'bash -s' < localfile`
- Conda envs: `training` (py3.10, Piper trainer + sherpa-onnx) and `hearty-voice` (py3.12, qwen-tts).
- GPU was freed for this work: `llama-server` + `ollama` docker containers are **stopped**.
  Restart when ALL Phase-2 GPU work is done: `docker start llama-server ollama`.

## Health check
```bash
pgrep -f piper_train                                   # training alive? (PID was 1548081)
ls /data/hearty-voice/training/output/lightning_logs/version_0/checkpoints/*.ckpt \
  | grep -oE 'epoch=[0-9]+' | sort -t= -k2 -n | tail -1   # newest epoch
nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader
grep -aE 'Traceback|CUDA error|OutOfMemory|RuntimeError' /data/hearty-voice/training/train.log | tail
```

## Send a progress sample (verified recipe)
```bash
PY=/data/miniconda/envs/training/bin/python
CKPT=$(ls -t /data/hearty-voice/training/output/lightning_logs/version_0/checkpoints/*.ckpt | head -1)
$PY /data/hearty-voice/export_for_sherpa.py "$CKPT" \
    /data/hearty-voice/training/preprocessed/config.json /data/hearty-voice/training/export_latest
# then synth in the `training` env with sherpa OfflineTtsVitsModelConfig(model, tokens, data_dir=espeak)
#   - espeak-ng-data: from the piper_phonemize package dir
#   - do NOT import parselmouth in the training env (not installed there)
# pull wavs with scp (NOT tar — the tar stdout stream got polluted before), then deliver to phone.
```
Samples sent so far: epoch 5, 54, 154, 214 (+ "That's rough, buddy" @214).

## Stop / next steps
- **Stop training when a sample sounds good to the user** (likely ~500–1000 epochs).
  `--max_epochs 12000` is just a high ceiling, NOT a target. Pick the best-sounding checkpoint.
- **Task 2.5:** blind listening panel (male/female/neutral + naturalness) — the real gender-neutrality gate.
- **Task 2.6:** ship `hearty-neutral.onnx` + `tokens.txt` + `espeak-ng-data/` into
  `hearty_app/assets/tts/` and point `NeuralTtsEngine` at it (export path already sherpa-verified).
- **Task 1.6 (separate, app side):** on-device full voice-flow + forced-fallback verify — needs the
  phone on a network for the chat API.

## Key references
- Full recipe (every step, incl. the seed-vs-clone lesson + sherpa export gotchas):
  `docs/superpowers/notes/2026-05-31-hearty-voice-recipe.md`
- Piper trainer setup: pkix `/data/hearty-voice/PIPER_TRAINING_SETUP.md`
- Plan + Living State: `docs/superpowers/plans/2026-05-30-hearty-nonbinary-voice.md`
- Spike/runtime results: `docs/superpowers/notes/2026-05-30-tts-spike-results.md`
- Claude memory: `project-nonbinary-voice` (has the same RESUME block) + `project-hearty-voice-recipe`.

## Known gotchas (already solved — don't re-trip)
- ORT conflict: sherpa bundles ORT 1.24.3; wake-word ORT dep bumped 1.19.2→1.24.3 + `pickFirst` in
  `hearty_app/android/app/build.gradle.kts`. Wake word re-verified working.
- VoiceDesign is non-deterministic per call → we CLONE a locked speaker embedding (consistent).
- Piper export needs ONNX metadata injected + tokens.txt with literal-space token (`export_for_sherpa.py`).
- Base ckpt is 904-speaker → train single-speaker with `--resume_from_single_speaker_checkpoint`
  (piper `__main__.py` patched to drop the `assert num_speakers>1`).
