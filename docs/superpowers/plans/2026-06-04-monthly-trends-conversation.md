# Monthly Trends Conversation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Surface the backend's already-computed `food_signals` to the user as a roughly-monthly, turn-based voice conversation (text-optional) in which Hearty explains the month's patterns and the user's confirm/dispute/snooze verdicts feed back to make future analysis smarter.

**Architecture:** A new **pure backend conversation engine** (`POST /api/trends/conversation`) grounds an LLM turn in the user's signals (filtered through a **feedback overlay** table the user's verdicts write to). A **signal presenter** applies the overlay (suppress disputed unless evidence grows, mark confirmed, flag new) and ranks by `unified_score`. The Flutter side is a thin **turn-based I/O layer** decoupled from the engine so streaming duplex can replace it later. Trend detection (`signal_engine.py`, `food_signals`) already exists and is **consumed, not modified**.

**Tech Stack:** FastAPI + Supabase (python `supabase` client, service key) + litellm; Flutter + Riverpod + Dio + go_router + `speech_to_text` + neural TTS; Supabase SQL migrations.

**Spec:** `docs/superpowers/specs/2026-06-04-monthly-trends-conversation-design.md`

---

## Prerequisites (ordered gate-tasks — resolve before the tasks that depend on them)

These are **not** optional polish; dependent tasks below reference them by name.

- **GATE-1 — Dictation/voice stability.** The conversation is voice-first and reuses the STT → engine → TTS pipeline currently being reworked for the dictation bugs. **Tasks 8–10 (the Flutter I/O layer) MUST NOT be implemented at code level until the dictation rework lands.** They are written here as interface **contracts** against the engine; finalize their Dart against the post-rework voice provider API.
- **GATE-2 — Android background execution mechanism.** The monthly smart-notification (Task 10) requires a scheduled background run to call `/api/trends/analyze/status`. The concrete mechanism (WorkManager periodic work vs. a scheduled local notification that defers the status check to tap-time) is an open infrastructure decision shared with the daily check-in. Pick one in Task 10's design step before coding.

Backend Tasks 1–7 have **no** dependency on the gates and can be built and tested immediately.

---

## File Structure

**Backend (new):**
- `supabase/migrations/<ts>_signal_feedback.sql` — feedback-overlay table.
- `hearty-api/app/services/signal_presenter.py` — pure overlay+ranking logic.
- `hearty-api/app/services/trends_conversation.py` — LLM turn generator (prompt build + parse).
- `hearty-api/app/routers/trends.py` — **modify**: add `POST /api/trends/conversation` and `POST /api/trends/signal-verdict`.
- `hearty-api/app/models/schemas.py` — **modify**: add request/response + presented-signal + verdict models.

**Backend (tests, new):**
- `hearty-api/tests/test_signal_presenter_unit.py`
- `hearty-api/tests/test_trends_conversation_unit.py`

**Flutter (contracts — finalize after GATE-1):**
- `hearty_app/lib/core/api/hearty_api_client.dart` — **modify**: `trendsConversation(...)`, `submitSignalVerdict(...)`.
- `hearty_app/lib/features/trends/screens/trends_conversation_screen.dart` — new.
- `hearty_app/lib/features/trends/providers/trends_conversation_provider.dart` — new.
- `hearty_app/lib/app/router.dart` — **modify**: register the screen route.
- `hearty_app/lib/core/notifications/notification_service.dart` — **modify**: monthly trigger.

---

## Task 1: Feedback-overlay migration (`signal_feedback`)

**Files:**
- Create: `supabase/migrations/<timestamp>_signal_feedback.sql` (use the next timestamp after the latest migration, format `YYYYMMDDHHMMSS`, matching existing files e.g. `20260512000001_food_signals.sql`).

The table is keyed by the natural identity of a signal so verdicts survive `signal_engine`'s delete-and-recompute. `score_at_verdict` stores the `unified_score` at dispute time so resurfacing can require the evidence to grow.

- [ ] **Step 1: Write the migration**

