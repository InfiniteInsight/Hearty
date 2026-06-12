"""Unit tests for the daily check-in endpoints — no network, no real JWT.

Mocks supabase (and, for the write-backs, ai_extraction) so the gap-queue
shape, the 48h expiry, and each write-back's row shape + follow-up flips are
tested deterministically.
"""
from datetime import datetime, timezone

from fastapi.testclient import TestClient

from app.main import app
from app.auth import get_current_user
from app.routers import checkin as checkin_module


class _Result:
    def __init__(self, data):
        self.data = data


# ── Read-path fake (gaps endpoint): every query returns empty; detector mocked ──
class _Q:
    def __init__(self, data):
        self._d = data

    def select(self, *a, **k):
        return self

    def eq(self, *a, **k):
        return self

    def gte(self, *a, **k):
        return self

    def lte(self, *a, **k):
        return self

    def execute(self):
        return _Result(self._d)


class _Supa:
    def table(self, name):
        return _Q([])


# ── Write-path fake: records inserts/updates, returns configured select data ──
class _Recorder:
    def __init__(self, select_data=None):
        self.inserts = []   # (table, rows)
        self.updates = []   # (table, vals)
        self.select_data = select_data or {}  # table -> list


class _Table:
    def __init__(self, name, rec):
        self.name = name
        self.rec = rec
        self._op = None

    def insert(self, rows, *a, **k):
        self.rec.inserts.append((self.name, rows))
        self._op = "insert"
        return self

    def update(self, vals, *a, **k):
        self.rec.updates.append((self.name, vals))
        self._op = "update"
        return self

    def select(self, *a, **k):
        self._op = "select"
        return self

    def eq(self, *a, **k):
        return self

    def gte(self, *a, **k):
        return self

    def lte(self, *a, **k):
        return self

    def execute(self):
        if self._op == "select":
            return _Result(self.rec.select_data.get(self.name, []))
        return _Result([{"id": "x1"}])


class _RecSupa:
    def __init__(self, rec):
        self.rec = rec

    def table(self, name):
        return _Table(name, self.rec)


def _auth():
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}


def _clear():
    app.dependency_overrides.clear()


# ─────────────────────────────── GET /gaps ──────────────────────────────────

def test_gaps_endpoint_returns_queue(monkeypatch):
    # Use TODAY so the request is always inside the 48h window, whenever this runs.
    today = datetime.now(timezone.utc).date().isoformat()
    _auth()
    monkeypatch.setattr(checkin_module, "supabase", _Supa())
    monkeypatch.setattr(checkin_module.checkin_detector, "detect_gaps",
                        lambda *a, **k: [{"type": "missing_chunk",
                                          "prompt": "p", "window_start": "s",
                                          "window_end": "e"}])
    client = TestClient(app)
    r = client.get(f"/api/checkin/gaps?date={today}")
    assert r.status_code == 200
    body = r.json()
    assert body["expired"] is False
    assert body["gaps"][0]["type"] == "missing_chunk"
    _clear()


def test_gaps_endpoint_expires_old_dates(monkeypatch):
    _auth()
    monkeypatch.setattr(checkin_module, "supabase", _Supa())
    client = TestClient(app)
    r = client.get("/api/checkin/gaps?date=2020-01-01")  # far in the past
    assert r.status_code == 200
    assert r.json()["expired"] is True
    assert r.json()["gaps"] == []
    _clear()


def test_gaps_endpoint_requires_auth():
    # No dependency override → real get_current_user rejects.
    c = TestClient(app)
    r = c.get("/api/checkin/gaps?date=2026-06-03")
    assert r.status_code in (401, 403)


# ─────────────────────────── write-backs (A) ────────────────────────────────

def test_resolve_symptom_gap_inserts_symptom_and_marks_meal(monkeypatch):
    rec = _Recorder()
    _auth()
    monkeypatch.setattr(checkin_module, "supabase", _RecSupa(rec))
    client = TestClient(app)
    r = client.post("/api/checkin/resolve/symptom", json={
        "meal_id": "m1", "raw_description": "a bit bloated", "severity": 4})
    assert r.status_code == 200
    assert any(t == "symptoms" for t, _ in rec.inserts)
    assert any(t == "meals" and v.get("followup_status") == "answered"
               for t, v in rec.updates)
    _clear()


def test_skip_symptom_gap_marks_resurfaced(monkeypatch):
    rec = _Recorder()
    _auth()
    monkeypatch.setattr(checkin_module, "supabase", _RecSupa(rec))
    client = TestClient(app)
    r = client.post("/api/checkin/skip/symptom", json={"meal_id": "m1"})
    assert r.status_code == 200
    assert any(t == "meals" and v.get("followup_status") == "resurfaced"
               for t, v in rec.updates)
    assert rec.inserts == []  # skip never writes a symptom
    _clear()


# ─────────────────────────── write-backs (C) ────────────────────────────────

def test_resolve_food_confirm_bumps_confidence_to_one(monkeypatch):
    rec = _Recorder(select_data={"meals": [
        {"foods": [{"name": "buldak ramen", "confidence": 0.45},
                   {"name": "rice", "confidence": 0.99}]}]})
    _auth()
    monkeypatch.setattr(checkin_module, "supabase", _RecSupa(rec))
    client = TestClient(app)
    r = client.post("/api/checkin/resolve/food", json={
        "meal_id": "m1", "food_name": "buldak ramen", "confirmed": True})
    assert r.status_code == 200
    # the matching food is bumped to 1.0; the other is untouched
    _, vals = next((t, v) for t, v in rec.updates if t == "meals")
    foods = {f["name"]: f["confidence"] for f in vals["foods"]}
    assert foods["buldak ramen"] == 1.0
    assert foods["rice"] == 0.99
    _clear()


def test_resolve_food_correction_reextracts_and_updates(monkeypatch):
    rec = _Recorder()
    _auth()
    monkeypatch.setattr(checkin_module, "supabase", _RecSupa(rec))
    monkeypatch.setattr(checkin_module.ai_extraction, "extract_meal",
                        lambda d: {"foods": [{"name": "buldak ramen"}],
                                   "inferred_meal_type": "snack"})
    client = TestClient(app)
    r = client.post("/api/checkin/resolve/food", json={
        "meal_id": "m1", "corrected_description": "buldak ramen"})
    assert r.status_code == 200
    _, vals = next((t, v) for t, v in rec.updates if t == "meals")
    assert vals["foods"] == [{"name": "buldak ramen"}]
    assert vals["description"] == "buldak ramen"
    _clear()


# ─────────────────────────── write-backs (D) ────────────────────────────────

def test_resolve_meal_inserts_on_target_day(monkeypatch):
    rec = _Recorder()
    _auth()
    monkeypatch.setattr(checkin_module, "supabase", _RecSupa(rec))
    monkeypatch.setattr(checkin_module.ai_extraction, "extract_meal",
                        lambda d: {"foods": [{"name": "toast"}],
                                   "inferred_meal_type": "breakfast"})
    client = TestClient(app)
    target_ts = "2026-06-03T15:00:00+00:00"
    r = client.post("/api/checkin/resolve/meal", json={
        "description": "toast at 3pm", "logged_at": target_ts})
    assert r.status_code == 200
    table, row = next((t, r_) for t, r_ in rec.inserts if t == "meals")
    assert row["logged_at"] == target_ts        # stamped to the target day
    assert row["foods"] == [{"name": "toast"}]
    assert row["user_id"] == "u1"
    _clear()
