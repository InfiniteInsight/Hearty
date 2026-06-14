from app.services.signal_persistence import compute_persistence


def _row(cat, year, score=0.7, outcome="bloating"):
    return {"category": cat, "year": year, "outcome_type": "symptom",
            "outcome_name": outcome, "unified_score": score}


def test_recurring_across_years():
    rows = [_row("dairy", 2024), _row("dairy", 2025, 0.8)]
    out = compute_persistence({"dairy"}, rows, current_year=2026)
    p = out["dairy"]
    assert p["years_seen"] == [2024, 2025]
    assert p["recurring"] is True
    assert p["is_new"] is False
    assert p["strength_by_year"] == {"2024": 0.7, "2025": 0.8}


def test_new_this_year_only():
    rows = [_row("gluten", 2026)]
    out = compute_persistence({"gluten"}, rows, current_year=2026)
    p = out["gluten"]
    assert p["years_seen"] == [2026]
    assert p["recurring"] is False
    assert p["is_new"] is True


def test_live_only_category_with_no_yearly_rows_is_new():
    out = compute_persistence({"soy"}, [], current_year=2026)
    p = out["soy"]
    assert p["years_seen"] == []
    assert p["recurring"] is False
    assert p["is_new"] is True


def test_only_live_categories_are_returned():
    rows = [_row("dairy", 2024), _row("ginger", 2024)]
    out = compute_persistence({"dairy"}, rows, current_year=2026)
    assert set(out.keys()) == {"dairy"}


def test_strength_takes_max_when_year_has_multiple_outcomes():
    rows = [_row("dairy", 2025, 0.5, outcome="bloating"),
            _row("dairy", 2025, 0.9, outcome="cramps")]
    out = compute_persistence({"dairy"}, rows, current_year=2026)
    assert out["dairy"]["strength_by_year"] == {"2025": 0.9}
    assert out["dairy"]["years_seen"] == [2025]
