# Food Intelligence — Tiered Nutrition Lookup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the Spec-07 tiered food-nutrition pipeline: given a barcode / product name / free-text description, return structured nutrition by trying cache → Tier 1 (Open Food Facts barcode) → Tier 2 (OFF branded + Nutritionix) → Tier 3 (Claude web_search via Brave) → Tier 4 (Claude AI estimate) → Tier 5 (honest fallback). Never block a log; Tier 5 always succeeds. Plus a shared `food_cache`, allergen cross-reference against the health profile, and free-text field extraction.

**Architecture:** Pure-ish tier services (each HTTP/LLM call injectable for tests) + a `food_cache` store (global, server-side, service-key only) + an orchestrator `food_lookup.lookup_food(...)` that owns cache + tier fall-through + allergen cross-ref + the Tier-4/5 message, behind `POST /api/food/lookup` and `GET /api/food/cache/{key}`. Sync services using `httpx.Client` + sync `litellm.completion` (matches the codebase's sync service style, e.g. `signal_engine.py`/`ai_extraction.py`); async routes call the sync orchestrator directly (as `trends.py` calls `signal_engine`).

**Tech Stack:** FastAPI + Supabase (service key) + litellm (incl. tool-use for Tier 3) + httpx. Spec: `docs/superpowers/specs/2026-05-04-hearty-07-food-intelligence.md`. Backend test runner: `cd hearty-api && set -a && . ../.env && set +a && .venv/bin/python -m pytest <file> -v`. Migrations: `scripts/db-push.sh`.

**Decisions (locked):** Full 5 tiers INCLUDING Tier 3 web-search. Nutritionix uses the app-level `.env` keys server-side (`NUTRITIONIX_APP_ID`/`NUTRITIONIX_API_KEY`), NOT per-user keys. Tier 3 uses Brave (`BRAVE_SEARCH_API_KEY`, placeholder added to `.env` — unit tests mock it; live/device pass needs it filled). USDA Tier-1-secondary deferred (no key). Vision→lookup wiring deferred (separate follow-up). LLM model: `FOOD_LLM_MODEL` env or fallback to `LLM_MODEL` (Haiku 4.5).

**Verified codebase facts:**
- `food_lookup.py` is a placeholder (comments only). Nothing calls `/api/food/lookup` yet.
- `httpx` available; existing async usage in `app/routers/transcribe.py`. We use sync `httpx.Client` here.
- `requests`/`httpx` in requirements; no new deps needed.
- `health_profile` table has `allergens JSONB DEFAULT '[]'`; health-profile schemas model it as `list[AllergenEntry]` (`app/health_profile/schemas.py`). Read the real `AllergenEntry` shape in Task 7 and match on its name field.
- Supabase client pattern: `supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])`.
- litellm pattern: `litellm.completion(model=..., messages=[...], api_base=os.environ.get("LLM_BASE_URL") or None)`.
- `app/models/schemas.py` already has `FoodItem`; imports `BaseModel, Field, Optional, List, Literal, Dict`.

**Constants (module-level, env-overridable):** `FOOD_LLM_MODEL = os.environ.get("FOOD_LLM_MODEL") or os.environ.get("LLM_MODEL","claude-sonnet-4-6")`, `CACHE_TTL_BARCODE=30`, `CACHE_TTL_RESTAURANT=30`, `CACHE_TTL_WEB=7`, `FUZZY_THRESHOLD=0.75`, `WEB_MAX_TOOL_ROUNDS=4`, `HTTP_TIMEOUT=10.0`.

---

## File Structure

- `supabase/migrations/20260616000000_food_cache.sql` — shared cache table.
- `hearty-api/app/services/food_cache.py` — get/set with TTL (service-key, global).
- `hearty-api/app/services/food_sources.py` — Open Food Facts (barcode + branded) + Nutritionix HTTP clients → normalized nutrition dicts.
- `hearty-api/app/services/web_nutrition.py` — Brave search + Tier 3 Claude tool-use extraction.
- `hearty-api/app/services/food_estimate.py` — Tier 4 AI estimation + Tier-5-adjacent helpers (free-text extraction, allergen cross-ref).
- `hearty-api/app/services/food_lookup.py` — orchestrator (replace placeholder).
- `hearty-api/app/routers/food.py` — endpoints.
- `hearty-api/app/models/schemas.py` — request/response models.
- `hearty-api/app/main.py` — register router.

---

## Task 1: `food_cache` migration

**Files:** Create `supabase/migrations/20260616000000_food_cache.sql`

- [ ] **Step 1: Write the migration**

```sql
-- Shared, server-side food-nutrition cache (NOT user-scoped — nutrition data is
-- public and shared across users). Written/read only by the service-key client;
-- RLS is enabled with no policies so it is never reachable via the Data API.
CREATE TABLE food_cache (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lookup_key     TEXT NOT NULL UNIQUE,
  source         TEXT NOT NULL,
  nutrition_data JSONB NOT NULL,
  cached_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  ttl_days       INT NOT NULL
);

CREATE INDEX idx_food_cache_key ON food_cache (lookup_key);

ALTER TABLE food_cache ENABLE ROW LEVEL SECURITY;
-- No policies: only the service-role key (which bypasses RLS) touches this table.
```

- [ ] **Step 2: Apply** — `scripts/db-push.sh --dry-run` (confirm only this is pending), then `scripts/db-push.sh --yes`.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260616000000_food_cache.sql
git commit -m "feat(food): food_cache table (shared server-side nutrition cache)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Cache store (TTL-aware, TDD)

**Files:** Create `hearty-api/app/services/food_cache.py`; Test `hearty-api/tests/test_food_cache_unit.py`

- [ ] **Step 1: Write the failing test**

```python
from datetime import datetime, timezone, timedelta
from app.services import food_cache as fc


class _Result:
    def __init__(self, data): self.data = data


def _supa(rows, rec=None):
    class _T:
        def select(self, *a, **k): return self
        def eq(self, *a, **k): return self
        def limit(self, *a, **k): return self
        def upsert(self, row, **k):
            if rec is not None: rec["upsert"] = row
            return self
        def execute(self): return _Result(rows)
    return type("S", (), {"table": lambda s, n: _T()})()


def test_get_cached_returns_fresh(monkeypatch):
    cached_at = (datetime.now(timezone.utc) - timedelta(days=5)).isoformat()
    monkeypatch.setattr(fc, "supabase", _supa([{
        "lookup_key": "barcode:1", "source": "open_food_facts",
        "nutrition_data": {"calories": 100}, "cached_at": cached_at, "ttl_days": 30}]))
    out = fc.get_cached("barcode:1")
    assert out["calories"] == 100


def test_get_cached_expired_returns_none(monkeypatch):
    cached_at = (datetime.now(timezone.utc) - timedelta(days=40)).isoformat()
    monkeypatch.setattr(fc, "supabase", _supa([{
        "lookup_key": "barcode:1", "source": "x",
        "nutrition_data": {"calories": 100}, "cached_at": cached_at, "ttl_days": 30}]))
    assert fc.get_cached("barcode:1") is None


def test_get_cached_miss_returns_none(monkeypatch):
    monkeypatch.setattr(fc, "supabase", _supa([]))
    assert fc.get_cached("barcode:nope") is None


def test_set_cached_upserts_by_key(monkeypatch):
    rec = {}
    monkeypatch.setattr(fc, "supabase", _supa([], rec))
    fc.set_cached("barcode:1", "open_food_facts", {"calories": 100}, 30)
    assert rec["upsert"]["lookup_key"] == "barcode:1"
    assert rec["upsert"]["ttl_days"] == 30
    assert rec["upsert"]["nutrition_data"] == {"calories": 100}
```

- [ ] **Step 2: Run to confirm fail.**

- [ ] **Step 3: Implement**

```python
"""Shared server-side nutrition cache. Global (not user-scoped); only the
service-key client touches food_cache. Expiry is evaluated at read time."""

import os
from datetime import datetime, timezone, timedelta

from supabase import create_client

supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


def get_cached(lookup_key: str) -> dict | None:
    rows = (supabase.table("food_cache").select("*")
            .eq("lookup_key", lookup_key).limit(1).execute()).data or []
    if not rows:
        return None
    row = rows[0]
    cached_at = datetime.fromisoformat(row["cached_at"])
    if cached_at.tzinfo is None:
        cached_at = cached_at.replace(tzinfo=timezone.utc)
    if cached_at + timedelta(days=row["ttl_days"]) <= datetime.now(timezone.utc):
        return None  # expired → treat as miss
    return row["nutrition_data"]


def set_cached(lookup_key: str, source: str, nutrition_data: dict,
               ttl_days: int) -> None:
    supabase.table("food_cache").upsert({
        "lookup_key": lookup_key, "source": source,
        "nutrition_data": nutrition_data, "ttl_days": ttl_days,
        "cached_at": datetime.now(timezone.utc).isoformat(),
    }, on_conflict="lookup_key").execute()
```

- [ ] **Step 4: Run to confirm pass** (4 tests).

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/food_cache.py hearty-api/tests/test_food_cache_unit.py
git commit -m "feat(food): TTL-aware nutrition cache store

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Open Food Facts client (Tier 1 barcode + Tier 2 branded, TDD)

**Files:** Create `hearty-api/app/services/food_sources.py` (OFF part); Test `hearty-api/tests/test_food_sources_off_unit.py`

OFF returns nutriments keyed `_serving` (preferred) or `_100g`. We map to the normalized schema; missing values stay `None`.

- [ ] **Step 1: Write the failing test**

```python
from unittest.mock import patch
from app.services import food_sources as fs


class _Resp:
    def __init__(self, payload, status=200): self._p = payload; self.status_code = status
    def json(self): return self._p
    def raise_for_status(self): pass


def test_off_barcode_parses_product():
    payload = {"status": 1, "product": {
        "product_name": "Oat Milk", "brands": "Oatly",
        "serving_size": "240 ml",
        "nutriments": {"energy-kcal_serving": 120, "fat_serving": 5,
                       "carbohydrates_serving": 16, "proteins_serving": 3,
                       "sodium_serving": 0.1},
        "ingredients_text": "water, oats", "allergens_tags": ["en:gluten"]}}
    with patch.object(fs.httpx, "Client") as C:
        C.return_value.__enter__.return_value.get.return_value = _Resp(payload)
        out = fs.off_barcode("123")
    assert out["product_name"] == "Oat Milk" and out["brand"] == "Oatly"
    assert out["calories"] == 120 and out["protein_g"] == 3
    assert out["source"] == "open_food_facts" and out["tier"] == 1
    assert "gluten" in [a.lower() for a in out["allergens"]]


def test_off_barcode_not_found_returns_none():
    with patch.object(fs.httpx, "Client") as C:
        C.return_value.__enter__.return_value.get.return_value = _Resp({"status": 0})
        assert fs.off_barcode("000") is None


def test_off_branded_search_first_hit():
    payload = {"products": [{"product_name": "Clif Bar", "brands": "Clif",
        "serving_size": "68 g",
        "nutriments": {"energy-kcal_serving": 250, "fat_serving": 6,
                       "carbohydrates_serving": 44, "proteins_serving": 9,
                       "sodium_serving": 0.2}}]}
    with patch.object(fs.httpx, "Client") as C:
        C.return_value.__enter__.return_value.get.return_value = _Resp(payload)
        out = fs.off_branded_search("clif bar")
    assert out["product_name"] == "Clif Bar"
    assert out["calories"] == 250 and out["tier"] == 2
    assert out["source"] == "open_food_facts_branded"


def test_off_branded_search_empty_returns_none():
    with patch.object(fs.httpx, "Client") as C:
        C.return_value.__enter__.return_value.get.return_value = _Resp({"products": []})
        assert fs.off_branded_search("zzzzz") is None
```

- [ ] **Step 2: Run to confirm fail.**

- [ ] **Step 3: Implement** (OFF section of `food_sources.py`)

```python
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
```

- [ ] **Step 4: Run to confirm pass** (4 tests).

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/food_sources.py hearty-api/tests/test_food_sources_off_unit.py
git commit -m "feat(food): Open Food Facts client (barcode + branded search)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Nutritionix client (Tier 2 secondary, TDD)

**Files:** Modify `hearty-api/app/services/food_sources.py` (add Nutritionix); Test `hearty-api/tests/test_food_sources_nutritionix_unit.py`

Only attempted if both `NUTRITIONIX_APP_ID` and `NUTRITIONIX_API_KEY` are set; otherwise returns None (caller falls through).

- [ ] **Step 1: Write the failing test**

```python
from unittest.mock import patch
from app.services import food_sources as fs


class _Resp:
    def __init__(self, payload, status=200): self._p = payload; self.status_code = status
    def json(self): return self._p
    def raise_for_status(self): pass


def test_nutritionix_parses_first_food(monkeypatch):
    monkeypatch.setenv("NUTRITIONIX_APP_ID", "id")
    monkeypatch.setenv("NUTRITIONIX_API_KEY", "key")
    payload = {"foods": [{"food_name": "big mac", "brand_name": "McDonald's",
        "serving_qty": 1, "serving_unit": "burger", "nf_calories": 563,
        "nf_total_fat": 33, "nf_total_carbohydrate": 45, "nf_protein": 26,
        "nf_sodium": 1010}]}
    rec = {}
    with patch.object(fs.httpx, "Client") as C:
        post = C.return_value.__enter__.return_value.post
        post.return_value = _Resp(payload)
        out = fs.nutritionix_lookup("big mac")
        rec["headers"] = post.call_args.kwargs.get("headers", {})
    assert out["item_name"] == "big mac" and out["calories"] == 563
    assert out["source"] == "nutritionix" and out["tier"] == 2
    assert rec["headers"]["x-app-id"] == "id" and rec["headers"]["x-app-key"] == "key"


def test_nutritionix_no_keys_returns_none(monkeypatch):
    monkeypatch.delenv("NUTRITIONIX_APP_ID", raising=False)
    monkeypatch.delenv("NUTRITIONIX_API_KEY", raising=False)
    assert fs.nutritionix_lookup("big mac") is None


def test_nutritionix_empty_returns_none(monkeypatch):
    monkeypatch.setenv("NUTRITIONIX_APP_ID", "id")
    monkeypatch.setenv("NUTRITIONIX_API_KEY", "key")
    with patch.object(fs.httpx, "Client") as C:
        C.return_value.__enter__.return_value.post.return_value = _Resp({"foods": []})
        assert fs.nutritionix_lookup("zzzzz") is None
```

- [ ] **Step 2: Run to confirm fail.**

- [ ] **Step 3: Implement** (append to `food_sources.py`)

```python
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
```

- [ ] **Step 4: Run to confirm pass** (3 tests).

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/food_sources.py hearty-api/tests/test_food_sources_nutritionix_unit.py
git commit -m "feat(food): Nutritionix client (Tier 2, server-side keys)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Tier 3 — Brave search + Claude tool-use extraction (TDD)

**Files:** Create `hearty-api/app/services/web_nutrition.py`; Test `hearty-api/tests/test_web_nutrition_unit.py`

`brave_search(query)` calls the Brave API (returns a list of `{title,url,description}`). `web_nutrition_lookup(description, search=, complete=)` runs a Claude tool-use loop: Claude may call a `web_search` function (we execute via `search`), reads results, and returns nutrition JSON (or null). Both `search` and `complete` are injected for tests. Returns None if no key, no data, or rounds exhausted.

> Verify litellm's tool-call object shape against the installed version (`response.choices[0].message.tool_calls[i].function.name/.arguments` and the `{"role":"tool","tool_call_id":...,"content":...}` reply format). Adapt the loop to the real shape if it differs; the tests below pin the contract via fakes.

- [ ] **Step 1: Write the failing test**

```python
import json
from types import SimpleNamespace
from app.services import web_nutrition as wn


def _msg(content=None, tool_calls=None):
    return SimpleNamespace(choices=[SimpleNamespace(
        message=SimpleNamespace(content=content, tool_calls=tool_calls))])


def _tool_call(cid, query):
    return SimpleNamespace(id=cid, function=SimpleNamespace(
        name="web_search", arguments=json.dumps({"query": query})))


def test_brave_search_parses_results(monkeypatch):
    from unittest.mock import patch
    class _Resp:
        status_code = 200
        def json(self): return {"web": {"results": [
            {"title": "T", "url": "http://x", "description": "D"}]}}
        def raise_for_status(self): pass
    monkeypatch.setenv("BRAVE_SEARCH_API_KEY", "bk")
    with patch.object(wn.httpx, "Client") as C:
        C.return_value.__enter__.return_value.get.return_value = _Resp()
        out = wn.brave_search("clif bar nutrition")
    assert out[0]["url"] == "http://x"


def test_web_lookup_tool_loop_then_json():
    calls = {"searches": 0}
    def fake_search(q):
        calls["searches"] += 1
        return [{"title": "Clif", "url": "http://c", "description": "250 cal"}]
    seq = [
        _msg(tool_calls=[_tool_call("c1", "clif bar nutrition")]),  # round 1: search
        _msg(content=json.dumps({"item_name": "Clif Bar", "calories": 250,
             "total_fat_g": 6, "total_carbs_g": 44, "protein_g": 9,
             "source_url": "http://c"})),                            # round 2: answer
    ]
    def fake_complete(**kw): return seq.pop(0)
    out = wn.web_nutrition_lookup("clif bar", search=fake_search, complete=fake_complete)
    assert calls["searches"] == 1
    assert out["calories"] == 250 and out["source"] == "web_search" and out["tier"] == 3
    assert out["source_url"] == "http://c"


def test_web_lookup_no_data_returns_none():
    def fake_complete(**kw): return _msg(content="NO_DATA")
    out = wn.web_nutrition_lookup("zzz", search=lambda q: [], complete=fake_complete)
    assert out is None


def test_web_lookup_no_key_returns_none(monkeypatch):
    monkeypatch.delenv("BRAVE_SEARCH_API_KEY", raising=False)
    # default search path requires the key; with no key and the real default search,
    # the loop must bail to None without calling the model.
    out = wn.web_nutrition_lookup("clif bar")
    assert out is None
```

- [ ] **Step 2: Run to confirm fail.**

- [ ] **Step 3: Implement**

```python
"""Tier 3: Claude reads Brave web-search results and extracts nutrition. The
search executor and the LLM call are injected so the tool-use loop is testable
without network or model access."""

import json
import os

import httpx
import litellm

HTTP_TIMEOUT = float(os.environ.get("FOOD_HTTP_TIMEOUT", "10.0"))
WEB_MAX_TOOL_ROUNDS = int(os.environ.get("FOOD_WEB_MAX_TOOL_ROUNDS", "4"))
FOOD_LLM_MODEL = os.environ.get("FOOD_LLM_MODEL") or os.environ.get(
    "LLM_MODEL", "claude-sonnet-4-6")
BRAVE_URL = "https://api.search.brave.com/res/v1/web/search"

_WEB_PROMPT = (
    "Find nutrition facts for: {item}. Use the web_search tool to look it up, "
    "then reply with ONLY a JSON object: {{\"item_name\": str, \"calories\": "
    "int|null, \"total_fat_g\": num|null, \"total_carbs_g\": num|null, "
    "\"protein_g\": num|null, \"source_url\": str}}. If you cannot find reliable "
    "nutrition data, reply with exactly NO_DATA."
)

_TOOLS = [{"type": "function", "function": {
    "name": "web_search",
    "description": "Search the web and return result snippets.",
    "parameters": {"type": "object",
                   "properties": {"query": {"type": "string"}},
                   "required": ["query"]}}}]


def brave_search(query: str) -> list[dict]:
    key = os.environ.get("BRAVE_SEARCH_API_KEY")
    if not key:
        return []
    headers = {"X-Subscription-Token": key, "Accept": "application/json"}
    with httpx.Client(timeout=HTTP_TIMEOUT) as client:
        r = client.get(BRAVE_URL, headers=headers,
                       params={"q": query, "count": 5})
        r.raise_for_status()
        results = ((r.json() or {}).get("web") or {}).get("results") or []
    return [{"title": x.get("title"), "url": x.get("url"),
             "description": x.get("description")} for x in results]


def _strip_fence(t: str) -> str:
    t = t.strip()
    if t.startswith("```"):
        t = t.split("\n", 1)[1] if "\n" in t else t
        if t.endswith("```"):
            t = t.rsplit("```", 1)[0]
    return t.strip()


def web_nutrition_lookup(description: str, search=None, complete=None) -> dict | None:
    # Default search needs a Brave key; bail before calling the model if absent.
    if search is None:
        if not os.environ.get("BRAVE_SEARCH_API_KEY"):
            return None
        search = brave_search
    complete = complete or litellm.completion

    messages = [{"role": "user", "content": _WEB_PROMPT.format(item=description)}]
    for _ in range(WEB_MAX_TOOL_ROUNDS):
        resp = complete(model=FOOD_LLM_MODEL, messages=messages, tools=_TOOLS,
                        api_base=os.environ.get("LLM_BASE_URL") or None)
        msg = resp.choices[0].message
        tool_calls = getattr(msg, "tool_calls", None)
        if tool_calls:
            messages.append({"role": "assistant", "content": msg.content or "",
                             "tool_calls": [
                {"id": tc.id, "type": "function",
                 "function": {"name": tc.function.name,
                              "arguments": tc.function.arguments}}
                for tc in tool_calls]})
            for tc in tool_calls:
                try:
                    args = json.loads(tc.function.arguments)
                except (TypeError, ValueError):
                    args = {}
                results = search(args.get("query", description))
                messages.append({"role": "tool", "tool_call_id": tc.id,
                                 "content": json.dumps(results)})
            continue
        content = _strip_fence(msg.content or "")
        if not content or content.strip() == "NO_DATA":
            return None
        try:
            data = json.loads(content)
        except (TypeError, ValueError):
            return None
        return {"item_name": data.get("item_name") or description,
                "calories": data.get("calories"),
                "total_fat_g": data.get("total_fat_g"),
                "total_carbs_g": data.get("total_carbs_g"),
                "protein_g": data.get("protein_g"),
                "source": "web_search",
                "source_url": data.get("source_url") or "",
                "tier": 3}
    return None
```

- [ ] **Step 4: Run to confirm pass** (4 tests).

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/web_nutrition.py hearty-api/tests/test_web_nutrition_unit.py
git commit -m "feat(food): Tier 3 web nutrition (Brave search + Claude tool-use)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: Tier 4 AI estimation (TDD)

**Files:** Create `hearty-api/app/services/food_estimate.py`; Test `hearty-api/tests/test_food_estimate_unit.py`

- [ ] **Step 1: Write the failing test**

```python
import json
from types import SimpleNamespace
from unittest.mock import patch
from app.services import food_estimate as fe


def _fake(content):
    return SimpleNamespace(choices=[SimpleNamespace(
        message=SimpleNamespace(content=content))])


def test_ai_estimate_parses():
    payload = {"calories": 200, "protein_g": 5, "total_carbs_g": 30,
               "total_fat_g": 7, "confidence": 0.6}
    with patch.object(fe.litellm, "completion", return_value=_fake(json.dumps(payload))):
        out = fe.ai_estimate("a slice of banana bread")
    assert out["calories"] == 200 and out["confidence"] == 0.6
    assert out["source"] == "ai_estimate" and out["tier"] == 4
    assert out["item_name"] == "a slice of banana bread"


def test_ai_estimate_unparseable_returns_null_estimate():
    with patch.object(fe.litellm, "completion", return_value=_fake("dunno")):
        out = fe.ai_estimate("mystery goo")
    assert out["tier"] == 4 and out["confidence"] == 0.0
    assert out["calories"] is None
```

- [ ] **Step 2: Run to confirm fail.**

- [ ] **Step 3: Implement**

```python
"""Tier 4: Claude estimates nutrition from a free-text description. Always
returns a result (never cached); on parse failure returns a zero-confidence
null estimate so the orchestrator can still surface the ai_estimate caveat."""

import json
import os

import litellm

FOOD_LLM_MODEL = os.environ.get("FOOD_LLM_MODEL") or os.environ.get(
    "LLM_MODEL", "claude-sonnet-4-6")

_ESTIMATE_PROMPT = (
    "Estimate the nutritional content for the following food item. Return JSON "
    "only, no prose: {{\"calories\": int, \"protein_g\": num, \"total_carbs_g\": "
    "num, \"total_fat_g\": num, \"confidence\": float between 0 and 1}}. Base your "
    "estimate on typical preparation and standard portion sizes. If you cannot "
    "make a reasonable estimate, set all numeric fields to null and confidence to "
    "0.\n\nFood item: {description}"
)


def _strip_fence(t: str) -> str:
    t = t.strip()
    if t.startswith("```"):
        t = t.split("\n", 1)[1] if "\n" in t else t
        if t.endswith("```"):
            t = t.rsplit("```", 1)[0]
    return t.strip()


def ai_estimate(description: str) -> dict:
    resp = litellm.completion(
        model=FOOD_LLM_MODEL,
        messages=[{"role": "user",
                   "content": _ESTIMATE_PROMPT.format(description=description)}],
        api_base=os.environ.get("LLM_BASE_URL") or None)
    content = _strip_fence(resp.choices[0].message.content or "")
    try:
        data = json.loads(content)
    except (TypeError, ValueError):
        data = {"calories": None, "protein_g": None, "total_carbs_g": None,
                "total_fat_g": None, "confidence": 0.0}
    return {"item_name": description, "calories": data.get("calories"),
            "protein_g": data.get("protein_g"),
            "total_carbs_g": data.get("total_carbs_g"),
            "total_fat_g": data.get("total_fat_g"),
            "confidence": data.get("confidence") if data.get("confidence") is not None else 0.0,
            "source": "ai_estimate", "tier": 4}
```

- [ ] **Step 4: Run to confirm pass** (2 tests).

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/food_estimate.py hearty-api/tests/test_food_estimate_unit.py
git commit -m "feat(food): Tier 4 AI nutrition estimation

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: Free-text extraction + allergen cross-reference (TDD)

**Files:** Modify `hearty-api/app/services/food_estimate.py` (add both); Test `hearty-api/tests/test_food_extract_allergen_unit.py`

First READ `hearty-api/app/health_profile/schemas.py` for the real `AllergenEntry` shape and how `health_profile.allergens` is stored (list of objects with a name field). Match on the name (case-insensitive substring).

- [ ] **Step 1: Write the failing test**

```python
import json
from types import SimpleNamespace
from unittest.mock import patch
from app.services import food_estimate as fe


def _fake(content):
    return SimpleNamespace(choices=[SimpleNamespace(
        message=SimpleNamespace(content=content))])


def test_extract_lookup_fields():
    payload = {"restaurant": "Gong Cha", "item": "wintergreen melon drink",
               "size": "large", "modifiers": None}
    with patch.object(fe.litellm, "completion", return_value=_fake(json.dumps(payload))):
        out = fe.extract_lookup_fields("I had a wintergreen melon large drink from Gong Cha")
    assert out["restaurant"] == "Gong Cha" and out["item"] == "wintergreen melon drink"
    assert out["size"] == "large"


def test_allergen_warnings_matches_user_allergens():
    nutrition = {"allergens": ["gluten"], "ingredients": ["water", "wheat flour"]}
    warnings = fe.allergen_warnings(nutrition, user_allergens=["wheat", "soy"])
    assert any("wheat" in w.lower() for w in warnings)
    assert not any("soy" in w.lower() for w in warnings)


def test_allergen_warnings_empty_when_no_match():
    nutrition = {"allergens": [], "ingredients": ["water", "oats"]}
    assert fe.allergen_warnings(nutrition, user_allergens=["peanut"]) == []
```

- [ ] **Step 2: Run to confirm fail.**

- [ ] **Step 3: Implement** (append to `food_estimate.py`)

```python
_EXTRACT_PROMPT = (
    "Extract structured food lookup fields from this user input. Return JSON only: "
    "{{\"restaurant\": str|null, \"item\": str, \"size\": str|null, \"modifiers\": "
    "[str]|null}}. If no restaurant is mentioned, set restaurant to null.\n\n"
    "User input: {raw_text}"
)


def extract_lookup_fields(raw_text: str) -> dict:
    resp = litellm.completion(
        model=FOOD_LLM_MODEL,
        messages=[{"role": "user",
                   "content": _EXTRACT_PROMPT.format(raw_text=raw_text)}],
        api_base=os.environ.get("LLM_BASE_URL") or None)
    content = _strip_fence(resp.choices[0].message.content or "")
    try:
        data = json.loads(content)
    except (TypeError, ValueError):
        return {"restaurant": None, "item": raw_text, "size": None, "modifiers": None}
    return {"restaurant": data.get("restaurant"), "item": data.get("item") or raw_text,
            "size": data.get("size"), "modifiers": data.get("modifiers")}


def allergen_warnings(nutrition: dict, user_allergens: list[str]) -> list[str]:
    """Case-insensitive substring match of each user allergen against the result's
    allergens + ingredients. Informational only — never blocks logging."""
    haystack = " ".join([
        *(nutrition.get("allergens") or []),
        *(nutrition.get("ingredients") or []),
    ]).lower()
    warnings = []
    for a in user_allergens:
        a = (a or "").strip().lower()
        if a and a in haystack:
            warnings.append(f"contains: {a}")
    return warnings
```

- [ ] **Step 4: Run to confirm pass** (3 tests).

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/food_estimate.py hearty-api/tests/test_food_extract_allergen_unit.py
git commit -m "feat(food): free-text field extraction + allergen cross-reference

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: Orchestrator — tiered fall-through + cache + allergens (TDD)

**Files:** Replace `hearty-api/app/services/food_lookup.py`; Test `hearty-api/tests/test_food_lookup_unit.py`

`lookup_food(type, value, restaurant, user_id)` — cache check first; barcode → Tier 1; name/free_text → (free_text: extract first) Tier 2 → Tier 3 → Tier 4; always Tier 5 fallback; cache writes for tiers 1–3; allergen cross-ref after any hit; Tier-4/5 messages.

- [ ] **Step 1: Write the failing test**

```python
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
           ai_estimate=lambda d: {"item_name": d, "calories": None, "confidence": 0.0, "source": "ai_estimate", "tier": 4},
           _user_allergens=lambda uid: [])
    # ai_estimate returns confidence 0/no calories → still tier 4 result; force a true
    # all-fail by making estimate raise to exercise tier 5:
    _patch(monkeypatch, ai_estimate=lambda d: (_ for _ in ()).throw(RuntimeError("down")))
    out = fl.lookup_food("name", "mystery", None, "u1")
    assert out["tier_used"] == 5 and out["nutrition"] is None
    assert "couldn't find" in out["message"].lower()


