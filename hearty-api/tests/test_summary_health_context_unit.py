import json
from types import SimpleNamespace
from unittest.mock import patch

from app.services import ai_extraction


def _fake_response(text="summary text"):
    return SimpleNamespace(
        choices=[SimpleNamespace(message=SimpleNamespace(content=text))]
    )


def _capture_prompt():
    """Patch litellm.completion; return (mock, getter) for the sent prompt."""
    holder = {}

    def fake_completion(*args, **kwargs):
        holder["messages"] = kwargs["messages"]
        return _fake_response()

    return fake_completion, holder


def test_generate_summary_includes_health_context():
    fake_completion, holder = _capture_prompt()
    with patch.object(ai_extraction.litellm, "completion", side_effect=fake_completion):
        ai_extraction.generate_summary(
            {"meals_logged": 3}, health_context="HP-SUMMARY-SENTINEL"
        )
    prompt = holder["messages"][0]["content"]
    assert "HP-SUMMARY-SENTINEL" in prompt


def test_generate_summary_without_context_is_byte_identical():
    stats = {"meals_logged": 3, "top_symptoms": []}
    expected = ai_extraction.SUMMARY_PROMPT.replace("{stats_json}", json.dumps(stats))

    fake_completion, holder = _capture_prompt()
    with patch.object(ai_extraction.litellm, "completion", side_effect=fake_completion):
        ai_extraction.generate_summary(stats)
    prompt = holder["messages"][0]["content"]
    assert prompt == expected


def test_generate_summary_empty_context_is_byte_identical():
    stats = {"meals_logged": 3, "top_symptoms": []}
    expected = ai_extraction.SUMMARY_PROMPT.replace("{stats_json}", json.dumps(stats))

    fake_completion, holder = _capture_prompt()
    with patch.object(ai_extraction.litellm, "completion", side_effect=fake_completion):
        ai_extraction.generate_summary(stats, health_context="")
    prompt = holder["messages"][0]["content"]
    assert prompt == expected
