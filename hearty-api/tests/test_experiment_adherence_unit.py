from datetime import datetime, timezone
from app.services.experiment_adherence import compute_adherence, should_nudge


def _meal(day, foods):
    return {"logged_at": datetime(2026, 6, day, 12, tzinfo=timezone.utc).isoformat(),
            "foods": [{"name": f} for f in foods]}


def _classify(names, cache=None):
    # 'milk'/'cheese' -> dairy; everything else uncategorized
    return {n: (["dairy"] if n in ("milk", "cheese") else []) for n in names}


def test_clean_and_violation_days():
    meals = [
        _meal(1, ["apple"]),          # clean
        _meal(2, ["cheese"]),         # violation
        _meal(3, ["rice", "milk"]),   # violation (milk)
        _meal(4, ["toast"]),          # clean
    ]
    a = compute_adherence(meals, "dairy", classify=_classify)
    assert a["logged_days"] == 4
    assert a["clean_days"] == 2
    assert a["adherence"] == 0.5


def test_multiple_meals_same_day_one_violation_taints_day():
    meals = [_meal(1, ["apple"]), _meal(1, ["cheese"])]  # same day, one dirty
    a = compute_adherence(meals, "dairy", classify=_classify)
    assert a["logged_days"] == 1
    assert a["clean_days"] == 0
    assert a["adherence"] == 0.0


def test_no_meals_is_zero_logged_days_not_divide_by_zero():
    a = compute_adherence([], "dairy", classify=_classify)
    assert a == {"clean_days": 0, "logged_days": 0, "adherence": 0.0}


def test_should_nudge_only_when_low_after_min_days_and_not_yet_nudged():
    # below 0.5 after >=4 days, not nudged -> True
    assert should_nudge(adherence=0.4, logged_days=5, nudged_at=None) is True
    # adherence fine -> False
    assert should_nudge(adherence=0.8, logged_days=5, nudged_at=None) is False
    # too few days (one early slip) -> False
    assert should_nudge(adherence=0.0, logged_days=2, nudged_at=None) is False
    # already nudged -> False
    assert should_nudge(adherence=0.1, logged_days=9, nudged_at="2026-06-10T00:00:00Z") is False