def test_allergen_warnings_attached(monkeypatch):
    _patch(monkeypatch,
           get_cached=lambda k: None,
           off_barcode=lambda b: {"product_name": "Bread", "calories": 100, "tier": 1, "source": "open_food_facts", "allergens": ["gluten"], "ingredients": ["wheat flour"]},
           set_cached=lambda *a: None,
           _user_allergens=lambda uid: ["wheat"])
    out = fl.lookup_food("barcode", "1", None, "u1")
    assert any("wheat" in w.lower() for w in out["allergen_warnings"])
```

- [ ] **Step 2: Run to confirm fail.**

- [ ] **Step 3: Implement** (replace `food_lookup.py`)

```python
"""Tiered food-nutrition lookup orchestrator. Cache → Tier 1 (barcode) /
Tier 2 (branded+Nutritionix) → Tier 3 (web) → Tier 4 (AI estimate) → Tier 5
(honest fallback). Never blocks: Tier 5 always returns a usable result."""

import hashlib
import os
import re

from supabase import create_client

from app.services.food_cache import get_cached, set_cached
from app.services.food_sources import off_barcode, off_branded_search, nutritionix_lookup
from app.services.web_nutrition import web_nutrition_lookup
from app.services.food_estimate import ai_estimate, extract_lookup_fields, allergen_warnings

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
    # Tier resolution depends on input type.
    if type == "barcode":
        key = f"barcode:{value}"
        cached = get_cached(key)
        if cached:
            return _result(cached, cached.get("tier", 1), cached.get("source", "open_food_facts"), user_id)
        try:
            hit = off_barcode(value)
        except Exception:
            hit = None
        if hit:
            set_cached(key, hit["source"], hit, CACHE_TTL_BARCODE)
            return _result(hit, 1, hit["source"], user_id)
        # Barcode unknown → honest fallback (no name to estimate from).
        return _tier5(value, user_id)

    # name / free_text
    item, rest = value, restaurant
    if type == "free_text":
        fields = extract_lookup_fields(value)
        item = fields.get("item") or value
        rest = fields.get("restaurant") or restaurant
        size = fields.get("size")
        item = f"{size} {item}".strip() if size else item

    # Tier 2 — branded + Nutritionix
    rkey = f"restaurant:{_norm(rest or '')}|{_norm(item)}"
    cached = get_cached(rkey)
    if cached:
        return _result(cached, cached.get("tier", 2), cached.get("source", "open_food_facts_branded"), user_id)
    for fn in (off_branded_search, nutritionix_lookup):
        try:
            hit = fn(item if fn is off_branded_search else (f"{rest} {item}".strip() if rest else item))
        except Exception:
            hit = None
        if hit:
            set_cached(rkey, hit["source"], hit, CACHE_TTL_RESTAURANT)
            return _result(hit, 2, hit["source"], user_id)

    # Tier 3 — web search
    query = f"{rest} {item}".strip() if rest else item
    wkey = "web:" + hashlib.sha256(_norm(query).encode()).hexdigest()
    cached = get_cached(wkey)
    if cached:
        return _result(cached, 3, "web_search", user_id)
    try:
        hit = web_nutrition_lookup(query)
    except Exception:
        hit = None
    if hit:
        set_cached(wkey, "web_search", hit, CACHE_TTL_WEB)
        return _result(hit, 3, "web_search", user_id)

    # Tier 4 — AI estimate (never cached)
    try:
        est = ai_estimate(query)
    except Exception:
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
```

- [ ] **Step 4: Run to confirm pass** (6 tests).

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/food_lookup.py hearty-api/tests/test_food_lookup_unit.py
git commit -m "feat(food): tiered lookup orchestrator (cache + fall-through + allergens)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Schemas + endpoints (TDD)

**Files:** Modify `hearty-api/app/models/schemas.py` + `hearty-api/app/main.py`; Create `hearty-api/app/routers/food.py`; Test `hearty-api/tests/test_food_endpoint_unit.py`

- [ ] **Step 1: Add schemas** (append to `schemas.py`)

```python
# ─── Food Intelligence ───────────────────────────────────────────────────────

