# Photo Retention Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Minimize raw-image retention — delete a food photo's image immediately after successful analysis, and purge failed/unprocessed images after a 24h grace window via a token-guarded cleanup endpoint.

**Architecture:** Add `image_purged_at` to `food_log_photos`. A `photo_store.purge_image` helper deletes the Storage object + stamps the row. `photo_pipeline.process_photo` calls it best-effort after a successful result. A token-guarded `POST /internal/photos/purge` endpoint (hit hourly by Cloud Scheduler at deploy time) purges anything past the retention window. Backend-only; the image is never served to clients, so no web/phone changes.

**Tech Stack:** FastAPI + Supabase (service key), pytest.

**Worktree:** `~/.config/superpowers/worktrees/photo-retention` (branch `photo-retention`, off master @ #16). Run all commands there.

**Spec:** `docs/superpowers/specs/2026-06-24-photo-retention-design.md`

**Backend test command (use everywhere below):**
```bash
cd hearty-api && SUPABASE_URL="http://localhost" SUPABASE_SERVICE_KEY="dummy-key" \
  /home/evan/projects/food-journal-assistant/hearty-api/.venv/bin/python -m pytest -k unit -q
```
Scope to one file by appending its path (still pass the env vars + same python).

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `supabase/migrations/20260624000000_photo_image_purged_at.sql` | add `image_purged_at` column | Create |
| `hearty-api/app/services/photo_store.py` | `purge_image`, `list_purgeable`, `_now_iso` | Modify |
| `hearty-api/tests/test_photo_store_unit.py` | tests for the two new store fns | Modify |
| `hearty-api/app/services/photo_pipeline.py` | best-effort delete-on-success | Modify |
| `hearty-api/tests/test_photo_pipeline_unit.py` | success purges / failure doesn't | Modify |
| `hearty-api/app/routers/internal.py` | `POST /internal/photos/purge` | Create |
| `hearty-api/tests/test_internal_endpoint_unit.py` | endpoint behavior + token | Create |
| `hearty-api/app/main.py` | mount internal router (ungated) | Modify |

---

## Task 1: Migration — `image_purged_at`

**Files:**
- Create: `supabase/migrations/20260624000000_photo_image_purged_at.sql`

- [ ] **Step 1: Write the migration**

```sql
-- Photo retention: timestamp when the raw image was deleted from Storage.
-- NULL = image still stored; non-null = purged (derived data is unaffected).
alter table food_log_photos add column if not exists image_purged_at timestamptz;
```

- [ ] **Step 2: Sanity check (no live apply)**

Run: `grep -c image_purged_at supabase/migrations/20260624000000_photo_image_purged_at.sql`
Expected: `1`. (Do NOT apply to any live DB — that's a consent-gated deploy step.)

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260624000000_photo_image_purged_at.sql
git commit -m "feat(api): food_log_photos.image_purged_at for photo retention"
```

---

## Task 2: `photo_store` — `purge_image` + `list_purgeable`

**Files:**
- Modify: `hearty-api/app/services/photo_store.py`
- Test: `hearty-api/tests/test_photo_store_unit.py`

- [ ] **Step 1: Write the failing tests** — append to `hearty-api/tests/test_photo_store_unit.py`:

```python
def test_purge_image_removes_object_and_stamps(monkeypatch):
    rec = {}
    class _Bucket:
        def remove(self, paths): rec["removed"] = paths; return {}
    class _Storage:
        def from_(self, name): rec["bucket"] = name; return _Bucket()
    class _T:
        def update(self, vals): rec["vals"] = vals; return self
        def eq(self, col, val): rec.setdefault("eqs", []).append((col, val)); return self
        def execute(self): return _Result([{"id": "p1"}])
    monkeypatch.setattr(ps, "supabase",
        type("S", (), {"storage": _Storage(), "table": lambda s, n: _T()})())
    ps.purge_image("u1", "p1", "u1/p1.jpg")
    assert rec["bucket"] == "food-photos"
    assert rec["removed"] == ["u1/p1.jpg"]
    assert rec["vals"]["image_purged_at"] is not None
    assert ("user_id", "u1") in rec["eqs"] and ("id", "p1") in rec["eqs"]


def test_list_purgeable_filters_null_and_cutoff(monkeypatch):
    rec = {}
    class _T:
        def select(self, cols): rec["cols"] = cols; return self
        def is_(self, col, val): rec["is"] = (col, val); return self
        def lt(self, col, val): rec["lt"] = (col, val); return self
        def execute(self): return _Result([{"id": "p1", "user_id": "u1", "photo_url": "u1/p1.jpg"}])
    monkeypatch.setattr(ps, "supabase", type("S", (), {"table": lambda s, n: _T()})())
    out = ps.list_purgeable("2026-06-23T00:00:00+00:00")
    assert out[0]["id"] == "p1"
    assert rec["is"] == ("image_purged_at", "null")
    assert rec["lt"] == ("created_at", "2026-06-23T00:00:00+00:00")
    assert rec["cols"] == "id,user_id,photo_url"
```

- [ ] **Step 2: Run to verify they fail**

Run (scoped): `... -m pytest tests/test_photo_store_unit.py -q`
Expected: FAIL — `purge_image` / `list_purgeable` not defined.

- [ ] **Step 3: Implement in `photo_store.py`** — add the `datetime` import at the top and these functions (after `download_bytes`):

```python
from datetime import datetime, timezone


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def purge_image(user_id: str, photo_id: str, path: str) -> None:
    """Delete the raw image from Storage and stamp the row purged. Storage
    remove is idempotent on a missing key, so this is safe to call repeatedly."""
    supabase.storage.from_(PHOTO_BUCKET).remove([path])
    supabase.table("food_log_photos").update({"image_purged_at": _now_iso()}) \
        .eq("user_id", user_id).eq("id", photo_id).execute()


def list_purgeable(cutoff_iso: str) -> list[dict]:
    """Photos whose raw image is still stored and uploaded before the cutoff."""
    return (
        supabase.table("food_log_photos")
        .select("id,user_id,photo_url")
        .is_("image_purged_at", "null")
        .lt("created_at", cutoff_iso)
        .execute()
    ).data or []
```

(Place the `from datetime import datetime, timezone` line with the other imports at the top of the file, not mid-file.)

- [ ] **Step 4: Run to verify they pass**

Run (scoped): `... -m pytest tests/test_photo_store_unit.py -q`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/photo_store.py hearty-api/tests/test_photo_store_unit.py
git commit -m "feat(api): photo_store purge_image + list_purgeable"
```

---

## Task 3: Delete-on-success in `photo_pipeline`

**Files:**
- Modify: `hearty-api/app/services/photo_pipeline.py`
- Test: `hearty-api/tests/test_photo_pipeline_unit.py`

Context: after a successful `set_result`, purge the image **best-effort** — a purge error must never flip an already-successful photo to `failed`, so it goes in its own nested try/except. The failure path must NOT purge (image stays for the retry window).

- [ ] **Step 1: Write the failing tests** — append to `hearty-api/tests/test_photo_pipeline_unit.py`:

```python
def test_success_purges_image(monkeypatch):
    rec = {}
    monkeypatch.setattr(pp.photo_store, "get_photo", lambda u, p: {
        "id": p, "user_id": u, "photo_url": "u1/p1.jpg",
        "photo_type": "food_plate", "processing_status": "processing",
        "extracted_data": None})
    monkeypatch.setattr(pp.photo_store, "download_bytes", lambda path: b"img")
    monkeypatch.setattr(pp.food_plate, "analyze_food_plate",
                        lambda data, ct: {"foods": [], "source": "food_plate_vision"})
    monkeypatch.setattr(pp.photo_store, "set_result", lambda u, p, d: None)
    monkeypatch.setattr(pp.photo_store, "purge_image",
                        lambda u, p, path: rec.update({"purged": (u, p, path)}))
    pp.process_photo("p1", "u1")
    assert rec["purged"] == ("u1", "p1", "u1/p1.jpg")


def test_failure_does_not_purge(monkeypatch):
    rec = {"purged": False}
    monkeypatch.setattr(pp.photo_store, "get_photo", lambda u, p: {
        "id": p, "user_id": u, "photo_url": "u1/p1.jpg", "photo_type": "food_plate",
        "processing_status": "processing", "extracted_data": None})
    monkeypatch.setattr(pp.photo_store, "download_bytes", lambda path: b"img")
    def _boom(data, ct): raise RuntimeError("vision down")
    monkeypatch.setattr(pp.food_plate, "analyze_food_plate", _boom)
    monkeypatch.setattr(pp.photo_store, "set_failed", lambda u, p, m: None)
    monkeypatch.setattr(pp.photo_store, "purge_image",
                        lambda u, p, path: rec.update({"purged": True}))
    pp.process_photo("p1", "u1")
    assert rec["purged"] is False


def test_purge_failure_does_not_mark_failed(monkeypatch):
    rec = {}
    monkeypatch.setattr(pp.photo_store, "get_photo", lambda u, p: {
        "id": p, "user_id": u, "photo_url": "u1/p1.jpg",
        "photo_type": "food_plate", "processing_status": "processing",
        "extracted_data": None})
    monkeypatch.setattr(pp.photo_store, "download_bytes", lambda path: b"img")
    monkeypatch.setattr(pp.food_plate, "analyze_food_plate",
                        lambda data, ct: {"foods": [], "source": "food_plate_vision"})
    monkeypatch.setattr(pp.photo_store, "set_result", lambda u, p, d: rec.update({"result": True}))
    monkeypatch.setattr(pp.photo_store, "set_failed", lambda u, p, m: rec.update({"failed": True}))
    def _boom(u, p, path): raise RuntimeError("storage down")
    monkeypatch.setattr(pp.photo_store, "purge_image", _boom)
    pp.process_photo("p1", "u1")
    assert rec.get("result") is True and "failed" not in rec  # success preserved
```

- [ ] **Step 2: Run to verify they fail**

Run (scoped): `... -m pytest tests/test_photo_pipeline_unit.py -q`
Expected: FAIL — `purge_image` not invoked (success test) / attribute error if monkeypatch target missing — note `purge_image` exists from Task 2, so the failing assertions are the un-wired pipeline call.

- [ ] **Step 3: Implement** — in `hearty-api/app/services/photo_pipeline.py`, replace the success line `photo_store.set_result(user_id, photo_id, result)` with:

```python
        photo_store.set_result(user_id, photo_id, result)
        # Retention: a successfully analyzed image has served its only purpose
        # (the pipeline read it once). Delete it now — best-effort, so a storage
        # hiccup never flips this already-successful photo to 'failed'; the
        # /internal/photos/purge backstop catches any miss.
        try:
            photo_store.purge_image(user_id, photo_id, row["photo_url"])
        except Exception as e:
            logger.warning("post-success image purge failed for %s: %s", photo_id, e)
```

(`logger` and `photo_store` are already imported in this file.)

- [ ] **Step 4: Run to verify they pass**

Run (scoped): `... -m pytest tests/test_photo_pipeline_unit.py -q`
Expected: PASS (new + existing pipeline tests).

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/photo_pipeline.py hearty-api/tests/test_photo_pipeline_unit.py
git commit -m "feat(api): delete photo image immediately after successful analysis"
```

---

## Task 4: Cleanup endpoint `POST /internal/photos/purge`

**Files:**
- Create: `hearty-api/app/routers/internal.py`
- Modify: `hearty-api/app/main.py`
- Test: `hearty-api/tests/test_internal_endpoint_unit.py`

- [ ] **Step 1: Write the failing tests** — create `hearty-api/tests/test_internal_endpoint_unit.py`:

```python
from fastapi.testclient import TestClient
from app.main import app
from app.routers import internal as it

PURGE = "/internal/photos/purge"


def test_rejects_when_token_unset(monkeypatch):
    monkeypatch.delenv("CLEANUP_TOKEN", raising=False)
    r = TestClient(app).post(PURGE, headers={"X-Cleanup-Token": "anything"})
    assert r.status_code == 403


def test_rejects_wrong_token(monkeypatch):
    monkeypatch.setenv("CLEANUP_TOKEN", "secret")
    r = TestClient(app).post(PURGE, headers={"X-Cleanup-Token": "nope"})
    assert r.status_code == 403


def test_purges_listed_rows(monkeypatch):
    monkeypatch.setenv("CLEANUP_TOKEN", "secret")
    monkeypatch.setenv("PHOTO_RETENTION_HOURS", "24")
    rows = [
        {"id": "p1", "user_id": "u1", "photo_url": "u1/p1.jpg"},
        {"id": "p2", "user_id": "u2", "photo_url": "u2/p2.jpg"},
    ]
    calls = []
    monkeypatch.setattr(it.photo_store, "list_purgeable", lambda cutoff: rows)
    monkeypatch.setattr(it.photo_store, "purge_image",
                        lambda u, p, path: calls.append((u, p, path)))
    r = TestClient(app).post(PURGE, headers={"X-Cleanup-Token": "secret"})
    assert r.status_code == 200
    assert r.json() == {"purged": 2, "scanned": 2}
    assert ("u1", "p1", "u1/p1.jpg") in calls and ("u2", "p2", "u2/p2.jpg") in calls


def test_per_row_failure_does_not_abort_batch(monkeypatch):
    monkeypatch.setenv("CLEANUP_TOKEN", "secret")
    rows = [{"id": "p1", "user_id": "u1", "photo_url": "u1/p1.jpg"},
            {"id": "p2", "user_id": "u2", "photo_url": "u2/p2.jpg"}]
    monkeypatch.setattr(it.photo_store, "list_purgeable", lambda cutoff: rows)
    def _purge(u, p, path):
        if p == "p1": raise RuntimeError("storage down")
    monkeypatch.setattr(it.photo_store, "purge_image", _purge)
    r = TestClient(app).post(PURGE, headers={"X-Cleanup-Token": "secret"})
    assert r.status_code == 200
    assert r.json() == {"purged": 1, "scanned": 2}
```

- [ ] **Step 2: Run to verify they fail**

Run (scoped): `... -m pytest tests/test_internal_endpoint_unit.py -q`
Expected: FAIL — route 404 (router not created/mounted).

- [ ] **Step 3: Create the router** — `hearty-api/app/routers/internal.py`:

```python
import logging
import os
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, HTTPException, Request

from app.services import photo_store

router = APIRouter()
logger = logging.getLogger(__name__)


@router.post("/internal/photos/purge")
async def purge_old_photos(request: Request) -> dict:
    """Delete raw images past the retention window. Token-guarded (fail-closed),
    no user auth — triggered by Cloud Scheduler. Derived data is untouched."""
    token = os.environ.get("CLEANUP_TOKEN", "")
    if not token or request.headers.get("X-Cleanup-Token") != token:
        raise HTTPException(status_code=403, detail="forbidden")
    hours = int(os.environ.get("PHOTO_RETENTION_HOURS", "24"))
    cutoff = (datetime.now(timezone.utc) - timedelta(hours=hours)).isoformat()
    rows = photo_store.list_purgeable(cutoff)
    purged = 0
    for r in rows:
        try:
            photo_store.purge_image(r["user_id"], r["id"], r["photo_url"])
            purged += 1
        except Exception as e:
            logger.warning("cleanup purge failed for %s: %s", r.get("id"), e)
    return {"purged": purged, "scanned": len(rows)}
```

- [ ] **Step 4: Mount it (ungated)** — in `hearty-api/app/main.py`, add `internal` to the routers import line and include it WITHOUT the license dependency (it's an ops endpoint, like `account`/`license`).

Change the import:
```python
from app.routers import auth_hooks, chat, meals, symptoms, trends, export, photos, preferences, transcribe, checkin, experiments, food, account, license, admin, internal
```
And add after `app.include_router(admin.router)`:
```python
app.include_router(internal.router)
```

- [ ] **Step 5: Run to verify they pass**

Run (scoped): `... -m pytest tests/test_internal_endpoint_unit.py -q`
Expected: PASS.

- [ ] **Step 6: Run the full unit suite**

Run the backend test command (no path). Expected: all unit tests pass (the autouse conftest license bypass is irrelevant to the ungated internal route).

- [ ] **Step 7: Commit**

```bash
git add hearty-api/app/routers/internal.py hearty-api/app/main.py hearty-api/tests/test_internal_endpoint_unit.py
git commit -m "feat(api): /internal/photos/purge cleanup endpoint (token-guarded)"
```

---

## Task 5: Deploy-time wiring (manual — at/after the Cloud Run deploy)

Not a code task. Requires the deployed Cloud Run URL + consent (sets prod env + a scheduled job).

- [ ] Apply the migration to prod: `supabase db push` (link + `SUPABASE_DB_PASSWORD` from `/home/evan/projects/food-journal-assistant/.env`).
- [ ] Set Cloud Run env: `CLEANUP_TOKEN=<random secret>`, `PHOTO_RETENTION_HOURS=24` (e.g. `gcloud run services update hearty-api --update-env-vars CLEANUP_TOKEN=...,PHOTO_RETENTION_HOURS=24`).
- [ ] Create an hourly Cloud Scheduler job POSTing to `https://<cloud-run-url>/internal/photos/purge` with header `X-Cleanup-Token: <CLEANUP_TOKEN>` (e.g. `gcloud scheduler jobs create http hearty-photo-purge --schedule="0 * * * *" --uri=... --http-method=POST --headers=X-Cleanup-Token=<token>`).
- [ ] Verify: `curl -X POST https://<url>/internal/photos/purge -H "X-Cleanup-Token: <token>"` → `{"purged":N,"scanned":N}`; a wrong/absent token → 403.

---

## Self-Review (completed by plan author)

- **Spec coverage:** `image_purged_at` column (T1); `purge_image`/`list_purgeable` (T2); delete-on-success best-effort (T3); token-guarded fail-closed cleanup endpoint + ungated mount (T4); Cloud Scheduler + migration apply (T5). No client changes — none needed per spec. ✓
- **Placeholder scan:** none — every code step has full code; T5 manual steps are concrete commands. ✓
- **Type/name consistency:** `purge_image(user_id, photo_id, path)`, `list_purgeable(cutoff_iso)`, `image_purged_at`, `CLEANUP_TOKEN`, `PHOTO_RETENTION_HOURS`, `X-Cleanup-Token`, route `/internal/photos/purge` consistent across T2–T5. The pipeline calls `purge_image(user_id, photo_id, row["photo_url"])` — matches T2's signature. ✓
- **Note:** `list_purgeable` uses `.is_("image_purged_at", "null")` (postgrest null filter) — the test asserts that exact call; if the installed supabase-py rejects the `"null"` string, switch to `.is_("image_purged_at", None)` and update the test's `rec["is"]` assertion accordingly.
