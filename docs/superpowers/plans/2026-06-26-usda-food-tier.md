# USDA FoodData Central Tier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add USDA FoodData Central as an authoritative nutrition tier for generic/whole foods in the existing tiered `food_lookup` pipeline (USDA-first for no-restaurant lookups, branded-first with USDA fallback when a brand is named).

**Architecture:** A new best-effort `fdc_lookup` source in `food_sources.py` (returns the same normalized nutrition dict as the OFF/Nutritionix sources, or `None`), wired into `food_lookup.py` via a `_usda_tier` helper with smart routing, cached in the shared `food_cache` with a long TTL. Gated on `FDC_API_KEY` — unset ⇒ tier silently skipped.

**Tech Stack:** FastAPI (Python), httpx, Supabase (food_cache).

**Spec:** `docs/superpowers/specs/2026-06-26-usda-food-tier-design.md`

**Worktree:** `~/.config/superpowers/worktrees/usda-tier` (branch `usda-tier`, off master). Tests (no local venv): from `hearty-api/`, `set -a; source /home/evan/projects/food-journal-assistant/.env; set +a` then `/home/evan/projects/food-journal-assistant/hearty-api/.venv/bin/python -m pytest <paths> -q`.

**Key existing code (verified on master):**
- `food_sources.py`: each source fn uses a per-call `httpx.Client(timeout=HTTP_TIMEOUT)`, returns a normalized dict (keys: `item_name`/`product_name`, `serving_size`, `calories`, `total_fat_g`, `saturated_fat_g`, `total_carbs_g`, `dietary_fiber_g`, `sugars_g`, `protein_g`, `sodium_mg`, `source`, `tier`) or `None`. `nutritionix_lookup` returns `None` when its keys are unset.
- `food_lookup.py`: `lookup_food(type, value, restaurant, user_id)`. After the barcode branch it extracts `item`/`rest` (rest = restaurant), `combined = f"{rest} {item}"`, then Tier 2 (branded+Nutritionix, cache key `restaurant:{norm(rest)}|{norm(item)}`) → Tier 3 (web, `web:{sha}`) → Tier 4 (AI estimate) → Tier 5 (fallback). Helpers: `_norm`, `_result(nutrition, tier, source, user_id, ...)`, `get_cached`/`set_cached` (imported names), `CACHE_TTL_*`.
- Tests `tests/test_food_lookup_unit.py` use `_patch(monkeypatch, **fns)` = `monkeypatch.setattr(fl, name, fn)` — so any source fn must be importable as `fl.<name>`. `tests/test_food_sources_*_unit.py` mock httpx via `patch.object(fs.httpx, "Client")` + a `_Resp` stub.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `hearty-api/app/services/food_sources.py` | `fdc_lookup` source fn (modify) | 1 |
| `hearty-api/tests/test_food_sources_fdc_unit.py` | fdc_lookup tests (create) | 1 |
| `hearty-api/app/services/food_lookup.py` | `_usda_tier` helper + routing + TTL + import (modify) | 2 |
| `hearty-api/tests/test_food_lookup_unit.py` | new routing tests + anti-flake stubs (modify) | 2 |
| `hearty-api/.env.example`, `docs/DEPLOYMENT.md` | `FDC_API_KEY` config (modify) | 3 |
| live deploy | set key, redeploy, verify | 4 |

---

### Task 1: `fdc_lookup` source in `food_sources.py`

**Files:**
- Modify: `hearty-api/app/services/food_sources.py`
- Test: `hearty-api/tests/test_food_sources_fdc_unit.py`

- [ ] **Step 1: Write the failing test** — create `hearty-api/tests/test_food_sources_fdc_unit.py`:

```python
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
```

- [ ] **Step 2: Run to verify it fails**

Run: `tests/test_food_sources_fdc_unit.py -v` → FAIL (`module 'app.services.food_sources' has no attribute 'fdc_lookup'`).

- [ ] **Step 3: Add `fdc_lookup`** to the end of `hearty-api/app/services/food_sources.py`:

