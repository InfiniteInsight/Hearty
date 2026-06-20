import json
from types import SimpleNamespace
from unittest.mock import patch
from app.services import food_estimate as fe


def _fake(content):
    return SimpleNamespace(choices=[SimpleNamespace(
        message=SimpleNamespace(content=content))])


def test_ai_estimate_parses():
    payload = {"calories": 200, "protein_g": 5, "total_carbs_g": 30,
               "total_fat_g": 7, "confidence": 0.6}
    with patch.object(fe.litellm, "completion", return_value=_fake(json.dumps(payload))):
        out = fe.ai_estimate("a slice of banana bread")
    assert out["calories"] == 200 and out["confidence"] == 0.6
    assert out["source"] == "ai_estimate" and out["tier"] == 4
    assert out["item_name"] == "a slice of banana bread"


def test_ai_estimate_unparseable_returns_null_estimate():
    with patch.object(fe.litellm, "completion", return_value=_fake("dunno")):
        out = fe.ai_estimate("mystery goo")
    assert out["tier"] == 4 and out["confidence"] == 0.0
    assert out["calories"] is None
