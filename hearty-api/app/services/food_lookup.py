"""Tiered food-nutrition lookup orchestrator. Cache → Tier 1 (barcode) /
Tier 2 (branded+Nutritionix) → Tier 3 (web) → Tier 4 (AI estimate) → Tier 5
(honest fallback). Never blocks: Tier 5 always returns a usable result."""

import hashlib
import logging
import os
import re

from supabase import create_client

from app.services.food_cache import get_cached, set_cached
from app.services.food_sources import off_barcode, off_branded_search, nutritionix_lookup
from app.services.web_nutrition import web_nutrition_lookup
from app.services.food_estimate import ai_estimate, extract_lookup_fields, allergen_warnings

logger = logging.getLogger(__name__)

CACHE_TTL_BARCODE = int(os.environ.get("FOOD_CACHE_TTL_BARCODE", "30"))
CACHE_TTL_RESTAURANT = int(os.environ.get("FOOD_CACHE_TTL_RESTAURANT", "30"))
CACHE_TTL_WEB = int(os.environ.get("FOOD_CACHE_TTL_WEB", "7"))

supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


def _norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", (s or "").lower()).strip()


def _user_allergens(user_id: str) -> list[str]:
    rows = (supabase.table("health_profile").select("allergens")
            .eq("user_id", user_id).limit(1).execute()).data or []
    if not rows:
        return []
    out = []
    for a in (rows[0].get("allergens") or []):
        name = a.get("name") if isinstance(a, dict) else a
        if name:
            out.append(str(name))
    return out


def _result(nutrition, tier, source, user_id, message=None, confidence=None):
    warnings = allergen_warnings(nutrition or {}, _user_allergens(user_id)) if nutrition else []
    return {"item_name": (nutrition or {}).get("item_name") or (nutrition or {}).get("product_name") or "",
            "nutrition": nutrition, "tier_used": tier, "source": source,
            "confidence": confidence, "allergen_warnings": warnings, "message": message}


def lookup_food(type: str, value: str, restaurant: str | None, user_id: str) -> dict:
    if type == "barcode":
        # Tier 1 — barcode
        key = f"barcode:{value}"
        cached = get_cached(key)
        # get_cached returns only the cached nutrition_data dict, so source/tier
        # are read back from inside it (they were embedded at set_cached time).
        if cached:
            return _result(cached, cached.get("tier", 1), cached.get("source", "open_food_facts"), user_id)
        try:
            hit = off_barcode(value)
        except Exception as e:
            logger.warning("food lookup tier failed (%s): %s", "off_barcode", e)
            hit = None
        if hit:
            set_cached(key, hit["source"], hit, CACHE_TTL_BARCODE)
            return _result(hit, 1, hit["source"], user_id)
        return _tier5(value, user_id)

    item, rest = value, restaurant
    if type == "free_text":
        fields = extract_lookup_fields(value)
        item = fields.get("item") or value
        rest = fields.get("restaurant") or restaurant
        size = fields.get("size")
        item = f"{size} {item}".strip() if size else item

    combined = f"{rest} {item}".strip() if rest else item

    # Tier 2 — branded + Nutritionix
    rkey = f"restaurant:{_norm(rest or '')}|{_norm(item)}"
    cached = get_cached(rkey)
    if cached:
        return _result(cached, cached.get("tier", 2), cached.get("source", "open_food_facts_branded"), user_id)
    for fn, arg in ((off_branded_search, item), (nutritionix_lookup, combined)):
        try:
            hit = fn(arg)
        except Exception as e:
            logger.warning("food lookup tier failed (%s): %s", fn.__name__, e)
            hit = None
        if hit:
            set_cached(rkey, hit["source"], hit, CACHE_TTL_RESTAURANT)
            return _result(hit, 2, hit["source"], user_id)

    # Tier 3 — web search
    query = combined
    wkey = "web:" + hashlib.sha256(_norm(query).encode()).hexdigest()
    cached = get_cached(wkey)
    if cached:
        return _result(cached, 3, "web_search", user_id)
    try:
        hit = web_nutrition_lookup(query)
    except Exception as e:
        logger.warning("food lookup tier failed (%s): %s", "web_nutrition_lookup", e)
        hit = None
    if hit:
        set_cached(wkey, "web_search", hit, CACHE_TTL_WEB)
        return _result(hit, 3, "web_search", user_id)

    # Tier 4 — AI estimate (never cached)
    try:
        est = ai_estimate(query)
    except Exception as e:
        logger.warning("food lookup tier failed (%s): %s", "ai_estimate", e)
        est = None
    if est:
        return _result(est, 4, "ai_estimate", user_id,
                       message="This is an AI estimate, not measured data.",
                       confidence=est.get("confidence"))

    # Tier 5 — honest fallback
    return _tier5(query, user_id)


def _tier5(item: str, user_id: str) -> dict:
    return {"item_name": item, "nutrition": None, "tier_used": 5, "source": None,
            "confidence": None, "allergen_warnings": [],
            "message": f"I couldn't find nutritional data for {item}. I've logged "
                       "that you had it — you can add details later if you find them."}
