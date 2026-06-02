# Hey Hearty Wake Word Training Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Train a "Hey Hearty" OpenWakeWord ONNX model on the A2000 workstation that works reliably across many speakers, then deploy it to replace hey_jarvis in the Flutter app.

**Architecture:** The lgpearson1771 automated training pipeline generates 50,000 synthetic TTS samples via Piper (with 700-speaker SLERP interpolation for multi-speaker coverage), applies RIR room augmentation and noise mixing, trains a ~200 KB classification head on top of Google's frozen speech embedding backbone, and exports two ONNX files. The resulting model drops into `hearty_app/assets/wake_word/` with minor updates to `HeartyWakeWordService.kt` and `pubspec.yaml`.

**Tech Stack:** Python 3.10, CUDA 12.x, piper-sample-generator, lgpearson1771/openwakeword-trainer, ONNX Runtime, Flutter/Kotlin

---

## Background and Why the Previous Attempt Failed

The Colab-trained `hey_hearty.onnx` scored a dead-flat **0.0008** at inference — it never triggered. Root cause: Piper TTS generates audio at **22,050 Hz**, but OpenWakeWord feature extraction requires **16,000 Hz**. If the resampling step is skipped or silently fails, training completes without errors but the model learns features computed at the wrong sample rate. At inference time (which always runs at 16 kHz) the model sees completely different features and scores flat.

This plan includes explicit sample rate validation gates to catch this before training starts.

---

## Hardware Requirements (A2000 Workstation)

- NVIDIA RTX A2000 12 GB VRAM ✓
- ~20 GB free disk space (17 GB negative data corpus, downloaded once)
- Linux or Windows with WSL2 (native Windows breaks VITS audio generation — use WSL2)
- Internet connection for one-time corpus downloads

---

## File Map

### Training Workstation (run these steps there)
- `~/openwakeword-trainer/` — cloned lgpearson1771 trainer repo
- `~/openwakeword-trainer/config.yaml` — training config (wake phrase, sample count)
- `~/openwakeword-trainer/output/hey_hearty.onnx` — primary classifier model output
- `~/openwakeword-trainer/output/hey_hearty_v1.0.0.onnx` — versioned copy
- `~/validate_hey_hearty.py` — validation script (written in Task 4)

### Flutter App (run these steps on dev machine)
- `hearty_app/assets/wake_word/hey_hearty.onnx` — replace with newly trained model
- `hearty_app/pubspec.yaml` — register hey_hearty.onnx, remove hey_jarvis.onnx
- `hearty_app/android/app/src/main/kotlin/com/hearty/app/HeartyWakeWordService.kt` — update model filename, ONNX node names, notification text

---

## Task 1: Set Up Training Environment on A2000 Workstation

**Run all steps in this task on the A2000 workstation (via WSL2 terminal if Windows).**

**Files:**
- Create: `~/openwakeword-trainer/` (cloned repo)

- [ ] **Step 1: Verify CUDA and Python version**

```bash
nvidia-smi
python3 --version   # Must be 3.10.x — training deps break on 3.11+
```

Expected output: GPU listed with 12 GB memory, Python 3.10.x. If Python is wrong version:

```bash
# Ubuntu/Debian
sudo apt install python3.10 python3.10-venv python3.10-dev
```

- [ ] **Step 2: Clone the trainer and create virtualenv**

```bash
cd ~
git clone https://github.com/lgpearson1771/openwakeword-trainer.git
cd openwakeword-trainer
python3.10 -m venv .venv
source .venv/bin/activate
```

- [ ] **Step 3: Install dependencies**

```bash
pip install --upgrade pip
pip install -r requirements.txt
```

Expected: installs torch, torchaudio, onnxruntime, speechbrain, piper-sample-generator, and supporting libs. This will take 5–10 minutes.

- [ ] **Step 4: Verify GPU is detected by PyTorch**

```bash
python3 -c "import torch; print(torch.cuda.get_device_name(0)); print(torch.cuda.mem_get_info())"
```

Expected output: `NVIDIA RTX A2000` and two large numbers (free/total VRAM in bytes). If CUDA is not found, check that `nvidia-smi` works from WSL2 and that CUDA drivers are installed.

