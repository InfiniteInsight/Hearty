import hmac
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
    if not token or not hmac.compare_digest(
            request.headers.get("X-Cleanup-Token", ""), token):
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
