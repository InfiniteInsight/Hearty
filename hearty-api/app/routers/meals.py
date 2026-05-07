import os
from datetime import datetime, timezone, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, Query, Response
from supabase import create_client

from app.auth import get_current_user
from app.models.schemas import (
    MealRequest,
    MealResponse,
    MealWithSymptoms,
    MealsListResponse,
    SymptomResponse,
)
from app.services import ai_extraction

router = APIRouter()
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])

_VALID_INPUT_METHODS = {"voice", "text", "photo"}


@router.post("/api/meals", status_code=201)
async def log_meal(
    body: MealRequest,
    response: Response,
    user=Depends(get_current_user),
) -> MealResponse:
    if body.offline_id:
        existing = (
            supabase.table("meals")
            .select("*")
            .eq("user_id", user["id"])
            .eq("offline_id", body.offline_id)
            .execute()
        )
        if existing.data:
            response.status_code = 200
            return MealResponse(**existing.data[0])

    extracted = ai_extraction.extract_meal(body.description)
    foods = extracted.get("foods", [])
    inferred_meal_type = extracted.get("inferred_meal_type")

    row = {
        "user_id": user["id"],
        "description": body.description,
        "meal_type": body.meal_type or inferred_meal_type,
        "foods": foods,
        "location": body.location,
        "mood_before": body.mood_before,
        "hunger_before": body.hunger_before,
        "logged_at": (body.logged_at or datetime.now(timezone.utc)).isoformat(),
        "input_method": body.input_method if body.input_method in _VALID_INPUT_METHODS else None,
        "notes": body.notes,
        "offline_id": body.offline_id,
    }
    row = {k: v for k, v in row.items() if v is not None}

    result = supabase.table("meals").insert(row).execute()
    return MealResponse(**result.data[0])


@router.get("/api/meals", status_code=200)
async def get_meals(
    user=Depends(get_current_user),
    start_date: Optional[str] = Query(None),
    end_date: Optional[str] = Query(None),
    meal_type: Optional[str] = Query(None),
    keyword: Optional[str] = Query(None),
    limit: int = Query(50, le=200),
    offset: int = Query(0),
) -> MealsListResponse:
    now = datetime.now(timezone.utc)
    start = start_date or (now - timedelta(days=7)).isoformat()
    end = end_date or now.isoformat()

    query = (
        supabase.table("meals")
        .select("*", count="exact")
        .eq("user_id", user["id"])
        .gte("logged_at", start)
        .lte("logged_at", end)
        .order("logged_at", desc=True)
        .range(offset, offset + limit - 1)
    )

    if meal_type:
        query = query.eq("meal_type", meal_type)
    if keyword:
        query = query.ilike("description", f"%{keyword}%")

    result = query.execute()
    meals_data = result.data or []
    total = result.count or 0

    if not meals_data:
        return MealsListResponse(total=total, meals=[])

    meal_ids = [m["id"] for m in meals_data]
    symptoms_result = (
        supabase.table("symptoms").select("*").in_("meal_id", meal_ids).execute()
    )
    symptoms_by_meal: dict[str, list] = {}
    for s in (symptoms_result.data or []):
        mid = s.get("meal_id")
        if mid:
            symptoms_by_meal.setdefault(mid, []).append(s)

    meals = [
        MealWithSymptoms(
            **m,
            symptoms=[SymptomResponse(**s) for s in symptoms_by_meal.get(m["id"], [])],
        )
        for m in meals_data
    ]
    return MealsListResponse(total=total, meals=meals)
