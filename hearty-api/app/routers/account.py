import logging
import os

from fastapi import APIRouter, Depends
from supabase import create_client

from app.auth import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter()
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])

PHOTO_BUCKET = os.environ.get("PHOTO_BUCKET", "food-photos")

# Children before parents (symptoms + food_log_photos reference meals; meals last).
# food_cache and waitlist are intentionally excluded — they are not user-scoped.
USER_TABLES = [
    "symptoms",
    "food_log_photos",
    "food_triggers",
    "food_signals",
    "food_signals_yearly",
    "signal_feedback",
    "experiments",
    "wellbeing_snapshots",
    "meals",
    "health_profile",
    "notification_preferences",
    "offline_queue",
]


@router.delete("/api/account", status_code=204)
async def delete_account(user=Depends(get_current_user)):
    """Permanently delete the authenticated user's data and auth account.

    Order matters: child rows first, then parent rows, then the auth user.
    Storage cleanup is best-effort and must never block row/auth deletion.
    """
    user_id = user["id"]

    # 1. Best-effort removal of the user's photo objects from Storage.
    try:
        photos = (
            supabase.table("food_log_photos")
            .select("storage_path")
            .eq("user_id", user_id)
            .execute()
        ).data or []
        paths = [p["storage_path"] for p in photos if p.get("storage_path")]
        if paths:
            supabase.storage.from_(PHOTO_BUCKET).remove(paths)
    except Exception as e:  # pragma: no cover - defensive
        logger.error("account photo storage cleanup failed: %s", e, exc_info=True)

    # 2. Delete all user-scoped rows (children first).
    for table in USER_TABLES:
        supabase.table(table).delete().eq("user_id", user_id).execute()

    # 3. Delete the auth user (admin API, service-role key).
    supabase.auth.admin.delete_user(user_id)
