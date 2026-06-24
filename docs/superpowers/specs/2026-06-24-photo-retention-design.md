# Photo Retention — Design

**Status:** Approved (brainstorm 2026-06-24)
**Tracking:** task #82.
**Context:** runs on the Cloud Run backend deploy (Cloud Scheduler triggers the cleanup).

## Problem & goal

User-submitted food photos must not be retained beyond their purpose. The raw image is read **exactly once, server-side**, by the analysis pipeline (`photo_pipeline.process_photo` → `photo_store.download_bytes`); no client endpoint ever serves it back. So retaining it afterward is pure liability + storage cost.

**Goal:** keep raw images for the minimum time:
- **On successful analysis → delete the image immediately** (retained ~seconds).
- **On failure / still-unprocessed → retain up to a grace window (default 24h)** so a user who was offline/away can hit retry (which re-downloads the image), then purge.

The derived data — the meal/journal entry and `extracted_data` (detected foods) — persists indefinitely. This is image-only deletion.

## Non-goals
- Deleting derived data / journal entries (the product's value; explicitly kept).
- Any client (web/phone) change — the image is never served to clients, so deletion is invisible to them.
- Reprocessing old photos with better models later (we are intentionally not retaining images for this).
- Re-architecting the upload/analysis flow.

## Why a grace window at all (the offline case)
A *successful* photo needs no retention past processing. The only reason to keep an image is **retry of a failed analysis**: `/api/photos/{id}/retry` re-downloads the image to re-run the vision call. If the user was offline/away when analysis failed, the image must still exist when they reconnect to retry. The grace window (24h) covers exactly that. The retention clock starts at **upload** time; an offline phone only uploads once back online, so offline capture never races the timer.

## Architecture

### 1. Schema — `image_purged_at`
Migration adds one nullable column to `food_log_photos`:
```sql
alter table food_log_photos add column if not exists image_purged_at timestamptz;
```
`NULL` = image still in Storage; non-null = image deleted (timestamp). `photo_url` is kept for provenance.

### 2. `photo_store.purge_image` (new)
```python
def purge_image(user_id: str, photo_id: str, path: str) -> None:
    """Delete the raw image from Storage and stamp the row purged. Storage
    remove is idempotent (missing key is not an error), so this is safe to call
    more than once."""
    supabase.storage.from_(PHOTO_BUCKET).remove([path])
    supabase.table("food_log_photos").update({"image_purged_at": _now_iso()}) \
        .eq("user_id", user_id).eq("id", photo_id).execute()
```

### 3. Delete-on-success (in `photo_pipeline.process_photo`)
After `photo_store.set_result(...)` succeeds, purge the image **best-effort** — a Storage hiccup must not fail an analysis that already succeeded; the daily cleanup is the backstop:
```python
photo_store.set_result(user_id, photo_id, result)
try:
    photo_store.purge_image(user_id, photo_id, row["photo_url"])
except Exception as e:
    logger.warning("post-success image purge failed for %s: %s", photo_id, e)
```
The failure path (`set_failed`) does **not** purge — the image stays for the retry window.

### 4. Cleanup endpoint — `POST /internal/photos/purge`
Token-guarded, no user auth, **not** behind `require_active_license` (it's an ops/cron endpoint). Deletes images for rows past the retention window that aren't yet purged (catches failures, stuck-`processing`, and any delete-on-success that didn't fire):
```python
@router.post("/internal/photos/purge")
async def purge_old_photos(request: Request) -> dict:
    token = os.environ.get("CLEANUP_TOKEN", "")
    if not token or request.headers.get("X-Cleanup-Token") != token:
        raise HTTPException(status_code=403, detail="forbidden")   # fail-closed
    hours = int(os.environ.get("PHOTO_RETENTION_HOURS", "24"))
    cutoff = (datetime.now(timezone.utc) - timedelta(hours=hours)).isoformat()
    rows = photo_store.list_purgeable(cutoff)          # image_purged_at IS NULL AND created_at < cutoff
    purged = 0
    for r in rows:
        try:
            photo_store.purge_image(r["user_id"], r["id"], r["photo_url"])
            purged += 1
        except Exception as e:
            logger.warning("cleanup purge failed for %s: %s", r["id"], e)
    return {"purged": purged, "scanned": len(rows)}
```
`photo_store.list_purgeable(cutoff)` selects `id,user_id,photo_url` from `food_log_photos` where `image_purged_at is null and created_at < cutoff`.

**Fail-closed:** if `CLEANUP_TOKEN` is unset, every request is rejected — never an open purge endpoint.

### 5. Trigger — Cloud Scheduler (deploy-time wiring)
A Cloud Scheduler job runs **hourly**, POSTing to `https://<cloud-run-url>/internal/photos/purge` with header `X-Cleanup-Token: <CLEANUP_TOKEN>`. Hourly (not daily) tightens the worst-case retention of a failed image to ~window + 1h. This is GCP console/CLI config, done at/after the Cloud Run deploy.
*(Self-contained alternative considered: Supabase `pg_cron` + `pg_net` calling the Storage REST delete. Rejected for this iteration: deleting Storage objects from SQL is fiddlier and less testable than reusing the backend `photo_store` Storage client, and we're already on GCP.)*

### 6. Config
- `PHOTO_RETENTION_HOURS` — grace window, default `24`.
- `CLEANUP_TOKEN` — shared secret for the cleanup endpoint (also set as the Cloud Scheduler header). Required for the endpoint to do anything.

## Data flow
1. Upload → image in Storage, row `processing`.
2. Pipeline analyzes → `complete` + `extracted_data` → **image deleted immediately**, `image_purged_at` stamped.
3. If analysis **failed** → image kept; user can retry (re-downloads image) within the window.
4. Hourly cleanup deletes any image past the window with `image_purged_at IS NULL` (failed/stuck/missed) and stamps it.
5. Account deletion (existing `account.py`) still removes any remaining images — idempotent with already-purged ones.

## Error handling
- Delete-on-success is best-effort (try/except); cleanup backstops.
- Storage `remove` is idempotent on missing keys → double-purge safe.
- Cleanup is fail-closed on missing token; per-row failures are logged and don't abort the batch.
- A `complete` photo whose image is gone still works: retry of a complete photo returns cached `extracted_data` without re-downloading (existing behavior).

## Security
- Cleanup endpoint requires a secret token, fail-closed; not user-authenticated, not license-gated.
- No user-editable input influences deletion (cleanup is time + purge-flag driven; `photo_url` paths are server-generated `{user_id}/{photo_id}.jpg`).
- Storage bucket `food-photos` stays private, RLS per-user (unchanged).

## Testing
**Backend (pytest, stateful Storage + table fakes):**
- `photo_store.purge_image`: calls Storage remove with the path and stamps `image_purged_at`.
- `process_photo`: on success → image purged + `image_purged_at` set; on failure → image NOT purged.
- `purge_old_photos` endpoint: purges rows older than window with null stamp; skips within-window; skips already-purged (idempotent); rejects missing/wrong token; fail-closed when `CLEANUP_TOKEN` unset.
- `list_purgeable`: correct cutoff + null-stamp filter.
- Existing photo tests stay green.

**No web/phone tests** — no client surface changes.

## Out of scope / follow-ups
- Cloud Scheduler job creation (deploy-time, documented in the deploy runbook).
- Retry-then-purge for stuck `processing` photos (cleanup currently just purges them after the window; auto-retry-once-before-purge is a possible later enhancement).
