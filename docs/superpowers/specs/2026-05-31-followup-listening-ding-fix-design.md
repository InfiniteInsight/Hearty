# Follow-Up Listening: Ding Storm Fix — Design

**Date:** 2026-05-31
**Status:** Approved (pending spec review)
**Area:** `hearty_app` voice follow-up flow

## Problem

When the post-meal follow-up notification fires and the user taps it, they land on
the voice overlay and hear the Android "listening" beep several times followed by
the "stopped listening" beep several times before transcription finally works.

## Root cause

The follow-up flow opens the mic *immediately* on screen open
(`primeForSymptomFollowUp` → `_beginStt`), before the overlay is fully visible and
before the user has oriented. While the user reads the question and is silent,
Android's native `SpeechRecognizer` hits its own short silence timeout and fires
`notListening`. The restart hack in `voice_provider.dart` (`_onSttStatus`, and the
`onResult` `finalResult` branch) then restarts the session — **with no check for
whether the user has actually started speaking** — burning its full
`_maxFollowUpRestarts` (3) budget on that initial orientation silence. Each
start/stop of the native recognizer plays a beep, so the budget is spent as a rapid
storm of dings before the user has said anything. Only a later session catches their
speech.

The beeps themselves are Android's native recognizer sounds (not played by Hearty
code) and are not suppressible via the `speech_to_text` API.

## Goal

Collapse the storm to ~one clean session: tap notification → read question → mic
opens once → speak → roughly one start beep + one stop beep. A single ding is
desirable — it tells the user the mic is live. We are only removing the *redundant*
dings, not all of them.

## Non-goals

- Eliminating the single legitimate beep (would need native `AudioManager` muting —
  deferred; explicitly not wanted, the ding is useful feedback).
- The countdown-timer UI (separate, deferred feature).
- Changing the wake-word `startListening()` path — it stays immediate, since the
  user just deliberately invoked it and needs no orientation delay.

## Behavior

Scope: the follow-up path only (`primeForSymptomFollowUp`).

1. **Orientation delay.** Show the question first, then wait a tunable delay
   (default 2.5s) before opening the mic. The delay is a *cancelable* timer: if the
   overlay is dismissed (or state leaves `awaitingFollowUp`) during it, the mic
   never opens. The duration is injectable so tests run it at zero.

2. **Restart only after speech.** Both restart sites gain a
   `state.transcript.isNotEmpty` guard:
   - `_onSttStatus`: restart on premature `notListening`/`done` only if some speech
     was already captured.
   - `onResult` `finalResult` branch: same guard before restarting.
   Pre-speech silence no longer burns the restart budget → no ding churn. Mid-answer
   pauses (transcript already populated) still restart up to the existing limit so
   the user can finish their thought — unchanged.

3. **Tap-to-talk fallback.** Because pre-speech silence no longer auto-restarts, a
   first window that ends with an empty transcript leaves the mic idle rather than
   churning. The overlay surfaces a "Tap to talk" mic button so the user is never
   stranded (their tap opens one user-initiated session — one expected ding). The
   existing text input remains available.

Net: the orientation delay removes the up-front churn; the restart-after-speech
guard prevents any residual pre-speech churn; the tap-to-talk button covers the
case where the user is still silent after the delay.

## Mechanics

**`hearty_app/lib/features/voice/models/voice_state.dart`**
- Add `enum MicPhase { none, preparing, listening, paused }` and a
  `final MicPhase micPhase;` field (default `MicPhase.none`), included in the
  constructor and `copyWith`. This explicitly disambiguates the three follow-up
  visuals that would otherwise collide on "mic off + empty transcript":
  - `preparing` — orientation delay running → question + "Getting ready…"
  - `listening` — session open → active waveform
  - `paused` — a session ended with nothing captured → "Tap to talk"
  - `none` — not in the follow-up mic flow (e.g. wake-word listening, thinking).

**`hearty_app/lib/features/voice/providers/voice_provider.dart`**
- Add a tunable follow-up start delay (e.g. `Duration _followUpStartDelay`, default
  2.5s, settable via constructor for tests) and a cancelable `Timer?` so dismiss/
  teardown cancels a pending start.
- `primeForSymptomFollowUp`: set `awaitingFollowUp` state with
  `micPhase: MicPhase.preparing`, start the cancelable delay timer; on fire (still
  mounted + still `awaitingFollowUp`) call `_beginStt(isFollowUp: true)`.
- `_beginStt`: set `micPhase: MicPhase.listening` when `_stt.listen` is invoked.
- `_onSttStatus`: restart branch additionally requires `state.transcript.isNotEmpty`.
  When it does not restart and is in follow-up with empty transcript, set
  `micPhase: MicPhase.paused` (tap-to-talk) instead of churning.
- `onResult` `finalResult` restart branch: add the `state.transcript.isNotEmpty`
  guard.
- Add `void resumeFollowUpListening()` — used by the tap-to-talk button — which
  re-opens one follow-up session (`_beginStt(isFollowUp: true)`, which sets
  `micPhase: listening`) without resetting accumulated transcript destructively.
- Cancel the delay timer in `dismiss()`/teardown.

**`hearty_app/lib/features/voice/screens/voice_overlay_screen.dart`**
- In `awaitingFollowUp`, branch on `state.micPhase`:
  - `preparing` → question + a calm "Getting ready…" hint (no active waveform, so it
    does not look like it is already listening).
  - `listening` → active waveform (as today).
  - `paused` → a "Tap to talk" mic button wired to `resumeFollowUpListening()`.
  The existing transcript display / submit row behavior is unchanged.

## Testing

`voice_provider` tests with an injected `SpeechToText` mock and the start delay set
to zero:
- Follow-up does **not** call `_stt.listen` synchronously in
  `primeForSymptomFollowUp`; it calls it only after the delay elapses.
- Dismissing during the delay cancels the pending start (no `listen` call).
- Premature `notListening` with an **empty** transcript does **not** trigger a
  restart (no second `listen`); `micPhase` becomes `paused`.
- Premature `notListening` with a **non-empty** transcript **does** restart
  (matches existing behavior).
- `resumeFollowUpListening()` opens a session and sets `micPhase` to `listening`.
- `micPhase` is `preparing` between `primeForSymptomFollowUp` and the delay firing.

## Base branch

The follow-up feature (`isFollowUp`, `primeForSymptomFollowUp`) lives on
`voice-nonbinary-tts` (partly committed, partly WIP) and does not fully exist on
`master`, so this work must build on the voice branch state, not `master`. Exact
branch/worktree handling to be decided at implementation time (see the prior
food-editing reorg for why isolation matters).

## Open questions

None blocking. Delay default (2.5s) will be tuned on-device.
