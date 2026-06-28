import hmac
import logging
import os

from fastapi import APIRouter, HTTPException, Request
from supabase import create_client

router = APIRouter()
logger = logging.getLogger(__name__)

supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


@router.post("/auth/on-login")
async def on_login(request: Request):
    # Verify the request is from Supabase. Fail-closed: a missing/empty
    # SUPABASE_WEBHOOK_SECRET rejects every request (never silently open),
    # and the comparison is constant-time (mirrors internal.py).
    secret = os.environ.get("SUPABASE_WEBHOOK_SECRET", "")
    if not secret:
        logger.warning("/auth/on-login rejected: SUPABASE_WEBHOOK_SECRET is not set")
    auth_header = request.headers.get("Authorization", "")
    if not secret or not hmac.compare_digest(auth_header, f"Bearer {secret}"):
        raise HTTPException(status_code=401, detail="Invalid webhook secret")

    payload = await request.json()
    user = payload.get("user") or payload.get("record", {})
    user_id = user.get("id")
    if not user_id:
        raise HTTPException(status_code=400, detail="No user id in payload")

    # Upsert health_profile (blank row — no-op if already exists)
    supabase.table("health_profile").upsert(
        {"user_id": user_id},
        on_conflict="user_id"
    ).execute()

    # Upsert notification_preferences (all defaults — no-op if already exists)
    supabase.table("notification_preferences").upsert(
        {"user_id": user_id},
        on_conflict="user_id"
    ).execute()

    return {"ok": True}
