from fastapi.testclient import TestClient
from app.main import app
from app.auth import get_current_user
from app.routers import food as fd


def test_lookup_endpoint(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    monkeypatch.setattr(fd.food_lookup, "lookup_food",
        lambda type, value, restaurant, user_id: {
            "item_name": "Oat Milk", "nutrition": {"calories": 120}, "tier_used": 1,
            "source": "open_food_facts", "confidence": None,
            "allergen_warnings": [], "message": None})
    client = TestClient(app)
    r = client.post("/api/food/lookup", json={"type": "barcode", "value": "123"})
    assert r.status_code == 200
    body = r.json()
    assert body["tier_used"] == 1 and body["nutrition"]["calories"] == 120
    app.dependency_overrides.clear()


def test_cache_endpoint_hit(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    monkeypatch.setattr(fd.food_cache, "get_cached", lambda key: {"calories": 100})
    client = TestClient(app)
    r = client.get("/api/food/cache/barcode:123")
    assert r.status_code == 200 and r.json()["hit"] is True
    assert r.json()["nutrition"]["calories"] == 100
    app.dependency_overrides.clear()


def test_cache_endpoint_miss(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    monkeypatch.setattr(fd.food_cache, "get_cached", lambda key: None)
    client = TestClient(app)
    r = client.get("/api/food/cache/barcode:nope")
    assert r.status_code == 200 and r.json()["hit"] is False
    app.dependency_overrides.clear()
