"""Unit tests for POST /api/meals verbatim-foods support — no network, no JWT.

When the caller supplies a `foods` list, the meal is stored as-is (name-only
items) and AI extraction is skipped — mirroring the merged PATCH behavior.
When no `foods` are supplied, the legacy extraction path still runs.
"""
import uuid
from datetime import datetime, timezone

from fastapi.testclient import TestClient

from app.main import app
from app.auth import get_current_user
from app.routers import meals as meals_module


class _Result:
    def __init__(self, data):
        self.data = data


class _Recorder:
    def __init__(self):
        self.inserts = []   # (table, row)


class _Table:
    def __init__(self, name, rec):
        self.name = name
        self.rec = rec
        self._op = None
        self._row = None

    def insert(self, row, *a, **k):
        self.rec.inserts.append((self.name, row))
        self._op = "insert"
        self._row = row
        return self

    def select(self, *a, **k):
        self._op = "select"
        return self

    def eq(self, *a, **k):
        return self

    def execute(self):
        if self._op == "select":
            # No existing offline_id match → empty.
            return _Result([])
        # Echo the inserted row with the columns MealResponse requires.
        return _Result([{
            **self._row,
            "id": str(uuid.uuid4()),
            "created_at": datetime.now(timezone.utc).isoformat(),
        }])


class _Supa:
    def __init__(self, rec):
        self.rec = rec

    def table(self, name):
        return _Table(name, self.rec)


def _auth():
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}


def _clear():
    app.dependency_overrides.clear()


def test_create_with_foods_skips_extraction(monkeypatch):
    rec = _Recorder()
    called = {"flag": False}

    def _recorder(description):
        called["flag"] = True
        return {"foods": [{"name": "AI WOULD HAVE EXTRACTED THIS"}]}

    _auth()
    monkeypatch.setattr(meals_module, "supabase", _Supa(rec))
    monkeypatch.setattr(meals_module.ai_extraction, "extract_meal", _recorder)
    client = TestClient(app)
    r = client.post("/api/meals", json={
        "description": "lunch",
        "foods": ["grilled salmon", "broccoli"],
        "input_method": "photo",
    })
    assert r.status_code == 201
    table, row = next((t, r_) for t, r_ in rec.inserts if t == "meals")
    assert row["foods"] == [{"name": "grilled salmon"}, {"name": "broccoli"}]
    assert row["input_method"] == "photo"
    assert called["flag"] is False  # extraction must NOT run on the verbatim path
    _clear()


def test_create_without_foods_still_extracts(monkeypatch):
    rec = _Recorder()
    called = {"flag": False}

    def _extract(description):
        called["flag"] = True
        return {"foods": [{"name": "toast"}], "inferred_meal_type": "breakfast"}

    _auth()
    monkeypatch.setattr(meals_module, "supabase", _Supa(rec))
    monkeypatch.setattr(meals_module.ai_extraction, "extract_meal", _extract)
    client = TestClient(app)
    r = client.post("/api/meals", json={"description": "some toast"})
    assert r.status_code == 201
    table, row = next((t, r_) for t, r_ in rec.inserts if t == "meals")
    assert row["foods"] == [{"name": "toast"}]
    assert called["flag"] is True  # legacy extraction path still runs
    _clear()
