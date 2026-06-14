from app.services.signal_presenter import apply_overlay, RESURFACE_MARGIN


def _sig(cat, score, outcome="bloating", otype="symptom", **kw):
    base = {
        "category": cat, "outcome_type": otype, "outcome_name": outcome,
        "direction": "harmful", "unified_score": score,
        "relative_risk": 2.0, "evidence_count": 8,
    }
    base.update(kw)
    return base


def test_unverdicted_signals_pass_through_ranked_by_score():
    signals = [_sig("dairy", 0.40), _sig("gluten", 0.80)]
    out = apply_overlay(signals, feedback=[], previously_surfaced=set())
    assert [s.category for s in out] == ["gluten", "dairy"]
    assert out[0].unified_score == 0.80


def test_disputed_signal_is_suppressed():
    signals = [_sig("dairy", 0.50)]
    feedback = [{"category": "dairy", "outcome_type": "symptom",
                 "outcome_name": "bloating", "verdict": "disputed",
                 "score_at_verdict": 0.50}]
    out = apply_overlay(signals, feedback=feedback, previously_surfaced=set())
    assert out == []


def test_disputed_signal_resurfaces_when_much_stronger():
    signals = [_sig("dairy", 0.50 + RESURFACE_MARGIN + 0.01)]
    feedback = [{"category": "dairy", "outcome_type": "symptom",
                 "outcome_name": "bloating", "verdict": "disputed",
                 "score_at_verdict": 0.50}]
    out = apply_overlay(signals, feedback=feedback, previously_surfaced=set())
    assert len(out) == 1
    assert out[0].is_resurfaced is True


def test_confirmed_signal_is_flagged_not_suppressed():
    signals = [_sig("dairy", 0.50)]
    feedback = [{"category": "dairy", "outcome_type": "symptom",
                 "outcome_name": "bloating", "verdict": "confirmed",
                 "score_at_verdict": 0.50}]
    out = apply_overlay(signals, feedback=feedback, previously_surfaced=set())
    assert len(out) == 1
    assert out[0].is_confirmed is True


def test_new_since_last_conversation_is_flagged():
    signals = [_sig("dairy", 0.50), _sig("gluten", 0.40)]
    surfaced = {("dairy", "symptom", "bloating")}
    out = apply_overlay(signals, feedback=[], previously_surfaced=surfaced)
    by_cat = {s.category: s for s in out}
    assert by_cat["dairy"].is_new is False
    assert by_cat["gluten"].is_new is True


def test_load_presented_signals_attaches_recurrence(monkeypatch):
    from app.services import signal_presenter as sp

    class _R:
        def __init__(self, data): self.data = data
    class _Q:
        def __init__(self, rows): self._rows = rows
        def select(self, *a, **k): return self
        def eq(self, *a, **k): return self
        def execute(self): return _R(self._rows)
    class _S:
        def table(self, name):
            if name == "food_signals":
                return _Q([{"category": "dairy", "outcome_type": "symptom",
                            "outcome_name": "bloating", "direction": "harmful",
                            "unified_score": 0.8, "relative_risk": 2.0,
                            "evidence_count": 9}])
            if name == "signal_feedback":
                return _Q([])
            if name == "food_signals_yearly":
                return _Q([
                    {"category": "dairy", "year": 2024, "outcome_type": "symptom",
                     "outcome_name": "bloating", "unified_score": 0.7},
                    {"category": "dairy", "year": 2025, "outcome_type": "symptom",
                     "outcome_name": "bloating", "unified_score": 0.8},
                ])
            return _Q([])

    out = sp.load_presented_signals(_S(), "u1")
    dairy = next(s for s in out if s.category == "dairy")
    assert dairy.recurring is True
    assert dairy.years_seen == [2024, 2025]
