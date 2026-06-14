# Tracked Experiments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let Hearty turn a harmful trend into a 14-day elimination experiment offered from the trends conversation, infer adherence from normal logs, nudge once if the user drifts, and report an honest improved/no_change/worse/inconclusive result that can write a `confirmed` verdict back into the trends feedback loop.

**Architecture:** A new `experiments` table + thin store; pure adherence/nudge/evaluator services (reusing `food_category_service` + the `signal_engine` rate style); an `experiments` router; nudge surfaced via the active-experiments fetch (defer-to-tap); experiment offers added to the existing trends conversation; result write-back reuses the existing `POST /api/trends/signal-verdict`. Flutter chips/result view are text-first, voice + notifications device-verified.

**Tech Stack:** FastAPI + Supabase (python client, service key) + litellm; Flutter/Riverpod/Dio; Supabase migrations. Spec: `docs/superpowers/specs/2026-06-04-tracked-experiments-design.md`. Backend test runner: `cd hearty-api && set -a && . ../.env && set +a && .venv/bin/python -m pytest <file> -v`. Migrations: `scripts/db-push.sh`.

**Constants (module-level, env-overridable):** `EXPERIMENT_DAYS=14`, `ADHERENCE_MIN=0.7`, `MIN_WINDOW_DAYS=7`, `NUDGE_ADHERENCE=0.5`, `NUDGE_MIN_DAYS=4`, `IMPROVE_REL_MARGIN=0.2`.

---

## File Structure

**Backend:**
- `supabase/migrations/20260614000002_experiments.sql` — table + partial-unique + RLS.
- `hearty-api/app/services/experiment_adherence.py` — pure: `compute_adherence` + `should_nudge`.
- `hearty-api/app/services/experiment_evaluator.py` — pure: `evaluate`.
- `hearty-api/app/services/experiment_store.py` — thin Supabase store.
- `hearty-api/app/routers/experiments.py` — endpoints.
- `hearty-api/app/models/schemas.py` — request/response models.
- `hearty-api/app/main.py` — register router.
- `hearty-api/app/services/trends_conversation.py` — offer an experiment in the turn.
- `hearty-api/app/models/schemas.py` — `ProposedExperiment` + `TrendsConversationResponse.proposed_experiment`.

**Flutter (contracts, text-first):**
- `hearty_app/lib/core/api/hearty_api_client.dart` — experiment methods.
- `hearty_app/lib/core/api/models/experiment.dart` — models.
- `hearty_app/lib/features/trends/...` — start chip in the conversation; nudge dialog; result view.
- `hearty_app/lib/core/notifications/notification_service.dart` — experiment-end notification.

---

## Task 1: `experiments` migration

**Files:**
- Create: `supabase/migrations/20260614000002_experiments.sql`

- [ ] **Step 1: Write the migration**

```sql
-- Tracked Experiments: a time-boxed elimination test of a harmful food pattern.
-- One active experiment per (category, outcome) at a time. nudged_at gates the
-- one-time mid-course adherence nudge. Mirrors the RLS/owner pattern of food_signals.
CREATE TABLE experiments (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID REFERENCES auth.users NOT NULL,
  category         TEXT NOT NULL,
  direction        TEXT NOT NULL DEFAULT 'eliminate' CHECK (direction IN ('eliminate', 'add')),
  outcome_type     TEXT NOT NULL CHECK (outcome_type IN ('symptom', 'wellbeing')),
  outcome_name     TEXT NOT NULL,
  baseline_start   TIMESTAMPTZ NOT NULL,
  baseline_end     TIMESTAMPTZ NOT NULL,
  experiment_start TIMESTAMPTZ NOT NULL,
  experiment_end   TIMESTAMPTZ NOT NULL,
  status           TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'abandoned')),
  result           JSONB,
  nudged_at        TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- At most one ACTIVE experiment per pattern.
CREATE UNIQUE INDEX uniq_active_experiment
  ON experiments (user_id, category, outcome_type, outcome_name)
  WHERE status = 'active';

CREATE INDEX idx_experiments_user_status ON experiments (user_id, status);

ALTER TABLE experiments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "experiments_owner_only" ON experiments
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
```

- [ ] **Step 2: Apply** — `scripts/db-push.sh --dry-run` (confirm only this is pending), then `scripts/db-push.sh --yes`.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260614000002_experiments.sql
git commit -m "feat(experiments): experiments table (one active per pattern, RLS)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Adherence calculator + nudge trigger (pure, TDD)

**Files:**
- Create: `hearty-api/app/services/experiment_adherence.py`
- Test: `hearty-api/tests/test_experiment_adherence_unit.py`

- [ ] **Step 1: Write the failing test**

