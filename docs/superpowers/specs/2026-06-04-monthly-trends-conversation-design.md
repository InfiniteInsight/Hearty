# Monthly Trends Conversation — Design Spec

**Date:** 2026-06-04
**Status:** Design approved (brainstorming). Implementation deferred — voice-first
feature, blocked on resolving the current dictation/voice bugs.

## Goal

A roughly **monthly, turn-based voice conversation** (text-optional) in which
Hearty explains the patterns it has found in the user's data and the user's
reactions feed back to make future analysis smarter. It is the user-facing
delivery layer over the trend analysis that already exists but is currently
invisible.

## Why this feature exists

The backend already computes rich correlations — `signal_engine.py` produces
`food_signals` (food category → symptom/wellbeing outcome, harmful/beneficial
direction, unified score, relative risk, evidence count) via counterfactual
relative-risk analysis over a rolling window. **None of it is surfaced to the
user.** This feature turns that dormant data into a warm, reflective monthly
conversation, and — crucially — lets the user confirm or dispute patterns so the
signal set gets more trustworthy over time.

## Scope

**In scope:** a decoupled conversation engine grounded in existing `food_signals`,
a turn-based voice I/O layer (text-optional), a monthly smart-notification trigger
plus a manual entry point, hybrid conversation flow with guaranteed signal
coverage, and a bidirectional feedback overlay (confirm / dispute / snooze).

**Explicitly NOT in scope (existing or future):**
- **Trend detection itself** — already built (`signal_engine.py`,
  `/api/trends/analyze`, `food_signals`). This feature *consumes* it; it does not
  modify or rebuild it.
- **Tracked experiments** (option C from brainstorming — "cut dairy for two weeks
  and I'll watch, then compare before/after") — a compelling follow-on that gets
  its **own spec and plan later**. Not built here.
- **Streaming duplex voice** ("true Gemini Live") — see I/O layer below; the
  engine is designed so this can be added later without redesign.

## What already exists (consume, don't rebuild)

- `hearty-api/app/services/signal_engine.py` — unified signal engine; deletes and
  recomputes all signals per run.
- `food_signals` table — `user_id`, `category`, `outcome_type`
  (symptom/wellbeing), `outcome_name`, `direction` (harmful/beneficial),
  `unified_score`, `relative_risk`, `score_delta`, `evidence_count`.
- `POST /api/trends/analyze` (runs analysis, `period_days=90`) and
  `GET /api/trends/analyze/status` (precheck: is there new data worth analyzing).
- Idle background analysis via the `com.hearty.app/analysis` MethodChannel →
  `AnalysisWorker`.
- `health_profile.last_analyzed_at` tracks when analysis last ran.

---

## Architecture — decoupled engine + swappable I/O

### Conversation engine (backend, new — pure, no voice)
A new endpoint, e.g. **`POST /api/trends/conversation`**, that takes:
- the conversation history (turns so far), and
- the user's current signals **filtered through the feedback overlay** (see
  below),

and returns **Hearty's next turn** plus any **proposed verdict** to surface. It is
a single LLM call (litellm, same path as `extract_meal`). A system prompt defines:
- Hearty's warm, reflective, plain-language persona (no clinical jargon, no
  alarmism).
- The **hybrid coverage** behavior (see Conversation flow).
- Instructions to detect when the user has expressed a verdict and to emit it as a
  **structured proposed-verdict** for client confirmation (never a silent write).

This engine is **pure** with respect to modality — it knows nothing about voice.

### I/O layer (Flutter — turn-based now, streaming-ready)
- **Turn-based v1:** reuse the existing voice pipeline — STT captures the user →
  call the conversation engine → neural TTS speaks Hearty's turn → repeat.
  Text input is always available as a fallback.
- The boundary between the I/O layer and the engine is clean enough that a
  **streaming duplex** implementation (realtime model API + real-time audio) can
  replace the turn-based layer later without touching the engine. Streaming is
  out of scope for v1.

---

## Trigger (mirrors the daily check-in)

1. **Monthly smart notification** — fires only when there are signals worth
   discussing. Reuses the existing `GET /api/trends/analyze/status` precheck (is
   there new evidence / new signals since last time). Silent when there's nothing
   meaningful to say.
2. **Manual "Talk about my trends"** button — always available in the app.

"Monthly" = cadence target, gated by the precheck; do not force a conversation on
a month with no meaningful change.

---

## Which signals come up

- Whatever `signal_engine` emits **above its existing thresholds** (e.g.
  `MIN_RR=1.5`, `MIN_EXPOSED_MEALS`, `MIN_UNEXPOSED_MEALS`, evidence counts) — this
  feature does **not** introduce new statistical thresholds.
- **Both harmful and beneficial** directions.
- Ranked by **`unified_score`** (highest first) for the "headline" and coverage
  order.
- **New since last conversation** is flagged (compare against the last
  conversation timestamp / previously-surfaced set).
