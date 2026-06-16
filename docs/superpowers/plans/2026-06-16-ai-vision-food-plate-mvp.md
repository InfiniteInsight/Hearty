# AI Vision — Food-Plate MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user upload a photo of a plate of food and get back a list of identified food items (name + portion + confidence), processed asynchronously and stored on `food_log_photos`, using Claude vision via litellm — no Google Cloud Vision, no `anthropic` SDK, no Spec 07 dependency.

**Architecture:** A thin `photo_store` (Supabase Storage bucket `food-photos` + `food_log_photos` table) · a pure `food_plate` processor that calls `litellm.completion` with a multimodal (image+text) message and parses the JSON food array · a `process_photo` background worker that downloads the image, dispatches by `photo_type`, and writes `extracted_data`/`processing_status` with a cache-check · the `POST /api/photos`, `GET /api/photos/{id}/status`, `POST /api/photos/{id}/retry` endpoints (replacing the current 501 stubs) wired to FastAPI `BackgroundTasks` · Flutter capture→upload→poll→show as a text-first contract task.

**Scope (decided):** Food-plate type only. Barcode / nutrition-label / food-label processors are out of scope (they depend on Spec 07 Food Intelligence and/or a label-OCR pass) — the dispatcher fails them cleanly as "not yet supported" so they're trivial to add later. Label OCR, when built, will also use Claude-native vision (decided), not GCV.

**Tech Stack:** FastAPI + Supabase (python client, service key) + litellm (multimodal). Spec: `docs/superpowers/specs/2026-05-04-hearty-06-ai-vision.md`. Backend test runner: `cd hearty-api && set -a && . ../.env && set +a && .venv/bin/python -m pytest <file> -v`.

**Verified codebase facts (do not re-derive):**
- Table `food_log_photos` columns: `id` (uuid pk), `meal_id` (nullable fk), `user_id`, `photo_url` (text), `photo_type` (nullable, CHECK in food_plate/barcode/nutrition_label/food_label), `processing_status` (CHECK pending/processing/complete/failed/needs_input, default 'pending'), `extracted_data` (jsonb), `created_at`.
- Storage bucket: **`food-photos`** (private; RLS scoped to `{user_id}/...`; the service-key client bypasses RLS).
- Schemas already exist in `hearty-api/app/models/schemas.py`: `PhotoType = Literal["food_plate","barcode","nutrition_label","food_label"]`, `PhotoStatus = Literal["pending","processing","complete","failed"]`, `PhotoUploadResponse{id,type,status,meal_id?,message}`, `PhotoStatusResponse{id,type,status,result?,error?}`.
- LLM access pattern (see `app/services/ai_extraction.py`): `litellm.completion(model=os.environ.get("LLM_MODEL","claude-sonnet-4-6"), messages=[...], api_base=os.environ.get("LLM_BASE_URL") or None)`. Configured `LLM_MODEL=claude-haiku-4-5-20251001` (multimodal-capable).
- Supabase client init pattern (e.g. `app/services/experiment_store.py`): `supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])`.
- The router stubs to replace are in `app/routers/photos.py` (currently raise 501). Router is already registered in `app/main.py`.

**Constants (module-level, env-overridable):** `VISION_MODEL = os.environ.get("VISION_MODEL") or os.environ.get("LLM_MODEL", "claude-sonnet-4-6")`, `PHOTO_BUCKET = "food-photos"`, `MAX_PHOTO_BYTES = 10*1024*1024`.

---

## File Structure

**Backend:**
- `hearty-api/app/services/photo_store.py` — Supabase Storage + `food_log_photos` thin layer.
- `hearty-api/app/services/food_plate.py` — pure food-plate vision processor (litellm multimodal).
- `hearty-api/app/services/photo_pipeline.py` — `process_photo` worker (download → dispatch → write status/result, with cache-check).
- `hearty-api/app/routers/photos.py` — replace 501 stubs with real endpoints.

