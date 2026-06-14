# Multi-Year Trends — Persistence & Year-over-Year Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Evaluate all of a user's history bucketed by calendar year, freeze past years, and surface which food→outcome patterns *recur across years* (persistence = confidence) as badges on the Trends screen, with the live lens widened from 90 to 365 days.

**Architecture:** Approach B — `food_signals` stays the live set (window 90→365); a new immutable `food_signals_yearly` table holds one frozen signal set per calendar year; a pure `signal_persistence` layer annotates live signals with `years_seen`/`recurring`/`is_new`/`strength_by_year`. Past years compute once; only the current year + the rolling-12mo live window recompute (debounced). Spec: `docs/superpowers/specs/2026-06-14-multi-year-trends-design.md`.

**Tech Stack:** FastAPI + Supabase (python client, service key) + litellm; Flutter/Riverpod/Dio; Supabase SQL migrations. Backend test runner: `cd hearty-api && set -a && . ../.env && set +a && .venv/bin/python -m pytest <file> -v`. Migrations apply via `scripts/db-push.sh`.

---

## File Structure

**Backend:**
- `supabase/migrations/20260614000000_food_signals_yearly.sql` — new frozen-history table.
- `hearty-api/app/services/signal_engine.py` — **modify**: extract `_load_between` + `_compute_signals`; widen `run_analysis` default to 365; add `analyze_year` + `ensure_yearly_backfill`.
- `hearty-api/app/services/signal_persistence.py` — **new**: pure `compute_persistence`.
- `hearty-api/app/models/schemas.py` — **modify**: add persistence fields to `FoodSignal`.
- `hearty-api/app/routers/trends.py` — **modify**: debounce in `ensure_fresh_signals`; `get_signals` runs backfill + annotates; manual analyze also backfills; counts 90→365.

**Backend tests (new):**
- `hearty-api/tests/test_signal_persistence_unit.py`
- `hearty-api/tests/test_signal_engine_yearly_unit.py`
- `hearty-api/tests/test_trends_persistence_endpoint_unit.py`

**Flutter:**
- `hearty_app/lib/core/api/models/trends_data.dart` — **modify**: persistence fields + parsing on the Dart `FoodSignal`.
- `hearty_app/lib/features/trends/screens/trends_screen.dart` — **modify**: recurring/new badges on the signal card.
- `hearty_app/test/features/trends/...` — badge widget test + model parse test.

---

## Task 1: Migration — `food_signals_yearly` table

**Files:**
- Create: `supabase/migrations/20260614000000_food_signals_yearly.sql`

- [ ] **Step 1: Write the migration**

```sql
-- Multi-year trends: one immutable signal set per calendar year. Past years are
-- computed once and frozen; the current year is recomputed as data lands. The
-- pure signal_persistence layer joins these against the live food_signals to
-- annotate recurrence. Identity (category, outcome_type, outcome_name) matches
-- signal_feedback so verdicts and persistence line up.
CREATE TABLE food_signals_yearly (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID REFERENCES auth.users NOT NULL,
  year           INTEGER NOT NULL,
  category       TEXT NOT NULL,
  outcome_type   TEXT NOT NULL CHECK (outcome_type IN ('symptom', 'wellbeing')),
  outcome_name   TEXT NOT NULL,
  direction      TEXT NOT NULL,
  unified_score  NUMERIC,
  relative_risk  NUMERIC,
  evidence_count INTEGER NOT NULL DEFAULT 0,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, year, category, outcome_type, outcome_name)
);

CREATE INDEX idx_food_signals_yearly_lookup ON food_signals_yearly (user_id, year);

ALTER TABLE food_signals_yearly ENABLE ROW LEVEL SECURITY;

CREATE POLICY "food_signals_yearly_owner_only" ON food_signals_yearly
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
```

- [ ] **Step 2: Apply it**

Run: `scripts/db-push.sh --dry-run` (confirm only this migration is pending), then `scripts/db-push.sh --yes`.
Expected: applies cleanly; `Finished supabase db push.`

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260614000000_food_signals_yearly.sql
git commit -m "feat(trends): add food_signals_yearly frozen-history table

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Refactor `signal_engine` — extract reusable load + compute; widen live window

No behavior change for the live path except the window (90→365). Extract two seams the yearly code reuses. This task is refactor-under-test: the existing engine has no direct unit test, so verify by import + the full suite staying green.

**Files:**
- Modify: `hearty-api/app/services/signal_engine.py`

- [ ] **Step 1: Extract `_load_between` and delegate `load_data` to it**

Replace the current `load_data` (lines ~38–71) with:

```python
def _load_between(user_id: str, start_iso: str, end_iso: str) -> tuple[list, list, list]:
    """Return (meals, symptoms, wellbeing_snapshots) logged within [start, end]."""
    meals = (
        supabase.table("meals")
        .select("id, foods, logged_at, meal_type")
        .eq("user_id", user_id)
        .gte("logged_at", start_iso)
        .lte("logged_at", end_iso)
        .execute()
    ).data or []

    symptoms = (
        supabase.table("symptoms")
        .select("id, meal_id, logged_at, symptom_type, severity, onset_minutes")
        .eq("user_id", user_id)
        .gte("logged_at", start_iso)
        .lte("logged_at", end_iso)
        .execute()
    ).data or []

    wellbeing = (
        supabase.table("wellbeing_snapshots")
        .select("id, logged_at, period, energy_level, mood, stress_level, sleep_quality, sleep_hours")
        .eq("user_id", user_id)
        .gte("logged_at", start_iso)
        .lte("logged_at", end_iso)
        .execute()
    ).data or []

    return meals, symptoms, wellbeing


def load_data(user_id: str, period_days: int) -> tuple[list, list, list]:
    """Return (meals, symptoms, wellbeing_snapshots) for the trailing window."""
    now = datetime.now(timezone.utc)
    start = (now - timedelta(days=period_days)).isoformat()
    return _load_between(user_id, start, now.isoformat())
```

- [ ] **Step 2: Extract `_compute_signals` from `run_analysis`**

Add this function (it is the classify→exposure→loop body, with NO DB writes), placed just above `run_analysis`:

```python
def _compute_signals(user_id: str, meals: list, symptoms: list,
                     wellbeing: list) -> list[dict]:
    """Pure-ish: classify foods, build exposure, compute per-category signals.
    Returns signal rows (with user_id, unified_score, analyzed_at) ready to insert.
    No DB writes. Returns [] when there are no meals."""
    if not meals:
        return []

    all_food_names: list[str] = []
    for meal in meals:
        for food_item in (meal.get("foods") or []):
            name = (food_item.get("name") or "").strip().lower()
            if name:
                all_food_names.append(name)

    classification_cache: dict[str, list[str]] = {}
    category_map = classify_foods_cached(list(set(all_food_names)), classification_cache)

    for meal in meals:
        for food_item in (meal.get("foods") or []):
            if food_item.get("name"):
                food_item["name"] = food_item["name"].strip().lower()

    exposure = build_category_exposure(meals, category_map)
    all_meal_ids = {m["id"] for m in meals}
    all_signals: list[dict] = []

    for category, exposed_ids in exposure.items():
        unexposed_ids = all_meal_ids - exposed_ids
        symptom_sigs = compute_symptom_signals(
            category, exposed_ids, unexposed_ids, meals, symptoms
        )
        wellbeing_sigs = compute_wellbeing_signals(
            category, exposed_ids, unexposed_ids, meals, wellbeing
        )
        if not symptom_sigs and not wellbeing_sigs:
            continue
        unified = compute_unified_score(symptom_sigs, wellbeing_sigs)
        analyzed_at = datetime.now(timezone.utc).isoformat()
        for sig in symptom_sigs + wellbeing_sigs:
            sig["unified_score"] = unified
            sig["analyzed_at"] = analyzed_at
            sig["user_id"] = user_id
            all_signals.append(sig)

    return all_signals
```

- [ ] **Step 3: Rewrite `run_analysis` to use the seam + widen the default to 365**

Replace the body of `run_analysis` with:

```python
def run_analysis(user_id: str, period_days: int = 365) -> dict:
    """Full live analysis: load trailing window → compute → replace food_signals.

    Returns a summary dict with counts and duration.
    """
    t0 = time.time()
    meals, symptoms, wellbeing = load_data(user_id, period_days)
    all_signals = _compute_signals(user_id, meals, symptoms, wellbeing)

    supabase.table("food_signals").delete().eq("user_id", user_id).execute()
    if all_signals:
        supabase.table("food_signals").insert(all_signals).execute()

    _update_last_analyzed(user_id)
    return {
        "categories_analysed": len({s["category"] for s in all_signals}),
        "signals_found": len(all_signals),
        "duration_seconds": round(time.time() - t0, 2),
    }
```

- [ ] **Step 4: Verify import + no regressions**

Run: `cd hearty-api && set -a && . ../.env && set +a && .venv/bin/python -c "from app.services import signal_engine; print('ok', signal_engine.run_analysis.__defaults__)"`
Expected: `ok (365,)`

Run: `cd hearty-api && set -a && . ../.env && set +a && .venv/bin/python -m pytest --ignore=tests/test_api.py -q`
Expected: all pass (no behavioral test covers the engine directly; this confirms nothing imports-broke).

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/signal_engine.py
git commit -m "refactor(trends): extract _load_between + _compute_signals; live window 90->365

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: `signal_engine` — `analyze_year` + `ensure_yearly_backfill`

**Files:**
- Modify: `hearty-api/app/services/signal_engine.py`
- Test: `hearty-api/tests/test_signal_engine_yearly_unit.py`

- [ ] **Step 1: Write the failing test**