```sql
-- Monthly Trends Conversation — user verdicts on signals (feedback overlay).
-- Separate from food_signals so verdicts survive the signal engine's
-- delete-and-recompute on every analysis run.

CREATE TABLE signal_feedback (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID REFERENCES auth.users NOT NULL,
  category         TEXT NOT NULL,
  outcome_type     TEXT NOT NULL CHECK (outcome_type IN ('symptom', 'wellbeing')),
  outcome_name     TEXT NOT NULL,
  verdict          TEXT NOT NULL CHECK (verdict IN ('confirmed', 'disputed', 'snoozed')),
  score_at_verdict NUMERIC(5,4),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, category, outcome_type, outcome_name)
);

CREATE INDEX idx_signal_feedback_lookup
  ON signal_feedback (user_id, category, outcome_type, outcome_name);

ALTER TABLE signal_feedback ENABLE ROW LEVEL SECURITY;

CREATE POLICY "signal_feedback_owner_only" ON signal_feedback
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
```

- [ ] **Step 2: Apply the migration locally**

Run: `cd /home/evan/projects/food-journal-assistant && supabase db push` (or the project's standard migration-apply command — check `supabase/README` or how prior migrations were applied).
Expected: migration applies cleanly; `signal_feedback` exists.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/
git commit -m "feat(trends): add signal_feedback overlay table for verdicts"
```

---

## Task 2: Pydantic schemas

**Files:**
- Modify: `hearty-api/app/models/schemas.py` (append near the existing trends models — `SignalsResponse`, `AnalyzeStatusResponse`).

- [ ] **Step 1: Add the models**

```python
# ─── Trends Conversation ────────────────────────────────────────────────────

VerdictType = Literal["confirmed", "disputed", "snoozed"]

class PresentedSignal(BaseModel):
    """A food_signal after the feedback overlay has been applied."""
    category: str
    outcome_type: Literal["symptom", "wellbeing"]
    outcome_name: str
    direction: Literal["harmful", "beneficial"]
    unified_score: float
    relative_risk: Optional[float] = None
    evidence_count: int
    is_new: bool = False          # not surfaced in a prior conversation
    is_confirmed: bool = False    # user previously confirmed this pattern
    is_resurfaced: bool = False   # previously disputed, now stronger

class ConversationTurn(BaseModel):
    role: Literal["user", "assistant"]
    content: str

class ProposedVerdict(BaseModel):
    """A verdict Hearty inferred from the user's words, for client confirmation.
    NEVER written without an explicit client confirmation step."""
    category: str
    outcome_type: Literal["symptom", "wellbeing"]
    outcome_name: str
    verdict: VerdictType

class TrendsConversationRequest(BaseModel):
    history: List[ConversationTurn] = Field(default_factory=list)

class TrendsConversationResponse(BaseModel):
    reply: str
    proposed_verdict: Optional[ProposedVerdict] = None
    is_closing: bool = False      # engine signalled it has covered everything

class SignalVerdictRequest(BaseModel):
    category: str
    outcome_type: Literal["symptom", "wellbeing"]
    outcome_name: str
    verdict: VerdictType

class SignalVerdictResponse(BaseModel):
    ok: bool
```

- [ ] **Step 2: Verify it imports**

Run: `cd hearty-api && python -c "from app.models import schemas; print(schemas.TrendsConversationResponse.model_fields.keys())"`
Expected: prints the field names including `reply`, `proposed_verdict`, `is_closing`.

- [ ] **Step 3: Commit**

```bash
git add hearty-api/app/models/schemas.py
git commit -m "feat(trends): add conversation + verdict schemas"
```

---

## Task 3: Signal presenter — load + overlay + rank (pure logic)

**Files:**
- Create: `hearty-api/app/services/signal_presenter.py`
- Test: `hearty-api/tests/test_signal_presenter_unit.py`

The presenter is the testable heart of the feedback loop. It takes raw signal rows and feedback rows (plain dicts, as returned by the supabase client) and returns ordered `PresentedSignal`s. Keep DB access in a thin loader; keep the overlay logic pure.

- [ ] **Step 1: Write the failing test**

```python
from app.services.signal_presenter import apply_overlay, RESURFACE_MARGIN


def _sig(cat, score, outcome="bloating", otype="symptom", **kw):
    base = {
        "category": cat, "outcome_type": otype, "outcome_name": outcome,
        "direction": "harmful", "unified_score": score,
        "relative_risk": 2.0, "evidence_count": 8,
    }
    base.update(kw)
    return base


def test_unverdicted_signals_pass_through_ranked_by_score():
    signals = [_sig("dairy", 0.40), _sig("gluten", 0.80)]
    out = apply_overlay(signals, feedback=[], previously_surfaced=set())
    assert [s.category for s in out] == ["gluten", "dairy"]
    assert out[0].unified_score == 0.80


def test_disputed_signal_is_suppressed():
    signals = [_sig("dairy", 0.50)]
    feedback = [{"category": "dairy", "outcome_type": "symptom",
                 "outcome_name": "bloating", "verdict": "disputed",
                 "score_at_verdict": 0.50}]
    out = apply_overlay(signals, feedback=feedback, previously_surfaced=set())
    assert out == []


def test_disputed_signal_resurfaces_when_much_stronger():
    signals = [_sig("dairy", 0.50 + RESURFACE_MARGIN + 0.01)]
    feedback = [{"category": "dairy", "outcome_type": "symptom",
                 "outcome_name": "bloating", "verdict": "disputed",
                 "score_at_verdict": 0.50}]
    out = apply_overlay(signals, feedback=feedback, previously_surfaced=set())
    assert len(out) == 1
    assert out[0].is_resurfaced is True


def test_confirmed_signal_is_flagged_not_suppressed():
    signals = [_sig("dairy", 0.50)]
    feedback = [{"category": "dairy", "outcome_type": "symptom",
                 "outcome_name": "bloating", "verdict": "confirmed",
                 "score_at_verdict": 0.50}]
    out = apply_overlay(signals, feedback=feedback, previously_surfaced=set())
    assert len(out) == 1
    assert out[0].is_confirmed is True


def test_new_since_last_conversation_is_flagged():
    signals = [_sig("dairy", 0.50), _sig("gluten", 0.40)]
    surfaced = {("dairy", "symptom", "bloating")}
    out = apply_overlay(signals, feedback=[], previously_surfaced=surfaced)
    by_cat = {s.category: s for s in out}
    assert by_cat["dairy"].is_new is False
    assert by_cat["gluten"].is_new is True
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `cd hearty-api && pytest tests/test_signal_presenter_unit.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.services.signal_presenter'`.

- [ ] **Step 3: Implement the presenter**

```python
"""Signal presenter: apply the user's feedback overlay to raw food_signals
and rank them for the monthly trends conversation. Pure logic — DB access is
isolated in load_presented_signals()."""

import os
from datetime import datetime, timezone
from typing import Optional

from app.models.schemas import PresentedSignal

# A disputed signal only resurfaces if its unified_score has grown by at least
# this much beyond the score at the time of dispute.
RESURFACE_MARGIN = float(os.environ.get("TRENDS_RESURFACE_MARGIN", "0.20"))


def _key(d: dict) -> tuple:
    return (d["category"], d["outcome_type"], d["outcome_name"])


def apply_overlay(
    signals: list[dict],
    feedback: list[dict],
    previously_surfaced: set[tuple],
) -> list[PresentedSignal]:
    """Filter + annotate + rank.

    - disputed: suppressed, unless current unified_score exceeds score_at_verdict
      by >= RESURFACE_MARGIN (then surfaced with is_resurfaced=True)
    - confirmed: kept, is_confirmed=True
    - snoozed / none: kept as-is
    - is_new: signal identity not in previously_surfaced
    Ranked by unified_score descending.
    """
    fb_by_key = {_key(f): f for f in feedback}
    presented: list[PresentedSignal] = []

    for s in signals:
        k = _key(s)
        fb = fb_by_key.get(k)
        is_confirmed = False
        is_resurfaced = False

        if fb is not None:
            verdict = fb["verdict"]
            if verdict == "disputed":
                prior = fb.get("score_at_verdict") or 0.0
                if float(s["unified_score"]) - float(prior) >= RESURFACE_MARGIN:
                    is_resurfaced = True
                else:
                    continue  # suppressed
            elif verdict == "confirmed":
                is_confirmed = True
            # snoozed → no change

        presented.append(PresentedSignal(
            category=s["category"],
            outcome_type=s["outcome_type"],
            outcome_name=s["outcome_name"],
            direction=s["direction"],
            unified_score=float(s["unified_score"]),
            relative_risk=(float(s["relative_risk"])
                           if s.get("relative_risk") is not None else None),
            evidence_count=int(s.get("evidence_count") or 0),
            is_new=(k not in previously_surfaced),
            is_confirmed=is_confirmed,
            is_resurfaced=is_resurfaced,
        ))

    presented.sort(key=lambda p: p.unified_score, reverse=True)
    return presented


def load_presented_signals(supabase, user_id: str) -> list[PresentedSignal]:
    """Load food_signals + signal_feedback for a user and apply the overlay.

    `previously_surfaced` is derived from signal_feedback identities: any signal
    the user has ever given a verdict on has, by definition, been surfaced. This
    is a pragmatic proxy for v1 (no separate surfaced-log table)."""
    signals = (
        supabase.table("food_signals")
        .select("category, outcome_type, outcome_name, direction, "
                "unified_score, relative_risk, evidence_count")
        .eq("user_id", user_id)
        .execute()
    ).data or []

    feedback = (
        supabase.table("signal_feedback")
        .select("category, outcome_type, outcome_name, verdict, score_at_verdict")
        .eq("user_id", user_id)
        .execute()
    ).data or []

    previously_surfaced = {_key(f) for f in feedback}
    return apply_overlay(signals, feedback, previously_surfaced)
```

- [ ] **Step 4: Run the tests to confirm they pass**

Run: `cd hearty-api && pytest tests/test_signal_presenter_unit.py -v`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/signal_presenter.py hearty-api/tests/test_signal_presenter_unit.py
git commit -m "feat(trends): signal presenter applies feedback overlay + ranking"
```

---

## Task 4: Conversation engine — prompt build + LLM turn + parse

**Files:**
- Create: `hearty-api/app/services/trends_conversation.py`
- Test: `hearty-api/tests/test_trends_conversation_unit.py`

Mirrors `ai_extraction.extract_meal`'s litellm usage. The engine builds a system prompt from the presented signals + the hybrid-coverage instruction, asks the model to reply in plain language AND emit a structured JSON envelope, and parses it. The model returns JSON `{"reply": "...", "proposed_verdict": {...}|null, "is_closing": bool}`.

- [ ] **Step 1: Write the failing test (parsing + prompt content; LLM mocked)**

```python
import json
from unittest.mock import patch
from types import SimpleNamespace

from app.models.schemas import PresentedSignal, ConversationTurn
from app.services import trends_conversation as tc


def _presented():
    return [
        PresentedSignal(category="dairy", outcome_type="symptom",
                        outcome_name="bloating", direction="harmful",
                        unified_score=0.82, relative_risk=2.4, evidence_count=9,
                        is_new=True),
        PresentedSignal(category="ginger", outcome_type="wellbeing",
                        outcome_name="energy_level", direction="beneficial",
                        unified_score=0.41, relative_risk=None, evidence_count=6),
    ]


def test_build_system_prompt_includes_signals_and_coverage_rule():
    prompt = tc.build_system_prompt(_presented())
    assert "dairy" in prompt and "bloating" in prompt
    assert "ginger" in prompt
    # hybrid coverage instruction present
    assert "before" in prompt.lower() and "finish" in prompt.lower()
    # JSON envelope contract present
    assert "proposed_verdict" in prompt and "is_closing" in prompt


def test_generate_turn_parses_envelope():
    fake = SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(
        content=json.dumps({
            "reply": "The big one this month is dairy before your bloating.",
            "proposed_verdict": None,
            "is_closing": False,
        })))])
    with patch.object(tc.litellm, "completion", return_value=fake):
        out = tc.generate_turn(_presented(), history=[])
    assert out.reply.startswith("The big one")
    assert out.proposed_verdict is None
    assert out.is_closing is False


