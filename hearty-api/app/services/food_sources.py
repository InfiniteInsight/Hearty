"""External nutrition sources. Each function returns a normalized nutrition dict
or None on miss. Sync httpx; the HTTP client is created per call so tests can
patch httpx.Client."""

import os
import httpx

HTTP_TIMEOUT = float(os.environ.get("FOOD_HTTP_TIMEOUT", "10.0"))
OFF_PRODUCT_URL = "https://world.openfoodfacts.org/api/v2/product/{barcode}.json"
OFF_SEARCH_URL = "https://world.openfoodfacts.org/cgi/search.pl"


def _num(nutriments: dict, *keys):
    for k in keys:
        v = nutriments.get(k)
        if v is not None:
            try:
                return float(v)
            except (TypeError, ValueError):
                continue
    return None


def _from_off_product(p: dict, tier: int, source: str) -> dict:
    n = p.get("nutriments") or {}
    allergens = [t.split(":", 1)[-1] for t in (p.get("allergens_tags") or [])]
    ingredients = p.get("ingredients_text") or ""
    return {
        "product_name": p.get("product_name") or "",
        "brand": p.get("brands") or "",
        "serving_size": p.get("serving_size") or "",
        "calories": _num(n, "energy-kcal_serving", "energy-kcal_100g"),
        "total_fat_g": _num(n, "fat_serving", "fat_100g"),
        "saturated_fat_g": _num(n, "saturated-fat_serving", "saturated-fat_100g"),
        "total_carbs_g": _num(n, "carbohydrates_serving", "carbohydrates_100g"),
        "dietary_fiber_g": _num(n, "fiber_serving", "fiber_100g"),
        "sugars_g": _num(n, "sugars_serving", "sugars_100g"),
        "protein_g": _num(n, "proteins_serving", "proteins_100g"),
        "sodium_mg": (lambda s: s * 1000 if s is not None else None)(
            _num(n, "sodium_serving", "sodium_100g")),
        "ingredients": [i.strip() for i in ingredients.split(",") if i.strip()],
        "allergens": allergens,
        "source": source, "tier": tier,
    }


def off_barcode(barcode: str) -> dict | None:
    with httpx.Client(timeout=HTTP_TIMEOUT) as client:
        r = client.get(OFF_PRODUCT_URL.format(barcode=barcode))
        r.raise_for_status()
        data = r.json()
    if data.get("status") != 1 or not data.get("product"):
        return None
    return _from_off_product(data["product"], tier=1, source="open_food_facts")


def off_branded_search(query: str) -> dict | None:
    params = {"search_terms": query, "search_simple": 1, "json": 1, "page_size": 5}
    with httpx.Client(timeout=HTTP_TIMEOUT) as client:
        r = client.get(OFF_SEARCH_URL, params=params)
        r.raise_for_status()
        products = (r.json() or {}).get("products") or []
    if not products:
        return None
    return _from_off_product(products[0], tier=2, source="open_food_facts_branded")
