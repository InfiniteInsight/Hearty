"""Tests for POST /api/symptoms/classify — the feeling-note sentiment gate.

The post-log "how are you feeling?" sheet calls this so positive/neutral notes
(e.g. "feeling good") are not recorded as symptoms.
"""

from fastapi.testclient import TestClient

from app.main import app
from app.auth import get_current_user
from app.routers import symptoms as sym


client = TestClient(app)


def _auth():
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}


def teardown_function():
    app.dependency_overrides.clear()


def test_classify_negative_note_is_symptom(monkeypatch):
    _auth()
    monkeypatch.setattr(sym.ai_extraction, "extract_symptoms",
                        lambda t: [{"symptom_type": "bloating", "severity": None}])
    r = client.post("/api/symptoms/classify", json={"text": "feeling bloated"})
    assert r.status_code == 200
    assert r.json() == {"is_symptom": True}


def test_classify_positive_note_is_not_symptom(monkeypatch):
    _auth()
    monkeypatch.setattr(sym.ai_extraction, "extract_symptoms", lambda t: [])
    r = client.post("/api/symptoms/classify", json={"text": "feeling good"})
    assert r.status_code == 200
    assert r.json() == {"is_symptom": False}


def test_classify_blank_text_short_circuits(monkeypatch):
    _auth()
    called = {"extract": False}
    monkeypatch.setattr(sym.ai_extraction, "extract_symptoms",
                        lambda t: called.__setitem__("extract", True) or [])
    r = client.post("/api/symptoms/classify", json={"text": "   "})
    assert r.status_code == 200
    assert r.json() == {"is_symptom": False}
    assert called["extract"] is False  # never calls the LLM for blank input


def test_classify_extraction_error_fails_to_not_symptom(monkeypatch):
    _auth()
    def _boom(t):
        raise RuntimeError("llm down")
    monkeypatch.setattr(sym.ai_extraction, "extract_symptoms", _boom)
    r = client.post("/api/symptoms/classify", json={"text": "feeling bloated"})
    assert r.status_code == 200
    assert r.json() == {"is_symptom": False}  # conservative: no false positive
