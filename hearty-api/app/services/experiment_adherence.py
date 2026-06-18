"""Experiment adherence: infer how well the user stayed off the eliminated
category from their normal logs, and decide the one-time mid-course nudge. Pure —
classification is injected (defaults to food_category_service)."""

import os

from app.services.food_category_service import classify_foods_cached

NUDGE_ADHERENCE = float(os.environ.get("EXPERIMENT_NUDGE_ADHERENCE", "0.5"))
NUDGE_MIN_DAYS = int(os.environ.get("EXPERIMENT_NUDGE_MIN_DAYS", "4"))


def _default_classify(names):
    return classify_foods_cached(names, {})


def compute_adherence(meals: list, category: str, classify=None) -> dict:
    """A 'clean day' has >=1 logged meal and no meal containing `category`.
    adherence = clean_days / logged_days. No meals -> all zeros (no divide-by-0)."""
    classify = classify or _default_classify
    names = []
    for m in meals:
        for f in (m.get("foods") or []):
            n = (f.get("name") or "").strip().lower()
            if n:
                names.append(n)
    category_map = classify(list(set(names)))

    by_day: dict[str, bool] = {}  # day -> clean so far
    for m in meals:
        day = m["logged_at"][:10]  # YYYY-MM-DD
        dirty = any(
            category in category_map.get((f.get("name") or "").strip().lower(), [])
            for f in (m.get("foods") or [])
        )
        by_day[day] = by_day.get(day, True) and not dirty

    logged_days = len(by_day)
    clean_days = sum(1 for clean in by_day.values() if clean)
    adherence = (clean_days / logged_days) if logged_days else 0.0
    return {"clean_days": clean_days, "logged_days": logged_days,
            "adherence": adherence}


def should_nudge(adherence: float, logged_days: int, nudged_at) -> bool:
    """One-time mid-course nudge: low adherence, enough days elapsed, not nudged yet."""
    if nudged_at:
        return False
    if logged_days < NUDGE_MIN_DAYS:
        return False
    return adherence < NUDGE_ADHERENCE