```python
from datetime import datetime, timezone
from app.services.experiment_adherence import compute_adherence, should_nudge


def _meal(day, foods):
    return {"logged_at": datetime(2026, 6, day, 12, tzinfo=timezone.utc).isoformat(),
            "foods": [{"name": f} for f in foods]}


def _classify(names, cache=None):
    # 'milk'/'cheese' -> dairy; everything else uncategorized
    return {n: (["dairy"] if n in ("milk", "cheese") else []) for n in names}


def test_clean_and_violation_days():
    meals = [
        _meal(1, ["apple"]),          # clean
        _meal(2, ["cheese"]),         # violation
        _meal(3, ["rice", "milk"]),   # violation (milk)
        _meal(4, ["toast"]),          # clean
    ]
    a = compute_adherence(meals, "dairy", classify=_classify)
    assert a["logged_days"] == 4
    assert a["clean_days"] == 2
    assert a["adherence"] == 0.5


def test_multiple_meals_same_day_one_violation_taints_day():
    meals = [_meal(1, ["apple"]), _meal(1, ["cheese"])]  # same day, one dirty
    a = compute_adherence(meals, "dairy", classify=_classify)
    assert a["logged_days"] == 1
    assert a["clean_days"] == 0
    assert a["adherence"] == 0.0


def test_no_meals_is_zero_logged_days_not_divide_by_zero():
    a = compute_adherence([], "dairy", classify=_classify)
    assert a == {"clean_days": 0, "logged_days": 0, "adherence": 0.0}


def test_should_nudge_only_when_low_after_min_days_and_not_yet_nudged():
    # below 0.5 after >=4 days, not nudged -> True
    assert should_nudge(adherence=0.4, logged_days=5, nudged_at=None) is True
    # adherence fine -> False
    assert should_nudge(adherence=0.8, logged_days=5, nudged_at=None) is False
    # too few days (one early slip) -> False
    assert should_nudge(adherence=0.0, logged_days=2, nudged_at=None) is False
    # already nudged -> False
    assert should_nudge(adherence=0.1, logged_days=9, nudged_at="2026-06-10T00:00:00Z") is False
```

- [ ] **Step 2: Run to confirm fail** — `...pytest tests/test_experiment_adherence_unit.py -v` → module missing.

- [ ] **Step 3: Implement**

```python
"""Experiment adherence: infer how well the user stayed off the eliminated
category from their normal logs, and decide the one-time mid-course nudge. Pure —
classification is injected (defaults to food_category_service)."""

import os
from datetime import datetime

from app.services.food_category_service import classify_foods_cached

NUDGE_ADHERENCE = float(os.environ.get("EXPERIMENT_NUDGE_ADHERENCE", "0.5"))
NUDGE_MIN_DAYS = int(os.environ.get("EXPERIMENT_NUDGE_MIN_DAYS", "4"))


def _default_classify(names):
    return classify_foods_cached(names, {})


def compute_adherence(meals: list, category: str, classify=None) -> dict:
    """A 'clean day' has >=1 logged meal and no meal containing `category`.
    adherence = clean_days / logged_days. No meals -> all zeros (no divide-by-0)."""
    classify = classify or _default_classify
    names = []
    for m in meals:
        for f in (m.get("foods") or []):
            n = (f.get("name") or "").strip().lower()
            if n:
                names.append(n)
    category_map = classify(list(set(names)))

    by_day: dict[str, bool] = {}  # day -> clean so far
    for m in meals:
        day = m["logged_at"][:10]  # YYYY-MM-DD
        dirty = any(
            category in category_map.get((f.get("name") or "").strip().lower(), [])
            for f in (m.get("foods") or [])
        )
        by_day[day] = by_day.get(day, True) and not dirty

    logged_days = len(by_day)
    clean_days = sum(1 for clean in by_day.values() if clean)
    adherence = (clean_days / logged_days) if logged_days else 0.0
    return {"clean_days": clean_days, "logged_days": logged_days,
            "adherence": adherence}


def should_nudge(adherence: float, logged_days: int, nudged_at) -> bool:
    """One-time mid-course nudge: low adherence, enough days elapsed, not nudged yet."""
    if nudged_at:
        return False
    if logged_days < NUDGE_MIN_DAYS:
        return False
    return adherence < NUDGE_ADHERENCE
```

- [ ] **Step 4: Run to confirm pass** (4 tests).

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/experiment_adherence.py hearty-api/tests/test_experiment_adherence_unit.py
git commit -m "feat(experiments): adherence calculator + one-time nudge trigger (pure)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Experiment evaluator (pure, TDD)

**Files:**
- Create: `hearty-api/app/services/experiment_evaluator.py`
- Test: `hearty-api/tests/test_experiment_evaluator_unit.py`

Outcome rates: **symptom** = (days with ≥1 `outcome_name` symptom) / logged_days; **wellbeing** = mean of `outcome_name` over snapshots. Eliminating a *harmful* pattern should drop a symptom rate or raise a wellbeing mean.

- [ ] **Step 1: Write the failing test**

