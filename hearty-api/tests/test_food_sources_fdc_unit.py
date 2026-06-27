from unittest.mock import patch
from app.services import food_sources as fs


class _Resp:
    def __init__(self, payload, status=200): self._p = payload; self.status_code = status
    def json(self): return self._p
    def raise_for_status(self): pass


_FDC_PAYLOAD = {"foods": [{
    "description": "Spinach, raw", "dataType": "Foundation",
    "foodNutrients": [
        {"nutrientNumber": "208", "value": 23},
        {"nutrientNumber": "203", "value": 2.86},
        {"nutrientNumber": "204", "value": 0.39},
        {"nutrientNumber": "606", "value": 0.063},
        {"nutrientNumber": "205", "value": 3.63},
        {"nutrientNumber": "291", "value": 2.2},
        {"nutrientNumber": "269", "value": 0.42},
        {"nutrientNumber": "307", "value": 79},
    ],
}]}


def test_fdc_lookup_maps_nutrients(monkeypatch):
    monkeypatch.setenv("FDC_API_KEY", "k")
    rec = {}
    with patch.object(fs.httpx, "Client") as C:
        get = C.return_value.__enter__.return_value.get
        get.return_value = _Resp(_FDC_PAYLOAD)
        out = fs.fdc_lookup("spinach")
        rec["params"] = get.call_args.kwargs.get("params", {})
    assert out["item_name"] == "Spinach, raw" and out["serving_size"] == "100 g"
    assert out["calories"] == 23 and out["protein_g"] == 2.86 and out["total_fat_g"] == 0.39
    assert out["saturated_fat_g"] == 0.063 and out["total_carbs_g"] == 3.63
    assert out["dietary_fiber_g"] == 2.2 and out["sugars_g"] == 0.42 and out["sodium_mg"] == 79
    assert out["source"] == "usda_fdc" and out["tier"] == 2
    assert rec["params"]["api_key"] == "k" and rec["params"]["query"] == "spinach"
    assert rec["params"]["dataType"] == ["Foundation", "SR Legacy"]


def test_fdc_lookup_no_key_returns_none(monkeypatch):
    monkeypatch.delenv("FDC_API_KEY", raising=False)
    assert fs.fdc_lookup("spinach") is None


def test_fdc_lookup_empty_returns_none(monkeypatch):
    monkeypatch.setenv("FDC_API_KEY", "k")
    with patch.object(fs.httpx, "Client") as C:
        C.return_value.__enter__.return_value.get.return_value = _Resp({"foods": []})
        assert fs.fdc_lookup("zzzz") is None