**Flutter (contract, text-first):**
- `hearty_app/lib/core/api/hearty_api_client.dart` — `uploadFoodPhoto` + `fetchPhotoStatus`.
- `hearty_app/lib/core/api/models/photo_analysis.dart` — result model.
- `hearty_app/lib/features/...` — capture → upload → poll → show identified foods.

---

## Task 1: Photo store (Storage + table, thin)

**Files:**
- Create: `hearty-api/app/services/photo_store.py`
- Test: `hearty-api/tests/test_photo_store_unit.py`

- [ ] **Step 1: Write the failing test**

```python
from app.services import photo_store as ps


class _Result:
    def __init__(self, data): self.data = data


def test_create_row_inserts_processing(monkeypatch):
    rec = {}
    class _T:
        def insert(self, row): rec["row"] = row; return self
        def execute(self): return _Result([{**rec["row"], "id": "p1"}])
    monkeypatch.setattr(ps, "supabase", type("S", (), {"table": lambda s, n: _T()})())

    out = ps.create_row("u1", "p1", "u1/p1.jpg", "food_plate", meal_id=None)
    row = rec["row"]
    assert row["id"] == "p1" and row["user_id"] == "u1"
    assert row["photo_url"] == "u1/p1.jpg" and row["photo_type"] == "food_plate"
    assert row["processing_status"] == "processing"
    assert out["id"] == "p1"


def test_upload_bytes_targets_bucket_and_path(monkeypatch):
    rec = {}
    class _Bucket:
        def upload(self, path, file, file_options=None):
            rec["path"] = path; rec["file"] = file; rec["opts"] = file_options; return {}
    class _Storage:
        def from_(self, name): rec["bucket"] = name; return _Bucket()
    monkeypatch.setattr(ps, "supabase", type("S", (), {"storage": _Storage()})())

    ps.upload_bytes("u1/p1.jpg", b"\xff\xd8\xff", "image/jpeg")
    assert rec["bucket"] == "food-photos"
    assert rec["path"] == "u1/p1.jpg"
    assert rec["file"] == b"\xff\xd8\xff"
    assert rec["opts"]["content-type"] == "image/jpeg"


def test_set_result_writes_complete(monkeypatch):
    rec = {}
    class _T:
        def update(self, vals): rec["vals"] = vals; return self
        def eq(self, *a, **k): return self
        def execute(self): return _Result([{"id": "p1"}])
    monkeypatch.setattr(ps, "supabase", type("S", (), {"table": lambda s, n: _T()})())
    ps.set_result("u1", "p1", {"foods": []})
    assert rec["vals"]["processing_status"] == "complete"
    assert rec["vals"]["extracted_data"] == {"foods": []}


def test_get_photo_user_scoped(monkeypatch):
    rec = {}
    class _T:
        def select(self, *a, **k): return self
        def eq(self, col, val): rec.setdefault("eqs", []).append((col, val)); return self
        def execute(self): return _Result([{"id": "p1", "user_id": "u1"}])
    monkeypatch.setattr(ps, "supabase", type("S", (), {"table": lambda s, n: _T()})())
    out = ps.get_photo("u1", "p1")
    assert out["id"] == "p1"
    assert ("user_id", "u1") in rec["eqs"] and ("id", "p1") in rec["eqs"]
```

- [ ] **Step 2: Run to confirm fail** — `...pytest tests/test_photo_store_unit.py -v` → module missing.

- [ ] **Step 3: Implement**

