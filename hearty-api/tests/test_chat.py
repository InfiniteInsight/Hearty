"""Unit tests for /api/chat meal-logging gate — no network, no real JWT, no LLM.

Pins the fix for the "off-topic refusal still logs a meal" bug: a first-turn
message that slips past the keyword _is_off_topic pre-filter but yields NO
extracted food must NOT insert a meal row (only the LLM reply declines).
"""
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.auth import get_current_user
from app.routers import chat as c


class _FakeQuery:
    def __init__(self, table, rec):
        self._table = table
        self._rec = rec
        self._op = None

    def insert(self, row):
        self._op = ("insert", row)
        self._rec["inserts"].append((self._table, row))
        return self

    def update(self, row):
        self._rec["updates"].append((self._table, row))
        return self

    def select(self, *a, **k):
        return self

    def eq(self, *a, **k):
        return self

    def order(self, *a, **k):
        return self

    def limit(self, *a, **k):
        return self

    def execute(self):
        if self._op and self._op[0] == "insert" and self._table == "meals":
            return SimpleNamespace(data=[{"id": "meal-123"}])
        return SimpleNamespace(data=[])


class _FakeSupabase:
    def __init__(self, rec):
        self._rec = rec

    def table(self, name):
        return _FakeQuery(name, self._rec)


@pytest.fixture
def harness(monkeypatch):
    rec = {"inserts": [], "updates": []}
    monkeypatch.setattr(c, "supabase", _FakeSupabase(rec))
    # Stub the conversational reply so no real LLM call happens.
    monkeypatch.setattr(
        c.litellm,
        "completion",
        lambda **k: SimpleNamespace(
            choices=[SimpleNamespace(message=SimpleNamespace(content="Got it!"))]
        ),
    )
    # Default: no symptoms (tests opt in). Prevents the no-food branch from
    # calling the real extractor.
    monkeypatch.setattr(c.ai_extraction, "extract_symptoms", lambda text: [])
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1"}
    yield rec, monkeypatch
    app.dependency_overrides.clear()


def _meals_inserted(rec):
    return [row for (table, row) in rec["inserts"] if table == "meals"]


def _symptoms_inserted(rec):
    return [row for (table, rows) in rec["inserts"] if table == "symptoms" for row in (rows if isinstance(rows, list) else [rows])]


def test_first_turn_with_food_logs_a_meal(harness):
    rec, monkeypatch = harness
    monkeypatch.setattr(
        c.ai_extraction,
        "extract_meal",
        lambda msg: {
            "foods": [{"name": "sandwich"}],
            "normalized_description": "a sandwich",
            "inferred_meal_type": "lunch",
        },
    )
    r = TestClient(app).post("/api/chat", json={"message": "I had a sandwich"})
    assert r.status_code == 200
    assert len(_meals_inserted(rec)) == 1
    assert r.json()["meal_id"] == "meal-123"


def test_first_turn_no_food_logs_nothing(harness):
    # The bug: this slips past the keyword _is_off_topic pre-filter, but the
    # extractor returns no foods → must NOT insert a junk meal.
    rec, monkeypatch = harness
    monkeypatch.setattr(
        c.ai_extraction,
        "extract_meal",
        lambda msg: {"foods": [], "normalized_description": "", "inferred_meal_type": "other"},
    )
    r = TestClient(app).post(
        "/api/chat", json={"message": "this is a transcription test"}
    )
    assert r.status_code == 200
    assert _meals_inserted(rec) == []
    assert r.json()["meal_id"] is None


def test_extraction_error_logs_nothing(harness):
    # Extractor raises → no foods → no meal (simple gate; user re-states on a
    # rare outage rather than us writing a junk row).
    rec, monkeypatch = harness

    def _boom(msg):
        raise RuntimeError("llm down")

    monkeypatch.setattr(c.ai_extraction, "extract_meal", _boom)
    r = TestClient(app).post("/api/chat", json={"message": "I had a sandwich"})
    assert r.status_code == 200
    assert _meals_inserted(rec) == []
    assert r.json()["meal_id"] is None


