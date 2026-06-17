from app.services import food_lookup as fl


def _patch(monkeypatch, **fns):
    for name, fn in fns.items():
        monkeypatch.setattr(fl, name, fn)


def test_barcode_cache_hit_skips_tiers(monkeypatch):
    _patch(monkeypatch,
           get_cached=lambda k: {"product_name": "Cached", "calories": 100, "tier": 1, "source": "open_food_facts"},
           _user_allergens=lambda uid: [])
    called = {"off": False}
    _patch(monkeypatch, off_barcode=lambda b: called.__setitem__("off", True) or None)
    out = fl.lookup_food("barcode", "123", None, "u1")
    assert out["tier_used"] == 1 and out["nutrition"]["product_name"] == "Cached"
    assert called["off"] is False


def test_barcode_tier1_then_caches(monkeypatch):
    rec = {}
    _patch(monkeypatch,
           get_cached=lambda k: None,
           off_barcode=lambda b: {"product_name": "Oat", "calories": 120, "tier": 1, "source": "open_food_facts", "allergens": [], "ingredients": []},
           set_cached=lambda k, s, d, t: rec.update({"key": k, "ttl": t}),
           _user_allergens=lambda uid: [])
    out = fl.lookup_food("barcode", "123", None, "u1")
    assert out["tier_used"] == 1 and rec["key"] == "barcode:123" and rec["ttl"] == 30


def test_name_falls_through_to_estimate(monkeypatch):
    _patch(monkeypatch,
           get_cached=lambda k: None,
           off_branded_search=lambda q: None,
           nutritionix_lookup=lambda q: None,
           web_nutrition_lookup=lambda d, **k: None,
           ai_estimate=lambda d: {"item_name": d, "calories": 210, "confidence": 0.5, "source": "ai_estimate", "tier": 4},
           _user_allergens=lambda uid: [])
    out = fl.lookup_food("name", "banana bread", None, "u1")
    assert out["tier_used"] == 4 and out["source"] == "ai_estimate"
    assert out["message"] and "estimate" in out["message"].lower()


def test_free_text_extracts_then_tier2(monkeypatch):
    _patch(monkeypatch,
           get_cached=lambda k: None,
           extract_lookup_fields=lambda t: {"restaurant": "Gong Cha", "item": "melon drink", "size": "large", "modifiers": None},
           off_branded_search=lambda q: None,
           nutritionix_lookup=lambda q: {"item_name": "melon drink", "restaurant": "Gong Cha", "calories": 300, "source": "nutritionix", "tier": 2},
           set_cached=lambda *a: None,
           _user_allergens=lambda uid: [])
    out = fl.lookup_food("free_text", "melon drink from Gong Cha", None, "u1")
    assert out["tier_used"] == 2 and out["source"] == "nutritionix"


def test_all_fail_tier5_fallback(monkeypatch):
    _patch(monkeypatch,
           get_cached=lambda k: None,
           off_branded_search=lambda q: None,
           nutritionix_lookup=lambda q: None,
           web_nutrition_lookup=lambda d, **k: None,
           _user_allergens=lambda uid: [])
    _patch(monkeypatch, ai_estimate=lambda d: (_ for _ in ()).throw(RuntimeError("down")))
    out = fl.lookup_food("name", "mystery", None, "u1")
    assert out["tier_used"] == 5 and out["nutrition"] is None
    assert "couldn't find" in out["message"].lower()


def test_tier2_source_exception_falls_through(monkeypatch):
    _patch(monkeypatch,
           get_cached=lambda k: None,
           off_branded_search=lambda q: (_ for _ in ()).throw(RuntimeError("off down")),
           nutritionix_lookup=lambda q: {"item_name": "x", "calories": 50, "source": "nutritionix", "tier": 2},
           set_cached=lambda *a: None,
           _user_allergens=lambda uid: [])
    out = fl.lookup_food("name", "x", None, "u1")
    assert out["tier_used"] == 2 and out["source"] == "nutritionix"


def test_allergen_warnings_attached(monkeypatch):
    _patch(monkeypatch,
           get_cached=lambda k: None,
           off_barcode=lambda b: {"product_name": "Bread", "calories": 100, "tier": 1, "source": "open_food_facts", "allergens": ["gluten"], "ingredients": ["wheat flour"]},
           set_cached=lambda *a: None,
           _user_allergens=lambda uid: ["wheat"])
    out = fl.lookup_food("barcode", "1", None, "u1")
    assert any("wheat" in w.lower() for w in out["allergen_warnings"])
