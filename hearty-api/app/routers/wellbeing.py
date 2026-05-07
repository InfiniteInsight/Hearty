import os
from datetime import datetime, timezone

from fastapi import APIRouter, Depends
from supabase import create_client

from app.auth import get_current_user
from app.models.schemas import WellbeingRequest, WellbeingResponse

router = APIRouter()
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


@router.post("/api/wellbeing", status_code=201)
async def log_wellbeing(
    body: WellbeingRequest,
    user=Depends(get_current_user),
) -> WellbeingResponse:
    logged_at = (body.logged_at or datetime.now(timezone.utc)).isoformat()

    row = {
        "user_id": user["id"],
        "logged_at": logged_at,
        "energy_level": body.energy_level,
        "mood": body.mood,
        "stress_level": body.stress_level,
        "sleep_hours": float(body.sleep_hours) if body.sleep_hours is not None else None,
        "sleep_quality": body.sleep_quality,
        "hydration": body.hydration,
        "exercise_minutes": body.exercise_minutes,
        "notes": body.notes,
    }
    row = {k: v for k, v in row.items() if v is not None}

    result = supabase.table("wellbeing_snapshots").insert(row).execute()
    return WellbeingResponse(**result.data[0])
