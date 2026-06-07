"""Unit tests for /api/transcribe — no network, no real JWT.

Mocks the outbound Google STT httpx call so transcript parsing, auth, the
missing-key guard, and upstream-error mapping are tested deterministically.
"""
import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.auth import get_current_user
from app.routers import transcribe as t


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(t, "_API_KEY", "test-key")
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1"}
    yield TestClient(app)
    app.dependency_overrides.clear()


class _FakeResp:
    def __init__(self, payload):
        self._payload = payload

    def raise_for_status(self):
        pass

    def json(self):
        return self._payload


def _patch_google(monkeypatch, payload):
    class _FakeAsyncClient:
        def __init__(self, *a, **k):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *a):
            return False

        async def post(self, *a, **k):
            return _FakeResp(payload)

    monkeypatch.setattr(t.httpx, "AsyncClient", _FakeAsyncClient)


def test_returns_transcript(client, monkeypatch):
    _patch_google(monkeypatch, {
        "results": [{"alternatives": [{"transcript": "I had an IQ bar"}]}]
    })
    r = client.post("/api/transcribe", json={"audio": "QUJD", "sample_rate": 16000})
    assert r.status_code == 200
    assert r.json()["transcript"] == "I had an IQ bar"


def test_concatenates_multiple_results(client, monkeypatch):
    _patch_google(monkeypatch, {"results": [
        {"alternatives": [{"transcript": "I had a turkey sandwich"}]},
        {"alternatives": [{"transcript": "and a coffee"}]},
    ]})
    r = client.post("/api/transcribe", json={"audio": "QUJD"})
    assert r.json()["transcript"] == "I had a turkey sandwich and a coffee"


def test_empty_audio_short_circuits(client):
    r = client.post("/api/transcribe", json={"audio": ""})
    assert r.status_code == 200
    assert r.json()["transcript"] == ""


def test_missing_key_returns_503(client, monkeypatch):
    monkeypatch.setattr(t, "_API_KEY", "")
    r = client.post("/api/transcribe", json={"audio": "QUJD"})
    assert r.status_code == 503


def test_upstream_error_maps_to_502(client, monkeypatch):
    class _BoomClient:
        def __init__(self, *a, **k):
            pass

        async def __aenter__(self):
            return self

        async def __aexit__(self, *a):
            return False

        async def post(self, *a, **k):
            raise t.httpx.ConnectError("boom")

    monkeypatch.setattr(t.httpx, "AsyncClient", _BoomClient)
    r = client.post("/api/transcribe", json={"audio": "QUJD"})
    assert r.status_code == 502


def test_requires_auth():
    # No dependency override → real get_current_user rejects.
    c = TestClient(app)
    r = c.post("/api/transcribe", json={"audio": "QUJD"})
    assert r.status_code in (401, 403)