```python
"""Thin Supabase layer for food photos: Storage bucket + food_log_photos table.
Uses the service-key client (bypasses RLS) so every table read/write is manually
user-scoped. Storage paths are always {user_id}/{photo_id}.jpg."""

import os
from supabase import create_client

PHOTO_BUCKET = os.environ.get("PHOTO_BUCKET", "food-photos")
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


def storage_path(user_id: str, photo_id: str) -> str:
    return f"{user_id}/{photo_id}.jpg"


def upload_bytes(path: str, data: bytes, content_type: str) -> None:
    supabase.storage.from_(PHOTO_BUCKET).upload(
        path, data, {"content-type": content_type, "upsert": "true"})


def download_bytes(path: str) -> bytes:
    return supabase.storage.from_(PHOTO_BUCKET).download(path)


def create_row(user_id: str, photo_id: str, photo_url: str, photo_type: str,
               meal_id: str | None) -> dict:
    row = {
        "id": photo_id, "user_id": user_id, "meal_id": meal_id,
        "photo_url": photo_url, "photo_type": photo_type,
        "processing_status": "processing",
    }
    return supabase.table("food_log_photos").insert(row).execute().data[0]


def get_photo(user_id: str, photo_id: str) -> dict | None:
    rows = (supabase.table("food_log_photos").select("*")
            .eq("user_id", user_id).eq("id", photo_id).execute()).data or []
    return rows[0] if rows else None


def set_processing(user_id: str, photo_id: str) -> None:
    supabase.table("food_log_photos").update({"processing_status": "processing",
        "extracted_data": None}).eq("user_id", user_id).eq("id", photo_id).execute()


def set_result(user_id: str, photo_id: str, extracted_data: dict) -> None:
    supabase.table("food_log_photos").update(
        {"processing_status": "complete", "extracted_data": extracted_data}) \
        .eq("user_id", user_id).eq("id", photo_id).execute()


def set_failed(user_id: str, photo_id: str, message: str) -> None:
    supabase.table("food_log_photos").update(
        {"processing_status": "failed", "extracted_data": {"error": message}}) \
        .eq("user_id", user_id).eq("id", photo_id).execute()
```

> **Note:** verify the installed `supabase-py` storage `.upload(path, file, file_options)` signature (it varies slightly by version — some accept `file_options` keys as strings only). If `download`/`upload` differ, adapt the two storage wrappers and note it; the table ops mirror `experiment_store.py` and are stable.

- [ ] **Step 4: Run to confirm pass** (4 tests).

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/photo_store.py hearty-api/tests/test_photo_store_unit.py
git commit -m "feat(vision): photo_store (food-photos bucket + food_log_photos table)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Food-plate vision processor (pure, litellm multimodal)

**Files:**
- Create: `hearty-api/app/services/food_plate.py`
- Test: `hearty-api/tests/test_food_plate_unit.py`

The processor is pure w.r.t. the LLM: `litellm.completion` is the only side-effecting call and is patched in tests. It takes raw image bytes, sends a multimodal message, and returns `{"foods": [...], "source": "food_plate_vision"}`.

- [ ] **Step 1: Write the failing test**

```python
import json
from types import SimpleNamespace
from unittest.mock import patch
from app.services import food_plate as fp


def _fake(content):
    return SimpleNamespace(choices=[SimpleNamespace(
        message=SimpleNamespace(content=content))])


def test_parses_food_array():
    arr = [{"name": "grilled salmon", "portion": "1 fillet", "confidence": 0.85},
           {"name": "broccoli", "portion": "small side", "confidence": 0.9}]
    with patch.object(fp.litellm, "completion", return_value=_fake(json.dumps(arr))):
        out = fp.analyze_food_plate(b"\xff\xd8\xff", "image/jpeg")
    assert out["source"] == "food_plate_vision"
    assert out["foods"][0]["name"] == "grilled salmon"
    assert out["foods"][1]["confidence"] == 0.9


def test_strips_code_fence_and_handles_empty():
    with patch.object(fp.litellm, "completion", return_value=_fake("```json\n[]\n```")):
        out = fp.analyze_food_plate(b"\xff\xd8\xff", "image/jpeg")
    assert out["foods"] == []


def test_sends_multimodal_image_content():
    captured = {}
    def _spy(**kwargs):
        captured.update(kwargs)
        return _fake("[]")
    with patch.object(fp.litellm, "completion", side_effect=_spy):
        fp.analyze_food_plate(b"\xff\xd8\xff", "image/png")
    content = captured["messages"][0]["content"]
    kinds = [p["type"] for p in content]
    assert "text" in kinds and "image_url" in kinds
    img = next(p for p in content if p["type"] == "image_url")
    assert img["image_url"]["url"].startswith("data:image/png;base64,")


def test_non_json_response_raises_valueerror():
    import pytest
    with patch.object(fp.litellm, "completion", return_value=_fake("sorry, no")):
        with pytest.raises(ValueError):
            fp.analyze_food_plate(b"\xff\xd8\xff", "image/jpeg")
```

