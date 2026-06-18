import json
from types import SimpleNamespace
from unittest.mock import patch
from app.services import food_plate as fp


def _fake(content):
    return SimpleNamespace(choices=[SimpleNamespace(
        message=SimpleNamespace(content=content))])


def test_parses_food_array():
    arr = [{"name": "grilled salmon", "portion": "1 fillet", "confidence": 0.85},
           {"name": "broccoli", "portion": "small side", "confidence": 0.9}]
    with patch.object(fp.litellm, "completion", return_value=_fake(json.dumps(arr))):
        out = fp.analyze_food_plate(b"\xff\xd8\xff", "image/jpeg")
    assert out["source"] == "food_plate_vision"
    assert out["foods"][0]["name"] == "grilled salmon"
    assert out["foods"][1]["confidence"] == 0.9


def test_strips_code_fence_and_handles_empty():
    with patch.object(fp.litellm, "completion", return_value=_fake("```json\n[]\n```")):
        out = fp.analyze_food_plate(b"\xff\xd8\xff", "image/jpeg")
    assert out["foods"] == []


def test_sends_multimodal_image_content():
    captured = {}
    def _spy(**kwargs):
        captured.update(kwargs)
        return _fake("[]")
    with patch.object(fp.litellm, "completion", side_effect=_spy):
        fp.analyze_food_plate(b"\xff\xd8\xff", "image/png")
    content = captured["messages"][0]["content"]
    kinds = [p["type"] for p in content]
    assert "text" in kinds and "image_url" in kinds
    img = next(p for p in content if p["type"] == "image_url")
    assert img["image_url"]["url"].startswith("data:image/png;base64,")


def test_non_json_response_raises_valueerror():
    import pytest
    with patch.object(fp.litellm, "completion", return_value=_fake("sorry, no")):
        with pytest.raises(ValueError):
            fp.analyze_food_plate(b"\xff\xd8\xff", "image/jpeg")
