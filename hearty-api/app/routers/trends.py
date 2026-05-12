import logging
import os
from datetime import datetime, timezone, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, Query, HTTPException
from supabase import create_client

from app.auth import get_current_user
from app.models.schemas import (
    TrendsResponse, TriggerFood, SummaryResponse,
    SignalsResponse, FoodSignal, SignalChannel,
    AnalyzeResponse, AnalyzeStatusResponse,
)
from app.services import ai_extraction, trend_engine, signal_engine

logger = logging.getLogger(__name__)
router = APIRouter()
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


# ── Signal endpoints (Plan 11) ────────────────────────────────────────────────

@router.get("/api/trends", status_code=200)
async def get_signals(
    user=Depends(get_current_user),
) -> SignalsResponse:
    """Return ranked food signals from the unified signal engine."""
    user_id = user["id"]

    rows = (
        supabase.table("food_signals")
        .select("*")
        .eq("user_id", user_id)
        .order("unified_score", desc=True)
        .execute()
    ).data or []

    # Group rows by category to build FoodSignal objects
    by_category: dict[str, list] = {}
    for row in rows:
        by_category.setdefault(row["category"], []).append(row)

    signals: list[FoodSignal] = []
    for category, category_rows in by_category.items():
        channels = [
            SignalChannel(
                outcome_type=r["outcome_type"],
                outcome_name=r["outcome_name"],
                direction=r["direction"],
                peak_window_minutes=r.get("peak_window_minutes"),
                meal_slot=r.get("meal_slot"),
                wellbeing_slot=r.get("wellbeing_slot"),
                relative_risk=r.get("relative_risk"),
                score_delta=r.get("score_delta"),
                evidence_count=r["evidence_count"],
            )
            for r in category_rows
        ]
        has_symptom = any(c.outcome_type == "symptom" for c in channels)
        has_wellbeing = any(c.outcome_type == "wellbeing" for c in channels)
        unified_score = max(
            (r["unified_score"] for r in category_rows if r["unified_score"] is not None),
            default=0.0,
        )
        signals.append(FoodSignal(
            category=category,
            unified_score=float(unified_score),
            channels=channels,
            convergent=has_symptom and has_wellbeing,
        ))

    signals.sort(key=lambda s: s.unified_score, reverse=True)

    # Get last_analyzed_at from health_profile
    profile = (
        supabase.table("health_profile")
        .select("last_analyzed_at")
        .eq("user_id", user_id)
        .maybe_single()
        .execute()
    ).data

    analyzed_at = None
    if profile and profile.get("last_analyzed_at"):
        analyzed_at = profile["last_analyzed_at"]

    # Counts for context
    now = datetime.now(timezone.utc)
    start_90d = (now - timedelta(days=90)).isoformat()

    meals_count = (
        supabase.table("meals")
        .select("id", count="exact")
        .eq("user_id", user_id)
        .gte("logged_at", start_90d)
        .execute()
    ).count or 0

    symptoms_count = (
        supabase.table("symptoms")
        .select("id", count="exact")
        .eq("user_id", user_id)
        .gte("logged_at", start_90d)
        .execute()
    ).count or 0

    wellbeing_count = (
        supabase.table("wellbeing_snapshots")
        .select("id", count="exact")
        .eq("user_id", user_id)
        .gte("logged_at", start_90d)
        .execute()
    ).count or 0

    return SignalsResponse(
        signals=signals,
        analyzed_at=analyzed_at,
        total_meals_analyzed=meals_count,
        total_symptoms_analyzed=symptoms_count,
        total_wellbeing_analyzed=wellbeing_count,
    )


@router.post("/api/trends/analyze", status_code=200)
async def trigger_analysis(
    user=Depends(get_current_user),
) -> AnalyzeResponse:
    """Run the full signal analysis for the authenticated user."""
    user_id = user["id"]
    result = signal_engine.run_analysis(user_id, period_days=90)
    return AnalyzeResponse(
        status="completed",
        analyzed_at=datetime.now(timezone.utc),
        new_signals_count=result["signals_found"],
    )


@router.get("/api/trends/analyze/status", status_code=200)
async def get_analysis_status(
    user=Depends(get_current_user),
) -> AnalyzeStatusResponse:
    """Return last_analyzed_at and whether new data exists since then."""
    user_id = user["id"]

    profile = (
        supabase.table("health_profile")
        .select("last_analyzed_at")
        .eq("user_id", user_id)
        .maybe_single()
        .execute()
    ).data

    last_analyzed_at = None
    if profile and profile.get("last_analyzed_at"):
        last_analyzed_at = profile["last_analyzed_at"]

    has_new_data = False
    if last_analyzed_at:
        meals_since = (
            supabase.table("meals")
            .select("id", count="exact")
            .eq("user_id", user_id)
            .gte("logged_at", last_analyzed_at)
            .execute()
        ).count or 0

        wb_since = (
            supabase.table("wellbeing_snapshots")
            .select("id", count="exact")
            .eq("user_id", user_id)
            .gte("logged_at", last_analyzed_at)
            .execute()
        ).count or 0

        has_new_data = (meals_since + wb_since) > 0
    else:
        # Never analyzed — check if any data exists at all
        any_meals = (
            supabase.table("meals")
            .select("id", count="exact")
            .eq("user_id", user_id)
            .execute()
        ).count or 0
        has_new_data = any_meals > 0

    return AnalyzeStatusResponse(
        last_analyzed_at=last_analyzed_at,
        has_new_data=has_new_data,
    )


# ── Legacy endpoints (kept until Plan 11 Phase 7 cleanup) ────────────────────

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