```python
from datetime import datetime, timezone
from app.services import signal_engine as se


class _Result:
    def __init__(self, data): self.data = data


def _meal(year):
    return {"logged_at": datetime(year, 6, 1, tzinfo=timezone.utc).isoformat()}


def test_analyze_year_writes_year_scoped_rows(monkeypatch):
    captured = {}
    # _load_between/_compute_signals stubbed: one signal row out of compute.
    monkeypatch.setattr(se, "_load_between", lambda u, s, e: ([{"id": "m"}], [], []))
    monkeypatch.setattr(se, "_compute_signals", lambda u, m, s, w: [{
        "user_id": u, "category": "dairy", "outcome_type": "symptom",
        "outcome_name": "bloating", "direction": "harmful",
        "unified_score": 0.7, "relative_risk": 2.0, "evidence_count": 8,
        "analyzed_at": "x",
    }])

    class _T:
        def __init__(self, name): self.name = name
        def delete(self): captured.setdefault("deleted", []).append(self.name); return self
        def insert(self, rows): captured["inserted"] = (self.name, rows); return self
        def eq(self, *a, **k): return self
        def execute(self): return _Result([])
    monkeypatch.setattr(se, "supabase", type("S", (), {"table": lambda self, n: _T(n)})())

    n = se.analyze_year("u1", 2025)
    assert n == 1
    table, rows = captured["inserted"]
    assert table == "food_signals_yearly"
    assert rows[0]["year"] == 2025
    assert rows[0]["category"] == "dairy"
    # slim row: only the yearly columns, no analyzed_at/unified leakage beyond schema
    assert set(rows[0].keys()) == {
        "user_id", "year", "category", "outcome_type", "outcome_name",
        "direction", "unified_score", "relative_risk", "evidence_count"}


def test_ensure_yearly_backfill_fills_missing_past_and_recomputes_current(monkeypatch):
    calls = []
    monkeypatch.setattr(se, "analyze_year", lambda u, y: calls.append(y) or 0)

    # earliest meal in 2023; existing yearly rows for 2023 only; "now" = 2025.
    class _Q:
        def __init__(self, data): self._d = data
        def select(self, *a, **k): return self
        def eq(self, *a, **k): return self
        def order(self, *a, **k): return self
        def limit(self, *a, **k): return self
        def execute(self): return _Result(self._d)
    class _S:
        def table(self, name):
            if name == "meals":
                return _Q([{"logged_at": datetime(2023, 3, 1, tzinfo=timezone.utc).isoformat()}])
            return _Q([{"year": 2023}])  # food_signals_yearly existing
    monkeypatch.setattr(se, "supabase", _S())

    class _FixedDate(datetime):
        @classmethod
        def now(cls, tz=None): return datetime(2025, 7, 1, tzinfo=timezone.utc)
    monkeypatch.setattr(se, "datetime", _FixedDate)

    se.ensure_yearly_backfill("u1", recompute_current=True)
    # 2023 already frozen → skipped; 2024 missing → computed; 2025 current → recomputed.
    assert calls == [2024, 2025]


def test_ensure_yearly_backfill_skips_current_when_not_recompute(monkeypatch):
    calls = []
    monkeypatch.setattr(se, "analyze_year", lambda u, y: calls.append(y) or 0)
    class _Q:
        def __init__(self, data): self._d = data
        def select(self, *a, **k): return self
        def eq(self, *a, **k): return self
        def order(self, *a, **k): return self
        def limit(self, *a, **k): return self
        def execute(self): return _Result(self._d)
    class _S:
        def table(self, name):
            if name == "meals":
                return _Q([{"logged_at": datetime(2024, 1, 1, tzinfo=timezone.utc).isoformat()}])
            return _Q([])  # nothing frozen yet
    monkeypatch.setattr(se, "supabase", _S())
    class _FixedDate(datetime):
        @classmethod
        def now(cls, tz=None): return datetime(2025, 2, 1, tzinfo=timezone.utc)
    monkeypatch.setattr(se, "datetime", _FixedDate)

    se.ensure_yearly_backfill("u1", recompute_current=False)
    # 2024 missing past → computed; 2025 current → skipped (recompute_current False).
    assert calls == [2024]
```

- [ ] **Step 2: Run to confirm it fails**

Run: `cd hearty-api && set -a && . ../.env && set +a && .venv/bin/python -m pytest tests/test_signal_engine_yearly_unit.py -v`
Expected: FAIL — `analyze_year` / `ensure_yearly_backfill` not defined.

- [ ] **Step 3: Implement both functions** (add after `run_analysis`)

