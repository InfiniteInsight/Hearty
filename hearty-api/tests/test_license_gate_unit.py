import types
from datetime import datetime, timezone, timedelta
from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient
from app import licensing
from app.auth import get_current_user


def _ns(data):
    return types.SimpleNamespace(data=data)


class _Tbl:
    """Routes by table name. licenses: stateful (select re-reads, upsert inserts
    once when empty to mimic on_conflict/ignore_duplicates). app_settings: returns
    the configured settings row."""
    def __init__(self, db, name):
        self.db, self.name = db, name
        self._op = None; self._payload = None
    def select(self, *a, **k): self._op = "select"; return self
    def eq(self, *a, **k): return self
    def limit(self, *a, **k): return self
    def upsert(self, payload, **k): self._op = "upsert"; self._payload = payload; return self
    def execute(self):
        if self.name == "app_settings":
            return _ns([self.db.settings] if self.db.settings else [])
        # licenses
        if self._op == "upsert":
            if not self.db.licenses:
                self.db.licenses.append({
                    "status": self._payload.get("status"),
                    "expires_at": self._payload.get("expires_at"),
                })
            return _ns(list(self.db.licenses))
        return _ns(list(self.db.licenses))


class _FakeDB:
    def __init__(self, licenses, settings):
        self.licenses = list(licenses)
        self.settings = settings
    def table(self, name): return _Tbl(self, name)


def _client():
    app = FastAPI()

    @app.get("/gated", dependencies=[Depends(licensing.require_active_license)])
    async def gated():
        return {"ok": True}

    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    return app


def _wire(monkeypatch, licenses, settings):
    monkeypatch.setattr(licensing, "supabase", _FakeDB(licenses, settings))


def test_active_allows(monkeypatch):
    _wire(monkeypatch, [{"status": "active", "expires_at": None}], {"provisioning_mode": "open", "trial_days": 14})
    assert TestClient(_client()).get("/gated").status_code == 200


def test_revoked_blocks(monkeypatch):
    _wire(monkeypatch, [{"status": "revoked", "expires_at": None}], {"provisioning_mode": "open", "trial_days": 14})
    assert TestClient(_client()).get("/gated").status_code == 403


def test_expired_blocks(monkeypatch):
    past = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
    _wire(monkeypatch, [{"status": "active", "expires_at": past}], {"provisioning_mode": "open", "trial_days": 14})
    assert TestClient(_client()).get("/gated").status_code == 403


def test_new_user_paywall_blocks(monkeypatch):
    _wire(monkeypatch, [], {"provisioning_mode": "paywall", "trial_days": 14})
    r = TestClient(_client()).get("/gated")
    assert r.status_code == 403 and r.json()["detail"] == "no_active_license"


def test_new_user_open_provisions_active(monkeypatch):
    db = _FakeDB([], {"provisioning_mode": "open", "trial_days": 14})
    monkeypatch.setattr(licensing, "supabase", db)
    assert TestClient(_client()).get("/gated").status_code == 200
    assert db.licenses and db.licenses[0]["status"] == "active"
    assert db.licenses[0]["expires_at"] is None


def test_new_user_trial_provisions_expiring(monkeypatch):
    db = _FakeDB([], {"provisioning_mode": "trial", "trial_days": 14})
    monkeypatch.setattr(licensing, "supabase", db)
    assert TestClient(_client()).get("/gated").status_code == 200
    exp = db.licenses[0]["expires_at"]
    assert exp is not None and datetime.fromisoformat(exp) > datetime.now(timezone.utc)


def test_get_settings_default_when_missing(monkeypatch):
    monkeypatch.setattr(licensing, "supabase", _FakeDB([], None))
    assert licensing._get_settings()["provisioning_mode"] == "open"
