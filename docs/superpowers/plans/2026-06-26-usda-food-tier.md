# USDA FoodData Central Tier (LLM-assisted) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Add USDA FoodData Central as an authoritative generic-food nutrition tier in `food_lookup`, selecting the right entry via an LLM (FDC keyword search alone is too noisy), then fetching that food's full nutrition by `fdcId`.

**Architecture:** Pure-HTTP `fdc_search`/`fdc_detail` in `food_sources.py`; an LLM-assisted `fdc_resolve.resolve(query)` (search → LLM pick → detail); `food_lookup._usda_tier` calls `resolve`, routed generic-first / branded-fallback, cached 90d. Best-effort + inert without `FDC_API_KEY`.

**Tech Stack:** FastAPI, httpx, litellm, Supabase (food_cache).

**Spec:** `docs/superpowers/specs/2026-06-26-usda-food-tier-design.md` (redesigned 2026-06-27).

**Worktree:** `~/.config/superpowers/worktrees/usda-tier` (branch `usda-tier`). Tests: from `hearty-api/`, `set -a; source /home/evan/projects/food-journal-assistant/.env; set +a` then `/home/evan/projects/food-journal-assistant/hearty-api/.venv/bin/python -m pytest <paths> -q`.

> **Note:** the branch already has a naive `fdc_lookup` (top-result) + tier wiring + `FDC_API_KEY` config from the first build. This plan REPLACES the naive selection. Task 1 removes `fdc_lookup`; Task 3 repoints `_usda_tier`. The `FDC_API_KEY` config (`.env.example` + DEPLOYMENT.md) is already done — no config task.

---

### Task 1: Pure-HTTP FDC sources — replace `fdc_lookup` with `fdc_search` + `fdc_detail`

**Files:** Modify `hearty-api/app/services/food_sources.py`; rewrite `hearty-api/tests/test_food_sources_fdc_unit.py`.

- [ ] **Step 1: Replace the test file** `hearty-api/tests/test_food_sources_fdc_unit.py` with:

```python
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
    {"nutrient": {"number": "957"}, "amount": 63.0},   # energy via Atwater (no 208 present)
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
    assert out["calories"] == 63.0  # from 957 Atwater fallback (no 208 present)
    assert out["protein_g"] == 0.15 and out["total_carbs_g"] == 15.7 and out["sodium_mg"] == 1.0
    assert out["source"] == "usda_fdc" and out["tier"] == 2


def test_fdc_detail_no_key_returns_none(monkeypatch):
    monkeypatch.delenv("FDC_API_KEY", raising=False)
    assert fs.fdc_detail(111) is None
```

- [ ] **Step 2: Run to verify it fails**