def test_generate_turn_parses_proposed_verdict():
    fake = SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(
        content=json.dumps({
            "reply": "Got it — want me to mark dairy as not a problem for you?",
            "proposed_verdict": {"category": "dairy", "outcome_type": "symptom",
                                 "outcome_name": "bloating", "verdict": "disputed"},
            "is_closing": False,
        })))])
    history = [ConversationTurn(role="user", content="nah dairy's fine for me")]
    with patch.object(tc.litellm, "completion", return_value=fake):
        out = tc.generate_turn(_presented(), history=history)
    assert out.proposed_verdict is not None
    assert out.proposed_verdict.category == "dairy"
    assert out.proposed_verdict.verdict == "disputed"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `cd hearty-api && pytest tests/test_trends_conversation_unit.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.services.trends_conversation'`.

- [ ] **Step 3: Implement the engine**

```python
"""Trends conversation engine: turn the user's presented signals into a warm,
plain-language back-and-forth. Pure with respect to voice — it knows nothing
about STT/TTS. One litellm call per turn, same pattern as ai_extraction."""

import json
import os

import litellm

from app.models.schemas import (
    PresentedSignal, ConversationTurn, ProposedVerdict, TrendsConversationResponse,
)


def _signal_line(s: PresentedSignal) -> str:
    tags = []
    if s.is_new:
        tags.append("NEW")
    if s.is_confirmed:
        tags.append("CONFIRMED")
    if s.is_resurfaced:
        tags.append("RESURFACED-STRONGER")
    tag = f" [{', '.join(tags)}]" if tags else ""
    rr = f", relative risk {s.relative_risk:.1f}x" if s.relative_risk else ""
    return (f"- {s.category} → {s.outcome_name} ({s.direction}, "
            f"strength {s.unified_score:.2f}{rr}, "
            f"{s.evidence_count} data points){tag}")


def build_system_prompt(signals: list[PresentedSignal]) -> str:
    signal_block = "\n".join(_signal_line(s) for s in signals) or "(no signals)"
    return f"""You are Hearty, a warm, plain-spoken food-and-symptom companion \
having a brief monthly check-in conversation with the user about the patterns \
in their data. Speak naturally and kindly. No clinical jargon, no alarmism, no \
medical claims — these are observed correlations, not diagnoses.

This month's patterns (ranked strongest first):
{signal_block}

How to run the conversation:
- Open with the single strongest, most useful pattern (the "headline").
- Let the user steer; answer their questions grounded ONLY in the patterns above.
- CONFIRMED patterns: mention briefly as established; do not re-litigate them.
- Coverage rule: before you finish, make sure every pattern above has been \
raised at least once ("Before we finish, there are a couple more I noticed…").
- When the user clearly expresses a verdict on a pattern (e.g. "that's right" / \
"dairy's fine for me, that's wrong" / "not sure"), propose the matching verdict \
for their confirmation — never assume it is final.
- When every pattern has been covered and there is nothing left to raise, set \
is_closing to true and give a short, finite goodbye.

Respond with ONLY a JSON object, no prose around it:
{{
  "reply": "what you say to the user this turn",
  "proposed_verdict": null OR {{"category": "...", "outcome_type": "symptom|wellbeing", "outcome_name": "...", "verdict": "confirmed|disputed|snoozed"}},
  "is_closing": false
}}
proposed_verdict must reference one of the exact patterns above, or be null."""


def _strip_code_fence(text: str) -> str:
    t = text.strip()
    if t.startswith("```"):
        t = t.split("\n", 1)[1] if "\n" in t else t
        if t.endswith("```"):
            t = t[: t.rfind("```")]
    return t.strip()


