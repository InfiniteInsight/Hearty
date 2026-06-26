# Knowledge Base RAG v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ground Hearty's two AI explanation surfaces (monthly trends conversation + health summary) in a curated, owner-managed health-research corpus via pgvector RAG, with an `/admin` curation panel.

**Architecture:** A `knowledge_base` pgvector table + `match_knowledge` cosine-retrieval RPC. A thin `embeddings.embed()` (litellm → Gemini `gemini-embedding-001`, 3072-dim) and a best-effort `knowledge` store/retrieval module. The `trends.py` router orchestrates retrieval (`_research_for`) and passes a `research_context` block into `trends_conversation.generate_turn` and `ai_extraction.generate_summary` — mirroring the existing `health_context` pattern. Retrieval is fully best-effort: any embedding/RPC error or empty corpus yields `""`, leaving the AI call byte-identical to today. Owner CRUD via `/api/admin/knowledge` + a "Knowledge base" panel on `/admin`.

**Tech Stack:** FastAPI (Python), Supabase Postgres + pgvector, litellm, React 19 + TanStack Query v5 + Vitest/RTL/MSW.

**Spec:** `docs/superpowers/specs/2026-06-25-knowledge-rag-design.md`

**Worktree:** `~/.config/superpowers/worktrees/knowledge-rag` (branch `knowledge-rag`, off master @ #19). Backend test command: `cd hearty-api && .venv/bin/pytest`. Web test command: `cd hearty-web && npm run test -- --run`.

**Key prod fact (already verified):** A raw Python `list[float]` binds directly to a `vector(N)` column on both insert and the RPC `query_embedding` param — pass plain Python lists everywhere, no `::vector` cast or string-literal form. (Spike used 1536; v1 uses Gemini's 3072 — binding is dimension-agnostic.)

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `supabase/migrations/<ts>_knowledge_base.sql` | `vector` ext, `knowledge_base` table, `match_knowledge` RPC | 1 |
| `hearty-api/app/services/embeddings.py` | `embed(text) -> list[float]` via litellm | 2 |
| `hearty-api/app/services/knowledge.py` | corpus store + best-effort retrieval + admin ops | 3 |
| `hearty-api/app/services/trends_conversation.py` | add `research_context` param (modify) | 4 |
| `hearty-api/app/services/ai_extraction.py` | add `research_context` param (modify) | 4 |
| `hearty-api/app/routers/trends.py` | `_research_for` orchestration + wire 2 endpoints (modify) | 5 |
| `hearty-api/app/routers/admin.py` | knowledge CRUD endpoints (modify) | 6 |
| `hearty-web/src/types/api.ts` | knowledge TS types (modify) | 7 |
| `hearty-web/src/lib/api.ts` | knowledge client methods (modify) | 7 |
| `hearty-web/src/hooks/useAdmin.ts` | `useKnowledge` + `useKnowledgeActions` (modify) | 8 |
| `hearty-web/src/pages/Admin.tsx` | `KnowledgeBase` panel (modify) | 9 |
| `.env`, `.env.example`, `docs/DEPLOYMENT.md` | `GEMINI_API_KEY` + apply migration + redeploy (modify) | 10 |

---

### Task 1: pgvector migration — `knowledge_base` table + `match_knowledge` RPC

**Files:**
- Create: `supabase/migrations/<timestamp>_knowledge_base.sql`

> Migrations don't fit the test-first loop (no local Postgres in this repo; the table is applied to prod at deploy time in Task 10). The pgvector binding is already prod-verified, so this task is: create the migration file with the exact SQL below, eyeball it, commit. Do NOT apply it to prod here — that is Task 10 (live, needs consent).

- [ ] **Step 1: Generate the migration file**

Run: `cd ~/.config/superpowers/worktrees/knowledge-rag && supabase migration new knowledge_base`
Expected: prints `Created new migration at supabase/migrations/<timestamp>_knowledge_base.sql`. (If the Supabase CLI is unavailable, create the file directly as `supabase/migrations/20260625120000_knowledge_base.sql` — match the existing `YYYYMMDDHHMMSS_name.sql` convention, using a timestamp later than `20260625000000_service_health.sql`.)

- [ ] **Step 2: Write the migration SQL**

Paste exactly this into the new file:

```sql
-- Knowledge Base RAG v1 (Spec 11 Layer 1): curated health-research corpus +
-- top-k cosine retrieval RPC. Service-key only (not user data).
create extension if not exists vector;

create table if not exists knowledge_base (
  id uuid primary key default gen_random_uuid(),
  source text not null default 'manual',     -- 'manual' (v1), later 'pubmed'/'nhs'/'nih'
  source_id text,
  title text,
  content text not null,
  content_embedding vector(3072),            -- Gemini gemini-embedding-001 (3072 dims)
  conditions text[] not null default '{}',   -- e.g. {'ibs','gerd','celiac'}; NOT NULL so the
                                             -- conditions = '{}' eligibility test below can't be
                                             -- defeated by a null (which would hide the row from
                                             -- every query).
  tags text[] not null default '{}',
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table knowledge_base enable row level security;
-- No ANN index in v1: an exact sequential scan over a tiny corpus is instant and gives perfect
-- recall (ivfflat with lists=100 would hurt recall at this size). Add an HNSW index once the
-- corpus reaches thousands of rows:
--   create index knowledge_base_embedding_idx
--     on knowledge_base using hnsw (content_embedding vector_cosine_ops);

-- Top-k cosine retrieval (PostgREST can't do vector ops via the query builder).
create or replace function match_knowledge(
  query_embedding vector(3072),
  match_count int default 4,
  filter_conditions text[] default null
) returns table (id uuid, source text, title text, content text, conditions text[], similarity float)
language sql stable as $$
  select kb.id, kb.source, kb.title, kb.content, kb.conditions,
         1 - (kb.content_embedding <=> query_embedding) as similarity
  from knowledge_base kb
  where kb.active
    and (filter_conditions is null               -- caller has no conditions: no filter
         or kb.conditions = '{}'                 -- untagged = general research, always eligible
         or kb.conditions && filter_conditions)  -- else require a condition overlap
  order by kb.content_embedding <=> query_embedding
  limit match_count;
$$;
```

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/*_knowledge_base.sql
git commit -m "feat(rag): knowledge_base pgvector table + match_knowledge RPC migration"
```

---

### Task 2: Embedding service — `embeddings.embed`

**Files:**
- Create: `hearty-api/app/services/embeddings.py`
- Test: `hearty-api/tests/test_embeddings_unit.py`

- [ ] **Step 1: Write the failing test**

```python
import types
from app.services import embeddings


def test_embed_returns_vector_and_uses_gemini_model(monkeypatch):
    captured = {}

    def fake_embedding(model, input):
        captured["model"] = model
        captured["input"] = input
        # Mirrors litellm's EmbeddingResponse: .data is a list of dict-like
        # objects each carrying an "embedding" key.
        return types.SimpleNamespace(data=[{"embedding": [0.1, 0.2, 0.3]}])

    monkeypatch.setattr(embeddings.litellm, "embedding", fake_embedding)
    out = embeddings.embed("hello world")
    assert out == [0.1, 0.2, 0.3]
    assert captured["model"] == "gemini/gemini-embedding-001"
    assert captured["input"] == ["hello world"]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd hearty-api && .venv/bin/pytest tests/test_embeddings_unit.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.services.embeddings'`.

- [ ] **Step 3: Write the implementation**

Create `hearty-api/app/services/embeddings.py`:

```python
"""Embedding service for the knowledge-base RAG (Spec 11 Layer 1).

Wraps litellm.embedding so the SAME model is used for both ingestion and query
(required for valid cosine similarity). Needs GEMINI_API_KEY at deploy time.
"""

import litellm

EMBEDDING_MODEL = "gemini/gemini-embedding-001"  # 3072 dims; matches vector(3072)


def embed(text: str) -> list[float]:
    """Return the embedding vector for a piece of text."""
    resp = litellm.embedding(model=EMBEDDING_MODEL, input=[text])
    return resp.data[0]["embedding"]
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd hearty-api && .venv/bin/pytest tests/test_embeddings_unit.py -v`
Expected: PASS (1 passed).

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/embeddings.py hearty-api/tests/test_embeddings_unit.py
git commit -m "feat(rag): embeddings.embed via litellm gemini gemini-embedding-001"
```

---

### Task 3: Knowledge store + best-effort retrieval — `knowledge.py`

**Files:**
- Create: `hearty-api/app/services/knowledge.py`
- Test: `hearty-api/tests/test_knowledge_unit.py`

- [ ] **Step 1: Write the failing test**

```python
import types
from app.services import knowledge


class _Query:
    def __init__(self, store, table):
        self.store, self.table = store, table
        self._op = None; self._payload = None; self._filters = []; self._order = None

    def insert(self, payload): self._op = "insert"; self._payload = payload; return self
    def select(self, cols): self._op = "select"; return self
    def update(self, payload): self._op = "update"; self._payload = payload; return self
    def delete(self): self._op = "delete"; return self
    def eq(self, col, val): self._filters.append((col, val)); return self
    def order(self, col, desc=False): self._order = (col, desc); return self

    def execute(self):
        self.store["calls"].append((self.table, self._op, self._payload, self._filters))
        if self._op == "insert":
            row = dict(self._payload); row["id"] = "kb1"
            return types.SimpleNamespace(data=[row])
        if self._op == "select":
            return types.SimpleNamespace(data=self.store.get("rows", []))
        if self._op == "update":
            return types.SimpleNamespace(data=[{"id": self._filters[0][1], **self._payload}])
        return types.SimpleNamespace(data=[])  # delete


class _FakeSupabase:
    def __init__(self, store): self.store = store
    def table(self, name): return _Query(self.store, name)
    def rpc(self, fn, params):
        self.store["rpc"] = (fn, params)
        return types.SimpleNamespace(
            execute=lambda: types.SimpleNamespace(data=self.store.get("rpc_rows", [])))


def _setup(monkeypatch, store):
    monkeypatch.setattr(knowledge, "supabase", _FakeSupabase(store))
    monkeypatch.setattr(knowledge, "embed", lambda t: [0.5] * 3072)


def test_add_entry_embeds_and_strips_vector(monkeypatch):
    store = {"calls": []}; _setup(monkeypatch, store)
    row = knowledge.add_entry("Title", "body text", conditions=["gerd"])
    assert "content_embedding" not in row          # returned row is lightweight
    table, op, payload, _ = store["calls"][0]
    assert table == "knowledge_base" and op == "insert"
    assert payload["content_embedding"] == [0.5] * 3072
    assert payload["conditions"] == ["gerd"]
    assert payload["content"] == "body text"


def test_search_calls_rpc_with_right_args(monkeypatch):
    store = {"calls": [], "rpc_rows": [
        {"id": "kb1", "title": "X", "content": "c", "conditions": [], "similarity": 0.9}]}
    _setup(monkeypatch, store)
    rows = knowledge.search("acid reflux", k=3, conditions=["gerd"])
    fn, params = store["rpc"]
    assert fn == "match_knowledge"
    assert params["query_embedding"] == [0.5] * 3072
    assert params["match_count"] == 3
    assert params["filter_conditions"] == ["gerd"]
    assert rows[0]["title"] == "X"


def test_search_empty_conditions_passes_none(monkeypatch):
    store = {"calls": [], "rpc_rows": []}; _setup(monkeypatch, store)
    knowledge.search("q", conditions=[])
    assert store["rpc"][1]["filter_conditions"] is None


def test_search_swallows_errors(monkeypatch):
    def boom(_): raise RuntimeError("no api key")
    monkeypatch.setattr(knowledge, "embed", boom)
    monkeypatch.setattr(knowledge, "supabase", _FakeSupabase({"calls": []}))
    assert knowledge.search("q") == []


def test_format_context_block_and_empty():
    assert knowledge.format_context([]) == ""
    block = knowledge.format_context([{"title": "T", "content": "body"}])
    assert "Relevant current research" in block
    assert "- T: body" in block


def test_set_active_updates_row(monkeypatch):
    store = {"calls": []}; _setup(monkeypatch, store)
    out = knowledge.set_active("kb9", False)
    table, op, payload, filters = store["calls"][0]
    assert op == "update" and payload == {"active": False} and filters == [("id", "kb9")]
    assert out["active"] is False
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd hearty-api && .venv/bin/pytest tests/test_knowledge_unit.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'app.services.knowledge'`.

- [ ] **Step 3: Write the implementation**

Create `hearty-api/app/services/knowledge.py`:

```python
"""Knowledge-base store + retrieval for the RAG corpus (Spec 11 Layer 1).

Owns the service-key Supabase client for the knowledge_base table. Retrieval is
best-effort: any embedding/RPC failure or empty corpus yields [] so a RAG miss
never breaks the AI call that depends on it.
"""

import logging
import os

from supabase import create_client

from app.services.embeddings import embed

logger = logging.getLogger(__name__)
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])

# Columns returned to the admin list view — never the embedding (heavy, useless to UI).
_LIST_COLUMNS = "id, source, title, conditions, tags, active, created_at"


def add_entry(title, content, conditions=None, source="manual", source_id=None) -> dict:
    """Embed ``content`` and insert a corpus row. Returns the row WITHOUT the
    embedding. Embedding failures propagate (admin write path — the owner should
    see that an entry wasn't embedded)."""
    vector = embed(content)
    row = {
        "title": title,
        "content": content,
        "content_embedding": vector,
        "conditions": conditions or [],
        "source": source,
        "source_id": source_id,
    }
    inserted = supabase.table("knowledge_base").insert(row).execute().data[0]
    inserted.pop("content_embedding", None)
    return inserted


def search(query_text, k=4, conditions=None) -> list[dict]:
    """Return up to ``k`` corpus rows most similar to ``query_text``. Best-effort:
    any embedding/RPC error or empty corpus yields []."""
    try:
        vector = embed(query_text)
        resp = supabase.rpc("match_knowledge", {
            "query_embedding": vector,
            "match_count": k,
            "filter_conditions": conditions or None,
        }).execute()
        return resp.data or []
    except Exception as e:  # never let a RAG miss break the caller's AI call
        logger.error("knowledge.search failed: %s", e, exc_info=True)
        return []


def format_context(rows) -> str:
    """Render retrieved rows as a system-prompt block. '' when no rows."""
    if not rows:
        return ""
    lines = ["Relevant current research (ground your explanation in this; "
             "still observations, not diagnoses):"]
    for r in rows:
        title = r.get("title") or "research"
        lines.append(f"- {title}: {r['content']}")
    return "\n".join(lines)


def list_entries() -> list[dict]:
    return (supabase.table("knowledge_base")
            .select(_LIST_COLUMNS)
            .order("created_at", desc=True)
            .execute()).data or []


def delete_entry(entry_id) -> None:
    supabase.table("knowledge_base").delete().eq("id", entry_id).execute()


def set_active(entry_id, active) -> dict:
    res = (supabase.table("knowledge_base")
           .update({"active": active})
           .eq("id", entry_id)
           .execute())
    return res.data[0] if res.data else {}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd hearty-api && .venv/bin/pytest tests/test_knowledge_unit.py -v`
Expected: PASS (6 passed).

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/knowledge.py hearty-api/tests/test_knowledge_unit.py
git commit -m "feat(rag): knowledge store + best-effort cosine retrieval"
```

---

### Task 4: Add `research_context` to both AI surfaces

**Files:**
- Modify: `hearty-api/app/services/trends_conversation.py:35-84`
- Modify: `hearty-api/app/services/ai_extraction.py:139-154`
- Test: `hearty-api/tests/test_research_context_unit.py`

- [ ] **Step 1: Write the failing test**

```python
import types
from app.services.trends_conversation import build_system_prompt
from app.services import ai_extraction


def test_system_prompt_appends_research_after_health():
    p = build_system_prompt([], health_context="HEALTH-BLOCK",
                            research_context="RESEARCH-BLOCK")
    assert "RESEARCH-BLOCK" in p
    assert p.index("HEALTH-BLOCK") < p.index("RESEARCH-BLOCK")


def test_system_prompt_omits_empty_research():
    p = build_system_prompt([], research_context="")
    assert "RESEARCH-BLOCK" not in p
    assert "Relevant current research" not in p


def test_generate_summary_includes_research_context(monkeypatch):
    captured = {}

    def fake_completion(model, messages, api_base=None):
        captured["content"] = messages[0]["content"]
        return types.SimpleNamespace(
            choices=[types.SimpleNamespace(message=types.SimpleNamespace(content="ok"))])

    monkeypatch.setattr(ai_extraction.litellm, "completion", fake_completion)
    ai_extraction.generate_summary({"a": 1}, health_context="HC",
                                   research_context="RESEARCH-BLOCK")
    assert "RESEARCH-BLOCK" in captured["content"]
    assert captured["content"].index("HC") < captured["content"].index("RESEARCH-BLOCK")
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd hearty-api && .venv/bin/pytest tests/test_research_context_unit.py -v`
Expected: FAIL — `TypeError: build_system_prompt() got an unexpected keyword argument 'research_context'`.

- [ ] **Step 3: Modify `trends_conversation.py`**

Change `build_system_prompt` signature and its tail (currently lines 35-36 and 73-75):

```python
def build_system_prompt(signals: list[PresentedSignal],
                        health_context: str = "",
                        research_context: str = "") -> str:
```

Replace the existing tail:

```python
    if health_context:
        prompt = f"{prompt}\n\n{health_context}"
    return prompt
```

with:

```python
    if health_context:
        prompt = f"{prompt}\n\n{health_context}"
    if research_context:
        prompt = f"{prompt}\n\n{research_context}"
    return prompt
```

Change `generate_turn` signature (currently lines 78-82) and its `build_system_prompt` call (line 84):

```python
def generate_turn(
    signals: list[PresentedSignal],
    history: list[ConversationTurn],
    health_context: str = "",
    research_context: str = "",
) -> TrendsConversationResponse:
    messages = [{"role": "system",
                 "content": build_system_prompt(signals, health_context, research_context)}]
```

- [ ] **Step 4: Modify `ai_extraction.py`**

Change `generate_summary` (currently lines 139-148):

```python
def generate_summary(stats: dict, health_context: str = "",
                     research_context: str = "") -> str:
    """Generate a natural language summary from aggregated health stats.

    When ``health_context``/``research_context`` are non-empty they are appended
    (health first, then research) so the summary accounts for the user's profile
    and any retrieved research. Empty contexts leave the prompt byte-identical to
    the no-context path.
    """
    prompt = SUMMARY_PROMPT.replace("{stats_json}", json.dumps(stats))
    if health_context:
        prompt = f"{prompt}\n\n{health_context}"
    if research_context:
        prompt = f"{prompt}\n\n{research_context}"
```

(Leave the `litellm.completion(...)` call and `return` below unchanged.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd hearty-api && .venv/bin/pytest tests/test_research_context_unit.py tests/test_trends_conversation_unit.py tests/test_summary_health_context_unit.py -v`
Expected: PASS — new tests pass and the existing conversation/summary tests stay green (the new params default to `""`, so existing callers are unaffected).

- [ ] **Step 6: Commit**

```bash
git add hearty-api/app/services/trends_conversation.py hearty-api/app/services/ai_extraction.py hearty-api/tests/test_research_context_unit.py
git commit -m "feat(rag): thread research_context into conversation + summary prompts"
```

---

### Task 5: Orchestrate retrieval in `trends.py` router

**Files:**
- Modify: `hearty-api/app/routers/trends.py` (imports ~18-22; conversation endpoint 286-302; summary endpoint 420-421; add helpers near top)
- Test: `hearty-api/tests/test_research_orchestration_unit.py`

- [ ] **Step 1: Write the failing test**

```python
from app.routers import trends


def test_research_for_returns_formatted_block(monkeypatch):
    monkeypatch.setattr(trends, "_user_condition_slugs", lambda uid: ["gerd"])
    monkeypatch.setattr(trends.knowledge, "search",
                        lambda q, conditions=None: [{"title": "T", "content": "body"}])
    out = trends._research_for("acid reflux", "u1")
    assert "T: body" in out


def test_research_for_swallows_errors(monkeypatch):
    def boom(*a, **k): raise RuntimeError("x")
    monkeypatch.setattr(trends, "_user_condition_slugs", lambda uid: [])
    monkeypatch.setattr(trends.knowledge, "search", boom)
    assert trends._research_for("q", "u1") == ""


def test_user_condition_slugs_lowercases_names(monkeypatch):
    class _R:
        data = {"conditions": [{"name": "GERD"}, {"name": "IBS"}]}

    class _Q:
        def select(self, *a): return self
        def eq(self, *a): return self
        def maybe_single(self): return self
        def execute(self): return _R()

    monkeypatch.setattr(trends.supabase, "table", lambda n: _Q())
    assert trends._user_condition_slugs("u1") == ["gerd", "ibs"]
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd hearty-api && .venv/bin/pytest tests/test_research_orchestration_unit.py -v`
Expected: FAIL — `AttributeError: module 'app.routers.trends' has no attribute '_research_for'`.

- [ ] **Step 3: Add the import and helpers**

In the `from app.services import (...)` block (lines 18-21), add `knowledge`:

```python
from app.services import (
    ai_extraction, trend_engine, signal_engine,
    signal_presenter, trends_conversation, signal_persistence,
    knowledge,
)
```

Add these helpers just below `TRENDS_MIN_RECOMPUTE_MINUTES` (after line 28):

```python
def _user_condition_slugs(user_id: str) -> list[str]:
    """Lowercased condition names from the user's health profile, used as
    match_knowledge filter_conditions. Best-effort: [] on any failure.

    v1 limitation: matching is exact-on-lowercased-name (e.g. profile "GERD" ->
    'gerd' matches a corpus tag 'gerd'). A mismatch only costs the condition-
    specific boost; untagged general research is always eligible regardless."""
    try:
        row = (supabase.table("health_profile")
               .select("conditions").eq("user_id", user_id)
               .maybe_single().execute()).data
        conds = (row or {}).get("conditions") or []
        return [c["name"].lower() for c in conds
                if isinstance(c, dict) and c.get("name")]
    except Exception as e:  # pragma: no cover - defensive
        logger.error("_user_condition_slugs failed: %s", e, exc_info=True)
        return []


def _research_for(query: str, user_id: str) -> str:
    """Best-effort RAG context block for ``query``. '' on any failure so
    retrieval never blocks the AI call it augments."""
    try:
        conditions = _user_condition_slugs(user_id) or None
        return knowledge.format_context(knowledge.search(query, conditions=conditions))
    except Exception as e:  # pragma: no cover - defensive
        logger.error("_research_for failed: %s", e, exc_info=True)
        return ""
```

- [ ] **Step 4: Wire into the conversation endpoint**

Replace the body tail of `trends_conversation_turn` (currently lines 299-302):

```python
    signals = signal_presenter.load_presented_signals(supabase, user_id)
    health_context = load_health_profile_context(user_id)
    return trends_conversation.generate_turn(
        signals, body.history, health_context=health_context)
```

with:

```python
    signals = signal_presenter.load_presented_signals(supabase, user_id)
    health_context = load_health_profile_context(user_id)
    last_user = next((t.content for t in reversed(body.history) if t.role == "user"), None)
    query = last_user or " ".join(s.category for s in signals[:3]) or "food symptom patterns"
    research_context = _research_for(query, user_id)
    return trends_conversation.generate_turn(
        signals, body.history, health_context=health_context,
        research_context=research_context)
```

- [ ] **Step 5: Wire into the summary endpoint**

Replace the two lines that build the summary (currently lines 420-421):

```python
    health_context = load_health_profile_context(user["id"])
    summary_text = ai_extraction.generate_summary(stats, health_context=health_context)
```

with:

```python
    health_context = load_health_profile_context(user["id"])
    query = " ".join(t["symptom_type"] for t in top_symptoms[:3]) or "food symptom patterns"
    research_context = _research_for(query, user["id"])
    summary_text = ai_extraction.generate_summary(
        stats, health_context=health_context, research_context=research_context)
```

- [ ] **Step 6: Fix the two existing conversation-endpoint tests (deterministic — do this, don't skip)**

Two existing unit tests POST to `/api/trends/conversation` and monkeypatch `generate_turn` with a lambda that has NO `research_context` param. After Task 5 the endpoint (a) passes `research_context=...` → those lambdas raise `TypeError` → 500, and (b) runs `_research_for`, which calls the REAL `litellm.embedding` — a **real, flaky network call** the moment `GEMINI_API_KEY` lands in `.env` at Task 10 (with today's empty key it silently returns `""` and the test still "passes", which is the trap). Neither test even stubs the knowledge client, and `test_trends_auto_analysis_unit.py` doesn't stub `trends_module.supabase` either, so `_user_condition_slugs` would hit **prod Supabase**. Fix both deterministically — never rely on the empty-key degradation.

**`tests/test_trends_conversation_endpoint_unit.py`** → in `test_conversation_endpoint_returns_reply`, replace the `generate_turn` monkeypatch and add a `_research_for` stub:

```python
    monkeypatch.setattr(
        trends_module.trends_conversation, "generate_turn",
        lambda signals, history, health_context="", research_context="":
            TrendsConversationResponse(reply="hi", is_closing=False),
    )
    monkeypatch.setattr(trends_module, "_research_for", lambda query, user_id: "")
```

**`tests/test_trends_auto_analysis_unit.py`** → in `test_conversation_first_turn_refreshes_but_later_turns_dont`, widen the `generate_turn` lambda (lines 87-89) and add the stub:

```python
    monkeypatch.setattr(trends_module.trends_conversation, "generate_turn",
                        lambda signals, history, health_context="", research_context="":
                            TrendsConversationResponse(reply="hi"))
    monkeypatch.setattr(trends_module, "_research_for", lambda query, user_id: "")
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd hearty-api && .venv/bin/pytest tests/test_research_orchestration_unit.py tests/test_trends_conversation_endpoint_unit.py tests/test_trends_auto_analysis_unit.py -v`
Expected: PASS — new orchestration tests pass and both patched endpoint tests stay green with **no network call** (the `_research_for` stub guarantees determinism). `tests/test_api.py::test_get_summary_week` is a separate live-server integration test (httpx against `api_base`) — it already exercises the real LLM and is out of scope for the unit suite.

- [ ] **Step 8: Commit**

```bash
git add hearty-api/app/routers/trends.py hearty-api/tests/test_research_orchestration_unit.py \
        hearty-api/tests/test_trends_conversation_endpoint_unit.py \
        hearty-api/tests/test_trends_auto_analysis_unit.py
git commit -m "feat(rag): orchestrate retrieval into conversation + summary endpoints"
```

---

### Task 6: Admin knowledge CRUD endpoints

**Files:**
- Modify: `hearty-api/app/routers/admin.py` (import ~10; models ~57-73; endpoints after line 191)
- Test: `hearty-api/tests/test_admin_knowledge_unit.py`

- [ ] **Step 1: Write the failing test**

```python
from fastapi.testclient import TestClient
from app.main import app
from app.auth import get_current_admin
from app.routers import admin as adm


def _admin():
    app.dependency_overrides[get_current_admin] = lambda: {"id": "admin1", "email": "o"}


def test_add_knowledge(monkeypatch):
    _admin()
    calls = {}
    monkeypatch.setattr(adm.knowledge, "add_entry",
                        lambda **k: (calls.update(k) or {"id": "kb1", "title": k.get("title")}))
    r = TestClient(app).post("/api/admin/knowledge",
                             json={"title": "T", "content": "body", "conditions": ["gerd"]})
    assert r.status_code == 200 and r.json()["id"] == "kb1"
    assert calls["content"] == "body" and calls["conditions"] == ["gerd"]
    app.dependency_overrides.clear()


def test_add_knowledge_embedding_error_returns_502(monkeypatch):
    _admin()

    def boom(**k): raise RuntimeError("no api key")
    monkeypatch.setattr(adm.knowledge, "add_entry", boom)
    r = TestClient(app).post("/api/admin/knowledge", json={"content": "body"})
    assert r.status_code == 502
    app.dependency_overrides.clear()


def test_list_knowledge(monkeypatch):
    _admin()
    monkeypatch.setattr(adm.knowledge, "list_entries", lambda: [{"id": "kb1", "title": "T"}])
    r = TestClient(app).get("/api/admin/knowledge")
    assert r.json()["entries"][0]["id"] == "kb1"
    app.dependency_overrides.clear()


def test_delete_knowledge(monkeypatch):
    _admin()
    seen = {}
    monkeypatch.setattr(adm.knowledge, "delete_entry", lambda i: seen.update(id=i))
    r = TestClient(app).delete("/api/admin/knowledge/kb9")
    assert r.status_code == 200 and seen["id"] == "kb9"
    app.dependency_overrides.clear()


def test_patch_knowledge_toggles_active(monkeypatch):
    _admin()
    seen = {}
    monkeypatch.setattr(adm.knowledge, "set_active",
                        lambda i, a: (seen.update(id=i, active=a) or {"id": i, "active": a}))
    r = TestClient(app).patch("/api/admin/knowledge/kb9", json={"active": False})
    assert r.json()["active"] is False and seen["active"] is False
    app.dependency_overrides.clear()


def test_knowledge_admin_required():
    assert TestClient(app).get("/api/admin/knowledge").status_code in (401, 403)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd hearty-api && .venv/bin/pytest tests/test_admin_knowledge_unit.py -v`
Expected: FAIL — `AttributeError: module 'app.routers.admin' has no attribute 'knowledge'` / 404 on the new routes.

- [ ] **Step 3: Add the import**

Add to the imports near the top of `admin.py` (after line 10 `from app.auth import get_current_admin`):

```python
from app.services import knowledge
```

- [ ] **Step 4: Add the request models**

After the existing `SettingsUpdate` model (line 73):

```python
class KnowledgeCreate(BaseModel):
    title: str | None = None
    content: str
    conditions: list[str] = []
    source: str = "manual"


class KnowledgeActive(BaseModel):
    active: bool
```

- [ ] **Step 5: Add the endpoints**

At the end of `admin.py` (after the `llm_test` endpoint, line 191):

```python
@router.post("/api/admin/knowledge")
async def add_knowledge(body: KnowledgeCreate, admin=Depends(get_current_admin)) -> dict:
    try:
        return knowledge.add_entry(
            title=body.title, content=body.content,
            conditions=body.conditions, source=body.source)
    except Exception as e:  # embedding/insert failure — tell the owner cleanly
        raise HTTPException(status_code=502, detail=f"embedding failed: {str(e)[:200]}")


@router.get("/api/admin/knowledge")
async def list_knowledge(admin=Depends(get_current_admin)) -> dict:
    return {"entries": knowledge.list_entries()}


@router.delete("/api/admin/knowledge/{entry_id}")
async def delete_knowledge(entry_id: str, admin=Depends(get_current_admin)) -> dict:
    knowledge.delete_entry(entry_id)
    return {"ok": True}


@router.patch("/api/admin/knowledge/{entry_id}")
async def patch_knowledge(entry_id: str, body: KnowledgeActive,
                          admin=Depends(get_current_admin)) -> dict:
    return knowledge.set_active(entry_id, body.active)
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `cd hearty-api && .venv/bin/pytest tests/test_admin_knowledge_unit.py tests/test_admin_endpoints_unit.py -v`
Expected: PASS (6 new + existing admin tests green).

- [ ] **Step 7: Commit**

```bash
git add hearty-api/app/routers/admin.py hearty-api/tests/test_admin_knowledge_unit.py
git commit -m "feat(rag): admin knowledge CRUD endpoints"
```

- [ ] **Step 8: Run the full backend suite**

Run: `cd hearty-api && .venv/bin/pytest -q`
Expected: PASS (whole suite green). Fix any regression before moving to the web tasks.

---

### Task 7: Web — knowledge types + API client methods

**Files:**
- Modify: `hearty-web/src/types/api.ts` (append types)
- Modify: `hearty-web/src/lib/api.ts` (type import + 4 methods)

- [ ] **Step 1: Add the TypeScript types**

Append to `hearty-web/src/types/api.ts`:

```typescript
export interface KnowledgeEntry {
  id: string;
  title: string | null;
  source: string;
  conditions: string[];
  active: boolean;
  created_at: string;
}
export interface KnowledgeListResponse { entries: KnowledgeEntry[] }
export interface CreateKnowledgeRequest {
  title?: string;
  content: string;
  conditions: string[];
  source?: string;
}
```

- [ ] **Step 2: Add the client methods**

In `hearty-web/src/lib/api.ts`, add `KnowledgeEntry`, `KnowledgeListResponse`, `CreateKnowledgeRequest` to the existing type import from `@/types/api` (or `../types/api` — match the file's existing import path). Then add these methods inside the object returned by `createApiClient`, next to the other admin methods (`getHealth`, `testLlm`):

```typescript
    getKnowledge: () => request<KnowledgeListResponse>(`/api/admin/knowledge`),
    createKnowledge: (body: CreateKnowledgeRequest) =>
      request<KnowledgeEntry>(`/api/admin/knowledge`, { method: "POST", body: JSON.stringify(body) }),
    deleteKnowledge: (id: string) =>
      request<unknown>(`/api/admin/knowledge/${id}`, { method: "DELETE" }),
    setKnowledgeActive: (id: string, active: boolean) =>
      request<KnowledgeEntry>(`/api/admin/knowledge/${id}`, { method: "PATCH", body: JSON.stringify({ active }) }),
```

- [ ] **Step 3: Verify type-check passes**

Run: `cd hearty-web && npm run build`
Expected: build succeeds (no TS errors). This is the type-check gate for the new methods/types before they're consumed.

- [ ] **Step 4: Commit**

```bash
git add hearty-web/src/types/api.ts hearty-web/src/lib/api.ts
git commit -m "feat(rag): web knowledge types + api client methods"
```

---

### Task 8: Web — knowledge React Query hooks

**Files:**
- Modify: `hearty-web/src/hooks/useAdmin.ts` (type import + 2 hooks)

- [ ] **Step 1: Add the hooks**

Add `CreateKnowledgeRequest` to the existing `import type { ... } from "@/types/api";` line, then append to `hearty-web/src/hooks/useAdmin.ts`:

```typescript
export function useKnowledge() {
  return useQuery({
    queryKey: ["admin", "knowledge"],
    queryFn: () => api.getKnowledge(),
    staleTime: 30_000,
  });
}

export function useKnowledgeActions() {
  const qc = useQueryClient();
  const invalidate = () => qc.invalidateQueries({ queryKey: ["admin", "knowledge"] });
  const create = useMutation({ mutationFn: (b: CreateKnowledgeRequest) => api.createKnowledge(b), onSuccess: invalidate });
  const remove = useMutation({ mutationFn: (id: string) => api.deleteKnowledge(id), onSuccess: invalidate });
  const setActive = useMutation({ mutationFn: ({ id, active }: { id: string; active: boolean }) => api.setKnowledgeActive(id, active), onSuccess: invalidate });
  return { create, remove, setActive };
}
```

- [ ] **Step 2: Verify type-check passes**

Run: `cd hearty-web && npm run build`
Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add hearty-web/src/hooks/useAdmin.ts
git commit -m "feat(rag): web useKnowledge + useKnowledgeActions hooks"
```

---

### Task 9: Web — Knowledge base panel on `/admin`

**Files:**
- Modify: `hearty-web/src/pages/Admin.tsx` (import + `KnowledgeBase` component + render)
- Test: `hearty-web/src/pages/Admin.test.tsx` (add one test)

- [ ] **Step 1: Write the failing test**

Append this test to `hearty-web/src/pages/Admin.test.tsx`:

```typescript
test("knowledge base lists entries and adds one", async () => {
  let created: unknown = null;
  server.use(
    http.get("*/api/admin/users", () => HttpResponse.json({ users: [] })),
    http.get("*/api/admin/settings", () => HttpResponse.json({ provisioning_mode: "open", trial_days: 14 })),
    http.get("*/api/admin/health", () => HttpResponse.json({
      backend: { status: "ok", version: "1", revision: "r", time: "2026-06-25T00:00:00Z" },
      supabase: { status: "ok", latency_ms: 5 }, llm: { status: "idle" },
    })),
    http.get("*/api/admin/knowledge", () => HttpResponse.json({ entries: [
      { id: "kb1", title: "Low-FODMAP and IBS", source: "manual", conditions: ["ibs"], active: true, created_at: "2026-06-01" },
    ] })),
    http.post("*/api/admin/knowledge", async ({ request }) => {
      created = await request.json();
      return HttpResponse.json({ id: "kb2", title: "New", source: "manual", conditions: [], active: true, created_at: "2026-06-25" });
    }),
  );
  renderWithProviders(<Admin />, { route: "/admin" });
  expect(await screen.findByText(/Low-FODMAP and IBS/)).toBeInTheDocument();
  await userEvent.type(screen.getByLabelText("Content"), "New research excerpt");
  await userEvent.click(screen.getByRole("button", { name: /add entry/i }));
  await vi.waitFor(() => expect(created).toMatchObject({ content: "New research excerpt" }));
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd hearty-web && npm run test -- --run Admin`
Expected: FAIL — `Unable to find a label with the text of: Content` (the panel doesn't exist yet).

- [ ] **Step 3: Add the import**

In `hearty-web/src/pages/Admin.tsx`, extend the `useAdmin` import to include the new hooks and add the type import:

```typescript
import { useAdminUsers, useAdminActions, useAppSettings, useUpdateAppSettings, useHealth, useTestLlm, useKnowledge, useKnowledgeActions } from "../hooks/useAdmin";
```

- [ ] **Step 4: Add the `KnowledgeBase` component**

Add this component to `Admin.tsx` (e.g. just above `export default function Admin()`):

```tsx
function KnowledgeBase() {
  const entries = useKnowledge();
  const actions = useKnowledgeActions();
  const [title, setTitle] = useState("");
  const [content, setContent] = useState("");
  const [conditions, setConditions] = useState("");

  function submit() {
    const conds = conditions.split(",").map((c) => c.trim()).filter(Boolean);
    actions.create.mutate(
      { title: title || undefined, content, conditions: conds },
      { onSuccess: () => { setTitle(""); setContent(""); setConditions(""); } },
    );
  }

  return (
    <div className="rounded-2xl border border-surface-border bg-surface p-4 flex flex-col gap-3">
      <h2 className="font-display text-xl">Knowledge base</h2>
      <p className="text-xs text-text-faint">
        Curated research the AI grounds its explanations in. Untagged entries apply to everyone;
        tag with conditions (comma-separated) to scope to those users.
      </p>

      <div className="flex flex-col gap-2">
        <input aria-label="Title" placeholder="Title (optional)" value={title}
          onChange={(e) => setTitle(e.target.value)}
          className="rounded border border-surface-border bg-background px-2 py-1 text-text" />
        <textarea aria-label="Content" placeholder="Research excerpt" value={content} rows={3}
          onChange={(e) => setContent(e.target.value)}
          className="rounded border border-surface-border bg-background px-2 py-1 text-text" />
        <input aria-label="Conditions" placeholder="Conditions, comma-separated (e.g. gerd, ibs)"
          value={conditions} onChange={(e) => setConditions(e.target.value)}
          className="rounded border border-surface-border bg-background px-2 py-1 text-text" />
        <button disabled={!content || actions.create.isPending} onClick={submit}
          className="self-start rounded px-3 py-1.5 text-sm bg-brand text-black hover:opacity-80 disabled:opacity-40">
          Add entry
        </button>
      </div>
      {actions.create.isError && (
        <p className="text-sm text-accent-red">Failed to add entry (embedding may have failed).</p>
      )}

      {entries.isPending && <p className="text-text-faint text-sm">Loading…</p>}
      {entries.data && entries.data.entries.length === 0 && (
        <p className="text-text-faint text-sm">No entries yet.</p>
      )}
      {entries.data && entries.data.entries.length > 0 && (
        <div className="flex flex-col divide-y divide-surface-border">
          {entries.data.entries.map((e) => (
            <div key={e.id} className="flex items-center justify-between py-2 gap-3">
              <div className="flex flex-col">
                <span className="text-sm text-text">{e.title || "(untitled)"}</span>
                <span className="text-xs text-text-faint">
                  {e.source}{e.conditions.length ? ` · ${e.conditions.join(", ")}` : ""}
                </span>
              </div>
              <div className="flex items-center gap-2">
                <button onClick={() => actions.setActive.mutate({ id: e.id, active: !e.active })}
                  className="rounded px-2 py-0.5 text-xs border border-surface-border text-text-muted hover:text-text">
                  {e.active ? "Active" : "Inactive"}
                </button>
                <button onClick={() => actions.remove.mutate(e.id)}
                  className="rounded px-2 py-0.5 text-xs bg-accent-red text-black hover:opacity-80">
                  Delete
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 5: Render the panel**

In the `Admin()` return, add `<KnowledgeBase />` after `<SignupPolicy />`:

```tsx
      <SystemHealth />
      <SignupPolicy />
      <KnowledgeBase />
```

- [ ] **Step 6: Run the test to verify it passes**

Run: `cd hearty-web && npm run test -- --run Admin`
Expected: PASS — the new test passes and the existing Admin tests stay green. (The pre-existing tests already render `SystemHealth`/`SignupPolicy` without mocking every endpoint; unhandled requests reject and surface as React Query `isError`, not a test failure. `KnowledgeBase` behaves identically.)

- [ ] **Step 7: Run the full web suite + lint + build**

Run: `cd hearty-web && npm run test -- --run && npm run lint && npm run build`
Expected: all green. Fix any failure before finishing.

- [ ] **Step 8: Commit**

```bash
git add hearty-web/src/pages/Admin.tsx hearty-web/src/pages/Admin.test.tsx
git commit -m "feat(rag): Knowledge base admin panel on /admin"
```

---

### Task 10: Deploy + live verification (MANUAL — requires user consent)

> This task performs live, externally-visible actions (adds a secret, applies a prod migration, redeploys Cloud Run). Do NOT run it without explicit user go-ahead. It also needs the user to supply a **Gemini API key** (Google AI Studio — free tier). The pgvector binding is already prod-verified, so no binding check is needed here.

- [ ] **Step 1: Obtain and store the Gemini key**

Ask the user for a `GEMINI_API_KEY` (from Google AI Studio, https://aistudio.google.com/apikey — keys start `AIza...`). Add it to `/home/evan/projects/food-journal-assistant/.env` (gitignored) as `GEMINI_API_KEY=AIza...`. Leave `.env.example`'s existing `GEMINI_API_KEY=` line as-is (already present).

- [ ] **Step 2: Add the key to the redeploy procedure**

In `docs/DEPLOYMENT.md`, add `GEMINI_API_KEY` to the env-file key list in the redeploy procedure (the `--env-vars-file` is full-replace, so every key — now 9 including this one — must be present or the redeploy un-sets it). Commit:

```bash
git add docs/DEPLOYMENT.md
git commit -m "docs(deploy): add GEMINI_API_KEY to redeploy env-file key list (RAG)"
```

- [ ] **Step 3: Apply the migration to prod**

Run from the repo root with the access token + DB password (same pattern used for prior prod migrations):

```bash
cd /home/evan/projects/food-journal-assistant
SUPABASE_ACCESS_TOKEN=$(cat ~/.supabase/access-token) \
SUPABASE_DB_PASSWORD=$(grep -E '^SUPABASE_DB_PASSWORD=' .env | head -1 | cut -d= -f2-) \
supabase db query --linked "$(cat .claude/worktrees/.../supabase/migrations/*_knowledge_base.sql)"
```

(Use the actual path to the `knowledge_base` migration in the worktree, or copy the file into the main checkout's `supabase/migrations/` when the branch merges.) Then verify:

```bash
SUPABASE_ACCESS_TOKEN=$(cat ~/.supabase/access-token) \
SUPABASE_DB_PASSWORD=$(grep -E '^SUPABASE_DB_PASSWORD=' .env | head -1 | cut -d= -f2-) \
supabase db query --linked "select to_regclass('public.knowledge_base') as tbl, (select count(*) from pg_proc where proname='match_knowledge') as fn;"
```

Expected: `tbl` = `knowledge_base`, `fn` = `1`.

- [ ] **Step 4: Redeploy Cloud Run with the full env set**

Build `/tmp/hearty-env.yaml` from `.env` (all 9 keys including `GEMINI_API_KEY`) and deploy per `docs/DEPLOYMENT.md`:

```bash
gcloud run deploy hearty-api --source . --region us-central1 \
  --allow-unauthenticated --memory 1Gi --min-instances 0 --no-cpu-throttling \
  --env-vars-file /tmp/hearty-env.yaml --quiet
shred -u /tmp/hearty-env.yaml
```

- [ ] **Step 5: Seed + verify retrieval**

Via the deployed `/admin` Knowledge base panel, add one untagged entry and one `ibs`-tagged entry. Then:
- Confirm `GET /api/admin/knowledge` lists both.
- Trigger a trends conversation or `/api/summary` and confirm the AI's wording reflects the seeded research.
- Toggle an entry inactive and confirm it drops out of retrieval.
- Confirm an empty/all-inactive corpus still produces a normal AI response (best-effort `""`).

> **This seed is the first time `embeddings.embed` runs for real** — the spike used dummy vectors and the unit tests monkeypatch the response shape, so `resp.data[0]["embedding"]` is only truly verified here. If adding an entry 502s with `KeyError: 'embedding'` (or similar), litellm's `EmbeddingResponse` shape differs from the assumption — fix `embeddings.embed` accordingly (e.g. `resp.data[0].embedding` / `resp["data"][0]["embedding"]`).

- [ ] **Step 6: (Optional) rotate the leaked service key here**

This step is a Cloud Run redeploy — the natural moment to also rotate the `SUPABASE_SERVICE_KEY` that was printed into a session transcript earlier (see the security flag raised during spec review), **if the user opted to rotate**. Rotating the legacy JWT-derived service key means rotating the project JWT secret (also invalidates the anon key) and re-supplying new keys to `.env`, this redeploy's env-file, Vercel, and the phone app — or migrating to Supabase's independently-rotatable secret keys. Skip if the user chose not to rotate.

- [ ] **Step 7: Finish the branch**

Use superpowers:finishing-a-development-branch (push + PR, or merge) per the user's choice.

---

## Self-Review

**1. Spec coverage:**
- §1 Storage (table + RPC + no-index + conditions filter + NOT NULL) → Task 1 ✓
- §2 Embedding service → Task 2 ✓
- §3 Knowledge store (add/search/format_context/list/delete/set_active; error→[]) → Task 3 ✓
- §4 Retrieval wired into both surfaces (research_context param + router orchestration) → Tasks 4, 5 ✓
- §5 Admin CRUD (POST/GET/DELETE/PATCH) → Task 6 ✓; web panel → Tasks 7-9 ✓
- §6 Health-profile scoping (conditions filter + untagged-always-eligible) → Task 1 (SQL) + Task 5 (`_user_condition_slugs`) ✓
- Error handling (best-effort retrieval) → Task 3 `search`, Task 5 `_research_for` ✓
- Security (admin-gated, service-key, GEMINI_API_KEY server-only) → Task 6 (`get_current_admin`), Task 10 ✓
- Testing (backend unit + web Vitest + live) → every task's tests + Task 10 ✓
- Deploy note (GEMINI_API_KEY full-replace) → Task 10 ✓

**2. Placeholder scan:** No TBD/TODO/"handle errors"-style placeholders; every code step shows complete code. The only deliberately abstract spot is Task 10's migration file path (`.../`), because the worktree path and merge target differ — the step explains both resolutions.

**3. Type/name consistency:** `embed` (Task 2) used by `knowledge` (Task 3) and monkeypatched as `knowledge.embed`/`trends`-level via `knowledge.search`. `research_context` param name identical across Tasks 4-5. `match_knowledge` params (`query_embedding`, `match_count`, `filter_conditions`) identical in Task 1 SQL and Task 3 `search`. Web: `KnowledgeEntry`/`KnowledgeListResponse`/`CreateKnowledgeRequest` defined in Task 7, consumed identically in Tasks 8-9. Endpoint paths (`/api/admin/knowledge`, `/{entry_id}`) identical between Task 6 (server) and Task 7 (client). Hook names `useKnowledge`/`useKnowledgeActions` (`create`/`remove`/`setActive`) identical between Tasks 8 and 9.