- [ ] **Step 2: Run to confirm fail.**

- [ ] **Step 3: Implement**

```python
"""Food-plate vision processor: send a plate photo to Claude (via litellm,
multimodal) and parse the identified-foods JSON array. Pure except for the
litellm call (patched in tests). Identification only — no calorie/macro data
(portion estimates from photos are unreliable; nutrition comes from Spec 07)."""

import base64
import json
import os

import litellm

VISION_MODEL = os.environ.get("VISION_MODEL") or os.environ.get(
    "LLM_MODEL", "claude-sonnet-4-6")

FOOD_PLATE_PROMPT = (
    "You are analyzing a photo of food. Identify every distinct food item "
    "visible on the plate or in the image. For each item, return a JSON array "
    "with this structure:\n"
    '[{"name": "common food name", "portion": "approximate portion description, '
    "e.g. 'approximately 1 fillet' or 'small side portion'\", "
    '"confidence": float between 0 and 1}]\n'
    "If no food is visible, return an empty array. If the items are "
    'indistinguishable (e.g. a stew), return [{"name": "mixed dish", "portion": '
    '"unknown", "confidence": 0.2}]. Do not fabricate ingredients. '
    "Reply with only the JSON array, no prose."
)


def _strip_code_fence(text: str) -> str:
    t = text.strip()
    if t.startswith("```"):
        t = t.split("\n", 1)[1] if "\n" in t else t
        if t.endswith("```"):
            t = t.rsplit("```", 1)[0]
    return t.strip()


def analyze_food_plate(image_bytes: bytes, content_type: str) -> dict:
    b64 = base64.b64encode(image_bytes).decode()
    messages = [{"role": "user", "content": [
        {"type": "text", "text": FOOD_PLATE_PROMPT},
        {"type": "image_url",
         "image_url": {"url": f"data:{content_type};base64,{b64}"}},
    ]}]
    response = litellm.completion(
        model=VISION_MODEL, messages=messages,
        api_base=os.environ.get("LLM_BASE_URL") or None,
    )
    content = _strip_code_fence(response.choices[0].message.content)
    try:
        foods = json.loads(content)
    except json.JSONDecodeError as e:
        raise ValueError(f"Vision returned non-JSON response: {content}") from e
    if not isinstance(foods, list):
        foods = foods.get("foods", []) if isinstance(foods, dict) else []
    return {"foods": foods, "source": "food_plate_vision"}
```

- [ ] **Step 4: Run to confirm pass** (4 tests).

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/food_plate.py hearty-api/tests/test_food_plate_unit.py
git commit -m "feat(vision): food-plate processor (Claude vision via litellm)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: process_photo worker (dispatch + status + cache)

**Files:**
- Create: `hearty-api/app/services/photo_pipeline.py`
- Test: `hearty-api/tests/test_photo_pipeline_unit.py`

`process_photo` loads the row (user-scoped), returns early if already complete with data (cache), downloads the image, dispatches by `photo_type`, writes result or failure. Only `food_plate` is supported in this MVP; other types fail cleanly.

- [ ] **Step 1: Write the failing test**

```python
from app.services import photo_pipeline as pp