def generate_turn(
    signals: list[PresentedSignal],
    history: list[ConversationTurn],
) -> TrendsConversationResponse:
    messages = [{"role": "system", "content": build_system_prompt(signals)}]
    for turn in history:
        messages.append({"role": turn.role, "content": turn.content})
    # If there is no history yet, prompt the model to open the conversation.
    if not history:
        messages.append({"role": "user",
                         "content": "Start the check-in with the headline pattern."})

    response = litellm.completion(
        model=os.environ.get("LLM_MODEL", "claude-sonnet-4-6"),
        messages=messages,
        api_base=os.environ.get("LLM_BASE_URL") or None,
    )
    content = _strip_code_fence(response.choices[0].message.content)
    data = json.loads(content)

    pv = data.get("proposed_verdict")
    proposed = ProposedVerdict(**pv) if pv else None
    return TrendsConversationResponse(
        reply=data["reply"],
        proposed_verdict=proposed,
        is_closing=bool(data.get("is_closing", False)),
    )
```

- [ ] **Step 4: Run the tests to confirm they pass**

Run: `cd hearty-api && pytest tests/test_trends_conversation_unit.py -v`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/trends_conversation.py hearty-api/tests/test_trends_conversation_unit.py
git commit -m "feat(trends): conversation engine builds prompt, parses verdict envelope"
```

