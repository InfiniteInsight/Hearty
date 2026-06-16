import io
from fastapi.testclient import TestClient
from app.main import app
from app.auth import get_current_user
from app.routers import photos as ph

# Response models type `id: UUID`, so test ids that flow into a response field
# must be valid UUID strings (pydantic rejects "p1"). The user id, the 404 path,
# and the create_row return never reach a UUID field, so they stay as-is.
PID = "11111111-1111-1111-1111-111111111111"


def _png_bytes():
    return b"\x89PNG\r\n\x1a\n" + b"\x00" * 32


def test_upload_creates_row_and_enqueues(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    rec = {}
    monkeypatch.setattr(ph.photo_store, "upload_bytes", lambda path, data, ct: rec.update({"path": path}))
    monkeypatch.setattr(ph.photo_store, "create_row",
        lambda u, pid, url, ptype, meal_id: {"id": pid, "type": ptype})
    monkeypatch.setattr(ph.photo_pipeline, "process_photo",
        lambda pid, uid: rec.update({"enqueued": (pid, uid)}))
    client = TestClient(app)
    r = client.post("/api/photos",
        files={"file": ("plate.png", io.BytesIO(_png_bytes()), "image/png")},
        data={"type": "food_plate"})
    assert r.status_code == 202
    body = r.json()
    assert body["status"] == "processing" and body["type"] == "food_plate"
    assert rec["path"].startswith("u1/")
    assert rec["enqueued"][1] == "u1"
    app.dependency_overrides.clear()


def test_upload_rejects_non_image(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    client = TestClient(app)
    r = client.post("/api/photos",
        files={"file": ("note.txt", io.BytesIO(b"hello"), "text/plain")},
        data={"type": "food_plate"})
    assert r.status_code == 400
    app.dependency_overrides.clear()


def test_upload_rejects_oversize(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    monkeypatch.setattr(ph, "MAX_PHOTO_BYTES", 10)  # tiny cap for the test
    client = TestClient(app)
    r = client.post("/api/photos",
        files={"file": ("plate.png", io.BytesIO(b"\x89PNG" + b"\x00" * 50), "image/png")},
        data={"type": "food_plate"})
    assert r.status_code == 400
    app.dependency_overrides.clear()


def test_status_maps_row(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    monkeypatch.setattr(ph.photo_store, "get_photo", lambda u, p: {
        "id": PID, "photo_type": "food_plate", "processing_status": "complete",
        "extracted_data": {"foods": [{"name": "egg"}]}})
    client = TestClient(app)
    r = client.get("/api/photos/p1/status")
    body = r.json()
    assert body["status"] == "complete"
    assert body["result"]["foods"][0]["name"] == "egg"
    app.dependency_overrides.clear()


def test_status_404_when_missing(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    monkeypatch.setattr(ph.photo_store, "get_photo", lambda u, p: None)
    client = TestClient(app)
    r = client.get("/api/photos/nope/status")
    assert r.status_code == 404
    app.dependency_overrides.clear()


def test_retry_resets_and_reenqueues(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    rec = {}
    monkeypatch.setattr(ph.photo_store, "get_photo", lambda u, p: {"id": PID, "photo_type": "food_plate"})
    monkeypatch.setattr(ph.photo_store, "set_processing", lambda u, p: rec.update({"reset": p}))
    monkeypatch.setattr(ph.photo_pipeline, "process_photo", lambda pid, uid: rec.update({"enqueued": pid}))
    client = TestClient(app)
    r = client.post(f"/api/photos/{PID}/retry")
    assert r.status_code == 202
    assert rec["reset"] == PID and rec["enqueued"] == PID
    app.dependency_overrides.clear()
