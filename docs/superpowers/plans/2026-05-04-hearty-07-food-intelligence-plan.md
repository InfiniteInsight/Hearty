# Hearty — Food Intelligence (Spec 07) — Living Plan

**Spec:** [`hearty-07-food-intelligence.md`](../specs/2026-05-04-hearty-07-food-intelligence.md)  
**Roadmap Phase:** Phase 4 — Food Intelligence  
**Plan Status:** 🔴 Not Started  
**Last Updated:** 2026-05-04  
**Last Verified Against Spec:** 2026-05-04 — re-verify if spec has changed since  
**Open Deviations:** 0

---

## How to Use This Plan

1. Always start with **Phase 0** at the beginning of any new session on this plan
2. Find the first phase/task marked **🔴 Not Started**, mark it **🟡 In Progress**
3. Paste the phase's **Activation Prompt** into a new Claude Code session
4. Follow the steps — Claude will guide you through each one
5. At natural break points, Claude will tell you to run `/compact`; do so, then start a new session with the **Activation Prompt** at the top of the next phase
6. Mark completed phases **🟢 Completed** and log any deviations as a single line at the bottom

**Status key:** 🔴 Not Started · 🟡 In Progress · 🟢 Completed · ⚠️ Blocked · ↩️ Deviated

---

## Phase Summary

| Phase | Name | Status | Depends On | Type |
|---|---|---|---|---|
| 0 | Review & Align | 🔴 Not Started | — | Claude (start of every session) |
| 1 | food_cache Table Migration | 🔴 Not Started | — | Claude |
| 2 | Pipeline Scaffold & Free-Text Extraction | 🔴 Not Started | Phase 1 | Claude |
| 3 | Tier 1 — Barcode Lookup | 🔴 Not Started | Phase 2 | Claude |
| 4 | Tier 2 — Restaurant Database | 🔴 Not Started | Phase 2 | Claude |
| 5 | Tier 3 — Claude web_search Tool | 🔴 Not Started | Phase 2 | Claude |
| 6 | Tier 4 — AI Estimation & Tier 5 — Honest Fallback | 🔴 Not Started | Phase 2 | Claude |
| 7 | Allergen Cross-Reference | 🔴 Not Started | Phases 3–6 | Claude |
| 8 | API Endpoints | 🔴 Not Started | Phases 3–7 | Claude |
| 9 | Integration Test | 🔴 Not Started | Phases 1–8 | Claude |

---

## Phase 0: Review & Align

**Status:** 🔴 Not Started  
**Goal:** Verify the dev environment, confirm all dependency plans are complete, check the spec hasn't drifted from this plan, and identify exactly which phase to start or resume.  
**Run this phase at the start of every session on this plan.**

### Activation Prompt

```
You are running Phase 0 (Review & Align) for the Hearty Food Intelligence pipeline (Spec 07).
This runs at the start of every session — it takes 5 minutes and prevents
working from stale assumptions.

Working directory: /home/evan/projects/food-journal-assistant

Steps:

1. Read both files in full:
   - docs/superpowers/plans/2026-05-04-hearty-07-food-intelligence-plan.md  (this plan)
   - docs/superpowers/specs/2026-05-04-hearty-07-food-intelligence.md

2. Check dependency plan completion — read the Plan Status line from each:
   - docs/superpowers/plans/2026-05-04-hearty-01-database-plan.md
   - docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md
   Both must show Plan Status: 🟢 Completed before Phase 1 can begin.

3. Check the dev environment (run each command):
   - python3 --version   (need >= 3.11)
   - git status
   - ls backend/ 2>/dev/null && echo "FastAPI project exists" || echo "not yet created"
   - supabase --version  (need for Phase 1 migration)

4. For the first upcoming non-zero phase (Phase 1), also verify:
   - Confirm the Supabase project is linked (supabase status or check supabase/config.toml)
   - Confirm the Anthropic Python SDK is installed:
     (run: cd backend && python3 -c "import anthropic; print(anthropic.__version__)" 2>/dev/null)
   - Note: food_cache table is deferred from Spec 01 to this plan per the Spec 01 plan Notes section.
     Verify it does NOT already exist: check supabase/migrations/ for any food_cache migration.
   - Check BRAVE_SEARCH_API_KEY is documented (needed for Phase 5 Tier 3):
     (run: grep -r BRAVE_SEARCH /home/evan/projects/food-journal-assistant/.env 2>/dev/null
     || echo "not yet configured")

5. Spec drift check — the plan was written on 2026-05-04. Scan the spec for any
   changes to: tier definitions, cache key formats, TTL values, API endpoint
   contracts, allergen cross-reference process. If you find anything that conflicts
   with this plan, list it.

6. Report:
   - Dependency plans: which are complete, which are not
   - Environment: what is/isn't installed or configured
   - food_cache migration status: exists already or needs to be created
   - BRAVE_SEARCH_API_KEY: present or needs to be obtained
   - Spec alignment: any drift found, or "clean"
   - Next action: which phase to proceed with (or what to fix/unblock first)

Before running any command, verify it exists with --help or equivalent.
If a command doesn't behave as expected, stop and tell me — don't improvise.

Update the plan: set Phase 0 status to 🟢 Completed and Last Updated to today.
```