---

## Task 5: `POST /api/trends/conversation` endpoint

**Files:**
- Modify: `hearty-api/app/routers/trends.py` (add the endpoint; import the new schemas + services).

- [ ] **Step 1: Add imports at the top of trends.py**

```python
from app.models.schemas import (
    TrendsConversationRequest, TrendsConversationResponse,
    SignalVerdictRequest, SignalVerdictResponse,
)
from app.services import signal_presenter, trends_conversation
```

- [ ] **Step 2: Add the endpoint**

```python
@router.post("/api/trends/conversation", status_code=200)
async def trends_conversation_turn(
    body: TrendsConversationRequest,
    user=Depends(get_current_user),
) -> TrendsConversationResponse:
    """Generate Hearty's next turn in the monthly trends conversation, grounded
    in the user's overlay-filtered signals."""
    user_id = user["id"]
    signals = signal_presenter.load_presented_signals(supabase, user_id)
    return trends_conversation.generate_turn(signals, body.history)
```

- [ ] **Step 3: Add a unit test (mock supabase + the engine), in `tests/test_trends_conversation_endpoint_unit.py`**

Follow the mocked-Supabase pattern from `tests/test_chat_followup_unit.py` (override `get_current_user`, monkeypatch `trends.supabase`). Minimal version:

```python
from types import SimpleNamespace
from fastapi.testclient import TestClient

from app.main import app
from app.auth import get_current_user
from app.routers import trends as trends_module
from app.models.schemas import TrendsConversationResponse


class _Result:
    def __init__(self, data): self.data = data

class _Table:
    def __init__(self, data): self._data = data
    def select(self, *a, **k): return self
    def eq(self, *a, **k): return self
    def execute(self): return _Result(self._data)

class _Supa:
    def table(self, name):
        return _Table([])  # no signals, no feedback — engine still replies


def test_conversation_endpoint_returns_reply(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    monkeypatch.setattr(trends_module, "supabase", _Supa())
    monkeypatch.setattr(
        trends_module.trends_conversation, "generate_turn",
        lambda signals, history: TrendsConversationResponse(reply="hi", is_closing=False),
    )
    client = TestClient(app)
    r = client.post("/api/trends/conversation", json={"history": []})
    assert r.status_code == 200
    assert r.json()["reply"] == "hi"
    app.dependency_overrides.clear()
```

- [ ] **Step 4: Run it**

Run: `cd hearty-api && pytest tests/test_trends_conversation_endpoint_unit.py -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/routers/trends.py hearty-api/tests/test_trends_conversation_endpoint_unit.py
git commit -m "feat(trends): POST /api/trends/conversation turn endpoint"
```

---

## Task 6: `POST /api/trends/signal-verdict` endpoint (write to overlay)

**Files:**
- Modify: `hearty-api/app/routers/trends.py`.

Writes the user's confirmed verdict to `signal_feedback`, capturing the current `unified_score` as `score_at_verdict` (needed for honest resurfacing). Upsert on the natural key.

- [ ] **Step 1: Add the endpoint**

```python
@router.post("/api/trends/signal-verdict", status_code=200)
async def submit_signal_verdict(
    body: SignalVerdictRequest,
    user=Depends(get_current_user),
) -> SignalVerdictResponse:
    """Record a user's verdict (confirm/dispute/snooze) on a signal. Captures the
    signal's current unified_score so a disputed signal only resurfaces when the
    evidence later grows materially stronger."""
    user_id = user["id"]

    current = (
        supabase.table("food_signals")
        .select("unified_score")
        .eq("user_id", user_id)
        .eq("category", body.category)
        .eq("outcome_type", body.outcome_type)
        .eq("outcome_name", body.outcome_name)
        .limit(1)
        .execute()
    ).data
    score_at_verdict = current[0]["unified_score"] if current else None

    row = {
        "user_id": user_id,
        "category": body.category,
        "outcome_type": body.outcome_type,
        "outcome_name": body.outcome_name,
        "verdict": body.verdict,
        "score_at_verdict": score_at_verdict,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
    supabase.table("signal_feedback").upsert(
        row, on_conflict="user_id,category,outcome_type,outcome_name"
    ).execute()
    return SignalVerdictResponse(ok=True)
```

(`datetime`, `timezone` are already imported at the top of trends.py.)

- [ ] **Step 2: Add a unit test in the same endpoint test file**

```python
def test_signal_verdict_upserts(monkeypatch):
    recorded = {}
    class _T:
        def __init__(self, name): self.name = name
        def select(self, *a, **k): return self
        def eq(self, *a, **k): return self
        def limit(self, *a, **k): return self
        def execute(self): return _Result([{"unified_score": 0.55}])
        def upsert(self, row, **k):
            recorded["row"] = row; recorded["kw"] = k; return self
    class _S:
        def table(self, name): return _T(name)
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    monkeypatch.setattr(trends_module, "supabase", _S())
    client = TestClient(app)
    r = client.post("/api/trends/signal-verdict", json={
        "category": "dairy", "outcome_type": "symptom",
        "outcome_name": "bloating", "verdict": "disputed"})
    assert r.status_code == 200 and r.json()["ok"] is True
    assert recorded["row"]["score_at_verdict"] == 0.55
    assert recorded["kw"]["on_conflict"] == "user_id,category,outcome_type,outcome_name"
    app.dependency_overrides.clear()
```