- [ ] **Step 5: Verify piper-sample-generator is installed**

```bash
python3 -c "import piper_train; print('piper ok')"
# or
python3 -m piper_sample_generator --help 2>&1 | head -5
```

Expected: help text shown without ImportError.

- [ ] **Step 6: Commit workstation setup notes**

This step is documentation only — on the dev machine, update the plan's Background section if anything differed from expectations.

---

## Task 2: Generate TTS Training Data

**Run on A2000 workstation. The goal is 50,000 samples of "hey hearty" at 16 kHz with maximum speaker diversity.**

**Files:**
- Create: `~/hey_hearty_raw/` — 22050 Hz raw Piper output (temporary)
- Create: `~/hey_hearty_16k/` — resampled 16 kHz samples (used for training)

- [ ] **Step 1: Generate 50,000 raw TTS samples**

```bash
mkdir -p ~/hey_hearty_raw
cd ~/openwakeword-trainer
source .venv/bin/activate

python3 -m piper_sample_generator \
  "hey hearty" \
  --max-samples 50000 \
  --output-dir ~/hey_hearty_raw/ \
  --length-scales 0.7 0.8 0.9 1.0 1.1 1.2 1.3 \
  --slerp-weights 0.0 0.25 0.5 0.75 1.0 \
  --max-speakers 700 \
  --batch-size 50
```

`--length-scales` varies speaking rate (makes the model respond to slow/fast speech and whispers). `--slerp-weights` interpolates between speaker embeddings to create thousands of synthetic voice profiles beyond the base 700. `--max-speakers 700` avoids quality degradation from data-sparse later speakers. On the A2000, expect ~100 samples/sec → ~8 minutes total.

Expected output: `~/hey_hearty_raw/` contains 50,000 sequentially numbered `.wav` files at 22050 Hz.

- [ ] **Step 2: Verify raw sample count and sample rate**

```bash
# Count files
ls ~/hey_hearty_raw/*.wav | wc -l   # Must be 50000

# Check sample rate of first 5 files — MUST be 22050 Hz at this stage
python3 - <<'EOF'
import wave, os, glob
files = sorted(glob.glob(os.path.expanduser("~/hey_hearty_raw/*.wav")))[:5]
for f in files:
    with wave.open(f) as w:
        print(f"{os.path.basename(f)}: {w.getframerate()} Hz, {w.getnframes()} frames")
EOF
```

Expected: 50000 files, all at **22050 Hz**.

- [ ] **Step 3: Resample all samples to 16 kHz**

```bash
mkdir -p ~/hey_hearty_16k

python3 - <<'EOF'
import glob, os, subprocess
from tqdm import tqdm

raw_dir = os.path.expanduser("~/hey_hearty_raw/")
out_dir = os.path.expanduser("~/hey_hearty_16k/")
files = sorted(glob.glob(raw_dir + "*.wav"))

for f in tqdm(files):
    out = os.path.join(out_dir, os.path.basename(f))
    subprocess.run([
        "ffmpeg", "-y", "-i", f,
        "-ar", "16000", "-ac", "1",
        "-sample_fmt", "s16", out
    ], capture_output=True, check=True)
EOF
```

This requires `ffmpeg` (`sudo apt install ffmpeg` if missing). Alternatively, the lgpearson1771 trainer has an internal resampling step — if the trainer's step 7 runs `torchaudio.transforms.Resample`, you can skip this manual step and rely on it. Prefer running this explicit step anyway as a gate.

- [ ] **Step 4: Validate 16 kHz conversion — THE CRITICAL GATE**

This is the step that was missing in the failed Colab run. Do not proceed to training until this passes.

```bash
python3 - <<'EOF'
import wave, os, glob

out_dir = os.path.expanduser("~/hey_hearty_16k/")
files = sorted(glob.glob(out_dir + "*.wav"))

wrong_rate = [f for f in files[:200] if wave.open(f).getframerate() != 16000]
print(f"Total files: {len(files)}")
print(f"Wrong sample rate in first 200: {len(wrong_rate)}")
if wrong_rate:
    print("FAIL — resampling did not work:")
    for f in wrong_rate[:5]:
        print(f"  {f}: {wave.open(f).getframerate()} Hz")
    exit(1)
else:
    print("PASS — all checked files are 16000 Hz")
EOF
```

