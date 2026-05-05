import os
from datetime import datetime, timezone, timedelta

from supabase import create_client

supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])

_ONSET_WINDOW_MINUTES = 240


def analyze_triggers(
    user_id: str,
    analysis_period_days: int,
    focus_symptom: str | None,
    min_occurrences: int,
) -> dict:
    now = datetime.now(timezone.utc)
    start = now - timedelta(days=analysis_period_days)

    meals_result = (
        supabase.table("meals")
        .select("id, foods, logged_at")
        .eq("user_id", user_id)
        .gte("logged_at", start.isoformat())
        .lte("logged_at", now.isoformat())
        .execute()
    )
    meals = meals_result.data or []

    symptoms_query = (
        supabase.table("symptoms")
        .select("id, meal_id, symptom_type, severity, onset_minutes, logged_at")
        .eq("user_id", user_id)
        .gte("logged_at", start.isoformat())
        .lte("logged_at", now.isoformat())
    )
    if focus_symptom:
        symptoms_query = symptoms_query.eq("symptom_type", focus_symptom)
    symptoms_result = symptoms_query.execute()
    symptoms = symptoms_result.data or []

    symptoms_by_meal: dict[str, list] = {}
    for s in symptoms:
        mid = s.get("meal_id")
        if mid:
            symptoms_by_meal.setdefault(mid, []).append(s)

    # co_occurrences: (food_name, symptom_type) → [{onset_minutes, severity}]
    co_occurrences: dict[tuple[str, str], list[dict]] = {}
    # meals containing each food (deduplicated per meal)
    food_meal_counts: dict[str, set] = {}

    for meal in meals:
        foods_raw = meal.get("foods") or []
        meal_logged_at = _parse_dt(meal.get("logged_at"))
        meal_id = meal["id"]

        # Dedupe food names within this meal
        food_names = {
            (f.get("name") or "").lower().strip()
            for f in foods_raw
            if (f.get("name") or "").strip()
        }

        # Collect symptoms for this meal — apply window to all (linked or not)
        meal_symptoms = []
        for s in symptoms:
            s_logged = _parse_dt(s.get("logged_at"))
            if s_logged and meal_logged_at:
                diff = (s_logged - meal_logged_at).total_seconds() / 60
                if 0 <= diff <= _ONSET_WINDOW_MINUTES:
                    meal_symptoms.append({"symptom": s, "diff_minutes": diff})
            elif s.get("meal_id") == meal_id:
                # Linked symptom with no parseable timestamp — include unconditionally
                meal_symptoms.append({"symptom": s, "diff_minutes": None})

        for food_name in food_names:
            food_meal_counts.setdefault(food_name, set()).add(meal_id)

            for entry in meal_symptoms:
                s = entry["symptom"]
                s_type = s.get("symptom_type") or ""
                if not s_type:
                    continue
                onset = s.get("onset_minutes")
                if onset is None and entry["diff_minutes"] is not None:
                    onset = int(entry["diff_minutes"])
                key = (food_name, s_type)
                co_occurrences.setdefault(key, []).append({
                    "onset_minutes": onset,
                    "severity": s.get("severity"),
                })

    triggers = []
    for (food_name, symptom_type), occurrences in co_occurrences.items():
        count = len(occurrences)
        if count < min_occurrences:
            continue

        total_meals_with_food = len(food_meal_counts.get(food_name, set())) or count
        co_occurrence_rate = count / total_meals_with_food

        severities = [o["severity"] for o in occurrences if o["severity"] is not None]
        avg_severity = sum(severities) / len(severities) if severities else 0.0

        onsets = [o["onset_minutes"] for o in occurrences if o["onset_minutes"] is not None]
        avg_onset = int(sum(onsets) / len(onsets)) if onsets else None

        # frequency_bonus: scales 0→1 linearly up to 10 occurrences
        frequency_bonus = min(count / 10.0, 1.0)
        confidence = (
            co_occurrence_rate * 0.5
            + (avg_severity / 10.0) * 0.3
            + frequency_bonus * 0.2
        )

        if count >= 6:
            label = "established"
        else:
            label = "early signal, needs more data"

        triggers.append({
            "food_name": food_name,
            "symptom_type": symptom_type,
            "confidence_score": round(confidence, 4),
            "occurrence_count": count,
            "avg_onset_minutes": avg_onset,
            "avg_severity": round(avg_severity, 2) if avg_severity else None,
            "is_confirmed": False,
            "label": label,
        })

    triggers.sort(key=lambda t: t["confidence_score"], reverse=True)

    return {
        "analysis_period_days": analysis_period_days,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "total_meals_analyzed": len(meals),
        "total_symptoms_analyzed": len(symptoms),
        "triggers": triggers,
    }


def update_food_triggers_table(user_id: str, analysis_period_days: int) -> None:
    result = analyze_triggers(
        user_id=user_id,
        analysis_period_days=analysis_period_days,
        focus_symptom=None,
        min_occurrences=3,
    )
    for trigger in result["triggers"]:
        supabase.table("food_triggers").upsert(
            {
                "user_id": user_id,
                "food_name": trigger["food_name"],
                "symptom_type": trigger["symptom_type"],
                "confidence_score": trigger["confidence_score"],
                "occurrence_count": trigger["occurrence_count"],
                "avg_onset_minutes": trigger["avg_onset_minutes"],
                "avg_severity": trigger["avg_severity"],
                "is_confirmed": trigger["is_confirmed"],
                "last_updated": datetime.now(timezone.utc).isoformat(),
            },
            on_conflict="user_id,food_name,symptom_type",
        ).execute()


def _parse_dt(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt
    except (ValueError, AttributeError):
        return None
