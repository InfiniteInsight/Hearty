#!/usr/bin/env bash
# TEMPORARY — Whisper/STT on-device spike (docs/superpowers/plans/
# 2026-06-07-voice-rebuild-whisper-ondevice-spike.md, Task S0).
#
# Downloads the four pre-built sherpa-onnx ASR models, extracts them, and
# `adb push`es each into its own dir under the Hearty app's external files so the
# whisper-spike probe screen can benchmark them. No pkix, no GPU, no conversion —
# these are pre-exported release assets. Run on the dev box that has wifi-adb to
# the Pixel 4a. Delete this script (and the on-device spike-* dirs) on teardown.
#
# Usage:   bash scripts/spike-download-push-models.sh
# Re-run:  safe — skips tarballs already downloaded and re-pushes.
set -euo pipefail

BASE="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models"
WORKDIR="${TMPDIR:-/tmp}/hearty-spike-models"
PKG="com.hearty.app"
DEST="/sdcard/Android/data/${PKG}/files"

# tarball-basename  ->  device-dir-name   (extracted dir == tarball basename)
declare -A MODELS=(
  ["sherpa-onnx-whisper-base.en"]="spike-whisper-base"
  ["sherpa-onnx-whisper-small.en"]="spike-whisper-small"
  ["sherpa-onnx-moonshine-base-en-int8"]="spike-moonshine-base"
  ["sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8"]="spike-parakeet-tdt"
)

command -v adb >/dev/null || { echo "ERROR: adb not on PATH"; exit 1; }
if ! adb get-state >/dev/null 2>&1; then
  echo "ERROR: no device via adb. Connect the Pixel (wifi-adb) first."; exit 1
fi

mkdir -p "$WORKDIR"
cd "$WORKDIR"
echo "Workdir: $WORKDIR   Device dest: $DEST"
echo

for name in "${!MODELS[@]}"; do
  tar="${name}.tar.bz2"
  devdir="${MODELS[$name]}"

  if [[ ! -f "$tar" ]]; then
    echo "↓ downloading $tar"
    curl -L --fail --retry 3 -o "$tar" "$BASE/$tar"
  else
    echo "✓ have $tar (skip download)"
  fi

  if [[ ! -d "$name" ]]; then
    echo "  extracting…"
    tar xjf "$tar"
  fi

  size=$(du -sh "$name" | cut -f1)
  echo "→ pushing $name ($size) → $DEST/$devdir/"
  adb shell "mkdir -p $DEST/$devdir"
  # Push the extracted dir's CONTENTS into the device dir.
  adb push "$name/." "$DEST/$devdir/" >/dev/null
  echo "  done ($devdir, on-disk $size)"
  echo
done

echo "Pushed model dirs on device:"
adb shell "ls -1 $DEST | grep '^spike-'"
echo
echo "Next: record p1..p8 WAVs → adb push to $DEST/spike-wavs/  (Task S1),"
echo "then 'make run' → Settings → '▶ Whisper/STT spike (dev)' → Run all (Task S4)."
echo "Local tarballs cached in $WORKDIR — 'rm -rf' it when the spike is done."