Expected: `PASS — all checked files are 16000 Hz`. If FAIL, check that ffmpeg ran without errors and rerun Step 3.

---

## Task 3: Run the Training Pipeline

**Run on A2000 workstation.**

**Files:**
- Modify: `~/openwakeword-trainer/config.yaml`
- Create: `~/openwakeword-trainer/output/hey_hearty.onnx`
- Create: `~/openwakeword-trainer/output/hey_hearty_v1.0.0.onnx`

- [ ] **Step 1: Write training config**

```bash
cat > ~/openwakeword-trainer/config.yaml << 'EOF'
wake_phrase: "hey hearty"
n_samples: 50000
tts_batch_size: 25
positive_data_dir: "/root/hey_hearty_16k"
output_dir: "/root/openwakeword-trainer/output"
EOF
```

Adjust `/root/` to your actual home path (`echo ~` to check). `tts_batch_size: 25` is safe for 12 GB VRAM. If training OOMs, reduce to 10.

- [ ] **Step 2: Run the automated trainer**

```bash
cd ~/openwakeword-trainer
source .venv/bin/activate
python3 train.py --config config.yaml
```

The trainer runs 13 steps. Watch for these milestones in the output:
- `Step 3: Download negative data` — downloads ~17 GB once, reusable. Takes 20–40 min on first run.
- `Step 6: Generate TTS clips` — if you passed `positive_data_dir`, it may skip this and use your pre-generated 16k files directly. If it re-generates, check that it also resamples (step 7).
- `Step 9: Augment clips` — applies RIR room acoustics + noise mixing. This is critical for far-field detection.
- `Step 11: Train DNN + export ONNX` — actual training, ~30 min on A2000.
- `Step 13: Export to output dir`

Expected total time: 1–2 hours (most of it is the one-time negative data download).

- [ ] **Step 3: Verify output files exist**

```bash
ls -lh ~/openwakeword-trainer/output/
```

Expected: two ONNX files totalling ~200 KB, e.g.:
```
hey_hearty.onnx         ~14 KB   (graph)
hey_hearty_v1.0.0.onnx ~186 KB  (weights)
```

If only one file: check the trainer's export step — some versions export a single combined file. Either is fine; identify which one the validator in Task 4 loads successfully.

---

## Task 4: Validate the Output Model

**Run on A2000 workstation. This catches the silent failure mode before you copy anything to the Flutter app.**

**Files:**
- Create: `~/validate_hey_hearty.py`

- [ ] **Step 1: Write the validation script**

```bash
cat > ~/validate_hey_hearty.py << 'EOF'
"""
Validates hey_hearty.onnx against the exact inference pipeline used by
HeartyWakeWordService.kt. Checks node names and runs a smoke-test inference.
"""
import os, sys
import numpy as np
import onnxruntime as ort

OUTPUT_DIR = os.path.expanduser("~/openwakeword-trainer/output/")

# Find the output ONNX files
onnx_files = [f for f in os.listdir(OUTPUT_DIR) if f.endswith(".onnx")]
print(f"Found ONNX files: {onnx_files}")

# Load the classifier (the larger file is typically the weights)
classifier_file = sorted(onnx_files, key=lambda f: os.path.getsize(os.path.join(OUTPUT_DIR, f)))[-1]
classifier_path = os.path.join(OUTPUT_DIR, classifier_file)
print(f"\nLoading classifier: {classifier_file} ({os.path.getsize(classifier_path)//1024} KB)")

session = ort.InferenceSession(classifier_path)

# Print actual node names — these MUST match HeartyWakeWordService.kt
print("\n--- INPUT NODES ---")
for inp in session.get_inputs():
    print(f"  name='{inp.name}'  shape={inp.shape}  dtype={inp.type}")

print("\n--- OUTPUT NODES ---")
for out in session.get_outputs():
    print(f"  name='{out.name}'  shape={out.shape}  dtype={out.type}")

# Run smoke test: 16 embeddings of 96 dims, all zeros (silence)
input_name = session.get_inputs()[0].name
output_name = session.get_outputs()[0].name
dummy_input = np.zeros((1, 16, 96), dtype=np.float32)

result = session.run([output_name], {input_name: dummy_input})
score = float(result[0].flat[0])
print(f"\n--- SMOKE TEST ---")
print(f"  Input shape: {dummy_input.shape}")
print(f"  Score on silence: {score:.6f}")

if score > 0.01:
    print("  WARNING: silence score > 0.01 — model may have high false positive rate")
elif score < 0.0:
    print("  FAIL: negative score — model output is invalid")
else:
    print("  PASS: silence scores near zero as expected")

# Report what HeartyWakeWordService.kt needs to be updated to
print(f"\n--- UPDATE HeartyWakeWordService.kt ---")
print(f"  wakeSession input node:  \"{input_name}\"   (currently \"x.1\")")
print(f"  wakeSession output node: \"{output_name}\"  (currently \"53\")")
if input_name == "x.1" and output_name == "53":
    print("  -> Node names match hey_jarvis — NO code change needed in runClassifier()")
else:
    print("  -> Node names DIFFER from hey_jarvis — update runClassifier() in HeartyWakeWordService.kt")
EOF
```

