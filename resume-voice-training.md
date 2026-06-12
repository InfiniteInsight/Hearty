# RESUME — Hearty non-binary voice (Phase 2 RETRAIN v2)

**Last updated:** 2026-06-01 — v2 pipeline LAUNCHED (corpus regenerating)
**Branch:** `voice-nonbinary-tts`

Durable resume pointer. The heavy work runs **detached on pkix** and does not depend on any Claude
session — corpus→chain→training→watcher all survive chat compaction/disconnect. Only ferrying samples
to the user's phone needs an awake agent.

---

## 2026-06-03 session — follow-up bugs A & B (exposed by the mic fix)

**Bug A — follow-up corrupted the meal + replied out of context. FIXED (commit 6886114).**
Saying "I'm okay" to the post-meal nudge overwrote the meal ("tuna" → "no food described")
because the chat follow-up branch treated "no symptom extracted" as a meal clarification and
re-ran extract_meal on "I'm okay". Layered fix in hearty-api/app/routers/chat.py + frontend:
(1) frontend sends `symptom_followup=true` for the nudge check-in → backend LOCKS the meal,
never edits it; (2) defense-in-depth: meal-clarification branch only updates when extract_meal
returns food; (3) backend fetches the logged meal into the LLM context so it stops asking "what
did you eat?". Backend VERIFIED via mocked unit tests (tests/test_chat_followup_unit.py, 3/3) +
an integration test added (test_api.py). NOTE: live integration suite needs a fresh TEST_JWT
(current one EXPIRED — all chat integration tests 401). Backend fix is LIVE on the local
--reload API; the frontend `symptom_followup` flag needs a rebuild to reach the phone (the
backend foods-guard alone already covers the nudge case on the old build).

