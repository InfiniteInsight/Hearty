# USDA FoodData Central Tier (LLM-assisted match) — Design

**Status:** Approved (brainstorm 2026-06-26; redesigned 2026-06-27 after a live spike)
**Initiative:** Spec 11 (Knowledge Freshness), **Layer 2 (food-DB freshness), sub-feature 1.** (Gap-visibility + bulk sync are separate future sub-specs.)
**Builds on:** the existing tiered `food_lookup` pipeline (Spec 06/07).

## Goal

Add **USDA FoodData Central (FDC)** as an authoritative nutrition source for **generic/whole foods** in the tiered `food_lookup`. Best-effort: with no `FDC_API_KEY` the tier is silently skipped.

## Why LLM-assisted selection (live-spike finding)
A first design took FDC's top search result. A live spike disproved it: FDC keyword search ranks processed items over canonical foods — "apple"→*Croissants, apple*; "banana"→*banana powder* (346 kcal); "chicken breast"→*lunchmeat* (no macros). No heuristic was safe ("shortest description" picked *Beets* for spinach; head-noun matching picked *Rose-apples* for apple). Returning wrong nutrition is worse than the existing AI-estimate tier, so selection must be smarter. A second spike confirmed an **LLM picks the right entry reliably** (apple→*Apples, fuji, raw*; chicken breast→*Chicken, breast, boneless, skinless, raw*; oatmeal→correctly **none**). A third spike found FDC's **search** payload omits energy for some Foundation foods, so we fetch the full **detail** by `fdcId` and read energy with a `208 → 957 (Atwater)` fallback.

## Non-goals (deferred)
USDA **Branded** dataset (OFF covers branded); scheduled **bulk sync**; the **gap-visibility** surface; refreshing cached entries.

## Architecture

### 1. Pure-HTTP FDC sources — `app/services/food_sources.py`
Two key-gated functions (return `[]`/`None` when `FDC_API_KEY` unset — graceful, like `nutritionix_lookup`):

- `fdc_search(query) -> list[dict]` — `GET https://api.nal.usda.gov/fdc/v1/foods/search` (`dataType=["Foundation","SR Legacy"]`, `pageSize=12`). Returns lean candidates: `[{"fdc_id": f["fdcId"], "description": f["description"], "data_type": f.get("dataType")}]`. `[]` on no key / no results / error-free empty.
- `fdc_detail(fdc_id) -> dict | None` — `GET .../v1/food/{fdc_id}`. Maps `foodNutrients[].nutrient.number` (string) / `.amount` to the **normalized nutrition dict** used by the other sources:
  - `item_name` = `description`; `serving_size = "100 g"` (Foundation/SR Legacy are per-100 g)
  - energy → first present of `["208","957","2048","2047"]` (SR Legacy uses 208; Foundation uses the Atwater 957/204x)
  - `protein_g`←203 · `total_fat_g`←204 · `saturated_fat_g`←606 · `total_carbs_g`←205 · `dietary_fiber_g`←291 · `sugars_g`←269 · `sodium_mg`←307 (missing → `None`)
  - `source="usda_fdc"`, `tier=2`
  - `None` if no key or the detail has no usable food.

### 2. LLM-assisted resolver — `app/services/fdc_resolve.py` (new)
Isolated so the LLM-selection logic is testable and `food_sources` stays pure-HTTP.
- `resolve(query) -> dict | None`:
  1. `cands = fdc_search(query)`; if empty → `None`.
  2. `idx = _select(query, cands)` — one `litellm.completion` (model `LLM_MODEL`, small `max_tokens`). Prompt: *"A user logged eating '{query}'. Pick the entry that is the SAME food in plain/raw/generic form; avoid processed variants (powder, flour, bread, croissant, lunchmeat, juice unless asked) and different foods. Reply ONLY `{"index": <n>}` or `{"index": null}`."* + the numbered `description` list. Parse the JSON; `null`/out-of-range/parse-failure → `None`.
  3. If a valid index → `fdc_detail(cands[idx]["fdc_id"])` → return the normalized dict (or `None` if detail is empty).
- Best-effort: any exception (search, LLM, detail) is caught + logged → `None`. The resolver never raises.

### 3. Tier routing — `app/services/food_lookup.py` (unchanged shape)
`_usda_tier(item, user_id)` (cache `usda:{_norm(item)}` → `fdc_resolve(item)` → cache on hit → `_result(..., 2, "usda_fdc")`, else `None`). Routing as before:
- **No restaurant/brand** → `_usda_tier` **before** the branded Tier 2 (authoritative generic wins).
- **Restaurant/brand named** → branded first, then `_usda_tier` as a **fallback** before web.
`food_lookup` imports `fdc_resolve` (so tests patch `fl.fdc_resolve`). Cached under `usda:` 90 days (`CACHE_TTL_USDA`); the LLM + 2 GETs run only on a cache miss.

## Data flow ("apple", no restaurant)
`lookup_food` → `not rest` → `_usda_tier("apple")` → cache miss → `fdc_resolve("apple")`: `fdc_search` → 12 candidates → LLM picks *Apples, fuji, raw* → `fdc_detail(fdcId)` → normalized macros → cached 90d → `_result(..., tier=2, source="usda_fdc")`. LLM "none" / no key / error → `None` → falls through to branded→web→AI (unchanged).

## Error handling
Fully best-effort end-to-end: `fdc_search`/`fdc_detail`/`_select` swallow errors (→ `[]`/`None`), `resolve` returns `None` on any failure, `_usda_tier` wraps `resolve` in try/except. An FDC outage, a bad LLM response, or a missing key never blocks logging — it just falls through.

## Security / cost
`FDC_API_KEY` backend-only; FDC data is public; `food_cache` service-key only. Cost: one cheap LLM call + two light FDC GETs **per uncached generic lookup**, then cached 90 days — the pipeline already makes an LLM call at Tier 4 (AI estimate), so this fits the pattern.

## Testing
**`food_sources` (pytest, mocked httpx):** `fdc_search` parses candidates (fdc_id/description/data_type) + sends the right params; `[]` on no key / empty. `fdc_detail` maps the detail shape (`nutrient.number`/`amount`), energy `208→957` fallback (a payload with only 957 yields calories), other macros, `serving_size`/`source`/`tier`; `None` on no key.
**`fdc_resolve` (pytest):** monkeypatch `fdc_search`/`fdc_detail`/`litellm.completion`: a valid LLM index → detail fetched + returned; LLM `null` → `None` (detail NOT fetched); no candidates → `None` (LLM not called); an LLM/detail exception → `None` (best-effort).
**`food_lookup`:** routing tests patch `fdc_resolve` (generic-first, branded-fallback, cache-hit-no-resolve); the existing no-restaurant tests get `fdc_resolve=lambda q: None` (deterministic).
**Live (deploy-time):** `FDC_API_KEY` set; log "apple"/"chicken breast"/"banana" and confirm `source=usda_fdc` with the correct raw-food macros; "oatmeal"/an obscure phrase falls through (resolver returns None); branded/barcode still uses OFF; logging still works with the key unset.

## Deferred
Gap-visibility surface; USDA Branded dataset; bulk sync; tuning the candidate count / selection prompt; a cheaper dedicated selection model.
