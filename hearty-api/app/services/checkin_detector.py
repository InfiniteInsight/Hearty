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


def _detect_missing_chunks(meals, now, waking_start_hour, waking_end_hour):
    """Flag stretches > MISSING_CHUNK_HOURS with no meals, inside the waking
    window, only up to `now` (never the unlived part of the day)."""
    day = now.date()
    waking_start = now.replace(hour=int(waking_start_hour), minute=0,
                               second=0, microsecond=0)
    waking_end = now.replace(hour=int(waking_end_hour), minute=0,
                             second=0, microsecond=0)
    window_end_cap = min(now, waking_end)

    times = sorted(_parse(m["logged_at"]) for m in meals
                   if _parse(m["logged_at"]).date() == day)
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


def detect_gaps(meals, symptoms, now, *, waking_start_hour=8,
                waking_end_hour=22, follow_up_status=None):
    """Return gaps ordered by priority (A -> C -> D), then by recency within type.

    follow_up_status: optional dict meal_id -> 'answered'|'dismissed'|'pending'
    (used by gap A; ignored until then)."""
    gaps = []
    gaps += _detect_missing_chunks(meals, now, waking_start_hour, waking_end_hour)
    gaps.sort(key=lambda g: _PRIORITY[g["type"]])
    return gaps
