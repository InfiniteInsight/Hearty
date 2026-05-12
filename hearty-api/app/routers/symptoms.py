import os
from datetime import datetime, timezone, timedelta
from typing import List, Optional

from fastapi import APIRouter, Depends, Query
from supabase import create_client

from app.auth import get_current_user
from app.models.schemas import SymptomRequest, SymptomResponse
from app.services import ai_extraction

router = APIRouter()
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


@router.post("/api/symptoms", status_code=201)
async def log_symptoms(
    body: SymptomRequest,
    user=Depends(get_current_user),
) -> List[SymptomResponse]:
    logged_at = (body.logged_at or datetime.now(timezone.utc)).isoformat()

    if body.symptoms:
        symptom_dicts = [s.model_dump() for s in body.symptoms]
    else:
        symptom_dicts = ai_extraction.extract_symptoms(body.raw_description)

    rows = []
    for s in symptom_dicts:
        row = {
            "user_id": user["id"],
            "raw_description": body.raw_description,
            "meal_id": str(body.meal_id) if body.meal_id else None,
            "onset_minutes": body.onset_minutes,
            "notes": body.notes,
            "logged_at": logged_at,
            "symptom_type": s.get("symptom_type"),
            "severity": s.get("severity"),
            "duration_minutes": s.get("duration_minutes"),
            "bathroom_urgency": s.get("bathroom_urgency"),
            "bathroom_visits": s.get("bathroom_visits"),
            "stool_consistency": s.get("stool_consistency"),
        }
        rows.append({k: v for k, v in row.items() if v is not None})

    if not rows:
        return []

    result = supabase.table("symptoms").insert(rows).execute()
    return [SymptomResponse(**r) for r in result.data]


@router.get("/api/symptoms", status_code=200)
async def get_symptoms(
    user=Depends(get_current_user),
    start_date: Optional[str] = Query(None),
    end_date: Optional[str] = Query(None),
    symptom_type: Optional[str] = Query(None),
    min_severity: Optional[int] = Query(None),
    limit: int = Query(50),
) -> List[SymptomResponse]:
    now = datetime.now(timezone.utc)
    start = start_date or (now - timedelta(days=7)).isoformat()
    end = end_date or now.isoformat()

    query = (
        supabase.table("symptoms")
        .select("*")
        .eq("user_id", user["id"])
        .gte("logged_at", start)
        .lte("logged_at", end)
        .order("logged_at", desc=True)
        .limit(limit)
    )

    if symptom_type:
        query = query.eq("symptom_type", symptom_type)
    if min_severity is not None:
        query = query.gte("severity", min_severity)

    result = query.execute()
    return [SymptomResponse(**r) for r in (result.data or [])]