def test_food_plate_happy_path(monkeypatch):
    rec = {}
    monkeypatch.setattr(pp.photo_store, "get_photo", lambda u, p: {
        "id": p, "user_id": u, "photo_url": "u1/p1.jpg",
        "photo_type": "food_plate", "processing_status": "processing",
        "extracted_data": None})
    monkeypatch.setattr(pp.photo_store, "download_bytes", lambda path: b"img")
    monkeypatch.setattr(pp.food_plate, "analyze_food_plate",
                        lambda data, ct: {"foods": [{"name": "egg"}], "source": "food_plate_vision"})
    monkeypatch.setattr(pp.photo_store, "set_result",
                        lambda u, p, d: rec.update({"result": d}))
    monkeypatch.setattr(pp.photo_store, "set_failed",
                        lambda u, p, m: rec.update({"failed": m}))
    pp.process_photo("p1", "u1")
    assert rec["result"]["foods"][0]["name"] == "egg"
    assert "failed" not in rec


def test_cache_short_circuits_when_already_complete(monkeypatch):
    calls = {"download": 0}
    monkeypatch.setattr(pp.photo_store, "get_photo", lambda u, p: {
        "id": p, "user_id": u, "photo_url": "u1/p1.jpg", "photo_type": "food_plate",
        "processing_status": "complete", "extracted_data": {"foods": []}})
    monkeypatch.setattr(pp.photo_store, "download_bytes",
                        lambda path: calls.__setitem__("download", calls["download"] + 1) or b"x")
    monkeypatch.setattr(pp.photo_store, "set_result", lambda u, p, d: None)
    pp.process_photo("p1", "u1")
    assert calls["download"] == 0  # no re-download, no re-analyze


def test_unsupported_type_fails_cleanly(monkeypatch):
    rec = {}
    monkeypatch.setattr(pp.photo_store, "get_photo", lambda u, p: {
        "id": p, "user_id": u, "photo_url": "u1/p1.jpg", "photo_type": "barcode",
        "processing_status": "processing", "extracted_data": None})
    monkeypatch.setattr(pp.photo_store, "download_bytes", lambda path: b"img")
    monkeypatch.setattr(pp.photo_store, "set_failed", lambda u, p, m: rec.update({"failed": m}))
    monkeypatch.setattr(pp.photo_store, "set_result", lambda u, p, d: rec.update({"result": d}))
    pp.process_photo("p1", "u1")
    assert "not yet supported" in rec["failed"]
    assert "result" not in rec


def test_processor_exception_sets_failed(monkeypatch):
    rec = {}
    monkeypatch.setattr(pp.photo_store, "get_photo", lambda u, p: {
        "id": p, "user_id": u, "photo_url": "u1/p1.jpg", "photo_type": "food_plate",
        "processing_status": "processing", "extracted_data": None})
    monkeypatch.setattr(pp.photo_store, "download_bytes", lambda path: b"img")
    def _boom(data, ct): raise RuntimeError("vision down")
    monkeypatch.setattr(pp.food_plate, "analyze_food_plate", _boom)
    monkeypatch.setattr(pp.photo_store, "set_failed", lambda u, p, m: rec.update({"failed": m}))
    pp.process_photo("p1", "u1")
    assert "failed" in rec


def test_missing_row_is_noop(monkeypatch):
    monkeypatch.setattr(pp.photo_store, "get_photo", lambda u, p: None)
    # must not raise
    pp.process_photo("nope", "u1")
```

- [ ] **Step 2: Run to confirm fail.**

- [ ] **Step 3: Implement**

```python
"""Background worker: turn an uploaded photo into structured extracted_data.
Dispatches by photo_type; only food_plate is supported in the MVP. All failures
are non-blocking and recorded as processing_status='failed' (the meal log is
never affected). Guessed content-type is fine for the data URL — Claude sniffs
the actual image."""

import logging

from app.services import photo_store, food_plate

logger = logging.getLogger(__name__)

_CONTENT_TYPE = "image/jpeg"  # stored objects are normalized to .jpg paths


