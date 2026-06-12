from datetime import datetime, timezone
from app.services.checkin_detector import detect_gaps, MISSING_CHUNK_HOURS


def _dt(h, m=0):
    return datetime(2026, 6, 3, h, m, tzinfo=timezone.utc)


def test_missing_chunks_between_and_after_meals():
    meals = [
        {"id": "m1", "logged_at": _dt(8).isoformat(), "foods": [{"name": "eggs"}]},
        {"id": "m2", "logged_at": _dt(16).isoformat(), "foods": [{"name": "salad"}]},
    ]
    gaps = detect_gaps(meals, symptoms=[], now=_dt(22),
                       waking_start_hour=8, waking_end_hour=22)
    d_gaps = [g for g in gaps if g["type"] == "missing_chunk"]
    assert len(d_gaps) == 2
    assert (d_gaps[0]["window_start"], d_gaps[0]["window_end"]) == \
        (_dt(8).isoformat(), _dt(16).isoformat())
    assert (d_gaps[1]["window_start"], d_gaps[1]["window_end"]) == \
        (_dt(16).isoformat(), _dt(22).isoformat())


def test_no_missing_chunk_when_meals_evenly_spaced():
    meals = [
        {"id": "m1", "logged_at": _dt(8).isoformat(), "foods": [{"name": "a"}]},
        {"id": "m2", "logged_at": _dt(12).isoformat(), "foods": [{"name": "b"}]},
        {"id": "m3", "logged_at": _dt(16).isoformat(), "foods": [{"name": "c"}]},
        {"id": "m4", "logged_at": _dt(20).isoformat(), "foods": [{"name": "d"}]},
    ]
    gaps = detect_gaps(meals, symptoms=[], now=_dt(22),
                       waking_start_hour=8, waking_end_hour=22)
    assert [g for g in gaps if g["type"] == "missing_chunk"] == []


def test_missing_chunk_only_counts_up_to_now():
    meals = [{"id": "m1", "logged_at": _dt(8).isoformat(), "foods": [{"name": "a"}]}]
    gaps = detect_gaps(meals, symptoms=[], now=_dt(14),
                       waking_start_hour=8, waking_end_hour=22)
    d_gaps = [g for g in gaps if g["type"] == "missing_chunk"]
    assert len(d_gaps) == 1
    assert d_gaps[0]["window_end"] == _dt(14).isoformat()