- [ ] **Step 3: Run it**

Run: `cd hearty-api && pytest tests/test_trends_conversation_endpoint_unit.py -v`
Expected: PASS (both endpoint tests).

- [ ] **Step 4: Commit**

```bash
git add hearty-api/app/routers/trends.py hearty-api/tests/test_trends_conversation_endpoint_unit.py
git commit -m "feat(trends): POST /api/trends/signal-verdict writes feedback overlay"
```

---

## Task 7: Verdict-survives-recompute integration check

**Files:**
- Test: `hearty-api/tests/test_signal_feedback_survives_recompute_unit.py`

Proves the core durability claim: a verdict written to `signal_feedback` is still applied after `food_signals` is wiped and recomputed. Simulated with fakes (no live engine run).

- [ ] **Step 1: Write the test**

```python
from app.services.signal_presenter import apply_overlay


def _sig(score):
    return {"category": "dairy", "outcome_type": "symptom",
            "outcome_name": "bloating", "direction": "harmful",
            "unified_score": score, "relative_risk": 2.0, "evidence_count": 8}


def test_disputed_verdict_still_applies_to_freshly_recomputed_signal():
    # User disputed dairy at score 0.50.
    feedback = [{"category": "dairy", "outcome_type": "symptom",
                 "outcome_name": "bloating", "verdict": "disputed",
                 "score_at_verdict": 0.50}]
    # signal_engine recomputed: a brand-new food_signals row, similar score.
    recomputed = [_sig(0.52)]
    out = apply_overlay(recomputed, feedback, previously_surfaced=set())
    assert out == []  # still suppressed despite being a fresh row
```

- [ ] **Step 2: Run it**

Run: `cd hearty-api && pytest tests/test_signal_feedback_survives_recompute_unit.py -v`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add hearty-api/tests/test_signal_feedback_survives_recompute_unit.py
git commit -m "test(trends): verdict overlay survives signal recompute"
```

**Backend complete and shippable here.** Tasks 8–10 require GATE-1 / GATE-2.

---

## Task 8 (CONTRACT — finalize after GATE-1): Flutter API client methods

**Files:**
- Modify: `hearty_app/lib/core/api/hearty_api_client.dart`

> **Contract task.** The HTTP shape is fully known from Tasks 2/5/6 and can be written now; it does not depend on the dictation rework. Implement these two methods following the existing `chat(...)` / `updateMeal(...)` patterns (Dio, `_call` wrapper, strip-null map).

- [ ] **Step 1: Add the methods**

```dart
/// One turn of the monthly trends conversation. [history] is the prior turns
/// as {'role': 'user'|'assistant', 'content': '...'} maps.
Future<TrendsTurn> trendsConversation(
    List<Map<String, String>> history) {
  return _call(() async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/trends/conversation',
      data: {'history': history},
    );
    return TrendsTurn.fromJson(response.data!);
  });
}

