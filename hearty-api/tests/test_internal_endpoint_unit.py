from fastapi.testclient import TestClient
from app.main import app
from app.routers import internal as it

PURGE = "/internal/photos/purge"


def test_rejects_when_token_unset(monkeypatch):
    monkeypatch.delenv("CLEANUP_TOKEN", raising=False)
    r = TestClient(app).post(PURGE, headers={"X-Cleanup-Token": "anything"})
    assert r.status_code == 403


def test_rejects_wrong_token(monkeypatch):
    monkeypatch.setenv("CLEANUP_TOKEN", "secret")
    r = TestClient(app).post(PURGE, headers={"X-Cleanup-Token": "nope"})
    assert r.status_code == 403


def test_purges_listed_rows(monkeypatch):
    monkeypatch.setenv("CLEANUP_TOKEN", "secret")
    monkeypatch.setenv("PHOTO_RETENTION_HOURS", "24")
    rows = [
        {"id": "p1", "user_id": "u1", "photo_url": "u1/p1.jpg"},
        {"id": "p2", "user_id": "u2", "photo_url": "u2/p2.jpg"},
    ]
    calls = []
    monkeypatch.setattr(it.photo_store, "list_purgeable", lambda cutoff: rows)
    monkeypatch.setattr(it.photo_store, "purge_image",
                        lambda u, p, path: calls.append((u, p, path)))
    r = TestClient(app).post(PURGE, headers={"X-Cleanup-Token": "secret"})
    assert r.status_code == 200
    assert r.json() == {"purged": 2, "scanned": 2}
    assert ("u1", "p1", "u1/p1.jpg") in calls and ("u2", "p2", "u2/p2.jpg") in calls


def test_per_row_failure_does_not_abort_batch(monkeypatch):
    monkeypatch.setenv("CLEANUP_TOKEN", "secret")
    rows = [{"id": "p1", "user_id": "u1", "photo_url": "u1/p1.jpg"},
            {"id": "p2", "user_id": "u2", "photo_url": "u2/p2.jpg"}]
    monkeypatch.setattr(it.photo_store, "list_purgeable", lambda cutoff: rows)
    def _purge(u, p, path):
        if p == "p1": raise RuntimeError("storage down")
    monkeypatch.setattr(it.photo_store, "purge_image", _purge)
    r = TestClient(app).post(PURGE, headers={"X-Cleanup-Token": "secret"})
    assert r.status_code == 200
    assert r.json() == {"purged": 1, "scanned": 2}


def test_empty_list_is_a_noop(monkeypatch):
    monkeypatch.setenv("CLEANUP_TOKEN", "secret")
    monkeypatch.setattr(it.photo_store, "list_purgeable", lambda cutoff: [])
    def _should_not_call(*a):
        raise AssertionError("purge_image should not be called for an empty list")
    monkeypatch.setattr(it.photo_store, "purge_image", _should_not_call)
    r = TestClient(app).post(PURGE, headers={"X-Cleanup-Token": "secret"})
    assert r.status_code == 200
    assert r.json() == {"purged": 0, "scanned": 0}