```python
from datetime import datetime, timezone
from app.services.experiment_evaluator import evaluate


def _sym(day, name="bloating"):
    return {"logged_at": datetime(2026, 6, day, 14, tzinfo=timezone.utc).isoformat(),
            "symptom_type": name}


def _wb(day, energy):
    return {"logged_at": datetime(2026, 6, day, 9, tzinfo=timezone.utc).isoformat(),
            "energy_level": energy}


def _good_adherence():
    return {"clean_days": 12, "logged_days": 13, "adherence": 0.92}


def test_low_adherence_is_inconclusive():
    out = evaluate(outcome_type="symptom", outcome_name="bloating",
                   baseline_symptoms=[_sym(1)], experiment_symptoms=[],
                   baseline_wellbeing=[], experiment_wellbeing=[],
                   baseline_logged_days=10, experiment_logged_days=10,
                   adherence={"clean_days": 4, "logged_days": 10, "adherence": 0.4})
    assert out["verdict"] == "inconclusive"
    assert out["reason"] == "low_adherence"


def test_thin_data_is_inconclusive():
    out = evaluate(outcome_type="symptom", outcome_name="bloating",
                   baseline_symptoms=[], experiment_symptoms=[],
                   baseline_wellbeing=[], experiment_wellbeing=[],
                   baseline_logged_days=3, experiment_logged_days=10,
                   adherence=_good_adherence())
    assert out["verdict"] == "inconclusive"
    assert out["reason"] == "thin_data"


def test_symptom_dropped_is_improved():
    # baseline: bloating on 6 of 10 days; experiment: 1 of 10
    base = [_sym(d) for d in range(1, 7)]
    exp = [_sym(20)]
    out = evaluate(outcome_type="symptom", outcome_name="bloating",
                   baseline_symptoms=base, experiment_symptoms=exp,
                   baseline_wellbeing=[], experiment_wellbeing=[],
                   baseline_logged_days=10, experiment_logged_days=10,
                   adherence=_good_adherence())
    assert out["verdict"] == "improved"
    assert out["baseline_rate"] > out["experiment_rate"]


def test_symptom_unchanged_is_no_change():
    base = [_sym(d) for d in range(1, 6)]
    exp = [_sym(d) for d in range(15, 20)]
    out = evaluate(outcome_type="symptom", outcome_name="bloating",
                   baseline_symptoms=base, experiment_symptoms=exp,
                   baseline_wellbeing=[], experiment_wellbeing=[],
                   baseline_logged_days=10, experiment_logged_days=10,
                   adherence=_good_adherence())
    assert out["verdict"] == "no_change"


def test_wellbeing_rose_is_improved():
    base = [_wb(d, 4) for d in range(1, 8)]
    exp = [_wb(d, 8) for d in range(15, 22)]
    out = evaluate(outcome_type="wellbeing", outcome_name="energy_level",
                   baseline_symptoms=[], experiment_symptoms=[],
                   baseline_wellbeing=base, experiment_wellbeing=exp,
                   baseline_logged_days=10, experiment_logged_days=10,
                   adherence=_good_adherence())
    assert out["verdict"] == "improved"
    assert out["experiment_rate"] > out["baseline_rate"]
```

- [ ] **Step 2: Run to confirm fail.**

- [ ] **Step 3: Implement**

```python
"""Experiment evaluator: baseline-vs-experiment outcome comparison with honest
guardrails. Pure. result dict: verdict, reason, adherence, baseline_rate,
experiment_rate, logged_days."""

import os

ADHERENCE_MIN = float(os.environ.get("EXPERIMENT_ADHERENCE_MIN", "0.7"))
MIN_WINDOW_DAYS = int(os.environ.get("EXPERIMENT_MIN_WINDOW_DAYS", "7"))
IMPROVE_REL_MARGIN = float(os.environ.get("EXPERIMENT_IMPROVE_REL_MARGIN", "0.2"))


def _symptom_rate(symptoms: list, name: str, logged_days: int) -> float:
    if logged_days <= 0:
        return 0.0
    days = {s["logged_at"][:10] for s in symptoms if s.get("symptom_type") == name}
    return len(days) / logged_days


def _wellbeing_mean(snapshots: list, name: str) -> float:
    vals = [s[name] for s in snapshots if s.get(name) is not None]
    return (sum(vals) / len(vals)) if vals else 0.0


def evaluate(*, outcome_type: str, outcome_name: str,
             baseline_symptoms: list, experiment_symptoms: list,
             baseline_wellbeing: list, experiment_wellbeing: list,
             baseline_logged_days: int, experiment_logged_days: int,
             adherence: dict) -> dict:
    result = {
        "adherence": adherence["adherence"],
        "logged_days": {"baseline": baseline_logged_days,
                        "experiment": experiment_logged_days},
        "baseline_rate": None, "experiment_rate": None,
    }

    if adherence["adherence"] < ADHERENCE_MIN:
        return {**result, "verdict": "inconclusive", "reason": "low_adherence"}
    if (baseline_logged_days < MIN_WINDOW_DAYS
            or experiment_logged_days < MIN_WINDOW_DAYS):
        return {**result, "verdict": "inconclusive", "reason": "thin_data"}

    if outcome_type == "symptom":
        base = _symptom_rate(baseline_symptoms, outcome_name, baseline_logged_days)
        exp = _symptom_rate(experiment_symptoms, outcome_name, experiment_logged_days)
        improved = exp <= base * (1 - IMPROVE_REL_MARGIN)
        worse = exp >= base * (1 + IMPROVE_REL_MARGIN)
    else:  # wellbeing: higher is better
        base = _wellbeing_mean(baseline_wellbeing, outcome_name)
        exp = _wellbeing_mean(experiment_wellbeing, outcome_name)
        improved = exp >= base * (1 + IMPROVE_REL_MARGIN)
        worse = exp <= base * (1 - IMPROVE_REL_MARGIN)

    verdict = "improved" if improved else "worse" if worse else "no_change"
    return {**result, "verdict": verdict, "reason": None,
            "baseline_rate": round(base, 4), "experiment_rate": round(exp, 4)}
```