- [ ] **Step 2: Run the validator**

```bash
cd ~
source ~/openwakeword-trainer/.venv/bin/activate
python3 validate_hey_hearty.py
```

Expected output (exact node names may vary):
```
Found ONNX files: ['hey_hearty.onnx', 'hey_hearty_v1.0.0.onnx']
Loading classifier: hey_hearty_v1.0.0.onnx (186 KB)

--- INPUT NODES ---
  name='x.1'  shape=[1, 16, 96]  dtype=tensor(float)

--- OUTPUT NODES ---
  name='53'  shape=[1, 1]  dtype=tensor(float)

--- SMOKE TEST ---
  Input shape: (1, 16, 96)
  Score on silence: 0.000812
  PASS: silence scores near zero as expected

--- UPDATE HeartyWakeWordService.kt ---
  wakeSession input node:  "x.1"   (currently "x.1")
  wakeSession output node: "53"  (currently "53")
  -> Node names match hey_jarvis — NO code change needed in runClassifier()
```

**Write down the actual node names from your run** — you will need them in Task 5 Step 3 regardless of whether they match.

If the smoke test score is > 0.5, the model is broken (likely trained on wrong-rate data again). Do not proceed — recheck the 16 kHz validation gate from Task 2 Step 4 and retrain.

- [ ] **Step 3: Copy the validated ONNX file to the dev machine**

Transfer `hey_hearty_v1.0.0.onnx` (the weights file) from the A2000 workstation to the dev machine:

```bash
# On the A2000 workstation — adjust IP/path as needed
scp ~/openwakeword-trainer/output/hey_hearty_v1.0.0.onnx \
    evan@<dev-machine-ip>:/home/evan/projects/food-journal-assistant/hearty_app/assets/wake_word/hey_hearty.onnx
```

Or use a USB drive / shared folder if SSH is not set up between the machines.

---

## Task 5: Deploy to Flutter App

**Run on dev machine (this machine). The app currently uses `hey_jarvis.onnx`; this task switches it to `hey_hearty.onnx`.**

**Files:**
- Modify: `hearty_app/pubspec.yaml`
- Modify: `hearty_app/android/app/src/main/kotlin/com/hearty/app/HeartyWakeWordService.kt`

- [ ] **Step 1: Confirm the ONNX file is in place**

```bash
ls -lh /home/evan/projects/food-journal-assistant/hearty_app/assets/wake_word/
```

Expected: `hey_hearty.onnx` present, size ~186 KB. If missing, transfer from the workstation (Task 4 Step 3).

- [ ] **Step 2: Update pubspec.yaml to register hey_hearty.onnx**

In `hearty_app/pubspec.yaml`, find the assets block (currently around line 60) and replace:

```yaml
  assets:
    - assets/wake_word/hey_jarvis.onnx
    - assets/wake_word/melspectrogram.onnx
    - assets/wake_word/embedding_model.onnx
    - assets/audio/wake_chime.wav
```