**Deviation Log:** _None_

---

## Phase 1: food_cache Table Migration

**Status:** 🔴 Not Started  
**Goal:** Create and deploy the `food_cache` Supabase migration — the table referenced in Spec 01's Notes as deferred to this plan — so the cache layer is available for all pipeline tiers.  
**Depends on:** Spec 01 plan complete  
**Type:** Claude

**Key deliverables:**
- New migration file `supabase/migrations/20260504000003_food_cache.sql` (or next available timestamp)
- `food_cache` table with columns matching spec Section 3: `lookup_key` (primary key), `source`, `nutrition_data` (JSONB), `cached_at`, `ttl_days`
- RLS enabled on `food_cache`; policy: authenticated users can SELECT rows where their lookup is relevant; service role handles INSERT/UPDATE
- Index on `lookup_key` for fast cache reads
- Migration deployed via `supabase db push` and verified (table appears in Dashboard)
- Committed: `git commit -m "feat: add food_cache table migration"`

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 2: Pipeline Scaffold & Free-Text Extraction

**Status:** 🔴 Not Started  
**Goal:** Implement the pipeline orchestrator that runs tiers in order (with cache check first), the cache read/write helpers, and the free-text food name extractor that structures natural language into `restaurant`/`item`/`size`/`modifiers` before dispatching to tiers.  
**Depends on:** Phase 1  
**Type:** Claude

**Key deliverables:**
- `food_intelligence/pipeline.py` — orchestrator function `lookup_food(type, value, restaurant, user_id)` that: checks `food_cache` first, runs Tier 1–5 in order, writes successful Tier 1–3 results to cache, returns a consistent response envelope with `tier_used`, `source`, `confidence`, `allergen_warnings`, `message`
- `food_intelligence/cache.py` — `cache_get(key)` (checks `cached_at + ttl_days > now()`) and `cache_set(key, source, nutrition_data, ttl_days)`
- `food_intelligence/extractor.py` — free-text extraction: sends raw input to Claude with exact prompt from spec Section 5; returns `{"restaurant", "item", "size", "modifiers"}`; used when `type == "free_text"` to route to Tier 2 first, then Tier 3 with concatenated string
- Cache key format helpers matching all spec-defined formats (barcode, restaurant, web hash)
- The pipeline must never raise an unhandled exception — every tier failure is caught and falls through; Tier 5 always returns a valid response

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 3: Tier 1 — Barcode Lookup

**Status:** 🔴 Not Started  
**Goal:** Implement Tier 1: try Open Food Facts then USDA FoodData Central for a given barcode string, normalize the response to the spec's return schema, and write to cache on success.  
**Depends on:** Phase 2  
**Type:** Claude

**Key deliverables:**
- `food_intelligence/tiers/tier1_barcode.py` — calls Open Food Facts API first (`https://world.openfoodfacts.org/api/v2/product/{barcode}.json`; no API key required); falls through to USDA FoodData Central (`https://api.nal.usda.gov/fdc/v1/foods/search?query={barcode}`) if not found
- Response normalized to the Tier 1 return schema from spec: `product_name`, `brand`, `serving_size`, calories, macros, `ingredients`, `allergens`, `source`, `tier: 1`
- Cache write on success: key `barcode:{barcode_value}`, TTL 30 days
- Graceful handling: barcode not found in either source → return None (pipeline falls through to Tier 2)
- Unit test: known EAN-13 barcode (e.g., a widely-available product) returns product name and calories

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 4: Tier 2 — Restaurant Database

