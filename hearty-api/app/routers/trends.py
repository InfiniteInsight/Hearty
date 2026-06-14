import logging
import os
from datetime import datetime, timezone, timedelta
from typing import Optional

from fastapi import APIRouter, Depends, Query, HTTPException
from supabase import create_client

from app.auth import get_current_user
from app.models.schemas import (
    TrendsResponse, TriggerFood, SummaryResponse,
    SignalsResponse, FoodSignal, SignalChannel, ResolvedSignal,
    AnalyzeResponse, AnalyzeStatusResponse,
    TrendsConversationRequest, TrendsConversationResponse,
    SignalVerdictRequest, SignalVerdictResponse,
)
from app.services import (
    ai_extraction, trend_engine, signal_engine,
    signal_presenter, trends_conversation, signal_persistence,
)

logger = logging.getLogger(__name__)
router = APIRouter()
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])

TRENDS_MIN_RECOMPUTE_MINUTES = float(os.environ.get("TRENDS_MIN_RECOMPUTE_MINUTES", "10"))


# ── Signal endpoints (Plan 11) ────────────────────────────────────────────────

@router.get("/api/trends", status_code=200)
async def get_signals(
    user=Depends(get_current_user),
) -> SignalsResponse:
    """Return ranked food signals from the unified signal engine."""
    user_id = user["id"]

    # Automatic refresh: recompute signals when new data has been logged since the
    # last run, so viewing Trends always reflects current data. The manual
    # "Analyse now" button (POST /api/trends/analyze) remains as a force-refresh.
    did_refresh = ensure_fresh_signals(user_id)
    try:
        signal_engine.ensure_yearly_backfill(user_id, recompute_current=did_refresh)
    except Exception as e:  # pragma: no cover - defensive
        logger.error("ensure_yearly_backfill failed: %s", e, exc_info=True)

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

    try:
        yearly_rows = (
            supabase.table("food_signals_yearly")
            .select("category, year, outcome_type, outcome_name, unified_score")
            .eq("user_id", user_id)
            .execute()
        ).data or []
        persistence = signal_persistence.compute_persistence(
            {s.category for s in signals}, yearly_rows,
            current_year=datetime.now(timezone.utc).year,
        )
        signals = [s.model_copy(update=persistence.get(s.category, {})) for s in signals]
    except Exception as e:  # pragma: no cover - defensive
        logger.error("persistence annotation failed: %s", e, exc_info=True)

    resolved: list[dict] = []
    try:
        yearly_rows = (
            supabase.table("food_signals_yearly")
            .select("category, year, outcome_type, outcome_name, unified_score")
            .eq("user_id", user_id)
            .execute()
        ).data or []
        feedback_rows = (
            supabase.table("signal_feedback")
            .select("category, verdict")
            .eq("user_id", user_id)
            .execute()
        ).data or []
        resolved = signal_persistence.compute_resolved(
            yearly_rows, {s.category for s in signals}, feedback_rows,
            current_year=datetime.now(timezone.utc).year,
        )
    except Exception as e:  # pragma: no cover - defensive
        logger.error("compute_resolved failed: %s", e, exc_info=True)
        resolved = []

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
        resolved=[ResolvedSignal(**r) for r in resolved],
    )


@router.post("/api/trends/analyze", status_code=200)
async def trigger_analysis(
    user=Depends(get_current_user),
) -> AnalyzeResponse:
    """Run the full signal analysis for the authenticated user."""
    user_id = user["id"]
    result = signal_engine.run_analysis(user_id, period_days=365)
    try:
        signal_engine.ensure_yearly_backfill(user_id, recompute_current=True)
    except Exception as e:  # pragma: no cover - defensive
        logger.error("ensure_yearly_backfill (manual) failed: %s", e, exc_info=True)
    return AnalyzeResponse(
        status="completed",
        analyzed_at=datetime.now(timezone.utc),
        new_signals_count=result["signals_found"],
    )


def _analysis_status(user_id: str) -> tuple[Optional[str], bool]:
    """Return (last_analyzed_at, has_new_data) for a user.

    has_new_data is True when meals/wellbeing have been logged since the last
    analysis, or when nothing has been analyzed yet but some data exists.
    """
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

    return last_analyzed_at, has_new_data


def ensure_fresh_signals(user_id: str) -> bool:
    """Auto-run the live analysis when new data exists AND the last run is older
    than the debounce window. Returns True if an analysis was run. Best-effort."""
    try:
        last_analyzed_at, has_new_data = _analysis_status(user_id)
        if not has_new_data:
            return False
        if last_analyzed_at:
            last_dt = datetime.fromisoformat(last_analyzed_at.replace("Z", "+00:00"))
            if last_dt.tzinfo is None:
                last_dt = last_dt.replace(tzinfo=timezone.utc)
            if datetime.now(timezone.utc) - last_dt < timedelta(minutes=TRENDS_MIN_RECOMPUTE_MINUTES):
                return False
        signal_engine.run_analysis(user_id)
        return True
    except Exception as e:  # pragma: no cover - defensive
        logger.error("ensure_fresh_signals failed: %s", e, exc_info=True)
        return False


@router.get("/api/trends/analyze/status", status_code=200)
async def get_analysis_status(
    user=Depends(get_current_user),
) -> AnalyzeStatusResponse:
    """Return last_analyzed_at and whether new data exists since then."""
    last_analyzed_at, has_new_data = _analysis_status(user["id"])
    return AnalyzeStatusResponse(
        last_analyzed_at=last_analyzed_at,
        has_new_data=has_new_data,
    )


# ── Monthly Trends Conversation ──────────────────────────────────────────────

@router.post("/api/trends/conversation", status_code=200)
async def trends_conversation_turn(
    body: TrendsConversationRequest,
    user=Depends(get_current_user),
) -> TrendsConversationResponse:
    """Generate Hearty's next turn in the monthly trends conversation, grounded
    in the user's overlay-filtered signals."""
    user_id = user["id"]
    # First turn: ensure the signals are fresh before opening the conversation so
    # the (possibly notification-triggered) chat never discusses stale patterns.
    # Later turns reuse what the first turn computed.
    if not body.history:
        ensure_fresh_signals(user_id)
    signals = signal_presenter.load_presented_signals(supabase, user_id)
    return trends_conversation.generate_turn(signals, body.history)


@router.post("/api/trends/signal-verdict", status_code=200)
async def submit_signal_verdict(
    body: SignalVerdictRequest,
    user=Depends(get_current_user),
) -> SignalVerdictResponse:
    """Record a user's verdict (confirm/dispute/snooze) on a signal. Captures the
    signal's current unified_score so a disputed signal only resurfaces when the
    evidence later grows materially stronger."""
    user_id = user["id"]

    current = (
        supabase.table("food_signals")
        .select("unified_score")
        .eq("user_id", user_id)
        .eq("category", body.category)
        .eq("outcome_type", body.outcome_type)
        .eq("outcome_name", body.outcome_name)
        .limit(1)
        .execute()
    ).data
    score_at_verdict = current[0]["unified_score"] if current else None

    row = {
        "user_id": user_id,
        "category": body.category,
        "outcome_type": body.outcome_type,
        "outcome_name": body.outcome_name,
        "verdict": body.verdict,
        "score_at_verdict": score_at_verdict,
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }
    supabase.table("signal_feedback").upsert(
        row, on_conflict="user_id,category,outcome_type,outcome_name"
    ).execute()
    return SignalVerdictResponse(ok=True)


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