```python
FDC_SEARCH_URL = "https://api.nal.usda.gov/fdc/v1/foods/search"
FDC_DATATYPES = ["Foundation", "SR Legacy"]
# FoodData Central nutrient numbers (stable across FDC).
_FDC_NUTRIENTS = {
    "calories": "208", "total_fat_g": "204", "saturated_fat_g": "606",
    "total_carbs_g": "205", "dietary_fiber_g": "291", "sugars_g": "269",
    "protein_g": "203", "sodium_mg": "307",
}


def fdc_lookup(query: str) -> dict | None:
    """USDA FoodData Central — authoritative generic/whole-food nutrition.
    Returns None when FDC_API_KEY is unset (graceful skip) or no result."""
    api_key = os.environ.get("FDC_API_KEY")
    if not api_key:
        return None
    params = {"api_key": api_key, "query": query,
              "dataType": FDC_DATATYPES, "pageSize": 1}
    with httpx.Client(timeout=HTTP_TIMEOUT) as client:
        r = client.get(FDC_SEARCH_URL, params=params)
        r.raise_for_status()
        foods = (r.json() or {}).get("foods") or []
    if not foods:
        return None
    f = foods[0]
    by_num: dict = {}
    for n in (f.get("foodNutrients") or []):
        num = n.get("nutrientNumber")
        if num is not None:
            by_num[str(num)] = n.get("value")

    def g(num):
        v = by_num.get(num)
        try:
            return float(v) if v is not None else None
        except (TypeError, ValueError):
            return None

    out = {"item_name": f.get("description") or query, "serving_size": "100 g",
           "source": "usda_fdc", "tier": 2}
    for key, num in _FDC_NUTRIENTS.items():
        out[key] = g(num)
    return out
```

- [ ] **Step 4: Run to verify pass**

Run: `tests/test_food_sources_fdc_unit.py -v` → 3 passed.

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/food_sources.py hearty-api/tests/test_food_sources_fdc_unit.py
git commit -m "feat(food): fdc_lookup source — USDA FoodData Central generic nutrition"
```

---

### Task 2: Wire the USDA tier into `food_lookup.py`

**Files:**
- Modify: `hearty-api/app/services/food_lookup.py` (import; `CACHE_TTL_USDA`; `_usda_tier`; routing)
- Modify: `hearty-api/tests/test_food_lookup_unit.py` (new routing tests + anti-flake stubs on existing tests)

- [ ] **Step 1: Write the failing tests** — append to `hearty-api/tests/test_food_lookup_unit.py`:

```python
def test_generic_lookup_usda_first(monkeypatch):
    called = {"branded": False}
    _patch(monkeypatch,
           get_cached=lambda k: None,
           fdc_lookup=lambda q: {"item_name": "banana", "calories": 89, "source": "usda_fdc", "tier": 2},
           off_branded_search=lambda q: called.__setitem__("branded", True) or {"item_name": "banana chips", "source": "open_food_facts_branded", "tier": 2},
           nutritionix_lookup=lambda q: None,
           set_cached=lambda *a: None,
           _user_allergens=lambda uid: [])
    out = fl.lookup_food("name", "banana", None, "u1")
    assert out["tier_used"] == 2 and out["source"] == "usda_fdc"
    assert called["branded"] is False  # USDA short-circuits before branded for generic


def test_restaurant_branded_then_usda_fallback(monkeypatch):
    _patch(monkeypatch,
           get_cached=lambda k: None,
           extract_lookup_fields=lambda t: {"restaurant": "Chipotle", "item": "chicken bowl", "size": None, "modifiers": None},
           off_branded_search=lambda q: None,
           nutritionix_lookup=lambda q: None,
           fdc_lookup=lambda q: {"item_name": "chicken", "calories": 165, "source": "usda_fdc", "tier": 2},
           web_nutrition_lookup=lambda d, **k: None,
           set_cached=lambda *a: None,
           _user_allergens=lambda uid: [])
    out = fl.lookup_food("free_text", "chicken bowl from Chipotle", None, "u1")
    assert out["tier_used"] == 2 and out["source"] == "usda_fdc"


