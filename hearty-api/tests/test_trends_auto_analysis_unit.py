"""Auto-analysis: signal reads recompute when new data exists.

`ensure_fresh_signals` runs the engine only when there's new data, swallows
errors, and is invoked by GET /api/trends and the conversation's first turn.
"""
from fastapi.testclient import TestClient

from app.main import app
from app.auth import get_current_user
from app.routers import trends as trends_module
from app.models.schemas import TrendsConversationResponse


class _Result:
    def __init__(self, data, count=0):
        self.data = data
        self.count = count


class _Q:
    """Permissive supabase query fake: any chained call returns self; execute
    yields an empty result so endpoint bodies run without real I/O."""
    def __getattr__(self, _name):
        return lambda *a, **k: self

    def execute(self):
        return _Result([])


class _Supa:
    def table(self, _name):
        return _Q()


# ── ensure_fresh_signals unit behavior ──────────────────────────────────────

def test_ensure_fresh_runs_analysis_when_new_data(monkeypatch):
    calls = []
    monkeypatch.setattr(trends_module, "_analysis_status", lambda uid: (None, True))
    monkeypatch.setattr(trends_module.signal_engine, "run_analysis",
                        lambda uid, period_days=90: calls.append((uid, period_days)))
    assert trends_module.ensure_fresh_signals("u1") is True
    assert calls == [("u1", 90)]


def test_ensure_fresh_skips_when_no_new_data(monkeypatch):
    calls = []
    monkeypatch.setattr(trends_module, "_analysis_status",
                        lambda uid: ("2026-06-01T00:00:00+00:00", False))
    monkeypatch.setattr(trends_module.signal_engine, "run_analysis",
                        lambda uid, period_days=90: calls.append(uid))
    assert trends_module.ensure_fresh_signals("u1") is False
    assert calls == []


def test_ensure_fresh_swallows_errors(monkeypatch):
    def _boom(uid):
        raise RuntimeError("db down")
    monkeypatch.setattr(trends_module, "_analysis_status", _boom)
    # Must not raise — a refresh failure cannot break the read.
    assert trends_module.ensure_fresh_signals("u1") is False


# ── read endpoints invoke ensure_fresh_signals ──────────────────────────────

def test_get_trends_auto_refreshes(monkeypatch):
    called = []
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    monkeypatch.setattr(trends_module, "supabase", _Supa())
    monkeypatch.setattr(trends_module, "ensure_fresh_signals",
                        lambda uid: called.append(uid))
    client = TestClient(app)
    r = client.get("/api/trends")
    assert r.status_code == 200
    assert called == ["u1"]
    app.dependency_overrides.clear()


def test_conversation_first_turn_refreshes_but_later_turns_dont(monkeypatch):
    called = []
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    monkeypatch.setattr(trends_module, "ensure_fresh_signals",
                        lambda uid: called.append(uid))
    monkeypatch.setattr(trends_module.signal_presenter,
                        "load_presented_signals", lambda s, u: [])
    monkeypatch.setattr(trends_module, "load_health_profile_context", lambda uid: "")
    monkeypatch.setattr(trends_module.trends_conversation, "generate_turn",
                        lambda signals, history, health_context="", research_context="", style_overlay="":
                            TrendsConversationResponse(reply="hi"))
    monkeypatch.setattr(trends_module, "_research_for", lambda query, user_id: "")
    monkeypatch.setattr(trends_module.prompt_overlays, "get_overlay", lambda surface: "")
    client = TestClient(app)

    r1 = client.post("/api/trends/conversation", json={"history": []})
    assert r1.status_code == 200 and called == ["u1"]

    called.clear()
    r2 = client.post("/api/trends/conversation",
                     json={"history": [{"role": "user", "content": "hi"}]})
    assert r2.status_code == 200 and called == []
    app.dependency_overrides.clear()
