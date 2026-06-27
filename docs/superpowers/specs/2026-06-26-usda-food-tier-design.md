# USDA FoodData Central Tier — Design

**Status:** Approved (brainstorm 2026-06-26)
**Initiative:** Spec 11 (Knowledge Freshness), **Layer 2 (food-DB freshness), sub-feature 1 of ~3.** (Sub-feature 2 = gap-visibility surface; sub-feature 3 = scheduled bulk sync — both separate future specs, the latter likely YAGNI.)
**Builds on:** the existing tiered `food_lookup` pipeline (Spec 06/07).

## Goal

Add **USDA FoodData Central (FDC)** as an authoritative nutrition source for **generic/whole foods** (e.g. "banana", "chicken breast"), which today fall through the branded tiers to web-search or AI estimates. This raises nutrition-data quality for the most common un-branded log entries, slotting cleanly into the existing on-demand, cached, tiered `food_lookup`. It ships safely before a key exists: with no `FDC_API_KEY`, the tier is silently skipped (exactly like the Nutritionix tier today).

## Non-goals (deferred)
- USDA **Branded Foods** dataset — heavy overlap with Open Food Facts/Nutritionix (already better for branded); generic-only here (Foundation + SR Legacy).
- **Scheduled bulk sync** of USDA data (the original Spec 11 heavy pipeline) — separate future spec, likely YAGNI.
- The **gap-visibility surface** (which logged foods got weak data) — separate Layer-2 sub-feature.
- Refreshing/re-fetching already-cached entries (TTL handles staleness).

## Architecture

### 1. New source — `fdc_lookup(query)` in `app/services/food_sources.py`
Mirrors the existing source functions (per-call `httpx.Client(timeout=HTTP_TIMEOUT)`, returns the normalized nutrition dict or `None` on miss):
- Requires `FDC_API_KEY` (env). If unset → return `None` (graceful, like `nutritionix_lookup`).
- `GET https://api.nal.usda.gov/fdc/v1/foods/search` with params `api_key`, `query`, `dataType=["Foundation", "SR Legacy"]`, `pageSize=1`. `raise_for_status()`.
- Top result (`foods[0]`); build a number→value map from `foodNutrients` keyed by `nutrientNumber`, then map to the normalized shape used by the other sources:
  - `item_name` = `description`; `serving_size` = `"100 g"` (Foundation/SR Legacy values are per-100 g)
  - `calories` ← 208 · `protein_g` ← 203 · `total_fat_g` ← 204 · `saturated_fat_g` ← 606 · `total_carbs_g` ← 205 · `dietary_fiber_g` ← 291 · `sugars_g` ← 269 · `sodium_mg` ← 307
  - missing nutrient → `None` (the `_num`-style helper pattern)
  - `source` = `"usda_fdc"`, `tier` = `2`
- Return `None` if `foods` is empty.

> Implementation note: FDC's GET search accepts `dataType` as repeated query params (httpx serializes a list that way) or comma-joined; the implementer confirms the exact serialization against the live API during the deploy-time check. Nutrient *numbers* (string keys like `"208"`) are stable across FDC; map by number, not name.

### 2. Tier routing in `app/services/food_lookup.py`
Extract a helper that encapsulates the USDA tier (cache → fetch → cache), returning a finished `_result` dict or `None`:
```python
def _usda_tier(item, user_id):
    ukey = "usda:" + _norm(item)
    cached = get_cached(ukey)
    if cached:
        return _result(cached, cached.get("tier", 2), cached.get("source", "usda_fdc"), user_id)
    try:
        hit = fdc_lookup(item)
    except Exception as e:
        logger.warning("food lookup tier failed (fdc_lookup): %s", e)
        hit = None
    if hit:
        set_cached(ukey, "usda_fdc", hit, CACHE_TTL_USDA)
        return _result(hit, 2, "usda_fdc", user_id)
    return None
```
Wire it into `lookup_food` (the name/free-text path, after the barcode branch and the `item`/`rest` extraction):
- **No restaurant/brand** (`not rest`): call `_usda_tier(item, ...)` **before** the branded tier — authoritative generic data wins for whole foods.
- **Restaurant/brand named** (`rest`): keep the branded tier first, then call `_usda_tier(item, ...)` as a fallback **before** the web tier.

Cache key is the generic `item` (without restaurant) since USDA is generic. USDA reports as **tier 2** (peer to branded — authoritative DB match); web=3 / AI-estimate=4 / honest-fallback=5 are unchanged. Update the module docstring's tier line to mention USDA.

### 3. Caching
Reuse the shared `food_cache` (service-key only). New TTL `CACHE_TTL_USDA = int(os.environ.get("FOOD_CACHE_TTL_USDA", "90"))` — USDA generic data is very stable, so a 90-day TTL is appropriate (longer than barcode/restaurant 30, web 7).

### 4. Config
- New env var `FDC_API_KEY` (free key from https://fdc.nal.usda.gov/api-key-signup.html, an api.data.gov key). Add to `.env`, `hearty-api/.env.example`, and the `docs/DEPLOYMENT.md` redeploy env-file key list.
- Best-effort: unset ⇒ `fdc_lookup` returns `None` ⇒ tier skipped, so the feature can deploy before the key is provisioned.

## Data flow (logging "grilled chicken breast", no restaurant)
1. `lookup_food(type="free_text", value="grilled chicken breast", restaurant=None, user_id)`.
2. `extract_lookup_fields` → `item="chicken breast"` (or similar), `rest=None`.
3. `not rest` → `_usda_tier("chicken breast", ...)`: cache miss → `fdc_lookup` → USDA returns the authoritative generic entry → cached (90d) → `_result(..., tier=2, source="usda_fdc")`.
4. If USDA misses/no key → falls through to branded → web → AI → fallback (unchanged behavior).

## Error handling
- USDA tier fully best-effort: `fdc_lookup` exceptions are caught + logged, the tier returns `None`, and lookup continues to the next tier. An FDC outage or a missing key never blocks logging.
- `raise_for_status` failures (4xx/5xx) are caught by the tier's `try/except`.

## Security
- `FDC_API_KEY` is a backend-only env var (never client-exposed). The FDC API returns public nutrition data. `food_cache` stays service-key-only (RLS on, no policies). No user data involved.

## Testing
**Backend (pytest):**
- `food_sources.fdc_lookup`: patch `httpx.Client` to return a recorded FDC search payload → asserts the normalized dict (calories/protein/fat/carbs/fiber/sugars/sodium mapped from nutrient numbers, `serving_size="100 g"`, `source="usda_fdc"`, `tier=2`); returns `None` when `FDC_API_KEY` unset; returns `None` on empty `foods`.
- `food_lookup`: a generic (no-restaurant) lookup calls USDA **before** branded (monkeypatch the source functions; assert the result is tier 2 / `usda_fdc` when USDA hits, and that branded was not consulted); a restaurant lookup tries branded first, then USDA; the USDA cache-hit path returns without an HTTP call. Existing food_lookup tests stay green (USDA returns `None` when its source is unpatched/no key → current behavior preserved).

**Live (deploy-time):** set `FDC_API_KEY`; redeploy; log a generic whole food (e.g. "raw spinach") and confirm the result's `source` is `usda_fdc` with sensible per-100g macros; confirm a branded/barcoded item still uses OFF; confirm logging still works with the key unset (tier skipped).

## Deferred (future Layer-2 sub-features)
Gap-visibility surface (flag Tier 3/4/unknown logged foods); USDA Branded dataset; scheduled bulk sync; a "refresh stale entry" action.