```python
def analyze_year(user_id: str, year: int) -> int:
    """Compute one calendar year's signals and replace that year's frozen rows.
    Returns the number of signal rows written."""
    start = datetime(year, 1, 1, tzinfo=timezone.utc).isoformat()
    end = datetime(year, 12, 31, 23, 59, 59, tzinfo=timezone.utc).isoformat()
    meals, symptoms, wellbeing = _load_between(user_id, start, end)
    signals = _compute_signals(user_id, meals, symptoms, wellbeing)

    rows = [{
        "user_id": user_id,
        "year": year,
        "category": s["category"],
        "outcome_type": s["outcome_type"],
        "outcome_name": s["outcome_name"],
        "direction": s["direction"],
        "unified_score": s.get("unified_score"),
        "relative_risk": s.get("relative_risk"),
        "evidence_count": s.get("evidence_count") or 0,
    } for s in signals]

    supabase.table("food_signals_yearly").delete() \
        .eq("user_id", user_id).eq("year", year).execute()
    if rows:
        supabase.table("food_signals_yearly").insert(rows).execute()
    return len(rows)


def ensure_yearly_backfill(user_id: str, recompute_current: bool = True) -> None:
    """Compute any missing PAST calendar years once (frozen), and recompute the
    CURRENT year when recompute_current is True. Cheap when already backfilled:
    past years are skipped if a row already exists for them."""
    current_year = datetime.now(timezone.utc).year

    earliest = (
        supabase.table("meals")
        .select("logged_at")
        .eq("user_id", user_id)
        .order("logged_at")
        .limit(1)
        .execute()
    ).data
    if not earliest:
        return
    first_dt = _parse_dt(earliest[0]["logged_at"])
    if first_dt is None:
        return
    first_year = first_dt.year

    existing_years = {
        r["year"] for r in (
            supabase.table("food_signals_yearly")
            .select("year")
            .eq("user_id", user_id)
            .execute()
        ).data or []
    }

    for year in range(first_year, current_year):  # past years only
        if year not in existing_years:
            analyze_year(user_id, year)

    if recompute_current:
        analyze_year(user_id, current_year)
```

- [ ] **Step 4: Run to confirm pass**

Run: `cd hearty-api && set -a && . ../.env && set +a && .venv/bin/python -m pytest tests/test_signal_engine_yearly_unit.py -v`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/signal_engine.py hearty-api/tests/test_signal_engine_yearly_unit.py
git commit -m "feat(trends): per-year analysis + freeze-past-years backfill

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: `signal_persistence` — pure overlay (TDD)

**Files:**
- Create: `hearty-api/app/services/signal_persistence.py`
- Test: `hearty-api/tests/test_signal_persistence_unit.py`

- [ ] **Step 1: Write the failing test**

```python
from app.services.signal_persistence import compute_persistence


def _row(cat, year, score=0.7, outcome="bloating"):
    return {"category": cat, "year": year, "outcome_type": "symptom",
            "outcome_name": outcome, "unified_score": score}


def test_recurring_across_years():
    rows = [_row("dairy", 2024), _row("dairy", 2025, 0.8)]
    out = compute_persistence({"dairy"}, rows, current_year=2026)
    p = out["dairy"]
    assert p["years_seen"] == [2024, 2025]
    assert p["recurring"] is True
    assert p["is_new"] is False
    assert p["strength_by_year"] == {"2024": 0.7, "2025": 0.8}


def test_new_this_year_only():
    rows = [_row("gluten", 2026)]
    out = compute_persistence({"gluten"}, rows, current_year=2026)
    p = out["gluten"]
    assert p["years_seen"] == [2026]
    assert p["recurring"] is False
    assert p["is_new"] is True


def test_live_only_category_with_no_yearly_rows_is_new():
    out = compute_persistence({"soy"}, [], current_year=2026)
    p = out["soy"]
    assert p["years_seen"] == []
    assert p["recurring"] is False
    assert p["is_new"] is True


def test_only_live_categories_are_returned():
    rows = [_row("dairy", 2024), _row("ginger", 2024)]
    out = compute_persistence({"dairy"}, rows, current_year=2026)
    assert set(out.keys()) == {"dairy"}


def test_strength_takes_max_when_year_has_multiple_outcomes():
    rows = [_row("dairy", 2025, 0.5, outcome="bloating"),
            _row("dairy", 2025, 0.9, outcome="cramps")]
    out = compute_persistence({"dairy"}, rows, current_year=2026)
    assert out["dairy"]["strength_by_year"] == {"2025": 0.9}
    assert out["dairy"]["years_seen"] == [2025]
```

- [ ] **Step 2: Run to confirm it fails**

Run: `cd hearty-api && set -a && . ../.env && set +a && .venv/bin/python -m pytest tests/test_signal_persistence_unit.py -v`
Expected: FAIL — module missing.

- [ ] **Step 3: Implement**

```python
"""Signal persistence: annotate live food signals with cross-year recurrence.

Pure logic — given the set of live category slugs and the frozen per-year rows
from food_signals_yearly, derive per-category recurrence/new flags. Keyed at the
category level (matching unified_score's granularity)."""


def compute_persistence(
    live_categories: set[str],
    yearly_rows: list[dict],
    current_year: int,
) -> dict[str, dict]:
    """Return {category: {years_seen, recurring, is_new, strength_by_year}} for
    every category in live_categories.

    - years_seen: sorted years that had a stored (real) signal for the category.
    - recurring: appeared in >= 2 calendar years.
    - is_new: no appearance in any year before current_year.
    - strength_by_year: {str(year): max unified_score that year} (JSON-friendly keys).
    """
    by_cat: dict[str, dict] = {}
    for r in yearly_rows:
        cat = r["category"]
        year = int(r["year"])
        score = float(r["unified_score"]) if r.get("unified_score") is not None else 0.0
        d = by_cat.setdefault(cat, {"years": set(), "strength": {}})
        d["years"].add(year)
        d["strength"][year] = max(d["strength"].get(year, 0.0), score)

    out: dict[str, dict] = {}
    for cat in live_categories:
        d = by_cat.get(cat)
        years = sorted(d["years"]) if d else []
        is_new = not any(y < current_year for y in years)  # True also when years == []
        out[cat] = {
            "years_seen": years,
            "recurring": len(years) >= 2,
            "is_new": is_new,
            "strength_by_year": {str(y): d["strength"][y] for y in years} if d else {},
        }
    return out
```

