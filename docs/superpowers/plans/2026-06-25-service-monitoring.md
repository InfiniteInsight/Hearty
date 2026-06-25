# Service Monitoring v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An on-demand owner "System health" view (backend / Supabase / LLM) on `/admin`, with passive LLM health recorded via a single litellm callback and an owner-triggered LLM test.

**Architecture:** A `service_health` single-row table holds the last LLM ok/error. A global litellm `CustomLogger` callback (registered at startup) records every completion's outcome there — zero per-call-site edits. `GET /api/admin/health` probes backend-self + Supabase live + derives LLM status from the row; `POST /api/admin/health/llm-test` makes one tiny real completion. A React panel renders status pills with Re-check + Test-LLM.

**Tech Stack:** FastAPI + Supabase (service key) + litellm; pytest. React 18 + TanStack Query + Vitest/RTL + MSW.

**Worktree:** `~/.config/superpowers/worktrees/monitoring` (branch `monitoring`, off master @ #18). Run all commands there.

**Spec:** `docs/superpowers/specs/2026-06-25-service-monitoring-design.md`

**Backend test command (use everywhere):**
```bash
cd hearty-api && SUPABASE_URL="http://localhost" SUPABASE_SERVICE_KEY="dummy-key" \
  /home/evan/projects/food-journal-assistant/hearty-api/.venv/bin/python -m pytest -k unit -q
```
Scope to one file by appending its path.

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `supabase/migrations/20260625000000_service_health.sql` | `service_health` table | Create |
| `hearty-api/app/services/llm_health.py` | recorder + litellm `HealthLogger` callback + `register()` | Create |
| `hearty-api/app/main.py` | register the callback at startup | Modify |
| `hearty-api/app/routers/admin.py` | `_llm_status`, `GET /api/admin/health`, `POST /api/admin/health/llm-test` | Modify |
| `hearty-api/tests/test_llm_health_unit.py` | recorder + callback tests | Create |
| `hearty-api/tests/test_health_endpoint_unit.py` | health + llm-test endpoint tests | Create |
| `hearty-web/src/types/api.ts` | health types | Modify |
| `hearty-web/src/lib/api.ts` | `getHealth` / `testLlm` | Modify |
| `hearty-web/src/hooks/useAdmin.ts` | `useHealth` / `useTestLlm` | Modify |
| `hearty-web/src/pages/Admin.tsx` | System health panel | Modify |
| `hearty-web/src/test/msw/handlers.ts` | default health handler | Modify |
| `hearty-web/src/pages/Admin.test.tsx` | panel test | Modify |

---

## Task 1: Migration — `service_health`

**Files:**
- Create: `supabase/migrations/20260625000000_service_health.sql`

- [ ] **Step 1: Write the migration**

```sql
-- Service monitoring: last LLM call outcome (single row), updated by the litellm
-- health callback. Service-key only.
create table if not exists service_health (
  id int primary key default 1 check (id = 1),
  llm_last_ok_at    timestamptz,
  llm_last_error_at timestamptz,
  llm_last_error    text,
  llm_last_model    text,
  updated_at        timestamptz not null default now()
);
alter table service_health enable row level security;
insert into service_health (id) values (1) on conflict (id) do nothing;
```

- [ ] **Step 2: Sanity check (no live apply)**

Run: `grep -c "create table if not exists service_health" supabase/migrations/20260625000000_service_health.sql`
Expected: `1`. Do NOT apply to a live DB (consent-gated deploy step).

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260625000000_service_health.sql
git commit -m "feat(api): service_health table for monitoring"
```

---

## Task 2: LLM health recorder + litellm callback

**Files:**
- Create: `hearty-api/app/services/llm_health.py`
- Modify: `hearty-api/app/main.py`
- Test: `hearty-api/tests/test_llm_health_unit.py`

- [ ] **Step 1: Write the failing tests** — create `hearty-api/tests/test_llm_health_unit.py`:

```python
import types
from app.services import llm_health as lh


class _Tbl:
    def __init__(self, log): self.log = log; self._payload = None
    def update(self, payload): self._payload = payload; return self
    def eq(self, *a, **k): return self
    def execute(self): self.log.append(self._payload); return types.SimpleNamespace(data=[{"id": 1}])


def _fake(log):
    return types.SimpleNamespace(table=lambda n: _Tbl(log))


def test_record_ok_sets_ok_and_model(monkeypatch):
    log = []
    monkeypatch.setattr(lh, "supabase", _fake(log))
    lh.record_llm_ok("claude-sonnet-4-6")
    assert log[0]["llm_last_ok_at"] is not None
    assert log[0]["llm_last_model"] == "claude-sonnet-4-6"
    assert "llm_last_error_at" not in log[0]


def test_record_error_sets_error_truncated(monkeypatch):
    log = []
    monkeypatch.setattr(lh, "supabase", _fake(log))
    lh.record_llm_error("m", "x" * 999)
    assert log[0]["llm_last_error_at"] is not None
    assert len(log[0]["llm_last_error"]) == 500
    assert log[0]["llm_last_model"] == "m"


def test_logger_success_calls_record_ok(monkeypatch):
    seen = {}
    monkeypatch.setattr(lh, "record_llm_ok", lambda model: seen.update({"ok": model}))
    lh.HealthLogger().log_success_event({"model": "mm"}, None, None, None)
    assert seen["ok"] == "mm"


def test_logger_failure_calls_record_error(monkeypatch):
    seen = {}
    monkeypatch.setattr(lh, "record_llm_error", lambda model, error: seen.update({"err": (model, error)}))
    lh.HealthLogger().log_failure_event({"model": "mm", "exception": RuntimeError("boom")}, None, None, None)
    assert seen["err"][0] == "mm" and "boom" in seen["err"][1]


def test_logger_swallows_recorder_exception(monkeypatch):
    def _boom(model): raise RuntimeError("db down")
    monkeypatch.setattr(lh, "record_llm_ok", _boom)
    # must not raise
    lh.HealthLogger().log_success_event({"model": "mm"}, None, None, None)
```

- [ ] **Step 2: Run to verify they fail**

Run (scoped): `... -m pytest tests/test_llm_health_unit.py -q`
Expected: FAIL — module `app.services.llm_health` not found.

- [ ] **Step 3: Implement `llm_health.py`**

```python
import logging
import os
from datetime import datetime, timezone

import litellm
from litellm.integrations.custom_logger import CustomLogger
from supabase import create_client

logger = logging.getLogger(__name__)
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def record_llm_ok(model: str | None) -> None:
    """Stamp the last successful LLM call. Best-effort; the row is seeded (id=1)."""
    supabase.table("service_health").update({
        "llm_last_ok_at": _now_iso(), "llm_last_model": model, "updated_at": _now_iso(),
    }).eq("id", 1).execute()


def record_llm_error(model: str | None, error: str) -> None:
    """Stamp the last failed LLM call (error truncated)."""
    supabase.table("service_health").update({
        "llm_last_error_at": _now_iso(), "llm_last_error": (error or "")[:500],
        "llm_last_model": model, "updated_at": _now_iso(),
    }).eq("id", 1).execute()


class HealthLogger(CustomLogger):
    """Global litellm callback — records every completion's outcome to service_health.
    Wrapped so a recorder failure can never affect the AI call or litellm."""
    def log_success_event(self, kwargs, response_obj, start_time, end_time):
        try:
            record_llm_ok(kwargs.get("model"))
        except Exception as e:
            logger.warning("llm health record (ok) failed: %s", e)

    def log_failure_event(self, kwargs, response_obj, start_time, end_time):
        try:
            record_llm_error(kwargs.get("model"), str(kwargs.get("exception") or response_obj))
        except Exception as e:
            logger.warning("llm health record (error) failed: %s", e)


def register() -> None:
    """Install the callback for all litellm completions (idempotent)."""
    litellm.callbacks = [HealthLogger()]
```

- [ ] **Step 4: Run to verify they pass**

Run (scoped): `... -m pytest tests/test_llm_health_unit.py -q`
Expected: PASS (5 tests).

- [ ] **Step 5: Register at startup in `main.py`**

In `hearty-api/app/main.py`, replace the empty lifespan:
```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    yield
```
with:
```python
@asynccontextmanager
async def lifespan(app: FastAPI):
    from app.services import llm_health
    llm_health.register()
    yield
```
(Import inside the function to keep startup side effects out of module import.)

- [ ] **Step 6: Run the full unit suite**

Run the backend test command (no path). Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add hearty-api/app/services/llm_health.py hearty-api/app/main.py hearty-api/tests/test_llm_health_unit.py
git commit -m "feat(api): passive LLM health via litellm callback + service_health recorder"
```

---

## Task 3: Health endpoints in `admin.py`

**Files:**
- Modify: `hearty-api/app/routers/admin.py`
- Test: `hearty-api/tests/test_health_endpoint_unit.py`

- [ ] **Step 1: Write the failing tests** — create `hearty-api/tests/test_health_endpoint_unit.py`:

```python
import types
from fastapi.testclient import TestClient
from app.main import app
from app.auth import get_current_admin
from app.routers import admin as adm


def _admin():
    app.dependency_overrides[get_current_admin] = lambda: {"id": "admin1", "email": "o"}


class _RowTbl:
    def __init__(self, row, raise_on_exec=False):
        self.row, self.raise_on_exec = row, raise_on_exec
    def select(self, *a, **k): return self
    def eq(self, *a, **k): return self
    def limit(self, *a, **k): return self
    def execute(self):
        if self.raise_on_exec: raise RuntimeError("supabase down")
        return types.SimpleNamespace(data=([self.row] if self.row else []))


def _fake(row=None, raise_on_exec=False):
    return types.SimpleNamespace(table=lambda n: _RowTbl(row, raise_on_exec))


def test_health_requires_admin():
    assert TestClient(app).get("/api/admin/health").status_code in (401, 403)


def test_health_ok_with_active_llm(monkeypatch):
    _admin()
    monkeypatch.setattr(adm, "supabase", _fake(row={
        "id": 1, "llm_last_ok_at": "2026-06-25T10:00:00+00:00",
        "llm_last_error_at": None, "llm_last_error": None, "llm_last_model": "m"}))
    r = TestClient(app).get("/api/admin/health")
    assert r.status_code == 200
    b = r.json()
    assert b["backend"]["status"] == "ok" and "revision" in b["backend"]
    assert b["supabase"]["status"] == "ok" and isinstance(b["supabase"]["latency_ms"], int)
    assert b["llm"]["status"] == "ok"
    app.dependency_overrides.clear()


def test_health_supabase_down_still_200(monkeypatch):
    _admin()
    monkeypatch.setattr(adm, "supabase", _fake(raise_on_exec=True))
    r = TestClient(app).get("/api/admin/health")
    assert r.status_code == 200
    assert r.json()["supabase"]["status"] == "down"
    assert r.json()["llm"]["status"] == "idle"
    app.dependency_overrides.clear()


def test_llm_status_derivation():
    assert adm._llm_status(None)["status"] == "idle"
    assert adm._llm_status({"llm_last_ok_at": "2026-06-25T10:00:00+00:00"})["status"] == "ok"
    degraded = adm._llm_status({
        "llm_last_ok_at": "2026-06-25T10:00:00+00:00",
        "llm_last_error_at": "2026-06-25T11:00:00+00:00", "llm_last_error": "boom"})
    assert degraded["status"] == "degraded" and degraded["last_error"] == "boom"


def test_llm_test_success(monkeypatch):
    _admin()
    monkeypatch.setattr(adm.litellm, "completion", lambda **k: types.SimpleNamespace())
    r = TestClient(app).post("/api/admin/health/llm-test")
    assert r.status_code == 200 and r.json()["ok"] is True
    app.dependency_overrides.clear()


def test_llm_test_failure_reports_error(monkeypatch):
    _admin()
    def _boom(**k): raise RuntimeError("provider 500")
    monkeypatch.setattr(adm.litellm, "completion", _boom)
    r = TestClient(app).post("/api/admin/health/llm-test")
    assert r.status_code == 200 and r.json()["ok"] is False and "provider 500" in r.json()["error"]
    app.dependency_overrides.clear()
```

- [ ] **Step 2: Run to verify they fail**

Run (scoped): `... -m pytest tests/test_health_endpoint_unit.py -q`
Expected: FAIL — routes 404 / `_llm_status` not defined.

- [ ] **Step 3: Implement in `admin.py`**

Add `import time` and `import litellm` to the top imports of `hearty-api/app/routers/admin.py` (next to `import os`).

Add this helper near `_effective_status`:
```python
def _parse_ts(ts):
    return datetime.fromisoformat(str(ts).replace("Z", "+00:00")) if ts else None


def _llm_status(row: dict | None) -> dict:
    """Derive LLM health from the service_health row: ok / degraded / idle."""
    row = row or {}
    ok_at, err_at = row.get("llm_last_ok_at"), row.get("llm_last_error_at")
    out = {"last_ok_at": ok_at, "last_error_at": err_at, "last_error": None,
           "model": row.get("llm_last_model")}
    if not ok_at and not err_at:
        out["status"] = "idle"
        return out
    okd, errd = _parse_ts(ok_at), _parse_ts(err_at)
    if errd and (not okd or errd > okd):
        out["status"] = "degraded"
        out["last_error"] = row.get("llm_last_error")
    else:
        out["status"] = "ok"
    return out
```

Add the two endpoints (after the settings endpoints):
```python
@router.get("/api/admin/health")
async def health(admin=Depends(get_current_admin)) -> dict:
    backend = {"status": "ok", "version": "1.0.0",
               "revision": os.environ.get("K_REVISION", "local"), "time": _now()}
    t0 = time.monotonic()
    try:
        rows = supabase.table("service_health").select("*").eq("id", 1).limit(1).execute().data or []
        sb = {"status": "ok", "latency_ms": round((time.monotonic() - t0) * 1000)}
        llm = _llm_status(rows[0] if rows else None)
    except Exception as e:  # dependency down must not 500 the health check
        sb = {"status": "down", "error": str(e)[:300]}
        llm = _llm_status(None)
    return {"backend": backend, "supabase": sb, "llm": llm}


@router.post("/api/admin/health/llm-test")
async def llm_test(admin=Depends(get_current_admin)) -> dict:
    model = os.environ.get("LLM_MODEL", "claude-sonnet-4-6")
    t0 = time.monotonic()
    try:
        litellm.completion(model=model, messages=[{"role": "user", "content": "ping"}], max_tokens=1)
        return {"ok": True, "model": model, "latency_ms": round((time.monotonic() - t0) * 1000)}
    except Exception as e:  # the global callback records the failure; report it cleanly
        return {"ok": False, "model": model, "error": str(e)[:300]}
```

- [ ] **Step 4: Run to verify they pass**

Run (scoped): `... -m pytest tests/test_health_endpoint_unit.py -q`
Expected: PASS (7 tests).

- [ ] **Step 5: Run the full unit suite**

Run the backend test command. Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add hearty-api/app/routers/admin.py hearty-api/tests/test_health_endpoint_unit.py
git commit -m "feat(api): GET /api/admin/health + POST /api/admin/health/llm-test"
```

---

## Task 4: Web — System health panel

**Files:**
- Modify: `hearty-web/src/types/api.ts`, `src/lib/api.ts`, `src/hooks/useAdmin.ts`, `src/pages/Admin.tsx`, `src/test/msw/handlers.ts`
- Test: `hearty-web/src/pages/Admin.test.tsx`

- [ ] **Step 1: Add types** — append to `hearty-web/src/types/api.ts`:

```typescript
export interface BackendHealth { status: string; version: string; revision: string; time: string }
export interface SupabaseHealth { status: string; latency_ms?: number; error?: string }
export interface LlmHealth {
  status: "ok" | "degraded" | "idle";
  last_ok_at?: string | null; last_error_at?: string | null; last_error?: string | null; model?: string | null;
}
export interface HealthStatus { backend: BackendHealth; supabase: SupabaseHealth; llm: LlmHealth }
export interface LlmTestResult { ok: boolean; model: string; latency_ms?: number; error?: string }
```

- [ ] **Step 2: Add API methods** — in `hearty-web/src/lib/api.ts`, add `HealthStatus, LlmTestResult` to the `@/types/api` type import, then add inside the client object (after `updateAppSettings`):

```typescript
    getHealth: () => request<HealthStatus>(`/api/admin/health`),
    testLlm: () => request<LlmTestResult>(`/api/admin/health/llm-test`, { method: "POST" }),
```

- [ ] **Step 3: Add hooks** — in `hearty-web/src/hooks/useAdmin.ts`, add `HealthStatus` to the type import and append:

```typescript
export function useHealth() {
  return useQuery({ queryKey: ["admin", "health"], queryFn: () => api.getHealth() });
}

export function useTestLlm() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: () => api.testLlm(),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin", "health"] }),
  });
}
```

- [ ] **Step 4: Default MSW handler** — in `hearty-web/src/test/msw/handlers.ts`, add to the `handlers` array:

```typescript
  http.get("*/api/admin/health", () => HttpResponse.json({
    backend: { status: "ok", version: "1.0.0", revision: "local", time: "2026-06-25T00:00:00Z" },
    supabase: { status: "ok", latency_ms: 12 },
    llm: { status: "idle", model: null },
  })),
