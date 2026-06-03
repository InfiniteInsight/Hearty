# Daily Check-in — Design Spec

**Date:** 2026-06-03
**Status:** Design approved (brainstorming). Implementation deferred — blocked on resolving the current dictation/voice bugs, since this feature is voice-first.

## Goal

An optional **end-of-day check-in** in which Hearty asks a small number of leading
questions to fill gaps in the day's logs, turning passive logging into a gentle
review. Answers write back as real structured data, so the record gets more
complete and correlations/trends downstream have better material to work with.

## Why this feature exists

Throughout the day the log accumulates gaps: meals logged without any record of
how the user felt afterward, foods Hearty wasn't confident it parsed, and
stretches of the day with nothing logged. Some of these are also the residue of
**dismissed in-the-moment follow-ups** (see "Relationship to the existing
symptom follow-up" below). The daily check-in is the calm, end-of-day safety net
that catches what the live flow missed — without nagging.

## Scope

**In scope:** detection of three gap types, an evening smart-notification trigger
plus a manual entry point, a preview/queue screen, a skippable voice-first
(text-optional) question cycle, and full structured write-back of answers.

**Out of scope (separate specs):**
- The **monthly trends conversation** — its own design + plan.
- **Confidence scoring in `extract_meal()`** — a hard dependency of gap type C
  (see C below). May be split into its own plan or included as a prerequisite
  phase; the plan must treat it as a gate, not assume it exists.

---

## Gap detection

Detection runs over a single target day's logs and produces an ordered list of
gaps. Three types:

### A · Meal → symptom gap
A meal with **no symptom entry logged within ~3 hours after it**.
> *"You had the buldak ramen around 1pm — how did your stomach feel after?"*

Threshold (`SYMPTOM_GAP_WINDOW`) default: **3 hours**. Adjustable.

### C · Low-confidence food  ⚠️ depends on confidence scoring
Any extracted food whose extraction confidence is **below a threshold**.
> *"I logged 'buldak ramen' but wasn't sure — did I get that right?"*

**Hard dependency:** `extract_meal()` does not currently emit a confidence score.
This gap type cannot ship until confidence scoring is added to the extraction
pipeline. The implementation plan MUST gate C on that work (either a prerequisite
phase in this feature's plan, or a separately-sequenced plan). If confidence
scoring is absent, gap type C is simply not produced — A and D still function.

### D · Missing chunk
A stretch **longer than ~5 hours with no logs**, falling inside the user's waking
window.
> *"Nothing logged between breakfast and 4pm — did you eat in there?"*

Threshold (`MISSING_CHUNK_WINDOW`) default: **5 hours**. Waking window default:
**08:00–22:00** (adjustable; a sensible default until/unless user-configurable).

### Where & when detection runs
The "smart notification only if gaps" behavior requires detection to run
**before** the notification fires — a **scheduled background task** that queries
the target day's logs in the evening and conditionally posts the notification.
On Android this is subject to background-execution limits; the plan must name the
concrete mechanism (e.g. WorkManager-backed periodic work, or a scheduled local
notification whose payload triggers detection on tap as a fallback). This is a
known implementation constraint, called out here so the plan does not hand-wave
it.

---

## Relationship to the existing symptom follow-up (critical)

The app already ships a **per-meal symptom follow-up** (`primeForSymptomFollowUp`
/ `VoiceStatus.awaitingFollowUp`, the flow associated with the earlier "ding
storm" work) that asks "how did you feel after that meal?" right after logging.
Gap type **A is the same question, batched to the evening.** Without a defined
relationship the two would double-ask. Rules:

- **Follow-up answered** → the meal already has a symptom → **excluded** from
  evening gaps.
- **Follow-up still pending/queued** → do **not** preempt it; the meal does not
  become an evening gap (yet).
- **Follow-up dismissed/skipped** → the meal **resurfaces once** in the evening
  check-in as a gap A. If skipped again *there*, it is gone for good (no further
  retries). This "resurface exactly once" rule is the safety-net-without-nagging
  behavior.

This means gap A's detection query is not merely "meal lacking a symptom within
3h" — it must also respect follow-up state and a "resurfaced once" marker so a
twice-skipped meal is never asked a third time. The plan needs a small piece of
per-meal state to track that an evening retry has already been offered.

---

## Trigger

1. **Evening smart notification** — fires **only if** detection finds at least one
   gap (silent on clean days). Day-anchored (see "Late taps & expiry").
2. **Manual "Review my day" button** — always available in the app. Target day =
   the **most-recent-completed day** OR today with gap D only flagged up to "now"
   (so a 2pm tap doesn't flag the unlived afternoon). Default: review **today up
   to the current time**; gap D only considers elapsed waking hours.

---

## Late taps & expiry

The notification is **day-anchored**: it carries its own date, and tapping it —
whenever — opens the review for *that* day, with all write-backs targeting *that*
day (never today). Because recall quality decays quickly:

- A missed notification **expires after ~48 hours.** Tapped the next morning it
  still works on the prior day's data; tapped 3 days later it gently reports
  "this review has expired" and no-ops.
- Gaps from missed/expired days are **not** rolled into a backlog and are **not**
  revisited (keeps the feature from becoming a chore and avoids encouraging
  unreliable "I think I ate something?" guesses).

`CHECKIN_EXPIRY` default: **48 hours**. Adjustable.

---

## Preview / queue screen

Before any back-and-forth, tapping the notification or button opens a **preview
screen**:

- Shows the **total** ("4 things to review").
- Lists gaps **highest-value first.** Priority order: **A (symptom gaps) → C
  (uncertain foods) → D (missing chunks)** — health signal first, data hygiene
  last.
- User can **skip any individual item** or **skip all**, then **Begin**.

This gives a finite, controllable sense of the work before committing.

---

## The check-in cycle

- **Voice-first**, reusing the existing voice overlay; **text input always
  available** as a fallback.
- Presents the queued gaps **one at a time**, in priority order, each **skippable
  mid-flow**.
- Ends with an explicit "that's everything for today" so the session always feels
  finite.

---

## Write-back — full structured (no light notes)

Answers become the **same quality of data as normal logging**:

- **A (symptom gap)** → creates a real **symptom entry** linked to that meal /
  time on the target day.
- **C (low-confidence food)** → on correction, **updates the actual meal record**
  (re-extract or direct edit of the food); on confirmation, marks it confirmed.
- **D (missing chunk)** → "yes, I had X at 3pm" runs a **mini-extraction** and
  logs a **real meal entry** on the target day; "no, I didn't eat" records that
  the gap was reviewed so it is not re-flagged.

All writes are date-stamped to the **target day**, not the day of the tap.

---

## Components (for the plan to decompose)

- **Gap detector** — pure-ish function: `(day's logs, follow-up state, thresholds)
  → ordered List<Gap>`. Independently testable. One responsibility.
- **Gap model** — typed representation (`GapType`, target entity ref, prompt text,
  priority). Includes the per-meal "evening retry already offered" marker for A.
- **Scheduler / notification poster** — background task that runs the detector in
  the evening and conditionally posts the day-anchored notification; handles
  expiry on tap.
- **Preview screen** — lists gaps, supports skip-any / skip-all / begin.
- **Check-in cycle controller** — drives the voice-first/text question loop over
  the queued gaps; per-gap skip; reuses the voice overlay.
- **Write-back handlers** — one per gap type (symptom create, meal update,
  mini-extraction meal create), reusing existing logging paths.

---

## Testing focus

- **Detector** unit tests: each gap type's threshold boundary; the follow-up
  relationship matrix (answered → excluded; pending → excluded; dismissed →
  resurfaces once; dismissed-then-evening-skipped → never again); D's
  waking-window and "up to now" handling.
- **Expiry** logic: < 48h works on target day; > 48h expires; write-backs target
  the anchored day not the tap day.
- **Priority ordering** of the preview queue.
- **Write-back** tests: each handler produces a correct structured entry on the
  target day, reusing existing logging code paths.
- C's tests are gated behind confidence scoring existing.

---

## Open dependencies (must be resolved before/within implementation)

1. **Dictation/voice bugs** — feature is voice-first; do not implement until the
   current dictation handling is stable.
2. **Confidence scoring in `extract_meal()`** — gate for gap type C.
3. **Android background-execution mechanism** for the evening detection run — name
   it concretely in the plan.
