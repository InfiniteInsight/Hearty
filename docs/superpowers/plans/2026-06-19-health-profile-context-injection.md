# Health-Profile Context Injection (Spec 08, Phases 4–5) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Finish Spec-08 Phases 4–5: format a user's health profile (allergens / intolerances / conditions / dietary protocols) into a system-prompt block and inject it into the AI surfaces that reason about the user's meals & symptoms, so Hearty becomes allergen/condition/protocol-aware (spec §9.1, §9.3). Plus tests.

**Architecture:** A pure formatter `build_health_profile_context(profile) -> str` (spec §9.1 format) + a loader `load_health_profile_context(user_id) -> str` (loads the row → `HealthProfileResponse` → formatted block; `""` when empty so callers skip injection). Injected into the two current AI call sites that match spec §9.2/§9.3: the **trends conversation** system prompt and the **summary** generation. Empty profile → no change in behavior.

**Re-validation note (month-old plan):** the plan named `/api/trends` + `/api/summary`. Today's equivalents: the trends-conversation system prompt (`services/trends_conversation.py`, the conversational AI surface — best match for §9.3's condition/protocol-aware insights) and `ai_extraction.generate_summary` (feeds `/api/summary`). MCP injection (spec §9.1) stays out of scope (separate Spec-02 plan) — leave a code comment.

**Tech Stack:** FastAPI + litellm. Runner: `cd hearty-api && set -a && . ../.env && set +a && .venv/bin/python -m pytest <file> -v`.

**Verified facts:**
- Profile shapes (`app/health_profile/schemas.py`): `AllergenEntry{name, severity(enum mild/moderate/severe), reaction?, confirmed_by_doctor:bool, notes?}`, `IntoleranceEntry{name, severity?, threshold?, notes?}`, `ConditionEntry{name, diagnosed:bool, diagnosis_year?, notes?}`, `DietaryProtocolEntry{name, active:bool=True, started?(YYYY-MM-DD), phase?, notes?}`, `HealthProfileResponse{allergens,intolerances,conditions,dietary_protocols,updated_at}`.
- Loading a profile (`app/health_profile/router.py`): `supabase.table("health_profile").select("*").eq("user_id", user_id)` → `_row_to_response(row) -> HealthProfileResponse` (reuse this conversion).
- Trends conversation: `services/trends_conversation.py` `build_system_prompt(signals)` → used in `generate_turn(...)` (`messages=[{"role":"system","content":build_system_prompt(signals)}]`, `litellm.completion(...)`).
- Summary: `services/ai_extraction.py` `generate_summary(stats)` (its own litellm call with a SUMMARY_PROMPT).

---

## Task 1: Context formatter + loader (TDD)

**Files:** Create `hearty-api/app/health_profile/context.py`; Test `hearty-api/tests/test_health_profile_context_unit.py`.

- [ ] **Step 1:** Read spec `docs/superpowers/specs/2026-05-04-hearty-08-health-profile.md` §9.1 (the exact output format) and §3.2 / §5.1 / §6.1 (the per-condition / per-protocol / allergen analysis instructions to enumerate). Implement:

`build_health_profile_context(profile: HealthProfileResponse) -> str`:
- If all four lists empty → return `""`.
- `User health profile:` header, then one bullet per non-empty domain:
  - Allergens: `name (severity, confirmed)` if `confirmed_by_doctor` else `name (severity)` (severity = the enum value).
  - Intolerances: `name (threshold)` if `threshold` else `name`.
  - Conditions: `name (diagnosed YYYY)` if `diagnosis_year` else `name`.
  - Dietary protocols (active ones): `name phase (started DATE)` when `phase`/`started` set, else `name`.
- Then a `When analyzing meals and symptoms:` block containing ONLY the instruction bullets relevant to what's present — drawn from spec §3.2/§5.1/§6.1 and the §9.1 example, e.g.:
  - allergens present → "Flag any meal containing {allergen names} regardless of symptom presence"
  - a FODMAP/low-FODMAP protocol present → "Cross-reference logged foods against FODMAP content"
  - GERD condition → "Note acid-triggering foods and late meals for GERD relevance"
  - IBS-D/IBS condition → "Use IBS context when interpreting bathroom urgency and stool consistency"
  - (Add the others the spec enumerates; do NOT invent behaviors beyond §3.2/§5.1/§6.1.)