- [ ] **Step 4: Run to confirm pass** (5 tests).

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/experiment_evaluator.py hearty-api/tests/test_experiment_evaluator_unit.py
git commit -m "feat(experiments): evaluator with adherence + thin-data guardrails (pure)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Schemas

**Files:**
- Modify: `hearty-api/app/models/schemas.py`

- [ ] **Step 1: Add models** (append near the trends models; `BaseModel/Field/Optional/List/Literal/Dict` already imported)

```python
# ─── Tracked Experiments ─────────────────────────────────────────────────────

class CreateExperimentRequest(BaseModel):
    category: str
    outcome_type: Literal["symptom", "wellbeing"]
    outcome_name: str

class ExperimentResponse(BaseModel):
    id: str
    category: str
    direction: str
    outcome_type: str
    outcome_name: str
    experiment_start: str
    experiment_end: str
    status: str
    result: Optional[Dict] = None
    nudged_at: Optional[str] = None
    # Computed on the active fetch (not stored):
    adherence: Optional[float] = None
    logged_days: Optional[int] = None
    nudge_suggested: bool = False

class ActiveExperimentsResponse(BaseModel):
    experiments: List[ExperimentResponse] = Field(default_factory=list)
```

- [ ] **Step 2: Verify import**

Run: `cd hearty-api && set -a && . ../.env && set +a && .venv/bin/python -c "from app.models.schemas import CreateExperimentRequest, ExperimentResponse, ActiveExperimentsResponse; print('ok')"`

- [ ] **Step 3: Commit**

```bash
git add hearty-api/app/models/schemas.py
git commit -m "feat(experiments): request/response schemas

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Experiment store (thin DB layer)

**Files:**
- Create: `hearty-api/app/services/experiment_store.py`
- Test: `hearty-api/tests/test_experiment_store_unit.py`

- [ ] **Step 1: Write the failing test** (mocked supabase recorder)

```python
from datetime import datetime, timezone
from app.services import experiment_store as es


class _Result:
    def __init__(self, data): self.data = data


def test_create_builds_window_and_inserts(monkeypatch):
    rec = {}
    class _T:
        def insert(self, row): rec["row"] = row; return self
        def execute(self): return _Result([{**rec["row"], "id": "e1"}])
    monkeypatch.setattr(es, "supabase", type("S", (), {"table": lambda s, n: _T()})())

    class _FixedDate(datetime):
        @classmethod
        def now(cls, tz=None): return datetime(2026, 6, 14, tzinfo=timezone.utc)
    monkeypatch.setattr(es, "datetime", _FixedDate)

    out = es.create_experiment("u1", "dairy", "symptom", "bloating")
    row = rec["row"]
    assert row["user_id"] == "u1" and row["category"] == "dairy"
    assert row["direction"] == "eliminate" and row["status"] == "active"
    # 14-day window; baseline is the matched prior 14 days
    assert row["experiment_start"] == datetime(2026, 6, 14, tzinfo=timezone.utc).isoformat()
    assert row["experiment_end"] == datetime(2026, 6, 28, tzinfo=timezone.utc).isoformat()
    assert row["baseline_start"] == datetime(2026, 5, 31, tzinfo=timezone.utc).isoformat()
    assert row["baseline_end"] == row["experiment_start"]
    assert out["id"] == "e1"


def test_abandon_sets_status(monkeypatch):
    rec = {}
    class _T:
        def update(self, vals): rec["vals"] = vals; return self
        def eq(self, *a, **k): return self
        def execute(self): return _Result([{"id": "e1"}])
    monkeypatch.setattr(es, "supabase", type("S", (), {"table": lambda s, n: _T()})())
    es.abandon_experiment("u1", "e1")
    assert rec["vals"]["status"] == "abandoned"