```

- [ ] **Step 5: Write the panel test** — append to `hearty-web/src/pages/Admin.test.tsx`:

```typescript
test("shows system health and runs an LLM test", async () => {
  let tested = false;
  server.use(
    http.get("*/api/admin/users", () => HttpResponse.json({ users: [] })),
    http.get("*/api/admin/health", () => HttpResponse.json({
      backend: { status: "ok", version: "1.0.0", revision: "r1", time: "2026-06-25T00:00:00Z" },
      supabase: { status: "down", error: "timeout" },
      llm: { status: "degraded", last_error: "boom", model: "m" },
    })),
    http.post("*/api/admin/health/llm-test", () => { tested = true; return HttpResponse.json({ ok: true, model: "m", latency_ms: 9 }); }),
  );
  renderWithProviders(<Admin />, { route: "/admin" });
  expect(await screen.findByText(/system health/i)).toBeInTheDocument();
  expect(await screen.findByText(/down/i)).toBeInTheDocument();   // supabase down pill
  await userEvent.click(screen.getByRole("button", { name: /test llm/i }));
  await vi.waitFor(() => expect(tested).toBe(true));
});
```

- [ ] **Step 6: Run the web test to verify it fails**

Run: `cd hearty-web && npm run test -- --run src/pages/Admin.test.tsx`
Expected: FAIL — no "System health".

- [ ] **Step 7: Add the panel to `Admin.tsx`** — extend the hook import to include `useHealth, useTestLlm`, and add `HealthStatus`-driven UI. Add this component above `export default function Admin()`:

```tsx
function pillClass(status: string): string {
  if (status === "ok") return "bg-good/15 text-good";
  if (status === "idle") return "bg-warn/15 text-warn";
  return "bg-accent-red/15 text-accent-red"; // down / degraded
}

