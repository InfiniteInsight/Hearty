from datetime import datetime, timezone
from app.services import signal_engine as se


class _Result:
    def __init__(self, data): self.data = data


def test_analyze_year_writes_year_scoped_rows(monkeypatch):
    captured = {}
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
    assert set(rows[0].keys()) == {
        "user_id", "year", "category", "outcome_type", "outcome_name",
        "direction", "unified_score", "relative_risk", "evidence_count"}


def test_ensure_yearly_backfill_fills_missing_past_and_recomputes_current(monkeypatch):
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
                return _Q([{"logged_at": datetime(2023, 3, 1, tzinfo=timezone.utc).isoformat()}])
            return _Q([{"year": 2023}])
    monkeypatch.setattr(se, "supabase", _S())

    class _FixedDate(datetime):
        @classmethod
        def now(cls, tz=None): return datetime(2025, 7, 1, tzinfo=timezone.utc)
    monkeypatch.setattr(se, "datetime", _FixedDate)

    se.ensure_yearly_backfill("u1", recompute_current=True)
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
            return _Q([])
    monkeypatch.setattr(se, "supabase", _S())
    class _FixedDate(datetime):
        @classmethod
        def now(cls, tz=None): return datetime(2025, 2, 1, tzinfo=timezone.utc)
    monkeypatch.setattr(se, "datetime", _FixedDate)

    se.ensure_yearly_backfill("u1", recompute_current=False)
    assert calls == [2024]