def process_photo(photo_id: str, user_id: str) -> None:
    row = photo_store.get_photo(user_id, photo_id)
    if not row:
        return
    # Cache: never re-process an already-complete photo (Claude calls cost money).
    if row.get("processing_status") == "complete" and row.get("extracted_data"):
        return
    try:
        image = photo_store.download_bytes(row["photo_url"])
        photo_type = row.get("photo_type") or "food_plate"
        if photo_type == "food_plate":
            result = food_plate.analyze_food_plate(image, _CONTENT_TYPE)
        else:
            photo_store.set_failed(
                user_id, photo_id, f"Photo type '{photo_type}' not yet supported")
            return
        photo_store.set_result(user_id, photo_id, result)
    except Exception as e:  # non-blocking: record and move on
        logger.warning("process_photo failed for %s: %s", photo_id, e)
        photo_store.set_failed(
            user_id, photo_id, "Vision processing failed — please try again")
```

- [ ] **Step 4: Run to confirm pass** (5 tests).

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/photo_pipeline.py hearty-api/tests/test_photo_pipeline_unit.py
git commit -m "feat(vision): process_photo worker (dispatch + cache + non-blocking failure)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Endpoints (upload / status / retry)

**Files:**
- Modify: `hearty-api/app/routers/photos.py` (replace the 501 stubs)
- Test: `hearty-api/tests/test_photos_endpoint_unit.py`

Replace the stubs. `POST /api/photos` validates type+size, uploads bytes, creates the row as `processing`, enqueues `process_photo` via `BackgroundTasks`, returns `PhotoUploadResponse`. `GET /api/photos/{id}/status` maps the row → `PhotoStatusResponse`. `POST /api/photos/{id}/retry` resets to processing and re-enqueues.

- [ ] **Step 1: Write the failing tests**

```python
import io
from fastapi.testclient import TestClient
from app.main import app
from app.auth import get_current_user
from app.routers import photos as ph


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
        "id": "p1", "photo_type": "food_plate", "processing_status": "complete",
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
    monkeypatch.setattr(ph.photo_store, "get_photo", lambda u, p: {"id": "p1", "photo_type": "food_plate"})
    monkeypatch.setattr(ph.photo_store, "set_processing", lambda u, p: rec.update({"reset": p}))
    monkeypatch.setattr(ph.photo_pipeline, "process_photo", lambda pid, uid: rec.update({"enqueued": pid}))
    client = TestClient(app)
    r = client.post("/api/photos/p1/retry")
    assert r.status_code == 202
    assert rec["reset"] == "p1" and rec["enqueued"] == "p1"
    app.dependency_overrides.clear()
```

- [ ] **Step 2: Run to confirm fail.**

- [ ] **Step 3: Implement** (replace the file body)

```python
# app/routers/photos.py
# AI Vision food-plate MVP (Spec 06). Async: upload → store → BackgroundTasks
# worker → poll status. Only food_plate is processed; other types fail cleanly.
import os
from uuid import uuid4

from fastapi import (APIRouter, Depends, HTTPException, UploadFile, File, Form,
                     BackgroundTasks)

from app.auth import get_current_user
from app.models.schemas import PhotoUploadResponse, PhotoStatusResponse
from app.services import photo_store, photo_pipeline

router = APIRouter()

MAX_PHOTO_BYTES = int(os.environ.get("MAX_PHOTO_BYTES", str(10 * 1024 * 1024)))
_ALLOWED_TYPES = {"image/jpeg", "image/png"}
_VALID_PHOTO_TYPES = {"food_plate", "barcode", "nutrition_label", "food_label"}