```

- [ ] **Step 2: Run to confirm fail.**

- [ ] **Step 3: Implement**

```python
"""Thin Supabase store for experiments. Window math lives here; adherence and
evaluation are computed elsewhere."""

import os
from datetime import datetime, timezone, timedelta

from supabase import create_client

EXPERIMENT_DAYS = int(os.environ.get("EXPERIMENT_DAYS", "14"))
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


def create_experiment(user_id: str, category: str, outcome_type: str,
                      outcome_name: str) -> dict:
    now = datetime.now(timezone.utc)
    end = now + timedelta(days=EXPERIMENT_DAYS)
    baseline_start = now - timedelta(days=EXPERIMENT_DAYS)
    row = {
        "user_id": user_id, "category": category, "direction": "eliminate",
        "outcome_type": outcome_type, "outcome_name": outcome_name,
        "baseline_start": baseline_start.isoformat(),
        "baseline_end": now.isoformat(),
        "experiment_start": now.isoformat(),
        "experiment_end": end.isoformat(),
        "status": "active",
    }
    return supabase.table("experiments").insert(row).execute().data[0]


def get_active(user_id: str) -> list[dict]:
    return (supabase.table("experiments").select("*")
            .eq("user_id", user_id).eq("status", "active").execute()).data or []


def get_one(user_id: str, experiment_id: str) -> dict | None:
    rows = (supabase.table("experiments").select("*")
            .eq("user_id", user_id).eq("id", experiment_id).execute()).data or []
    return rows[0] if rows else None


def abandon_experiment(user_id: str, experiment_id: str) -> None:
    supabase.table("experiments").update({"status": "abandoned"}) \
        .eq("user_id", user_id).eq("id", experiment_id).execute()


def restart_experiment(user_id: str, experiment_id: str) -> dict:
    now = datetime.now(timezone.utc)
    vals = {
        "experiment_start": now.isoformat(),
        "experiment_end": (now + timedelta(days=EXPERIMENT_DAYS)).isoformat(),
        "baseline_start": (now - timedelta(days=EXPERIMENT_DAYS)).isoformat(),
        "baseline_end": now.isoformat(),
        "nudged_at": None,
    }
    return (supabase.table("experiments").update(vals)
            .eq("user_id", user_id).eq("id", experiment_id).execute()).data[0]


def mark_completed(user_id: str, experiment_id: str, result: dict) -> None:
    supabase.table("experiments").update({"status": "completed", "result": result}) \
        .eq("user_id", user_id).eq("id", experiment_id).execute()


def mark_nudged(user_id: str, experiment_id: str) -> None:
    supabase.table("experiments").update(
        {"nudged_at": datetime.now(timezone.utc).isoformat()}) \
        .eq("user_id", user_id).eq("id", experiment_id).execute()
```

- [ ] **Step 4: Run to confirm pass** (2 tests).

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/experiment_store.py hearty-api/tests/test_experiment_store_unit.py
git commit -m "feat(experiments): store (create/get/abandon/restart/complete/nudge)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Experiments router (create / active / evaluate / abandon / restart / ack-nudge)

**Files:**
- Create: `hearty-api/app/routers/experiments.py`
- Modify: `hearty-api/app/main.py` (register), reuse `_load_between` from `signal_engine` for window data.
- Test: `hearty-api/tests/test_experiments_endpoint_unit.py`

The active fetch computes adherence + `nudge_suggested` per active experiment. `evaluate` loads baseline+experiment windows (`signal_engine._load_between`), runs adherence + evaluator, stores the result. ack-nudge sets `nudged_at`.

- [ ] **Step 1: Write the failing tests**

```python
from datetime import datetime, timezone, timedelta
from fastapi.testclient import TestClient
from app.main import app
from app.auth import get_current_user
from app.routers import experiments as ex


class _Result:
    def __init__(self, data): self.data = data