with:

```yaml
  assets:
    - assets/wake_word/hey_hearty.onnx
    - assets/wake_word/melspectrogram.onnx
    - assets/wake_word/embedding_model.onnx
    - assets/audio/wake_chime.wav
```

- [ ] **Step 3: Update HeartyWakeWordService.kt — model filename and ONNX node names**

In `hearty_app/android/app/src/main/kotlin/com/hearty/app/HeartyWakeWordService.kt`:

**Change line 137** (model filename):
```kotlin
// Before
wakeSession  = loadModel("flutter_assets/assets/wake_word/hey_jarvis.onnx")
// After
wakeSession  = loadModel("flutter_assets/assets/wake_word/hey_hearty.onnx")
```

**Check lines 288 and 291** (ONNX node names in `runClassifier()`):
```kotlin
wakeSession!!.run(mapOf("x.1" to inputTensor)).use { result ->
    (result["53"].get() as OnnxTensor).floatBuffer.get()
```

Update `"x.1"` and `"53"` to the actual node names reported by the validator in Task 4 Step 2. If the validator said they match, leave these lines unchanged.

- [ ] **Step 4: Update notification text from "Hey Jarvis" to "Hey Hearty"**

In `HeartyWakeWordService.kt`, there are two places that still say "Hey Jarvis":

**Line 319** (wake detection notification):
```kotlin
// Before
.setContentTitle("Hey Jarvis detected")
// After
.setContentTitle("Hey Hearty detected")
```

**Line 351** (persistent foreground notification):
```kotlin
// Before
.setContentTitle("Hearty is listening for 'Hey Jarvis'")
// After
.setContentTitle("Hearty is listening for 'Hey Hearty'")
```

- [ ] **Step 5: Build and run**

```bash
make run
```

Watch logcat output (`adb logcat -s HeartyWakeWord`) after the app starts. Expected:
```
D/HeartyWakeWord: Loading model: flutter_assets/assets/wake_word/hey_hearty.onnx
D/HeartyWakeWord: All ONNX models loaded successfully
D/HeartyWakeWord: AudioRecord started — sliding window detection loop beginning
D/HeartyWakeWord: chunk=50 rms=0.0012 score=0.0009 max=0.0012
```

Baseline ambient scores should be < 0.01 (same range as hey_jarvis ambient scores). If you see scores > 0.05 on silence, the model has a high false positive rate — retrain with more negative data diversity.

- [ ] **Step 6: Test wake word detection**

Say "Hey Hearty" clearly toward the phone mic. Watch logcat for:
```
D/HeartyWakeWord: WAKE WORD DETECTED! score=0.6312
```

The score should be > 0.5 (the `DEFAULT_THRESHOLD`). Try at least 5 times from different distances and speaking speeds. If detection is inconsistent at the default threshold, it can be tuned — but try the trained model first before lowering the threshold.

- [ ] **Step 7: Commit**

```bash
cd /home/evan/projects/food-journal-assistant
git add hearty_app/assets/wake_word/hey_hearty.onnx \
        hearty_app/pubspec.yaml \
        hearty_app/android/app/src/main/kotlin/com/hearty/app/HeartyWakeWordService.kt
git commit -m "feat: deploy hey hearty wake word model, replace hey jarvis placeholder"
```

---

## Troubleshooting Reference

| Symptom | Likely Cause | Fix |
|---|---|---|
| Flat scores (~0.0008) on all audio | Training data at wrong sample rate | Redo Task 2 Step 4 gate, retrain |
| ONNX load error in logcat | Node name mismatch | Run validator again, update runClassifier() node names |
| Score never exceeds 0.1 on wake phrase | Insufficient training data or augmentation | Retrain with n_samples: 100000 |
| High false positives (score > 0.5 on random speech) | Phonetically-similar confuser phrases in negative data | Retrain with only clearly-different confusers |
| OOM during training | tts_batch_size too high | Lower to 10 in config.yaml |
| Silent .wav files on TTS generation | Running on native Windows | Switch to WSL2 |
| Python version error during install | Python 3.11+ used | Recreate venv with python3.10 |