def test_usda_cache_hit_no_fetch(monkeypatch):
    called = {"fdc": False}
    _patch(monkeypatch,
           get_cached=lambda k: {"item_name": "banana", "calories": 89, "tier": 2, "source": "usda_fdc"} if k.startswith("usda:") else None,
           fdc_lookup=lambda q: called.__setitem__("fdc", True) or None,
           off_branded_search=lambda q: None, nutritionix_lookup=lambda q: None,
           _user_allergens=lambda uid: [])
    out = fl.lookup_food("name", "banana", None, "u1")
    assert out["tier_used"] == 2 and out["source"] == "usda_fdc" and called["fdc"] is False
```

- [ ] **Step 2: Add anti-flake stubs to the three existing no-restaurant tests** (REQUIRED). These three currently call `lookup_food` with a name and NO restaurant, so after this task they hit the USDA tier first. Their `_patch` calls don't stub `fdc_lookup`, so they'd invoke the REAL `fl.fdc_lookup` — which only returns `None` because `FDC_API_KEY` is unset (a flaky dependency: once the key lands in `.env`, they'd make real HTTP calls). Add `fdc_lookup=lambda q: None,` to the `_patch(...)` call in each:
  - `test_name_falls_through_to_estimate`
  - `test_all_fail_tier5_fallback`
  - `test_tier2_source_exception_falls_through`

(e.g. in `test_name_falls_through_to_estimate`, the `_patch(monkeypatch, get_cached=..., off_branded_search=..., nutritionix_lookup=..., web_nutrition_lookup=..., ai_estimate=..., _user_allergens=...)` gains `fdc_lookup=lambda q: None,`.)

- [ ] **Step 3: Run to verify the new tests fail**

Run: `tests/test_food_lookup_unit.py -v`
Expected: the 3 new tests FAIL (`fl` has no `fdc_lookup` / USDA not wired); the existing tests still pass (the added `fdc_lookup` stub is accepted by `_patch`).

- [ ] **Step 4: Modify `food_lookup.py`** — (a) extend the import:

```python
from app.services.food_sources import off_barcode, off_branded_search, nutritionix_lookup, fdc_lookup
```

(b) add the TTL constant near the other `CACHE_TTL_*`:

```python
CACHE_TTL_USDA = int(os.environ.get("FOOD_CACHE_TTL_USDA", "90"))
```

(c) add the `_usda_tier` helper (e.g. just above `lookup_food`):

```python
def _usda_tier(item: str, user_id: str) -> dict | None:
    """USDA authoritative generic-food tier. Cache → fetch → cache. None on miss."""
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

(d) wire it into `lookup_food`. After the line `combined = f"{rest} {item}".strip() if rest else item` and BEFORE the `# Tier 2 — branded + Nutritionix` block, insert the generic-first call:

```python
    # USDA authoritative generic tier — tried FIRST when no restaurant/brand is named.
    if not rest:
        usda = _usda_tier(item, user_id)
        if usda:
            return usda
```

Then, AFTER the Tier 2 `for fn, arg in (...)` loop and BEFORE the `# Tier 3 — web search` block, insert the fallback call:

```python
    # USDA fallback — when a restaurant/brand was named and branded missed.
    if rest:
        usda = _usda_tier(item, user_id)
        if usda:
            return usda
```

(e) update the module docstring's first line to mention USDA, e.g.: `... Tier 2 (branded+Nutritionix / USDA generic) → Tier 3 (web) → Tier 4 (AI estimate) → Tier 5 ...`.

- [ ] **Step 5: Run to verify pass**

Run: `tests/test_food_lookup_unit.py -v` → all pass (3 new + the existing tests, now deterministic with the `fdc_lookup` stubs).

- [ ] **Step 6: Commit**

```bash
git add hearty-api/app/services/food_lookup.py hearty-api/tests/test_food_lookup_unit.py
git commit -m "feat(food): route USDA tier (generic-first; branded-first fallback) into food_lookup"
```

- [ ] **Step 7: Run the full backend unit suite**

Run: from `hearty-api/`, `/home/evan/projects/food-journal-assistant/hearty-api/.venv/bin/python -m pytest -q` (env sourced; `pytest.ini` excludes the live-server integration tests).
Expected: green. Fix any regression before Task 3.

---

### Task 3: Config — `FDC_API_KEY` in `.env.example` + DEPLOYMENT.md

