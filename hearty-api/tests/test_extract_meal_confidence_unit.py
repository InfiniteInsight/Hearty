import json
from unittest.mock import patch
from types import SimpleNamespace
from app.services import ai_extraction


def test_extract_meal_includes_confidence_per_food():
    fake = SimpleNamespace(choices=[SimpleNamespace(message=SimpleNamespace(
        content=json.dumps({
            "normalized_description": "buldak ramen",
            "foods": [{"name": "buldak ramen", "quantity": None,
                       "estimated_calories": None, "preparation": None,
                       "confidence": 0.45}],
            "inferred_meal_type": "snack",
        })))])
    with patch.object(ai_extraction.litellm, "completion", return_value=fake):
        out = ai_extraction.extract_meal("buldak swicy ramen")
    assert out["foods"][0]["confidence"] == 0.45
