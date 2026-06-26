# Prompt Overlays Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the owner tune the tone/guidance of Hearty's two AI surfaces (weekly summary + monthly trends conversation) from `/admin` via a safe "guidance overlay" layered onto locked core prompts, with version history + one-click revert.

**Architecture:** Two Supabase tables (`prompt_overlays` current value per surface + `prompt_overlay_versions` append-only history). A best-effort `prompt_overlays` service. A `style_overlay` param threaded into `build_system_prompt`/`generate_turn`/`generate_summary`, appended **before** `health_context`/`research_context` (so the locked core — JSON schema + no-diagnosis guardrail — always wins). The `trends.py` router loads the overlay and passes it (mirrors the RAG `_research_for` pattern). Admin CRUD + a "Prompt tuning" `/admin` panel.

**Tech Stack:** FastAPI (Python), Supabase Postgres, litellm, React 19 + TanStack Query v5 + Vitest/RTL/MSW.

**Spec:** `docs/superpowers/specs/2026-06-26-prompt-overlays-design.md`

**Worktree:** `~/.config/superpowers/worktrees/prompt-overlays` (branch `prompt-overlays`, off master). Backend tests in this worktree (no local `.venv`): from `hearty-api/`, run `set -a; source /home/evan/projects/food-journal-assistant/.env; set +a` then `/home/evan/projects/food-journal-assistant/hearty-api/.venv/bin/python -m pytest <paths> -q`. Web: `cd hearty-web && npm install` (fresh worktree) then `npm run test -- --run`.

**Key existing signatures (post-RAG, verified on master):**
- `trends_conversation.build_system_prompt(signals, health_context="", research_context="")` — appends `health_context` then `research_context`, then `return prompt`.
- `trends_conversation.generate_turn(signals, history, health_context="", research_context="")` — builds the system message via `build_system_prompt(signals, health_context, research_context)`.
- `ai_extraction.generate_summary(stats, health_context="", research_context="")` — appends `health_context` then `research_context`.
- `trends.py` imports `knowledge` in the `from app.services import (...)` block, has `_research_for`, and wires `research_context` into the conversation endpoint (`trends_conversation_turn`) and summary endpoint (`get_summary`).

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `supabase/migrations/<ts>_prompt_overlays.sql` | `prompt_overlays` + `prompt_overlay_versions` tables + seed | 1 |
| `hearty-api/app/services/prompt_overlays.py` | best-effort get + admin set/list/revert | 2 |
| `hearty-api/app/services/trends_conversation.py` | add `style_overlay` param (modify) | 3 |
| `hearty-api/app/services/ai_extraction.py` | add `style_overlay` param (modify) | 3 |
| `hearty-api/app/routers/trends.py` | load + pass overlay in both endpoints (modify) | 4 |
| `hearty-api/app/routers/admin.py` | overlay CRUD endpoints (modify) | 5 |
| `hearty-web/src/types/api.ts` | overlay TS types (modify) | 6 |
| `hearty-web/src/lib/api.ts` | overlay client methods (modify) | 6 |
| `hearty-web/src/hooks/useAdmin.ts` | overlay hooks (modify) | 7 |
| `hearty-web/src/pages/Admin.tsx` | "Prompt tuning" panel (modify) | 8 |
| live deploy | apply migration + verify | 9 |

---

### Task 1: Migration — `prompt_overlays` + `prompt_overlay_versions`

**Files:**
- Create: `supabase/migrations/<timestamp>_prompt_overlays.sql`

> Migrations don't fit the test-first loop (no local Postgres). Create the file, eyeball it, commit. Do NOT apply to prod here — that's Task 9.

- [ ] **Step 1: Generate the migration file**

Run: `cd ~/.config/superpowers/worktrees/prompt-overlays && supabase migration new prompt_overlays` (or create `supabase/migrations/20260626000000_prompt_overlays.sql` directly — timestamp later than `20260625235623_knowledge_base.sql`).

- [ ] **Step 2: Write the SQL**

