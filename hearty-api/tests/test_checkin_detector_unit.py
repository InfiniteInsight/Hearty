from datetime import datetime, timezone, timedelta
from app.services.checkin_detector import detect_gaps, MISSING_CHUNK_HOURS


def _dt(h, m=0):
    return datetime(2026, 6, 3, h, m, tzinfo=timezone.utc)


def test_waking_window_follows_the_timezone_of_now():
    # When `now` is tz-aware in the user's local zone, the missing-chunk window
    # must be anchored to local waking hours — NOT shifted by the UTC offset.
    # (Regression: a UTC `now` made the 8am waking-start render as 4am at UTC-4.)
    eastern = timezone(timedelta(hours=-4))
    now = datetime(2026, 6, 3, 22, 0, tzinfo=eastern)  # 10pm local
    gaps = detect_gaps([], symptoms=[], now=now,
                       waking_start_hour=8, waking_end_hour=22)
    d = [g for g in gaps if g["type"] == "missing_chunk"]
    assert len(d) == 1
    start = datetime.fromisoformat(d[0]["window_start"])
    assert start.hour == 8                      # 8am, not 4am
    assert start.utcoffset() == timedelta(hours=-4)  # in the user's zone


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


def test_low_confidence_food_flagged():
    meals = [{"id": "m1", "logged_at": _dt(13).isoformat(),
              "foods": [{"name": "buldak ramen", "confidence": 0.45}]}]
    gaps = detect_gaps(meals, symptoms=[], now=_dt(22))
    c = [g for g in gaps if g["type"] == "low_confidence"]
    assert len(c) == 1
    assert c[0]["meal_id"] == "m1"
    assert c[0]["food_name"] == "buldak ramen"


def test_confident_food_not_flagged():
    meals = [{"id": "m1", "logged_at": _dt(13).isoformat(),
              "foods": [{"name": "apple", "confidence": 0.97}]}]
    gaps = detect_gaps(meals, symptoms=[], now=_dt(22))
    assert [g for g in gaps if g["type"] == "low_confidence"] == []


def test_food_without_confidence_is_not_flagged():
    # Legacy meals (pre-confidence) must not all light up as gaps.
    meals = [{"id": "m1", "logged_at": _dt(13).isoformat(),
              "foods": [{"name": "apple"}]}]
    gaps = detect_gaps(meals, symptoms=[], now=_dt(22))
    assert [g for g in gaps if g["type"] == "low_confidence"] == []


def _meal(mid, hour, status=None):
    return {"id": mid, "logged_at": _dt(hour).isoformat(),
            "foods": [{"name": "x"}], "followup_status": status}


def test_symptom_gap_for_meal_without_symptom():
    meals = [_meal("m1", 13)]
    gaps = detect_gaps(meals, symptoms=[], now=_dt(22))
    a = [g for g in gaps if g["type"] == "symptom_gap"]
    assert len(a) == 1 and a[0]["meal_id"] == "m1"


def test_no_symptom_gap_when_symptom_logged_within_window():
    meals = [_meal("m1", 13)]
    symptoms = [{"meal_id": "m1", "logged_at": _dt(14).isoformat()}]
    gaps = detect_gaps(meals, symptoms=symptoms, now=_dt(22))
    assert [g for g in gaps if g["type"] == "symptom_gap"] == []


def test_answered_followup_excluded():
    gaps = detect_gaps([_meal("m1", 13, "answered")], symptoms=[], now=_dt(22))
    assert [g for g in gaps if g["type"] == "symptom_gap"] == []


def test_pending_followup_excluded():
    gaps = detect_gaps([_meal("m1", 13, "pending")], symptoms=[], now=_dt(22))
    assert [g for g in gaps if g["type"] == "symptom_gap"] == []


def test_dismissed_followup_resurfaces_once():
    gaps = detect_gaps([_meal("m1", 13, "dismissed")], symptoms=[], now=_dt(22))
    a = [g for g in gaps if g["type"] == "symptom_gap"]
    assert len(a) == 1 and a[0]["meal_id"] == "m1"


def test_resurfaced_followup_excluded():
    gaps = detect_gaps([_meal("m1", 13, "resurfaced")], symptoms=[], now=_dt(22))
    assert [g for g in gaps if g["type"] == "symptom_gap"] == []


