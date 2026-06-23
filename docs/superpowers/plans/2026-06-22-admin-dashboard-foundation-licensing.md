# Admin Dashboard — Foundation + Licensing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Ship owner-only licensing: a `licenses` table + a server-side access gate, admin endpoints to grant/revoke/manage licenses, a gated `/admin` subscribers view in `hearty-web`, and a "no active access" gated state on both the web and phone clients.

**Architecture:** Backend adds a `licenses` table (Supabase), a `get_current_admin` auth dependency (`app_metadata.role=="admin"`), a `require_active_license` dependency applied at the router level to all user-facing data routers, and a `GET /api/license/status` endpoint. A new `app/routers/admin.py` exposes `/api/admin/*`. `hearty-web` gets a `/admin` route (admin-gated via the Supabase session's `app_metadata.role`) + a license-gate that shows a "no access" screen on `403 no_active_license`. `hearty_app` (Flutter) maps that 403 to a typed exception and routes to a non-dismissable gated screen after login.

**Tech Stack:** Supabase (Postgres + migration), FastAPI + Pydantic (pytest), React + TS + TanStack Query + Vitest/RTL/MSW (`hearty-web`), Flutter/Riverpod/Dio (`hearty_app`).

**Spec:** `docs/superpowers/specs/2026-06-22-admin-dashboard-design.md`.

**Workspace:** worktree `/home/evan/.config/superpowers/worktrees/admin-dashboard`, branch `admin-dashboard` (off current `master`).

**Runners (verified):**
- Backend pytest: `cd hearty-api && SUPABASE_URL="http://localhost" SUPABASE_SERVICE_KEY="dummy-key" /home/evan/projects/food-journal-assistant/hearty-api/.venv/bin/python -m pytest <path> -q`
- Web: `cd hearty-web && npm run test -- --run <path>` · `npm run build` · `npm run lint`
- Flutter: `cd hearty_app && flutter test <path>` · `flutter analyze lib/<dir>`

**Conventions:** backend tests = `TestClient` + `app.dependency_overrides[...]` + `monkeypatch.setattr(<module>, "supabase", fake)`. Web TS = `erasableSyntaxOnly`/`verbatimModuleSyntax`, `import type`, MSW `onUnhandledRequest:"error"`, mock `lib/supabase`. Flutter mirrors the `OfflineException` pattern. Commit per task with trailer `Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Migrations: dry-run → apply (never blind). Push/PR only with consent.

---

## PHASE A — Backend foundation (table + gate + status)

### Task 1: `licenses` migration + backfill

**Files:** Create `supabase/migrations/<timestamp>_licenses.sql` (use `supabase migration new licenses` to generate the timestamped filename; do NOT hand-invent it).

- [ ] **Step 1: Generate the migration file**

Run: `cd /home/evan/projects/food-journal-assistant && supabase migration new licenses`
Then put this SQL in the created file:

```sql
-- Per-user license / access record. Server-authoritative (service-key only).
create table if not exists licenses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  status text not null default 'active' check (status in ('active','revoked')),
  expires_at timestamptz,
  tier text,
  activation_source text not null default 'manual'
    check (activation_source in ('manual','web_checkout','play_billing','comp')),
  granted_by uuid references auth.users(id) on delete set null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table licenses enable row level security;
-- Intentionally NO anon/authenticated policies: the gate runs server-side with the
-- service key, so license state stays off the client. Service role bypasses RLS.

-- Rollout safety: grant every existing user an active license so enabling the
-- gate never locks anyone out.
insert into licenses (user_id, status, activation_source)
select id, 'active', 'comp' from auth.users
on conflict (user_id) do nothing;
```

- [ ] **Step 2: Dry-run review, then apply**

Review the SQL. Apply via the project's migration flow (e.g. `supabase db push` against the target, or the established apply process). Verify with: table exists, RLS enabled, every `auth.users` row has a `licenses` row. **Do not** proceed to the gate (Task 3 wiring) against a live DB until the backfill is confirmed.

- [ ] **Step 3: Add `licenses` to the account-deletion cascade** (matches spec §5). The FK `on delete cascade` from `auth.users` already covers DB cleanup, but for explicitness add `"licenses"` to the `USER_TABLES` list in `hearty-api/app/routers/account.py` (children-first ordering is fine to append it). The existing `test_account_endpoint_unit.py` iterates `acct.USER_TABLES`, so it stays green automatically.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/*_licenses.sql hearty-api/app/routers/account.py
git commit -m "feat(db): licenses table + RLS + backfill; add licenses to account-delete cascade"
```

---

### Task 2: `get_current_admin` dependency

**Files:** Modify `hearty-api/app/auth.py`; Create `hearty-api/tests/test_admin_auth_unit.py`.

- [ ] **Step 1: Write the failing test**

Create `hearty-api/tests/test_admin_auth_unit.py`:

```python
import types
import pytest
from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient
from app import auth


def _app_with_admin_route():
    app = FastAPI()

    @app.get("/whoami")
    async def whoami(admin=Depends(auth.get_current_admin)):
        return admin

    return app


def _fake_supabase(user):
    fake = types.SimpleNamespace()
    fake.auth = types.SimpleNamespace(
        get_user=lambda token: types.SimpleNamespace(user=user)
    )
    return fake


def test_admin_allowed(monkeypatch):
    user = types.SimpleNamespace(id="u1", email="e", app_metadata={"role": "admin"})
    monkeypatch.setattr(auth, "supabase", _fake_supabase(user))
    client = TestClient(_app_with_admin_route())
    r = client.get("/whoami", headers={"Authorization": "Bearer t"})
    assert r.status_code == 200 and r.json()["id"] == "u1"


def test_non_admin_forbidden(monkeypatch):
    user = types.SimpleNamespace(id="u2", email="e", app_metadata={})
    monkeypatch.setattr(auth, "supabase", _fake_supabase(user))
    client = TestClient(_app_with_admin_route())
    r = client.get("/whoami", headers={"Authorization": "Bearer t"})
    assert r.status_code == 403


def test_missing_token_rejected():
    client = TestClient(_app_with_admin_route())
    assert client.get("/whoami").status_code in (401, 403)
```

- [ ] **Step 2: Run → fail**

Run: `cd hearty-api && SUPABASE_URL="http://localhost" SUPABASE_SERVICE_KEY="dummy-key" /home/evan/projects/food-journal-assistant/hearty-api/.venv/bin/python -m pytest tests/test_admin_auth_unit.py -q`
Expected: FAIL — `get_current_admin` doesn't exist.

- [ ] **Step 3: Implement** — append to `hearty-api/app/auth.py`:

```python
async def get_current_admin(
    credentials: HTTPAuthorizationCredentials = Security(security)
) -> dict:
    """Owner-only. Validates the token and requires app_metadata.role == 'admin'.
    app_metadata is server-set (not user-editable) — safe for authorization."""
    token = credentials.credentials
    try:
        response = supabase.auth.get_user(token)
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    user = response.user
    if user is None:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    role = (getattr(user, "app_metadata", None) or {}).get("role")
    if role != "admin":
        raise HTTPException(status_code=403, detail="admin only")
    return {"id": user.id, "email": user.email}
```

- [ ] **Step 4: Run → pass; Step 5: Commit** (`feat(api): get_current_admin dependency (app_metadata role)`).

---

### Task 3: `require_active_license` gate + `GET /api/license/status` + wire the gate

**Files:** Create `hearty-api/app/licensing.py`, `hearty-api/app/routers/license.py`, `hearty-api/tests/test_license_gate_unit.py`; Modify `hearty-api/app/main.py`.

- [ ] **Step 1: Write the failing tests** — `hearty-api/tests/test_license_gate_unit.py`:

```python
import types
from datetime import datetime, timezone, timedelta
from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient
from app import licensing
from app.auth import get_current_user


def _fake_supabase(rows):
    class _Q:
        def select(self, *a, **k): return self
        def eq(self, *a, **k): return self
        def limit(self, *a, **k): return self
        def execute(self): return types.SimpleNamespace(data=rows)
    fake = types.SimpleNamespace()
    fake.table = lambda name: _Q()
    return fake


def _client(rows):
    app = FastAPI()

    @app.get("/gated", dependencies=[Depends(licensing.require_active_license)])
    async def gated():
        return {"ok": True}

    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    return app, _fake_supabase(rows)


def test_active_allows(monkeypatch):
    app, fake = _client([{"status": "active", "expires_at": None}])
    monkeypatch.setattr(licensing, "supabase", fake)
    assert TestClient(app).get("/gated").status_code == 200


def test_missing_blocks(monkeypatch):
    app, fake = _client([])
    monkeypatch.setattr(licensing, "supabase", fake)
    r = TestClient(app).get("/gated")
    assert r.status_code == 403 and r.json()["detail"] == "no_active_license"


def test_revoked_blocks(monkeypatch):
    app, fake = _client([{"status": "revoked", "expires_at": None}])
    monkeypatch.setattr(licensing, "supabase", fake)
    assert TestClient(app).get("/gated").status_code == 403


def test_expired_blocks(monkeypatch):
    past = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
    app, fake = _client([{"status": "active", "expires_at": past}])
    monkeypatch.setattr(licensing, "supabase", fake)
    assert TestClient(app).get("/gated").status_code == 403


def test_state_helper(monkeypatch):
    fake = _fake_supabase([{"status": "active", "expires_at": None}])
    monkeypatch.setattr(licensing, "supabase", fake)
    assert licensing._license_state("u1")[0] == "active"
```

- [ ] **Step 2: Run → fail.** (module missing)

- [ ] **Step 3: Implement `hearty-api/app/licensing.py`:**

```python
import os
from datetime import datetime, timezone

from fastapi import Depends, HTTPException
from supabase import create_client

from app.auth import get_current_user

supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


def _license_state(user_id: str) -> tuple[str, str | None]:
    """(state, expires_at_iso) — state in active|none|revoked|expired."""
    rows = (
        supabase.table("licenses")
        .select("status,expires_at")
        .eq("user_id", user_id)
        .limit(1)
        .execute()
    ).data or []
    if not rows:
        return "none", None
    row = rows[0]
    exp = row.get("expires_at")
    if row.get("status") != "active":
        return "revoked", exp
    if exp:
        exp_dt = datetime.fromisoformat(str(exp).replace("Z", "+00:00"))
        if exp_dt.tzinfo is None:
            exp_dt = exp_dt.replace(tzinfo=timezone.utc)
        if exp_dt <= datetime.now(timezone.utc):
            return "expired", exp
    return "active", exp


async def require_active_license(user=Depends(get_current_user)) -> dict:
    """Gate user-facing data routes on an active, non-expired license.
    Depends on get_current_user; FastAPI caches that call within a request so the
    endpoint's own Depends(get_current_user) does not re-hit Supabase auth."""
    state, _ = _license_state(user["id"])
    if state != "active":
        raise HTTPException(status_code=403, detail="no_active_license")
    return user
```

- [ ] **Step 4: Implement `hearty-api/app/routers/license.py`:**

```python
from fastapi import APIRouter, Depends

from app.auth import get_current_user
from app.licensing import _license_state

router = APIRouter()


@router.get("/api/license/status")
async def license_status(user=Depends(get_current_user)) -> dict:
    state, expires_at = _license_state(user["id"])
    return {"status": state, "expires_at": expires_at}
```

- [ ] **Step 5: Wire the gate + status router in `app/main.py`.**

Add imports: `from app.licensing import require_active_license` and `from fastapi import Depends`, and `from app.routers import license` (alongside the others). Add `dependencies=[Depends(require_active_license)]` to **these** data-router includes: `chat, meals, symptoms, trends, export, photos, preferences, transcribe, checkin, experiments, food`, and `health_profile_router`. Example:

```python
app.include_router(meals.router, dependencies=[Depends(require_active_license)])
app.include_router(symptoms.router, dependencies=[Depends(require_active_license)])
# ...same for trends, export, photos, preferences, transcribe, checkin, experiments, food, chat
app.include_router(health_profile_router, dependencies=[Depends(require_active_license)])
```

Do **NOT** gate: `defaults_router` (public reference data), `auth_hooks` (webhook), `account` (a license-less user may still delete their account), the new `license.router`, and the new `admin.router` (Task 4, role-gated). Add `app.include_router(license.router)` (un-gated).

- [ ] **Step 6: Add an autouse gate-bypass fixture so the existing suite stays green.**

⚠️ **Required, not optional.** Router-level `dependencies=[Depends(require_active_license)]` runs on *every* request to those routers. The existing endpoint tests (`test_meals*`, `test_experiments_endpoint`, `test_summary*`, `test_trends*`, `test_chat*`, …) do `from app.main import app` + `TestClient(app)` and override only `get_current_user` — they do **not** monkeypatch `licensing.supabase`. So without a bypass, the gate calls the real Supabase client against dummy env → connection error → **500**, turning the whole suite red. Add a suite-wide override in `hearty-api/tests/conftest.py`:

```python
import pytest
from app.main import app
from app.licensing import require_active_license

@pytest.fixture(autouse=True)
def _bypass_license_gate():
    # Existing endpoint tests assert behavior, not licensing — bypass the gate
    # suite-wide. Gate behavior is covered in isolation by test_license_gate_unit.py
    # (which builds its own FastAPI app and is unaffected by this override).
    app.dependency_overrides[require_active_license] = lambda: {"id": "u1", "email": "e"}
    yield
    app.dependency_overrides.pop(require_active_license, None)
```

(If a `conftest.py` already exists, merge this fixture in.) Optionally add one dedicated test that pops the override and asserts a gated route 403s for an unlicensed user — but `test_license_gate_unit.py` already covers the gate logic directly.

- [ ] **Step 7: Run the gate tests + the full unit suite:**

`cd hearty-api && SUPABASE_URL="http://localhost" SUPABASE_SERVICE_KEY="dummy-key" /home/evan/projects/food-journal-assistant/hearty-api/.venv/bin/python -m pytest tests/test_license_gate_unit.py -q && … -m pytest -q -k unit`
Expected: gate tests pass; full unit suite green **because of the conftest bypass** (verify — a red suite here means the bypass isn't wired).

- [ ] **Step 8: Commit** (`feat(api): require_active_license gate + GET /api/license/status; gate data routers + test bypass`).

---

## PHASE B — Admin API

### Task 4: `/api/admin/*` (list users + grant/revoke/reactivate/edit)

**Files:** Create `hearty-api/app/routers/admin.py`, `hearty-api/tests/test_admin_endpoints_unit.py`; Modify `app/main.py` (register router).

- [ ] **Step 1: Write the failing tests** — `hearty-api/tests/test_admin_endpoints_unit.py`:

```python
import types
from fastapi.testclient import TestClient
from app.main import app
from app.auth import get_current_admin
from app.routers import admin as adm


class _Tbl:
    def __init__(self, log, rows):
        self.log, self.rows = log, rows
        self._op = None; self._payload = None; self._eq = None
    def select(self, *a, **k): self._op = "select"; return self
    def upsert(self, payload, **k): self._op = "upsert"; self._payload = payload; return self
    def update(self, payload): self._op = "update"; self._payload = payload; return self
    def eq(self, col, val): self._eq = (col, val); return self
    def execute(self):
        if self._op == "select":
            return types.SimpleNamespace(data=self.rows)
        self.log.append((self._op, self._payload, self._eq))
        row = dict(self._payload) if isinstance(self._payload, dict) else {}
        if self._eq: row["user_id"] = self._eq[1]
        return types.SimpleNamespace(data=[row])


class _FakeSupabase:
    def __init__(self, rows):
        self.log = []; self.rows = rows
        self.auth = types.SimpleNamespace(admin=types.SimpleNamespace(
            list_users=lambda: [types.SimpleNamespace(id="u1", email="a@x.com", created_at="2026-01-01")]
        ))
    def table(self, name): return _Tbl(self.log, self.rows)


def _admin():
    app.dependency_overrides[get_current_admin] = lambda: {"id": "admin1", "email": "o"}


def test_list_users(monkeypatch):
    _admin()
    monkeypatch.setattr(adm, "supabase", _FakeSupabase(rows=[{"user_id": "u1", "status": "active", "expires_at": None, "tier": None, "activation_source": "comp"}]))
    r = TestClient(app).get("/api/admin/users")
    assert r.status_code == 200
    u = r.json()["users"][0]
    assert u["user_id"] == "u1" and u["license"]["status"] == "active"
    app.dependency_overrides.clear()


def test_grant(monkeypatch):
    _admin()
    fake = _FakeSupabase(rows=[]); monkeypatch.setattr(adm, "supabase", fake)
    r = TestClient(app).post("/api/admin/licenses", json={"user_id": "u9", "expires_at": "2027-01-01T00:00:00Z"})
    assert r.status_code == 200
    assert any(op == "upsert" and p.get("status") == "active" and p.get("granted_by") == "admin1" for (op, p, _e) in fake.log)
    app.dependency_overrides.clear()


def test_revoke(monkeypatch):
    _admin()
    fake = _FakeSupabase(rows=[]); monkeypatch.setattr(adm, "supabase", fake)
    r = TestClient(app).post("/api/admin/licenses/u9/revoke")
    assert r.status_code == 200
    assert any(op == "update" and p.get("status") == "revoked" for (op, p, _e) in fake.log)
    app.dependency_overrides.clear()


def test_admin_required():
    # no override → real get_current_admin → 403/401 without a token
    assert TestClient(app).get("/api/admin/users").status_code in (401, 403)
```

- [ ] **Step 2: Run → fail.**

- [ ] **Step 3: Implement `hearty-api/app/routers/admin.py`:**

```python
import os
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from supabase import create_client

from app.auth import get_current_admin

router = APIRouter()
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


class GrantRequest(BaseModel):
    user_id: str
    expires_at: str | None = None
    tier: str | None = None
    notes: str | None = None


class UpdateRequest(BaseModel):
    expires_at: str | None = None
    tier: str | None = None
    status: str | None = None
    notes: str | None = None


@router.get("/api/admin/users")
async def list_users(admin=Depends(get_current_admin)) -> dict:
    users = supabase.auth.admin.list_users()
    rows = supabase.table("licenses").select("*").execute().data or []
    by_user = {r["user_id"]: r for r in rows}
    out = []
    for u in users:
        lr = by_user.get(u.id)
        out.append({
            "user_id": u.id,
            "email": u.email,
            "created_at": str(getattr(u, "created_at", "")),
            "license": ({
                "status": lr["status"], "expires_at": lr.get("expires_at"),
                "tier": lr.get("tier"), "activation_source": lr.get("activation_source"),
            } if lr else None),
        })
    return {"users": out}


@router.post("/api/admin/licenses")
async def grant(body: GrantRequest, admin=Depends(get_current_admin)) -> dict:
    row = {
        "user_id": body.user_id, "status": "active",
        "expires_at": body.expires_at, "tier": body.tier,
        "activation_source": "manual", "granted_by": admin["id"],
        "notes": body.notes, "updated_at": _now(),
    }
    row = {k: v for k, v in row.items() if v is not None}
    return supabase.table("licenses").upsert(row, on_conflict="user_id").execute().data[0]


@router.patch("/api/admin/licenses/{user_id}")
async def update(user_id: str, body: UpdateRequest, admin=Depends(get_current_admin)) -> dict:
    updates = {k: v for k, v in {
        "expires_at": body.expires_at, "tier": body.tier,
        "status": body.status, "notes": body.notes,
    }.items() if v is not None}
    updates["updated_at"] = _now()
    res = supabase.table("licenses").update(updates).eq("user_id", user_id).execute()
    if not res.data:
        raise HTTPException(status_code=404, detail="license not found")
    return res.data[0]


@router.post("/api/admin/licenses/{user_id}/revoke")
async def revoke(user_id: str, admin=Depends(get_current_admin)) -> dict:
    res = supabase.table("licenses").update({"status": "revoked", "updated_at": _now()}).eq("user_id", user_id).execute()
    if not res.data:
        raise HTTPException(status_code=404, detail="license not found")
    return res.data[0]


@router.post("/api/admin/licenses/{user_id}/reactivate")
async def reactivate(user_id: str, admin=Depends(get_current_admin)) -> dict:
    res = supabase.table("licenses").update({"status": "active", "updated_at": _now()}).eq("user_id", user_id).execute()
    if not res.data:
        raise HTTPException(status_code=404, detail="license not found")
    return res.data[0]
```

> **Verify before relying on it:** `supabase.auth.admin.list_users()`'s return shape + pagination vary across gotrue-py versions (often a bare `list[User]`, page-limited to ~50). Confirm the actual shape in your installed version (a quick REPL check or reading the SDK) and adjust the iteration/`.id`/`.email`/`.created_at` access + add pagination if the subscriber base may exceed one page. For a small base, one page is fine — just confirm, don't assume.

- [ ] **Step 4: Register in `main.py`:** `from app.routers import admin` + `app.include_router(admin.router)` (no `require_active_license`; gated by `get_current_admin` per-endpoint).

- [ ] **Step 5: Run → pass; full unit suite green. Step 6: Commit** (`feat(api): admin license endpoints (list/grant/revoke/reactivate/edit)`).

---

## PHASE C — Web `/admin` + gated state

### Task 5: Web API client — license + admin methods

**Files:** Modify `hearty-web/src/types/api.ts`, `hearty-web/src/lib/api.ts`, `hearty-web/src/lib/api.test.ts`.

- [ ] **Step 1: Add failing tests** to `src/lib/api.test.ts`:

```ts
test("getLicenseStatus returns the state", async () => {
  server.use(http.get("http://api.test/api/license/status", () => HttpResponse.json({ status: "active", expires_at: null })));
  const { createApiClient } = await import("./api");
  expect((await createApiClient("http://api.test").getLicenseStatus()).status).toBe("active");
});

test("getAdminUsers + grant/revoke hit the right endpoints", async () => {
  let granted: unknown = null; let revoked = false;
  server.use(
    http.get("http://api.test/api/admin/users", () => HttpResponse.json({ users: [{ user_id: "u1", email: "a@x", created_at: "x", license: { status: "active" } }] })),
    http.post("http://api.test/api/admin/licenses", async ({ request }) => { granted = await request.json(); return HttpResponse.json({ user_id: "u1", status: "active" }); }),
    http.post("http://api.test/api/admin/licenses/u1/revoke", () => { revoked = true; return HttpResponse.json({ user_id: "u1", status: "revoked" }); }),
  );
  const { createApiClient } = await import("./api");
  const api = createApiClient("http://api.test");
  expect((await api.getAdminUsers()).users).toHaveLength(1);
  await api.grantLicense({ user_id: "u1" });
  await api.revokeLicense("u1");
  expect(granted).toMatchObject({ user_id: "u1" });
  expect(revoked).toBe(true);
});
```

- [ ] **Step 2: Run → fail. Step 3: Add types** to `src/types/api.ts`:

```ts
export type LicenseState = "active" | "none" | "revoked" | "expired";
export interface LicenseStatus { status: LicenseState; expires_at?: string | null }
export interface AdminUserLicense { status: string; expires_at?: string | null; tier?: string | null; activation_source?: string }
export interface AdminUser { user_id: string; email: string; created_at: string; license: AdminUserLicense | null }
export interface AdminUsersResponse { users: AdminUser[] }
export interface GrantLicenseRequest { user_id: string; expires_at?: string; tier?: string; notes?: string }
```

- [ ] **Step 4: Add methods** to `src/lib/api.ts` (import the new types):

```ts
    getLicenseStatus: () => request<LicenseStatus>(`/api/license/status`),
    getAdminUsers: () => request<AdminUsersResponse>(`/api/admin/users`),
    grantLicense: (body: GrantLicenseRequest) => request<unknown>(`/api/admin/licenses`, { method: "POST", body: JSON.stringify(body) }),
    revokeLicense: (id: string) => request<unknown>(`/api/admin/licenses/${id}/revoke`, { method: "POST" }),
    reactivateLicense: (id: string) => request<unknown>(`/api/admin/licenses/${id}/reactivate`, { method: "POST" }),
    updateLicense: (id: string, body: { expires_at?: string; tier?: string; status?: string; notes?: string }) => request<unknown>(`/api/admin/licenses/${id}`, { method: "PATCH", body: JSON.stringify(body) }),
```

- [ ] **Step 5: Run → pass; build; lint. Step 6: Commit** (`feat(web): license-status + admin license API methods`).

---

### Task 6: Web license gate (the "no access" screen)

**Files:** Create `hearty-web/src/hooks/useLicenseStatus.ts`, `hearty-web/src/components/LicenseGate.tsx`, `hearty-web/src/components/LicenseGate.test.tsx`; Modify `hearty-web/src/components/layout/AppShell.tsx` (wrap content in `LicenseGate`).

- [ ] **Step 1: Write the failing test** — `LicenseGate.test.tsx`:

```tsx
import { expect, test, vi } from "vitest";
import { screen } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
import { renderWithProviders } from "../test/utils";
vi.mock("../lib/supabase", () => ({ supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } } }));
import LicenseGate from "./LicenseGate";

test("renders children when license active", async () => {
  server.use(http.get("*/api/license/status", () => HttpResponse.json({ status: "active" })));
  renderWithProviders(<LicenseGate><div>dashboard</div></LicenseGate>);
  expect(await screen.findByText("dashboard")).toBeInTheDocument();
});

test("shows no-access screen when not active", async () => {
  server.use(http.get("*/api/license/status", () => HttpResponse.json({ status: "none" })));
  renderWithProviders(<LicenseGate><div>dashboard</div></LicenseGate>);
  expect(await screen.findByText(/no active access/i)).toBeInTheDocument();
  expect(screen.queryByText("dashboard")).not.toBeInTheDocument();
});
```

- [ ] **Step 2: Run → fail. Step 3: Implement** `src/hooks/useLicenseStatus.ts`:

```ts
import { useQuery } from "@tanstack/react-query";
import { api } from "../lib/api";
export function useLicenseStatus() {
  return useQuery({ queryKey: ["license-status"], queryFn: () => api.getLicenseStatus(), staleTime: 60_000 });
}
```

`src/components/LicenseGate.tsx`:

```tsx
import type { ReactNode } from "react";
import { useLicenseStatus } from "../hooks/useLicenseStatus";
export default function LicenseGate({ children }: { children: ReactNode }) {
  const q = useLicenseStatus();
  if (q.isPending) return <div className="p-8 text-text-faint">Loading…</div>;
  if (q.isSuccess && q.data.status !== "active") {
    return (
      <div className="mx-auto mt-24 max-w-md rounded-2xl border border-surface-border bg-surface p-6 text-center">
        <h1 className="font-display text-2xl">No active access</h1>
        <p className="mt-2 text-text-muted">Your account doesn’t have an active license. Please contact the owner to regain access.</p>
      </div>
    );
  }
  return <>{children}</>; // active, or error (fail-open to avoid lockout on a transient error; the API still enforces)
}
```

- [ ] **Step 4: Wrap `AppShell` content** — in `src/components/layout/AppShell.tsx`, wrap the `<Outlet/>` (page area) with `<LicenseGate>…</LicenseGate>` so all gated pages sit behind it. Keep the sidebar/header visible (so sign-out works on the gated screen).

- [ ] **Step 5: Run tests + build + lint. Step 6: Commit** (`feat(web): LicenseGate — no-active-access screen`).

---

### Task 7: Web `/admin` Subscribers page

**Files:** Create `hearty-web/src/pages/Admin.tsx`, `hearty-web/src/pages/Admin.test.tsx`, `hearty-web/src/hooks/useAdmin.ts`; Modify `hearty-web/src/App.tsx` (route), `hearty-web/src/components/layout/Sidebar.tsx` (admin-only nav link), `hearty-web/src/lib/auth.ts` (expose `isAdmin` from the session).

- [ ] **Step 1: Admin detection** — add to `src/lib/auth.ts` a helper that reads the Supabase session's `app_metadata.role`:

```ts
export async function isAdmin(): Promise<boolean> {
  const { data } = await supabase.auth.getSession();
  return ((data.session?.user?.app_metadata as { role?: string } | undefined)?.role) === "admin";
}
```

(Cosmetic gate; the API enforces admin server-side.)

- [ ] **Step 2: `useAdmin.ts`** — `useAdminUsers` query (`["admin","users"]` → `api.getAdminUsers`) + `useAdminActions` (grant/revoke/reactivate/update mutations, each `onSuccess` invalidates `["admin","users"]`). Mirror `useExperiments.ts`.

- [ ] **Step 3: Failing test** — `Admin.test.tsx`: with MSW for `/api/admin/users` returning a user, the page lists the email + license status; clicking **Revoke** calls `/api/admin/licenses/{id}/revoke`; clicking **Grant** on an unlicensed user calls `POST /api/admin/licenses`. (mock `../lib/supabase`.)

```tsx
import { expect, test, vi } from "vitest";
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
import { renderWithProviders } from "../test/utils";
vi.mock("../lib/supabase", () => ({ supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t", user: { app_metadata: { role: "admin" } } } } }) } } }));
import Admin from "./Admin";

test("lists subscribers and revokes a license", async () => {
  let revoked = false;
  server.use(
    http.get("*/api/admin/users", () => HttpResponse.json({ users: [{ user_id: "u1", email: "a@x.com", created_at: "2026-01-01", license: { status: "active" } }] })),
    http.post("*/api/admin/licenses/u1/revoke", () => { revoked = true; return HttpResponse.json({ user_id: "u1", status: "revoked" }); }),
  );
  renderWithProviders(<Admin />, { route: "/admin" });
  expect(await screen.findByText("a@x.com")).toBeInTheDocument();
  await userEvent.click(screen.getByRole("button", { name: /revoke/i }));
  await vi.waitFor(() => expect(revoked).toBe(true));
});
```

- [ ] **Step 4: Implement `Admin.tsx`** — a table of `users` (email · created · license status · expiry · tier) with per-row actions: **Grant** (when `license` is null/revoked → `grantLicense({user_id})`), **Revoke** (when active), **Reactivate** (when revoked), and an expiry edit (calls `updateLicense`). Loading/error/empty states; a shared `busy` from the mutations. Reuse the Aurora card/table styling from existing pages.

- [ ] **Step 5: Wire route + nav** — `App.tsx`: add `<Route path="/admin" element={<Admin />} />` inside the AppShell/ProtectedRoute group (it is fine for it to sit under `LicenseGate` since the owner is licensed; if preferred, place `/admin` as a sibling that bypasses `LicenseGate`). `Sidebar.tsx`: show an "Admin" link only when `isAdmin()` resolves true (store the boolean in state via an effect, or a tiny `useIsAdmin` hook).

- [ ] **Step 6: Run the page test + full web suite + build + lint. Step 7: Commit** (`feat(web): /admin subscribers page + admin-only nav`).

---

## PHASE D — Phone gated state

### Task 8: `NoActiveLicenseException` mapping

**Files:** Modify `hearty_app/lib/core/api/hearty_api_client.dart` (+ a new `no_active_license_exception.dart` mirroring `offline_exception.dart`); Test `hearty_app/test/core/api/hearty_api_client_license_test.dart`.

- [ ] **Step 1: Write the failing test** — assert that a Dio `403` whose body is `{"detail":"no_active_license"}` thrown from a client call surfaces as `NoActiveLicenseException` (not a generic `DioException`). Mirror the existing client tests' interceptor/mock-adapter setup.

- [ ] **Step 2: Run → fail. Step 3: Implement** — create `NoActiveLicenseException` (like `OfflineException`); in the client's error handling (where `DioException`s are translated), detect `e.response?.statusCode == 403 && (e.response?.data is Map && data['detail'] == 'no_active_license')` and throw `NoActiveLicenseException`. Keep all other error behavior unchanged.

- [ ] **Step 4: `flutter test test/core/api/` + `flutter analyze lib/core/api/`. Step 5: Commit** (`feat(app): map 403 no_active_license to NoActiveLicenseException`).

---

### Task 9: Post-login license gate screen

**Files:** Create `hearty_app/lib/features/licensing/no_access_screen.dart`, `hearty_app/lib/features/licensing/license_provider.dart`; modify the post-login routing (wherever the app decides home vs login — e.g. the root router/gate widget); Tests under `hearty_app/test/features/licensing/`.

- [ ] **Step 1: Add a client method** `Future<String> licenseStatus()` → `GET /api/license/status` → returns `status` string. Add to `hearty_api_client.dart` (+ a small test).

- [ ] **Step 2: `license_provider.dart`** — a Riverpod provider that fetches license status after auth. **Guard provider mutations to post-frame / async** (do NOT mutate during build — the lesson from the photo-upload fix).

- [ ] **Step 3: Failing widget test** — the root gate routes to `NoAccessScreen` when status != active, and to the normal home shell when active; `NoAccessScreen` is non-dismissable (no back/close to the app) and offers Sign out.

- [ ] **Step 4: Implement `NoAccessScreen`** (message: "No active access — contact the owner", + Sign out) and wire the post-login gate: after a session exists, check license status; route accordingly. Treat a transient fetch error as "allow through" (the API still enforces) to avoid false lockouts offline (offline-first: cached data still works; the gate asserts only when the server answers non-active).

- [ ] **Step 5: `flutter test test/features/licensing/` + full `flutter test` + `flutter analyze lib/`. Step 6: Commit** (`feat(app): post-login license gate + no-access screen`).

---

## Self-Review

**1. Spec coverage:** licenses table + RLS + backfill (Task 1 ✓ §5/§7); `get_current_admin` app_metadata role (Task 2 ✓ §4/§11); `require_active_license` gate on data routers + `GET /api/license/status` (Task 3 ✓ §4/§6); admin list/grant/revoke/reactivate/edit (Task 4 ✓ §6); web admin methods + `/admin` subscribers + web gate (Tasks 5–7 ✓ §8); phone `NoActiveLicenseException` + gate screen (Tasks 8–9 ✓ §8). Payment/LLM-routing/monitoring excluded ✓ §9.

**2. Placeholder scan:** backend tasks have complete code; web/phone tasks give complete code for the load-bearing units (api, gate, hooks) and precise, test-anchored specs for the page/screen UIs that follow established Aurora/Flutter patterns. No "TBD"/"handle errors" hand-waves.

**3. Consistency:** `no_active_license` detail string is identical across the gate (Task 3), web gate (Task 6), and phone mapping (Task 8). `app_metadata.role=="admin"` used in Task 2 (backend enforce) + Task 7 (web cosmetic gate). License method names consistent web (`getLicenseStatus`/`getAdminUsers`/`grant/revoke/reactivate/updateLicense`) across Tasks 5–7. The gate depends on `get_current_user` (cached) so no double Supabase-auth call.

**4. Risks flagged:** migration is dry-run→apply with backfill verified before gating; the gate **fail-opens** on transient status-fetch errors client-side (API remains the true enforcer) to avoid false lockouts; Flutter providers mutated post-frame (photo-upload lesson).

---

## Execution handoff

Execute via **superpowers:subagent-driven-development** — Phase A/B backend (Python, standard model), Phase C web (mechanical→standard), Phase D phone (standard). Two-stage review per task + final whole-implementation review. The migration (Task 1) is dry-run→apply with the owner's consent before touching the live DB. Device-verify the phone gate (revoke→gated, grant→restored) at the end. Finish with **superpowers:finishing-a-development-branch** (push + PR, base `master`) **only with user consent**.
