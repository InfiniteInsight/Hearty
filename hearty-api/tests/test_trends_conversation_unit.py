import json
from unittest.mock import patch
from types import SimpleNamespace

from app.models.schemas import PresentedSignal, ConversationTurn
from app.services import trends_conversation as tc


def _presented():
    return [
        PresentedSignal(category="dairy", outcome_type="symptom",
                        outcome_name="bloating", direction="harmful",
                        unified_score=0.82, relative_risk=2.4, evidence_count=9,
                        is_new=True),
        PresentedSignal(category="ginger", outcome_type="wellbeing",
                        outcome_name="energy_level", direction="beneficial",
                        unified_score=0.41, relative_risk=None, evidence_count=6),
    ]


def test_build_system_prompt_includes_signals_and_coverage_rule():
    prompt = tc.build_system_prompt(_presented())
    assert "dairy" in prompt and "bloating" in prompt
    assert "ginger" in prompt
    assert "before" in prompt.lower() and "finish" in prompt.lower()
    assert "proposed_verdict" in prompt and "is_closing" in prompt


def test_generate_turn_parses_envelope():
    fake = SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(
        content=json.dumps({
            "reply": "The big one this month is dairy before your bloating.",
            "proposed_verdict": None,
            "is_closing": False,
        })))])
    with patch.object(tc.litellm, "completion", return_value=fake):
        out = tc.generate_turn(_presented(), history=[])
    assert out.reply.startswith("The big one")
    assert out.proposed_verdict is None
    assert out.is_closing is False


def test_signal_line_tags_recurring():
    s = PresentedSignal(category="dairy", outcome_type="symptom",
                        outcome_name="bloating", direction="harmful",
                        unified_score=0.8, relative_risk=2.0, evidence_count=9,
                        recurring=True, years_seen=[2024, 2025, 2026])
    line = tc._signal_line(s)
    assert "RECURRING 3 years" in line


def test_system_prompt_mentions_recurrence_confidence():
    from app.models.schemas import PresentedSignal as PS
    prompt = tc.build_system_prompt([PS(category="dairy", outcome_type="symptom",
        outcome_name="bloating", direction="harmful", unified_score=0.8,
        relative_risk=2.0, evidence_count=9)])
    assert "recurring" in prompt.lower()


def test_generate_turn_parses_proposed_verdict():
    fake = SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(
        content=json.dumps({
            "reply": "Got it — want me to mark dairy as not a problem for you?",
            "proposed_verdict": {"category": "dairy", "outcome_type": "symptom",
                                 "outcome_name": "bloating", "verdict": "disputed"},
            "is_closing": False,
        })))])
    history = [ConversationTurn(role="user", content="nah dairy's fine for me")]
    with patch.object(tc.litellm, "completion", return_value=fake):
        out = tc.generate_turn(_presented(), history=history)
    assert out.proposed_verdict is not None
    assert out.proposed_verdict.category == "dairy"
    assert out.proposed_verdict.verdict == "disputed"


def test_generate_turn_parses_proposed_experiment():
    fake = SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(
        content=json.dumps({
            "reply": "Want to actually test the dairy link — cut it for two weeks?",
            "proposed_verdict": None,
            "proposed_experiment": {"category": "dairy_casein", "outcome_type": "symptom",
                                    "outcome_name": "bloating"},
            "is_closing": False,
        })))])
    with patch.object(tc.litellm, "completion", return_value=fake):
        out = tc.generate_turn(_presented(), history=[])
    assert out.proposed_experiment is not None
    assert out.proposed_experiment.category == "dairy_casein"
    assert out.proposed_experiment.category_label == "Dairy / Casein"