- **Confirmed** patterns (see feedback) are summarized briefly as established —
  not re-litigated each month.

---

## Conversation flow (hybrid — option C)

- Hearty **opens conversationally** with the top headline ("The big thing this
  month — dairy keeps coming up before your bloating, and it's a fairly strong
  pattern.").
- The conversation is **free-form back-and-forth**: the user can steer, ask
  questions, and Hearty answers grounded in the signals.
- **Guaranteed coverage:** before wrapping, Hearty surfaces each *significant*
  signal at least once ("Before we finish, there are two more I noticed…"), so the
  feedback loop actually collects verdicts on the patterns that matter.
- Ends with a clear, finite close.

---

## Feedback loop (bidirectional — option B)

### Feedback overlay (new, separate from `food_signals`)
Because `signal_engine` **deletes and recomputes** all signals per run, verdicts
must NOT live on signal rows. A separate **feedback-overlay table**, keyed by
**(user_id, category, outcome_type, outcome_name)**, stores the user's standing
verdict and is applied whenever signals are presented or recomputed. Suggested
fields: the verdict (`confirmed` / `disputed` / `snoozed`), the
`score_at_verdict` (the `unified_score` when the verdict was given — needed for
honest resurfacing), and a timestamp.

### Verdict semantics
- **Confirm** ("yeah, that tracks") → the pattern is **locked in as established**;
  surfaced briefly as confirmed thereafter, not re-litigated.
- **Dispute** ("nah, dairy's fine for me") → **down-weighted**: dropped from the
  conversation, and only allowed to **resurface** if the evidence later gets
  *much* stronger than at dismissal (compare current `unified_score` against
  `score_at_verdict` by a meaningful margin). When it does resurface, Hearty
  acknowledges the prior verdict ("I know you felt dairy was fine, but it's
  showing up a lot more strongly now — worth another look?").
- **Snooze / unsure** → leave as-is; keep gathering evidence; eligible again next
  time.

### Verdict capture (no silent writes)
Hearty **detects** a verdict from the conversation, but the verdict is **never
written from a possibly-misheard phrase**. Instead it is surfaced as a
**confirmable chip** ("Got it — mark dairy → bloating as *not a problem for you*?")
that the user taps to confirm before the overlay is written. This protects data
integrity given the voice/dictation reliability concerns.

---

## Components (for the plan to decompose)

- **Conversation engine endpoint** (`POST /api/trends/conversation`) — pure
  LLM-backed turn generator; takes history + overlay-filtered signals → next turn
  + proposed verdict. Independently testable with fixture signal sets.
- **Signal presenter** — backend logic that loads `food_signals`, applies the
  feedback overlay (suppress disputed unless resurfacing condition met; mark
  confirmed; flag new), and ranks by `unified_score`. One responsibility; unit
  testable.
- **Feedback overlay store** — table + read/write for verdicts (confirm / dispute
  / snooze), including `score_at_verdict` for resurfacing.
- **Verdict endpoint** — writes a confirmed verdict to the overlay.
- **Monthly trigger** — reuses `/api/trends/analyze/status`; posts the monthly
  notification only when there's something to say. Plan must name the concrete
  Android scheduling mechanism (same constraint family as the daily check-in's
  background run).
- **Conversation I/O layer** (Flutter) — turn-based STT ↔ engine ↔ TTS, with text
  fallback and verdict-confirmation chips; decoupled from the engine for future
  streaming.
- **Manual entry point** — "Talk about my trends" button.

---

## Testing focus

- **Signal presenter** unit tests: overlay application — disputed signals
  suppressed; disputed signal resurfaces only when current score exceeds
  `score_at_verdict` by the defined margin; confirmed signals marked established;
  "new since last conversation" flagging; ranking by `unified_score`.
- **Verdict overlay** persistence across a simulated `signal_engine` recompute
  (verdicts survive delete-and-recompute).
- **Conversation engine** tests with fixture signal sets: produces a sensible
  headline, covers all significant signals before closing (hybrid guarantee),
  emits a structured proposed-verdict when the user expresses one and does NOT
  emit one otherwise.
- **Verdict capture** never writes without explicit confirmation.
- **Trigger** fires only when the status precheck reports meaningful new signals.

---

## Open dependencies (must be resolved before/within implementation)

1. **Dictation/voice bugs** — feature is voice-first; do not implement until the
   current dictation handling is stable.
2. **Android background-execution mechanism** for the monthly trigger — name it
   concretely in the plan (shares the daily check-in's constraint).
3. Confirm the exact `food_signals` field names and `analyze/status` response
   shape against the live backend when writing the plan (this spec cites them from
   a code survey).

---

## Relationship to the daily check-in

These two features are **sequenced and synergistic**: the daily check-in keeps the
day-to-day data complete and clean; the monthly trends conversation is only as
good as that data. They share patterns deliberately (smart-notification + manual
button trigger, voice-first/text-optional, confirmable verdicts, queue/coverage
discipline) but are independent specs and plans.