def test_keyword_offtopic_short_circuits_before_db(harness):
    # Obvious off-topic is caught by the cheap pre-filter — extractor never runs.
    rec, monkeypatch = harness

    def _should_not_run(msg):
        raise AssertionError("extract_meal must not be called for off-topic")

    monkeypatch.setattr(c.ai_extraction, "extract_meal", _should_not_run)
    r = TestClient(app).post("/api/chat", json={"message": "what's the weather today?"})
    assert r.status_code == 200
    assert _meals_inserted(rec) == []
    assert r.json()["meal_id"] is None
    assert "can't help" in r.json()["reply"].lower()


def test_first_turn_rated_symptom_logs_a_symptom_not_a_meal(harness):
    # #16: a fresh symptom-only turn with a severity logs a symptom (no meal).
    rec, monkeypatch = harness
    monkeypatch.setattr(
        c.ai_extraction,
        "extract_meal",
        lambda msg: {"foods": [], "normalized_description": "", "inferred_meal_type": "other"},
    )
    monkeypatch.setattr(
        c.ai_extraction,
        "extract_symptoms",
        lambda text: [{"symptom_type": "bloating", "severity": 7}],
    )
    r = TestClient(app).post("/api/chat", json={"message": "I'm bloated, about a 7"})
    assert r.status_code == 200
    assert _meals_inserted(rec) == []
    syms = _symptoms_inserted(rec)
    assert len(syms) == 1 and syms[0]["symptom_type"] == "bloating" and syms[0]["severity"] == 7
    assert r.json()["meal_id"] is None


def test_first_turn_unrated_symptom_waits_logs_nothing(harness):
    # Symptom with no severity yet → don't log; the LLM asks for a 1-10 rating,
    # and the next turn (with history) logs it once with the number.
    rec, monkeypatch = harness
    monkeypatch.setattr(
        c.ai_extraction,
        "extract_meal",
        lambda msg: {"foods": [], "normalized_description": "", "inferred_meal_type": "other"},
    )
    monkeypatch.setattr(
        c.ai_extraction,
        "extract_symptoms",
        lambda text: [{"symptom_type": "bloating", "severity": None}],
    )
    r = TestClient(app).post("/api/chat", json={"message": "I'm really bloated today"})
    assert r.status_code == 200
    assert _meals_inserted(rec) == []
    assert _symptoms_inserted(rec) == []
    assert r.json()["meal_id"] is None


def test_followup_turn_rated_symptom_inserts_via_helper(harness):
    # #16 refactor coverage: the meal_id follow-up branch is the path that was
    # changed to share _insert_ready_symptoms. A rated symptom on a follow-up
    # turn must insert a symptom row (and never re-extract/overwrite the meal).
    rec, monkeypatch = harness

    def _meal_must_not_run(msg):
        raise AssertionError("extract_meal must not run when a symptom is rated")

    monkeypatch.setattr(c.ai_extraction, "extract_meal", _meal_must_not_run)
    monkeypatch.setattr(
        c.ai_extraction,
        "extract_symptoms",
        lambda text: [{"symptom_type": "bloating", "severity": 7}],
    )
    r = TestClient(app).post(
        "/api/chat",
        json={
            "message": "about a 7",
            "meal_id": "M1",
            "history": [
                {"role": "user", "content": "I feel bloated"},
                {"role": "assistant", "content": "On a scale of 1-10, how bad?"},
            ],
        },
    )
    assert r.status_code == 200
    assert _meals_inserted(rec) == []
    syms = _symptoms_inserted(rec)
    assert len(syms) == 1 and syms[0]["symptom_type"] == "bloating" and syms[0]["severity"] == 7


def test_meal_turn_does_not_extract_symptoms(harness):
    # When food IS logged we stay a meal turn — no extra symptom call/insert.
    rec, monkeypatch = harness
    monkeypatch.setattr(
        c.ai_extraction,
        "extract_meal",
        lambda msg: {"foods": [{"name": "pizza"}], "normalized_description": "pizza", "inferred_meal_type": "dinner"},
    )

    def _symptoms_should_not_run(text):
        raise AssertionError("symptom extraction must not run on a meal turn")

    monkeypatch.setattr(c.ai_extraction, "extract_symptoms", _symptoms_should_not_run)
    r = TestClient(app).post("/api/chat", json={"message": "I had pizza"})
    assert r.status_code == 200
    assert len(_meals_inserted(rec)) == 1
    assert _symptoms_inserted(rec) == []
