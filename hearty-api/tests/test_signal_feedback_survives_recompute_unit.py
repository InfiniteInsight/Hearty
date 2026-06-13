from app.services.signal_presenter import apply_overlay


def _sig(score):
    return {"category": "dairy", "outcome_type": "symptom",
            "outcome_name": "bloating", "direction": "harmful",
            "unified_score": score, "relative_risk": 2.0, "evidence_count": 8}


def test_disputed_verdict_still_applies_to_freshly_recomputed_signal():
    feedback = [{"category": "dairy", "outcome_type": "symptom",
                 "outcome_name": "bloating", "verdict": "disputed",
                 "score_at_verdict": 0.50}]
    recomputed = [_sig(0.52)]
    out = apply_overlay(recomputed, feedback, previously_surfaced=set())
    assert out == []
