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
