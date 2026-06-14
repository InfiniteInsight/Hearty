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


# Backfill skips years recorded in health_profile.yearly_backfilled_years (NOT by
# signal-row presence), so a zero-signal past year still freezes once.

class _Q:
    def __init__(self, data): self._d = data
    def select(self, *a, **k): return self
    def eq(self, *a, **k): return self
    def order(self, *a, **k): return self
    def limit(self, *a, **k): return self
    def maybe_single(self): return self
    def execute(self): return _Result(self._d)


def _backfill_supa(meal_year, marker, upserts):
    class _Profile(_Q):
        def upsert(self, row, **k): upserts.append(row); return self
    class _S:
        def table(self, name):
            if name == "meals":
                return _Q([{"logged_at": datetime(meal_year, 3, 1, tzinfo=timezone.utc).isoformat()}])
            if name == "health_profile":
                return _Profile({"yearly_backfilled_years": marker})
            return _Q([])
    return _S()


def test_ensure_yearly_backfill_fills_missing_past_and_recomputes_current(monkeypatch):
    calls, upserts = [], []
    monkeypatch.setattr(se, "analyze_year", lambda u, y: calls.append(y) or 0)
    monkeypatch.setattr(se, "supabase", _backfill_supa(2023, [2023], upserts))

    class _FixedDate(datetime):
        @classmethod
        def now(cls, tz=None): return datetime(2025, 7, 1, tzinfo=timezone.utc)
    monkeypatch.setattr(se, "datetime", _FixedDate)

    se.ensure_yearly_backfill("u1", recompute_current=True)
    # 2023 already in the marker → skipped; 2024 missing → computed; 2025 current → recomputed.
    assert calls == [2024, 2025]
    # The newly-frozen past year is recorded in the marker (2023 retained, 2024 added).
    assert upserts and upserts[0]["yearly_backfilled_years"] == [2023, 2024]


def test_ensure_yearly_backfill_skips_already_backfilled_zero_signal_year(monkeypatch):
    # A past year with no signal rows but recorded in the marker must NOT re-run.
    calls, upserts = [], []
    monkeypatch.setattr(se, "analyze_year", lambda u, y: calls.append(y) or 0)
    monkeypatch.setattr(se, "supabase", _backfill_supa(2023, [2023, 2024], upserts))

    class _FixedDate(datetime):
        @classmethod
        def now(cls, tz=None): return datetime(2025, 7, 1, tzinfo=timezone.utc)
    monkeypatch.setattr(se, "datetime", _FixedDate)

    se.ensure_yearly_backfill("u1", recompute_current=False)
    assert calls == []          # both past years already frozen, current skipped
    assert upserts == []        # nothing new → no marker write


def test_ensure_yearly_backfill_skips_current_when_not_recompute(monkeypatch):
    calls, upserts = [], []
    monkeypatch.setattr(se, "analyze_year", lambda u, y: calls.append(y) or 0)
    monkeypatch.setattr(se, "supabase", _backfill_supa(2024, [], upserts))

    class _FixedDate(datetime):
        @classmethod
        def now(cls, tz=None): return datetime(2025, 2, 1, tzinfo=timezone.utc)
    monkeypatch.setattr(se, "datetime", _FixedDate)

    se.ensure_yearly_backfill("u1", recompute_current=False)
    assert calls == [2024]
    assert upserts[0]["yearly_backfilled_years"] == [2024]