- Keep it deterministic (stable ordering) so it's testable.

`load_health_profile_context(user_id: str) -> str`: query `health_profile` for the user (service-key supabase client, like the router), convert via the same logic as `_row_to_response`, return `build_health_profile_context(resp)`; return `""` if no row. (Import/reuse `_row_to_response` if cleanly importable, else replicate minimally.)

Add a comment noting the MCP Server's `get_health_profile` tool (Spec 02) should also call `build_health_profile_context` — not implemented here.

- [ ] **Step 2: Tests** (pure formatter — no DB needed for `build_*`; mock supabase for `load_*`):
  - Full profile (the spec §9.1 example data) → output contains the listing bullets AND the matching analysis bullets (allergen flag names, FODMAP cross-ref, GERD, IBS).
  - Empty profile → `""`.
  - Partial profile (only allergens) → only the allergen bullet + allergen-flag instruction; no condition/protocol bullets.
  - `load_health_profile_context`: no row → `""`; a row → formatted block (mock the supabase select).
- [ ] **Step 3:** Run the test file + full suite (`--ignore=tests/test_api.py`) → pass.
- [ ] **Step 4: Commit** (`feat(health-profile): context-injection formatter + loader (Spec 08 §9.1)`).

---

## Task 2: Inject into the trends conversation (TDD)

**Files:** Modify `hearty-api/app/services/trends_conversation.py` + its route handler (find where `generate_turn` is called — likely `app/routers/trends.py`); Test: extend `tests/test_trends_conversation_unit.py`.

- [ ] **Step 1:** Thread an optional `health_context: str = ""` through: `build_system_prompt(signals, health_context="")` appends the block (when non-empty) to the system prompt; `generate_turn(..., health_context="")` passes it to `build_system_prompt`. Keep defaults so existing callers/tests are unaffected.
- [ ] **Step 2:** In the route that calls `generate_turn`, load `health_profile.context.load_health_profile_context(user["id"])` and pass it as `health_context`.
- [ ] **Step 3: Tests:** a `build_system_prompt(signals, health_context="User health profile:\n- Allergens: milk (severe, confirmed)...")` includes the block; with `""` the prompt is unchanged from before (existing tests still green). Add a focused assertion that `generate_turn` forwards a provided `health_context` into the system message (patch litellm.completion, capture the system message).
- [ ] **Step 4:** Run the conversation tests + full suite → pass.
- [ ] **Step 5: Commit** (`feat(health-profile): inject profile context into the trends conversation`).

---

## Task 3: Inject into summary generation (TDD)

**Files:** Modify `hearty-api/app/services/ai_extraction.py` (`generate_summary`) + the `/api/summary` route; Test: extend the relevant test (`tests/` — grep `generate_summary` / `/api/summary`).

- [ ] **Step 1:** Add an optional `health_context: str = ""` to `generate_summary(stats, health_context="")`; when non-empty, include it in the prompt (prepend a "Consider the user's health profile:\n{health_context}" note). Default keeps current behavior.
- [ ] **Step 2:** In the `/api/summary` route handler, load `load_health_profile_context(user["id"])` and pass it.
- [ ] **Step 3: Tests:** `generate_summary` with a non-empty `health_context` includes it in the litellm prompt (patch completion, capture prompt); with `""` unchanged. Endpoint test still green.
- [ ] **Step 4:** Run tests + full suite (`--ignore=tests/test_api.py`) → all pass.
- [ ] **Step 5: Commit** (`feat(health-profile): inject profile context into summary generation`).

---

## Self-review
- **Spec coverage:** §9.1 formatter (T1) · §9.2/§9.3 injection into the trends conversation (T2) + summary (T3). MCP (§9.1) intentionally deferred with a code comment (separate plan). Empty profile → `""` → zero behavior change.
- **Re-validation:** injected into today's real AI call sites (trends_conversation, generate_summary) rather than the plan's stale `/api/trends`+`/api/summary` literal names; documented.
- **Backward compat:** all `health_context` params are optional/defaulted — existing callers/tests unaffected.
- **No placeholders:** formatter rules + injection points are concrete; the instruction-bullet mapping is sourced from the cited spec sections (implementer reads §3.2/§5.1/§6.1).
- **Phase 5 (integration tests):** folded into each task's tests (formatter cases + injection-forwarding assertions) rather than a separate live-DB phase.
