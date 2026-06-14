from app.services.signal_persistence import compute_resolved


def _row(cat, year, score=0.6):
    return {"category": cat, "year": year, "outcome_type": "symptom",
            "outcome_name": "bloating", "unified_score": score}


def test_unconfirmed_last_year_absent_now_is_potentially_resolved():
    out = compute_resolved([_row("dairy", 2025, 0.6)], live_categories=set(),
                           feedback=[], current_year=2026)
    assert len(out) == 1
    assert out[0]["category"] == "dairy"
    assert out[0]["status"] == "potentially_resolved"
    assert out[0]["last_year"] == 2025


def test_confirmed_last_year_absent_now_is_resolved():
    fb = [{"category": "dairy", "verdict": "confirmed"}]
    out = compute_resolved([_row("dairy", 2025)], set(), fb, current_year=2026)
    assert out[0]["status"] == "resolved"


def test_still_live_category_not_resolved():
    out = compute_resolved([_row("dairy", 2025)], {"dairy"}, [], current_year=2026)
    assert out == []


def test_older_than_last_year_not_resolved():
    out = compute_resolved([_row("dairy", 2023)], set(), [], current_year=2026)
    assert out == []


def test_sorted_by_strength_desc():
    rows = [_row("dairy", 2025, 0.4), _row("gluten", 2025, 0.9)]
    out = compute_resolved(rows, set(), [], current_year=2026)
    assert [r["category"] for r in out] == ["gluten", "dairy"]