function SystemHealth() {
  const health = useHealth();
  const test = useTestLlm();
  const h = health.data;
  return (
    <div className="rounded-2xl border border-surface-border bg-surface p-4 flex flex-col gap-3">
      <div className="flex items-center justify-between">
        <h2 className="font-display text-xl">System health</h2>
        <div className="flex gap-2">
          <button onClick={() => health.refetch()} disabled={health.isFetching}
            className="rounded px-3 py-1 text-xs border border-surface-border text-text-muted hover:text-text disabled:opacity-40">
            Re-check
          </button>
          <button onClick={() => test.mutate()} disabled={test.isPending}
            className="rounded px-3 py-1 text-xs bg-brand text-black hover:opacity-80 disabled:opacity-40">
            {test.isPending ? "Testing…" : "Test LLM"}
          </button>
        </div>
      </div>
      {health.isPending && <p className="text-text-faint text-sm">Checking…</p>}
      {health.isError && <p className="text-accent-red text-sm">Couldn't load health.</p>}
      {h && (
        <div className="flex flex-col divide-y divide-surface-border">
          <HealthRow label="Backend" status={h.backend.status} detail={`rev ${h.backend.revision} · v${h.backend.version}`} />
          <HealthRow label="Database" status={h.supabase.status}
            detail={h.supabase.status === "ok" ? `${h.supabase.latency_ms} ms` : (h.supabase.error ?? "")} />
          <HealthRow label="AI / LLM" status={h.llm.status}
            detail={h.llm.status === "degraded" ? (h.llm.last_error ?? "") :
                    h.llm.status === "idle" ? "no recent calls" : `last ok · ${h.llm.model ?? ""}`} />
        </div>
      )}
      {test.isError && <p className="text-accent-red text-sm">LLM test failed.</p>}
      {test.data && (
        <p className={`text-sm ${test.data.ok ? "text-good" : "text-accent-red"}`}>
          {test.data.ok ? `LLM ok (${test.data.latency_ms} ms)` : `LLM test failed: ${test.data.error}`}
        </p>
      )}
    </div>
  );
}

function HealthRow({ label, status, detail }: { label: string; status: string; detail: string }) {
  return (
    <div className="flex items-center justify-between py-2">
      <span className="text-sm text-text">{label}</span>
      <div className="flex items-center gap-3">
        <span className="text-xs text-text-muted">{detail}</span>
        <span className={`rounded-full px-2 py-0.5 text-xs font-medium ${pillClass(status)}`}>{status}</span>
      </div>
    </div>
  );
}
```

Update the import line at the top of `Admin.tsx`:
```typescript
import { useAdminUsers, useAdminActions, useAppSettings, useUpdateAppSettings, useHealth, useTestLlm } from "../hooks/useAdmin";
```
Render `<SystemHealth />` right after the `<h1>Subscribers</h1>` line (above `<SignupPolicy />`).

- [ ] **Step 8: Run web test to verify it passes**

Run: `cd hearty-web && npm run test -- --run src/pages/Admin.test.tsx`
Expected: PASS.

- [ ] **Step 9: Full web gate**

Run: `cd hearty-web && npm run test -- --run && npm run lint && npm run build`
Expected: all green.

- [ ] **Step 10: Commit**

```bash
git add hearty-web/src/types/api.ts hearty-web/src/lib/api.ts hearty-web/src/hooks/useAdmin.ts hearty-web/src/pages/Admin.tsx hearty-web/src/pages/Admin.test.tsx hearty-web/src/test/msw/handlers.ts
git commit -m "feat(web): admin System health panel"
```

---

## Task 5: Deploy wiring (manual — after merge, consent-gated)

Not a code task.

- [ ] Apply the migration to prod: `supabase db push` (link + `SUPABASE_DB_PASSWORD` from `/home/evan/projects/food-journal-assistant/.env`).
- [ ] Redeploy the backend from master (`docs/DEPLOYMENT.md` command) — picks up the callback + endpoints; Cloud Run sets `K_REVISION` automatically. No new env vars.
- [ ] Verify: open `/admin` on the web → System health shows Backend ok (revision), Database ok + latency, AI/LLM idle; click **Test LLM** → turns ok. Or: `curl -s -H "Authorization: Bearer <admin-jwt>" https://hearty-api-5aclgyfsva-uc.a.run.app/api/admin/health`.

---

## Self-Review (completed by plan author)

- **Spec coverage:** `service_health` table (T1); recorder + global litellm callback + startup registration (T2); `GET /api/admin/health` (backend self + Supabase live probe + LLM derivation) and `POST .../llm-test` (T3); web System health panel with Re-check + Test-LLM (T4); deploy wiring (T5). Forward-compat (history/usage) is spec-noted, not built — correct for v1. ✓
- **Placeholder scan:** none — every code step has full code; T5 steps are concrete. ✓
- **Type/name consistency:** `service_health` columns (`llm_last_ok_at/llm_last_error_at/llm_last_error/llm_last_model`) consistent across T1–T3; `record_llm_ok/record_llm_error/HealthLogger/register` (T2) match `main.py` + tests; `_llm_status` shape (`status/last_ok_at/last_error_at/last_error/model`) matches the web `LlmHealth` type (T4); `getHealth/testLlm/useHealth/useTestLlm/HealthStatus/LlmTestResult` consistent across T4. Endpoint paths `/api/admin/health` + `/api/admin/health/llm-test` consistent backend↔web. ✓
- **Note:** the Supabase probe selects from `service_health`, so in any environment the migration must be applied before the endpoint reports `supabase: ok` (else it reports `down` — correct behavior, flagged for T5 ordering).