```sql
-- Prompt Overlays (Spec 11 Layer 3): owner-editable guidance per AI surface,
-- layered onto locked core prompts. Service-key only (server config, not user data).
create table if not exists prompt_overlays (
  surface     text primary key,            -- 'summary' | 'trends_conversation'
  guidance    text not null default '',    -- the editable overlay block ('' = none)
  updated_at  timestamptz not null default now(),
  updated_by  uuid
);
alter table prompt_overlays enable row level security;
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
alter table prompt_overlay_versions enable row level security;
create index if not exists prompt_overlay_versions_surface_idx
  on prompt_overlay_versions (surface, created_at desc);
```

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/*_prompt_overlays.sql
git commit -m "feat(prompts): prompt_overlays + prompt_overlay_versions migration"
```

---

### Task 2: Service — `prompt_overlays.py`

**Files:**
- Create: `hearty-api/app/services/prompt_overlays.py`
- Test: `hearty-api/tests/test_prompt_overlays_unit.py`

- [ ] **Step 1: Write the failing test**

```python
import types
import pytest
from app.services import prompt_overlays


class _Query:
    def __init__(self, store, table):
        self.store, self.table = store, table
        self._op = None; self._payload = None; self._filters = []; self._order = None
    def select(self, cols): self._op = "select"; return self
    def insert(self, payload): self._op = "insert"; self._payload = payload; return self
    def update(self, payload): self._op = "update"; self._payload = payload; return self
    def eq(self, c, v): self._filters.append((c, v)); return self
    def limit(self, *a, **k): return self
    def order(self, c, desc=False): self._order = (c, desc); return self
    def execute(self):
        self.store["calls"].append((self.table, self._op, self._payload, self._filters, self._order))
        if self._op == "select":
            key = f"{self.table}:rows"
            return types.SimpleNamespace(data=self.store.get(key, []))
        if self._op == "update":
            return types.SimpleNamespace(data=[{"surface": self._filters[0][1], **self._payload}])
        return types.SimpleNamespace(data=[dict(self._payload or {})])  # insert


class _FakeSupabase:
    def __init__(self, store): self.store = store
    def table(self, name): return _Query(self.store, name)


def _setup(monkeypatch, store):
    monkeypatch.setattr(prompt_overlays, "supabase", _FakeSupabase(store))


def test_get_overlay_returns_guidance(monkeypatch):
    _setup(monkeypatch, {"calls": [], "prompt_overlays:rows": [{"guidance": "be warm"}]})
    assert prompt_overlays.get_overlay("summary") == "be warm"


def test_get_overlay_missing_is_empty(monkeypatch):
    _setup(monkeypatch, {"calls": [], "prompt_overlays:rows": []})
    assert prompt_overlays.get_overlay("summary") == ""


def test_get_overlay_swallows_errors(monkeypatch):
    class _Boom:
        def table(self, n): raise RuntimeError("db down")
    monkeypatch.setattr(prompt_overlays, "supabase", _Boom())
    assert prompt_overlays.get_overlay("summary") == ""


def test_set_overlay_appends_version_and_updates(monkeypatch):
    store = {"calls": []}; _setup(monkeypatch, store)
    row = prompt_overlays.set_overlay("summary", "new guidance", "admin1")
    ops = [(t, op) for (t, op, _p, _f, _o) in store["calls"]]
    assert ("prompt_overlay_versions", "insert") in ops
    assert ("prompt_overlays", "update") in ops
    # version insert carries the new guidance + author
    vins = next(p for (t, op, p, _f, _o) in store["calls"]
                if t == "prompt_overlay_versions" and op == "insert")
    assert vins["surface"] == "summary" and vins["guidance"] == "new guidance"
    assert vins["created_by"] == "admin1"
    assert row["guidance"] == "new guidance"


def test_set_overlay_rejects_unknown_surface(monkeypatch):
    _setup(monkeypatch, {"calls": []})
    with pytest.raises(ValueError):
        prompt_overlays.set_overlay("bogus", "x", "admin1")


def test_list_versions_ordered_desc(monkeypatch):
    store = {"calls": [], "prompt_overlay_versions:rows": [{"id": "v1", "guidance": "a"}]}
    _setup(monkeypatch, store)
    out = prompt_overlays.list_versions("summary")
    _t, _op, _p, filters, order = store["calls"][0]
    assert filters == [("surface", "summary")] and order == ("created_at", True)
    assert out[0]["id"] == "v1"


def test_revert_reapplies_version(monkeypatch):
    store = {"calls": [], "prompt_overlay_versions:rows": [{"guidance": "old text"}]}
    _setup(monkeypatch, store)
    prompt_overlays.revert("summary", "v9", "admin1")
    # a new version insert with the reverted guidance happened
    vins = [p for (t, op, p, _f, _o) in store["calls"]
            if t == "prompt_overlay_versions" and op == "insert"]
    assert vins and vins[-1]["guidance"] == "old text"
```

- [ ] **Step 2: Run to verify it fails**

Run: `tests/test_prompt_overlays_unit.py` → FAIL (`ModuleNotFoundError: app.services.prompt_overlays`).

- [ ] **Step 3: Write the implementation**

Create `hearty-api/app/services/prompt_overlays.py`:

```python
"""Server-side prompt overlays (Spec 11 Layer 3).

Owner-editable 'guidance' text layered onto the locked core prompts of Hearty's
AI surfaces. Reads are best-effort: any error or missing row yields '' so a
storage hiccup can never break an AI call. Writes append a version for
history/revert.
"""

import logging
import os
from datetime import datetime, timezone

from supabase import create_client

logger = logging.getLogger(__name__)
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])

SURFACES = ("summary", "trends_conversation")


def get_overlay(surface: str) -> str:
    """Current guidance overlay for a surface. Best-effort: '' on missing/error."""
    try:
        rows = (supabase.table("prompt_overlays")
                .select("guidance").eq("surface", surface).limit(1)
                .execute()).data or []
        return (rows[0].get("guidance") or "") if rows else ""
    except Exception as e:  # never break the AI call this augments
        logger.error("get_overlay(%s) failed: %s", surface, e, exc_info=True)
        return ""


def list_overlays() -> list[dict]:
    return (supabase.table("prompt_overlays")
            .select("surface, guidance, updated_at")
            .execute()).data or []


def set_overlay(surface: str, guidance: str, admin_id) -> dict:
    """Update the current overlay AND append a history version. Raises ValueError
    on an unknown surface."""
    if surface not in SURFACES:
        raise ValueError(f"unknown surface: {surface}")
    supabase.table("prompt_overlay_versions").insert(
        {"surface": surface, "guidance": guidance, "created_by": admin_id}).execute()
    res = (supabase.table("prompt_overlays")
           .update({"guidance": guidance,
                    "updated_at": datetime.now(timezone.utc).isoformat(),
                    "updated_by": admin_id})
           .eq("surface", surface).execute())
    return res.data[0] if res.data else {}


def list_versions(surface: str) -> list[dict]:
    return (supabase.table("prompt_overlay_versions")
            .select("id, surface, guidance, created_at, created_by")
            .eq("surface", surface)
            .order("created_at", desc=True)
            .execute()).data or []


def revert(surface: str, version_id, admin_id) -> dict:
    """Re-apply an old version's guidance as a NEW save (forward history)."""
    rows = (supabase.table("prompt_overlay_versions")
            .select("guidance").eq("id", version_id).limit(1)
            .execute()).data or []
    if not rows:
        raise ValueError("version not found")
    return set_overlay(surface, rows[0]["guidance"], admin_id)
```

- [ ] **Step 4: Run to verify pass**

Run: `tests/test_prompt_overlays_unit.py -v` → 7 passed.

- [ ] **Step 5: Commit**

```bash
git add hearty-api/app/services/prompt_overlays.py hearty-api/tests/test_prompt_overlays_unit.py
git commit -m "feat(prompts): best-effort prompt_overlays store + version/revert"
```

---

### Task 3: `style_overlay` param in both AI surfaces

**Files:**
- Modify: `hearty-api/app/services/trends_conversation.py` (`build_system_prompt` signature + tail; `generate_turn` signature + call)
- Modify: `hearty-api/app/services/ai_extraction.py` (`generate_summary`)
- Test: `hearty-api/tests/test_style_overlay_unit.py`

- [ ] **Step 1: Write the failing test**

```python
import types
from app.services.trends_conversation import build_system_prompt
from app.services import ai_extraction


def test_system_prompt_overlay_before_health_and_research():
    p = build_system_prompt([], health_context="HEALTH", research_context="RESEARCH",
                            style_overlay="OVERLAY")
    assert "OVERLAY" in p
    assert p.index("OVERLAY") < p.index("HEALTH") < p.index("RESEARCH")


def test_system_prompt_empty_overlay_byte_identical():
    assert build_system_prompt([], style_overlay="") == build_system_prompt([])


def test_generate_summary_overlay_before_health(monkeypatch):
    captured = {}

    def fake_completion(model, messages, api_base=None):
        captured["content"] = messages[0]["content"]
        return types.SimpleNamespace(
            choices=[types.SimpleNamespace(message=types.SimpleNamespace(content="ok"))])

    monkeypatch.setattr(ai_extraction.litellm, "completion", fake_completion)
    ai_extraction.generate_summary({"a": 1}, health_context="HEALTH",
                                   style_overlay="OVERLAY")
    assert captured["content"].index("OVERLAY") < captured["content"].index("HEALTH")


def test_generate_summary_empty_overlay_byte_identical(monkeypatch):
    import json
    stats = {"meals_logged": 1}
    expected = ai_extraction.SUMMARY_PROMPT.replace("{stats_json}", json.dumps(stats))
    captured = {}

    def fake_completion(model, messages, api_base=None):
        captured["content"] = messages[0]["content"]
        return types.SimpleNamespace(
            choices=[types.SimpleNamespace(message=types.SimpleNamespace(content="ok"))])

    monkeypatch.setattr(ai_extraction.litellm, "completion", fake_completion)
    ai_extraction.generate_summary(stats, style_overlay="")
    assert captured["content"] == expected
```

- [ ] **Step 2: Run to verify it fails**

Run: `tests/test_style_overlay_unit.py` → FAIL (`build_system_prompt() got an unexpected keyword argument 'style_overlay'`).

- [ ] **Step 3: Modify `trends_conversation.py`**

Change `build_system_prompt` signature (currently `def build_system_prompt(signals: list[PresentedSignal], health_context: str = "", research_context: str = "") -> str:`) to add `style_overlay`:

```python
def build_system_prompt(signals: list[PresentedSignal],
                        health_context: str = "",
                        research_context: str = "",
                        style_overlay: str = "") -> str:
```

Replace the existing append tail:

```python
    if health_context:
        prompt = f"{prompt}\n\n{health_context}"
    if research_context:
        prompt = f"{prompt}\n\n{research_context}"
    return prompt
```

with (overlay first — before health/research):

```python
    if style_overlay:
        prompt = f"{prompt}\n\n{style_overlay}"
    if health_context:
        prompt = f"{prompt}\n\n{health_context}"
    if research_context:
        prompt = f"{prompt}\n\n{research_context}"
    return prompt
```

Change `generate_turn` signature to add `style_overlay: str = ""` and pass it through:

```python
def generate_turn(
    signals: list[PresentedSignal],
    history: list[ConversationTurn],
    health_context: str = "",
    research_context: str = "",
    style_overlay: str = "",
) -> TrendsConversationResponse:
    messages = [{"role": "system",
                 "content": build_system_prompt(signals, health_context, research_context, style_overlay)}]
```

- [ ] **Step 4: Modify `ai_extraction.py`**

Change `generate_summary` signature to add `style_overlay: str = ""`, and insert the overlay append **before** the `health_context` append:

```python
def generate_summary(stats: dict, health_context: str = "",
                     research_context: str = "", style_overlay: str = "") -> str:
```

In the body, the appends become (overlay first):

```python
    prompt = SUMMARY_PROMPT.replace("{stats_json}", json.dumps(stats))
    if style_overlay:
        prompt = f"{prompt}\n\n{style_overlay}"
    if health_context:
        prompt = f"{prompt}\n\n{health_context}"
    if research_context:
        prompt = f"{prompt}\n\n{research_context}"
```

(Leave the docstring + `litellm.completion(...)` + return unchanged.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `tests/test_style_overlay_unit.py tests/test_research_context_unit.py tests/test_summary_health_context_unit.py tests/test_trends_conversation_unit.py -v`
Expected: new tests pass; existing health/research ordering + byte-identity tests stay green (overlay is a new earlier block; it doesn't change health-vs-research order, and empty defaults keep existing callers unaffected).

- [ ] **Step 6: Commit**

```bash
git add hearty-api/app/services/trends_conversation.py hearty-api/app/services/ai_extraction.py hearty-api/tests/test_style_overlay_unit.py
git commit -m "feat(prompts): thread style_overlay (before health/research) into both AI surfaces"
```

---

### Task 4: Orchestrate overlay loading in `trends.py`

**Files:**
- Modify: `hearty-api/app/routers/trends.py` (service import; conversation endpoint; summary endpoint)
- Modify: `hearty-api/tests/test_trends_conversation_endpoint_unit.py` (deterministic stub)
- Modify: `hearty-api/tests/test_trends_auto_analysis_unit.py` (deterministic stub)

- [ ] **Step 1: Add the import**

In `trends.py`, the `from app.services import (...)` block currently ends with `knowledge,`. Add `prompt_overlays`:

```python
from app.services import (
    ai_extraction, trend_engine, signal_engine,
    signal_presenter, trends_conversation, signal_persistence,
    knowledge, prompt_overlays,
)
```

- [ ] **Step 2: Wire the conversation endpoint**

In `trends_conversation_turn`, the tail currently is:

```python
    research_context = _research_for(query, user_id)
    return trends_conversation.generate_turn(
        signals, body.history, health_context=health_context,
        research_context=research_context)
```

Change to:

```python
    research_context = _research_for(query, user_id)
    style_overlay = prompt_overlays.get_overlay("trends_conversation")
    return trends_conversation.generate_turn(
        signals, body.history, health_context=health_context,
        research_context=research_context, style_overlay=style_overlay)
```

(`get_overlay` is already best-effort — returns `""` on any failure.)

- [ ] **Step 3: Wire the summary endpoint**

In `get_summary`, the tail currently is:

```python
    research_context = _research_for(query, user["id"])
    summary_text = ai_extraction.generate_summary(
        stats, health_context=health_context, research_context=research_context)
```

Change to:

```python
    research_context = _research_for(query, user["id"])
    style_overlay = prompt_overlays.get_overlay("summary")
    summary_text = ai_extraction.generate_summary(
        stats, health_context=health_context, research_context=research_context,
        style_overlay=style_overlay)
```

- [ ] **Step 4: Fix the two existing conversation-endpoint tests (deterministic — required)**

After this task the endpoint passes `style_overlay=...` to `generate_turn` (so the monkeypatched lambdas must accept it) and calls `prompt_overlays.get_overlay` (which, unstubbed, makes a REAL Supabase call — `get_overlay` swallows the error to `""` but still does a flaky network round-trip). Stub it deterministically in both tests.

**`tests/test_trends_conversation_endpoint_unit.py`** → in `test_conversation_endpoint_returns_reply`, widen the `generate_turn` lambda and add the stub:

```python
    monkeypatch.setattr(
        trends_module.trends_conversation, "generate_turn",
        lambda signals, history, health_context="", research_context="", style_overlay="":
            TrendsConversationResponse(reply="hi", is_closing=False),
    )
    monkeypatch.setattr(trends_module, "_research_for", lambda query, user_id: "")
    monkeypatch.setattr(trends_module.prompt_overlays, "get_overlay", lambda surface: "")
```

**`tests/test_trends_auto_analysis_unit.py`** → in `test_conversation_first_turn_refreshes_but_later_turns_dont`, same:

```python
    monkeypatch.setattr(trends_module.trends_conversation, "generate_turn",
                        lambda signals, history, health_context="", research_context="", style_overlay="":
                            TrendsConversationResponse(reply="hi"))
    monkeypatch.setattr(trends_module, "_research_for", lambda query, user_id: "")
    monkeypatch.setattr(trends_module.prompt_overlays, "get_overlay", lambda surface: "")
```

- [ ] **Step 5: Run tests**

Run: `tests/test_trends_conversation_endpoint_unit.py tests/test_trends_auto_analysis_unit.py -v`
Expected: PASS with no network call (both lambdas widened, `get_overlay` stubbed).

- [ ] **Step 6: Commit**

```bash
git add hearty-api/app/routers/trends.py \
        hearty-api/tests/test_trends_conversation_endpoint_unit.py \
        hearty-api/tests/test_trends_auto_analysis_unit.py
git commit -m "feat(prompts): load + pass style_overlay in conversation + summary endpoints"
```

---

### Task 5: Admin overlay CRUD endpoints

**Files:**
- Modify: `hearty-api/app/routers/admin.py` (import; models; endpoints)
- Test: `hearty-api/tests/test_admin_prompt_overlays_unit.py`

- [ ] **Step 1: Write the failing test**

```python
from fastapi.testclient import TestClient
from app.main import app
from app.auth import get_current_admin
from app.routers import admin as adm


def _admin():
    app.dependency_overrides[get_current_admin] = lambda: {"id": "admin1", "email": "o"}


def test_list_overlays(monkeypatch):
    _admin()
    monkeypatch.setattr(adm.prompt_overlays, "list_overlays",
                        lambda: [{"surface": "summary", "guidance": "warm", "updated_at": "t"}])
    r = TestClient(app).get("/api/admin/prompt-overlays")
    assert r.status_code == 200 and r.json()["overlays"][0]["surface"] == "summary"
    app.dependency_overrides.clear()


def test_update_overlay(monkeypatch):
    _admin()
    seen = {}
    monkeypatch.setattr(adm.prompt_overlays, "set_overlay",
                        lambda s, g, a: (seen.update(surface=s, guidance=g, admin=a) or
                                         {"surface": s, "guidance": g}))
    r = TestClient(app).put("/api/admin/prompt-overlays/summary", json={"guidance": "be brief"})
    assert r.status_code == 200 and r.json()["guidance"] == "be brief"
    assert seen == {"surface": "summary", "guidance": "be brief", "admin": "admin1"}
    app.dependency_overrides.clear()


def test_update_overlay_unknown_surface_400(monkeypatch):
    _admin()

    def boom(s, g, a): raise ValueError("unknown surface: bogus")
    monkeypatch.setattr(adm.prompt_overlays, "set_overlay", boom)
    r = TestClient(app).put("/api/admin/prompt-overlays/bogus", json={"guidance": "x"})
    assert r.status_code == 400
    app.dependency_overrides.clear()


def test_list_versions(monkeypatch):
    _admin()
    monkeypatch.setattr(adm.prompt_overlays, "list_versions",
                        lambda s: [{"id": "v1", "surface": s, "guidance": "a", "created_at": "t", "created_by": None}])
    r = TestClient(app).get("/api/admin/prompt-overlays/summary/versions")
    assert r.json()["versions"][0]["id"] == "v1"
    app.dependency_overrides.clear()


def test_revert_overlay(monkeypatch):
    _admin()
    seen = {}
    monkeypatch.setattr(adm.prompt_overlays, "revert",
                        lambda s, v, a: (seen.update(surface=s, version=v, admin=a) or
                                         {"surface": s, "guidance": "old"}))
    r = TestClient(app).post("/api/admin/prompt-overlays/summary/revert", json={"version_id": "v9"})
    assert r.status_code == 200 and r.json()["guidance"] == "old"
    assert seen == {"surface": "summary", "version": "v9", "admin": "admin1"}
    app.dependency_overrides.clear()


def test_overlays_admin_required():
    assert TestClient(app).get("/api/admin/prompt-overlays").status_code in (401, 403)
```

- [ ] **Step 2: Run to verify it fails**

Run: `tests/test_admin_prompt_overlays_unit.py` → FAIL (`module 'app.routers.admin' has no attribute 'prompt_overlays'` / 404s).

- [ ] **Step 3: Add the import**

`admin.py` currently has `from app.services import knowledge`. Change to:

```python
from app.services import knowledge, prompt_overlays
```

- [ ] **Step 4: Add the request models**

After the existing `KnowledgeActive` model:

```python
class OverlayUpdate(BaseModel):
    guidance: str


class OverlayRevert(BaseModel):
    version_id: str
```

- [ ] **Step 5: Add the endpoints**

At the end of `admin.py`:

```python
@router.get("/api/admin/prompt-overlays")
async def list_prompt_overlays(admin=Depends(get_current_admin)) -> dict:
    return {"overlays": prompt_overlays.list_overlays()}


@router.put("/api/admin/prompt-overlays/{surface}")
async def update_prompt_overlay(surface: str, body: OverlayUpdate,
                                admin=Depends(get_current_admin)) -> dict:
    try:
        return prompt_overlays.set_overlay(surface, body.guidance, admin["id"])
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))


@router.get("/api/admin/prompt-overlays/{surface}/versions")
async def list_prompt_overlay_versions(surface: str,
                                       admin=Depends(get_current_admin)) -> dict:
    return {"versions": prompt_overlays.list_versions(surface)}


@router.post("/api/admin/prompt-overlays/{surface}/revert")
async def revert_prompt_overlay(surface: str, body: OverlayRevert,
                                admin=Depends(get_current_admin)) -> dict:
    try:
        return prompt_overlays.revert(surface, body.version_id, admin["id"])
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
```

- [ ] **Step 6: Run tests**

Run: `tests/test_admin_prompt_overlays_unit.py tests/test_admin_endpoints_unit.py -v` → all pass.

- [ ] **Step 7: Commit**

```bash
git add hearty-api/app/routers/admin.py hearty-api/tests/test_admin_prompt_overlays_unit.py
git commit -m "feat(prompts): admin prompt-overlay CRUD + versions + revert endpoints"
```

- [ ] **Step 8: Run the full backend unit suite**

Run: from `hearty-api/`, `/home/evan/projects/food-journal-assistant/hearty-api/.venv/bin/python -m pytest -q` (env sourced).
Expected: green (integration tests deselected by `pytest.ini` if PR #22 merged; otherwise run `-m "not integration"` or ignore the live-server files). Fix any regression before the web tasks.

---

### Task 6: Web — overlay types + API client methods

**Files:**
- Modify: `hearty-web/src/types/api.ts`
- Modify: `hearty-web/src/lib/api.ts`

- [ ] **Step 1: Add the TypeScript types**

Append to `hearty-web/src/types/api.ts`:

```typescript
export interface PromptOverlay { surface: string; guidance: string; updated_at: string }
export interface PromptOverlaysResponse { overlays: PromptOverlay[] }
export interface PromptOverlayVersion {
  id: string; surface: string; guidance: string; created_at: string; created_by: string | null;
}
export interface PromptOverlayVersionsResponse { versions: PromptOverlayVersion[] }
```

- [ ] **Step 2: Add the client methods**

Add `PromptOverlay`, `PromptOverlaysResponse`, `PromptOverlayVersionsResponse` to the existing `@/types/api` import in `api.ts`, then add these methods next to the knowledge methods inside `createApiClient`:

```typescript
    getPromptOverlays: () => request<PromptOverlaysResponse>(`/api/admin/prompt-overlays`),
    updatePromptOverlay: (surface: string, guidance: string) =>
      request<PromptOverlay>(`/api/admin/prompt-overlays/${surface}`, { method: "PUT", body: JSON.stringify({ guidance }) }),
    getPromptOverlayVersions: (surface: string) =>
      request<PromptOverlayVersionsResponse>(`/api/admin/prompt-overlays/${surface}/versions`),
    revertPromptOverlay: (surface: string, versionId: string) =>
      request<PromptOverlay>(`/api/admin/prompt-overlays/${surface}/revert`, { method: "POST", body: JSON.stringify({ version_id: versionId }) }),
```

- [ ] **Step 3: Verify type-check**

Run: `cd hearty-web && npm install && npm run build` → succeeds.

- [ ] **Step 4: Commit**

```bash
git add hearty-web/src/types/api.ts hearty-web/src/lib/api.ts
git commit -m "feat(prompts): web prompt-overlay types + api client methods"
```

---

### Task 7: Web — overlay hooks

**Files:**
- Modify: `hearty-web/src/hooks/useAdmin.ts`

- [ ] **Step 1: Add the hooks**

Append to `hearty-web/src/hooks/useAdmin.ts`:

```typescript
export function usePromptOverlays() {
  return useQuery({
    queryKey: ["admin", "prompt-overlays"],
    queryFn: () => api.getPromptOverlays(),
    staleTime: 30_000,
  });
}

export function usePromptOverlayVersions(surface: string, enabled: boolean) {
  return useQuery({
    queryKey: ["admin", "prompt-overlays", surface, "versions"],
    queryFn: () => api.getPromptOverlayVersions(surface),
    enabled,
  });
}

export function usePromptOverlayActions() {
  const qc = useQueryClient();
  const invalidate = () => qc.invalidateQueries({ queryKey: ["admin", "prompt-overlays"] });
  const save = useMutation({
    mutationFn: ({ surface, guidance }: { surface: string; guidance: string }) => api.updatePromptOverlay(surface, guidance),
    onSuccess: invalidate,
  });
  const revert = useMutation({
    mutationFn: ({ surface, versionId }: { surface: string; versionId: string }) => api.revertPromptOverlay(surface, versionId),
    onSuccess: invalidate,
  });
  return { save, revert };
}
```

- [ ] **Step 2: Verify type-check**

Run: `cd hearty-web && npm run build` → succeeds.

- [ ] **Step 3: Commit**

```bash
git add hearty-web/src/hooks/useAdmin.ts
git commit -m "feat(prompts): web usePromptOverlays + versions + actions hooks"
```

---

### Task 8: Web — "Prompt tuning" panel on `/admin`

**Files:**
- Modify: `hearty-web/src/pages/Admin.tsx` (import + `PromptTuning` component + render)
- Test: `hearty-web/src/pages/Admin.test.tsx` (add one test)

- [ ] **Step 1: Write the failing test**

Append to `hearty-web/src/pages/Admin.test.tsx`:

```typescript
test("prompt tuning saves a guidance overlay", async () => {
  let saved: unknown = null;
  server.use(
    http.get("*/api/admin/users", () => HttpResponse.json({ users: [] })),
    http.get("*/api/admin/settings", () => HttpResponse.json({ provisioning_mode: "open", trial_days: 14 })),
    http.get("*/api/admin/health", () => HttpResponse.json({
      backend: { status: "ok", version: "1", revision: "r", time: "2026-06-26T00:00:00Z" },
      supabase: { status: "ok", latency_ms: 5 }, llm: { status: "idle" },
    })),
    http.get("*/api/admin/knowledge", () => HttpResponse.json({ entries: [] })),
    http.get("*/api/admin/prompt-overlays", () => HttpResponse.json({ overlays: [
      { surface: "summary", guidance: "", updated_at: "2026-06-26" },
      { surface: "trends_conversation", guidance: "", updated_at: "2026-06-26" },
    ] })),
    http.put("*/api/admin/prompt-overlays/summary", async ({ request }) => {
      saved = await request.json();
      return HttpResponse.json({ surface: "summary", guidance: "Keep it short.", updated_at: "2026-06-26" });
    }),
  );
  renderWithProviders(<Admin />, { route: "/admin" });
  const box = await screen.findByLabelText("summary overlay");
  await userEvent.type(box, "Keep it short.");
  await userEvent.click(screen.getByRole("button", { name: /save summary/i }));
  await vi.waitFor(() => expect(saved).toMatchObject({ guidance: "Keep it short." }));
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run Admin` → FAIL (`Unable to find a label with the text of: summary overlay`).

- [ ] **Step 3: Add the import**

Extend the `useAdmin` import in `Admin.tsx`:

```typescript
import { useAdminUsers, useAdminActions, useAppSettings, useUpdateAppSettings, useHealth, useTestLlm, useKnowledge, useKnowledgeActions, usePromptOverlays, usePromptOverlayVersions, usePromptOverlayActions } from "../hooks/useAdmin";
```

- [ ] **Step 4: Add the `PromptTuning` component**

Add to `Admin.tsx` (e.g. above `export default function Admin()`):

```tsx
const OVERLAY_SURFACES: { surface: string; label: string; help: string }[] = [
  { surface: "summary", label: "Weekly summary", help: "How Hearty writes your weekly summary." },
  { surface: "trends_conversation", label: "Trends conversation", help: "How Hearty runs the monthly trends check-in." },
];

