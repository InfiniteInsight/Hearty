# Spec 11 Layer 3 — Server-Side Prompt / Config Updates (Pre-Brainstorm Research)

**Status:** Research / options memo (NOT a spec or design). Input for a future brainstorm.
**Date:** 2026-06-26
**Initiative:** Spec 11 (Knowledge Freshness), **Layer 3 of 3** — change AI prompts/behavior without shipping an app build. (Layer 1 = RAG, shipped. Layer 2 = food-DB freshness — sibling memo.)
**Parent spec:** `docs/superpowers/specs/2026-05-04-hearty-11-knowledge-freshness.md` §4 (App & Prompt Updates).

---

## TL;DR

**Model selection is already server-side** (env var `LLM_MODEL`) — the parent spec's §4.3 goal is effectively met. **Everything else is not:** every AI prompt is a hardcoded Python string literal, there is **no `feature_flags` table** and **no remote-config** mechanism. There *is* a solid foundation to build on: an admin-gated singleton `app_settings` table with GET/PUT endpoints, admin auth (`get_current_admin`), and an admin web page already wiring similar CRUD (licenses, knowledge base). The Layer 3 question is which slice of "live config" is worth the operational risk of editing prompts in prod.

**Recommendation:** Start with a small **DB-backed prompt store + admin editor for a curated allowlist of prompts**, with versioning/rollback baked in from day one. Treat broad feature-flagging as a separate, later concern.

---

## 1. Current state (with file refs)

### 1.1 Model selection — ALREADY server-side ✅
Every LLM call reads the model from env, matching parent spec §4.3:
```python
model = os.environ.get("LLM_MODEL", "claude-sonnet-4-6")
```
- `ai_extraction.py` (extraction/summary calls), `trends_conversation.py`, `food_category_service.py`, `chat.py` (`_MODEL`), plus food estimate/plate/web-nutrition.
- Optional `LLM_BASE_URL` allows redirecting litellm to a custom/local backend (`ai_extraction.py`, `trends_conversation.py`).
- Admin LLM smoke test exists: `POST /api/admin/health/llm-test` (`admin.py`).
- **Gap vs spec:** no `CLAUDE_MODEL_FALLBACK` rollback var; model is global (one value for all users).

### 1.2 Prompts — hardcoded Python literals ❌
All system/extraction prompts live in source, not config:
- `ai_extraction.py` — `MEAL_EXTRACTION_PROMPT`, `SYMPTOM_EXTRACTION_PROMPT`, `SUMMARY_PROMPT` (with `{}` placeholders; `health_context`/`research_context` appended at runtime).
- `trends_conversation.py` — `build_system_prompt(signals, health_context="", research_context="")` assembles a hardcoded block.
- `chat.py` — `_MEAL_CLARIFICATION_RULES_BASE`, `_ALWAYS_WARM`, `_ALWAYS_CONCISE`, etc., assembled by `_make_system_prompt()` keyed on `conversation_style`.
- `food_category_service.py` — `_CLASSIFY_PROMPT`; `food_plate.py` — vision prompt.

There is a *partial* dynamic-behavior precedent: `conversation_style` (`warm`/`concise`) is a stored user preference that selects between hardcoded prompt fragments at runtime. So "behavior varies by stored config" already exists in miniature — but the prompt *text* is still in code.

### 1.3 The foundation that already exists ✅
- **`app_settings` singleton** (migration `20260623120000_app_settings.sql`): single row (`id=1` CHECK), fields `provisioning_mode`, `trial_days`, `updated_at`, `updated_by`. Endpoints `GET /api/admin/settings`, `PUT /api/admin/settings` (`admin.py`), both `Depends(get_current_admin)`.
- **Admin auth:** `get_current_admin` requires Supabase `app_metadata.role == "admin"` (`app/auth.py`).
- **Admin web page** (`hearty-web/src/pages/Admin.tsx`, ~360 lines) already does admin CRUD over licenses, settings, health, and the RAG knowledge base — the editor pattern for a prompt store would slot right in (hooks `useAppSettings`/`useUpdateAppSettings`, `useKnowledge`/`useKnowledgeActions`).
- **Knowledge-base CRUD** (Layer 1) is a working template: admin-gated `POST/GET/DELETE/PATCH /api/admin/knowledge`.

### 1.4 What does NOT exist (verified)
- No `feature_flags` table (parent spec §4.4 — `grep feature_flag` → 0 hits), no `/config/features` endpoint.
- No `prompts` / `ai_config` / `model_config` table.
- No prompt versioning/history, no remote-config client/cache anywhere.

---

## 2. Options