@router.post("/api/photos", status_code=202)
async def upload_photo(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    type: str = Form("food_plate"),
    meal_id: str | None = Form(None),
    user=Depends(get_current_user),
) -> PhotoUploadResponse:
    if file.content_type not in _ALLOWED_TYPES:
        raise HTTPException(status_code=400,
            detail="Unsupported file type — please use JPEG or PNG")
    if type not in _VALID_PHOTO_TYPES:
        raise HTTPException(status_code=400, detail="Invalid photo type")
    data = await file.read()
    if len(data) > MAX_PHOTO_BYTES:
        raise HTTPException(status_code=400, detail="Image too large (max 10 MB)")
    if not data:
        raise HTTPException(status_code=400, detail="Empty file")

    user_id = user["id"]
    photo_id = str(uuid4())
    path = photo_store.storage_path(user_id, photo_id)
    photo_store.upload_bytes(path, data, file.content_type)
    photo_store.create_row(user_id, photo_id, path, type, meal_id)
    background_tasks.add_task(photo_pipeline.process_photo, photo_id, user_id)

    return PhotoUploadResponse(id=photo_id, type=type, status="processing",
                               meal_id=meal_id, message="Processing your photo…")


@router.get("/api/photos/{photo_id}/status")
async def get_photo_status(photo_id: str,
                           user=Depends(get_current_user)) -> PhotoStatusResponse:
    row = photo_store.get_photo(user["id"], photo_id)
    if not row:
        raise HTTPException(status_code=404, detail="Photo not found")
    data = row.get("extracted_data") or {}
    status = row["processing_status"]
    error = data.get("error") if status == "failed" else None
    result = data if status == "complete" else None
    return PhotoStatusResponse(id=row["id"], type=row.get("photo_type") or "food_plate",
                               status=status, result=result, error=error)


@router.post("/api/photos/{photo_id}/retry", status_code=202)
async def retry_photo(photo_id: str, background_tasks: BackgroundTasks,
                      user=Depends(get_current_user)) -> PhotoStatusResponse:
    user_id = user["id"]
    row = photo_store.get_photo(user_id, photo_id)
    if not row:
        raise HTTPException(status_code=404, detail="Photo not found")
    photo_store.set_processing(user_id, photo_id)
    background_tasks.add_task(photo_pipeline.process_photo, photo_id, user_id)
    return PhotoStatusResponse(id=photo_id, type=row.get("photo_type") or "food_plate",
                               status="processing", result=None, error=None)