function OverlayEditor({ surface, label, help }: { surface: string; label: string; help: string }) {
  const overlays = usePromptOverlays();
  const actions = usePromptOverlayActions();
  const current = overlays.data?.overlays.find((o) => o.surface === surface);
  const [text, setText] = useState("");
  const [loaded, setLoaded] = useState(false);
  const [showHistory, setShowHistory] = useState(false);
  const versions = usePromptOverlayVersions(surface, showHistory);
  if (overlays.isSuccess && !loaded) { setText(current?.guidance ?? ""); setLoaded(true); }

  return (
    <div className="flex flex-col gap-2 border-t border-surface-border pt-3 first:border-t-0 first:pt-0">
      <div className="flex items-center justify-between">
        <span className="text-sm text-text">{label}</span>
        <button onClick={() => setShowHistory((v) => !v)}
          className="text-xs text-text-muted hover:text-text">
          {showHistory ? "Hide history" : "History"}
        </button>
      </div>
      <p className="text-xs text-text-faint">{help} The structural rules and the “observations, not diagnoses” guardrail always apply.</p>
      <textarea aria-label={`${surface} overlay`} value={text} rows={3}
        onChange={(e) => setText(e.target.value)}
        placeholder="Optional guidance (tone, emphasis, things to mention or avoid)…"
        className="rounded border border-surface-border bg-background px-2 py-1 text-text" />
      <button disabled={actions.save.isPending}
        onClick={() => actions.save.mutate({ surface, guidance: text })}
        className="self-start rounded px-3 py-1.5 text-sm bg-brand text-black hover:opacity-80 disabled:opacity-40">
        Save {label.toLowerCase()}
      </button>
      {actions.save.isError && <p className="text-sm text-accent-red">Failed to save.</p>}
      {showHistory && versions.data && (
        <div className="flex flex-col divide-y divide-surface-border">
          {versions.data.versions.length === 0 && <p className="text-xs text-text-faint">No history yet.</p>}
          {versions.data.versions.map((v) => (
            <div key={v.id} className="flex items-center justify-between py-1.5 gap-3">
              <span className="text-xs text-text-faint truncate">
                {new Date(v.created_at).toLocaleString()} · {v.guidance ? v.guidance.slice(0, 60) : "(empty)"}
              </span>
              <button onClick={() => actions.revert.mutate({ surface, versionId: v.id }, { onSuccess: () => { setText(v.guidance); } })}
                className="rounded px-2 py-0.5 text-xs border border-surface-border text-text-muted hover:text-text">
                Revert
              </button>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function PromptTuning() {
  return (
    <div className="rounded-2xl border border-surface-border bg-surface p-4 flex flex-col gap-3">
      <h2 className="font-display text-xl">Prompt tuning</h2>
      <p className="text-xs text-text-faint">Tune how Hearty talks. Edits layer on top of the locked core prompts and apply to the next AI call.</p>
      {OVERLAY_SURFACES.map((s) => <OverlayEditor key={s.surface} {...s} />)}
    </div>
  );
}
```

- [ ] **Step 5: Render the panel**

In the `Admin()` return, add `<PromptTuning />` after `<KnowledgeBase />`:

```tsx
      <SignupPolicy />
      <KnowledgeBase />
      <PromptTuning />
```

- [ ] **Step 6: Run the test**

Run: `cd hearty-web && npm run test -- --run Admin` → PASS (new test + existing Admin tests green).

- [ ] **Step 7: Full web suite + lint + build**

Run: `cd hearty-web && npm run test -- --run && npm run lint && npm run build` → all green.

- [ ] **Step 8: Commit**

```bash
git add hearty-web/src/pages/Admin.tsx hearty-web/src/pages/Admin.test.tsx
git commit -m "feat(prompts): Prompt tuning panel on /admin"
```

---

### Task 9: Deploy + live verification (MANUAL — requires user consent)

> Live actions (prod migration + Cloud Run redeploy). Do NOT run without explicit go-ahead. No new env vars are needed (overlays use the existing `SUPABASE_*`).

- [ ] **Step 1: Apply the migration to prod**

From the repo root (same pattern as prior migrations; `db query` needs `-f` because the SQL starts with a comment):

```bash
cd /home/evan/projects/food-journal-assistant
SUPABASE_ACCESS_TOKEN=$(cat ~/.supabase/access-token) \
SUPABASE_DB_PASSWORD=$(grep -E '^SUPABASE_DB_PASSWORD=' .env | head -1 | cut -d= -f2-) \
supabase db query --linked -f <path-to>/supabase/migrations/*_prompt_overlays.sql
```

Then verify:

```bash
SUPABASE_ACCESS_TOKEN=$(cat ~/.supabase/access-token) \
SUPABASE_DB_PASSWORD=$(grep -E '^SUPABASE_DB_PASSWORD=' .env | head -1 | cut -d= -f2-) \
supabase db query --linked "select surface from prompt_overlays order by surface;"
```

Expected: `summary`, `trends_conversation`.

- [ ] **Step 2: Redeploy Cloud Run** (no env changes; ships the new code) per `docs/DEPLOYMENT.md` — build `/tmp/hearty-env.yaml` from `.env` (the full key list) and `gcloud run deploy hearty-api --source . ... --env-vars-file /tmp/hearty-env.yaml`, then `shred -u`.

- [ ] **Step 3: Verify** — on `/admin`, set a small guidance on "Weekly summary" (e.g. "Keep it to 3 sentences and mention hydration when relevant."), trigger a summary, confirm the tone reflects it; check the version appears in History; Revert; confirm an empty overlay is a no-op.

- [ ] **Step 4: Finish the branch** — superpowers:finishing-a-development-branch (push + PR).

---

## Self-Review

**1. Spec coverage:**
- §1 Storage (two tables + seed + RLS) → Task 1 ✓
- §2 Locked core + injection (style_overlay before health/research; empty byte-identical) → Task 3 ✓
- §3 Service (get_overlay best-effort, set_overlay+version, list_versions, revert) → Task 2 ✓
- §4 Router orchestration (load + pass in both endpoints) → Task 4 ✓
- §5 Admin API (list/put/versions/revert, 400 unknown surface) → Task 5 ✓
- §6 Web "Prompt tuning" panel (textarea + save + history + revert) → Tasks 6-8 ✓
- Error handling (best-effort read) → Task 2 `get_overlay` ✓; Security (admin-gated, service-key) → Task 5 ✓
- Testing (service, injection, endpoints incl. the deterministic stub, admin, web) → every task ✓; Live → Task 9 ✓

**2. Placeholder scan:** none — every code step shows complete code; the only abstract token is Task 9's migration path (`<path-to>`), explained in context.

**3. Type/name consistency:** `style_overlay` identical across Tasks 3-4. `get_overlay`/`set_overlay`/`list_overlays`/`list_versions`/`revert` identical between Task 2 (service), Task 4 (router calls `get_overlay`), and Task 5 (admin calls `list_overlays`/`set_overlay`/`list_versions`/`revert`). Surface slugs `"summary"`/`"trends_conversation"` identical across migration seed, `SURFACES`, router calls, and the web `OVERLAY_SURFACES`. Endpoint paths identical between Task 5 (server) and Task 6 (client). Web hook names (`usePromptOverlays`/`usePromptOverlayVersions`/`usePromptOverlayActions` with `save`/`revert`) identical between Tasks 7 and 8. The PUT/revert request bodies (`{guidance}` / `{version_id}`) match between client (Task 6), server models (Task 5), and tests.
