# Knowledge Base RAG v1 — Design

**Status:** Approved (brainstorm 2026-06-25)
**Initiative:** Spec 11 (Knowledge Freshness), **Layer 1 of 3** — Health Knowledge Base (RAG). Layer 2 (food-DB sync) and Layer 3 (server-side prompt/config) are separate future specs.
**Builds on:** Spec 03 (REST API / `ai_extraction`, `trends_conversation`), Spec 08 (`health_profile`), the admin dashboard (#15/#16/#19).

## Goal

Ground Hearty's AI explanations in a **curated corpus of current health/nutrition research** instead of model weights alone. When the AI discusses a user's food↔symptom patterns, it retrieves relevant research excerpts (RAG) and incorporates them — without changing the "observed correlations, not diagnoses" guardrail.

**v1 scope:** `pgvector` corpus + retrieval wired into the two AI explanation surfaces + owner curation via `/admin`. **Deferred** (later Layer-1 iterations): automated PubMed/NHS/NIH ingestion, MeSH-term pulls, a human review queue, source-freshness alerts.

## Non-goals
- Automated research ingestion (owner manually curates in v1).
- General medical / drug / non-GI literature (corpus is dietary patterns, food-symptom relationships, GI condition management — same scope limit as the existing Spec 11).
- Any change to how signals are *computed* (signals stay purely statistical; RAG only grounds the AI *explanation* of them).
- User-facing corpus management (admin/owner only).

## Architecture

### 1. Storage — `pgvector` + `knowledge_base` + retrieval RPC (migration)

```sql
create extension if not exists vector;

create table if not exists knowledge_base (
  id uuid primary key default gen_random_uuid(),
  source text not null,                 -- 'manual' (v1), later 'pubmed'/'nhs'/'nih'
  source_id text,
  title text,
  content text not null,
  content_embedding vector(1536),       -- OpenAI text-embedding-3-small
  conditions text[] default '{}',       -- e.g. {'ibs','gerd','celiac'}
  tags text[] default '{}',
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table knowledge_base enable row level security;  -- service-key only; not user data
create index if not exists knowledge_base_embedding_idx
  on knowledge_base using ivfflat (content_embedding vector_cosine_ops) with (lists = 100);

-- Top-k cosine retrieval (PostgREST can't do vector ops via the query builder).
create or replace function match_knowledge(
  query_embedding vector(1536),
  match_count int default 4,
  filter_conditions text[] default null
) returns table (id uuid, source text, title text, content text, conditions text[], similarity float)
language sql stable as $$
  select kb.id, kb.source, kb.title, kb.content, kb.conditions,
         1 - (kb.content_embedding <=> query_embedding) as similarity
  from knowledge_base kb
  where kb.active
    and (filter_conditions is null or kb.conditions && filter_conditions)
  order by kb.content_embedding <=> query_embedding
  limit match_count;
$$;
```
Service-key client retrieves via `supabase.rpc("match_knowledge", {...})`. If PostgREST won't coerce the JSON array to `vector(1536)` on the RPC param, fall back to a `text` param cast inside (`query_embedding::vector`) — decided at implementation against the live client.

### 2. Embedding service — `app/services/embeddings.py`
```python
def embed(text: str) -> list[float]:
    resp = litellm.embedding(model="text-embedding-3-small", input=[text])
    return resp.data[0]["embedding"]
```
Same model for ingestion and query (required for valid similarity). Needs `OPENAI_API_KEY` (new deploy-time env var). One thin module.

### 3. Knowledge store + retrieval — `app/services/knowledge.py`
- `add_entry(title, content, conditions, source="manual", source_id=None) -> dict` — `embed(content)` then insert; returns the row (without the embedding).
- `search(query_text, k=4, conditions=None) -> list[dict]` — `embed(query_text)`, call `match_knowledge` RPC, return rows. **Any embedding/RPC error or empty corpus → return `[]`** (never raises).
- `format_context(rows) -> str` — compact block, `""` if no rows:
  ```
  Relevant current research (ground your explanation in this; still observations, not diagnoses):
  - {title}: {content}
  ...
  ```
- `list_entries()`, `delete_entry(id)`, `set_active(id, active)` for admin.

### 4. Retrieval wired into both AI surfaces
Mirror the existing `health_context` pattern — append a `research_context` block; the **`trends.py` router orchestrates** retrieval (keeps `knowledge` out of the leaf services):

- `trends_conversation.build_system_prompt(signals, health_context="", research_context="")` and `generate_turn(..., research_context="")` — append `research_context` after `health_context`.
- `ai_extraction.generate_summary(stats, health_context="", research_context="")` — append `research_context`.
- **Router (`trends.py`)**:
  - Conversation turn endpoint: build the query from the latest user message (if any) else the signals, retrieve with the user's `health_profile.conditions` as `filter_conditions`, `format_context`, pass as `research_context`.
  - Summary endpoint: build the query from the top signals in `stats`, same conditions filter, pass `research_context`.
- A small helper `_research_for(query, user_id)` in the router: load conditions from `health_profile`, `knowledge.search`, `format_context`. Wrapped so a failure yields `""` (RAG augments, never blocks the AI call).

### 5. Owner curation — admin corpus management
Backend (`app/routers/admin.py`, all `Depends(get_current_admin)`):
- `POST /api/admin/knowledge` `{title, content, conditions[], source?}` → `add_entry`.
- `GET /api/admin/knowledge` → list (id, title, source, conditions, active, created_at — no embeddings).
- `DELETE /api/admin/knowledge/{id}`.
- `PATCH /api/admin/knowledge/{id}` `{active}` → toggle.

Web — a **"Knowledge base"** panel on `/admin`: list entries (title / source / conditions / active toggle / delete) + an add form (title, content textarea, conditions, source). v1 entries are `active` immediately (owner is the trusted curator; no review queue yet).

### 6. Health-profile scoping
`search` filters by the user's conditions (from Spec 08 `health_profile.conditions`) via `match_knowledge`'s `filter_conditions` (corpus row matches if `conditions && filter_conditions`). A GERD user gets GERD-tagged research. If the user has no conditions, pass `null` (no filter).

## Data flow (a trends conversation turn)
1. User sends a message → `trends.py` turn endpoint.
2. Router builds the query (latest message + signals), loads the user's conditions, `knowledge.search(query, conditions)` → top-k rows → `format_context`.
3. Router calls `generate_turn(signals, history, health_context, research_context)`; the system prompt now carries the research block.
4. Claude answers grounded in the user's patterns **and** the retrieved research.
5. Corpus empty / retrieval error → `research_context=""` → identical to today's behavior.

## Error handling
- Retrieval is fully best-effort: embedding or RPC failure, or empty corpus → `""` research_context → the AI call proceeds unchanged. No user-facing path can break because RAG is down.
- `add_entry` surfaces embedding failures to the admin (so the owner knows an entry wasn't embedded) — admin write path, not a user path.

## Security
- `knowledge_base`: RLS on, no anon/auth policies (service-key only) — it's server corpus, not user data; `match_knowledge` is `stable` and read-only.
- All corpus-management endpoints `get_current_admin`. Retrieval uses the service-key client; the query text derives from the requesting user's own signals/message + their own conditions.
- `OPENAI_API_KEY` is a backend env var (never client-exposed).

## Cost / performance
- One embedding per RAG'd AI call (query) + one vector search — `text-embedding-3-small` ≈ $0.02/1M tokens (negligible); adds ~50–150 ms. Ingestion embeds once per entry on add.
- ivfflat index is fine; at a small corpus even a scan is instant.

## Testing
**Backend (pytest):**
- `embeddings.embed`: monkeypatch `litellm.embedding` → returns the vector.
- `knowledge.add_entry`: embeds + inserts (fake supabase); `search`: embeds query + calls `match_knowledge` RPC with the right args + returns rows; **error/empty → `[]`**; `format_context`: block when rows, `""` when none.
- `build_system_prompt`/`generate_summary`: `research_context` appears in the prompt when provided, absent when `""`.
- `trends.py` `_research_for`: returns formatted context on hits; `""` when `search` raises (best-effort).
- Admin knowledge CRUD: admin-gated (non-admin 403); add/list/delete/toggle hit the store correctly (fake supabase).

**Web (Vitest + RTL + MSW):** the Knowledge base panel lists entries from a mocked payload, the add form posts, delete/toggle hit the right endpoints. Existing `/admin` tests stay green.

**Live (deploy-time):** set `OPENAI_API_KEY`; apply the migration (enables `vector`); add a couple of seed entries via `/admin`; confirm a trends conversation/summary reflects the research (and still works with an empty corpus).

## Deferred (future Layer-1 iterations)
Automated PubMed (NCBI E-utilities) / NHS / NIH ingestion on a schedule, MeSH-term pulls, a human review queue (`reviewed` workflow), source-freshness alerts, and a larger seeded corpus.
