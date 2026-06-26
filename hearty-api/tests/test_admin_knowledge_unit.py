from fastapi.testclient import TestClient
from app.main import app
from app.auth import get_current_admin
from app.routers import admin as adm


def _admin():
    app.dependency_overrides[get_current_admin] = lambda: {"id": "admin1", "email": "o"}


def test_add_knowledge(monkeypatch):
    _admin()
    calls = {}
    monkeypatch.setattr(adm.knowledge, "add_entry",
                        lambda **k: (calls.update(k) or {"id": "kb1", "title": k.get("title")}))
    r = TestClient(app).post("/api/admin/knowledge",
                             json={"title": "T", "content": "body", "conditions": ["gerd"]})
    assert r.status_code == 200 and r.json()["id"] == "kb1"
    assert calls["content"] == "body" and calls["conditions"] == ["gerd"]
    app.dependency_overrides.clear()


def test_add_knowledge_embedding_error_returns_502(monkeypatch):
    _admin()

    def boom(**k): raise RuntimeError("no api key")
    monkeypatch.setattr(adm.knowledge, "add_entry", boom)
    r = TestClient(app).post("/api/admin/knowledge", json={"content": "body"})
    assert r.status_code == 502
    app.dependency_overrides.clear()


def test_list_knowledge(monkeypatch):
    _admin()
    monkeypatch.setattr(adm.knowledge, "list_entries", lambda: [{"id": "kb1", "title": "T"}])
    r = TestClient(app).get("/api/admin/knowledge")
    assert r.json()["entries"][0]["id"] == "kb1"
    app.dependency_overrides.clear()


def test_delete_knowledge(monkeypatch):
    _admin()
    seen = {}
    monkeypatch.setattr(adm.knowledge, "delete_entry", lambda i: seen.update(id=i))
    r = TestClient(app).delete("/api/admin/knowledge/kb9")
    assert r.status_code == 200 and seen["id"] == "kb9"
    app.dependency_overrides.clear()


def test_patch_knowledge_toggles_active(monkeypatch):
    _admin()
    seen = {}
    monkeypatch.setattr(adm.knowledge, "set_active",
                        lambda i, a: (seen.update(id=i, active=a) or {"id": i, "active": a}))
    r = TestClient(app).patch("/api/admin/knowledge/kb9", json={"active": False})
    assert r.json()["active"] is False and seen["active"] is False
    app.dependency_overrides.clear()


def test_knowledge_admin_required():
    assert TestClient(app).get("/api/admin/knowledge").status_code in (401, 403)