- [ ] **Step 4: Run to confirm pass**

Run: `cd hearty-api && set -a && . ../.env && set +a && .venv/bin/python -m pytest tests/test_signal_persistence_unit.py -v`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/signal_persistence.py hearty-api/tests/test_signal_persistence_unit.py
git commit -m "feat(trends): signal_persistence — cross-year recurrence overlay

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Schemas — persistence fields on `FoodSignal`

**Files:**
- Modify: `hearty-api/app/models/schemas.py`

- [ ] **Step 1: Add `Dict` to the typing import**

At the top of `schemas.py`, change `from typing import Optional, List, Literal` to:

```python
from typing import Optional, List, Literal, Dict
```

- [ ] **Step 2: Add fields to `FoodSignal`** (the class at ~line 136)

Replace the `FoodSignal` class with:

```python
class FoodSignal(BaseModel):
    category: str
    unified_score: float
    channels: List[SignalChannel]
    convergent: bool
    # Multi-year persistence (default empty so older clients/responses are valid).
    years_seen: List[int] = Field(default_factory=list)
    recurring: bool = False
    is_new: bool = False
    strength_by_year: Dict[str, float] = Field(default_factory=dict)
```

- [ ] **Step 3: Verify import**

Run: `cd hearty-api && set -a && . ../.env && set +a && .venv/bin/python -c "from app.models.schemas import FoodSignal; print(sorted(FoodSignal.model_fields.keys()))"`
Expected: includes `is_new`, `recurring`, `strength_by_year`, `years_seen`.

- [ ] **Step 4: Commit**

```bash
git add hearty-api/app/models/schemas.py
git commit -m "feat(trends): FoodSignal carries persistence fields

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Trends router — debounce, backfill, annotate

**Files:**
- Modify: `hearty-api/app/routers/trends.py`
- Test: `hearty-api/tests/test_trends_persistence_endpoint_unit.py`

Imports already present: `signal_engine`, `signal_presenter`, `FoodSignal`. Add `signal_persistence` to the `from app.services import (...)` block.

- [ ] **Step 1: Add a debounce to `ensure_fresh_signals`**

Near the other config constants (after `CHECKIN_EXPIRY_HOURS`-style lines, top of file), add:

```python
TRENDS_MIN_RECOMPUTE_MINUTES = float(os.environ.get("TRENDS_MIN_RECOMPUTE_MINUTES", "10"))
```

Replace the existing `ensure_fresh_signals` body with:

```python
def ensure_fresh_signals(user_id: str) -> bool:
    """Auto-run the live analysis when new data exists AND the last run is older
    than the debounce window. Returns True if an analysis was run. Best-effort —
    failures never break the read."""
    try:
        last_analyzed_at, has_new_data = _analysis_status(user_id)
        if not has_new_data:
            return False
        if last_analyzed_at:
            last_dt = datetime.fromisoformat(last_analyzed_at.replace("Z", "+00:00"))
            if last_dt.tzinfo is None:
                last_dt = last_dt.replace(tzinfo=timezone.utc)
            age = datetime.now(timezone.utc) - last_dt
            if age < timedelta(minutes=TRENDS_MIN_RECOMPUTE_MINUTES):
                return False  # debounced — recomputed too recently
        signal_engine.run_analysis(user_id)
        return True
    except Exception as e:  # pragma: no cover - defensive
        logger.error("ensure_fresh_signals failed: %s", e, exc_info=True)
        return False
```

- [ ] **Step 2: Wire backfill + annotation into `get_signals`**

At the top of `get_signals`, replace the existing single `ensure_fresh_signals(user_id)` call with:

```python
    did_refresh = ensure_fresh_signals(user_id)
    try:
        signal_engine.ensure_yearly_backfill(user_id, recompute_current=did_refresh)
    except Exception as e:  # pragma: no cover - defensive
        logger.error("ensure_yearly_backfill failed: %s", e, exc_info=True)
```

Then, after the `signals.sort(key=lambda s: s.unified_score, reverse=True)` line and BEFORE the `profile = ...` block, add the persistence annotation:

```python
    # Annotate each signal with cross-year recurrence.
    try:
        yearly_rows = (
            supabase.table("food_signals_yearly")
            .select("category, year, outcome_type, outcome_name, unified_score")
            .eq("user_id", user_id)
            .execute()
        ).data or []
        persistence = signal_persistence.compute_persistence(
            {s.category for s in signals}, yearly_rows,
            current_year=datetime.now(timezone.utc).year,
        )
        signals = [
            s.model_copy(update=persistence.get(s.category, {})) for s in signals
        ]
    except Exception as e:  # pragma: no cover - defensive
        logger.error("persistence annotation failed: %s", e, exc_info=True)