**Status:** 🔴 Not Started  
**Goal:** Implement Tier 2: fuzzy-match the restaurant + item against Open Food Facts branded products (primary, free) and optionally Nutritionix (if user has configured an API key), normalize to the Tier 2 schema, and cache on success.  
**Depends on:** Phase 2  
**Type:** Claude

**Key deliverables:**
- `food_intelligence/tiers/tier2_restaurant.py` — tries Open Food Facts branded products search first (no API key); falls through to Nutritionix only if `user_preferences.nutritionix_api_key` is configured for the user
- Fuzzy matching: Levenshtein distance (or `python-Levenshtein` / `rapidfuzz` library); accept matches above 0.75 similarity threshold; for Nutritionix, use the NLP endpoint
- Response normalized to Tier 2 schema: `item_name`, `restaurant`, `serving_size`, calories, `total_fat_g`, `total_carbs_g`, `protein_g`, `sodium_mg`, `source`, `tier: 2`
- Cache write on success: key `restaurant:{normalized_restaurant}|{normalized_item}`, TTL 30 days
- No match above threshold → return None (pipeline falls through to Tier 3)
- Nutritionix API key retrieval: read from user's preferences row (server-side); never exposed to client

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 5: Tier 3 — Claude web_search Tool

**Status:** 🔴 Not Started  
**Goal:** Implement Tier 3: invoke Claude (`claude-sonnet-4-6`) with the `web_search` tool backed by the Brave Search API to find nutrition data for the food description, extract structured data from search results, and cache on success.  
**Depends on:** Phase 2; `BRAVE_SEARCH_API_KEY` configured  
**Type:** Claude

**Key deliverables:**
- `food_intelligence/tiers/tier3_web_search.py` — calls Claude API with `web_search` tool; Brave Search API key read from `BRAVE_SEARCH_API_KEY` env variable
- Claude searches for `"{item} nutrition facts"`, reasons about result relevance, extracts structured data; no brittle HTML parsing required
- Response normalized to Tier 3 schema: `item_name`, calories, macros, `source: "web_search"`, `source_url`, `tier: 3`
- Cache write on success: key `web:{sha256(normalized_query)}`, TTL 7 days (shorter than Tiers 1–2 per spec)
- Claude signals no data found → return None (pipeline falls through to Tier 4)
- Rate awareness: Brave Search free tier = 2,000 queries/month; log each Tier 3 call to `api_cost_log` if that table exists

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 6: Tier 4 — AI Estimation & Tier 5 — Honest Fallback

**Status:** 🔴 Not Started  
**Goal:** Implement Tier 4 (Claude AI estimation with `confidence` field, never cached) and Tier 5 (honest fallback: log the item with null nutrition data and return the spec-defined human-readable message).  
**Depends on:** Phase 2  
**Type:** Claude

**Key deliverables:**
- `food_intelligence/tiers/tier4_ai_estimate.py` — calls Claude with exact estimation prompt from spec Section 4; returns `calories`, `protein_g`, `total_carbs_g`, `total_fat_g`, `confidence`; sets all numeric fields null and `confidence: 0` if estimate is unreasonable
- `source: "ai_estimate"` always surfaced in the response envelope so the UI can display the estimation caveat
- Tier 4 results are **never cached** (spec requirement); each call generates a fresh estimate
- `food_intelligence/tiers/tier5_fallback.py` — returns a valid response with `nutritional_data: null`, `lookup_attempted: true`, `tier_reached: 5`, and the exact human-readable message from spec: "I couldn't find nutritional data for [item]. I've logged that you had it — you can add details later if you find them."
- Tier 5 is never an error — pipeline orchestrator always completes successfully

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 7: Allergen Cross-Reference

**Status:** 🔴 Not Started  
**Goal:** Implement the post-lookup allergen cross-reference step: after any successful Tier 1–4 result, compare returned allergens and ingredients against the user's `health_profile.allergens` and append `allergen_warnings` to the response.  
**Depends on:** Phases 3–6  
**Type:** Claude

**Key deliverables:**
- `food_intelligence/allergens.py` — `cross_reference(nutrition_result, user_id)`: loads `health_profile.allergens` for the user; checks for exact and substring matches in `result.allergens` and `result.ingredients`; returns populated `allergen_warnings` array
- Cross-reference applied inside the pipeline orchestrator after any successful tier result (Tiers 1–4 only; Tier 5 has null nutrition data so no cross-reference needed)
- Allergen warnings are **informational only** — never prevent a log entry; UI displays as a non-blocking banner
- `allergen_warnings` field included in every pipeline response envelope (empty list `[]` when no matches)

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 8: API Endpoints

