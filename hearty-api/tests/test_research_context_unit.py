import json
import types
from app.services.trends_conversation import build_system_prompt
from app.services import ai_extraction


def test_system_prompt_appends_research_after_health():
    p = build_system_prompt([], health_context="HEALTH-BLOCK",
                            research_context="RESEARCH-BLOCK")
    assert "RESEARCH-BLOCK" in p
    assert p.index("HEALTH-BLOCK") < p.index("RESEARCH-BLOCK")


def test_system_prompt_empty_research_is_byte_identical():
    # Empty research_context must leave the prompt byte-identical to the no-arg
    # call — this actually exercises the `if research_context:` guard (a sentinel
    # check would pass vacuously since the sentinel is never in the base prompt).
    assert build_system_prompt([], research_context="") == build_system_prompt([])


def test_generate_summary_includes_research_context(monkeypatch):
    captured = {}

    def fake_completion(model, messages, api_base=None):
        captured["content"] = messages[0]["content"]
        return types.SimpleNamespace(
            choices=[types.SimpleNamespace(message=types.SimpleNamespace(content="ok"))])

    monkeypatch.setattr(ai_extraction.litellm, "completion", fake_completion)
    ai_extraction.generate_summary({"a": 1}, health_context="HC",
                                   research_context="RESEARCH-BLOCK")
    assert "RESEARCH-BLOCK" in captured["content"]
    assert captured["content"].index("HC") < captured["content"].index("RESEARCH-BLOCK")


def test_generate_summary_empty_research_is_byte_identical(monkeypatch):
    # The router always passes research_context (default "") — lock down that the
    # empty path leaves the summary prompt byte-identical to the no-arg call.
    stats = {"meals_logged": 3, "top_symptoms": []}
    expected = ai_extraction.SUMMARY_PROMPT.replace("{stats_json}", json.dumps(stats))

    captured = {}

    def fake_completion(model, messages, api_base=None):
        captured["content"] = messages[0]["content"]
        return types.SimpleNamespace(
            choices=[types.SimpleNamespace(message=types.SimpleNamespace(content="ok"))])

    monkeypatch.setattr(ai_extraction.litellm, "completion", fake_completion)
    ai_extraction.generate_summary(stats, research_context="")
    assert captured["content"] == expected
