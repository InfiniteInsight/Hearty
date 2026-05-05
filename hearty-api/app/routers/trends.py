import os
from datetime import datetime, timezone, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, Query, HTTPException
from supabase import create_client

from app.auth import get_current_user
from app.models.schemas import TrendsResponse, TriggerFood, SummaryResponse
from app.services import ai_extraction, trend_engine

router = APIRouter()
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


@router.get("/api/trends", status_code=200)
async def get_trends(
    user=Depends(get_current_user),
    analysis_period_days: int = Query(30),
    focus_symptom: Optional[str] = Query(None),
    min_occurrences: int = Query(2),
) -> TrendsResponse:
    result = trend_engine.analyze_triggers(
        user_id=user["id"],
        analysis_period_days=analysis_period_days,
        focus_symptom=focus_symptom,
        min_occurrences=min_occurrences,
    )
    triggers = [TriggerFood(**t) for t in result["triggers"]]
    return TrendsResponse(
        analysis_period_days=result["analysis_period_days"],
        generated_at=result["generated_at"],
        triggers=triggers,
        total_meals_analyzed=result["total_meals_analyzed"],
        total_symptoms_analyzed=result["total_symptoms_analyzed"],
    )


@router.get("/api/summary", status_code=200)
async def get_summary(
    user=Depends(get_current_user),
    period: str = Query("week"),
    start_date: Optional[str] = Query(None),
    end_date: Optional[str] = Query(None),
) -> SummaryResponse:
    now = datetime.now(timezone.utc)

    if period == "custom":
        if not start_date or not end_date:
            raise HTTPException(
                status_code=422,
                detail="start_date and end_date are required when period=custom",
            )
        start = datetime.fromisoformat(start_date.replace("Z", "+00:00"))
        end = datetime.fromisoformat(end_date.replace("Z", "+00:00"))
    elif period == "month":
        start = now - timedelta(days=30)
        end = now
    else:
        start = now - timedelta(days=7)
        end = now

    meals_result = (
        supabase.table("meals")
        .select("id", count="exact")
        .eq("user_id", user["id"])
        .gte("logged_at", start.isoformat())
        .lte("logged_at", end.isoformat())
        .execute()
    )
    meals_count = meals_result.count or 0

    symptoms_result = (
        supabase.table("symptoms")
        .select("symptom_type, severity")
        .eq("user_id", user["id"])
        .gte("logged_at", start.isoformat())
        .lte("logged_at", end.isoformat())
        .execute()
    )
    symptoms = symptoms_result.data or []

    symptom_buckets: dict[str, dict] = {}
    for s in symptoms:
        st = s.get("symptom_type") or "unknown"
        if st not in symptom_buckets:
            symptom_buckets[st] = {"symptom_type": st, "count": 0, "severities": []}
        symptom_buckets[st]["count"] += 1
        if s.get("severity") is not None:
            symptom_buckets[st]["severities"].append(s["severity"])

    top_symptoms = []
    for entry in sorted(symptom_buckets.values(), key=lambda x: x["count"], reverse=True)[:5]:
        sevs = entry.pop("severities")
        entry["avg_severity"] = round(sum(sevs) / len(sevs), 1) if sevs else None
        top_symptoms.append(entry)

    period_days = max(int((end - start).total_seconds() / 86400), 1)
    trend_result = trend_engine.analyze_triggers(
        user_id=user["id"],
        analysis_period_days=period_days,
        focus_symptom=None,
        min_occurrences=2,
    )
    top_triggers = [TriggerFood(**t) for t in trend_result["triggers"][:5]]

    stats = {
        "period": period,
        "start_date": start.isoformat(),
        "end_date": end.isoformat(),
        "meals_logged": meals_count,
        "top_symptoms": top_symptoms,
        "top_triggers": [t.model_dump() for t in top_triggers],
    }
    summary_text = ai_extraction.generate_summary(stats)

    return SummaryResponse(
        period=period,
        start_date=start,
        end_date=end,
        summary_text=summary_text,
        meals_logged=meals_count,
        top_symptoms=top_symptoms,
        top_triggers=top_triggers,
    )