def test_meal_before_waking_window_does_not_flag_spurious_gap():
    # 6am coffee (before waking_start 8am) + lunch 12:30, now 10pm. The pre-waking
    # meal must NOT splice into the boundary scan and create a phantom 6:00->12:30
    # gap (the non-monotonic-boundary bug).
    meals = [
        {"id": "m1", "logged_at": _dt(6).isoformat(), "foods": [{"name": "coffee"}]},
        {"id": "m2", "logged_at": _dt(12, 30).isoformat(), "foods": [{"name": "salad"}]},
    ]
    gaps = detect_gaps(meals, symptoms=[], now=_dt(22),
                       waking_start_hour=8, waking_end_hour=22)
    d = [g for g in gaps if g["type"] == "missing_chunk"]
    # Only the legitimate trailing 12:30->22:00 (9.5h) gap; no phantom morning one.
    assert len(d) == 1
    assert (d[0]["window_start"], d[0]["window_end"]) == \
        (_dt(12, 30).isoformat(), _dt(22).isoformat())


def test_symptom_gap_carries_meal_context():
    meals = [{"id": "m1", "logged_at": _dt(12, 30).isoformat(),
              "meal_type": "lunch",
              "foods": [{"name": "grilled chicken salad"}]}]
    gaps = detect_gaps(meals, symptoms=[], now=_dt(22))
    a = [g for g in gaps if g["type"] == "symptom_gap"][0]
    assert a["meal_label"] == "grilled chicken salad"
    assert a["meal_time"] == _dt(12, 30).isoformat()
    assert a["meal_type"] == "lunch"


def test_low_confidence_carries_meal_context():
    meals = [{"id": "m1", "logged_at": _dt(13).isoformat(), "meal_type": "snack",
              "foods": [{"name": "buldak ramen", "confidence": 0.4}]}]
    gaps = detect_gaps(meals, symptoms=[], now=_dt(22))
    c = [g for g in gaps if g["type"] == "low_confidence"][0]
    assert c["meal_label"] == "buldak ramen"
    assert c["meal_time"] == _dt(13).isoformat()
    assert c["meal_type"] == "snack"


def test_meal_label_joins_two_or_three_foods():
    meals = [{"id": "m1", "logged_at": _dt(18).isoformat(),
              "foods": [{"name": "chicken"}, {"name": "rice"}, {"name": "broccoli"}]}]
    gaps = detect_gaps(meals, symptoms=[], now=_dt(22))
    a = [g for g in gaps if g["type"] == "symptom_gap"][0]
    assert a["meal_label"] == "chicken, rice, broccoli"


def test_meal_label_caps_long_lists_with_more():
    meals = [{"id": "m1", "logged_at": _dt(18).isoformat(),
              "foods": [{"name": "a"}, {"name": "b"}, {"name": "c"},
                        {"name": "d"}, {"name": "e"}]}]
    gaps = detect_gaps(meals, symptoms=[], now=_dt(22))
    a = [g for g in gaps if g["type"] == "symptom_gap"][0]
    assert a["meal_label"] == "a, b, c +2 more"


def test_meal_label_null_when_no_foods():
    meals = [{"id": "m1", "logged_at": _dt(18).isoformat(), "foods": []}]
    gaps = detect_gaps(meals, symptoms=[], now=_dt(22))
    a = [g for g in gaps if g["type"] == "symptom_gap"][0]
    assert a["meal_label"] is None
    # prompt stays as the fallback the client renders when label is null.
    assert a["prompt"] == "How did your stomach feel after that meal?"


def test_interval_exactly_at_threshold_is_not_flagged():
    # 8:00 and 13:00 = exactly 5h; strict `>` means no gap. (8:00 == waking_start,
    # so no leading gap; trailing 13:00->14:00 is 1h.)
    meals = [
        {"id": "m1", "logged_at": _dt(8).isoformat(), "foods": [{"name": "a"}]},
        {"id": "m2", "logged_at": _dt(13).isoformat(), "foods": [{"name": "b"}]},
    ]
    gaps = detect_gaps(meals, symptoms=[], now=_dt(14),
                       waking_start_hour=8, waking_end_hour=22)
    assert [g for g in gaps if g["type"] == "missing_chunk"] == []
