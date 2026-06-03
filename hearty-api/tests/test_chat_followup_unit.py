"""Unit tests for the /api/chat follow-up branch — no network, no JWT.

Mocks Supabase, the AI extractors, and litellm so the meal-update decision
logic is tested deterministically. Guards the data-corruption fix: a symptom
check-in (or any no-food follow-up) must never overwrite the logged meal.
"""
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.auth import get_current_user
from app.routers import chat as chat_module


class _FakeResult:
    def __init__(self, data):
        self.data = data


class _FakeTable:
    """Fluent stub. select() on 'meals' returns the existing meal; update()/
    insert() are recorded on the shared recorder so tests can assert on them."""

    def __init__(self, recorder, name, meal_desc):
        self._rec = recorder
        self._name = name
        self._meal_desc = meal_desc
        self._op = None

    def select(self, *a, **k):
        self._op = "select"
        return self

    def insert(self, rows, *a, **k):
        self._op = "insert"
        self._rec["insert"].append((self._name, rows))
        return self

    def update(self, updates, *a, **k):
        self._op = "update"
        self._rec["update"].append((self._name, updates))
        return self

    def delete(self, *a, **k):
        self._op = "delete"
        return self

    # chainable no-ops
    def eq(self, *a, **k):
        return self

    def in_(self, *a, **k):
        return self

    def ilike(self, *a, **k):
        return self

    def order(self, *a, **k):
        return self

    def gte(self, *a, **k):
        return self

    def lte(self, *a, **k):
        return self

    def limit(self, *a, **k):
        return self

    def execute(self):
        if self._op == "select":
            data = (
                [{"id": "meal-1", "description": self._meal_desc}]
                if self._name == "meals"
                else []
            )
            return _FakeResult(data)
        if self._op == "insert":
            return _FakeResult([{"id": "meal-new"}])
        return _FakeResult([])


class _FakeSupabase:
    def __init__(self, recorder, meal_desc):
        self._rec = recorder
        self._meal_desc = meal_desc

    def table(self, name):
        return _FakeTable(self._rec, name, self._meal_desc)


@pytest.fixture
def harness(monkeypatch):
    recorder = {"insert": [], "update": []}

    monkeypatch.setattr(
        chat_module, "supabase", _FakeSupabase(recorder, "tuna salad")
    )
    # Keep the signal-context query out of the picture.
    monkeypatch.setattr(chat_module, "_build_signal_context", lambda _uid: None)
    # Deterministic reply — avoid a real LLM call.
    monkeypatch.setattr(
        chat_module.litellm,
        "completion",
        lambda **_kw: SimpleNamespace(
            choices=[SimpleNamespace(message=SimpleNamespace(content="Glad you're okay!"))]
        ),
    )
    app.dependency_overrides[get_current_user] = lambda: {"id": "user-1"}
    client = TestClient(app)
    try:
        yield client, recorder, monkeypatch
    finally:
        app.dependency_overrides.clear()


def _meal_updates(recorder):
    return [u for (name, u) in recorder["update"] if name == "meals"]


def test_symptom_followup_never_edits_meal(harness):
    client, recorder, mp = harness
    # "I'm okay" extracts no symptom; the lock flag must short-circuit any meal edit.
    mp.setattr(chat_module.ai_extraction, "extract_symptoms", lambda _t: [])
    mp.setattr(
        chat_module.ai_extraction,
        "extract_meal",
        lambda _t: pytest.fail("extract_meal must not run on a locked check-in"),
    )

    r = client.post(
        "/api/chat",
        json={
            "message": "I'm okay",
            "meal_id": "meal-1",
            "symptom_followup": True,
            "history": [
                {"role": "assistant", "content": "How are you feeling after your last meal?"}
            ],
        },
    )
    assert r.status_code == 200
    assert _meal_updates(recorder) == []  # meal left untouched


def test_followup_without_food_does_not_overwrite_meal(harness):
    client, recorder, mp = harness
    # In-app follow-up (no lock flag), no symptom, and no food extracted -> guard
    # must skip the update so the existing meal is preserved.
    mp.setattr(chat_module.ai_extraction, "extract_symptoms", lambda _t: [])
    mp.setattr(
        chat_module.ai_extraction,
        "extract_meal",
        lambda _t: {"foods": [], "normalized_description": "no food described"},
    )

    r = client.post(
        "/api/chat",
        json={
            "message": "I'm okay",
            "meal_id": "meal-1",
            "history": [
                {"role": "assistant", "content": "How are you feeling?"}
            ],
        },
    )
    assert r.status_code == 200
    assert _meal_updates(recorder) == []  # no food -> not a clarification -> untouched


def test_followup_with_food_updates_meal(harness):
    client, recorder, mp = harness
    # A genuine meal clarification (food extracted) still updates the meal.
    mp.setattr(chat_module.ai_extraction, "extract_symptoms", lambda _t: [])
    mp.setattr(
        chat_module.ai_extraction,
        "extract_meal",
        lambda _t: {
            "foods": [{"name": "tuna sandwich"}],
            "normalized_description": "tuna sandwich",
            "inferred_meal_type": "lunch",
        },
    )

    r = client.post(
        "/api/chat",
        json={
            "message": "it was a tuna sandwich",
            "meal_id": "meal-1",
            "history": [
                {"role": "user", "content": "I had a sandwich"},
                {"role": "assistant", "content": "What kind of sandwich?"},
            ],
        },
    )
    assert r.status_code == 200
    updates = _meal_updates(recorder)
    assert len(updates) == 1
    assert "tuna sandwich" in updates[0]["description"].lower()
