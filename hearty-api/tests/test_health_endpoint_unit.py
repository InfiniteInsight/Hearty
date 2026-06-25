import types
from fastapi.testclient import TestClient
from app.main import app
from app.auth import get_current_admin
from app.routers import admin as adm


def _admin():
    app.dependency_overrides[get_current_admin] = lambda: {"id": "admin1", "email": "o"}


class _RowTbl:
    def __init__(self, row, raise_on_exec=False):
        self.row, self.raise_on_exec = row, raise_on_exec
    def select(self, *a, **k): return self
    def eq(self, *a, **k): return self
    def limit(self, *a, **k): return self
    def execute(self):
        if self.raise_on_exec: raise RuntimeError("supabase down")
        return types.SimpleNamespace(data=([self.row] if self.row else []))


def _fake(row=None, raise_on_exec=False):
    return types.SimpleNamespace(table=lambda n: _RowTbl(row, raise_on_exec))


def test_health_requires_admin():
    assert TestClient(app).get("/api/admin/health").status_code in (401, 403)


def test_health_ok_with_active_llm(monkeypatch):
    _admin()
    monkeypatch.setattr(adm, "supabase", _fake(row={
        "id": 1, "llm_last_ok_at": "2026-06-25T10:00:00+00:00",
        "llm_last_error_at": None, "llm_last_error": None, "llm_last_model": "m"}))
    r = TestClient(app).get("/api/admin/health")
    assert r.status_code == 200
    b = r.json()
    assert b["backend"]["status"] == "ok" and "revision" in b["backend"]
    assert b["supabase"]["status"] == "ok" and isinstance(b["supabase"]["latency_ms"], int)
    assert b["llm"]["status"] == "ok"
    app.dependency_overrides.clear()


def test_health_supabase_down_still_200(monkeypatch):
    _admin()
    monkeypatch.setattr(adm, "supabase", _fake(raise_on_exec=True))
    r = TestClient(app).get("/api/admin/health")
    assert r.status_code == 200
    assert r.json()["supabase"]["status"] == "down"
    assert r.json()["llm"]["status"] == "idle"
    app.dependency_overrides.clear()


def test_llm_status_derivation():
    assert adm._llm_status(None)["status"] == "idle"
    assert adm._llm_status({"llm_last_ok_at": "2026-06-25T10:00:00+00:00"})["status"] == "ok"
    degraded = adm._llm_status({
        "llm_last_ok_at": "2026-06-25T10:00:00+00:00",
        "llm_last_error_at": "2026-06-25T11:00:00+00:00", "llm_last_error": "boom"})
    assert degraded["status"] == "degraded" and degraded["last_error"] == "boom"


def test_llm_test_success(monkeypatch):
    _admin()
    monkeypatch.setattr(adm.litellm, "completion", lambda **k: types.SimpleNamespace())
    r = TestClient(app).post("/api/admin/health/llm-test")
    assert r.status_code == 200 and r.json()["ok"] is True
    app.dependency_overrides.clear()


def test_llm_test_failure_reports_error(monkeypatch):
    _admin()
    def _boom(**k): raise RuntimeError("provider 500")
    monkeypatch.setattr(adm.litellm, "completion", _boom)
    r = TestClient(app).post("/api/admin/health/llm-test")
    assert r.status_code == 200 and r.json()["ok"] is False and "provider 500" in r.json()["error"]
    app.dependency_overrides.clear()
