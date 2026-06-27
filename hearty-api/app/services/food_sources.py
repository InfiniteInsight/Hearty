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


NUTRITIONIX_URL = "https://trackapi.nutritionix.com/v2/natural/nutrients"


def nutritionix_lookup(query: str) -> dict | None:
    app_id = os.environ.get("NUTRITIONIX_APP_ID")
    api_key = os.environ.get("NUTRITIONIX_API_KEY")
    if not app_id or not api_key:
        return None  # not configured → fall through
    headers = {"x-app-id": app_id, "x-app-key": api_key,
               "Content-Type": "application/json"}
    with httpx.Client(timeout=HTTP_TIMEOUT) as client:
        r = client.post(NUTRITIONIX_URL, headers=headers, json={"query": query})
        r.raise_for_status()
        foods = (r.json() or {}).get("foods") or []
    if not foods:
        return None
    f = foods[0]
    serving = f"{f.get('serving_qty', '')} {f.get('serving_unit', '')}".strip()
    return {
        "item_name": f.get("food_name") or query,
        "restaurant": f.get("brand_name") or "",
        "serving_size": serving,
        "calories": f.get("nf_calories"),
        "total_fat_g": f.get("nf_total_fat"),
        "total_carbs_g": f.get("nf_total_carbohydrate"),
        "protein_g": f.get("nf_protein"),
        "sodium_mg": f.get("nf_sodium"),
        "source": "nutritionix", "tier": 2,
    }


FDC_SEARCH_URL = "https://api.nal.usda.gov/fdc/v1/foods/search"
FDC_DETAIL_URL = "https://api.nal.usda.gov/fdc/v1/food/{fdc_id}"
FDC_DATATYPES = ["Foundation", "SR Legacy"]
FDC_CANDIDATES = 12
# Energy nutrient numbers in priority order (SR Legacy uses 208; Foundation uses
# the Atwater factors 957 / 2048 / 2047).
_FDC_ENERGY = ["208", "957", "2048", "2047"]
_FDC_MACROS = {
    "protein_g": "203", "total_fat_g": "204", "saturated_fat_g": "606",
    "total_carbs_g": "205", "dietary_fiber_g": "291", "sugars_g": "269", "sodium_mg": "307",
}


def fdc_search(query: str) -> list[dict]:
    """USDA FDC candidate search (generic datasets). [] when FDC_API_KEY unset / no results."""
    api_key = os.environ.get("FDC_API_KEY")
    if not api_key:
        return []
    params = {"api_key": api_key, "query": query,
              "dataType": FDC_DATATYPES, "pageSize": FDC_CANDIDATES}
    with httpx.Client(timeout=HTTP_TIMEOUT) as client:
        r = client.get(FDC_SEARCH_URL, params=params)
        r.raise_for_status()
        foods = (r.json() or {}).get("foods") or []
    return [{"fdc_id": f.get("fdcId"), "description": f.get("description") or "",
             "data_type": f.get("dataType")}
            for f in foods if f.get("fdcId")]


def fdc_detail(fdc_id) -> dict | None:
    """Full nutrition for one FDC food → normalized dict. None when no key / no food."""
    api_key = os.environ.get("FDC_API_KEY")
    if not api_key:
        return None
    with httpx.Client(timeout=HTTP_TIMEOUT) as client:
        r = client.get(FDC_DETAIL_URL.format(fdc_id=fdc_id), params={"api_key": api_key})
        r.raise_for_status()
        food = r.json() or {}
    if not food.get("description"):
        return None
    by_num: dict = {}
    for n in (food.get("foodNutrients") or []):
        num = (n.get("nutrient") or {}).get("number")
        if num is not None:
            by_num[str(num)] = n.get("amount")

    def g(num):
        v = by_num.get(num)
        try:
            return float(v) if v is not None else None
        except (TypeError, ValueError):
            return None

    energy = None
    for num in _FDC_ENERGY:
        if by_num.get(num) is not None:
            energy = g(num)
            break
    out = {"item_name": food.get("description"), "serving_size": "100 g",
           "calories": energy, "source": "usda_fdc", "tier": 2}
    for key, num in _FDC_MACROS.items():
        out[key] = g(num)
    return out
