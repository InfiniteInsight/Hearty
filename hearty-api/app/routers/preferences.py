import os
from typing import List, Optional

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from supabase import create_client

from app.auth import get_current_user

router = APIRouter()
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


class UserPreferencesSchema(BaseModel):
    # Health profile fields (from health_profile table)
    allergens: List[str] = []
    conditions: List[str] = []
    dietary_protocols: List[str] = []
    medications: List[str] = []
    # Notification fields (from notification_preferences table)
    nudge_delay_minutes: int = 45
    post_meal_nudge_enabled: bool = True
    daily_checkin_enabled: bool = True
    weekly_digest_enabled: bool = True
    sync_error_alerts_enabled: bool = True
    wake_word_enabled: bool = True
    daily_checkin_hour: int = 8
    daily_checkin_minute: int = 0
    fcm_token: Optional[str] = None


def _get_or_create_notif_prefs(user_id: str) -> dict:
    result = (
        supabase.table("notification_preferences")
        .select("*")
        .eq("user_id", user_id)
        .execute()
    )
    if result.data:
        return result.data[0]
    row = {"user_id": user_id}
    created = (
        supabase.table("notification_preferences")
        .upsert(row, on_conflict="user_id")
        .execute()
    )
    return created.data[0]


def _get_or_create_health_profile(user_id: str) -> dict:
    result = (
        supabase.table("health_profile")
        .select("allergens,conditions,dietary_protocols,medications")
        .eq("user_id", user_id)
        .execute()
    )
    if result.data:
        return result.data[0]
    return {"allergens": [], "conditions": [], "dietary_protocols": [], "medications": []}


def _row_to_schema(hp: dict, np: dict) -> UserPreferencesSchema:
    # daily_checkin_time is stored as "HH:MM:SS" in Postgres
    checkin_time = np.get("daily_checkin_time") or "08:00:00"
    parts = str(checkin_time).split(":")
    hour = int(parts[0]) if len(parts) > 0 else 8
    minute = int(parts[1]) if len(parts) > 1 else 0

    return UserPreferencesSchema(
        allergens=hp.get("allergens") or [],
        conditions=hp.get("conditions") or [],
        dietary_protocols=hp.get("dietary_protocols") or [],
        medications=hp.get("medications") or [],
        nudge_delay_minutes=np.get("post_meal_delay_minutes") or 45,
        post_meal_nudge_enabled=np.get("post_meal_enabled") if np.get("post_meal_enabled") is not None else True,
        daily_checkin_enabled=np.get("daily_checkin_enabled") if np.get("daily_checkin_enabled") is not None else True,
        weekly_digest_enabled=np.get("weekly_digest_enabled") if np.get("weekly_digest_enabled") is not None else True,
        sync_error_alerts_enabled=np.get("sync_error_alerts_enabled") if np.get("sync_error_alerts_enabled") is not None else True,
        wake_word_enabled=np.get("wake_word_enabled") if np.get("wake_word_enabled") is not None else True,
        daily_checkin_hour=hour,
        daily_checkin_minute=minute,
        fcm_token=np.get("fcm_token"),
    )


@router.get("/api/preferences")
async def get_preferences(user=Depends(get_current_user)) -> UserPreferencesSchema:
    hp = _get_or_create_health_profile(user["id"])
    np = _get_or_create_notif_prefs(user["id"])
    return _row_to_schema(hp, np)


@router.put("/api/preferences")
async def update_preferences(
    body: UserPreferencesSchema,
    user=Depends(get_current_user),
) -> UserPreferencesSchema:
    checkin_time = f"{body.daily_checkin_hour:02d}:{body.daily_checkin_minute:02d}:00"

    notif_row = {
        "user_id": user["id"],
        "post_meal_enabled": body.post_meal_nudge_enabled,
        "post_meal_delay_minutes": body.nudge_delay_minutes,
        "daily_checkin_enabled": body.daily_checkin_enabled,
        "daily_checkin_time": checkin_time,
        "weekly_digest_enabled": body.weekly_digest_enabled,
        "sync_error_alerts_enabled": body.sync_error_alerts_enabled,
        "wake_word_enabled": body.wake_word_enabled,
        "fcm_token": body.fcm_token,
    }
    notif_row = {k: v for k, v in notif_row.items() if v is not None or k == "fcm_token"}
    np_result = (
        supabase.table("notification_preferences")
        .upsert(notif_row, on_conflict="user_id")
        .execute()
    )

    hp_row = {
        "user_id": user["id"],
        "allergens": body.allergens,
        "conditions": body.conditions,
        "dietary_protocols": body.dietary_protocols,
        "medications": body.medications,
    }
    hp_result = (
        supabase.table("health_profile")
        .upsert(hp_row, on_conflict="user_id")
        .execute()
    )

    return _row_to_schema(hp_result.data[0], np_result.data[0])
