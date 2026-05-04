# Hearty — Spec 07: Food Intelligence

**Version:** 1.0
**Date:** 2026-05-04
**Status:** Active
**Phase:** 4

---

## 1. Overview

The Food Intelligence pipeline accepts a food identifier — a barcode string, a product name, a restaurant item, or a free-text description — and returns structured nutritional data. It works through five tiers in order, stopping at the first successful result. If all tiers fail, the item is logged anyway with a clear note that data is unavailable.

The pipeline is called by:

- The AI Vision worker (Spec 06) after food plate or food label processing
- The API directly when a user submits a barcode or free-text meal description
- The MCP Server when Claude extracts food items from a voice or text log

**Core constraint:** the pipeline must never block a log entry. Every tier that fails simply falls through to the next; Tier 5 always succeeds.

**Calorie data principle:** Hearty does not estimate calories from photos. Calorie data is only included when sourced from a barcode lookup or nutrition label scan. This avoids presenting unreliable estimates as meaningful data. Food plate photos produce food identification only — what foods are present and an approximate portion description. No calorie numbers are generated from photo analysis.

---

## 2. The Tiered Pipeline

Tiers are attempted in order. On a cache hit (§3), the cached result is returned before Tier 1 is attempted.

| Tier | Name | Input | Source |
|---|---|---|---|
| 1 | Barcode lookup | Barcode string | Open Food Facts, USDA FoodData Central |
| 2 | Restaurant database | Restaurant + item name | Open Food Facts branded; Nutritionix (optional, user-configured) |
| 3 | Claude web search | Food description string | Claude with web_search tool (Brave Search API) |
| 4 | AI estimation | Food description string | Claude API (claude-sonnet-4-6) |
| 5 | Honest fallback | Any | None — log entry created with null nutrition data |

---

### Tier 1 — Barcode Lookup

**Input:** barcode string (EAN-13, UPC-A, or compatible format)

**Sources (tried in order):**

1. **Open Food Facts** (`https://world.openfoodfacts.org/api/v2/product/{barcode}.json`) — free, no API key, global product database
2. **USDA FoodData Central** (`https://api.nal.usda.gov/fdc/v1/foods/search?query={barcode}`) — free, US-centric, strong branded product coverage

**Return on success:**

```json
{
  "product_name": "string",
  "brand": "string",
  "serving_size": "string",
  "calories": integer,
  "total_fat_g": number,
  "saturated_fat_g": number,
  "trans_fat_g": number,
  "cholesterol_mg": number,
  "sodium_mg": number,
  "total_carbs_g": number,
  "dietary_fiber_g": number,
  "sugars_g": number,
  "protein_g": number,
  "ingredients": ["string"],
  "allergens": ["string"],
  "source": "open_food_facts" | "usda_fdc",
  "tier": 1
}
```

**Cache:** results cached in `food_cache` for 30 days. Cache key: `barcode:{barcode_value}`.

---

### Tier 2 — Restaurant Database

**Input:** restaurant name + item name (extracted from free text via §5, or supplied directly)

**Sources (tried in order):**

1. **Open Food Facts branded products** — free, no API key required; global branded product database; primary Tier 2 source
2. **Nutritionix Track API** — 1M+ branded and restaurant items; better coverage for US restaurant chains; only attempted if the user has configured their own Nutritionix API key in Settings → Food Data Sources (key stored in user preferences and passed as a request header or retrieved server-side from user config)

> **Note:** Nutritionix provides better restaurant menu coverage but requires a free account and API key from nutritionix.com. Users can add their key in Settings → Food Data Sources. If no key is configured, Tier 2 uses Open Food Facts only and falls through to Tier 3 if not found.

