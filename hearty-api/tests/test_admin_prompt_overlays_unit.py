from fastapi.testclient import TestClient
from app.main import app
from app.auth import get_current_admin
from app.routers import admin as adm


def _admin():
    app.dependency_overrides[get_current_admin] = lambda: {"id": "admin1", "email": "o"}


def test_list_overlays(monkeypatch):
    _admin()
    monkeypatch.setattr(adm.prompt_overlays, "list_overlays",
                        lambda: [{"surface": "summary", "guidance": "warm", "updated_at": "t"}])
    r = TestClient(app).get("/api/admin/prompt-overlays")
    assert r.status_code == 200 and r.json()["overlays"][0]["surface"] == "summary"
    app.dependency_overrides.clear()


def test_update_overlay(monkeypatch):
    _admin()
    seen = {}
    monkeypatch.setattr(adm.prompt_overlays, "set_overlay",
                        lambda s, g, a: (seen.update(surface=s, guidance=g, admin=a) or
                                         {"surface": s, "guidance": g}))
    r = TestClient(app).put("/api/admin/prompt-overlays/summary", json={"guidance": "be brief"})
    assert r.status_code == 200 and r.json()["guidance"] == "be brief"
    assert seen == {"surface": "summary", "guidance": "be brief", "admin": "admin1"}
    app.dependency_overrides.clear()


def test_update_overlay_unknown_surface_400(monkeypatch):
    _admin()

    def boom(s, g, a): raise ValueError("unknown surface: bogus")
    monkeypatch.setattr(adm.prompt_overlays, "set_overlay", boom)
    r = TestClient(app).put("/api/admin/prompt-overlays/bogus", json={"guidance": "x"})
    assert r.status_code == 400
    app.dependency_overrides.clear()


def test_list_versions(monkeypatch):
    _admin()
    monkeypatch.setattr(adm.prompt_overlays, "list_versions",
                        lambda s: [{"id": "v1", "surface": s, "guidance": "a", "created_at": "t", "created_by": None}])
    r = TestClient(app).get("/api/admin/prompt-overlays/summary/versions")
    assert r.json()["versions"][0]["id"] == "v1"
    app.dependency_overrides.clear()


def test_revert_overlay(monkeypatch):
    _admin()
    seen = {}
    monkeypatch.setattr(adm.prompt_overlays, "revert",
                        lambda s, v, a: (seen.update(surface=s, version=v, admin=a) or
                                         {"surface": s, "guidance": "old"}))
    r = TestClient(app).post("/api/admin/prompt-overlays/summary/revert", json={"version_id": "v9"})
    assert r.status_code == 200 and r.json()["guidance"] == "old"
    assert seen == {"surface": "summary", "version": "v9", "admin": "admin1"}
    app.dependency_overrides.clear()


def test_overlays_admin_required():
    assert TestClient(app).get("/api/admin/prompt-overlays").status_code in (401, 403)