**Status:** 🔴 Not Started  
**Goal:** Expose the two API endpoints defined in the spec (`POST /api/food/lookup` and `GET /api/food/cache/{key}`) with the exact request/response contracts from spec Section 6, wired to the pipeline and cache layer.  
**Depends on:** Phases 3–7  
**Type:** Claude

**Key deliverables:**
- `POST /api/food/lookup` — accepts `{"type": "barcode"|"name"|"free_text", "value": string, "restaurant": string|null, "user_id": uuid}`; runs full pipeline; returns spec response envelope: `item_name`, `nutrition`, `tier_used`, `source`, `confidence`, `allergen_warnings`, `message`
- `GET /api/food/cache/{key}` — checks cache for the given key; returns `{"hit": bool, "cached_at": iso_timestamp|null, "ttl_days": int|null, "nutrition": {...}|null}`
- Both endpoints protected by JWT Bearer auth (from Spec 03); `user_id` extracted from JWT, not from request body (request body `user_id` is for internal routing only and must match the JWT claim)
- Input validation: `type` must be one of the three allowed values; `value` must be non-empty
- OpenAPI schema in FastAPI auto-docs reflects the exact spec contracts

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 9: Integration Test

**Status:** 🔴 Not Started  
**Goal:** Run integration tests against a live environment for all five tiers, cache behavior, allergen cross-reference, and both API endpoints.  
**Depends on:** Phases 1–8  
**Type:** Claude

**Key deliverables:**
- Tier 1: submit a known EAN-13 barcode → confirm product name and calories returned with `tier_used: 1`; re-submit → confirm `GET /api/food/cache/{key}` returns `hit: true`
- Tier 2: submit a known restaurant + item → confirm match returned with `tier_used: 2` (requires Open Food Facts branded match or Nutritionix key)
- Tier 3: submit a specialty drink description (e.g., "Gong Cha wintergreen melon large drink") → confirm `tier_used: 3` and `source_url` populated (requires `BRAVE_SEARCH_API_KEY`)
- Tier 4: submit an obscure food with no web presence → confirm `tier_used: 4`, `source: "ai_estimate"`, `confidence` between 0 and 1
- Tier 5: mock all tiers to fail → confirm `tier_used: 5`, `nutritional_data: null`, correct fallback message returned
- Allergen cross-reference: submit a food known to contain a user's declared allergen → confirm `allergen_warnings` is non-empty
- Cache TTL: write a cache entry with `ttl_days: 0` → confirm cache miss on next read (expired)
- `POST /api/food/lookup` with invalid `type` → confirm 422 validation error

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Deviation Log

_Format: `[date] — Phase X, Task Y — changed X because Y`_

---

## Notes

- **`food_cache` table ownership:** Per the Spec 01 plan Notes section, this table was intentionally deferred from Spec 01 to this plan. Phase 1 of this plan owns the migration.
- **`BRAVE_SEARCH_API_KEY`:** Required for Phase 5 (Tier 3). Obtain a free-tier key at [brave.com/search/api](https://brave.com/search/api). Free tier allows 2,000 queries/month — sufficient for personal use. Add to the FastAPI project's `.env`.
- **Nutritionix API key:** Optional. Users can configure their own key in Settings → Food Data Sources. If not configured, Tier 2 uses Open Food Facts only. Nutritionix key is stored in `user_preferences` server-side; never returned to the client.
- **Tier 4 never cached:** This is a spec requirement. AI estimates are always generated fresh because the model may improve over time and estimates for the same food description may legitimately differ across calls.
- **Calorie data principle:** Food plate photos (Spec 06) produce food identification only — no calorie data. Calorie data only enters the system through Tiers 1–3 (sourced from structured databases or verified web data) or Tier 4 (AI estimate, clearly labeled). This is enforced in the pipeline: food plate processor outputs feed into the pipeline with `type: "name"`, which routes to Tier 2+ and skips barcode lookup.
- **Spec 08 dependency for health profile schema:** Allergen cross-reference (Phase 7) reads `health_profile.allergens`. If Spec 08 is not yet complete, use the health profile data already stored in the Spec 01 `health_profile` table.
