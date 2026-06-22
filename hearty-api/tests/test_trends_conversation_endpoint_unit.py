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
        return _Table([])


def test_conversation_endpoint_returns_reply(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    monkeypatch.setattr(trends_module, "supabase", _Supa())
    monkeypatch.setattr(trends_module, "load_health_profile_context", lambda uid: "")
    monkeypatch.setattr(
        trends_module.trends_conversation, "generate_turn",
        lambda signals, history, health_context="": TrendsConversationResponse(
            reply="hi", is_closing=False),
    )
    client = TestClient(app)
    r = client.post("/api/trends/conversation", json={"history": []})
    assert r.status_code == 200
    assert r.json()["reply"] == "hi"
    app.dependency_overrides.clear()


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
