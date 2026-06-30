"""Daily check-in: detect gaps in a day's logs and write back answers.

GET /api/checkin/gaps        — day-anchored gap queue (48h expiry).
POST /api/checkin/resolve/symptom — A answered: insert a symptom, mark meal answered.
POST /api/checkin/skip/symptom    — A skipped in the evening: spend its one retry.
POST /api/checkin/resolve/food    — C: confirm (bump confidence) or correct (re-extract).
POST /api/checkin/resolve/meal    — D: mini-extract + insert a meal on the target day.

Write-backs reuse the existing meal/symptom row shapes (see routers/meals.py,
routers/symptoms.py) rather than inventing new persistence.
"""

import os
from datetime import datetime, timezone, timedelta, date as date_cls

from fastapi import APIRouter, Depends, HTTPException, Query
from supabase import create_client

from app.auth import get_current_user
from app.models.schemas import CheckinGap, CheckinGapsResponse
from app.services import checkin_detector
from app.services import ai_extraction

router = APIRouter()
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])

CHECKIN_EXPIRY_HOURS = float(os.environ.get("CHECKIN_EXPIRY_HOURS", "48"))


@router.get("/api/checkin/gaps", status_code=200)
async def get_checkin_gaps(
    date: str = Query(..., description="Target day, YYYY-MM-DD (day-anchored)"),
    utc_offset_minutes: int = Query(
        0, description="Client UTC offset in minutes (e.g. -240 for EDT). The "
        "target day and the waking window are anchored to this zone so times "
        "render in the user's local clock."),
    user=Depends(get_current_user),
) -> CheckinGapsResponse:
    user_id = user["id"]
    # Anchor the day + waking window to the user's local zone. Without this the
    # 8am-10pm waking window was built in UTC and rendered shifted on-device
    # (e.g. an 8am start showing as 4am at UTC-4).
    tz = timezone(timedelta(minutes=utc_offset_minutes))
    now = datetime.now(timezone.utc).astimezone(tz)
    target = date_cls.fromisoformat(date)

    # 48h expiry: anchored to the END of the (local) target day.
    day_end = datetime(target.year, target.month, target.day, 23, 59, 59,
                       tzinfo=tz)
    if now - day_end > timedelta(hours=CHECKIN_EXPIRY_HOURS):
        return CheckinGapsResponse(target_date=date, expired=True, gaps=[])

    day_start = datetime(target.year, target.month, target.day, 0, 0, 0,
                         tzinfo=tz)
    detect_until = min(now, day_end)  # never the unlived part of today

    meals = (
        supabase.table("meals")
        .select("id, foods, logged_at, followup_status, meal_type")
        .eq("user_id", user_id)
        .gte("logged_at", day_start.isoformat())
        .lte("logged_at", day_end.isoformat())
        .execute()
    ).data or []
    symptoms = (
        supabase.table("symptoms")
        .select("id, meal_id, logged_at")
        .eq("user_id", user_id)
        .gte("logged_at", day_start.isoformat())
        .lte("logged_at", day_end.isoformat())
        .execute()
    ).data or []

    gaps = checkin_detector.detect_gaps(meals, symptoms, now=detect_until)
    return CheckinGapsResponse(
        target_date=date, expired=False,
        gaps=[CheckinGap(**g) for g in gaps],
    )


@router.post("/api/checkin/resolve/symptom", status_code=200)
async def resolve_symptom_gap(body: dict, user=Depends(get_current_user)) -> dict:
    """A-gap answer: create a symptom linked to the meal, mark the meal answered.

    Day-anchored: `logged_at` must carry the target day (the spec stamps every
    write-back to the reviewed day, not the tap day). Falls back to now only when
    the caller omits it.
    """
    user_id = user["id"]
    logged_at = body.get("logged_at") or datetime.now(timezone.utc).isoformat()
    row = {k: v for k, v in {
        "user_id": user_id,
        "raw_description": body.get("raw_description", ""),
        "meal_id": body["meal_id"],
        "symptom_type": body.get("symptom_type"),
        "severity": body.get("severity"),
        "onset_minutes": body.get("onset_minutes"),
        "logged_at": logged_at,
    }.items() if v is not None}
    supabase.table("symptoms").insert(row).execute()
    supabase.table("meals").update({"followup_status": "answered"}) \
        .eq("id", body["meal_id"]).eq("user_id", user_id).execute()
    return {"ok": True}


@router.post("/api/checkin/skip/symptom", status_code=200)
async def skip_symptom_gap(body: dict, user=Depends(get_current_user)) -> dict:
    """A-gap skipped in the evening: spend its one retry (resurfaced)."""
    user_id = user["id"]
    supabase.table("meals").update({"followup_status": "resurfaced"}) \
        .eq("id", body["meal_id"]).eq("user_id", user_id).execute()
    return {"ok": True}


@router.post("/api/checkin/dismiss/symptom", status_code=200)
async def dismiss_symptom_gap(body: dict, user=Depends(get_current_user)) -> dict:
    """The user closed an in-the-moment symptom follow-up without answering. Mark
    it dismissed so the evening check-in can resurface it once (gap A)."""
    user_id = user["id"]
    supabase.table("meals").update({"followup_status": "dismissed"}) \
        .eq("id", body["meal_id"]).eq("user_id", user_id).execute()
    return {"ok": True}


@router.post("/api/checkin/resolve/food", status_code=200)
async def resolve_food_gap(body: dict, user=Depends(get_current_user)) -> dict:
    """C-gap resolution.

    confirmed=True  -> the user says we got it right: raise that food's confidence
                       to 1.0 in the stored meal so it stops re-flagging.
    otherwise       -> the user corrects it: re-extract from corrected_description
                       and replace the meal's foods (mirrors meals.update_meal).
    """
    user_id = user["id"]
    meal_id = body["meal_id"]

    if body.get("confirmed"):
        existing = (
            supabase.table("meals")
            .select("foods")
            .eq("id", meal_id)
            .eq("user_id", user_id)
            .execute()
        )
        if not existing.data:
            raise HTTPException(status_code=404, detail="Meal not found")
        foods = existing.data[0].get("foods") or []
        target_name = body.get("food_name")
        for food in foods:
            if target_name is None or food.get("name") == target_name:
                food["confidence"] = 1.0
        supabase.table("meals").update({"foods": foods}) \
            .eq("id", meal_id).eq("user_id", user_id).execute()
        return {"ok": True}

    corrected = body.get("corrected_description", "")
    extracted = ai_extraction.extract_meal(corrected)
    updates = {"description": corrected, "foods": extracted.get("foods", [])}
    inferred = extracted.get("inferred_meal_type")
    if inferred:
        updates["meal_type"] = inferred
    supabase.table("meals").update(updates) \
        .eq("id", meal_id).eq("user_id", user_id).execute()
    return {"ok": True}


@router.post("/api/checkin/resolve/meal", status_code=200)
async def resolve_meal_gap(body: dict, user=Depends(get_current_user)) -> dict:
    """D-gap resolution: 'I had X at 3pm' -> mini-extract + insert a meal on the
    target day (mirrors meals.log_meal). logged_at must carry the target day."""
    user_id = user["id"]
    description = body["description"]
    extracted = ai_extraction.extract_meal(description)
    row = {
        "user_id": user_id,
        "description": description,
        "foods": extracted.get("foods", []),
        "meal_type": extracted.get("inferred_meal_type"),
        "logged_at": body.get("logged_at")
        or datetime.now(timezone.utc).isoformat(),
        "input_method": "voice",
    }
    row = {k: v for k, v in row.items() if v is not None}
    supabase.table("meals").insert(row).execute()
    return {"ok": True}
