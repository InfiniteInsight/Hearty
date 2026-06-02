# Follow-Up Restart Beep Suppression — Design

**Date:** 2026-06-02
**Status:** Approved (pending spec review)
**Branch:** voice-beep-mute
**Area:** `hearty_app` voice follow-up flow + Android native audio

## Problem

When Hearty asks a follow-up question and the user answers with pauses, the
follow-up flow restarts the Android `SpeechRecognizer` up to 3 times to keep the
mic open and stitch the answer together (`_maxFollowUpRestarts`, intended
behavior — Android ignores `pauseFor` and ends each session after its own ~2–3s
silence timeout). Each session start/stop plays Android's native recognizer beep,
so the user hears a confusing run of ~3 beeps. The first beep is useful ("I'm
listening"); the subsequent restart beeps are noise and read as a malfunction.

## Goal

Keep exactly **one** audible beep — the initial one when the follow-up mic first
opens — and silence every beep from the restart sessions. Preserve the
restart/stitching behavior unchanged (it is what lets users pause mid-answer).

## Non-goals

- Removing the restart mechanism or changing recognition behavior.
- On-device recognition (`onDevice: true`) — considered and rejected: it could
  avoid the beep at the source on some devices, but imposes a recognition-accuracy
  cost on continuation speech for every user, while stream-muting already silences
  the beeps reliably. Kept in reserve only if real devices still beep.
- Silencing the *first* beep (it is intentional feedback).
- The wake-word / first-turn (non-follow-up) path — unaffected.

## Why native

The beeps are Android's `SpeechRecognizer` system sounds; `speech_to_text` exposes
no API to suppress them. The only lever is muting the audio stream the beep plays
on, via `AudioManager` in native Kotlin.

## Cross-device strategy

There is no API to query which stream the recognizer beeps on, and it varies by
OEM/version. So we do not detect — we **cover the candidate set**: mute
`STREAM_MUSIC`, `STREAM_SYSTEM`, and `STREAM_NOTIFICATION` for the suppression
window and restore them. Muting the extras is harmless in this window (active
listening, no media playing, user not tapping UI). The residual risk is an exotic
device that beeps on a stream outside the set — there the beep simply is not
suppressed (cosmetic), never a functional failure.

## Behavior / timing

1. **First follow-up session** (`_followUpRestarts == 0`): no muting → the initial
   beep plays.
2. **~800 ms after that first session starts** (after the short start beep, well
   before Android's ~2–3s silence cutoff that ends session 1): engage muting and
   keep it engaged. This catches session 1's *stop* beep and all restart beeps.
3. **Restart sessions:** silenced by the already-engaged mute. No recognizer change.
4. **On resolve** — submit (`setThinking`), tap-to-talk pause (`_pauseFollowUpMic`),
   `dismiss`, final `_onSttError`, app backgrounded, or `dispose` — restore audio
   immediately.

Net: one beep when the follow-up mic first opens, silence through the restarts.

## Components

### Native — `MainActivity.kt`
- Register a new `MethodChannel("com.hearty.app/audio")`.
- Method `setBeepSuppressed(bool suppressed)`:
  - `true`: for each of `STREAM_MUSIC`, `STREAM_SYSTEM`, `STREAM_NOTIFICATION`,
    record the current state and mute it. Track that *we* muted (so we never
    restore a stream the user already had muted). No-op if already suppressed.
  - `false`: restore each stream we muted to its recorded state; clear tracking.
    No-op if not currently suppressed.
  - Whole body wrapped in try/catch — log and continue on failure; never throw back
    to Dart (a failed mute is a cosmetic beep, not a crash).
- Implementation detail (decide at build time, test on device): prefer
  `adjustStreamVolume(stream, ADJUST_MUTE/ADJUST_UNMUTE, 0)`; if that proves
  unreliable on the Pixel, fall back to save/restore via
  `getStreamVolume`/`setStreamVolume`.

### Dart — `AudioBeepChannel` (new, `hearty_app/lib/core/audio/audio_beep_channel.dart`)
- Thin wrapper over `MethodChannel('com.hearty.app/audio')`:
  - `Future<void> suppress()` → `invokeMethod('setBeepSuppressed', true)`
  - `Future<void> restore()` → `invokeMethod('setBeepSuppressed', false)`
- Swallows and logs platform exceptions so callers never need try/catch.
- Injectable into `VoiceNotifier` for testing (constructor param, defaulting to the
  real channel), mirroring `sttForTesting`/`ttsForTesting`.

### `voice_provider.dart`
- New field: `Timer? _beepSuppressTimer;` and `bool _beepSuppressed = false;`
- New const: `Duration _beepSuppressDelay` (default 800 ms; injectable for tests).
- In `_beginStt`, when `isFollowUp && _followUpRestarts == 0`: cancel any existing
  `_beepSuppressTimer`, then start one for `_beepSuppressDelay`; on fire, if still
  `mounted && state.status == VoiceStatus.awaitingFollowUp`, call
  `_beep.suppress()` and set `_beepSuppressed = true`.
- New `void _releaseBeepSuppression()`: cancel `_beepSuppressTimer`; if
  `_beepSuppressed`, call `_beep.restore()` and set `_beepSuppressed = false`.
  Idempotent.
- Call `_releaseBeepSuppression()` from every follow-up exit path:
  `setThinking`, `_pauseFollowUpMic`, `dismiss`, the terminal branch of
  `_onSttError`, and `dispose`.

## Failure handling

- Native mute failure → caught natively, logged, listening unaffected (beep may
  play).
- The single `_releaseBeepSuppression()` funnel guarantees restore on every exit,
  so audio can never be left muted. `dispose` is a final backstop.

## Testing

**Dart unit tests** (`voice_provider_test.dart`) with a fake `AudioBeepChannel`
(records suppress/restore calls) and the existing fake `SpeechToText`, with
`_beepSuppressDelay` set near-zero:
- First follow-up listen schedules `suppress()`; it fires after the delay only if
  still in `awaitingFollowUp`.
- Cancelling the follow-up before the delay (dismiss) → `suppress()` never called.
- `restore()` is called on each exit path: submit→thinking, pause, dismiss, error.
- `restore()` is idempotent (multiple exits don't double-restore).

**On-device** (Pixel 4a over wifi): trigger a follow-up, answer with a pause —
confirm only the first beep is audible, restart beeps silent, and the multi-pause
answer still transcribes. Verify other audio (media) is unaffected after the turn.

## Open questions

None blocking. Exact `AudioManager` muting call validated on the Pixel during
implementation; the 800 ms delay tuned on-device if needed.