def test_create_experiment(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    monkeypatch.setattr(ex.experiment_store, "create_experiment",
                        lambda u, c, ot, on: {"id": "e1", "category": c,
                            "direction": "eliminate", "outcome_type": ot,
                            "outcome_name": on, "experiment_start": "s",
                            "experiment_end": "e", "status": "active",
                            "result": None, "nudged_at": None})
    client = TestClient(app)
    r = client.post("/api/experiments", json={"category": "dairy",
                    "outcome_type": "symptom", "outcome_name": "bloating"})
    assert r.status_code == 200 and r.json()["category"] == "dairy"
    app.dependency_overrides.clear()


def test_active_includes_adherence_and_nudge_flag(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    start = (datetime.now(timezone.utc) - timedelta(days=6)).isoformat()
    monkeypatch.setattr(ex.experiment_store, "get_active", lambda u: [{
        "id": "e1", "category": "dairy", "direction": "eliminate",
        "outcome_type": "symptom", "outcome_name": "bloating",
        "experiment_start": start, "experiment_end": "z", "status": "active",
        "result": None, "nudged_at": None}])
    monkeypatch.setattr(ex.signal_engine, "_load_between", lambda u, s, e: ([], [], []))
    # force low adherence after enough days
    monkeypatch.setattr(ex.experiment_adherence, "compute_adherence",
                        lambda meals, cat, classify=None: {"clean_days": 1,
                            "logged_days": 5, "adherence": 0.2})
    client = TestClient(app)
    r = client.get("/api/experiments/active")
    body = r.json()["experiments"][0]
    assert body["adherence"] == 0.2
    assert body["nudge_suggested"] is True
    app.dependency_overrides.clear()


def test_abandon(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    called = {}
    monkeypatch.setattr(ex.experiment_store, "abandon_experiment",
                        lambda u, i: called.setdefault("id", i))
    client = TestClient(app)
    r = client.post("/api/experiments/e1/abandon")
    assert r.status_code == 200 and called["id"] == "e1"
    app.dependency_overrides.clear()
```

- [ ] **Step 2: Run to confirm fail.**

- [ ] **Step 3: Implement the router**

```python
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException

from app.auth import get_current_user
from app.models.schemas import (
    CreateExperimentRequest, ExperimentResponse, ActiveExperimentsResponse,
)
from app.services import experiment_store, experiment_adherence, experiment_evaluator
from app.services import signal_engine

router = APIRouter()


def _to_response(row: dict, **extra) -> ExperimentResponse:
    return ExperimentResponse(
        id=row["id"], category=row["category"], direction=row["direction"],
        outcome_type=row["outcome_type"], outcome_name=row["outcome_name"],
        experiment_start=row["experiment_start"], experiment_end=row["experiment_end"],
        status=row["status"], result=row.get("result"), nudged_at=row.get("nudged_at"),
        **extra,
    )


@router.post("/api/experiments", status_code=200)
async def create_experiment(body: CreateExperimentRequest,
                            user=Depends(get_current_user)) -> ExperimentResponse:
    try:
        row = experiment_store.create_experiment(
            user["id"], body.category, body.outcome_type, body.outcome_name)
    except Exception as e:
        # partial-unique violation = an active experiment already exists for this pattern
        raise HTTPException(status_code=409, detail="active experiment already exists")
    return _to_response(row)


@router.get("/api/experiments/active", status_code=200)
async def active_experiments(user=Depends(get_current_user)) -> ActiveExperimentsResponse:
    user_id = user["id"]
    out = []
    for row in experiment_store.get_active(user_id):
        meals, _sym, _wb = signal_engine._load_between(
            user_id, row["experiment_start"], datetime.now(timezone.utc).isoformat())
        adh = experiment_adherence.compute_adherence(meals, row["category"])
        nudge = experiment_adherence.should_nudge(
            adh["adherence"], adh["logged_days"], row.get("nudged_at"))
        out.append(_to_response(row, adherence=adh["adherence"],
                                logged_days=adh["logged_days"], nudge_suggested=nudge))
    return ActiveExperimentsResponse(experiments=out)


@router.post("/api/experiments/{experiment_id}/evaluate", status_code=200)
async def evaluate_experiment(experiment_id: str,
                              user=Depends(get_current_user)) -> ExperimentResponse:
    user_id = user["id"]
    row = experiment_store.get_one(user_id, experiment_id)
    if not row:
        raise HTTPException(status_code=404, detail="experiment not found")
    b_meals, b_sym, b_wb = signal_engine._load_between(
        user_id, row["baseline_start"], row["baseline_end"])
    e_meals, e_sym, e_wb = signal_engine._load_between(
        user_id, row["experiment_start"], row["experiment_end"])
    adh = experiment_adherence.compute_adherence(e_meals, row["category"])
    b_adh = experiment_adherence.compute_adherence(b_meals, row["category"])
    result = experiment_evaluator.evaluate(
        outcome_type=row["outcome_type"], outcome_name=row["outcome_name"],
        baseline_symptoms=b_sym, experiment_symptoms=e_sym,
        baseline_wellbeing=b_wb, experiment_wellbeing=e_wb,
        baseline_logged_days=b_adh["logged_days"],
        experiment_logged_days=adh["logged_days"], adherence=adh)
    experiment_store.mark_completed(user_id, experiment_id, result)
    row = {**row, "status": "completed", "result": result}
    return _to_response(row)


@router.post("/api/experiments/{experiment_id}/abandon", status_code=200)
async def abandon(experiment_id: str, user=Depends(get_current_user)) -> dict:
    experiment_store.abandon_experiment(user["id"], experiment_id)
    return {"ok": True}


@router.post("/api/experiments/{experiment_id}/restart", status_code=200)
async def restart(experiment_id: str, user=Depends(get_current_user)) -> ExperimentResponse:
    row = experiment_store.restart_experiment(user["id"], experiment_id)
    return _to_response(row)


@router.post("/api/experiments/{experiment_id}/ack-nudge", status_code=200)
async def ack_nudge(experiment_id: str, user=Depends(get_current_user)) -> dict:
    experiment_store.mark_nudged(user["id"], experiment_id)
    return {"ok": True}
```

Register in `app/main.py`: add `experiments` to the `from app.routers import (...)` line and `app.include_router(experiments.router)` with the others.

- [ ] **Step 4: Run** the endpoint tests + full suite (`--ignore=tests/test_api.py`).

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/routers/experiments.py hearty-api/app/main.py hearty-api/tests/test_experiments_endpoint_unit.py
git commit -m "feat(experiments): endpoints (create/active+nudge/evaluate/abandon/restart/ack)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Conversation offers an experiment

**Files:**
- Modify: `hearty-api/app/models/schemas.py` (`ProposedExperiment` + `TrendsConversationResponse.proposed_experiment`)
- Modify: `hearty-api/app/services/trends_conversation.py` (prompt + parse)
- Test: `hearty-api/tests/test_trends_conversation_unit.py` (add a case)

- [ ] **Step 1: Schemas** — add:

```python
class ProposedExperiment(BaseModel):
    category: str
    outcome_type: Literal["symptom", "wellbeing"]
    outcome_name: str
```
and add to `TrendsConversationResponse`: `proposed_experiment: Optional[ProposedExperiment] = None`.

- [ ] **Step 2: Failing test** (add to `test_trends_conversation_unit.py`)

```python
def test_generate_turn_parses_proposed_experiment():
    import json
    from unittest.mock import patch
    from types import SimpleNamespace
    fake = SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(
        content=json.dumps({
            "reply": "Want to actually test the dairy link — cut it for two weeks?",
            "proposed_verdict": None,
            "proposed_experiment": {"category": "dairy", "outcome_type": "symptom",
                                    "outcome_name": "bloating"},
            "is_closing": False,
        })))])
    with patch.object(tc.litellm, "completion", return_value=fake):
        out = tc.generate_turn(_presented(), history=[])
    assert out.proposed_experiment is not None
    assert out.proposed_experiment.category == "dairy"