class FoodLookupRequest(BaseModel):
    type: Literal["barcode", "name", "free_text"]
    value: str
    restaurant: Optional[str] = None

class FoodLookupResponse(BaseModel):
    item_name: str
    nutrition: Optional[Dict] = None
    tier_used: int
    source: Optional[str] = None
    confidence: Optional[float] = None
    allergen_warnings: List[str] = Field(default_factory=list)
    message: Optional[str] = None

class FoodCacheResponse(BaseModel):
    hit: bool
    nutrition: Optional[Dict] = None
```

- [ ] **Step 2: Write the failing tests** (`tests/test_food_endpoint_unit.py`)

```python
from fastapi.testclient import TestClient
from app.main import app
from app.auth import get_current_user
from app.routers import food as fd


def test_lookup_endpoint(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    monkeypatch.setattr(fd.food_lookup, "lookup_food",
        lambda type, value, restaurant, user_id: {
            "item_name": "Oat Milk", "nutrition": {"calories": 120}, "tier_used": 1,
            "source": "open_food_facts", "confidence": None,
            "allergen_warnings": [], "message": None})
    client = TestClient(app)
    r = client.post("/api/food/lookup", json={"type": "barcode", "value": "123"})
    assert r.status_code == 200
    body = r.json()
    assert body["tier_used"] == 1 and body["nutrition"]["calories"] == 120
    app.dependency_overrides.clear()


def test_cache_endpoint_hit(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    monkeypatch.setattr(fd.food_cache, "get_cached", lambda key: {"calories": 100})
    client = TestClient(app)
    r = client.get("/api/food/cache/barcode:123")
    assert r.status_code == 200 and r.json()["hit"] is True
    assert r.json()["nutrition"]["calories"] == 100
    app.dependency_overrides.clear()


def test_cache_endpoint_miss(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    monkeypatch.setattr(fd.food_cache, "get_cached", lambda key: None)
    client = TestClient(app)
    r = client.get("/api/food/cache/barcode:nope")
    assert r.status_code == 200 and r.json()["hit"] is False
    app.dependency_overrides.clear()
```

- [ ] **Step 3: Implement the router** (`app/routers/food.py`)

```python
from fastapi import APIRouter, Depends

from app.auth import get_current_user
from app.models.schemas import (FoodLookupRequest, FoodLookupResponse,
                                 FoodCacheResponse)
from app.services import food_lookup, food_cache

router = APIRouter()


@router.post("/api/food/lookup", status_code=200)
async def lookup(body: FoodLookupRequest,
                 user=Depends(get_current_user)) -> FoodLookupResponse:
    result = food_lookup.lookup_food(body.type, body.value, body.restaurant, user["id"])
    return FoodLookupResponse(**result)


@router.get("/api/food/cache/{key:path}", status_code=200)
async def cache_check(key: str,
                      user=Depends(get_current_user)) -> FoodCacheResponse:
    cached = food_cache.get_cached(key)
    return FoodCacheResponse(hit=cached is not None, nutrition=cached)
```

Register in `app/main.py`: add `food` to the `from app.routers import (...)` line and `app.include_router(food.router)` with the others.

> The cache key contains `:` and `|`, so the path param uses `{key:path}` to accept them. Confirm this resolves before other `/api/food/...` routes (it's the only GET under `/api/food/cache/`).

- [ ] **Step 4: Run** the endpoint tests, then the full suite excluding the live test:
`cd hearty-api && set -a && . ../.env && set +a && .venv/bin/python -m pytest --ignore=tests/test_api.py -q` — all pass.

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/models/schemas.py hearty-api/app/routers/food.py hearty-api/app/main.py hearty-api/tests/test_food_endpoint_unit.py
git commit -m "feat(food): /api/food/lookup + /api/food/cache endpoints

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Device / live verification (after the tasks)

- Barcode of a known product → Tier 1 (Open Food Facts) returns nutrition; second call → cache hit (no outbound HTTP).
- A branded item name → Tier 2 (OFF branded or Nutritionix); free-text "X from {restaurant}" → extraction → Tier 2.
- An obscure item with `BRAVE_SEARCH_API_KEY` set → Tier 3 returns web-sourced nutrition with a `source_url`; without the key → falls to Tier 4.
- A generic description → Tier 4 `ai_estimate` with the estimate caveat message.
- Total nonsense / unknown barcode → Tier 5 honest message, nutrition null.
- A user with a declared allergen that appears in a result → `allergen_warnings` populated.

---

## Self-review

- **Spec coverage:** 5 tiers (T3 OFF-barcode; T4 Nutritionix+OFF-branded; T5 Brave+Claude tool-use; T6 AI estimate; T8 orchestrator incl. Tier 5) · cache with per-tier TTL + key formats (T2/T8) · allergen cross-ref (T7/T8) · free-text extraction (T7/T8) · endpoints `POST /api/food/lookup` + `GET /api/food/cache/{key}` (T9) · migration (T1). USDA Tier-1-secondary and vision→lookup wiring deferred by decision.
- **Placeholders:** every backend task has full code; no Flutter in this pass (pure backend pipeline).
- **Type/name consistency:** `off_barcode/off_branded_search/nutritionix_lookup` (T3/T4) → orchestrator (T8); `web_nutrition_lookup(description, search=, complete=)` (T5) → T8; `ai_estimate/extract_lookup_fields/allergen_warnings` (T6/T7) → T8; `get_cached/set_cached` (T2) → T8; orchestrator returns the exact `FoodLookupResponse` field set (T9). Cache key formats match the spec (`barcode:`, `restaurant:{r}|{item}`, `web:{sha256}`; Tier 4 never cached).
- **Security:** `food_cache` is a shared global table reachable only via the service key (RLS on, no policies). `_user_allergens` is user-scoped. Endpoints derive `user_id` from auth only.
- **Robustness:** every tier call in the orchestrator is wrapped so one source failing falls through (never blocks); Tier 5 always returns. Nutritionix/Brave self-disable cleanly when unconfigured.
- **Risk:** Tier 3's litellm tool-use message/`tool_calls` shape is the main external assumption — T5 pins the contract via injected fakes and notes verifying the installed litellm shape; live behavior is covered in device verification.
