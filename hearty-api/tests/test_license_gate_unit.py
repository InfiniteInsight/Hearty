import types
from datetime import datetime, timezone, timedelta
from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient
from app import licensing
from app.auth import get_current_user


def _fake_supabase(rows):
    class _Q:
        def select(self, *a, **k): return self
        def eq(self, *a, **k): return self
        def limit(self, *a, **k): return self
        def execute(self): return types.SimpleNamespace(data=rows)
    fake = types.SimpleNamespace()
    fake.table = lambda name: _Q()
    return fake


def _client(rows):
    app = FastAPI()

    @app.get("/gated", dependencies=[Depends(licensing.require_active_license)])
    async def gated():
        return {"ok": True}

    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    return app, _fake_supabase(rows)


def test_active_allows(monkeypatch):
    app, fake = _client([{"status": "active", "expires_at": None}])
    monkeypatch.setattr(licensing, "supabase", fake)
    assert TestClient(app).get("/gated").status_code == 200


def test_missing_blocks(monkeypatch):
    app, fake = _client([])
    monkeypatch.setattr(licensing, "supabase", fake)
    r = TestClient(app).get("/gated")
    assert r.status_code == 403 and r.json()["detail"] == "no_active_license"


def test_revoked_blocks(monkeypatch):
    app, fake = _client([{"status": "revoked", "expires_at": None}])
    monkeypatch.setattr(licensing, "supabase", fake)
    assert TestClient(app).get("/gated").status_code == 403


def test_expired_blocks(monkeypatch):
    past = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
    app, fake = _client([{"status": "active", "expires_at": past}])
    monkeypatch.setattr(licensing, "supabase", fake)
    assert TestClient(app).get("/gated").status_code == 403


def test_state_helper(monkeypatch):
    fake = _fake_supabase([{"status": "active", "expires_at": None}])
    monkeypatch.setattr(licensing, "supabase", fake)
    assert licensing._license_state("u1")[0] == "active"
