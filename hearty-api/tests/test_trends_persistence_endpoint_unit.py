from datetime import datetime, timezone
from fastapi.testclient import TestClient
from app.main import app
from app.auth import get_current_user
from app.routers import trends as trends_module


class _Result:
    def __init__(self, data, count=0):
        self.data = data
        self.count = count


class _Q:
    def __init__(self, rows, count=0):
        self._rows = rows
        self._count = count
    def __getattr__(self, _n):
        return lambda *a, **k: self
    def execute(self):
        return _Result(self._rows, self._count)


class _Supa:
    def table(self, name):
        if name == "food_signals":
            return _Q([{
                "category": "dairy", "outcome_type": "symptom",
                "outcome_name": "bloating", "direction": "harmful",
                "unified_score": 0.8, "relative_risk": 2.0, "evidence_count": 8,
            }])
        if name == "food_signals_yearly":
            return _Q([
                {"category": "dairy", "year": 2024, "outcome_type": "symptom",
                 "outcome_name": "bloating", "unified_score": 0.7},
                {"category": "dairy", "year": 2025, "outcome_type": "symptom",
                 "outcome_name": "bloating", "unified_score": 0.8},
            ])
        return _Q([], 0)  # health_profile, counts, etc.


def test_get_trends_annotates_recurrence(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    monkeypatch.setattr(trends_module, "supabase", _Supa())
    monkeypatch.setattr(trends_module, "ensure_fresh_signals", lambda uid: False)
    monkeypatch.setattr(trends_module.signal_engine, "ensure_yearly_backfill",
                        lambda uid, recompute_current=True: None)
    client = TestClient(app)
    r = client.get("/api/trends")
    assert r.status_code == 200
    sig = next(s for s in r.json()["signals"] if s["category"] == "dairy")
    assert sig["recurring"] is True
    assert sig["years_seen"] == [2024, 2025]
    assert sig["is_new"] is False
    app.dependency_overrides.clear()


def test_ensure_fresh_debounced_within_window(monkeypatch):
    ran = []
    recent = datetime.now(timezone.utc).isoformat()
    monkeypatch.setattr(trends_module, "_analysis_status", lambda uid: (recent, True))
    monkeypatch.setattr(trends_module.signal_engine, "run_analysis",
                        lambda uid, period_days=365: ran.append(uid))
    assert trends_module.ensure_fresh_signals("u1") is False
    assert ran == []
