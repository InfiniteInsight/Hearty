from fastapi import APIRouter, HTTPException, Request
import os
from supabase import create_client

router = APIRouter()

supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])
WEBHOOK_SECRET = os.environ.get("SUPABASE_WEBHOOK_SECRET", "")

@router.post("/auth/on-login")
async def on_login(request: Request):
    # Verify webhook secret
    auth_header = request.headers.get("Authorization", "")
    if WEBHOOK_SECRET and auth_header != f"Bearer {WEBHOOK_SECRET}":
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