**Bug B — follow-up showed "listening" before STT captured. Fixed in CODE (commit 3208d48), PENDING device confirmation.**
_beginStt set micPhase=listening BEFORE the wake-word handoff (release + 250ms), so the waveform
showed ~250ms before SpeechRecognizer captured → first words lost ("mic active but nothing
transcribed"). Fix: (1) flip micPhase to listening only after the handoff, right before
_stt.listen() (overlay shows "Getting ready…" during handoff); (2) pay the settle delay only on
the FIRST listen of a session (flag `_wakeWordMicReleased`), so restarts/tap-to-talk resume
re-acquire instantly. Regression test added. CAVEAT (advisor): #2 is an optimization bundled
with the real fix (#1) and is the ONLY change that could reintroduce mic contention — if device
testing shows residual "nothing transcribed", REVERT #2 first (it's isolated). Frontend-only →
needs a rebuild to device-test.

**NEXT on resume:** rebuild (`make run`) → run the full 4-test wake-word matrix (esp. #4 "hey
hearty AGAIN after a session" = re-arm regression from the _beginStt changes) + bug-A phrasings
("I'm okay" / "I feel fine" / "good, a bit full"); confirm the meal isn't overwritten. Port: a
local --reload API (with both fixes' backend) is serving 8080 — free it before `make run` so its
own API binds, or the clash is harmless (same code).

## 2026-06-02 session — mic-contention fix + branch consolidation

**FIXED: STT heard nothing on follow-up notification (and in-app tap-to-talk).**
Root cause (confirmed on-device via logcat): the always-on wake-word foreground
service holds the mic (AudioRecord, VOICE_RECOGNITION). On Android the existing
capture client wins → SpeechRecognizer starved on any STT path that didn't first
release it. Only "hey hearty" worked (native onWakeWordDetected stops the recorder).
Fix: `_beginStt()` calls `WakeWordChannel.stopListening()` + settle delay before
`_stt.listen()`; `VoiceOverlayScreen.dispose()` re-arms (single session-end
chokepoint); removed the redundant re-arm in router.dart. 20/20 voice tests pass.
Commit `6a5cb1a` on voice-beep-mute. **Device matrix (wake word ON) PENDING:**
tap-to-talk ✓, follow-up ✓, "hey hearty" ✓, and "hey hearty" AGAIN after a session ✓
(re-arm regression check).

**Branch consolidation onto master — DONE (2026-06-03).** master = acb2ea6:
FF'd to voice-beep-mute (mic fix + beep + tempo), cherry-picked the wake-word-settings
page (WakeWordSettingsScreen, its own page out of Notification prefs), merged prism-waveform
(live-STT waveform visualizer — conflicts in voice_provider.dart fields + voice_provider_test.dart
resolved keeping BOTH mic-handoff and soundLevel). Full suite 81/81 green, analyze clean.
Worktrees prism-waveform + wake-word-settings REMOVED; branches voice-beep-mute,
prism-waveform, wake-word-settings DELETED. Recovery refs kept: `backup/preconsolidate-*`
(master 5216b1a, voice-beep-mute 50a64e2, prism d4a7515, wake-word-settings 6d63cbc,
food-editing 4bcddf3) — delete once everything's confirmed good. NOTE: phone build still
predates the prism/settings consolidation (had mic fix only) → rebuild to see + re-verify.
**DEFERRED: `food-editing` branch** is pre-LFS-rewrite history (223/244 divergence;
its commits are content-dupes of master under old SHAs). Its real unique work = the
manual-food-editing feature (~4 top commits: 4bcddf3, 4f21b54, 6f1097a, a8349ed),
NOT in master. Do NOT merge (re-bloats repo with purged onnx blobs) — CHERRY-PICK
those 4 onto master later as a focused task. Branch + backup preserve it.

---

## What changed in v2 (why we restarted)
The epoch-799 distilled voice read slightly feminine + had faint "ch" artifacts. A distilled student
only copies its source, so we **re-neutralized the source first**. After 3 rounds (see memory
`project-nonbinary-voice`), the user picked **seed256** from a seed sweep of the C description:
neutral, no accent, "ch" confirmed clean by ear. Locked as the new source.

- **New source:** pkix `/data/hearty-voice/LOCKED_v2/hearty_neutral_v2.pt` (key `hearty_neutral_v2`, 2048-d, =seed256).
- **Corpus QC band RE-CENTERED:** v1 used 145-180/target160 (old ~157Hz voice). v2 uses
  **128-160 / target 143** to match seed256's approved-neutral distribution (else QC would pick its
  feminine upper tail). First batch confirmed F0 mean=143.8, 25/25 in-band — correct.
- **Checkpoint retention FIXED:** patched `piper_train/__main__.py` ->
  `ModelCheckpoint(every_n_epochs=..., save_top_k=-1)` and run with `--checkpoint-epochs 25`
  (v1 kept only save_top_k=1 → only epoch 814 survived). v2 retains EVERY 25 epochs.

## Running processes (pkix, detached)
- `corpus_gen_v2.py` → `/data/hearty-voice/corpus_v2_run.log` (ETA ~5.7h, marker DONE_CORPUS_V2)
- `chain_train_v2.sh` → waits DONE_CORPUS_V2, stages in-band utts, preprocess→`training_v2/preprocessed`,
  then fine-tunes from libritts base with `--resume_from_single_speaker_checkpoint`, `--max_epochs 800`,
  `--checkpoint-epochs 25`. Output `training_v2/output`. Logs: `training_v2/{chain.log,train.log}`.
- `ckpt_watcher_v2.sh` → `/data/hearty-voice/training_v2/watcher.log`. For each every-25 ckpt:
  export_for_sherpa → synth_sherpa 4 lines → `training_v2/deliver/epochNNNN/{greet,care,chstress,question}.wav`
  + `ckpt_path.txt`, marks `.done`. Runs until epoch0799 or training ends.

## FERRY (agent job): user wants every-25 samples in chat AND in /tmp/hearty-neutral, + the .ckpt files
For each NEW `training_v2/deliver/epochNNNN/.done`:
1. `scp` the 4 wavs → local `/tmp/hearty-neutral/epochNNNN/`
2. `scp` the source ckpt (path in `ckpt_path.txt`) → same local folder
3. `SendUserFile` the 4 wavs to the phone (caption = epoch #)
First deliverable ~6.3h out (corpus 5.7h + ~0.5h to epoch 25). ~32 deliveries total over the run.

## pkix access
`ssh -i ~/.ssh/pkix_training evan@192.168.1.220` (RTX PRO 4000 Blackwell, fish shell → pipe `bash -s`).
Envs: `hearty-voice` (py3.12, qwen-tts — corpus) + `training` (py3.10, piper+sherpa — train/export/synth).
GPU freed for this; restart `docker start llama-server ollama` ONLY when ALL Phase-2 GPU work done.

## CLEANUP after v2 ships (user asked to MARK, not delete yet)
v1 artifacts to remove once v2 is locked + shipped:
- `/data/hearty-voice/training/` (v1 output incl. epoch=814 ckpt, 808M logs + 4G preprocessed)
- `/data/hearty-voice/corpus/hearty_corpus/` (v1 corpus wavs)
- `/data/hearty-voice/LOCKED/` (v1 166Hz source) — keep LOCKED_v2
- `/data/hearty-voice/design/{reneutral,seed_sweep,lock_v2,finetune_accent}` scratch dirs
- repo `voice-final/hearty_voice_embedding.pt` (v1 source) — replace with seed256

## ✅ ep24 SHIPPED INTO APP (2026-06-01) — Task 2.6 code done, device-verify pending
ep24 PASSED user eval: no buzz (incl. fricative torture lines), stable+natural on long sentences.
Locked artifacts: repo `voice-final/ep24/{hearty-neutral.onnx,tokens.txt,README.txt}`.
App integration done:
- Asset dir renamed `assets/tts/vits-piper-en_US-libritts_r-medium` → `assets/tts/hearty-neutral`;
  stock onnx + stale .onnx.json removed; ep24 `hearty-neutral.onnx` + our `tokens.txt` dropped in;
  existing `espeak-ng-data/` reused (same phonemizer). MODEL_CARD kept.
- `pubspec.yaml`: all 37 tts asset lines repointed to hearty-neutral.
- `NeuralTtsEngine`: default modelAssetDir → `assets/tts/hearty-neutral`, onnx → `hearty-neutral.onnx`;
  added `_applyPronunciationFixes` runtime lexicon (caffeine→caffeen; extend map as needed).
- `flutter analyze lib/core/tts/` → clean.
DONE: device run confirmed (user: "runs well on the phone") = Task 1.6 ✓.
SHIPPED TO MAIN 2026-06-01: commit 455d97e fast-forwarded onto origin/master (GitHub). Push included
voice + curated app/api WIP (wellbeing removal, health-profile widgets, screen refactors, symptom
taxonomy, migrations) + android native + docs/images; EXCLUDED only tooling scratch (.claude,
.superpowers, .playwright-mcp) and voice scratch (voice-candidates-*, voice-final 62MB dup). Secret scan clean.

GIT-LFS SET UP (2026-06-01): migrated ALL *.onnx into LFS via `git lfs migrate import --include="*.onnx"
--include-ref=refs/heads/master --include-ref=refs/heads/voice-nonbinary-tts` (history rewrite, 241
commits). `.gitattributes` now has `*.onnx filter=lfs ...` so FUTURE model swaps (v-next voice) auto-go to
LFS — just commit + push normally. Force-pushed master + branch (455d97e→6d63cbc); 146MB LFS objects
uploaded; remote onnx are now pointers. GOTCHAS hit: (1) `git lfs migrate` PROMPTS "[y/N]" on a dirty
tree and HANGS at 0% CPU if backgrounded — run foreground with `</dev/null` on a CLEAN tree; (2)
untracked scratch counts as "dirty" → gitignored .claude/.superpowers/.playwright-mcp/voice-candidates-*/
voice-final/; (3) `--everything` hangs on the prism-waveform worktree branch → target refs explicitly;
(4) after migrate, working tree holds pointers → `git lfs checkout` to re-materialize real files.
LEFTOVER (local only, remote is clean): branches food-editing + prism-waveform still hold pre-LFS onnx
history → local .git stays ~282MB until they're migrated/merged/deleted + gc. Not blocking.
v-NEXT queued: less-breathy source re-clone (same neutral pitch/tone) → corpus regen → retrain with the
buzz-avoiding recipe (low LR / early-clean checkpoint) → drop-in onnx swap (no re-integration needed).

### ✅ RESOLVED (2026-06-02) — voice-final LOCKED: ep24 @ +8% tempo, NO edge
The "harsher/edge + faster" exploration is CLOSED. User verdict (session 96dd2086):
- **Tempo:** +8% (sherpa `speed` 1.08) — "ep_24 at 8% faster is great". Concise style a touch snappier (1.18).
- **Edge (output DSP):** DROPPED — "the edge doesn't sound so good and I think it makes it skew masculine".
- **No retrain needed** — tempo is a free sherpa speed knob on the already-shipped ep24 model.
Shipped in `neural_tts_engine.dart` speak(): `speed = concise ? 1.18 : 1.08`. No DSP filter in the engine.
The breathiness/edge re-derive+retrain fallback below is therefore SHELVED unless new feedback reopens it.

### (SHELVED) v-NEXT — breathiness reduction (2026-06-01)
Surgical phonation-axis edit (NOT a re-roll): dir = clone(PRESSED desc) − clone(BREATHY desc) with
pitch/gender/accent held constant in both descs → seed256 + alpha*||seed256||*unit(dir). Script
/data/hearty-voice/breathiness_candidates.py; embeddings saved design/breathiness/breathiness_embeddings.pt
(keys A0_seed256_orig, P0.04/0.08/0.14/0.22_pressed). F0 noisy but ~138-153 (P0.04 spiked 180=fluke,
skipped). Rendered all 4 candidates × 4 phrases (/data/hearty-voice/design/breath_full/, local /tmp/breath_full/).
User feedback: liked "8 with a minor speed boost — clip/tone of 4 + richer timbre of 8". So AVERAGED
P0.04+P0.08 → `avg_0408` embedding (saved /data/hearty-voice/design/breath_avg/avg_0408_embedding.pt),
rendered 4 phrases at natural + ~8% pitch-preserving speed boost (/tmp/breath_avg/, __x100/__x108).
avg_0408 REJECTED by user — averaging 2 embeddings = ECHO artifact (doubled timbre). Don't average.
User verdict: likes the ORIGINAL seed256 character (A0) and says the SHIPPED ep24 (voice-final) sounds
BEST. Wants voice-final "a little harsher/edge + a bit faster tempo".
KEY: voice-final is the TRAINED model — tempo is a free sherpa speed knob, but harsher phonation is baked
in (would need source re-derive + retrain). TRYING CHEAP SHORTCUT FIRST: tempo via sherpa speed + "edge"
via OUTPUT DSP (one-pole high-freq presence emphasis + soft-clip) on ep24's output — if good, ship as an
app audio-output filter, NO retrain. render_voicefinal_edge.py → voice-samples/voicefinal_edge/
(vf__phrase__sSPEED__edge: s100/108/112, noedge/lightedge/mededge). AWAITING pick of tempo% + edge level.
If DSP edge sounds artificial → fall back: re-derive seed256 with small press nudge (NOT average; small
single-direction like P0.04-0.08) → regen corpus → retrain (early-clean-ckpt) → drop-in onnx (auto-LFS).
NOTE: /tmp wipes on reboot — voice audition samples now kept in gitignored repo dir voice-samples/
(source of truth on pkix /data/hearty-voice/design/). .gitignore has voice-samples/ (works uncommitted).
Buzz-avoiding retrain recipe reminder: train from libritts base, watch every-25, the model stays clean
through ~ep74 then drifts buzzy — pick an early CLEAN checkpoint (ep24 was the sweet spot last time).

### Device verify (Task 1.6) — user running `make run` for ep24 on-device (2026-06-01). Awaiting result.

## Stop / next steps
- Pick best-sounding every-25 checkpoint from the ladder (avoid overtraining; not necessarily epoch 799).
- Task 2.5: blind listening panel (gender-neutral gate).
- Task 2.6: ship chosen `hearty-neutral.onnx`+`tokens.txt`+`espeak-ng-data/` → `hearty_app/assets/tts/`,
  point `NeuralTtsEngine` at it. Export path = `export_for_sherpa.py` (sherpa 1.13.2 verified).
- Task 1.6 (app side): on-device full voice-flow + forced-fallback verify (needs phone on network).

## VOICE-QUALITY FEEDBACK (2026-06-01) — reduce breathiness / slightly harsher
External listener feedback: pitch + tone are GOOD (keep ~143-150Hz neutral + current tonal character),
but the voice is a bit TOO BREATHY → want it a little HARSHER (more pressed/modal phonation, less
aspiration). KEY: breathiness is a SOURCE trait of seed256 (Qwen clone) → inherited by the corpus →
copied by EVERY checkpoint (ep24/49/74/probe all share it). So NO checkpoint pick fixes it; it requires a
SOURCE revision: re-design/re-clone a less-breathy seed (VoiceDesign instruct: "not breathy, pressed/
modal, slightly harsh, clear" while holding the SAME neutral pitch/tone), then regenerate corpus +
retrain. Fold into the next source iteration. SEQUENCING DECISION (user 2026-06-01): **finish ep24 eval first,
then branch** — ep24 solid → ship it + queue less-breathy re-clone as v-next; ep24 has other issues →
roll breathiness fix into the same redo. (Pitch/tone locked-good; only phonation quality changes.)

## OPEN ISSUE — fricative "buzz" distortion (under diagnosis 2026-06-01)
User hears /f/ ("rough"), /s/ ("slow"), /sh/ distorting in the STUDENT; clean in the Qwen teacher/seed.
Onset ~epoch 74, worsens with training. **v1 had the same thing** (the "ch" /tʃ/ complaint) → likely a
SYSTEMATIC corpus→preprocess→train pipeline issue, not v2-specific. Key facts found:
- Corpus wavs are **24000 Hz** (Qwen native); training config sample_rate=**22050** → piper resamples.
- Piper resample = `librosa.load(sr=22050)` (norm_audio/__init__.py:65) = anti-aliased/high-quality,
  so crude aliasing is unlikely. Mel params are stock VITS (fmax≈null→11025).
- My objective unvoiced-HNR metric was inconclusive (silence-contaminated) — rely on user's ear.
- care-line F0 bump to 157 @ep399 was transient (back to 149 @ep424); NOT a feminine drift (other 3
  lines steady ~138-151).
DECISIVE TEST SENT: 3 sibilant corpus clips native24k vs resamp22k. User to report which case:
(A) native buzzes → source data bad (best-of-N screened F0 not audio quality);
(B) only resamp buzzes → resample step; (C) both clean → introduced by piper mel/training.
User verdict: **Case C** — seeds, native24k corpus, AND resamp22k corpus all CLEAN. So audio data is
fine; buzz is introduced downstream (render path or training stage). Both common to v1+v2.
**Localization battery (no GPU retrain), on ep399:**
- noise_scale sweep (sherpa): default 0.667/0.8 == what user heard (NOT a scale mismatch). Lowering
  noise helps — D zero-noise (0.0/0.0) "noticeably better but STILL buzzes" → buzz is PART stochastic
  (noise-driven) + PART deterministic residual in the model output.
- torch-native vs ONNX (RESOLVED): torch-native (raw ckpt, NO onnx) buzzes EVEN MORE than the
  ONNX/sherpa path → **export is NOT the culprit; buzz is TRAINED INTO the model.** Also phoneme-specific:
  /f/ ("rough") worst, /s/ ("slow") clean at ep399/zero-noise.
- BASE test (PENDING user verdict): rendered libritts base (real speech, same arch+harness, multispkr
  sid 0/100, /tmp/base_native.py → base_spk0/100.wav). Base clean → arch capable → our buzz is from the
  SYNTHETIC Qwen corpus (lead hypothesis: Qwen 12Hz-codec high-band periodicity the VITS vocoder
  amplifies; fix = low-pass/clean corpus + retrain, validate with a SHORT ~ep100 2h probe first).
  Base also buzzes → arch/harness limit, different plan.
- BASE verdict: **CLEAN** (user). So localization COMPLETE → buzz is TRAINED-IN from the synthetic
  Qwen corpus. High-band spectrum (/tmp/hiband.png) CONFIRMS: Qwen corpus has an abnormal raised/flat
  ~7-11kHz shelf (~10dB hotter than real-speech base which rolls off); our student reproduces+amplifies
  it → buzz. Mechanism = neural-codec high-band "fill" that VITS periodicity discriminator latches onto.

### v2 RUN STOPPED at epoch 474 (2026-06-01) — buzzy end-to-end, no point to 800.
GPU freed (docker still stopped). Checkpoints 24..474 (every 25) kept in training_v2/output for reference.
Monitor + watcher stopped. Local ladder + ckpts in /tmp/hearty-neutral/epoch00{24..74}..0474.

### CORRECTION (2026-06-01) — high-band theory WRONG; it's fricative-VOICING
User: clean through ep74, buzz ONSETS ~ep99 (mid-training transition, NOT constant); and NO low-pass
cutoff (9/8/7/6kHz) kills the buzz → buzz energy is BELOW 6kHz = BROADBAND periodic. Mechanism =
model VOICING unvoiced fricatives (F0 harmonics through whole spectrum; weak /f/ hit harder than /s/).
The hiband.png shelf was a real-but-IRRELEVANT finding. ⇒ DO NOT rebuild/low-pass the corpus (targets
clean). Loss curves (version_0 events): loss_disc_all flat ~1.9 (NOT collapsing), loss_gen_all stable,
no spike across the transition → "smooth generator drift", not a GAN blow-up.

### LEADING CANDIDATE: epoch 24 (user's pick — "genuinely sounds the best")
User compared clean checkpoints and prefers **ep24** (least-trained clean one) over ep74/probe — to their
ear it's the most natural AND clean (reminder: trust user ear over "more epochs=better"). ep24 ckpt:
training_v2/output/lightning_logs/version_0/checkpoints/epoch=24-step=8400.ckpt. Exported to
/tmp/ep24_export (onnx+tokens). VALIDATION SET (19 varied Hearty-style lines: questions, numbers/times,
fricative stress, long sentence, care) rendered via shipping ONNX→sherpa path → /tmp/ep24_test/, sent to
user. AWAITING verdict. If it passes → LOCK ep24, Task 2.6 (ship onnx+tokens+espeak to
hearty_app/assets/tts/, point NeuralTtsEngine at it). If it stumbles → fall back to ep49/ep74 or a clean
probe ckpt. Probe (below) kept running as backup candidate pool (now DONE: full clean ladder probe ep9..79 in
/tmp/hearty-neutral/probe_epoch00*/, GPU free).

ep24 broad-set verdict: **NO BUZZ anywhere** (incl. fricative torture lines) → ep24 confirmed clean.
Issues: (1) "caffeine"→"caffene" — espeak phonemes are CORRECT (k æ f ˈiː n = kaf-FEEN), so it's ep24
RENDERING the long /iː/ imperfectly = symptom of ep24 being very early/under-trained, NOT a phonemizer
bug. (2) test lines mostly short. Sent LONG set (L1-L8 multi-clause) + caffeine respellings
(/tmp/ep24_long/). AWAITING verdict: if ep24 stays stable on long text → lock + Task 2.6; if it fumbles
words → step up to a slightly-more-trained CLEAN ckpt (ep49/ep74 or probe ep29-79) for more phonetic
precision while staying buzz-free, render same sets to compare. (Caffeine, if persists, also fixable via a
runtime lexicon/respelling normalization in the app text layer.)

### PROBE RUNNING (v3) — resume clean ep74 at 1/5 LR (now BACKUP only; user prefers ep24)
run_probe_v3.py: loads ep74 weights via --resume_from_single_speaker_checkpoint into fresh model+AdamW,
LR forced 4e-5 (1/5 of 2e-4) by patching VitsModel.configure_optimizers (patching __init__ broke
save_hyperparameters → KeyError 'a'; don't do that). max_epochs 80, ckpt every 10, output
training_v3_probe/ (clean v2 ckpts untouched). watcher_v3.sh renders 4 lines/ckpt → deliver_v3/.
DECISION (pre-committed): does "rough" stay CLEAN as prosody firms up? YES → ship from there.
NO (buzz returns as detail sharpens) → next lever = reduce adversarial/feature-matching loss weight in
lightning.py (NOT another corpus, NOT high-LR full retrain).

### (OBSOLETE) earlier FIX PLAN — tame the corpus high band, then retrain
1. Buzz-localization sent: low-passed the buzzy output at 9/8/7/6kHz (/tmp/lp/) → user reports the cutoff
   where buzz dies = the band to filter. (Highest cutoff that kills buzz = best, preserves fricatives.)
2. Build corpus_v3: low-pass each seed256 corpus wav at chosen cutoff + resample→22050 (soxr) into new
   wavs dir. (Consider gentle high-shelf instead of brickwall to keep fricative crispness.)
3. SHORT PROBE first: preprocess + fine-tune from libritts base to ~ep100-150 (~2-3h), render rough/slow.
   Clean → commit full retrain (~16h, every-25). Still buzzy → escalate (lower cutoff / shelf / rethink).
4. Source/corpus seed256 (LOCKED_v2) UNCHANGED — only the high-band filtering is new. Neutral pitch + the
   128-160/target143 F0 screening stay.
Render-path tooling proven: piper infer noise defaults 0.667/1.0/0.8; sherpa defaults identical;
torch infer via VitsModel.load_from_checkpoint(map_location=cpu) + phonemize_espeak/phoneme_ids_espeak
+ model_g.infer(x,xl,noise_scale,length_scale,noise_scale_w,sid). Current 800-run still going (free,
quantifies worst-case); ship-blocker is localization, not yet a fix.

## Power-loss / crash recovery (TESTED 2026-06-01)
Detached procs die on reboot but ALL data persists on /data (corpus, preprocessed, every-25 ckpts).
To resume training from the latest checkpoint:
1. `ls .../training_v2/output/lightning_logs/version_*/checkpoints/*.ckpt` → newest epoch.
2. Run `/data/hearty-voice/run_resume_v2.py` (edit the `CK=` path to the newest ckpt) with nohup.
   **It MUST monkeypatch `torch.load` to `weights_only=False`** — PyTorch 2.6+ defaults it True and
   rejects the `PosixPath` stored in our Lightning ckpts (a plain `--resume_from_checkpoint` CLI run
   would crash on load). The base ckpt didn't trip this; our v2 ckpts do.
3. Relaunch `ckpt_watcher_v2.sh` (idempotent — skips epochs with a `.done`).
4. Re-arm the Monitor on the agent side if the session was lost.
**GOTCHA:** after resume the process is `run_resume_v2.py`, NOT `-m piper_train`. The watcher's and
Monitor's liveness check must `pgrep -f 'piper_train|run_resume_v2'` — otherwise the watcher decides
training "finished," renders nothing new, and exits (cost us epochs 124/149 once). Already patched in
`ckpt_watcher_v2.sh`.
Resume restores optimizer+epoch and continues (don't use `--resume_from_single_speaker_checkpoint`
to resume — that's only for adapting the multi-speaker base and resets to epoch 0).

## Known gotchas (don't re-trip)
- Use `--resume_from_single_speaker_checkpoint` (NOT `--resume_from_checkpoint`) — triggers 904→1 speaker
  adaptation; `__main__.py` patched to drop the `assert num_speakers>1`. `chain_train.sh` (v1) line 34 is stale.
- export needs ONNX metadata injected + tokens.txt literal-space token (`export_for_sherpa.py` handles it).
- ORT: sherpa 1.24.3 vs wake-word — app bumped onnxruntime-android to 1.24.3 + `pickFirst`. Wake word re-verified.
- VoiceDesign is per-call non-deterministic → we CLONE a locked embedding. Seed dominates pitch (sweep 124→182Hz).
