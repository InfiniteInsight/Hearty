import types
from uuid import uuid4
from fastapi.testclient import TestClient
from app.main import app
from app.auth import get_current_user
from app.routers import symptoms as sym


class _Q:
    def __init__(self, store):
        self.store = store; self._op = None; self._payload = None
    def select(self, *a, **k): self._op = "select"; return self
    def update(self, payload): self._op = "update"; self._payload = payload; return self
    def eq(self, *a, **k): return self
    def execute(self):
        if self._op == "update":
            self.store["update_payload"] = self._payload
            row = {"id": self.store["sid"], "symptom_type": self._payload.get("symptom_type", "bloating"),
                   "severity": self._payload.get("severity"), "onset_minutes": self._payload.get("onset_minutes"),
                   "logged_at": "2026-06-26T00:00:00Z"}
            return types.SimpleNamespace(data=[row])
        return types.SimpleNamespace(data=[{"id": self.store["sid"], "user_id": "u1"}])


class _Supa:
    def __init__(self, store): self.store = store
    def table(self, name): return _Q(self.store)


def _setup(monkeypatch):
    sid = str(uuid4())
    store = {"sid": sid}
    monkeypatch.setattr(sym, "supabase", _Supa(store))
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    return sid, store


def test_patch_sets_symptom_type_without_touching_description(monkeypatch):
    sid, store = _setup(monkeypatch)
    r = TestClient(app).patch(f"/api/symptoms/{sid}", json={"symptom_type": "nausea", "severity": 4})
    assert r.status_code == 200
    assert store["update_payload"]["symptom_type"] == "nausea"
    assert store["update_payload"]["severity"] == 4
    assert "raw_description" not in store["update_payload"]
    app.dependency_overrides.clear()


def test_patch_with_description_updates_raw_description(monkeypatch):
    sid, store = _setup(monkeypatch)
    r = TestClient(app).patch(f"/api/symptoms/{sid}", json={"description": "less bloated"})
    assert r.status_code == 200
    assert store["update_payload"]["raw_description"] == "less bloated"
    app.dependency_overrides.clear()


def test_patch_requires_auth():
    from uuid import uuid4 as u
    assert TestClient(app).patch(f"/api/symptoms/{u()}", json={"severity": 1}).status_code in (401, 403)