### Option A — DB-backed prompt store + admin editor (curated allowlist)
**How:** New table (e.g. `prompt_config`: `key`, `content`, `active_version`, `updated_at/by`). Refactor the chosen prompts to load text from DB at startup (and on a refresh interval / explicit reload), falling back to the in-code default if the row is missing/empty. Admin panel on `/admin` to view/edit each allowlisted prompt. Mirrors the existing knowledge-base CRUD pattern exactly.
**Effort:** M (table + endpoints + a `prompt_store` service + per-prompt refactor + admin panel + tests).
**Cost:** ~$0.
**Tradeoffs:** + Directly delivers the spec's §4.1/§4.2 goal; reuses proven admin/auth/CRUD scaffolding; in-code fallback means a bad/empty row can't fully break the app. − Editing prompts live is genuinely risky (a bad edit degrades AI for all users instantly) — *must* pair with versioning + guardrails (Option D).

### Option B — Generic remote-config / key-value store
**How:** Extend `app_settings` (or a `app_config` KV table) into a general typed config store the backend reads at startup; clients fetch a `/config` snapshot. Prompts become just one kind of config value.
**Effort:** M–L (schema + typing + cache/refresh + client integration in Flutter & web).
**Tradeoffs:** + One mechanism for everything (prompts, thresholds, model, flags). − Over-general for the immediate need; typed validation of heterogeneous values is fiddly; risks becoming a dumping ground. The singleton `app_settings` already half-exists but is purpose-built, not generic.

### Option C — Feature flags table (parent spec §4.4)
**How:** Build the spec's `feature_flags` table (`key`, `enabled`, `enabled_for_users uuid[]`, …) + a `/config/features` endpoint cached per session; gate new analysis features.
**Effort:** M (table + endpoint + client read + per-feature gating).
**Tradeoffs:** + Safe rollout / A-B / per-user enabling; clean separation from prompts. − Solves a *different* problem than "edit prompts live"; valuable but arguably not the Layer 3 headline. Could be a fast follow.

### Option D — Versioning / rollback + guardrails (cross-cutting, pairs with A/B)
**How:** Whatever store ships, keep prompt *history* (append-only versions, `active_version` pointer) so any change is one-click revertible; add edit-time guardrails: required-placeholder validation (e.g. `{description}` must remain), length caps, a "test against sample input" action (reuse the `llm-test` pattern), and an audit trail (`updated_by`, already present on `app_settings`).
**Effort:** S–M on top of A.
**Tradeoffs:** + Turns the scary "live prompt edit" into a safe, reversible operation — the difference between viable and reckless. − Adds schema/UI surface; minor.

| Option | New infra | Effort | Delivers spec goal | Risk without guardrails |
|---|---|---|---|---|
| A Prompt store + editor | 1 table + panel | M | §4.1/§4.2 ✅ | high → mitigate w/ D |
| B Generic remote-config | KV + client | M–L | §4.1/§4.2/§4.4 | high |
| C Feature flags | 1 table + endpoint | M | §4.4 | low |
| D Versioning/guardrails | additive | S–M | safety | — (it *is* the mitigation) |

---

## 3. Recommendation (for the brainstorm to confirm/reject)

**Option A + D, scoped to a small allowlist of prompts; Option C as a separate fast-follow; skip Option B.**
- **A + D together:** a DB-backed prompt store with versioning, in-code fallback, and edit-time guardrails delivers the parent spec's core Layer 3 goal (change AI behavior without an app build) while making live edits *reversible and validated* — non-negotiable given a bad prompt degrades every user instantly. The admin/auth/CRUD scaffolding already exists, so this is mostly a focused refactor, not new infrastructure.
- **Start with the highest-value, lowest-blast-radius prompts** (e.g. the trends-conversation system prompt and summary prompt) rather than all of them. Extraction prompts are higher-risk (they shape structured output parsing) — add later behind guardrails.
- **Option C (feature flags)** is worth doing but is a distinct concern; treat it as a follow-up, not part of the first Layer 3 cut.
- **Skip Option B** — `app_settings` is already a clean purpose-built singleton; a generic KV store is over-engineering for the need.
- **Model selection is done** — just add the `CLAUDE_MODEL_FALLBACK` rollback var to close §4.3 fully.

---

## 4. Open questions for the brainstorm

1. **Which prompts go in the allowlist first?** Conversation/summary (lower risk) vs extraction (shapes parsing, higher risk).
2. **Reload cadence:** startup-only, fixed interval, or explicit admin "reload" button? (Startup-only is simplest and safest.)
3. **Guardrail strength:** required-placeholder validation + length caps + a mandatory "test before activate" step — how strict before an edit can go live?
4. **Versioning model:** full version history vs just "previous value for one-click rollback"?
5. **Feature flags now or later?** Is per-user A/B (spec §4.4) needed for upcoming work, or deferrable?
6. **Per-user / per-cohort prompts?** Out of scope for v1 (global only), matching how `LLM_MODEL` is global today?
7. **Audit & access:** is `get_current_admin` (single owner-admin) sufficient, or do prompt edits need their own audit log / second-person review given the blast radius?
