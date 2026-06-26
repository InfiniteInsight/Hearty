import types
from app.services.trends_conversation import build_system_prompt
from app.services import ai_extraction


def test_system_prompt_overlay_before_health_and_research():
    p = build_system_prompt([], health_context="HEALTH", research_context="RESEARCH",
                            style_overlay="OVERLAY")
    assert "OVERLAY" in p
    assert p.index("OVERLAY") < p.index("HEALTH") < p.index("RESEARCH")


def test_system_prompt_empty_overlay_byte_identical():
    assert build_system_prompt([], style_overlay="") == build_system_prompt([])


def test_generate_summary_overlay_before_health(monkeypatch):
    captured = {}

    def fake_completion(model, messages, api_base=None):
        captured["content"] = messages[0]["content"]
        return types.SimpleNamespace(
            choices=[types.SimpleNamespace(message=types.SimpleNamespace(content="ok"))])

    monkeypatch.setattr(ai_extraction.litellm, "completion", fake_completion)
    ai_extraction.generate_summary({"a": 1}, health_context="HEALTH",
                                   style_overlay="OVERLAY")
    assert captured["content"].index("OVERLAY") < captured["content"].index("HEALTH")


def test_generate_summary_empty_overlay_byte_identical(monkeypatch):
    import json
    stats = {"meals_logged": 1}
    expected = ai_extraction.SUMMARY_PROMPT.replace("{stats_json}", json.dumps(stats))
    captured = {}

    def fake_completion(model, messages, api_base=None):
        captured["content"] = messages[0]["content"]
        return types.SimpleNamespace(
            choices=[types.SimpleNamespace(message=types.SimpleNamespace(content="ok"))])

    monkeypatch.setattr(ai_extraction.litellm, "completion", fake_completion)
    ai_extraction.generate_summary(stats, style_overlay="")
    assert captured["content"] == expected
