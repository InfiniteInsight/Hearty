import types
import pytest
from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient
from app import auth


def _app_with_admin_route():
    app = FastAPI()

    @app.get("/whoami")
    async def whoami(admin=Depends(auth.get_current_admin)):
        return admin

    return app


def _fake_supabase(user):
    fake = types.SimpleNamespace()
    fake.auth = types.SimpleNamespace(
        get_user=lambda token: types.SimpleNamespace(user=user)
    )
    return fake


def test_admin_allowed(monkeypatch):
    user = types.SimpleNamespace(id="u1", email="e", app_metadata={"role": "admin"})
    monkeypatch.setattr(auth, "supabase", _fake_supabase(user))
    client = TestClient(_app_with_admin_route())
    r = client.get("/whoami", headers={"Authorization": "Bearer t"})
    assert r.status_code == 200 and r.json()["id"] == "u1"


def test_non_admin_forbidden(monkeypatch):
    user = types.SimpleNamespace(id="u2", email="e", app_metadata={})
    monkeypatch.setattr(auth, "supabase", _fake_supabase(user))
    client = TestClient(_app_with_admin_route())
    r = client.get("/whoami", headers={"Authorization": "Bearer t"})
    assert r.status_code == 403


def test_missing_token_rejected():
    client = TestClient(_app_with_admin_route())
    assert client.get("/whoami").status_code in (401, 403)
