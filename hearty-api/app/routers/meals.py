import os
from datetime import datetime, timezone, timedelta
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Response
from pydantic import BaseModel
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

    if body.foods is not None:
        # Verbatim save: store the caller's foods as name-only items, skip
        # extraction, and leave meal_type to body.meal_type (mirrors PATCH).
        foods = [{"name": n.strip()} for n in body.foods if n and n.strip()]
        inferred_meal_type = None
    else:
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


class MealUpdateRequest(BaseModel):
    description: str
    foods: Optional[list[str]] = None


@router.patch("/api/meals/{meal_id}", status_code=200)
async def update_meal(
    meal_id: UUID,
    body: MealUpdateRequest,
    user=Depends(get_current_user),
) -> MealResponse:
    existing = (
        supabase.table("meals")
        .select("id,user_id")
        .eq("id", str(meal_id))
        .eq("user_id", user["id"])
        .execute()
    )
    if not existing.data:
        raise HTTPException(status_code=404, detail="Meal not found")

    if body.foods is not None:
        # Verbatim save: store the caller's foods as name-only items,
        # skip extraction, leave meal_type unchanged.
        updates: dict = {
            "description": body.description,
            "foods": [{"name": n.strip()} for n in body.foods if n and n.strip()],
        }
    else:
        # No foods supplied: re-extract from the description (legacy behavior).
        extracted = ai_extraction.extract_meal(body.description)
        updates = {"description": body.description, "foods": extracted.get("foods", [])}
        inferred_meal_type = extracted.get("inferred_meal_type")
        if inferred_meal_type:
            updates["meal_type"] = inferred_meal_type

    result = (
        supabase.table("meals")
        .update(updates)
        .eq("id", str(meal_id))
        .execute()
    )
    return MealResponse(**result.data[0])


@router.delete("/api/meals/{meal_id}", status_code=204)
async def delete_meal(
    meal_id: UUID,
    user=Depends(get_current_user),
):
    existing = (
        supabase.table("meals")
        .select("id,user_id")
        .eq("id", str(meal_id))
        .eq("user_id", user["id"])
        .execute()
    )
    if not existing.data:
        raise HTTPException(status_code=404, detail="Meal not found")
    supabase.table("meals").delete().eq("id", str(meal_id)).execute()