**Matching:** fuzzy match on item name (Levenshtein distance or Nutritionix's built-in NLP endpoint for Nutritionix lookups). Accept matches above 0.75 similarity threshold.

**Return on success:**

```json
{
  "item_name": "string",
  "restaurant": "string",
  "serving_size": "string",
  "calories": integer,
  "total_fat_g": number,
  "total_carbs_g": number,
  "protein_g": number,
  "sodium_mg": number,
  "source": "open_food_facts_branded" | "nutritionix",
  "tier": 2
}
```

**Cache:** results cached 30 days. Cache key: `restaurant:{normalized_restaurant}|{normalized_item}` (lowercase, punctuation stripped).

---

### Tier 3 — Claude with web_search Tool

**Input:** food description string (e.g. `"Gong Cha wintergreen melon large drink"`)

**Source:** Claude API (claude-sonnet-4-6) with a `web_search` tool backed by the Brave Search API.

- Brave Search API free tier: 2,000 queries/month — sufficient for personal use
- Required env variable: `BRAVE_SEARCH_API_KEY`

**Process:**

1. Claude is invoked with the food description and given access to a `web_search` tool
2. Claude searches for `"{item} nutrition facts"` (and may refine the query if the first results are unhelpful)
3. Claude reads the returned results, reasons about relevance, and extracts structured nutrition data — no brittle HTML parsing required
4. Claude returns structured JSON if nutrition data is found, or signals that no data was found

This is significantly more reliable than script-based scraping because Claude can understand varied page formats, reason about result relevance, and handle ambiguity gracefully.

**Return on success:**

```json
{
  "item_name": "string",
  "calories": integer or null,
  "total_fat_g": number or null,
  "total_carbs_g": number or null,
  "protein_g": number or null,
  "source": "web_search",
  "source_url": "string",
  "tier": 3
}
```

**Cache:** results cached 7 days (web data changes more frequently than barcode data). Cache key: SHA-256 hash of the normalized query string, prefixed `web:{hash}`.

---

### Tier 4 — AI Estimation

**Input:** free-text food description

**Process:** send to Claude API (claude-sonnet-4-6):

```
Estimate the nutritional content for the following food item.
Return JSON only, no prose:
{
  "calories": integer,
  "protein_g": number,
  "total_carbs_g": number,
  "total_fat_g": number,
  "confidence": float between 0 and 1
}
Base your estimate on typical preparation and standard portion sizes for the description given.
If you cannot make a reasonable estimate, set all numeric fields to null and confidence to 0.

Food item: {description}
```

**Return on success:**

```json
{
  "item_name": "string — echoed from input",
  "calories": integer or null,
  "protein_g": number or null,
  "total_carbs_g": number or null,
  "total_fat_g": number or null,
  "confidence": float,
  "source": "ai_estimate",
  "tier": 4
}
```

**Important:** `source: "ai_estimate"` is always surfaced in the UI so the user knows the data is estimated, not measured. Results from this tier are never cached — estimates are always generated fresh.

---

### Tier 5 — Honest Fallback

Reached only when all preceding tiers fail or return no usable data.

**Action:**

- Log the food item with `nutritional_data: null`, `lookup_attempted: true`, `tier_reached: 5`
- Return a human-readable message alongside the log confirmation:

```
"I couldn't find nutritional data for [item]. I've logged that you had it — you can add details later if you find them."
```

**The log entry is always created.** Tier 5 is never an error state — it is a successful log with a noted data gap.

---

## 3. Caching Strategy

All cache interactions use the `food_cache` table (see Spec 01 for schema).

| Field | Description |
|---|---|
| `lookup_key` | Tier-prefixed string (see key formats below) |
| `source` | `open_food_facts`, `usda_fdc`, `nutritionix`, `web_search` |
| `nutrition_data` | JSONB — full tier response |
| `cached_at` | Timestamp of cache write |
| `ttl_days` | 30 for Tiers 1–2; 7 for Tier 3 |

**Cache key formats:**

| Tier | Key Format |
|---|---|
| 1 | `barcode:{barcode_value}` |
| 2 | `restaurant:{normalized_restaurant}\|{normalized_item}` |
| 3 | `web:{sha256(normalized_query)}` |
| 4 | Not cached |

**Cache lookup occurs before Tier 1.** On cache hit: return cached result immediately, bypass all tiers. On cache miss: run tiers, write result to cache if Tier 1–3 succeeds.

Cache expiry is checked at read time: `cached_at + ttl_days * interval '1 day' > now()`. Expired entries are treated as cache misses and overwritten on the next successful lookup.

---

## 4. Allergen Cross-Reference

After any successful lookup (Tiers 1–4), the pipeline cross-references returned allergen data against the user's health profile (see Spec 08 for health profile schema).

**Process:**

1. Collect allergens from the lookup result (`allergens` array or ingredients text)
2. Load user's declared allergens from `health_profile.allergens`
3. For each user allergen, check for exact or substring match in the result's allergens and ingredients
4. If match found, append to `allergen_warnings` in the response

**Response field:**

```json
"allergen_warnings": [
  "contains: wheat",
  "may contain: tree nuts"
]
```

This field is **informational only**. Allergen warnings never prevent logging. The UI displays warnings as a non-blocking banner.

---

## 5. Free-Text Food Name Extraction

When a user's input is a natural language sentence rather than a structured lookup request, Claude is used to extract the structured fields before the pipeline runs.

**Extraction prompt:**

```
Extract structured food lookup fields from this user input.
Return JSON only:
{
  "restaurant": "string or null",
  "item": "string",
  "size": "string or null",
  "modifiers": ["string"] or null
}
If no restaurant is mentioned, set restaurant to null.

User input: {raw_text}
```

**Example:**

Input: `"I had a wintergreen melon large drink from Gong Cha"`

Extracted:
```json
{
  "restaurant": "Gong Cha",
  "item": "wintergreen melon drink",
  "size": "large",
  "modifiers": null
}
```

The extracted fields are then passed to Tier 2 (`restaurant` + `item`). If Tier 2 fails, the concatenated string `"large wintergreen melon drink from Gong Cha"` is passed to Tier 3, then Tier 4.

---

## 6. API Endpoints

Authentication on all endpoints follows the JWT Bearer scheme defined in Spec 03.

### `POST /api/food/lookup`

Look up a food item by name or barcode. Runs the full tiered pipeline.

**Request body:**

```json
{
  "type": "barcode" | "name" | "free_text",
  "value": "string",
  "restaurant": "string or null",
  "user_id": "uuid"
}
```

**Response:**

```json
{
  "item_name": "string",
  "nutrition": { ... },
  "tier_used": integer,
  "source": "string",
  "confidence": float or null,
  "allergen_warnings": ["string"],
  "message": "string or null"
}
```

The `message` field is populated only for Tier 4 (to surface the `ai_estimate` caveat) and Tier 5 (the honest fallback message).

### `GET /api/food/cache/{key}`

Check whether a lookup key exists in the cache and has not expired.

**Response:**

```json
{
  "hit": true | false,
  "cached_at": "ISO timestamp or null",
  "ttl_days": integer or null,
  "nutrition": { ... } | null
}
```

---

*For photo-based food identification that feeds into this pipeline, see Spec 06: AI Vision.*
*For the health profile allergen schema, see Spec 08: Health Profile.*
*For the `food_cache` table schema and RLS, see Spec 01: Database.*
