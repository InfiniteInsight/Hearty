from unittest.mock import patch
from app.services import food_sources as fs


class _Resp:
    def __init__(self, payload, status=200): self._p = payload; self.status_code = status
    def json(self): return self._p
    def raise_for_status(self): pass


def test_off_barcode_parses_product():
    payload = {"status": 1, "product": {
        "product_name": "Oat Milk", "brands": "Oatly",
        "serving_size": "240 ml",
        "nutriments": {"energy-kcal_serving": 120, "fat_serving": 5,
                       "carbohydrates_serving": 16, "proteins_serving": 3,
                       "sodium_serving": 0.1},
        "ingredients_text": "water, oats", "allergens_tags": ["en:gluten"]}}
    with patch.object(fs.httpx, "Client") as C:
        C.return_value.__enter__.return_value.get.return_value = _Resp(payload)
        out = fs.off_barcode("123")
    assert out["product_name"] == "Oat Milk" and out["brand"] == "Oatly"
    assert out["calories"] == 120 and out["protein_g"] == 3
    assert out["source"] == "open_food_facts" and out["tier"] == 1
    assert "gluten" in [a.lower() for a in out["allergens"]]


def test_off_barcode_not_found_returns_none():
    with patch.object(fs.httpx, "Client") as C:
        C.return_value.__enter__.return_value.get.return_value = _Resp({"status": 0})
        assert fs.off_barcode("000") is None


def test_off_branded_search_first_hit():
    payload = {"products": [{"product_name": "Clif Bar", "brands": "Clif",
        "serving_size": "68 g",
        "nutriments": {"energy-kcal_serving": 250, "fat_serving": 6,
                       "carbohydrates_serving": 44, "proteins_serving": 9,
                       "sodium_serving": 0.2}}]}
    with patch.object(fs.httpx, "Client") as C:
        C.return_value.__enter__.return_value.get.return_value = _Resp(payload)
        out = fs.off_branded_search("clif bar")
    assert out["product_name"] == "Clif Bar"
    assert out["calories"] == 250 and out["tier"] == 2
    assert out["source"] == "open_food_facts_branded"


def test_off_branded_search_empty_returns_none():
    with patch.object(fs.httpx, "Client") as C:
        C.return_value.__enter__.return_value.get.return_value = _Resp({"products": []})
        assert fs.off_branded_search("zzzzz") is None
