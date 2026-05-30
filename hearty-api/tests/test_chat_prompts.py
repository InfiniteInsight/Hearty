import pytest


def test_make_system_prompt_warm_has_empathy_instruction():
    from app.routers.chat import _make_system_prompt
    prompt = _make_system_prompt(None, "warm")
    assert "respond with brief empathy" in prompt
    assert "Warm but concise" in prompt


def test_make_system_prompt_concise_has_no_empathy():
    from app.routers.chat import _make_system_prompt
    prompt = _make_system_prompt(None, "concise")
    assert "respond with brief empathy" not in prompt
    assert "Warm but concise" not in prompt
    assert "Do not comment" in prompt


def test_make_system_prompt_concise_closes_without_warmth():
    from app.routers.chat import _make_system_prompt
    prompt = _make_system_prompt(None, "concise")
    assert "brief warm statement" not in prompt
    assert "confirm with one short statement" in prompt


def test_make_system_prompt_defaults_to_warm():
    from app.routers.chat import _make_system_prompt
    warm = _make_system_prompt(None, "warm")
    default = _make_system_prompt(None, "unknown_value")
    assert warm == default


def test_make_system_prompt_includes_signal_context():
    from app.routers.chat import _make_system_prompt
    prompt = _make_system_prompt("Known food signals: dairy → bloating", "warm")
    assert "dairy" in prompt
