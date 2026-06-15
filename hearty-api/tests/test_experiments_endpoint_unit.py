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
