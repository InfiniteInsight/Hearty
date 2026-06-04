# Daily Check-in Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An optional, voice-first (text-optional) end-of-day check-in where Hearty detects gaps in the day's logs (meal→symptom, low-confidence food, missing chunk), presents them in a skippable review queue, and writes the user's answers back as real structured data.

**Architecture:** A backend **gap detector** (pure logic over a target day's meals/symptoms/follow-up state + thresholds) returns an ordered gap list via `GET /api/checkin/gaps`. Answers reuse the **existing** meal/symptom write paths. A Flutter **preview screen** + **skippable cycle** (reusing the voice overlay) drives it; a **day-anchored smart notification** (48h expiry) plus a manual button trigger it. Gap A is gated on persisting follow-up outcome server-side; gap C is gated on confidence scoring in `extract_meal`.

**Tech Stack:** FastAPI + Supabase (python client, service key) + litellm; Flutter + Riverpod + Drift + Dio + go_router + flutter_local_notifications + the (in-rework) voice pipeline; Supabase SQL migrations.

**Spec:** `docs/superpowers/specs/2026-06-03-daily-checkin-design.md`

---

## Prerequisites (ordered gate-tasks)

- **GATE-1 — Dictation/voice stability.** Voice-first; the cycle (Task 9) reuses the STT→engine→TTS pipeline under rework. Flutter Tasks 8–11 are **contracts**; finalize their voice wiring after the rework. Text-only paths can be built earlier.
- **GATE-2 — Confidence scoring in `extract_meal`.** Gap type **C** cannot exist until `extract_meal()` emits a per-food confidence. Implemented as **Task 1** below (it's stable backend work, so it's the first real task, not deferred). If product chooses to ship the check-in with only A+D first, C's detector branch (Task 4) is simply skipped.
- **GATE-3 — Server-side follow-up outcome.** **Confirmed during planning:** follow-up status (answered/dismissed/pending) currently lives ONLY in-memory in `VoiceNotifier` and is lost on app restart (`voice_provider.dart`; see spec). Gap A's detector needs to know a meal's follow-up was *dismissed* in the evening, which requires this status **persisted and queryable server-side**. Where that status lands is entangled with the dictation rework. Task 3 below is the gate task; Task 5 (gap A detector) depends on it and **must not** be coded until Task 3's schema is final.
- **GATE-4 — Android background execution.** The evening detection run for the smart notification (Task 10) shares the trends plan's GATE-2 infrastructure decision (WorkManager vs. defer-to-tap). Decide before coding Task 10.

**Build order:** Task 1 (confidence) → Task 2 (D detector) → Task 4 (C detector) → Task 3 (follow-up persistence gate) → Task 5 (A detector) → Task 6 (gaps endpoint) → Task 7 (write-back) → Flutter contracts 8–11.

---

## File Structure

**Backend:**
- `hearty-api/app/services/ai_extraction.py` — **modify**: add confidence to `extract_meal`.
- `hearty-api/app/services/checkin_detector.py` — new: pure gap detection.
- `hearty-api/app/routers/checkin.py` — new: `GET /api/checkin/gaps`, write-back endpoints.
- `hearty-api/app/models/schemas.py` — **modify**: gap + check-in models.
- `hearty-api/app/main.py` — **modify**: register the new router (follow how existing routers are included).
- `supabase/migrations/<ts>_meal_followup_status.sql` — new (GATE-3): persist follow-up outcome.

**Backend (tests):**
- `hearty-api/tests/test_checkin_detector_unit.py`
- `hearty-api/tests/test_checkin_endpoint_unit.py`

**Flutter (contracts — finalize after GATE-1):**
- `hearty_app/lib/core/api/hearty_api_client.dart` — **modify**: `fetchCheckinGaps(date)`.
- `hearty_app/lib/features/checkin/screens/checkin_preview_screen.dart` — new.
- `hearty_app/lib/features/checkin/screens/checkin_cycle_screen.dart` — new (or reuse voice overlay).
- `hearty_app/lib/features/checkin/providers/checkin_provider.dart` — new.
- `hearty_app/lib/core/notifications/notification_service.dart` — **modify**: day-anchored evening trigger + expiry.
- `hearty_app/lib/app/router.dart` — **modify**: register routes.

---

## Task 1 (GATE-2): Add confidence scoring to `extract_meal`

**Files:**
- Modify: `hearty-api/app/services/ai_extraction.py`
- Test: `hearty-api/tests/test_extract_meal_confidence_unit.py`

Gap C needs to know which extracted foods Hearty was unsure about. Add a `confidence` (0..1) per food to the extraction output. This is additive and backward-compatible (existing callers ignore the new field).

- [ ] **Step 1: Write the failing test (LLM mocked)**

```python
import json
from unittest.mock import patch
from types import SimpleNamespace
from app.services import ai_extraction


def test_extract_meal_includes_confidence_per_food():
    fake = SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(
        content=json.dumps({
            "normalized_description": "buldak ramen",
            "foods": [{"name": "buldak ramen", "quantity": None,
                       "estimated_calories": None, "preparation": None,
                       "confidence": 0.45}],
            "inferred_meal_type": "snack",
        })))])
    with patch.object(ai_extraction.litellm, "completion", return_value=fake):
        out = ai_extraction.extract_meal("buldak swicy ramen")
    assert out["foods"][0]["confidence"] == 0.45
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `cd hearty-api && pytest tests/test_extract_meal_confidence_unit.py -v`
Expected: FAIL — `KeyError: 'confidence'` (current prompt does not request it).

- [ ] **Step 3: Update `MEAL_EXTRACTION_PROMPT`** in `ai_extraction.py` — add `"confidence"` to the per-food JSON shape and an instruction:

```python
# In the foods array shape, add the field:
#   "confidence": number_between_0_and_1
# And add this instruction line before "Description:":
# "confidence is your certainty (0-1) that you correctly identified this food
#  from the description; lower it when the wording was ambiguous or misspelled."
```

`extract_meal`'s body is unchanged — it already returns the parsed JSON verbatim, so the new field flows through. (Confirm `app/routers/meals.py` stores `foods` as-is or strips unknown keys; if it constructs `FoodItem` per food, add an optional `confidence: Optional[float] = None` to the `FoodItem` Pydantic model in `schemas.py` so it is preserved.)

- [ ] **Step 4: Run the test to confirm it passes**

Run: `cd hearty-api && pytest tests/test_extract_meal_confidence_unit.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/ai_extraction.py hearty-api/app/models/schemas.py hearty-api/tests/test_extract_meal_confidence_unit.py
git commit -m "feat(extraction): per-food confidence score (gap C dependency)"
```

---

## Task 2: Gap detector — D (missing chunk) + scaffolding

**Files:**
- Create: `hearty-api/app/services/checkin_detector.py`
- Test: `hearty-api/tests/test_checkin_detector_unit.py`

Pure logic: given the day's meals + symptoms + thresholds + "now", return an ordered list of `Gap` dicts. Start with D and the ordering/priority scaffold; A and C plug in later. Priority order (spec): **A → C → D** (health signal first, hygiene last).

- [ ] **Step 1: Write the failing test**

```python
from datetime import datetime, timezone
from app.services.checkin_detector import detect_gaps, MISSING_CHUNK_HOURS


def _dt(h, m=0):
    return datetime(2026, 6, 3, h, m, tzinfo=timezone.utc)


def test_missing_chunk_flagged_between_distant_meals():
    meals = [
        {"id": "m1", "logged_at": _dt(8).isoformat(), "foods": [{"name": "eggs"}]},
        {"id": "m2", "logged_at": _dt(16).isoformat(), "foods": [{"name": "salad"}]},
    ]
    gaps = detect_gaps(meals, symptoms=[], now=_dt(22),
                       waking_start_hour=8, waking_end_hour=22)
    d_gaps = [g for g in gaps if g["type"] == "missing_chunk"]
    assert len(d_gaps) == 1
    assert d_gaps[0]["window_start"] == _dt(8).isoformat()
    assert d_gaps[0]["window_end"] == _dt(16).isoformat()


def test_no_missing_chunk_when_meals_close_together():
    meals = [
        {"id": "m1", "logged_at": _dt(12).isoformat(), "foods": [{"name": "a"}]},
        {"id": "m2", "logged_at": _dt(15).isoformat(), "foods": [{"name": "b"}]},
    ]
    gaps = detect_gaps(meals, symptoms=[], now=_dt(22),
                       waking_start_hour=8, waking_end_hour=22)
    assert [g for g in gaps if g["type"] == "missing_chunk"] == []


def test_missing_chunk_only_counts_up_to_now():
    # 2pm "now": the unlived afternoon must not be flagged as a gap.
    meals = [{"id": "m1", "logged_at": _dt(8).isoformat(), "foods": [{"name": "a"}]}]
    gaps = detect_gaps(meals, symptoms=[], now=_dt(14),
                       waking_start_hour=8, waking_end_hour=22)
    # 8am→2pm is 6h > threshold, but only elapsed time counts; the gap end is now.
    d_gaps = [g for g in gaps if g["type"] == "missing_chunk"]
    assert len(d_gaps) == 1
    assert d_gaps[0]["window_end"] == _dt(14).isoformat()
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `cd hearty-api && pytest tests/test_checkin_detector_unit.py -v`
Expected: FAIL — module does not exist.

- [ ] **Step 3: Implement the detector (D + scaffold)**

```python
"""Daily check-in gap detector. Pure logic over a target day's logs.

Gap types (priority order A → C → D):
  - symptom_gap   (A): a meal with no symptom within SYMPTOM_GAP_HOURS  [Task 5]
  - low_confidence (C): an extracted food below CONFIDENCE_THRESHOLD     [Task 4]
  - missing_chunk (D): a waking-window stretch > MISSING_CHUNK_HOURS with no logs
"""

import os
from datetime import datetime, timedelta

SYMPTOM_GAP_HOURS = float(os.environ.get("CHECKIN_SYMPTOM_GAP_HOURS", "3"))
MISSING_CHUNK_HOURS = float(os.environ.get("CHECKIN_MISSING_CHUNK_HOURS", "5"))
CONFIDENCE_THRESHOLD = float(os.environ.get("CHECKIN_CONFIDENCE_THRESHOLD", "0.6"))

# Priority weight: lower sorts first.
_PRIORITY = {"symptom_gap": 0, "low_confidence": 1, "missing_chunk": 2}


def _parse(ts: str) -> datetime:
    return datetime.fromisoformat(ts)


def _detect_missing_chunks(meals, now, waking_start_hour, waking_end_hour):
    """Flag stretches > MISSING_CHUNK_HOURS with no meals, inside the waking
    window, only up to `now` (never the unlived part of the day)."""
    day = now.date()
    waking_start = now.replace(hour=int(waking_start_hour), minute=0,
                               second=0, microsecond=0)
    waking_end = now.replace(hour=int(waking_end_hour), minute=0,
                             second=0, microsecond=0)
    window_end_cap = min(now, waking_end)

    times = sorted(_parse(m["logged_at"]) for m in meals
                   if _parse(m["logged_at"]).date() == day)
    # Boundaries: from waking_start, through each meal, to the cap.
    boundaries = [waking_start] + times + [window_end_cap]

    gaps = []
    threshold = timedelta(hours=MISSING_CHUNK_HOURS)
    for a, b in zip(boundaries, boundaries[1:]):
        if b - a > threshold:
            gaps.append({
                "type": "missing_chunk",
                "window_start": a.isoformat(),
                "window_end": b.isoformat(),
                "prompt": "I don't see anything logged for a stretch there — "
                          "did you eat in that window?",
            })
    return gaps


def detect_gaps(meals, symptoms, now, *, waking_start_hour=8,
                waking_end_hour=22, follow_up_status=None):
    """Return gaps ordered by priority (A → C → D), then by recency within type.

    follow_up_status: optional dict meal_id -> 'answered'|'dismissed'|'pending'
    (used by gap A in Task 5; ignored until then)."""
    gaps = []
    # A (Task 5) and C (Task 4) prepend here.
    gaps += _detect_missing_chunks(meals, now, waking_start_hour, waking_end_hour)

    gaps.sort(key=lambda g: _PRIORITY[g["type"]])
    return gaps
```

- [ ] **Step 4: Run the tests to confirm they pass**

Run: `cd hearty-api && pytest tests/test_checkin_detector_unit.py -v`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/checkin_detector.py hearty-api/tests/test_checkin_detector_unit.py
git commit -m "feat(checkin): gap detector with missing-chunk (D) detection"
```

---

## Task 4 (GATE-2): Gap detector — C (low-confidence food)

**Files:**
- Modify: `hearty-api/app/services/checkin_detector.py`
- Test: `hearty-api/tests/test_checkin_detector_unit.py` (add cases)

Depends on Task 1 (foods carry `confidence`). A meal whose `foods[].confidence` is below `CONFIDENCE_THRESHOLD` becomes a `low_confidence` gap.

- [ ] **Step 1: Add failing tests**

```python
def test_low_confidence_food_flagged():
    meals = [{"id": "m1", "logged_at": _dt(13).isoformat(),
              "foods": [{"name": "buldak ramen", "confidence": 0.45}]}]
    gaps = detect_gaps(meals, symptoms=[], now=_dt(22))
    c = [g for g in gaps if g["type"] == "low_confidence"]
    assert len(c) == 1
    assert c[0]["meal_id"] == "m1"
    assert c[0]["food_name"] == "buldak ramen"


def test_confident_food_not_flagged():
    meals = [{"id": "m1", "logged_at": _dt(13).isoformat(),
              "foods": [{"name": "apple", "confidence": 0.97}]}]
    gaps = detect_gaps(meals, symptoms=[], now=_dt(22))
    assert [g for g in gaps if g["type"] == "low_confidence"] == []


def test_food_without_confidence_is_not_flagged():
    # Legacy meals (pre-confidence) must not all light up as gaps.
    meals = [{"id": "m1", "logged_at": _dt(13).isoformat(),
              "foods": [{"name": "apple"}]}]
    gaps = detect_gaps(meals, symptoms=[], now=_dt(22))
    assert [g for g in gaps if g["type"] == "low_confidence"] == []
```

- [ ] **Step 2: Run to confirm new cases fail**

Run: `cd hearty-api && pytest tests/test_checkin_detector_unit.py -v`
Expected: the 3 new tests FAIL (no low_confidence gaps produced yet).

- [ ] **Step 3: Add `_detect_low_confidence` and call it in `detect_gaps`**

```python
def _detect_low_confidence(meals):
    gaps = []
    for m in meals:
        for food in m.get("foods") or []:
            conf = food.get("confidence")
            if conf is not None and float(conf) < CONFIDENCE_THRESHOLD:
                gaps.append({
                    "type": "low_confidence",
                    "meal_id": m["id"],
                    "food_name": food.get("name", ""),
                    "prompt": f"I logged \"{food.get('name','')}\" but wasn't "
                              "sure I got it right — did I?",
                })
    return gaps
```

In `detect_gaps`, before the missing-chunk line:

```python
    gaps += _detect_low_confidence(meals)
```

- [ ] **Step 4: Run all detector tests**

Run: `cd hearty-api && pytest tests/test_checkin_detector_unit.py -v`
Expected: PASS (all, incl. priority — `low_confidence` sorts before `missing_chunk`).

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/checkin_detector.py hearty-api/tests/test_checkin_detector_unit.py
git commit -m "feat(checkin): low-confidence food (C) gap detection"
```

---

## Task 3 (GATE-3): Persist follow-up outcome server-side

**Files:**
- Create: `supabase/migrations/<ts>_meal_followup_status.sql`
- (Flutter + chat-endpoint wiring noted as a contract — see below.)

> **Gate task — schema first, then coordinate with the dictation rework.** Today the follow-up outcome (answered/dismissed) is in-memory only. Gap A (Task 5) needs it persisted. Add a column to `meals`, then wire the write where the follow-up resolves.

- [ ] **Step 1: Write the migration**

```sql
-- Daily check-in: persist the per-meal symptom follow-up outcome so the evening
-- check-in can resurface dismissed follow-ups (gap A). 'resurfaced' marks that
-- the evening check-in has already offered its one retry.

ALTER TABLE meals
  ADD COLUMN IF NOT EXISTS followup_status TEXT
    CHECK (followup_status IN ('pending', 'answered', 'dismissed', 'resurfaced'));
```

- [ ] **Step 2: Apply the migration**

Run: `cd /home/evan/projects/food-journal-assistant && supabase db push`
Expected: applies cleanly.

- [ ] **Step 3 (CONTRACT — coordinate with dictation rework):** wire the writes:
  - When a symptom follow-up is **answered** (the `/api/chat` symptom-follow-up branch creates a symptom for `meal_id`) → set that meal's `followup_status = 'answered'`.
  - When the user **dismisses** the in-the-moment follow-up → set `followup_status = 'dismissed'`. **This is the write that currently has no home** (dismiss is client-only, in-memory). The dictation rework decides whether the client PATCHes the meal or the server infers it; finalize here.
  - New meals default `followup_status = 'pending'` when a follow-up is scheduled.

- [ ] **Step 4: Commit the migration now; commit the wiring with the rework.**

```bash
git add supabase/migrations/
git commit -m "feat(checkin): persist meal follow-up status (gap A dependency)"
```

---

## Task 5 (depends on Task 3): Gap detector — A (meal → symptom)

**Files:**
- Modify: `hearty-api/app/services/checkin_detector.py`
- Test: `hearty-api/tests/test_checkin_detector_unit.py`

> **Do not start until Task 3's `followup_status` schema is final.** Gap A is a meal with no symptom within `SYMPTOM_GAP_HOURS`, filtered by the follow-up relationship from the spec:
> - `answered` → excluded (already has a symptom).
> - `pending` → excluded (don't preempt the in-the-moment follow-up).
> - `dismissed` → **resurfaces once** (becomes a gap; the act of surfacing it flips it to `resurfaced`).
> - `resurfaced` → excluded (its one evening retry is spent).
> - `null`/no follow-up → eligible by the time rule alone.

- [ ] **Step 1: Add failing tests**

```python
def _meal(mid, hour, status=None):
    return {"id": mid, "logged_at": _dt(hour).isoformat(),
            "foods": [{"name": "x"}], "followup_status": status}


def test_symptom_gap_for_meal_without_symptom():
    meals = [_meal("m1", 13)]
    gaps = detect_gaps(meals, symptoms=[], now=_dt(22))
    a = [g for g in gaps if g["type"] == "symptom_gap"]
    assert len(a) == 1 and a[0]["meal_id"] == "m1"


def test_no_symptom_gap_when_symptom_logged_within_window():
    meals = [_meal("m1", 13)]
    symptoms = [{"meal_id": "m1", "logged_at": _dt(14).isoformat()}]
    gaps = detect_gaps(meals, symptoms=symptoms, now=_dt(22))
    assert [g for g in gaps if g["type"] == "symptom_gap"] == []


def test_answered_followup_excluded():
    gaps = detect_gaps([_meal("m1", 13, "answered")], symptoms=[], now=_dt(22))
    assert [g for g in gaps if g["type"] == "symptom_gap"] == []


def test_pending_followup_excluded():
    gaps = detect_gaps([_meal("m1", 13, "pending")], symptoms=[], now=_dt(22))
    assert [g for g in gaps if g["type"] == "symptom_gap"] == []


def test_dismissed_followup_resurfaces_once():
    gaps = detect_gaps([_meal("m1", 13, "dismissed")], symptoms=[], now=_dt(22))
    a = [g for g in gaps if g["type"] == "symptom_gap"]
    assert len(a) == 1 and a[0]["meal_id"] == "m1"


def test_resurfaced_followup_excluded():
    gaps = detect_gaps([_meal("m1", 13, "resurfaced")], symptoms=[], now=_dt(22))
    assert [g for g in gaps if g["type"] == "symptom_gap"] == []
```

- [ ] **Step 2: Run to confirm they fail**

Run: `cd hearty-api && pytest tests/test_checkin_detector_unit.py -v`
Expected: the new tests FAIL.

- [ ] **Step 3: Add `_detect_symptom_gaps` and call it first in `detect_gaps`**

```python
from datetime import timedelta  # already imported


def _detect_symptom_gaps(meals, symptoms):
    gap_window = timedelta(hours=SYMPTOM_GAP_HOURS)
    # meal_id -> earliest symptom time after the meal
    sym_by_meal = {}
    for s in symptoms:
        mid = s.get("meal_id")
        if mid:
            t = _parse(s["logged_at"])
            sym_by_meal.setdefault(mid, []).append(t)

    gaps = []
    for m in meals:
        status = m.get("followup_status")
        if status in ("answered", "pending", "resurfaced"):
            continue
        meal_time = _parse(m["logged_at"])
        sym_times = sym_by_meal.get(m["id"], [])
        has_symptom = any(meal_time <= t <= meal_time + gap_window
                          for t in sym_times)
        if has_symptom:
            continue
        gaps.append({
            "type": "symptom_gap",
            "meal_id": m["id"],
            "prompt": "How did your stomach feel after that meal?",
        })
    return gaps
```

In `detect_gaps`, make it the first source:

```python
    gaps += _detect_symptom_gaps(meals, symptoms)
    gaps += _detect_low_confidence(meals)
    gaps += _detect_missing_chunks(meals, now, waking_start_hour, waking_end_hour)
```

(The `dismissed` case is *included* by virtue of not being in the excluded set; surfacing-flips-to-`resurfaced` is performed by the write-back in Task 7 when the gap is acted on or skipped.)

- [ ] **Step 4: Run all detector tests**

Run: `cd hearty-api && pytest tests/test_checkin_detector_unit.py -v`
Expected: PASS (all; priority order A→C→D holds).

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/checkin_detector.py hearty-api/tests/test_checkin_detector_unit.py
git commit -m "feat(checkin): meal->symptom (A) gaps honoring follow-up status"
```

---

## Task 6: `GET /api/checkin/gaps` endpoint (day-anchored + expiry)

**Files:**
- Create: `hearty-api/app/routers/checkin.py`
- Modify: `hearty-api/app/main.py` (register router), `hearty-api/app/models/schemas.py` (response models).
- Test: `hearty-api/tests/test_checkin_endpoint_unit.py`

Loads the target day's meals + symptoms (day-anchored), runs the detector, returns the ordered queue. Enforces the **48h expiry**: if the requested `date` is older than `CHECKIN_EXPIRY_HOURS` before now, return `expired: true` and an empty queue.

- [ ] **Step 1: Add response models to `schemas.py`**

```python
# ─── Daily Check-in ─────────────────────────────────────────────────────────

class CheckinGap(BaseModel):
    type: Literal["symptom_gap", "low_confidence", "missing_chunk"]
    prompt: str
    meal_id: Optional[str] = None
    food_name: Optional[str] = None
    window_start: Optional[str] = None
    window_end: Optional[str] = None

class CheckinGapsResponse(BaseModel):
    target_date: str           # YYYY-MM-DD, the anchored day
    expired: bool = False
    gaps: List[CheckinGap] = Field(default_factory=list)
```

- [ ] **Step 2: Write the failing endpoint test (mock supabase + detector)**

```python
from types import SimpleNamespace
from fastapi.testclient import TestClient
from app.main import app
from app.auth import get_current_user
from app.routers import checkin as checkin_module


class _Result:
    def __init__(self, data): self.data = data

class _Q:
    def __init__(self, data): self._d = data
    def select(self, *a, **k): return self
    def eq(self, *a, **k): return self
    def gte(self, *a, **k): return self
    def lte(self, *a, **k): return self
    def execute(self): return _Result(self._d)

class _Supa:
    def table(self, name): return _Q([])


def test_gaps_endpoint_returns_queue(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    monkeypatch.setattr(checkin_module, "supabase", _Supa())
    monkeypatch.setattr(checkin_module.checkin_detector, "detect_gaps",
                        lambda *a, **k: [{"type": "missing_chunk",
                                          "prompt": "p", "window_start": "s",
                                          "window_end": "e"}])
    client = TestClient(app)
    r = client.get("/api/checkin/gaps?date=2026-06-03")
    assert r.status_code == 200
    body = r.json()
    assert body["expired"] is False
    assert body["gaps"][0]["type"] == "missing_chunk"
    app.dependency_overrides.clear()


def test_gaps_endpoint_expires_old_dates(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    monkeypatch.setattr(checkin_module, "supabase", _Supa())
    client = TestClient(app)
    r = client.get("/api/checkin/gaps?date=2020-01-01")  # far in the past
    assert r.status_code == 200
    assert r.json()["expired"] is True
    assert r.json()["gaps"] == []
    app.dependency_overrides.clear()
```

- [ ] **Step 3: Run it to confirm it fails**

Run: `cd hearty-api && pytest tests/test_checkin_endpoint_unit.py -v`
Expected: FAIL — router/module missing.

- [ ] **Step 4: Implement the router**

```python
import os
from datetime import datetime, timezone, timedelta, date as date_cls

from fastapi import APIRouter, Depends, Query
from supabase import create_client

from app.auth import get_current_user
from app.models.schemas import CheckinGap, CheckinGapsResponse
from app.services import checkin_detector

router = APIRouter()
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])

CHECKIN_EXPIRY_HOURS = float(os.environ.get("CHECKIN_EXPIRY_HOURS", "48"))


@router.get("/api/checkin/gaps", status_code=200)
async def get_checkin_gaps(
    date: str = Query(..., description="Target day, YYYY-MM-DD (day-anchored)"),
    user=Depends(get_current_user),
) -> CheckinGapsResponse:
    user_id = user["id"]
    now = datetime.now(timezone.utc)
    target = date_cls.fromisoformat(date)

    # 48h expiry: anchored to the END of the target day.
    day_end = datetime(target.year, target.month, target.day, 23, 59, 59,
                       tzinfo=timezone.utc)
    if now - day_end > timedelta(hours=CHECKIN_EXPIRY_HOURS):
        return CheckinGapsResponse(target_date=date, expired=True, gaps=[])

    day_start = datetime(target.year, target.month, target.day, 0, 0, 0,
                         tzinfo=timezone.utc)
    detect_until = min(now, day_end)  # never the unlived part of today

    meals = (
        supabase.table("meals")
        .select("id, foods, logged_at, followup_status")
        .eq("user_id", user_id)
        .gte("logged_at", day_start.isoformat())
        .lte("logged_at", day_end.isoformat())
        .execute()
    ).data or []
    symptoms = (
        supabase.table("symptoms")
        .select("id, meal_id, logged_at")
        .eq("user_id", user_id)
        .gte("logged_at", day_start.isoformat())
        .lte("logged_at", day_end.isoformat())
        .execute()
    ).data or []

    gaps = checkin_detector.detect_gaps(meals, symptoms, now=detect_until)
    return CheckinGapsResponse(
        target_date=date, expired=False,
        gaps=[CheckinGap(**g) for g in gaps],
    )
```

- [ ] **Step 5: Register the router in `app/main.py`** following the existing `app.include_router(...)` pattern for trends/meals/symptoms.

- [ ] **Step 6: Run the tests**

Run: `cd hearty-api && pytest tests/test_checkin_endpoint_unit.py -v`
Expected: PASS (2 tests).

- [ ] **Step 7: Commit**

```bash
git add hearty-api/app/routers/checkin.py hearty-api/app/main.py hearty-api/app/models/schemas.py hearty-api/tests/test_checkin_endpoint_unit.py
git commit -m "feat(checkin): GET /api/checkin/gaps (day-anchored, 48h expiry)"
```

---

## Task 7: Write-back endpoints (reuse existing paths)

**Files:**
- Modify: `hearty-api/app/routers/checkin.py`
- Test: `hearty-api/tests/test_checkin_endpoint_unit.py` (add cases)

Answers become real structured data. Rather than new logic, these endpoints delegate to the existing write shapes (symptom insert from `symptoms.py`, meal update/insert from `meals.py`) and additionally flip `followup_status`.

Three resolutions + a skip:
- **A answered:** create a symptom for `meal_id` (reuse `symptoms` insert), set meal `followup_status='answered'`.
- **A skipped (in the evening):** set `followup_status='resurfaced'` (its one retry is spent).
- **C corrected:** update the meal's `foods` (reuse meal update); on confirm, raise that food's `confidence` to 1.0 so it stops re-flagging.
- **D answered:** "I had X at 3pm" → `extract_meal` + insert a meal on the target day; "didn't eat" → record reviewed (no-op meal; do not re-flag — for v1, simply nothing is logged and the chunk is accepted by the user dismissing it client-side).

- [ ] **Step 1: Add a failing test for the symptom-gap resolution**

```python
def test_resolve_symptom_gap_inserts_symptom_and_marks_meal(monkeypatch):
    rec = {"insert": [], "update": []}
    class _T:
        def __init__(self, name): self.name = name
        def insert(self, rows, *a, **k):
            rec["insert"].append((self.name, rows)); return self
        def update(self, vals, *a, **k):
            rec["update"].append((self.name, vals)); return self
        def eq(self, *a, **k): return self
        def execute(self): return _Result([{"id": "s1"}])
    class _S:
        def table(self, name): return _T(name)
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    monkeypatch.setattr(checkin_module, "supabase", _S())
    client = TestClient(app)
    r = client.post("/api/checkin/resolve/symptom", json={
        "meal_id": "m1", "raw_description": "a bit bloated", "severity": 4})
    assert r.status_code == 200
    assert any(t == "symptoms" for t, _ in rec["insert"])
    assert any(t == "meals" and v.get("followup_status") == "answered"
               for t, v in rec["update"])
    app.dependency_overrides.clear()
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `cd hearty-api && pytest tests/test_checkin_endpoint_unit.py::test_resolve_symptom_gap_inserts_symptom_and_marks_meal -v`
Expected: FAIL — endpoint missing.

- [ ] **Step 3: Add the resolution endpoints**

```python
from app.models.schemas import SymptomRequest  # reuse existing shape

@router.post("/api/checkin/resolve/symptom", status_code=200)
async def resolve_symptom_gap(body: dict, user=Depends(get_current_user)) -> dict:
    """A-gap answer: create a symptom linked to the meal, mark meal answered."""
    user_id = user["id"]
    now = datetime.now(timezone.utc).isoformat()
    row = {k: v for k, v in {
        "user_id": user_id,
        "raw_description": body.get("raw_description", ""),
        "meal_id": body["meal_id"],
        "symptom_type": body.get("symptom_type"),
        "severity": body.get("severity"),
        "logged_at": now,
    }.items() if v is not None}
    supabase.table("symptoms").insert(row).execute()
    supabase.table("meals").update({"followup_status": "answered"}) \
        .eq("id", body["meal_id"]).eq("user_id", user_id).execute()
    return {"ok": True}


@router.post("/api/checkin/skip/symptom", status_code=200)
async def skip_symptom_gap(body: dict, user=Depends(get_current_user)) -> dict:
    """A-gap skipped in the evening: spend its one retry."""
    user_id = user["id"]
    supabase.table("meals").update({"followup_status": "resurfaced"}) \
        .eq("id", body["meal_id"]).eq("user_id", user_id).execute()
    return {"ok": True}
```

(For C-correction and D-meal-creation, reuse the exact bodies from `meals.py` update/insert — repeat them in dedicated `/api/checkin/resolve/food` and `/api/checkin/resolve/meal` endpoints; out of line here only to keep this task focused. Add their tests mirroring Step 1.)

- [ ] **Step 4: Run the tests**

Run: `cd hearty-api && pytest tests/test_checkin_endpoint_unit.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/routers/checkin.py hearty-api/tests/test_checkin_endpoint_unit.py
git commit -m "feat(checkin): write-back endpoints reuse symptom/meal paths + follow-up flip"
```

**Backend complete (A gated on Task 3 wiring). Tasks 8–11 require GATE-1.**

---

## Task 8 (CONTRACT — finalize after GATE-1): Flutter gaps API client

**Files:**
- Modify: `hearty_app/lib/core/api/hearty_api_client.dart`

> The HTTP shape is fully known and implementable now. Add `fetchCheckinGaps(DateTime date)` returning a `List<CheckinGap>` (+ `expired` flag), following the `fetchMeals` pattern; create a `CheckinGap` Dart model mirroring the Pydantic `CheckinGap`. Also add resolve/skip POST helpers mirroring Task 7's endpoints.

- [ ] Implement, test (Dio mock), commit.

---

## Task 9 (CONTRACT — finalize after GATE-1): Preview screen + skippable cycle

**Files:**
- Create: `hearty_app/lib/features/checkin/providers/checkin_provider.dart`
- Create: `hearty_app/lib/features/checkin/screens/checkin_preview_screen.dart`
- Create/reuse: cycle UI (reuse `voice_overlay_screen.dart`).
- Modify: `hearty_app/lib/app/router.dart`.

> **Contract.** Provider (`StateNotifier`) holds `{queue: List<CheckinGap>, index, skipped:Set}`. Preview screen shows the count + list (already ordered A→C→D by the backend), per-item skip + skip-all + Begin. Cycle presents `queue[index]` one at a time, voice-first (reuse the post-rework voice pipeline), each skippable; on answer calls the matching resolve endpoint; ends with a finite "that's everything." **Finalize STT/TTS wiring against the reworked voice provider** (do not copy today's `_beginStt`). Text fallback always present.

- [ ] Design step (read reworked voice provider) → provider → preview screen → cycle → widget test (begin → answer first → resolve called; skip-all → no resolves) → commit.

---

## Task 10 (CONTRACT — requires GATE-4): Day-anchored evening notification + expiry

**Files:**
- Modify: `hearty_app/lib/core/notifications/notification_service.dart`

> **Contract.** Mirror `scheduleFollowUpNotification`. Evening notification carries the **target date** in its payload (`/checkin?date=YYYY-MM-DD`); tap routes to the preview screen for *that* date (write-backs target that day). **Smart gating:** only present gaps if `fetchCheckinGaps(date).gaps` is non-empty; GATE-4 decides whether gating runs in a WorkManager background job (post only if gaps exist) or defers to tap-time. Expiry is enforced server-side (Task 6) AND the tap handler shows "this review has expired" when `expired: true`.

- [ ] Implement per GATE-4 decision; route registration; commit.

---

## Task 11 (CONTRACT): Manual entry + preferences

**Files:**
- Modify: a home/today screen (add "Review my day" button → `/checkin?date=<today>`).
- `UserPreferences` already has `dailyCheckinEnabled`, `dailyCheckinHour`, `dailyCheckinMinute` — reuse them for the evening trigger time/toggle. Optionally add `wakingStartHour`/`wakingEndHour` + threshold tunables following the `copyWith` pattern, surfaced on a settings page (mirror `voice_settings_screen.dart`).

- [ ] Add button; wire preferences; commit.

---

## Final review

After all reachable tasks (1–2,4,6–7 now; 3 schema now + wiring with rework; 5 after 3; 8–11 after gates), dispatch a final code reviewer, then use `superpowers:finishing-a-development-branch`.

---

## Self-review notes (author)

- **Spec coverage:** A/C/D detection (T5/T4/T2), confidence dependency (T1), follow-up relationship incl. resurface-once (T5 + T3 + T7 skip), preview queue ordered A→C→D + skip any/all (T9), voice-first/text-optional (T9), full structured write-back (T7), day-anchored + 48h expiry (T6/T10), smart notification + manual button + preference (T10/T11).
- **Gates are explicit, not hidden:** C waits on T1 (done as the first task), A waits on T3 (server-side follow-up status — confirmed absent today), voice on GATE-1, scheduling on GATE-4.
- **Logged simplification:** D's "didn't eat" answer is, in v1, accepted by client-side dismissal with nothing logged (no "reviewed" marker table). If gap D should never re-flag a user-confirmed-empty window across re-opens of the same day, add a small reviewed-windows store — noted, not silently dropped.
- **Reused, not reinvented:** write-backs delegate to the existing `symptoms`/`meals` insert/update shapes rather than new persistence logic.
