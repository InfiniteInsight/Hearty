import types
from fastapi.testclient import TestClient
from app.main import app
from app.auth import get_current_admin
from app.routers import admin as adm


class _Tbl:
    def __init__(self, log, rows):
        self.log, self.rows = log, rows
        self._op = None; self._payload = None; self._eq = None
    def select(self, *a, **k): self._op = "select"; return self
    def upsert(self, payload, **k): self._op = "upsert"; self._payload = payload; return self
    def update(self, payload): self._op = "update"; self._payload = payload; return self
    def eq(self, col, val): self._eq = (col, val); return self
    def limit(self, *a, **k): return self
    def execute(self):
        if self._op == "select":
            return types.SimpleNamespace(data=self.rows)
        self.log.append((self._op, self._payload, self._eq))
        row = dict(self._payload) if isinstance(self._payload, dict) else {}
        if self._eq: row["user_id"] = self._eq[1]
        return types.SimpleNamespace(data=[row])


class _FakeSupabase:
    def __init__(self, rows):
        self.log = []; self.rows = rows
        self.auth = types.SimpleNamespace(admin=types.SimpleNamespace(
            list_users=lambda: [types.SimpleNamespace(id="u1", email="a@x.com", created_at="2026-01-01")]
        ))
    def table(self, name): return _Tbl(self.log, self.rows)


def _admin():
    app.dependency_overrides[get_current_admin] = lambda: {"id": "admin1", "email": "o"}


def test_list_users(monkeypatch):
    _admin()
    monkeypatch.setattr(adm, "supabase", _FakeSupabase(rows=[{"user_id": "u1", "status": "active", "expires_at": None, "tier": None, "activation_source": "comp"}]))
    r = TestClient(app).get("/api/admin/users")
    assert r.status_code == 200
    u = r.json()["users"][0]
    assert u["user_id"] == "u1" and u["license"]["status"] == "active"
    app.dependency_overrides.clear()


def test_grant(monkeypatch):
    _admin()
    fake = _FakeSupabase(rows=[]); monkeypatch.setattr(adm, "supabase", fake)
    r = TestClient(app).post("/api/admin/licenses", json={"user_id": "u9", "expires_at": "2027-01-01T00:00:00Z"})
    assert r.status_code == 200
    assert any(op == "upsert" and p.get("status") == "active" and p.get("granted_by") == "admin1" for (op, p, _e) in fake.log)
    app.dependency_overrides.clear()


def test_revoke(monkeypatch):
    _admin()
    fake = _FakeSupabase(rows=[]); monkeypatch.setattr(adm, "supabase", fake)
    r = TestClient(app).post("/api/admin/licenses/u9/revoke")
    assert r.status_code == 200
    assert any(op == "update" and p.get("status") == "revoked" for (op, p, _e) in fake.log)
    app.dependency_overrides.clear()


def test_admin_required():
    # no override → real get_current_admin → 403/401 without a token
    assert TestClient(app).get("/api/admin/users").status_code in (401, 403)


def test_get_settings(monkeypatch):
    _admin()
    monkeypatch.setattr(adm, "supabase", _FakeSupabase(rows=[{"provisioning_mode": "trial", "trial_days": 7}]))
    r = TestClient(app).get("/api/admin/settings")
    assert r.status_code == 200
    assert r.json()["provisioning_mode"] == "trial" and r.json()["trial_days"] == 7
    app.dependency_overrides.clear()


def test_put_settings(monkeypatch):
    _admin()
    fake = _FakeSupabase(rows=[]); monkeypatch.setattr(adm, "supabase", fake)
    r = TestClient(app).put("/api/admin/settings", json={"provisioning_mode": "paywall", "trial_days": 30})
    assert r.status_code == 200
    assert any(op == "update" and p.get("provisioning_mode") == "paywall" and p.get("trial_days") == 30 and p.get("updated_by") == "admin1" for (op, p, _e) in fake.log)
    app.dependency_overrides.clear()


def test_put_settings_rejects_bad_mode(monkeypatch):
    _admin()
    monkeypatch.setattr(adm, "supabase", _FakeSupabase(rows=[]))
    r = TestClient(app).put("/api/admin/settings", json={"provisioning_mode": "nope"})
    assert r.status_code == 400
    app.dependency_overrides.clear()


def test_put_settings_rejects_bad_trial_days(monkeypatch):
    _admin()
    monkeypatch.setattr(adm, "supabase", _FakeSupabase(rows=[]))
    assert TestClient(app).put("/api/admin/settings", json={"trial_days": 0}).status_code == 400
    assert TestClient(app).put("/api/admin/settings", json={"trial_days": 99999}).status_code == 400
    app.dependency_overrides.clear()
