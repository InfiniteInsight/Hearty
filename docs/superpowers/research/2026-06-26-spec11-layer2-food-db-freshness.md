# Spec 11 Layer 2 — Food / Nutrition Data Freshness (Pre-Brainstorm Research)

**Status:** Research / options memo (NOT a spec or design). Input for a future brainstorm.
**Date:** 2026-06-26
**Initiative:** Spec 11 (Knowledge Freshness), **Layer 2 of 3** — keeping food/nutrition DATA current. (Layer 1 = health-knowledge RAG, shipped — see `docs/superpowers/specs/2026-06-25-knowledge-rag-design.md`. Layer 3 = server-side prompt/config — see sibling memo.)
**Parent spec:** `docs/superpowers/specs/2026-05-04-hearty-11-knowledge-freshness.md` §3 (Food Database Freshness).

---

## TL;DR

Hearty already has a working **5-tier on-demand lookup with a TTL'd Supabase cache** (`food_cache`). Open Food Facts and (optionally) Nutritionix are integrated; **USDA FoodData Central is not**, and **there is no scheduled/background sync of any kind**. The parent spec assumes batch syncs (OFF weekly, USDA quarterly), but the system that actually shipped is on-demand-with-cache. The real Layer 2 question is therefore narrower than the spec implied: *do we add bulk/scheduled sources at all, or just make the existing on-demand cache smarter?*

**Recommendation:** Lean on the existing tiered lookup; add a lightweight **gap-tracking + staleness** layer before committing to any bulk-sync infrastructure. Defer USDA/OFF bulk sync until gap data shows it's worth it.

---

## 1. Current state (what exists today, with file refs)

### 1.1 The tiered lookup
`hearty-api/app/services/food_lookup.py` — `lookup_food()` orchestrates a cache-first cascade:

| Step | Source | Module / fn | Cached? | TTL |
|---|---|---|---|---|
| 0 | `food_cache` (Supabase) | `food_cache.get_cached()` | — | read-time expiry |
| 1 | Open Food Facts — barcode | `food_sources.off_barcode()` | yes | `FOOD_CACHE_TTL_BARCODE` (30d) |
| 2a | Open Food Facts — branded search | `food_sources.off_branded_search()` | yes | `FOOD_CACHE_TTL_RESTAURANT` (30d) |
| 2b | Nutritionix (restaurant/branded) | `food_sources.nutritionix_lookup()` | yes | `FOOD_CACHE_TTL_RESTAURANT` (30d) |
| 3 | Claude + Brave web search | `web_nutrition.web_nutrition_lookup()` | yes | `FOOD_CACHE_TTL_WEB` (7d) |
| 4 | Claude LLM estimate | `food_estimate.ai_estimate()` | **no** | — |
| 5 | Honest fallback ("couldn't find it; add later") | `food_lookup` (`_tier5`) | — | — |

Router entry point: `hearty-api/app/routers/food.py` (`POST /api/food/lookup`).

### 1.2 The cache store
`hearty-api/app/services/food_cache.py` + migration `supabase/migrations/20260616000000_food_cache.sql`:
- Supabase table `food_cache`: `lookup_key` (unique), `source`, `nutrition_data` (JSONB), `cached_at`, `ttl_days`. RLS on, no policies (service-key only).
- **Expiry is evaluated at read time** (`food_cache.py:21-22`): if `cached_at + ttl_days <= now()` → treated as a miss. There is no background refresh, no soft-expiry, no revalidation.
- Cache keys: `barcode:{value}`, `restaurant:{rest}|{item}`, `web:{sha256(query)}`.

### 1.3 External sources & env vars
- **Open Food Facts** — public, no key. Both barcode and branded-search endpoints (`food_sources.py`). This is the only always-on structured source.
- **Nutritionix** — `NUTRITIONIX_APP_ID` / `NUTRITIONIX_API_KEY`; gracefully skipped if absent.
- **Brave Search** — `BRAVE_SEARCH_API_KEY`; returns `[]` if absent (feeds Tier 3).
- **Claude** via litellm — `LLM_MODEL` (default `claude-sonnet-4-6`), Tiers 3 & 4.

