# Service Monitoring v1 — Design

**Status:** Approved (brainstorm 2026-06-25)
**Initiative:** Admin/Owner Dashboard, sub-spec #3 (Service Monitoring). Builds on #15 (admin foundation) + #16 (provisioning).
**Scope:** v1 = **service health** (backend / Supabase / LLM), on-demand, owner-only. Usage/cost, errors, per-user activity, and uptime history are explicit later additions.

## Goal

Give the owner a "is everything up right now?" view inside the existing `/admin` web dashboard, at ≈ zero running cost. Health is computed **on demand** (when the owner opens the panel), not by a background poller — so there's no always-on probe keeping the scale-to-zero backend warm and no synthetic LLM token spend.

## Decisions locked in brainstorming

- **On-demand, not polled.** A `GET /api/admin/health` endpoint probes live when called. (Polling would defeat Cloud Run scale-to-zero and add steady cost — rejected for v1. The probe logic is structured so a future cron can record the same results into a history table without changing it.)
- **LLM health is passive**, recorded from *real* user AI calls — not a synthetic ping per check. Captured via a **single global litellm callback** registered at startup (no per-call-site edits across the ~10 `litellm.completion` sites in 7 files). The per-user-LLM-routing wrapper (#1) is deferred, so a passive callback is the right tool now.
- **Optional owner-triggered active check:** a "Test LLM now" button does **one** tiny real completion on demand (owner-initiated, ~$0) to confirm the LLM works even when traffic is quiet.

## Architecture

### 1. `service_health` table (single row)

```sql
create table if not exists service_health (
  id int primary key default 1 check (id = 1),
  llm_last_ok_at    timestamptz,
  llm_last_error_at timestamptz,
  llm_last_error    text,
  llm_last_model    text,
  updated_at        timestamptz not null default now()
);
alter table service_health enable row level security;   -- no anon/auth policies; service-key only
insert into service_health (id) values (1) on conflict (id) do nothing;
```

### 2. LLM outcome recorder + litellm callback

`hearty-api/app/services/llm_health.py`:
- `record_llm_ok(model: str | None)` — upsert row id=1: set `llm_last_ok_at=now()`, `llm_last_model=model`, `updated_at=now()`.
- `record_llm_error(model: str | None, error: str)` — upsert: set `llm_last_error_at=now()`, `llm_last_error=error[:500]`, `llm_last_model=model`, `updated_at=now()`.
- `class HealthLogger(litellm.integrations.custom_logger.CustomLogger)` implementing:
  - `log_success_event(self, kwargs, response_obj, start_time, end_time)` → `record_llm_ok(kwargs.get("model"))`
  - `log_failure_event(self, kwargs, response_obj, start_time, end_time)` → `record_llm_error(kwargs.get("model"), str(kwargs.get("exception") or response_obj))`
  - Both wrapped in `try/except` (a recorder failure must never affect the AI call or litellm).
- `register()` — `litellm.callbacks = [HealthLogger()]` (idempotent; called once at app startup).

Registered in `app/main.py` (module import or lifespan startup). Fires for **all** `litellm.completion` calls app-wide — zero call-site changes.

### 3. Health probe + endpoints (`app/routers/admin.py`, admin-gated)

`GET /api/admin/health` → builds and returns:
```json
{
  "backend": { "status": "ok", "version": "1.0.0", "revision": "hearty-api-00003-n6t", "time": "<iso>" },
  "supabase": { "status": "ok", "latency_ms": 42 },
  "llm": { "status": "ok", "last_ok_at": "<iso>", "last_error_at": null, "last_error": null, "model": "claude-sonnet-4-6" }
}
```
- **backend:** `status="ok"` (it answered), `version=app.version`, `revision=os.environ.get("K_REVISION","local")` (Cloud Run injects `K_REVISION`), `time=now`.
- **supabase:** time a trivial probe `supabase.table("service_health").select("id").eq("id",1).limit(1).execute()`; `{"status":"ok","latency_ms":N}` on success, `{"status":"down","error":...}` on exception (caught; the endpoint never 500s on a dependency being down).
- **llm:** derive from the `service_health` row:
  - both timestamps null → `"idle"` (no traffic to judge by — amber, not red)
  - `llm_last_ok_at` present and (`llm_last_error_at` null or `ok_at >= error_at`) → `"ok"`
  - else (`error_at > ok_at`) → `"degraded"` (include `last_error`, `model`, `last_error_at`)

`POST /api/admin/health/llm-test` → one tiny real completion:
```python
litellm.completion(model=os.environ.get("LLM_MODEL","claude-sonnet-4-6"),
                   messages=[{"role":"user","content":"ping"}], max_tokens=1)
```
The global callback records the outcome automatically. Returns `{"ok": true, "model": ..., "latency_ms": N}` or `{"ok": false, "error": ...}` (wrapped in try/except so a provider error is reported, not raised).

### 4. Web — "System health" panel (`hearty-web`)

- `types/api.ts`: `HealthStatus` (backend/supabase/llm shapes above), `LlmTestResult`.
- `lib/api.ts`: `getHealth()` → `GET /api/admin/health`; `testLlm()` → `POST /api/admin/health/llm-test`.
- `hooks/useAdmin.ts`: `useHealth()` query (key `["admin","health"]`, no auto-refetch interval — on-demand); `useTestLlm()` mutation (invalidates `["admin","health"]` on success).
- `pages/Admin.tsx`: a **System health** card above the subscribers table — three rows (Backend, Database, AI / LLM), each with a status pill (Aurora `good` / `warn` / `accent-red` for ok / idle / down-degraded), a detail line (revision; latency; last-ok timestamp + model / the error), a **Re-check** button (refetch), and a **Test LLM** button (`useTestLlm`, disabled while pending). Reuses the page's existing error/`run()` pattern.

## Forward-compatibility (later, not v1)

- **Uptime history (option B):** a cron POSTs to a new internal probe route or calls the same probe function; results append to a `health_checks` table; the panel adds an uptime % + timeline. The v1 probe returns structured results specifically so this needs no probe rewrite.
- **Usage / cost:** the same litellm callback already sees token counts (`response_obj.usage`); a later iteration can sum tokens/$ per model/user into a usage table.
- **Errors / per-user activity:** additional panels reading their own aggregates.

## Error handling

- The health endpoint catches per-dependency failures and reports them as `down`/`degraded` — it must always return 200 with a body, never 500 because Supabase or the LLM is unhappy.
- The litellm callback recorder is fully `try/except`-guarded — instrumentation can never break an AI call.
- `llm-test` reports provider errors in the body; the global callback still records the failure.

## Security

- `service_health`: RLS on, no anon/auth policies (service-key only).
- `GET /api/admin/health` and `POST .../llm-test` are `Depends(get_current_admin)` (server-side `app_metadata.role=="admin"`).
- No user-editable input influences anything; no secrets in responses.

## Testing

**Backend (pytest, TestClient + dependency_overrides + monkeypatched supabase/litellm):**
- `GET /api/admin/health`: non-admin → 403; admin → 200. backend block always `ok` with version/revision/time. supabase `ok` + latency when the probe returns; `down` + error when it raises (monkeypatched to throw) — endpoint still 200.
- LLM status derivation: row with only `llm_last_ok_at` → `ok`; `error_at > ok_at` → `degraded` (+ error/model); both null → `idle`.
- `record_llm_ok` / `record_llm_error`: upsert row id=1 with the right fields (fake supabase).
- `HealthLogger.log_success_event` → calls `record_llm_ok`; `log_failure_event` → `record_llm_error`; a recorder exception is swallowed.
- `POST /api/admin/health/llm-test`: admin-gated; monkeypatch `litellm.completion` → success returns `{ok:true,...}`; raising → `{ok:false,error:...}` (no 500).

**Web (Vitest + RTL + MSW):** the System health panel renders the three pills from a mocked `/api/admin/health` payload (ok / down / idle variants); **Re-check** refetches; **Test LLM** posts to `/api/admin/health/llm-test` and the panel reflects the result. Existing `/admin` tests stay green.

## Out of scope (v1)

Uptime history / cron, usage & cost accounting, error log aggregation, per-user activity, alerting/notifications. All are clean later additions on the structures above.