**Files:**
- Modify: `hearty-api/.env.example`
- Modify: `docs/DEPLOYMENT.md`

- [ ] **Step 1: Add to `hearty-api/.env.example`** — near the other optional food-source keys (`NUTRITIONIX_*`), add:

```
# USDA FoodData Central (authoritative generic-food nutrition tier).
# Free key: https://fdc.nal.usda.gov/api-key-signup.html . Unset → tier skipped.
FDC_API_KEY=
```

- [ ] **Step 2: Add to the DEPLOYMENT.md redeploy env-file key list** — in `docs/DEPLOYMENT.md`, add `FDC_API_KEY` to the `for k in ...` loop in the redeploy procedure (the loop skips empty keys, so it's harmless until set), and mention it in the env-var prose list as an optional food-source key.

- [ ] **Step 3: Commit**

```bash
git add hearty-api/.env.example docs/DEPLOYMENT.md
git commit -m "docs(food): document FDC_API_KEY (USDA tier) in .env.example + DEPLOYMENT"
```

---

### Task 4: Deploy + live verification (MANUAL — requires user consent)

> Live actions (add a secret + Cloud Run redeploy). No migration. Do NOT run without explicit go-ahead. Needs the user's free FDC key (optional — the feature ships safely without it, just inert).

- [ ] **Step 1: Obtain + store the key** — ask the user for an `FDC_API_KEY` (free, https://fdc.nal.usda.gov/api-key-signup.html). Add `FDC_API_KEY=...` to `/home/evan/projects/food-journal-assistant/.env`.
- [ ] **Step 2: Redeploy backend** per `docs/DEPLOYMENT.md` — build `/tmp/hearty-env.yaml` from `.env` (the full key list now includes `FDC_API_KEY`) and `gcloud run deploy hearty-api --source . ... --env-vars-file /tmp/hearty-env.yaml`; `shred -u` after.
- [ ] **Step 3: Verify** — log a generic whole food (e.g. "raw spinach") via the API/app and confirm the result `source` is `usda_fdc` with sensible per-100g macros; confirm a branded/barcoded item still uses Open Food Facts; confirm logging still works with the key unset (tier skipped). FDC `dataType` GET serialization: if the live call returns 400/empty, the `dataType` list may need comma-joining (`"Foundation,SR Legacy"`) instead of repeated params — adjust `fdc_lookup` and redeploy.

---

## Self-Review

**1. Spec coverage:**
- §1 `fdc_lookup` source (key gate, FDC search, nutrient-number mapping, normalized dict, None on miss) → Task 1 ✓
- §2 `_usda_tier` helper + generic-first / branded-first-fallback routing + tier 2 / `usda_fdc` → Task 2 ✓
- §3 Caching (`usda:` key + `CACHE_TTL_USDA` 90d) → Task 2 ✓
- §4 Config (`FDC_API_KEY` in .env.example + DEPLOYMENT.md; best-effort skip) → Task 3 ✓
- Error handling (best-effort tier) → Task 2 `_usda_tier` try/except ✓
- Security (key backend-only; food_cache service-key) → unchanged, noted ✓
- Testing (fdc_lookup mapping/no-key/empty; routing generic-first/branded-fallback/cache-hit; existing tests deterministic) → Tasks 1-2 ✓; Live → Task 4 ✓
- Non-goals (branded dataset, bulk sync, gap-visibility) → not implemented ✓

**2. Placeholder scan:** none — every code step is complete. The only deliberate deploy-time contingency is the `dataType` GET-serialization fallback (Task 4 Step 3), which is a real external-API verification, not a code placeholder.

**3. Type/name consistency:** `fdc_lookup` defined in Task 1, imported + patched as `fl.fdc_lookup` and called by `_usda_tier` in Task 2. The normalized dict keys match the other sources (`food_sources.py`) and what `_result`/the meal layer consume. `source="usda_fdc"`, `tier=2` consistent across `fdc_lookup`, `_usda_tier`, and the tests. Cache key prefix `usda:` consistent between `_usda_tier` and the cache-hit test. `CACHE_TTL_USDA` env name matches `.env.example`/DEPLOYMENT additions.
