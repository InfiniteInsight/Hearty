import json
from types import SimpleNamespace
from unittest.mock import patch
from app.services import food_estimate as fe


def _fake(content):
    return SimpleNamespace(choices=[SimpleNamespace(
        message=SimpleNamespace(content=content))])


def test_extract_lookup_fields():
    payload = {"restaurant": "Gong Cha", "item": "wintergreen melon drink",
               "size": "large", "modifiers": None}
    with patch.object(fe.litellm, "completion", return_value=_fake(json.dumps(payload))):
        out = fe.extract_lookup_fields("I had a wintergreen melon large drink from Gong Cha")
    assert out["restaurant"] == "Gong Cha" and out["item"] == "wintergreen melon drink"
    assert out["size"] == "large"


def test_allergen_warnings_matches_user_allergens():
    nutrition = {"allergens": ["gluten"], "ingredients": ["water", "wheat flour"]}
    warnings = fe.allergen_warnings(nutrition, user_allergens=["wheat", "soy"])
    assert any("wheat" in w.lower() for w in warnings)
    assert not any("soy" in w.lower() for w in warnings)


def test_allergen_warnings_empty_when_no_match():
    nutrition = {"allergens": [], "ingredients": ["water", "oats"]}
    assert fe.allergen_warnings(nutrition, user_allergens=["peanut"]) == []
