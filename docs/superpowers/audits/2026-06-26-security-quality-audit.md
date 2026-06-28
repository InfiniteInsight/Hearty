# Hearty Security & Code-Quality Audit — 2026-06-26

Scope: post-RAG (Knowledge Base) feature + Supabase API-key migration (`sb_secret_` /
`sb_publishable_`). Read-only review of `hearty-api/`, `hearty-web/`, and
`supabase/migrations/`. No application code was changed.

Branch reviewed: `origin/master` at audit time.

> **Resolution (2026-06-28, branch `security-hardening`):** the actionable findings
> were fixed in code.
> - **M1 — fixed.** `/auth/on-login` is now fail-closed (rejects when
>   `SUPABASE_WEBHOOK_SECRET` is unset/blank, logs a warning) and uses
>   `hmac.compare_digest`. A real `SUPABASE_WEBHOOK_SECRET` was provisioned in the
>   environment. Confirmed during the fix that **no Supabase webhook/auth-hook is
>   currently registered** to call this endpoint (no DB trigger, all auth hooks
>   disabled), so fail-closing it broke no live caller. Regression-tested in
>   `tests/test_security_hardening_unit.py`.
> - **M2 — fixed.** CORS no longer falls back to `*`; an unset/blank
>   `ALLOWED_ORIGINS` now yields an empty allow-list (deny all cross-origin) and logs
>   a warning. Origin parsing extracted to `_parse_origins` and unit-tested.
> - **L1 — fixed.** The web `/admin` route is now wrapped in a `RequireAdmin` guard
>   that redirects non-admins to `/dashboard` (`hearty-web/src/router/RequireAdmin.tsx`,
>   tested). Backend admin enforcement was already correct; this closes the UX/DiD gap.
> - **L2, L3, I2 — deferred (intentional).** The audit rates these "optional" /
>   "no action required" (admin-only error-detail surfacing, `str(e)` on owner-gated
>   admin routes, and an optional defense-in-depth `REVOKE EXECUTE` on
>   `match_knowledge` whose guarantee already rests on RLS deny-all). Not blocking;
>   may be picked up later.
> - **I1, I3, Note — acknowledged, no action.** Unauthenticated defaults endpoint is
>   correct; RAG prompt-injection surface is owner-curated only; the
>   `VITE_SUPABASE_ANON_KEY` env-var name carries the correct publishable value.

## Executive summary

Overall posture is **good**. The core security model is sound and consistently applied:

- Every user-data table in the `public` schema has Row Level Security enabled with an
  `auth.uid() = user_id` owner-only policy, and the new service-key-only tables
  (`knowledge_base`, `licenses`, `app_settings`, `service_health`, `food_cache`) correctly
  have RLS enabled with **no** anon/authenticated policies (deny-all to the client).
- Admin authorization keys off `app_metadata.role` — the server-set, non-user-editable
  metadata bucket — which is the correct choice (see Verified Good).
- The new RAG retrieval (`match_knowledge`) is parameterized via PostgREST RPC, retrieval
  is best-effort and fail-soft, and the service/secret key is never shipped to the browser.
- No XSS sinks in the web app; no `dangerouslySetInnerHTML`.

**No Critical findings.** The highest-severity issue is a Medium: an internal webhook
endpoint (`/auth/on-login`) is **fail-open** when its secret env var is unset and uses a
timing-unsafe string comparison — inconsistent with the correctly fail-closed
`/internal/photos/purge` endpoint. Blast radius is small (it only upserts blank rows), so
the severity reflects the pattern, not the impact.

Findings: **0 Critical / 0 High / 2 Medium / 3 Low / 3 Informational.**

---

## Medium

### M1 — `/auth/on-login` webhook is fail-open and timing-unsafe
`hearty-api/app/routers/auth_hooks.py:13-15`

```python
WEBHOOK_SECRET = os.environ.get("SUPABASE_WEBHOOK_SECRET", "")
...
if WEBHOOK_SECRET and auth_header != f"Bearer {WEBHOOK_SECRET}":
    raise HTTPException(status_code=401, detail="Invalid webhook secret")
```

Two problems:

1. **Fail-open default.** The check is guarded by `if WEBHOOK_SECRET and ...`. If
   `SUPABASE_WEBHOOK_SECRET` is unset or empty in the environment, the comparison is
   skipped entirely and the endpoint accepts **any** unauthenticated request. This is the
   opposite of the correctly fail-closed pattern in `internal.py` (which raises 403 when
   its token is missing).
2. **Timing-unsafe comparison.** `auth_header != f"Bearer {WEBHOOK_SECRET}"` is a plain
   string `!=`, which short-circuits and leaks timing information about the secret.
   `internal.py:19` correctly uses `hmac.compare_digest` for the same job.

