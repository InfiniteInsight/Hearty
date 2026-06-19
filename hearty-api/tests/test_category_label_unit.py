from app.services.food_category_service import category_label


def test_known_slug_returns_display():
    assert category_label("dairy_casein") == "Dairy / Casein"
    assert category_label("fodmap_lactose") == "FODMAP Lactose"
    assert category_label("histamine") == "High Histamine"


def test_unknown_slug_prettified_fallback():
    assert category_label("made_up_thing") == "Made Up Thing"


def test_empty_or_none_is_safe():
    assert category_label("") == ""
    assert category_label(None) == ""