```

> `model_copy(update=...)` applies the `years_seen/recurring/is_new/strength_by_year` dict onto the `FoodSignal`. When a category has no entry, the defaults (empty/false) stand.

- [ ] **Step 3: Make the manual analyze endpoint backfill too** + widen its context counts

In `trigger_analysis` (the `POST /api/trends/analyze` handler), after `result = signal_engine.run_analysis(user_id, period_days=90)` change the period and add a forced backfill:

```python
    result = signal_engine.run_analysis(user_id, period_days=365)
    try:
        signal_engine.ensure_yearly_backfill(user_id, recompute_current=True)
    except Exception as e:  # pragma: no cover - defensive
        logger.error("ensure_yearly_backfill (manual) failed: %s", e, exc_info=True)
```

(If `trigger_analysis` did not pass `period_days`, just add the backfill block after the existing `run_analysis(user_id)` call — `run_analysis` now defaults to 365.)

- [ ] **Step 4: Write the endpoint tests**

```python
from fastapi.testclient import TestClient
from app.main import app
from app.auth import get_current_user
from app.routers import trends as trends_module
from app.models.schemas import FoodSignal, SignalChannel


class _Result:
    def __init__(self, data, count=0):
        self.data = data
        self.count = count


class _Q:
    """Permissive supabase fake; food_signals_yearly returns a recurring dairy row."""
    def __init__(self, name):
        self.name = name
    def __getattr__(self, _n):
        return lambda *a, **k: self
    def execute(self):
        if self.name == "food_signals_yearly":
            return _Result([
                {"category": "dairy", "year": 2024, "outcome_type": "symptom",
                 "outcome_name": "bloating", "unified_score": 0.7},
                {"category": "dairy", "year": 2025, "outcome_type": "symptom",
                 "outcome_name": "bloating", "unified_score": 0.8},
            ])
        return _Result([])


class _Supa:
    def table(self, name):
        return _Q(name)


