from unittest.mock import patch
from app.services import food_sources as fs


class _Resp:
    def __init__(self, payload, status=200): self._p = payload; self.status_code = status
    def json(self): return self._p
    def raise_for_status(self): pass


_SEARCH = {"foods": [
    {"fdcId": 111, "description": "Apples, fuji, with skin, raw", "dataType": "Foundation"},
    {"fdcId": 222, "description": "Croissants, apple", "dataType": "SR Legacy"},
]}

_DETAIL = {"description": "Apples, fuji, with skin, raw", "foodNutrients": [
    {"nutrient": {"number": "957"}, "amount": 63.0},
    {"nutrient": {"number": "203"}, "amount": 0.15},
    {"nutrient": {"number": "204"}, "amount": 0.16},
    {"nutrient": {"number": "606"}, "amount": 0.027},
    {"nutrient": {"number": "205"}, "amount": 15.7},
    {"nutrient": {"number": "291"}, "amount": 2.1},
    {"nutrient": {"number": "269"}, "amount": 13.3},
    {"nutrient": {"number": "307"}, "amount": 1.0},
]}


def test_fdc_search_returns_candidates(monkeypatch):
    monkeypatch.setenv("FDC_API_KEY", "k")
    rec = {}
    with patch.object(fs.httpx, "Client") as C:
        get = C.return_value.__enter__.return_value.get
        get.return_value = _Resp(_SEARCH)
        out = fs.fdc_search("apple")
        rec["params"] = get.call_args.kwargs.get("params", {})
    assert out == [
        {"fdc_id": 111, "description": "Apples, fuji, with skin, raw", "data_type": "Foundation"},
        {"fdc_id": 222, "description": "Croissants, apple", "data_type": "SR Legacy"},
    ]
    assert rec["params"]["query"] == "apple" and rec["params"]["dataType"] == ["Foundation", "SR Legacy"]


def test_fdc_search_no_key_returns_empty(monkeypatch):
    monkeypatch.delenv("FDC_API_KEY", raising=False)
    assert fs.fdc_search("apple") == []


def test_fdc_detail_maps_with_energy_fallback(monkeypatch):
    monkeypatch.setenv("FDC_API_KEY", "k")
    with patch.object(fs.httpx, "Client") as C:
        C.return_value.__enter__.return_value.get.return_value = _Resp(_DETAIL)
        out = fs.fdc_detail(111)
    assert out["item_name"] == "Apples, fuji, with skin, raw" and out["serving_size"] == "100 g"
    assert out["calories"] == 63.0
    assert out["protein_g"] == 0.15 and out["total_carbs_g"] == 15.7 and out["sodium_mg"] == 1.0
    assert out["source"] == "usda_fdc" and out["tier"] == 2


def test_fdc_detail_no_key_returns_none(monkeypatch):
    monkeypatch.delenv("FDC_API_KEY", raising=False)
    assert fs.fdc_detail(111) is None