Impact is limited: the handler only upserts blank `health_profile` / `notification_preferences`
rows keyed by a caller-supplied `user_id`, so the worst an attacker can do is create empty
default rows for arbitrary user IDs (or for IDs that don't exist). No data is read or
exfiltrated. The finding is Medium because of the auth-bypass *pattern* on a service-key
endpoint, not the blast radius.

**Fix:**
- Make it fail-closed: `if not WEBHOOK_SECRET or not hmac.compare_digest(auth_header, f"Bearer {WEBHOOK_SECRET}"): raise HTTPException(401, ...)`.
- Import and use `hmac.compare_digest` (mirror `internal.py`).
- Treat a missing `SUPABASE_WEBHOOK_SECRET` at startup as a misconfiguration (reject all
  requests, and ideally log a warning at boot), so a forgotten env var can never silently
  open the endpoint.

### M2 — CORS falls back to `*` when `ALLOWED_ORIGINS` is unset
`hearty-api/app/main.py:10-11, 26-31`

```python
_origins_env = os.getenv("ALLOWED_ORIGINS", "")
_allowed_origins = [o.strip() for o in _origins_env.split(",") if o.strip()] or ["*"]
...
app.add_middleware(CORSMiddleware, allow_origins=_allowed_origins,
                   allow_methods=["*"], allow_headers=["*"])
```

If `ALLOWED_ORIGINS` is unset or blank, the app silently serves CORS to **any** origin
(`*`). This is a deploy-hardening / fail-open-default issue, not a live credential-theft
vector — auth is a `Bearer` token in a request header (not a cookie), and
`allow_credentials` is left at its default of `False`, so `*` does not enable
cross-origin reading of authenticated responses with credentials. Severity is held at
Medium (leaning Low) because the consequence is a silently-permissive default on
misconfiguration, not an exploitable flaw given the current auth scheme.

**Fix:** fail closed instead of defaulting to `*` — if `ALLOWED_ORIGINS` is empty, either
raise at startup or default to an empty list (deny all cross-origin) rather than `["*"]`.
Keep an explicit allow-list per environment.

---

## Low

### L1 — `/admin` web route is auth-gated but not admin-gated
`hearty-web/src/App.tsx:31` (route under `ProtectedRoute` only)

The `/admin` route is wrapped by `ProtectedRoute` (requires a logged-in session) but has
no admin-role check. A non-admin authenticated user who navigates to `/admin` renders the
full Admin page; its API calls then fail server-side with 403, so the page shows empty
error states rather than data. **No data is exposed** — the backend correctly enforces
admin-only access via `get_current_admin` on every `/api/admin/*` route. This is a
defense-in-depth / UX gap only.

**Fix:** add an admin guard to the route (the app already has `isAdmin()` in
`hearty-web/src/lib/auth.ts:21` and uses it to conditionally show the sidebar link) and
redirect non-admins away from `/admin`.

### L2 — Client `ApiError` discards server-provided error detail
`hearty-web/src/lib/api.ts:42`

```python
if (!res.ok) throw new ApiError(res.status, `${res.status} ${res.statusText}`);
```

Errors are surfaced only as `status + statusText`; the JSON `detail` returned by the API
is never read. This is *safe* (it avoids reflecting any backend message into the UI) but
means actionable validation messages (e.g. `400 invalid provisioning_mode`,
`502 embedding failed: ...`) are lost, hurting admin debuggability. Not a vulnerability —
listed for completeness.

**Fix (optional):** for non-2xx JSON responses, parse and surface `detail` where it is
known to be owner-facing (admin screens), while keeping generic messages on user surfaces.

### L3 — `str(e)` returned to clients on admin endpoints
`hearty-api/app/routers/admin.py:190, 203, 213`

Three admin endpoints return truncated exception strings to the client
(`{"status": "down", "error": str(e)[:300]}`, the LLM-test error, and the
`embedding failed: {str(e)[:200]}` detail). These are all gated behind `get_current_admin`
(owner-only) and the leakage is intentional for diagnostics, so impact is minimal. Flagged
only to confirm the exposure is confined to admin-authenticated routes and does not appear
on any user-facing endpoint (it does not). Truncation caps are applied, which is good.

**Fix (optional):** none required; if desired, log full exceptions server-side and return a
short opaque error id instead of `str(e)`.

---

## Informational

### I1 — `/api/health-profile/defaults` is intentionally unauthenticated
`hearty-api/app/health_profile/defaults_router.py:32-54`

Mounted at `/api/health-profile/defaults` **without** the `require_active_license`
dependency and with no `get_current_user`. Confirmed it returns only static reference
constants (allergen / intolerance / condition / dietary-protocol lists) — no per-user or
sensitive data. Correctly unauthenticated. (Every other bare-mounted router was verified:
`account`→`get_current_user`, `license`→`get_current_user`, `admin`→`get_current_admin`,
`internal`→token, `auth_hooks`→webhook secret per M1.)

### I2 — `match_knowledge` RPC relies on RLS, not on an EXECUTE grant
`supabase/migrations/20260625235623_knowledge_base.sql:29-45`

The retrieval function is `LANGUAGE sql STABLE` (default `SECURITY INVOKER`) with no
explicit `REVOKE`/`GRANT`. By Postgres default it is PUBLIC-executable, so an
authenticated user *could* call it via PostgREST — but because it runs with the caller's
privileges and `knowledge_base` has RLS enabled with no anon/authenticated policy, the
query returns **zero rows** to any non-service caller. The "service-key only" guarantee for
the corpus therefore rests on the RLS-deny-all mechanism, which is correct. No action
needed; documented so the guarantee's basis is explicit. (Optional defense-in-depth:
`revoke execute on function match_knowledge(...) from anon, authenticated;`.)