Run: `tests/test_food_sources_fdc_unit.py -v` → FAIL (`fdc_search`/`fdc_detail` don't exist).

- [ ] **Step 3: Replace `fdc_lookup`** in `hearty-api/app/services/food_sources.py` — DELETE the existing `FDC_SEARCH_URL`/`FDC_DATATYPES`/`_FDC_NUTRIENTS`/`fdc_lookup` block (the naive version, at the end of the file) and replace it with:

```python
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
```

- [ ] **Step 4: Run to verify pass** — `tests/test_food_sources_fdc_unit.py -v` → 4 passed.

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/food_sources.py hearty-api/tests/test_food_sources_fdc_unit.py
git commit -m "feat(food): FDC search + detail sources (replaces naive top-result lookup)"
```

---

### Task 2: LLM-assisted resolver — `app/services/fdc_resolve.py`

**Files:** Create `hearty-api/app/services/fdc_resolve.py`; Test `hearty-api/tests/test_fdc_resolve_unit.py`.

- [ ] **Step 1: Write the failing test** — `hearty-api/tests/test_fdc_resolve_unit.py`:

```python
import types
from app.services import fdc_resolve as fr


def _llm(content):
    return types.SimpleNamespace(choices=[types.SimpleNamespace(
        message=types.SimpleNamespace(content=content))])


def test_resolve_picks_and_fetches_detail(monkeypatch):
    monkeypatch.setattr(fr, "fdc_search", lambda q: [
        {"fdc_id": 111, "description": "Apples, fuji, raw", "data_type": "Foundation"},
        {"fdc_id": 222, "description": "Croissants, apple", "data_type": "SR Legacy"}])
    seen = {}
    monkeypatch.setattr(fr, "fdc_detail",
                        lambda fid: seen.update(fid=fid) or {"item_name": "Apples, fuji, raw", "calories": 63, "source": "usda_fdc", "tier": 2})
    monkeypatch.setattr(fr.litellm, "completion", lambda **k: _llm('{"index": 0}'))
    out = fr.resolve("apple")
    assert out["source"] == "usda_fdc" and seen["fid"] == 111


def test_resolve_none_when_llm_says_null(monkeypatch):
    monkeypatch.setattr(fr, "fdc_search", lambda q: [{"fdc_id": 1, "description": "x", "data_type": "Foundation"}])
    called = {"detail": False}
    monkeypatch.setattr(fr, "fdc_detail", lambda fid: called.__setitem__("detail", True) or {"x": 1})
    monkeypatch.setattr(fr.litellm, "completion", lambda **k: _llm('{"index": null}'))
    assert fr.resolve("zzz") is None and called["detail"] is False


def test_resolve_no_candidates_skips_llm(monkeypatch):
    called = {"llm": False}
    monkeypatch.setattr(fr, "fdc_search", lambda q: [])
    monkeypatch.setattr(fr.litellm, "completion", lambda **k: called.__setitem__("llm", True) or _llm('{"index": 0}'))
    assert fr.resolve("apple") is None and called["llm"] is False


def test_resolve_swallows_errors(monkeypatch):
    monkeypatch.setattr(fr, "fdc_search", lambda q: [{"fdc_id": 1, "description": "x", "data_type": "Foundation"}])
    monkeypatch.setattr(fr.litellm, "completion", lambda **k: (_ for _ in ()).throw(RuntimeError("llm down")))
    assert fr.resolve("apple") is None
```

- [ ] **Step 2: Run to verify it fails** — `tests/test_fdc_resolve_unit.py -v` → FAIL (`No module named 'app.services.fdc_resolve'`).

- [ ] **Step 3: Create** `hearty-api/app/services/fdc_resolve.py`:

```python
"""LLM-assisted USDA FoodData Central resolver. Search candidates → ask the LLM to
pick the best generic-food match → fetch that food's full nutrition. Fully
best-effort: any failure (no key, no candidates, LLM/HTTP error, no match) → None."""

import json
import logging
import os
import re

import litellm

from app.services.food_sources import fdc_search, fdc_detail

logger = logging.getLogger(__name__)


def _select(query: str, candidates: list[dict]) -> int | None:
    listing = "\n".join(f"{i}. {c['description']}" for i, c in enumerate(candidates))
    prompt = (
        f"A user logged eating: \"{query}\".\n"
        f"From the USDA entries below, choose the ONE that is the same food in its "
        f"plain/raw/generic form. Avoid processed variants (powder, flour, bread, "
        f"croissant, lunchmeat, chips) and different foods. If none truly match, choose none.\n\n"
        f"{listing}\n\n"
        f'Reply with ONLY a JSON object: {{"index": <number>}} for the best match, '
        f'or {{"index": null}} if none match.'
    )
    resp = litellm.completion(
        model=os.environ.get("LLM_MODEL", "claude-sonnet-4-6"),
        messages=[{"role": "user", "content": prompt}],
        api_base=os.environ.get("LLM_BASE_URL") or None,
        max_tokens=20,
    )
    content = resp.choices[0].message.content or ""
    m = re.search(r"\{.*\}", content, re.S)
    if not m:
        return None
    idx = json.loads(m.group(0)).get("index")
    if isinstance(idx, int) and 0 <= idx < len(candidates):
        return idx
    return None


def resolve(query: str) -> dict | None:
    """Normalized USDA nutrition for the best generic match to `query`, or None."""
    try:
        candidates = fdc_search(query)
        if not candidates:
            return None
        idx = _select(query, candidates)
        if idx is None:
            return None
        return fdc_detail(candidates[idx]["fdc_id"])
    except Exception as e:  # fully best-effort — never raises into the lookup pipeline
        logger.warning("fdc_resolve failed for %r: %s", query, e)
        return None
```

- [ ] **Step 4: Run to verify pass** — `tests/test_fdc_resolve_unit.py -v` → 4 passed.

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/fdc_resolve.py hearty-api/tests/test_fdc_resolve_unit.py
git commit -m "feat(food): LLM-assisted FDC resolver (search -> pick -> detail)"
```

---

### Task 3: Repoint `_usda_tier` to the resolver

**Files:** Modify `hearty-api/app/services/food_lookup.py`; modify `hearty-api/tests/test_food_lookup_unit.py`.

- [ ] **Step 1: Update the routing-test stubs** — in `hearty-api/tests/test_food_lookup_unit.py`, the USDA-related tests currently patch `fdc_lookup=...`. Rename every `fdc_lookup=` to `fdc_resolve=` (same lambda values). This affects: the 3 new USDA tests (`test_generic_lookup_usda_first`, `test_restaurant_branded_then_usda_fallback`, `test_usda_cache_hit_no_fetch`) and the 3 existing anti-flake stubs (`test_name_falls_through_to_estimate`, `test_all_fail_tier5_fallback`, `test_tier2_source_exception_falls_through`). (In `test_generic_lookup_usda_first` the key is `fdc_lookup=lambda q: {...}` → `fdc_resolve=lambda q: {...}`; in the anti-flake ones `fdc_lookup=lambda q: None` → `fdc_resolve=lambda q: None`; in `test_usda_cache_hit_no_fetch` the `fdc_lookup=lambda q: called...` → `fdc_resolve=lambda q: called...`.)

- [ ] **Step 2: Run to verify it fails** — `tests/test_food_lookup_unit.py -v` → the USDA tests FAIL (`fl` has no `fdc_resolve`; `_usda_tier` still calls `fdc_lookup`).

- [ ] **Step 3: Modify `hearty-api/app/services/food_lookup.py`:**
  (a) Change the food_sources import to drop `fdc_lookup` (keep the others):
```python
from app.services.food_sources import off_barcode, off_branded_search, nutritionix_lookup
```
  (b) Add a new import for the resolver:
```python
from app.services.fdc_resolve import resolve as fdc_resolve
```
  (c) In `_usda_tier`, change the fetch line `hit = fdc_lookup(item)` to:
```python
        hit = fdc_resolve(item)
```
(Everything else in `_usda_tier` and the routing is unchanged.)

- [ ] **Step 4: Run to verify pass** — `tests/test_food_lookup_unit.py -v` → all pass.

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/food_lookup.py hearty-api/tests/test_food_lookup_unit.py
git commit -m "feat(food): _usda_tier uses the LLM-assisted resolver"
```

- [ ] **Step 6: Run the full backend unit suite** — from `hearty-api/`, `/home/evan/projects/food-journal-assistant/hearty-api/.venv/bin/python -m pytest -q` (env sourced). Expected green. Report the summary line.

---

### Task 4: Deploy + live verification (MANUAL — requires user consent)

> Live actions (Cloud Run redeploy). `FDC_API_KEY` is already in `.env`. Do NOT run without explicit go-ahead.

- [ ] **Step 1: Redeploy backend** from master (after merge) per `docs/DEPLOYMENT.md` — build `/tmp/hearty-env.yaml` from `.env` (key list already includes `FDC_API_KEY`), `gcloud run deploy hearty-api --source . ... --env-vars-file /tmp/hearty-env.yaml`, `shred -u`.
- [ ] **Step 2: Verify** — log "apple", "chicken breast", "banana" → confirm `source=usda_fdc` with correct raw-food macros (apple ≈ 52–63 kcal, chicken breast ≈ 110–165, banana ≈ 89); log "oatmeal" or an obscure phrase → confirm it falls through (resolver returns None) without error; a branded/barcoded item still uses OFF; logging works with `FDC_API_KEY` unset (tier skipped).
- [ ] **Step 3: Finish the branch** — superpowers:finishing-a-development-branch.

---

## Self-Review

**1. Spec coverage:** §1 `fdc_search`+`fdc_detail` (energy 208→957 fallback, candidates) → Task 1 ✓; §2 `fdc_resolve` (search→LLM pick→detail, best-effort, null/no-cand/error→None) → Task 2 ✓; §3 `_usda_tier` repointed to `fdc_resolve`, routing unchanged, cached 90d → Task 3 ✓; config already present (noted) ✓; testing (sources, resolver, routing) → Tasks 1-3 ✓; live → Task 4 ✓; non-goals deferred ✓.

**2. Placeholder scan:** none — every code step is complete.

**3. Type/name consistency:** `fdc_search`/`fdc_detail` defined in Task 1, imported by `fdc_resolve` (Task 2) and patched as `fr.fdc_search`/`fr.fdc_detail`. `fdc_resolve.resolve` imported into `food_lookup` as `fdc_resolve` (Task 3), called by `_usda_tier`, patched as `fl.fdc_resolve` in tests. Normalized dict keys (`item_name`, `calories`, macros, `source="usda_fdc"`, `tier=2`) consistent between `fdc_detail`, the resolver's return, `_result`, and the meal layer. Candidate dict keys (`fdc_id`, `description`, `data_type`) consistent between `fdc_search`, `_select` (reads `description`), and `resolve` (reads `fdc_id`).