/// Record a confirmed verdict on a signal.
Future<void> submitSignalVerdict({
  required String category,
  required String outcomeType,
  required String outcomeName,
  required String verdict, // 'confirmed' | 'disputed' | 'snoozed'
}) {
  return _call(() async {
    await _dio.post<Map<String, dynamic>>(
      '/api/trends/signal-verdict',
      data: {
        'category': category,
        'outcome_type': outcomeType,
        'outcome_name': outcomeName,
        'verdict': verdict,
      },
    );
  });
}
```

- [ ] **Step 2: Add the `TrendsTurn` model** (new file `hearty_app/lib/core/api/models/trends_turn.dart`) mirroring `TrendsConversationResponse`: `reply` (String), `proposedVerdict` (nullable `{category, outcomeType, outcomeName, verdict}`), `isClosing` (bool); with a `fromJson`.

- [ ] **Step 3: Commit**

```bash
git add hearty_app/lib/core/api/
git commit -m "feat(trends): Flutter API client for conversation + verdict"
```

---

## Task 9 (CONTRACT — finalize after GATE-1): Conversation I/O layer + screen

**Files:**
- Create: `hearty_app/lib/features/trends/providers/trends_conversation_provider.dart`
- Create: `hearty_app/lib/features/trends/screens/trends_conversation_screen.dart`
- Modify: `hearty_app/lib/app/router.dart` (register `Routes.trendsConversation` → `/trends-conversation`, following the existing GoRoute pattern).

> **Contract task — DO NOT code the voice I/O until GATE-1.** The provider is a `StateNotifier` holding `{history, currentReply, pendingVerdict, isClosing, micPhase}`. Its contract:
> - On open: call `trendsConversation([])`, speak `reply` via TTS, then listen via STT (reusing the post-rework dictation pipeline — the same STT/TTS the voice overlay uses).
> - Each user turn: append to history, call `trendsConversation(history)`, speak reply.
> - When `proposedVerdict != null`: render a **confirmable chip**; on tap call `submitSignalVerdict(...)`. **Never** auto-submit from speech.
> - When `isClosing`: speak the closing line, then allow dismiss.
> - Text input always available as a fallback (mirror `voice_overlay_screen.dart`'s text field).
>
> The screen mirrors `voice_overlay_screen.dart` structure (it may reuse the prism waveform during listening). Because the dictation pipeline's exact API is being reworked, **finalize the STT/TTS wiring against the new voice provider** rather than copying today's `_beginStt` internals.

- [ ] **Step 1 (after GATE-1): Design step** — read the post-rework voice provider; decide whether the trends conversation reuses `VoiceNotifier` directly or wraps it. Write a 3-bullet note in this task before coding.
- [ ] **Step 2:** Implement the provider against that decision.
- [ ] **Step 3:** Implement the screen + register the route.
- [ ] **Step 4:** Widget test: given a fake API client returning a scripted turn + a proposed verdict, tapping the verdict chip calls `submitSignalVerdict` exactly once with the right args.
- [ ] **Step 5:** Commit.

---

## Task 10 (CONTRACT — requires GATE-2, finalize after GATE-1): Monthly trigger + manual entry

**Files:**
- Modify: `hearty_app/lib/core/notifications/notification_service.dart`
- Modify: a trends/home screen to add a **"Talk about my trends"** button that navigates to `/trends-conversation` (mirror existing `context.push` usage).

> **Contract task.** Mirrors the existing `scheduleFollowUpNotification` + tap→deeplink pattern. The monthly notification must be **gated**: before/at fire time, call `GET /api/trends/analyze/status`; only present the conversation entry if there are signals worth discussing (reuse `has_new_data` plus a non-empty presented-signal set). The **GATE-2** decision determines whether the gating query runs in a WorkManager background task (post only if worthwhile) or is deferred to tap-time (always post, check on open).

- [ ] **Step 1 (after GATE-2 decision):** Implement the scheduled monthly check using the chosen mechanism; deep-link payload `'/trends-conversation'`.
- [ ] **Step 2:** Add the manual "Talk about my trends" button.
- [ ] **Step 3:** Respect a user preference toggle (add `trendsConversationEnabled` to `UserPreferences`, defaulting true, following the `dailyCheckinEnabled` field pattern).
- [ ] **Step 4:** Commit.

---

## Final review

After all reachable tasks (1–7 now; 8–10 post-gates), dispatch a final code reviewer over the whole implementation, then use `superpowers:finishing-a-development-branch`.

---

## Self-review notes (author)

- **Spec coverage:** decoupled engine (T4), signal presenter overlay (T3), feedback table (T1), verdict endpoint (T6), conversation endpoint (T5), durability across recompute (T7), turn-based I/O contract (T9), monthly smart-notification + manual button + preference (T10), text fallback (T9). "Tracked experiments" correctly excluded (future spec).
- **Known simplification (logged, not hidden):** `previously_surfaced` is derived from `signal_feedback` identities rather than a dedicated surfaced-log — so `is_new` means "never verdicted," a pragmatic proxy for v1. If product wants true "new since last *conversation*," add a `last_conversation_at` per-user timestamp + a surfaced-signals log; noted here rather than silently approximated.
- **Gates are real:** Tasks 8–10 are contracts, not placeholders — the HTTP shapes are concrete (T8 is fully implementable now); only the STT/TTS wiring waits on the dictation rework.