```

> The current stub imports `PhotoUploadResponse, PhotoStatusResponse` already; keep `app/main.py`'s existing `photos.router` registration (no change needed). `PhotoStatus` Literal lacks `needs_input`, which the MVP never emits — fine.

- [ ] **Step 4: Run** the endpoint tests, then the full suite excluding the live test:
`cd hearty-api && set -a && . ../.env && set +a && .venv/bin/python -m pytest --ignore=tests/test_api.py -q` — all pass.

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/routers/photos.py hearty-api/tests/test_photos_endpoint_unit.py
git commit -m "feat(vision): photo endpoints (upload/status/retry) replacing 501 stubs

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5 (CONTRACT — text-first): Flutter capture → upload → poll → show foods

**Files:**
- Create: `hearty_app/lib/core/api/models/photo_analysis.dart` — `PhotoAnalysis` (id, type, status, `List<IdentifiedFood> foods`, error?) + `IdentifiedFood` (name, portion?, confidence?) with `fromJson`. `foods` parsed from `result.foods` (empty when result null).
- Modify: `hearty_app/lib/core/api/hearty_api_client.dart` — mirroring the existing `_call`/`_dio` pattern:
  - `Future<String> uploadFoodPhoto({required List<int> bytes, required String filename, String type = 'food_plate', String? mealId})` → multipart POST `/api/photos` (`MultipartFile.fromBytes`, field `file`; form fields `type`, `meal_id`); returns the new photo `id`.
  - `Future<PhotoAnalysis> fetchPhotoStatus(String id)` → GET `/api/photos/{id}/status`.
  - `Future<void> retryPhoto(String id)` → POST `/api/photos/{id}/retry`.
- Modify/Create UI under `hearty_app/lib/features/...` — wire the existing camera/image_picker capture so that, after a plate photo is taken, the app uploads it, polls `fetchPhotoStatus` (e.g. every 2s, ~30s cap) until `complete`/`failed`, and shows the identified foods (each `name` + `portion`) with a "looks right?"/manual-edit fallback consistent with the existing meal-logging UX. On `failed`, show the inline error + manual entry. (Find the existing photo/camera entry point — the Android plan added `image_picker`; mirror its surface.)
- Test: `hearty_app/test/core/api/hearty_api_client_photos_test.dart` (interceptor-based, mirror existing client tests): uploadFoodPhoto posts multipart to `/api/photos` and returns the id; fetchPhotoStatus parses status + foods from `result.foods`. Widget test for the result view: a `complete` analysis renders the food names; a `failed` analysis shows the error + manual-entry affordance.

- [ ] Implement, `flutter test test/core/api/ test/features/...`, `flutter analyze lib/`, commit.

> **GATE:** the live capture→upload→Claude round-trip is **device-verified** (camera + real vision call). Contract + widget tests + analyze are the bar here; device steps are in the Device-verification section.

---

## Device verification (after the tasks)

- Capture/pick a clear plate photo → upload → within ~30s the status flips to `complete` and identified foods appear; portions read sensibly; confidences present.
- Re-fetch status of a completed photo → cached `extracted_data` returned (no second Claude call — check the API log shows no new vision request).
- No-food image → `complete` with an empty foods list and the "no foods detected" affordance.
- A non-JPEG/PNG or >10 MB upload → 400 with the right message; meal logging still works.
- Retry on a `failed` photo → re-processes and resolves.

---

## Self-review

- **Spec coverage (MVP slice):** upload + Supabase Storage (`food-photos`) + `food_log_photos` row (T1) · food-plate Claude-vision identification with empty/mixed handling (T2) · async `BackgroundTasks` worker with dispatch + 30s-irrelevant non-blocking failure + cost-control caching (T3) · `POST /api/photos`, `GET /status`, `POST /retry` with type/size validation and the spec's error messages (T4) · Flutter capture→upload→poll→show (T5). Out-of-scope-by-decision: barcode, nutrition-label, food-label processors and Spec 07 nutrition forwarding (dispatcher fails non-food_plate cleanly so they slot in later). GCV dropped in favor of Claude-native vision (decided).
- **Drift resolved vs the 2026-05-04 spec:** litellm (not `anthropic` SDK); bucket `food-photos` (not `photos`); columns `id`/`photo_url`/`processing_status`/`extracted_data` (not `photo_id`/`storage_path`/`status`); error state `failed` (not `error`/`timeout`); no `needs_input` in the MVP. All reflected in the code above.
- **Placeholders:** backend tasks (1–4) carry full code; Flutter (T5) is a contract task with exact method shapes, fields, endpoints, and test targets (the established pattern for device/camera-dependent UI).
- **Type/name consistency:** `analyze_food_plate(bytes, content_type)->{"foods","source"}` (T2) used in T3; `photo_store` fns (T1) used in T3+T4; `process_photo(photo_id, user_id)` (T3) enqueued in T4; `PhotoUploadResponse`/`PhotoStatusResponse`/`PhotoType`/`PhotoStatus` (existing) used in T4; the Dart `PhotoAnalysis.foods` (T5) reads `result.foods` produced by T2/T4.
- **Security:** service-key client bypasses RLS, so every `photo_store` table read/write is manually `.eq("user_id", ...)`-scoped (T1) and storage paths are `{user_id}/...`; endpoints derive `user_id` only from the auth dependency, never the client.
- **Risk:** the `litellm` multimodal call shape (`image_url` data URL) is the one external assumption — T2's `test_sends_multimodal_image_content` pins the request shape, and litellm normalizes `image_url` for Claude models; if the configured model/proxy rejects it, that surfaces immediately in device verification, not silently.
