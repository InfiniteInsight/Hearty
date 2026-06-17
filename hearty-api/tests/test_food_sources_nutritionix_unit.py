from unittest.mock import patch
from app.services import food_sources as fs


class _Resp:
    def __init__(self, payload, status=200): self._p = payload; self.status_code = status
    def json(self): return self._p
    def raise_for_status(self): pass


def test_nutritionix_parses_first_food(monkeypatch):
    monkeypatch.setenv("NUTRITIONIX_APP_ID", "id")
    monkeypatch.setenv("NUTRITIONIX_API_KEY", "key")
    payload = {"foods": [{"food_name": "big mac", "brand_name": "McDonald's",
        "serving_qty": 1, "serving_unit": "burger", "nf_calories": 563,
        "nf_total_fat": 33, "nf_total_carbohydrate": 45, "nf_protein": 26,
        "nf_sodium": 1010}]}
    rec = {}
    with patch.object(fs.httpx, "Client") as C:
        post = C.return_value.__enter__.return_value.post
        post.return_value = _Resp(payload)
        out = fs.nutritionix_lookup("big mac")
        rec["headers"] = post.call_args.kwargs.get("headers", {})
    assert out["item_name"] == "big mac" and out["calories"] == 563
    assert out["source"] == "nutritionix" and out["tier"] == 2
    assert rec["headers"]["x-app-id"] == "id" and rec["headers"]["x-app-key"] == "key"


def test_nutritionix_no_keys_returns_none(monkeypatch):
    monkeypatch.delenv("NUTRITIONIX_APP_ID", raising=False)
    monkeypatch.delenv("NUTRITIONIX_API_KEY", raising=False)
    assert fs.nutritionix_lookup("big mac") is None


def test_nutritionix_empty_returns_none(monkeypatch):
    monkeypatch.setenv("NUTRITIONIX_APP_ID", "id")
    monkeypatch.setenv("NUTRITIONIX_API_KEY", "key")
    with patch.object(fs.httpx, "Client") as C:
        C.return_value.__enter__.return_value.post.return_value = _Resp({"foods": []})
        assert fs.nutritionix_lookup("zzzzz") is None
