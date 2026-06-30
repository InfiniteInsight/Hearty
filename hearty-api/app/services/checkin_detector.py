"""Daily check-in gap detector. Pure logic over a target day's logs.

Gap types (priority order A -> C -> D):
  - symptom_gap   (A): a meal with no symptom within SYMPTOM_GAP_HOURS
  - low_confidence (C): an extracted food below CONFIDENCE_THRESHOLD
  - missing_chunk (D): a waking-window stretch > MISSING_CHUNK_HOURS with no logs
"""

import os
from datetime import datetime, timedelta

SYMPTOM_GAP_HOURS = float(os.environ.get("CHECKIN_SYMPTOM_GAP_HOURS", "3"))
MISSING_CHUNK_HOURS = float(os.environ.get("CHECKIN_MISSING_CHUNK_HOURS", "5"))
CONFIDENCE_THRESHOLD = float(os.environ.get("CHECKIN_CONFIDENCE_THRESHOLD", "0.6"))

# Priority weight: lower sorts first.
_PRIORITY = {"symptom_gap": 0, "low_confidence": 1, "missing_chunk": 2}


def _parse(ts: str) -> datetime:
    return datetime.fromisoformat(ts)


def _meal_label(meal) -> str | None:
    """A clean, human meal label from the structured `foods` names.

    The raw `meals.description` is the user's utterance ("had a salad for lunch")
    and reads badly inline, so we build the label from `foods[].name` instead:
    one name as-is, 2–3 comma-joined, and longer lists capped at three + " +N
    more". Returns None when the meal has no usable food names, so the caller can
    fall back to the generic `prompt`."""
    names = [
        (f.get("name") or "").strip()
        for f in (meal.get("foods") or [])
        if (f.get("name") or "").strip()
    ]
    if not names:
        return None
    if len(names) <= 3:
        return ", ".join(names)
    return ", ".join(names[:3]) + f" +{len(names) - 3} more"


def _meal_context(meal) -> dict:
    """Structured context attached to meal-anchored gaps so the client can
    compose a specific question (with a device-local time)."""
    return {
        "meal_label": _meal_label(meal),
        "meal_time": meal.get("logged_at"),
        "meal_type": meal.get("meal_type"),
    }


def _detect_missing_chunks(meals, now, waking_start_hour, waking_end_hour):
    """Flag stretches > MISSING_CHUNK_HOURS with no meals, inside the waking
    window, only up to `now` (never the unlived part of the day)."""
    day = now.date()
    waking_start = now.replace(hour=int(waking_start_hour), minute=0,
                               second=0, microsecond=0)
    waking_end = now.replace(hour=int(waking_end_hour), minute=0,
                             second=0, microsecond=0)
    window_end_cap = min(now, waking_end)

    # Clamp meal times into [waking_start, window_end_cap]. A meal logged before
    # the waking window starts (e.g. 6am coffee) or after the cap must not be
    # spliced between the boundary endpoints — that would make `boundaries`
    # non-monotonic and flag a spurious gap. Outside-window meals don't define
    # in-window stretches, so they're excluded from the scan.
    times = sorted(t for t in (_parse(m["logged_at"]) for m in meals
                               if _parse(m["logged_at"]).date() == day)
                   if waking_start <= t <= window_end_cap)
    boundaries = [waking_start] + times + [window_end_cap]

    gaps = []
    threshold = timedelta(hours=MISSING_CHUNK_HOURS)
    for a, b in zip(boundaries, boundaries[1:]):
        if b - a > threshold:
            gaps.append({
                "type": "missing_chunk",
                "window_start": a.isoformat(),
                "window_end": b.isoformat(),
                "prompt": "I don't see anything logged for a stretch there — "
                          "did you eat in that window?",
            })
    return gaps


def _detect_symptom_gaps(meals, symptoms):
    gap_window = timedelta(hours=SYMPTOM_GAP_HOURS)
    sym_by_meal = {}
    for s in symptoms:
        mid = s.get("meal_id")
        if mid:
            t = _parse(s["logged_at"])
            sym_by_meal.setdefault(mid, []).append(t)

    gaps = []
    for m in meals:
        status = m.get("followup_status")
        if status in ("answered", "pending", "resurfaced"):
            continue
        meal_time = _parse(m["logged_at"])
        sym_times = sym_by_meal.get(m["id"], [])
        has_symptom = any(meal_time <= t <= meal_time + gap_window
                          for t in sym_times)
        if has_symptom:
            continue
        gaps.append({
            "type": "symptom_gap",
            "meal_id": m["id"],
            "prompt": "How did your stomach feel after that meal?",
            **_meal_context(m),
        })
    return gaps


def _detect_low_confidence(meals):
    gaps = []
    for m in meals:
        for food in m.get("foods") or []:
            conf = food.get("confidence")
            if conf is not None and float(conf) < CONFIDENCE_THRESHOLD:
                gaps.append({
                    "type": "low_confidence",
                    "meal_id": m["id"],
                    "food_name": food.get("name", ""),
                    "prompt": f"I logged \"{food.get('name','')}\" but wasn't "
                              "sure I got it right — did I?",
                    **_meal_context(m),
                })
    return gaps


def _gap_key(g) -> str:
    """A stable identity for a gap, used to dismiss it for the day. Deterministic
    given the underlying data, so the same gap computed on a later request hashes
    to the same key (and a genuinely new gap gets a different one)."""
    t = g["type"]
    if t == "symptom_gap":
        return f"symptom:{g['meal_id']}"
    if t == "low_confidence":
        return f"food:{g['meal_id']}:{g.get('food_name', '')}"
    if t == "missing_chunk":
        return f"chunk:{g['window_start']}"
    return f"{t}:{g.get('prompt', '')}"


def detect_gaps(meals, symptoms, now, *, waking_start_hour=8,
                waking_end_hour=22, follow_up_status=None, dismissed=None):
    """Return gaps ordered by priority (A -> C -> D), then by recency within type.

    Each gap carries a ``gap_key`` (see ``_gap_key``). Gaps whose key is in
    ``dismissed`` (a set the user skipped earlier today) are filtered out, so a
    skipped gap stays gone while a new gap still surfaces.

    follow_up_status: optional dict meal_id -> 'answered'|'dismissed'|'pending'
    (used by gap A; ignored until then)."""
    dismissed = dismissed or set()
    gaps = []
    gaps += _detect_symptom_gaps(meals, symptoms)
    gaps += _detect_low_confidence(meals)
    gaps += _detect_missing_chunks(meals, now, waking_start_hour, waking_end_hour)
    for g in gaps:
        g["gap_key"] = _gap_key(g)
    gaps = [g for g in gaps if g["gap_key"] not in dismissed]
    gaps.sort(key=lambda g: _PRIORITY[g["type"]])
    return gaps
