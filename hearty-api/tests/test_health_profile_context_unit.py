from datetime import datetime, timezone

from app.health_profile import context as ctx
from app.health_profile.context import (
    build_health_profile_context,
    load_health_profile_context,
)
from app.health_profile.schemas import HealthProfileResponse


_UPDATED = datetime(2026, 6, 1, tzinfo=timezone.utc)


def _full_profile() -> HealthProfileResponse:
    return HealthProfileResponse(
        allergens=[
            {"name": "milk", "severity": "severe", "confirmed_by_doctor": True},
            {"name": "peanuts", "severity": "moderate"},
        ],
        intolerances=[
            {"name": "lactose"},
            {"name": "histamine"},
        ],
        conditions=[
            {"name": "IBS-D", "diagnosed": True, "diagnosis_year": 2022},
            {"name": "GERD", "diagnosed": True},
        ],
        dietary_protocols=[
            {
                "name": "low-FODMAP",
                "active": True,
                "started": "2026-01-01",
                "phase": "elimination",
            },
        ],
        updated_at=_UPDATED,
    )


# ── build_health_profile_context ─────────────────────────────────────────────


def test_full_profile_matches_spec_9_1_exactly():
    expected = (
        "User health profile:\n"
        "- Allergens: milk (severe, confirmed), peanuts (moderate)\n"
        "- Intolerances: lactose, histamine\n"
        "- Conditions: IBS-D (diagnosed 2022), GERD\n"
        "- Dietary protocols: low-FODMAP elimination phase (started 2026-01-01)\n"
        "\n"
        "When analyzing meals and symptoms:\n"
        "- Flag any meal containing milk or peanuts regardless of symptom presence\n"
        "- Cross-reference logged foods against FODMAP content\n"
        "- Note acid-triggering foods for GERD relevance\n"
        "- Use IBS-D context when interpreting bathroom urgency and stool consistency patterns"
    )
    assert build_health_profile_context(_full_profile()) == expected


def test_empty_profile_returns_empty_string():
    profile = HealthProfileResponse(updated_at=_UPDATED)
    assert build_health_profile_context(profile) == ""


def test_partial_allergens_only():
    profile = HealthProfileResponse(
        allergens=[
            {"name": "milk", "severity": "severe", "confirmed_by_doctor": True},
            {"name": "peanuts", "severity": "moderate"},
        ],
        updated_at=_UPDATED,
    )
    result = build_health_profile_context(profile)

    # Allergen listing + analysis flag present.
    assert "- Allergens: milk (severe, confirmed), peanuts (moderate)" in result
    assert (
        "- Flag any meal containing milk or peanuts regardless of symptom presence"
        in result
    )
    # No condition/protocol/intolerance listing bullets.
    assert "Intolerances:" not in result
    assert "Conditions:" not in result
    assert "Dietary protocols:" not in result
    # No condition/protocol analysis bullets.
    assert "FODMAP" not in result
    assert "GERD" not in result
    assert "IBS" not in result


# ── load_health_profile_context ──────────────────────────────────────────────


class _Result:
    def __init__(self, data):
        self.data = data


def _supa(rows):
    class _T:
        def select(self, *a, **k):
            return self

        def eq(self, *a, **k):
            return self

        def execute(self):
            return _Result(rows)

    return type("S", (), {"table": lambda s, n: _T()})()


def test_load_no_row_returns_empty(monkeypatch):
    monkeypatch.setattr(ctx, "supabase", _supa([]))
    assert load_health_profile_context("user-123") == ""


def test_load_one_row_returns_block(monkeypatch):
    row = {
        "allergens": [
            {"name": "milk", "severity": "severe", "confirmed_by_doctor": True},
        ],
        "intolerances": [],
        "conditions": [],
        "dietary_protocols": [],
        "updated_at": "2026-06-01T00:00:00+00:00",
    }
    monkeypatch.setattr(ctx, "supabase", _supa([row]))
    result = load_health_profile_context("user-123")
    assert result != ""
    assert "User health profile:" in result
    assert "- Allergens: milk (severe, confirmed)" in result
