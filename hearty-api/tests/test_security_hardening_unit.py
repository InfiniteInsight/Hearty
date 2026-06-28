"""Security-hardening regression tests (audit 2026-06-26).

M1 — /auth/on-login must fail-closed (reject when SUPABASE_WEBHOOK_SECRET unset)
     and use a constant-time comparison.
M2 — CORS origin parsing must NOT fall back to "*" when ALLOWED_ORIGINS is blank.
"""

import types

from fastapi.testclient import TestClient

from app.main import app, _parse_origins
from app.routers import auth_hooks


client = TestClient(app)


class _FakeTable:
    def upsert(self, *a, **k):
        return self

    def execute(self):
        return types.SimpleNamespace(data=[])


class _FakeSupabase:
    def __init__(self):
        self.tables = []

    def table(self, name):
        self.tables.append(name)
        return _FakeTable()


# ---- M1: /auth/on-login fail-closed ----

def test_on_login_rejects_when_secret_unset(monkeypatch):
    monkeypatch.delenv("SUPABASE_WEBHOOK_SECRET", raising=False)
    r = client.post("/auth/on-login", json={"user": {"id": "u1"}})
    assert r.status_code == 401


def test_on_login_rejects_when_secret_blank(monkeypatch):
    monkeypatch.setenv("SUPABASE_WEBHOOK_SECRET", "")
    r = client.post("/auth/on-login", json={"user": {"id": "u1"}})
    assert r.status_code == 401


def test_on_login_rejects_wrong_secret(monkeypatch):
    monkeypatch.setenv("SUPABASE_WEBHOOK_SECRET", "correct-secret")
    r = client.post("/auth/on-login", json={"user": {"id": "u1"}},
                    headers={"Authorization": "Bearer wrong-secret"})
    assert r.status_code == 401


def test_on_login_rejects_missing_header(monkeypatch):
    monkeypatch.setenv("SUPABASE_WEBHOOK_SECRET", "correct-secret")
    r = client.post("/auth/on-login", json={"user": {"id": "u1"}})
    assert r.status_code == 401


def test_on_login_accepts_correct_secret(monkeypatch):
    monkeypatch.setenv("SUPABASE_WEBHOOK_SECRET", "correct-secret")
    fake = _FakeSupabase()
    monkeypatch.setattr(auth_hooks, "supabase", fake)
    r = client.post("/auth/on-login", json={"user": {"id": "u1"}},
                    headers={"Authorization": "Bearer correct-secret"})
    assert r.status_code == 200
    assert r.json() == {"ok": True}
    assert fake.tables == ["health_profile", "notification_preferences"]


def test_on_login_authed_but_missing_user_id(monkeypatch):
    monkeypatch.setenv("SUPABASE_WEBHOOK_SECRET", "correct-secret")
    monkeypatch.setattr(auth_hooks, "supabase", _FakeSupabase())
    r = client.post("/auth/on-login", json={"record": {}},
                    headers={"Authorization": "Bearer correct-secret"})
    assert r.status_code == 400


def test_on_login_uses_constant_time_compare(monkeypatch):
    """Guard against regressing to a plain `!=` comparison."""
    import inspect
    src = inspect.getsource(auth_hooks.on_login)
    assert "compare_digest" in src
    assert "!= f\"Bearer" not in src


# ---- M2: CORS fail-closed ----

def test_parse_origins_blank_is_empty():
    assert _parse_origins("") == []


def test_parse_origins_whitespace_is_empty():
    assert _parse_origins("  ,  , ") == []


def test_parse_origins_splits_and_strips():
    assert _parse_origins("https://a.com, https://b.com ") == [
        "https://a.com", "https://b.com"]


def test_empty_allowlist_denies_cross_origin():
    """An empty allow-list must yield NO access-control-allow-origin header
    (deny all cross-origin), proving the fail-closed default at the middleware."""
    from fastapi import FastAPI
    from fastapi.middleware.cors import CORSMiddleware

    sub = FastAPI()
    sub.add_middleware(CORSMiddleware, allow_origins=_parse_origins(""),
                       allow_methods=["*"], allow_headers=["*"])

    @sub.get("/x")
    def _x():
        return {"ok": True}

    r = TestClient(sub).get("/x", headers={"Origin": "https://evil.example"})
    assert r.status_code == 200
    assert "access-control-allow-origin" not in {k.lower() for k in r.headers}