def test_get_trends_annotates_recurrence(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    monkeypatch.setattr(trends_module, "supabase", _Supa())
    monkeypatch.setattr(trends_module, "ensure_fresh_signals", lambda uid: False)
    monkeypatch.setattr(trends_module.signal_engine, "ensure_yearly_backfill",
                        lambda uid, recompute_current=True: None)
    # Force the grouped live signals to include a dairy signal.
    monkeypatch.setattr(trends_module, "_build_signals_from_rows", None, raising=False)
    # Inject a live dairy FoodSignal by stubbing the rows the endpoint groups.
    # food_signals (live) read returns one dairy row:
    real_table = _Supa().table
    class _Supa2:
        def table(self, name):
            if name == "food_signals":
                q = _Q(name)
                q.execute = lambda: _Result([{  # noqa: E731
                    "category": "dairy", "outcome_type": "symptom",
                    "outcome_name": "bloating", "direction": "harmful",
                    "unified_score": 0.8, "relative_risk": 2.0, "evidence_count": 8,
                }])
                return q
            return _Q(name)
    monkeypatch.setattr(trends_module, "supabase", _Supa2())

    client = TestClient(app)
    r = client.get("/api/trends")
    assert r.status_code == 200
    sig = next(s for s in r.json()["signals"] if s["category"] == "dairy")
    assert sig["recurring"] is True
    assert sig["years_seen"] == [2024, 2025]
    assert sig["is_new"] is False
    app.dependency_overrides.clear()


def test_ensure_fresh_debounced_within_window(monkeypatch):
    from datetime import datetime, timezone
    ran = []
    recent = datetime.now(timezone.utc).isoformat()
    monkeypatch.setattr(trends_module, "_analysis_status", lambda uid: (recent, True))
    monkeypatch.setattr(trends_module.signal_engine, "run_analysis",
                        lambda uid, period_days=365: ran.append(uid))
    assert trends_module.ensure_fresh_signals("u1") is False
    assert ran == []  # debounced: recomputed too recently
```

> If `_build_signals_from_rows` monkeypatch line errors in your tree, delete it — it's a harmless guard. The essential stub is `_Supa2` returning a live dairy `food_signals` row so the endpoint produces a dairy `FoodSignal` to annotate.

- [ ] **Step 5: Run the endpoint tests + full suite**

Run: `cd hearty-api && set -a && . ../.env && set +a && .venv/bin/python -m pytest tests/test_trends_persistence_endpoint_unit.py -v`
Expected: PASS (2 tests).

Run: `cd hearty-api && set -a && . ../.env && set +a && .venv/bin/python -m pytest --ignore=tests/test_api.py -q`
Expected: all pass (incl. the existing `test_trends_auto_analysis_unit.py` — note its `test_ensure_fresh_runs_analysis_when_new_data` uses `_analysis_status` returning `(None, True)`, so the debounce branch is skipped and it still runs; if that test now asserts on timing, leave it green).

- [ ] **Step 6: Commit**

```bash
git add hearty-api/app/routers/trends.py hearty-api/tests/test_trends_persistence_endpoint_unit.py
git commit -m "feat(trends): debounce live recompute; backfill years; annotate recurrence on GET /api/trends

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Flutter — persistence fields on the Dart `FoodSignal`

**Files:**
- Modify: `hearty_app/lib/core/api/models/trends_data.dart`
- Test: `hearty_app/test/core/api/trends_data_persistence_test.dart` (create)

- [ ] **Step 1: Read the existing model**

Open `trends_data.dart`, find the `FoodSignal` class (fields `category`, `unifiedScore`, `channels`, `convergent`) and its `fromJson`. Mirror that exact style for the additions.

- [ ] **Step 2: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/api/models/trends_data.dart';

void main() {
  test('FoodSignal parses persistence fields', () {
    final s = FoodSignal.fromJson({
      'category': 'dairy',
      'unified_score': 0.8,
      'channels': <dynamic>[],
      'convergent': false,
      'years_seen': [2024, 2025],
      'recurring': true,
      'is_new': false,
      'strength_by_year': {'2024': 0.7, '2025': 0.8},
    });
    expect(s.yearsSeen, [2024, 2025]);
    expect(s.recurring, isTrue);
    expect(s.isNew, isFalse);
    expect(s.strengthByYear['2025'], 0.8);
  });

  test('FoodSignal persistence fields default when absent', () {
    final s = FoodSignal.fromJson({
      'category': 'soy',
      'unified_score': 0.4,
      'channels': <dynamic>[],
      'convergent': false,
    });
    expect(s.yearsSeen, isEmpty);
    expect(s.recurring, isFalse);
    expect(s.isNew, isFalse);
    expect(s.strengthByYear, isEmpty);
  });
}
```

- [ ] **Step 3: Run to confirm it fails**

Run: `cd hearty_app && /home/evan/tools/flutter/bin/flutter test test/core/api/trends_data_persistence_test.dart`
Expected: FAIL — `yearsSeen`/`recurring`/`isNew`/`strengthByYear` undefined.

- [ ] **Step 4: Add the fields + parsing**

In the `FoodSignal` class add final fields and constructor params:

```dart
  final List<int> yearsSeen;
  final bool recurring;
  final bool isNew;
  final Map<String, double> strengthByYear;
```

In the constructor parameter list add (defaulting so existing call sites compile):

```dart
    this.yearsSeen = const [],
    this.recurring = false,
    this.isNew = false,
    this.strengthByYear = const {},
```

In `fromJson`, add (defensive parsing matching the file's style):

```dart
      yearsSeen: ((json['years_seen'] as List<dynamic>?) ?? const [])
          .map((e) => (e as num).toInt())
          .toList(),
      recurring: (json['recurring'] as bool?) ?? false,
      isNew: (json['is_new'] as bool?) ?? false,
      strengthByYear: ((json['strength_by_year'] as Map<dynamic, dynamic>?) ??
              const {})
          .map((k, v) => MapEntry(k.toString(), (v as num).toDouble())),
```

- [ ] **Step 5: Run to confirm pass + analyze**

Run: `cd hearty_app && /home/evan/tools/flutter/bin/flutter test test/core/api/trends_data_persistence_test.dart`
Expected: PASS (2 tests).
Run: `cd hearty_app && /home/evan/tools/flutter/bin/flutter analyze lib/core/api/models/trends_data.dart`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add hearty_app/lib/core/api/models/trends_data.dart hearty_app/test/core/api/trends_data_persistence_test.dart
git commit -m "feat(trends): Dart FoodSignal carries persistence fields

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Flutter — recurring / new badges on the signal card

**Files:**
- Modify: `hearty_app/lib/features/trends/screens/trends_screen.dart`
- Test: `hearty_app/test/features/trends/signal_badge_test.dart` (create)

The signal card is `_SignalCard` (takes `signal`). Add a badge row under the category title.

- [ ] **Step 1: Write the failing widget test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hearty_app/core/api/models/trends_data.dart';
import 'package:hearty_app/features/trends/screens/trends_screen.dart';

FoodSignal _sig({List<int> years = const [], bool recurring = false, bool isNew = false}) =>
    FoodSignal.fromJson({
      'category': 'dairy', 'unified_score': 0.8,
      'channels': <dynamic>[], 'convergent': false,
      'years_seen': years, 'recurring': recurring, 'is_new': isNew,
    });

void main() {
  Widget host(FoodSignal s) =>
      MaterialApp(home: Scaffold(body: SignalCard(signal: s)));

  testWidgets('recurring shows a "Seen N years" badge', (t) async {
    await t.pumpWidget(host(_sig(years: [2024, 2025, 2026], recurring: true)));
    expect(find.byKey(const Key('signal-recurring-badge')), findsOneWidget);
    expect(find.textContaining('3 year'), findsOneWidget);
  });

  testWidgets('new this year shows a New chip', (t) async {
    await t.pumpWidget(host(_sig(years: [2026], isNew: true)));
    expect(find.byKey(const Key('signal-new-chip')), findsOneWidget);
  });

  testWidgets('single non-recurring year shows no badge', (t) async {
    await t.pumpWidget(host(_sig(years: [2025])));
    expect(find.byKey(const Key('signal-recurring-badge')), findsNothing);
    expect(find.byKey(const Key('signal-new-chip')), findsNothing);
  });
}
```

- [ ] **Step 2: Make `_SignalCard` testable**

Rename the private `_SignalCard` to a public `SignalCard` (class name only; update its single usage site in the file from `_SignalCard(` to `SignalCard(`). This lets the widget test construct it directly.

- [ ] **Step 3: Run to confirm it fails**

Run: `cd hearty_app && /home/evan/tools/flutter/bin/flutter test test/features/trends/signal_badge_test.dart`
Expected: FAIL — `SignalCard` undefined or no badges found.

- [ ] **Step 4: Render the badges**

In `SignalCard.build`, immediately after the category-title `Row(...)` (the one containing `_formatCategory(signal.category)` and the convergent tooltip), insert:

```dart
              if (signal.recurring || signal.isNew) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (signal.recurring)
                      Container(
                        key: const Key('signal-recurring-badge'),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Seen ${signal.yearsSeen.length} years'
                          '${signal.yearsSeen.isNotEmpty ? ' · ${signal.yearsSeen.map((y) => "'" "${y % 100}").join(' · ')}' : ''}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    if (signal.isNew)
                      Container(
                        key: const Key('signal-new-chip'),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text('New this year', style: TextStyle(fontSize: 11)),
                      ),
                  ],
                ),
              ],
```

> The recurring label renders e.g. `Seen 3 years · '24 · '25 · '26`. The test only asserts on "3 year" + the badge key, so exact punctuation is flexible.

- [ ] **Step 5: Run to confirm pass + analyze + full suite**

Run: `cd hearty_app && /home/evan/tools/flutter/bin/flutter test test/features/trends/signal_badge_test.dart`
Expected: PASS (3 tests).
Run: `cd hearty_app && /home/evan/tools/flutter/bin/flutter analyze lib/features/trends/`
Expected: clean.
Run: `cd hearty_app && /home/evan/tools/flutter/bin/flutter test`
Expected: full suite green (the `_SignalCard`→`SignalCard` rename touches only this file).

- [ ] **Step 6: Commit**

```bash
git add hearty_app/lib/features/trends/screens/trends_screen.dart hearty_app/test/features/trends/signal_badge_test.dart
git commit -m "feat(trends): recurring / new-this-year badges on signal cards

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Device verification (after the tasks)

Not unit-testable; run on device once merged:
- A user with >1 calendar year of data: open Trends → recurring categories show the "Seen N years" badge; a first-time category shows "New this year".
- First open backfills past years once (watch it's not recomputing them on every subsequent open — the debounce + freeze).
- "Analyse now" forces a full refresh + current-year recompute.

---

## Self-review

- **Spec coverage:** `food_signals_yearly` (T1) · live window 90→365 (T2) · date-bounded load + `_compute_signals` seam (T2) · `analyze_year` + freeze-past-years `ensure_yearly_backfill` (T3) · pure `compute_persistence` recurring/new/years_seen/strength_by_year + <2yr graceful (T4) · `FoodSignal` persistence fields (T5) · debounce + backfill wiring + `GET /api/trends` annotation + manual-analyze backfill (T6) · Dart model fields (T7) · Trends recurring/new badges (T8). Deferred-by-spec (conversation integration, Resolved list, sparkline, trajectory, off-request-path) are correctly absent.
- **Placeholders:** none — every code step has full code; modification steps cite exact anchors (`run_analysis`, `get_signals` sort line, `_SignalCard` rename).
- **Type/name consistency:** `_load_between(user_id, start_iso, end_iso)` and `_compute_signals(user_id, meals, symptoms, wellbeing)` defined T2, reused T3. `analyze_year(user_id, year)` / `ensure_yearly_backfill(user_id, recompute_current)` defined T3, called T6. `compute_persistence(live_categories, yearly_rows, current_year) -> {category: {years_seen, recurring, is_new, strength_by_year}}` defined T4, consumed T6 (keys match the `FoodSignal` fields from T5 so `model_copy(update=...)` applies cleanly). Dart `yearsSeen/recurring/isNew/strengthByYear` (T7) match the JSON keys emitted by T5/T6. `SignalCard` rename (T8) is the only public-surface change.
- **Risk note:** the engine has no pre-existing direct unit test; T2 is refactor-validated by import + the full suite. The endpoint test in T6 stubs the live `food_signals` row to force a dairy signal to annotate — keep that stub if the permissive-fake approach needs adjusting to the real `get_signals` query order.