```

- [ ] **Step 3: Implement** — in `trends_conversation.py`:
  - In `build_system_prompt`, extend the JSON envelope contract to include `"proposed_experiment": null OR {"category","outcome_type","outcome_name"}` and add an instruction bullet: "For a HARMFUL pattern the user seems interested in, you may offer a 2-week elimination experiment via proposed_experiment (the same category/outcome as that pattern) — never start it silently; the app shows a confirm chip."
  - In `generate_turn`, parse it:
```python
    pe = data.get("proposed_experiment")
    proposed_exp = ProposedExperiment(**pe) if pe else None
```
  and pass `proposed_experiment=proposed_exp` into the `TrendsConversationResponse(...)`. Import `ProposedExperiment`.

- [ ] **Step 4: Run** the conversation tests + full suite.

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/models/schemas.py hearty-api/app/services/trends_conversation.py hearty-api/tests/test_trends_conversation_unit.py
git commit -m "feat(experiments): trends conversation can propose an elimination experiment

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8 (CONTRACT — text-first): Flutter API client + models

**Files:**
- Create: `hearty_app/lib/core/api/models/experiment.dart` — `Experiment` (id, category, outcomeType, outcomeName, experimentStart/End, status, result map?, nudgedAt?, adherence?, loggedDays?, nudgeSuggested) + `ProposedExperiment` (mirror the conversation field) with `fromJson`.
- Modify: `hearty_app/lib/core/api/hearty_api_client.dart` — add, mirroring the existing `_call`/`_dio` pattern + the trends methods:
  - `Future<Experiment> createExperiment({required String category, required String outcomeType, required String outcomeName})` → POST `/api/experiments`.
  - `Future<List<Experiment>> fetchActiveExperiments()` → GET `/api/experiments/active` (parse `experiments`).
  - `Future<Experiment> evaluateExperiment(String id)` → POST `/api/experiments/{id}/evaluate`.
  - `Future<void> abandonExperiment(String id)` / `restartExperiment(String id)` / `ackExperimentNudge(String id)`.
- Also extend `TrendsTurn` (`models/trends_turn.dart`) with `proposedExperiment` parsed from `proposed_experiment`.
- Test: `hearty_app/test/core/api/hearty_api_client_experiments_test.dart` mirroring the existing interceptor-based client tests (create parses; active parses adherence+nudgeSuggested; abandon posts the path).

- [ ] Implement, test (`flutter test test/core/api/hearty_api_client_experiments_test.dart`), `flutter analyze lib/core/api/`, commit.

---

## Task 9 (CONTRACT — text-first): Start chip in the trends conversation

**Files:**
- Modify: `hearty_app/lib/features/trends/screens/trends_conversation_screen.dart` + its provider.

> When a turn carries `proposedExperiment != null`, render a confirm chip "Test this — cut {category} for 2 weeks?" (keyed `trends-experiment-chip`). Tapping calls `createExperiment(...)` then shows a short confirmation ("Started — I'll check back in two weeks"). Never auto-create. Mirror the existing verdict-chip wiring (`confirmVerdict`). Widget test: a turn with a proposed experiment → tapping the chip calls `createExperiment` once with the right args (fake client).

- [ ] Implement, widget test, analyze, commit.

---

## Task 10 (CONTRACT — requires defer-to-tap scheduling): end-of-window + nudge surfacing + result view

**Files:**
- Modify: `hearty_app/lib/core/notifications/notification_service.dart` — `scheduleExperimentEndNotification({required String experimentId, required DateTime end})` (new id 3013 + channel), payload `/experiment-result?id=<id>`; mirror `scheduleCheckinNotification`.
- Create: `hearty_app/lib/features/experiments/screens/experiment_result_screen.dart` + route `/experiment-result` — on open calls `evaluateExperiment(id)`, shows the plain-language result; when `result.verdict == 'improved'` (and not low-adherence) offers a confirm chip → `submitSignalVerdict(category, outcomeType, outcomeName, 'confirmed')` (the EXISTING trends endpoint).
- Nudge surfacing: where active experiments are fetched (app start / trends entry — mirror `checkinGapsTodayProvider`), if any `nudgeSuggested`, show a dialog "noticed {category} in a few meals — keep going / restart / stop": keep → `ackExperimentNudge(id)`; restart → `restartExperiment(id)`; stop → `abandonExperiment(id)`.
- Schedule the end notification when an experiment is created (in the start-chip success path), gated on a `experimentsEnabled` pref if you add one (optional; default on).

> All voice-adjacent surfaces are text-first. GATE: this is **device-verified** (notifications + real evaluation). Add widget tests for the result view (improved → confirm chip calls submitSignalVerdict; inconclusive → no chip) and the nudge dialog (each action calls the right client method) using fake clients; the notification scheduling is analyze-only.

- [ ] Implement, widget tests, analyze, full `flutter test`, commit.

---

## Device verification (after the tasks)

- Start an experiment from the trends conversation → row created (409 if one already active for that pattern).
- Log meals containing the category for several days → on next active fetch, the nudge dialog appears once; keep/restart/stop behave; it doesn't reappear after "keep".
- At/after `experiment_end`, the notification → result view evaluates and shows a plain-language verdict; an `improved`+adherent result's confirm chip writes a `confirmed` verdict (verify it appears in the trends conversation/overlay).
- Low-adherence run → `inconclusive`, no confirm chip, nothing written.

---

## Self-review

- **Spec coverage:** experiments table + one-active constraint (T1) · adherence option-A inference (T2) · one-time mid-course nudge trigger (T2 `should_nudge`, surfaced T6 active fetch, delivered T10) · evaluator with low-adherence + thin-data guardrails and improved/no_change/worse (T3) · store + window/baseline math (T5) · endpoints incl. restart/abandon/ack (T6) · conversation offer (T7) · feedback write-back reuses `POST /api/trends/signal-verdict` (T10) · Flutter chips/result/nudge (T8–T10). `add` direction reserved in the schema (T1), eliminate-only logic (T3).
- **Adaptation noted:** the spec said nudge detection rides "on the meal-logging path (no polling)"; this plan computes it on the **active-experiments fetch** (the defer-to-tap surface the client already hits) — same one-time behavior, far simpler than hooking three meal-write paths, and the server can't fire a local notification anyway. Flagged for awareness; behavior matches the approved design.
- **Placeholders:** backend tasks (1–7) have full code; Flutter tasks (8–10) are contract tasks with exact API shapes, behaviors, keys, and test targets (the established pattern for device/voice-dependent UI), to be filled against the real screens.
- **Type/name consistency:** `compute_adherence(meals, category, classify=None)->{clean_days,logged_days,adherence}` (T2) used in T6; `should_nudge(adherence,logged_days,nudged_at)` (T2) used in T6; `evaluate(**kw)->result` (T3) used in T6; store fns (T5) used in T6; `signal_engine._load_between` (existing) reused in T6; `ExperimentResponse` fields (T4) match `_to_response` (T6) and the Dart `Experiment` (T8); conversation `proposed_experiment` (T7) matches `ProposedExperiment` + the Dart `TrendsTurn.proposedExperiment` (T8).
- **Risk:** the create-conflict path relies on the partial-unique index raising — T6 maps any insert exception to 409; acceptable for v1 (the only expected failure there is the uniqueness violation).
