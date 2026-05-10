import os
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, Query
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


@router.get("/api/wellbeing", status_code=200)
async def get_wellbeing(
    user=Depends(get_current_user),
    start_date: Optional[str] = Query(None),
    end_date: Optional[str] = Query(None),
    limit: int = Query(50, le=200),
) -> list[WellbeingResponse]:
    now = datetime.now(timezone.utc)
    start = start_date or now.replace(hour=0, minute=0, second=0, microsecond=0).isoformat()
    end = end_date or now.isoformat()

    result = (
        supabase.table("wellbeing_snapshots")
        .select("*")
        .eq("user_id", user["id"])
        .gte("logged_at", start)
        .lte("logged_at", end)
        .order("logged_at", desc=True)
        .limit(limit)
        .execute()
    )
    return [WellbeingResponse(**row) for row in (result.data or [])]