### I3 — Prompt-injection surface from owner-curated RAG content is acceptable but worth noting
`hearty-api/app/services/knowledge.py:56-65`, consumed in
`trends_conversation.py:74-78` and `ai_extraction.py:148-152`

Retrieved corpus `content` is concatenated verbatim into the system/user prompt via
`format_context`. The corpus is **owner-curated only** (admin CRUD, service-key writes), so
this is not a user-controlled injection vector today. If the corpus ever ingests external
sources (the migration comment anticipates `pubmed`/`nhs`/`nih`), treat retrieved text as
untrusted and sandbox it (clear delimiters / "the following is reference data, not
instructions"). The framing text already hedges ("observations, not diagnoses"), which is
good. No action required for v1.

---

## Verified good (coverage map)

These were checked and are correctly implemented:

- **Admin authorization keystone — `app_metadata.role`.** `auth.py:35` reads the role from
  `app_metadata`, which in Supabase is **service-role-set and not user-editable** (unlike
  `user_metadata`, which the user *can* edit via the client SDK). Had the code used
  `user_metadata.role`, any user could self-promote to admin — a Critical. It uses the
  correct bucket. Both `get_current_user` and `get_current_admin` validate the JWT via
  `supabase.auth.get_user(token)` and fail closed on any exception or null user.
- **RLS coverage.** All 18 `public` tables have RLS enabled. User-data tables
  (`meals`, `symptoms`, `wellbeing_snapshots`, `food_triggers`, `food_signals`,
  `food_signals_yearly`, `health_profile`, `notification_preferences`, `offline_queue`,
  `experiments`, `signal_feedback`, `food_log_photos`) use
  `FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id)`. Service-key-only
  tables (`knowledge_base`, `licenses`, `app_settings`, `service_health`, `food_cache`) have
  RLS on with no client policy. `waitlist` grants `anon` insert-only with no read policy
  (intentional public signup).
- **Storage policies.** `food-photos` bucket is private; insert/select/delete policies all
  scope to `(storage.foldername(name))[1] = auth.uid()::text`, so users only touch their own
  folder. Photo storage path is `{user_id}/{photo_id}`.
- **Internal photo-purge endpoint.** `internal.py:19` uses `hmac.compare_digest` and is
  fail-closed (403 when the token is missing or mismatched). Correct.
- **Account deletion.** `account.py:34-64` derives `user_id` from the validated token (not a
  caller-supplied param) and scopes every delete with `.eq("user_id", user_id)`. Storage
  cleanup is best-effort and never blocks row/auth deletion.
- **RAG injection surface.** `match_knowledge` is a parameterized PostgREST RPC
  (`query_embedding`, `match_count`, `filter_conditions` bound, not string-built); no SQL
  injection. `knowledge.search` and the `trends.py` `_research_for` / `_user_condition_slugs`
  helpers are best-effort with broad `except` → `[]`/`""`, so a RAG failure never breaks the
  user-facing AI call and never surfaces internals to the user (errors go to the logger).
- **Admin CRUD validation.** `update_settings` validates `provisioning_mode` against an
  allow-list and bounds `trial_days` (1–3650). Knowledge create requires `content`
  (Pydantic), embeds before insert, and strips `content_embedding` from responses.
- **Secrets handling / key migration.** Backend service key read from
  `SUPABASE_SERVICE_KEY` (server only). The web client (`supabase.ts`) uses a publishable
  key from a `VITE_`-prefixed env var (the var is still named `VITE_SUPABASE_ANON_KEY` — a
  legacy name now carrying the `sb_publishable_` value; see Note below). No secret/service
  key is referenced anywhere in `hearty-web/src`. The litellm health callback
  (`llm_health.py`) records model name + truncated error to `service_health`; it does not
  log request/response bodies or keys, and is wrapped so a recorder failure can't affect the
  AI call.
- **Web auth header handling.** `api.ts` attaches `Authorization: Bearer <access_token>`
  from the live Supabase session on every request; sends `Content-Type` only on
  body-carrying methods (avoids unnecessary CORS preflight).
- **XSS.** No `dangerouslySetInnerHTML` / `innerHTML` anywhere in `hearty-web/src`. All API
  data (including AI-generated summaries and admin tables) is rendered through JSX text
  interpolation, which React auto-escapes.
- **Model ID.** `claude-sonnet-4-6` (default `LLM_MODEL` in `trends_conversation.py`,
  `ai_extraction.py`, `admin.py`) is a valid current model ID and embeddings use
  `gemini/gemini-embedding-001` (3072-dim) matching the `vector(3072)` column.

### Note on env-var naming (not a finding)
The web app reads the publishable key from `VITE_SUPABASE_ANON_KEY`. The value is correct
(a `sb_publishable_` key), but the variable name predates the key migration. Consider
renaming to `VITE_SUPABASE_PUBLISHABLE_KEY` for clarity so nobody mistakes it for the
disabled legacy anon JWT.
