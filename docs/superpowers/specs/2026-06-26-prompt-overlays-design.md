# Prompt Overlays — Design

**Status:** Approved (brainstorm 2026-06-26)
**Initiative:** Spec 11 (Knowledge Freshness), **Layer 3 of 3** — server-side prompt/config updates. (Layer 1 = Knowledge RAG, shipped. Layer 2 = food-DB freshness, separate future spec.)
**Builds on:** Spec 03 (`ai_extraction`, `trends_conversation`), the admin dashboard (#15/#16/#19), and the RAG context-injection pattern (PR #20).

## Goal

Let the owner tune **how Hearty talks** — the tone, emphasis, and standing guidance of its two AI explanation surfaces — from the `/admin` dashboard, **without shipping a new build**. Editing is a safe *overlay* on top of a locked core prompt: the structural rules (JSON output schema for the trends conversation) and the medical-safety guardrail ("observed correlations, not diagnoses") stay in code and always apply. A bad edit can make the tone odd; it cannot break parsing or strip safety.

**v1 scope:** an owner-editable "guidance overlay" per surface (weekly **summary** + monthly **trends conversation**), version history with one-click revert, injected via the existing append-a-context pattern, managed via `/admin`.

## Non-goals
- Editing the structured-extraction prompts (`MEAL_EXTRACTION_PROMPT`, `SYMPTOM_EXTRACTION_PROMPT`) — they must return strict JSON; out of scope to keep logging integrity safe.
- Full-prompt override — the owner edits only the overlay block, never the locked core.
- Per-user overlays — overlays are global (the same for every user).
- A live "test-run" preview in v1 — low blast radius makes edit→save→applies-next-call acceptable. (Possible later iteration.)

## Architecture

### 1. Storage — two tables + seed (migration)

```sql
-- One editable guidance overlay per AI surface. Service-key only (not user data).
create table if not exists prompt_overlays (
  surface     text primary key,                 -- 'summary' | 'trends_conversation'
  guidance    text not null default '',         -- the owner-editable overlay block ('' = none)
  updated_at  timestamptz not null default now(),
  updated_by  uuid
);
alter table prompt_overlays enable row level security;   -- service-key only; no policies
insert into prompt_overlays (surface) values ('summary'), ('trends_conversation')
  on conflict (surface) do nothing;

-- Append-only history: one row per save, enabling view + one-click revert.
create table if not exists prompt_overlay_versions (
  id          uuid primary key default gen_random_uuid(),
  surface     text not null,
  guidance    text not null,
  created_at  timestamptz not null default now(),
  created_by  uuid
);
alter table prompt_overlay_versions enable row level security;  -- service-key only
create index if not exists prompt_overlay_versions_surface_idx
  on prompt_overlay_versions (surface, created_at desc);
```

The two surface slugs are a fixed, code-known set (`SURFACES = {"summary", "trends_conversation"}`). The migration seeds both rows so reads always find a row.

### 2. Locked core + overlay injection

The base prompts stay exactly as they are in code (`ai_extraction.SUMMARY_PROMPT`, `trends_conversation.build_system_prompt`'s body) — including the trends-conversation JSON schema and the no-diagnosis framing. The owner's guidance is appended as one more block, using the **same mechanism as `health_context`/`research_context`** (Spec 08 / RAG). Final block order:

```
base prompt  →  owner overlay  →  health_context  →  research_context
```

The overlay goes first among the appended blocks (it's global standing guidance — part of "who Hearty is"), before the per-call user contexts.

- `trends_conversation.build_system_prompt(signals, health_context="", research_context="", style_overlay="")` and `generate_turn(..., style_overlay="")` — append `style_overlay` right after the base prompt (before `health_context`).
- `ai_extraction.generate_summary(stats, health_context="", research_context="", style_overlay="")` — same.
- **Empty `style_overlay` ⇒ the prompt is byte-identical to today.** (Same guarantee the RAG params have.)

> Note the ordering change vs. RAG: RAG appended research *after* health. The overlay appends *before* health. This is intentional — re-verify the existing health/research ordering tests still hold (overlay is a new earlier block, it doesn't reorder health vs research).

### 3. Service — `app/services/prompt_overlays.py`

Owns the service-key Supabase client for the two tables.
- `get_overlay(surface) -> str` — return the current `guidance` for a surface. **Best-effort: any error or missing row ⇒ `""`** (never raises), so a DB hiccup can never break an AI call.
- `set_overlay(surface, guidance, admin_id) -> dict` — validate `surface in SURFACES`; update the `prompt_overlays` row (guidance, updated_at, updated_by) **and** append a `prompt_overlay_versions` row. Returns the updated overlay row.
- `list_versions(surface) -> list[dict]` — version history (id, guidance, created_at, created_by), newest first.
- `revert(surface, version_id, admin_id) -> dict` — load that version's `guidance` and re-apply it via `set_overlay` (so a revert is itself a new version — full forward history, no history rewriting).

### 4. Retrieval wired into both AI surfaces (router orchestration)

Mirror the RAG pattern — the **`trends.py` router** loads overlays and passes them (keeps `prompt_overlays` out of the leaf services):
- Conversation endpoint: `style_overlay = prompt_overlays.get_overlay("trends_conversation")`, passed to `generate_turn`.
- Summary endpoint: `style_overlay = prompt_overlays.get_overlay("summary")`, passed to `generate_summary`.
- Wrapped best-effort (a load failure yields `""`).

### 5. Owner curation — admin API (all `Depends(get_current_admin)`)
- `GET /api/admin/prompt-overlays` → `{"overlays": [{surface, guidance, updated_at}, ...]}` for both surfaces.
- `PUT /api/admin/prompt-overlays/{surface}` `{guidance}` → `set_overlay`; 400 on unknown surface.
- `GET /api/admin/prompt-overlays/{surface}/versions` → `{"versions": [...]}`.
- `POST /api/admin/prompt-overlays/{surface}/revert` `{version_id}` → `revert`.

### 6. Web — "Prompt tuning" panel on `/admin`

A panel (mirrors the Knowledge base panel) with, per surface:
- A labeled `textarea` bound to the current `guidance` + a Save button, and a one-line helper describing what the surface controls ("How Hearty writes your weekly summary" / "How Hearty runs the monthly trends check-in").
- A collapsible version-history list (timestamp + a truncated preview) with a **Revert** button per version.
- Save / revert use React Query mutations that invalidate the overlays + versions queries (same idiom as `useKnowledgeActions`).

## Data flow (a weekly summary)
1. User hits the summary endpoint → `trends.py` `get_summary`.
2. Router builds `stats`, loads `health_context`, `research_context`, and `style_overlay = get_overlay("summary")`.
3. `generate_summary(stats, health_context, research_context, style_overlay)` → base prompt + overlay (+ contexts) → litellm.
4. No overlay set (empty) ⇒ identical to today.

## Error handling
- Read path fully best-effort: a `get_overlay` failure ⇒ `""` ⇒ normal behavior. No user-facing path can break because prompt-overlay storage is down.
- Write path (`set_overlay`/`revert`) surfaces errors to the admin (owner-only).
- `surface` is validated against the fixed `SURFACES` set on every write.

## Security
- Both tables: RLS on, no anon/auth policies (service-key only) — server config, not user data.
- All endpoints `get_current_admin`. The overlay is global, never reflects one user's data.
- The overlay cannot remove the JSON schema or the no-diagnosis guardrail (those live in the locked core), so a malicious/careless edit can't break parsing or strip medical-safety framing — only add guidance.

## Cost / performance
- One extra tiny `select` per RAG'd/summary AI call (the overlay). Negligible; could be cached later if needed. No new external calls.

## Testing
**Backend (pytest):**
- `prompt_overlays`: `get_overlay` returns guidance / `""` on missing / `""` on error (fake supabase); `set_overlay` updates the row AND appends a version + rejects unknown surface; `list_versions` ordered newest-first; `revert` re-applies an old version as a new save.
- Injection: `build_system_prompt`/`generate_summary` include `style_overlay` when set, absent when `""`, and `style_overlay` appears **before** `health_context`; existing health/research ordering tests stay green.
- `trends.py`: the summary + conversation endpoints pass the loaded overlay; the existing endpoint tests get a `prompt_overlays.get_overlay` stub (same anti-flake discipline used for `_research_for` — no real DB call).
- Admin CRUD: admin-gated (non-admin 403); get/put/versions/revert hit the store correctly (fake supabase); 400 on unknown surface.

**Web (Vitest + RTL + MSW):** the Prompt tuning panel lists overlays, the textarea saves, the version list renders + revert posts. Existing `/admin` tests stay green.

**Live (deploy-time):** apply the migration; via `/admin` set a small guidance on the summary surface, trigger a summary, confirm the tone reflects it; revert; confirm an empty overlay is a no-op.

## Deferred (future iterations)
A live "test-run" preview (render the prompt + a sample completion with the draft overlay before saving); editable extraction prompts behind a token-validation gate; per-segment overlays; A/B of overlays.
