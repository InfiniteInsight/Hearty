import httpx
import uuid
import pytest

# ── Happy paths ──────────────────────────────────────────────────────────────

def test_health_check(api_base):
    r = httpx.get(f"{api_base}/health", timeout=30)
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}

def test_log_meal(api_base, headers):
    r = httpx.post(f"{api_base}/api/meals", headers=headers, json={
        "description": "Scrambled eggs with toast",
        "offline_id": str(uuid.uuid4())
    }, timeout=30)
    assert r.status_code == 201
    body = r.json()
    assert "id" in body
    assert isinstance(body.get("foods"), list)
    assert len(body["foods"]) >= 1

def test_log_meal_idempotency(api_base, headers):
    oid = str(uuid.uuid4())
    payload = {"description": "Oatmeal with berries", "offline_id": oid}
    r1 = httpx.post(f"{api_base}/api/meals", headers=headers, json=payload, timeout=30)
    assert r1.status_code == 201
    r2 = httpx.post(f"{api_base}/api/meals", headers=headers, json=payload, timeout=30)
    assert r2.status_code == 200
    assert r1.json()["id"] == r2.json()["id"]

def test_query_meals(api_base, headers):
    r = httpx.get(f"{api_base}/api/meals", headers=headers)
    assert r.status_code == 200
    body = r.json()
    assert "total" in body
    assert "meals" in body
    assert isinstance(body["meals"], list)
    if body["meals"]:
        assert "symptoms" in body["meals"][0]

def test_log_symptoms(api_base, headers):
    r = httpx.post(f"{api_base}/api/symptoms", headers=headers, json={
        "raw_description": "Mild bloating about 20 minutes after eating, maybe a 4 out of 10"
    }, timeout=30)
    assert r.status_code == 201
    body = r.json()
    assert isinstance(body, list)
    assert len(body) >= 1

def test_log_wellbeing(api_base, headers):
    r = httpx.post(f"{api_base}/api/wellbeing", headers=headers, json={
        "energy_level": 7, "mood": 8, "sleep_hours": 7.5
    })
    assert r.status_code == 201
    assert "id" in r.json()

def test_get_trends(api_base, headers):
    r = httpx.get(f"{api_base}/api/trends", headers=headers)
    assert r.status_code == 200

def test_get_summary_week(api_base, headers):
    r = httpx.get(f"{api_base}/api/summary?period=week", headers=headers, timeout=30)
    assert r.status_code == 200
    body = r.json()
    assert "summary_text" in body

def test_export_json(api_base, headers):
    r = httpx.get(f"{api_base}/api/export/json", headers=headers)
    assert r.status_code == 200
    assert "application/json" in r.headers.get("content-type", "")

def test_export_csv(api_base, headers):
    r = httpx.get(f"{api_base}/api/export/csv", headers=headers)
    assert r.status_code == 200
    assert "text/csv" in r.headers.get("content-type", "")

def test_export_pdf(api_base, headers):
    r = httpx.post(f"{api_base}/api/export/pdf", headers=headers, json={}, timeout=30)
    assert r.status_code == 200
    assert r.headers.get("content-type") == "application/pdf"
    assert r.content[:4] == b"%PDF"

def test_get_health_profile(api_base, headers):
    r = httpx.get(f"{api_base}/api/health-profile", headers=headers)
    assert r.status_code == 200

def test_update_health_profile(api_base, headers):
    r = httpx.put(f"{api_base}/api/health-profile", headers=headers, json={
        "allergens": [{"name": "peanuts", "severity": "mild"}],
        "intolerances": [],
        "conditions": [],
        "dietary_protocols": []
    })
    assert r.status_code == 200

# ── Error paths ───────────────────────────────────────────────────────────────

def test_unauthenticated_request(api_base):
    r = httpx.get(f"{api_base}/api/meals")
    assert r.status_code == 401

def test_invalid_token(api_base):
    r = httpx.get(f"{api_base}/api/meals", headers={"Authorization": "Bearer bad-token"})
    assert r.status_code == 401

def test_summary_custom_missing_dates(api_base, headers):
    r = httpx.get(f"{api_base}/api/summary?period=custom", headers=headers)
    assert r.status_code == 422

def test_photo_stub(api_base, headers):
    import io
    r = httpx.post(
        f"{api_base}/api/photos",
        headers=headers,
        files={"file": ("test.jpg", io.BytesIO(b"fake"), "image/jpeg")},
        data={"type": "meal"}
    )
    assert r.status_code == 501


def test_update_meal(api_base, headers):
    # Create
    r = httpx.post(f"{api_base}/api/meals", headers=headers, json={
        "description": "pancakes with syrup", "offline_id": str(uuid.uuid4())
    }, timeout=30)
    assert r.status_code == 201
    meal_id = r.json()["id"]

    # Patch
    r2 = httpx.patch(f"{api_base}/api/meals/{meal_id}", headers=headers,
                     json={"description": "pancakes with maple syrup"}, timeout=30)
    assert r2.status_code == 200
    body = r2.json()
    assert body["description"] == "pancakes with maple syrup"
    assert isinstance(body["foods"], list)

    # Cleanup
    httpx.delete(f"{api_base}/api/meals/{meal_id}", headers=headers)


def test_delete_meal(api_base, headers):
    r = httpx.post(f"{api_base}/api/meals", headers=headers, json={
        "description": "toast to delete", "offline_id": str(uuid.uuid4())
    }, timeout=30)
    assert r.status_code == 201
    meal_id = r.json()["id"]

    r2 = httpx.delete(f"{api_base}/api/meals/{meal_id}", headers=headers)
    assert r2.status_code == 204

    # Verify gone: PATCH on deleted ID returns 404
    r3 = httpx.patch(f"{api_base}/api/meals/{meal_id}", headers=headers,
                     json={"description": "ghost"}, timeout=30)
    assert r3.status_code == 404


def test_delete_meal_wrong_user(api_base, headers):
    r = httpx.post(f"{api_base}/api/meals", headers=headers, json={
        "description": "private meal", "offline_id": str(uuid.uuid4())
    }, timeout=30)
    assert r.status_code == 201
    meal_id = r.json()["id"]

    # Attempt delete without auth header → 403 or 401
    r2 = httpx.delete(f"{api_base}/api/meals/{meal_id}")
    assert r2.status_code in (401, 403)

    # Cleanup
    httpx.delete(f"{api_base}/api/meals/{meal_id}", headers=headers)
