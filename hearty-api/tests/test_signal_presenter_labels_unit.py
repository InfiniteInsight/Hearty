"""GET /api/trends surfaces friendly category_label on signal responses.

Drives the real build path in routers/trends.py: a food_signals row with
category='dairy_casein' must produce a FoodSignal whose category_label is the
TAXONOMY display name ('Dairy / Casein'), and a last-year-only category must
produce a ResolvedSignal carrying its friendly label too. The supabase chain is
faked per-table so the endpoint body runs without real I/O.
"""
from fastapi.testclient import TestClient

from app.main import app
from app.auth import get_current_user
from app.routers import trends as trends_module


class _Result:
    def __init__(self, data, count=0):
        self.data = data
        self.count = count


class _Q:
    """Permissive chained-query fake returning preset rows on execute()."""
    def __init__(self, rows, count=0):
        self._rows = rows
        self._count = count

    def __getattr__(self, _name):
        # select/eq/order/gte/maybe_single all chain and return self.
        return lambda *a, **k: self

    def execute(self):
        return _Result(self._rows, self._count)


class _Supa:
    def table(self, name):
        if name == "food_signals":
            return _Q([{
                "category": "dairy_casein", "outcome_type": "symptom",
                "outcome_name": "bloating", "direction": "harmful",
                "unified_score": 0.8, "relative_risk": 2.0, "evidence_count": 9,
            }])
        if name == "food_signals_yearly":
            # 'gluten' present only last year (2025) and absent from the live
            # set -> compute_resolved yields a ResolvedSignal for it.
            return _Q([{
                "category": "gluten", "year": 2025, "outcome_type": "symptom",
                "outcome_name": "bloating", "unified_score": 0.6,
            }])
        # signal_feedback, health_profile, meals/symptoms/wellbeing counts.
        return _Q([], count=0)


def test_trends_signals_carry_friendly_category_label(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    monkeypatch.setattr(trends_module, "supabase", _Supa())
    monkeypatch.setattr(trends_module, "ensure_fresh_signals", lambda uid: False)
    monkeypatch.setattr(trends_module.signal_engine,
                        "ensure_yearly_backfill",
                        lambda uid, recompute_current=False: None)
    # Pin current year so 'gluten' (year 2025) counts as last-year-resolved.
    # trends.py computes current_year via datetime.now(...).year and passes it
    # into compute_resolved, so patching the router's datetime is sufficient.
    class _FixedDT:
        @staticmethod
        def now(tz=None):
            import datetime as _d
            return _d.datetime(2026, 6, 18, tzinfo=tz)

    monkeypatch.setattr(trends_module, "datetime", _FixedDT)

    client = TestClient(app)
    r = client.get("/api/trends")
    assert r.status_code == 200
    body = r.json()

    dairy = next(s for s in body["signals"] if s["category"] == "dairy_casein")
    assert dairy["category_label"] == "Dairy / Casein"

    resolved = next(x for x in body["resolved"] if x["category"] == "gluten")
    assert resolved["category_label"] == "Gluten"
