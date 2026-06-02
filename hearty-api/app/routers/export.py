import csv
import io
import os
from datetime import datetime, timezone, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, Query
from fastapi.responses import Response, StreamingResponse
from supabase import create_client

from app.auth import get_current_user
from app.models.schemas import (
    ExportRequest,
    MealWithSymptoms,
    SymptomResponse,
    TriggerFood,
)
from app.health_profile.schemas import HealthProfileResponse
from app.services import export_service, trend_engine
from app.services.symptom_taxonomy import expand_symptom_list

router = APIRouter()
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


def _resolve_period(start_date: Optional[str], end_date: Optional[str]) -> tuple[Optional[datetime], Optional[datetime], int]:
    """Return (start, end, period_days). period_days is 365 when both dates are None."""
    now = datetime.now(timezone.utc)
    if start_date and end_date:
        start = datetime.fromisoformat(start_date.replace("Z", "+00:00"))
        end = datetime.fromisoformat(end_date.replace("Z", "+00:00"))
        period_days = max(int((end - start).total_seconds() / 86400), 1)
    elif start_date:
        start = datetime.fromisoformat(start_date.replace("Z", "+00:00"))
        end = now
        period_days = max(int((end - start).total_seconds() / 86400), 1)
    elif end_date:
        end = datetime.fromisoformat(end_date.replace("Z", "+00:00"))
        start = end - timedelta(days=365)
        period_days = 365
    else:
        start = None
        end = None
        period_days = 365
    return start, end, period_days


def _fetch_meals_with_symptoms(user_id: str, start: Optional[datetime], end: Optional[datetime]) -> list[MealWithSymptoms]:
    query = supabase.table("meals").select("*").eq("user_id", user_id).order("logged_at", desc=False)
    if start:
        query = query.gte("logged_at", start.isoformat())
    if end:
        query = query.lte("logged_at", end.isoformat())
    meals_result = query.execute()
    meals_data = meals_result.data or []

    if not meals_data:
        return []

    meal_ids = [m["id"] for m in meals_data]
    symptoms_result = supabase.table("symptoms").select("*").in_("meal_id", meal_ids).execute()
    symptoms_by_meal: dict[str, list] = {}
    for s in (symptoms_result.data or []):
        mid = s.get("meal_id")
        if mid:
            symptoms_by_meal.setdefault(mid, []).append(s)

    return [
        MealWithSymptoms(
            **m,
            symptoms=expand_symptom_list(
                [SymptomResponse(**s) for s in symptoms_by_meal.get(m["id"], [])]
            ),
        )
        for m in meals_data
    ]


@router.get("/api/export/json", status_code=200)
async def export_json(
    user=Depends(get_current_user),
    start_date: Optional[str] = Query(None),
    end_date: Optional[str] = Query(None),
):
    user_id = user["id"]
    start, end, period_days = _resolve_period(start_date, end_date)

    meals = _fetch_meals_with_symptoms(user_id, start, end)

    wellbeing_query = supabase.table("wellbeing_snapshots").select("*").eq("user_id", user_id).order("logged_at", desc=False)
    if start:
        wellbeing_query = wellbeing_query.gte("logged_at", start.isoformat())
    if end:
        wellbeing_query = wellbeing_query.lte("logged_at", end.isoformat())
    wellbeing_result = wellbeing_query.execute()
    wellbeing_data = wellbeing_result.data or []

    trend_result = trend_engine.analyze_triggers(
        user_id=user_id,
        analysis_period_days=period_days,
        focus_symptom=None,
        min_occurrences=2,
    )
    food_triggers = [TriggerFood(**t).model_dump() for t in trend_result["triggers"]]

    health_result = supabase.table("health_profile").select("*").eq("user_id", user_id).execute()
    health_row = (health_result.data or [{}])[0]
    health_profile = None
    if health_row:
        try:
            health_profile = HealthProfileResponse(
                allergens=health_row.get("allergens") or [],
                intolerances=health_row.get("intolerances") or [],
                conditions=health_row.get("conditions") or [],
                dietary_protocols=health_row.get("dietary_protocols") or [],
                updated_at=health_row.get("updated_at") or datetime.now(timezone.utc),
            ).model_dump(mode="json")
        except Exception:
            health_profile = None

    now = datetime.now(timezone.utc)
    return {
        "exported_at": now.isoformat(),
        "user_id": user_id,
        "period": {
            "start": start.isoformat() if start else None,
            "end": end.isoformat() if end else None,
        },
        "meals": [m.model_dump(mode="json") for m in meals],
        "wellbeing_snapshots": wellbeing_data,
        "food_triggers": food_triggers,
        "health_profile": health_profile,
    }


@router.get("/api/export/csv", status_code=200)
async def export_csv(
    user=Depends(get_current_user),
    start_date: Optional[str] = Query(None),
    end_date: Optional[str] = Query(None),
):
    user_id = user["id"]
    start, end, _ = _resolve_period(start_date, end_date)

    meals = _fetch_meals_with_symptoms(user_id, start, end)

    # Also fetch unlinked symptoms for the period
    unlinked_query = (
        supabase.table("symptoms")
        .select("*")
        .eq("user_id", user_id)
        .is_("meal_id", "null")
    )
    if start:
        unlinked_query = unlinked_query.gte("logged_at", start.isoformat())
    if end:
        unlinked_query = unlinked_query.lte("logged_at", end.isoformat())
    unlinked_result = unlinked_query.execute()
    unlinked_symptoms = unlinked_result.data or []

    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow([
        "Meal Description",
        "Food Items",
        "Symptom Type",
        "Severity",
        "Onset (minutes)",
        "Meal Type",
        "Logged At",
    ])

    for meal in meals:
        food_names = ", ".join(f.name for f in (meal.foods or []))
        if meal.symptoms:
            for sym in meal.symptoms:
                writer.writerow([
                    meal.description,
                    food_names,
                    sym.symptom_type,
                    sym.severity if sym.severity is not None else "",
                    sym.onset_minutes if sym.onset_minutes is not None else "",
                    meal.meal_type or "",
                    meal.logged_at.isoformat(),
                ])
        else:
            # Meal with no symptoms — still emit a row
            writer.writerow([
                meal.description,
                food_names,
                "",
                "",
                "",
                meal.meal_type or "",
                meal.logged_at.isoformat(),
            ])

    for sym in unlinked_symptoms:
        writer.writerow([
            "",
            "",
            sym.get("symptom_type", ""),
            sym.get("severity", "") if sym.get("severity") is not None else "",
            sym.get("onset_minutes", "") if sym.get("onset_minutes") is not None else "",
            "",
            sym.get("logged_at", ""),
        ])

    buf.seek(0)
    return StreamingResponse(
        iter([buf.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": "attachment; filename=hearty-export.csv"},
    )


@router.post("/api/export/pdf", status_code=200)
async def export_pdf(
    body: ExportRequest,
    user=Depends(get_current_user),
):
    pdf_bytes = export_service.generate_pdf(user["id"], body.start_date, body.end_date)
    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={"Content-Disposition": "attachment; filename=hearty-report.pdf"},
    )