### 1.4 What is NOT there (verified)
- **No USDA FoodData Central** anywhere (`grep usda|fdc|fooddata` → 0 hits). The parent spec §3.3 assumed quarterly USDA sync; never built.
- **No scheduled/background sync** — no Celery, no pg_cron, no APScheduler, no GitHub-Actions data job. `main.py` startup only registers `llm_health`. (`BackgroundTasks` is used for the photo pipeline only.)
- **No gap-tracking** — Tier 5 returns a user-facing "add later" message but does **not** log the miss anywhere for aggregation/backfill. (Daily check-in has food-confidence resolution in `checkin.py`, but that's per-entry UX, not a data-freshness signal.)
- **No "knowledge last updated" surface** for food data (parent spec §5.1).

### 1.5 The problem this layer addresses
- **Stale cached records**: a 30-day OFF entry can drift from a reformulated product; the cache never revalidates, it just expires-and-refetches on next access.
- **Missing data**: foods that fall through all tiers reach Tier 4 (LLM estimate, uncached) or Tier 5 (nothing) — and we have no idea which foods these are or how often.
- **Source authority**: OFF is crowd-sourced; USDA Foundation/SR-Legacy are authoritative for whole foods. No authoritative baseline today.

---

## 2. Options

> The parent spec framed Layer 2 as "scheduled syncs." Given what actually shipped (on-demand + cache, no scheduler), the options below range from *no new infra* to *full batch sync*.

### Option 1 — Smarten the existing on-demand cache (no new sources)
**How:** Add gap-tracking (log every Tier-4/Tier-5 miss with normalized query + count), surface "top missing foods" in `/admin`, and add a freshness signal ("food data last refreshed" derived from `food_cache.cached_at`). Optionally add per-source TTL tuning and a manual "refresh this key" admin action.
**Effort:** S (1 small table + a few admin endpoints/panel; no scheduler).
**Cost:** ~$0.
**Tradeoffs:** + Directly measures whether a bulk source is even needed; reuses the working cascade. − Doesn't itself add coverage or authority; staleness still reactive (expire-on-read).

### Option 2 — Add USDA FoodData Central as an authoritative tier (on-demand)
**How:** New `food_sources` fn calling the FDC API (`api.nal.usda.gov/fdc`, free key) inserted ahead of/alongside OFF for whole-food/generic queries; cache like the others. No bulk import — query-time only.
**Effort:** M (one source module + tier wiring + tests + key provisioning).
**Cost:** Free API; rate-limited (1000/hr default).
**Tradeoffs:** + Authoritative nutrient profiles for generic foods; fits existing cascade with no new infra. − Another upstream dependency/key; FDC's branded-food coverage is weaker than OFF/Nutritionix for packaged items.

### Option 3 — Scheduled bulk sync (OFF weekly and/or USDA quarterly) into a local reference table
**How:** Background job downloads OFF delta/dump and/or USDA quarterly export, upserts a local `food_reference` table; lookup checks it before hitting live APIs. This is the parent spec's original §3.1/§3.3 design.
**Effort:** L (new job runner — Supabase Edge Fn + pg_cron, or Celery/Render worker — plus dump parsing, chunking, a large table, migrations, ops).
**Cost:** Storage for millions of rows; compute for parsing; ongoing operational burden. OFF full dump is multi-GB.
**Tradeoffs:** + Offline-fast lookups, full control, true "data freshness" cadence. − Heaviest option by far; large data we mostly won't query; the spec itself flags Edge-Function execution limits for big dumps. Likely premature without gap data.

### Option 4 — Targeted/triggered backfill (gap-driven, hybrid)
**How:** Build Option 1's gap log first; then a small scheduled (or manual) job re-runs lookups for the *most-requested missing foods only*, promoting good results into cache. Optionally pull just those items from USDA/OFF.
**Effort:** M (Option 1 + a small worker over a bounded queue).
**Cost:** Low (bounded to actual demand).
**Tradeoffs:** + Spends effort only where users actually hit gaps; natural growth path from Option 1. − Needs *some* scheduler (smallest possible); benefit depends on gap volume being meaningful.

| Option | New infra | Effort | Cost | Adds coverage | Adds authority | Fixes staleness |
|---|---|---|---|---|---|---|
| 1 Smarter cache | none | S | ~$0 | no | no | partial (measure) |
| 2 USDA on-demand | none | M | free API | some | **yes** | no |
| 3 Bulk sync | job runner + big table | L | high | yes | yes | yes |
| 4 Gap-driven backfill | tiny scheduler | M | low | targeted | optional | targeted |

---

## 3. Recommendation (for the brainstorm to confirm/reject)

**Sequence: Option 1 → Option 2 → revisit 3/4 with data.**
1. **Option 1 (gap-tracking + freshness surface)** is cheap, reuses the working cascade, and is the only way to know whether bulk sync is justified. It also delivers the parent spec's §5.1 "last updated" trust signal.
2. **Option 2 (USDA on-demand)** adds the missing *authoritative* tier without new infrastructure — the single highest-value coverage/quality win for the effort.
3. **Defer Option 3.** The shipped architecture is on-demand-with-cache; a multi-GB bulk pipeline is a large, speculative bet. Only pursue it (or the lighter Option 4) if gap data shows real, recurring misses that live APIs can't serve.

This keeps Layer 2 proportional to demonstrated need rather than building the spec's full batch-sync vision speculatively.

---

## 4. Open questions for the brainstorm

1. **Is freshness actually a felt problem yet?** No gap data exists — do we instrument first (Option 1) before deciding anything?
2. **Authority vs coverage:** is USDA's whole-food accuracy worth a 5th upstream dependency, or is OFF "good enough" for Hearty's symptom-correlation use case (where exact macros matter less than *what was eaten*)?
3. **Job runner choice** (if any sync is built): Supabase Edge Fn + pg_cron vs Celery/Render worker vs GitHub Actions — the spec leans pg_cron but flags execution limits for large dumps.
4. **Cache revalidation policy:** keep expire-on-read, or add soft-expiry/background refresh for high-traffic keys?
5. **Restaurant menus** (spec §3.4): out of scope for v1 of Layer 2, or part of gap-tracking?
6. **Tier-4 (LLM estimate) caching:** currently uncached — should estimates be cached (with provenance) and counted as "missing data" gaps?
7. **Trust surface:** where does "food database last updated" live — Settings (parent spec §5.1), `/admin`, or both?
