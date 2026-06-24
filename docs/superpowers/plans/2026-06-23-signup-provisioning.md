# New-User License Provisioning — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give a brand-new signup access (or not) according to an owner-controlled, runtime-toggleable provisioning mode (`open`/`trial`/`paywall`), and gate un-onboarded users cleanly.

**Architecture:** A single-row `app_settings` table holds the mode. Provisioning happens lazily inside `_license_state` the first time a user's access is evaluated (the `/api/license/status` poll after sign-in), so there's no auth-webhook race and existing users' gate path is untouched. Admin endpoints expose the setting; the web admin page gets a control. The phone router applies the license gate before onboarding so gated users see `NoAccessScreen` instead of 403ing mid-onboarding.

**Tech Stack:** FastAPI + Supabase (service key), pytest; React 18 + TanStack Query + Vitest/RTL + MSW; Flutter + Riverpod + GoRouter.

**Worktree:** `~/.config/superpowers/worktrees/signup-provisioning` (branch `signup-provisioning`, off master @ #15). Run all commands there.

**Spec:** `docs/superpowers/specs/2026-06-23-signup-provisioning-design.md`

**Backend test command (use everywhere below):**
```bash
cd hearty-api && SUPABASE_URL="http://localhost" SUPABASE_SERVICE_KEY="dummy-key" \
  /home/evan/projects/food-journal-assistant/hearty-api/.venv/bin/python -m pytest -k unit -q
```

---

## File Structure

| File | Responsibility | Action |
|------|----------------|--------|
| `hearty-api/supabase/migrations/20260623120000_app_settings.sql` | `app_settings` table + extend `licenses.activation_source` enum | Create |
| `hearty-api/app/licensing.py` | `_get_settings`, `_provision`, lazy-provisioning `_license_state` | Modify |
| `hearty-api/tests/test_license_gate_unit.py` | Gate + provisioning unit tests (stateful fake) | Modify |
| `hearty-api/app/routers/admin.py` | `GET/PUT /api/admin/settings` | Modify |
| `hearty-api/tests/test_admin_endpoints_unit.py` | Settings endpoint tests | Modify |
| `hearty-web/src/types/api.ts` | `AppSettings` type | Modify |
| `hearty-web/src/lib/api.ts` | `getAppSettings` / `updateAppSettings` | Modify |
| `hearty-web/src/hooks/useAdmin.ts` | `useAppSettings` / `useUpdateAppSettings` | Modify |
| `hearty-web/src/pages/Admin.tsx` | "Signup policy" panel | Modify |
| `hearty-web/src/test/msw/handlers.ts` | Default settings handler | Modify |
| `hearty-web/src/pages/Admin.test.tsx` | Settings panel test | Modify |
| `hearty_app/lib/features/licensing/license_provider.dart` | `inLicensedArea` pure helper | Modify |
| `hearty_app/lib/app/router.dart` | Gate before onboarding | Modify |
| `hearty_app/test/features/licensing/license_provider_test.dart` | `inLicensedArea` tests | Modify |

---

## Task 1: Migration — `app_settings` + `trial` activation source

**Files:**
- Create: `hearty-api/supabase/migrations/20260623120000_app_settings.sql`

- [ ] **Step 1: Write the migration**

```sql
-- App-wide, owner-configurable settings. Single row (id=1). Service-key only.
create table if not exists app_settings (
  id int primary key default 1 check (id = 1),
  provisioning_mode text not null default 'open'
    check (provisioning_mode in ('open','trial','paywall')),
  trial_days int not null default 14 check (trial_days > 0),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);
alter table app_settings enable row level security;
-- No anon/authenticated policies: read/written only via the service key (like licenses).
insert into app_settings (id) values (1) on conflict (id) do nothing;

-- Allow auto-provisioned trial licenses.
alter table licenses drop constraint licenses_activation_source_check;
alter table licenses add constraint licenses_activation_source_check
  check (activation_source in ('manual','web_checkout','play_billing','comp','trial'));
```

- [ ] **Step 2: Sanity-check SQL locally (no live apply)**

Run: `grep -c "create table if not exists app_settings" hearty-api/supabase/migrations/20260623120000_app_settings.sql`
Expected: `1`. (Do NOT apply to any live DB — that's a consent-gated deploy step.)

- [ ] **Step 3: Commit**

```bash
git add hearty-api/supabase/migrations/20260623120000_app_settings.sql
git commit -m "feat(api): app_settings table + trial activation_source"
```

---

## Task 2: Lazy provisioning in `licensing.py`

**Files:**
- Modify: `hearty-api/app/licensing.py`
- Test: `hearty-api/tests/test_license_gate_unit.py`

Context: today `_license_state` returns `none` when no row exists. After this change it provisions per the current mode, then re-reads. The existing `test_missing_blocks` (no row → 403) is no longer valid as-is — with `open` mode the user is now provisioned active. It is replaced by mode-specific tests below.

- [ ] **Step 1: Replace the gate unit test file with the stateful-fake version**

Overwrite `hearty-api/tests/test_license_gate_unit.py` with:

```python
import types
from datetime import datetime, timezone, timedelta
from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient
from app import licensing
from app.auth import get_current_user


def _ns(data):
    return types.SimpleNamespace(data=data)


class _Tbl:
    """Routes by table name. licenses: stateful (select re-reads, upsert inserts
    once when empty to mimic on_conflict/ignore_duplicates). app_settings: returns
    the configured settings row."""
    def __init__(self, db, name):
        self.db, self.name = db, name
        self._op = None; self._payload = None
    def select(self, *a, **k): self._op = "select"; return self
    def eq(self, *a, **k): return self
    def limit(self, *a, **k): return self
    def upsert(self, payload, **k): self._op = "upsert"; self._payload = payload; return self
    def execute(self):
        if self.name == "app_settings":
            return _ns([self.db.settings] if self.db.settings else [])
        # licenses
        if self._op == "upsert":
            if not self.db.licenses:
                self.db.licenses.append({
                    "status": self._payload.get("status"),
                    "expires_at": self._payload.get("expires_at"),
                })
            return _ns(list(self.db.licenses))
        return _ns(list(self.db.licenses))


class _FakeDB:
    def __init__(self, licenses, settings):
        self.licenses = list(licenses)
        self.settings = settings
    def table(self, name): return _Tbl(self, name)


def _client():
    app = FastAPI()

    @app.get("/gated", dependencies=[Depends(licensing.require_active_license)])
    async def gated():
        return {"ok": True}

    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    return app


def _wire(monkeypatch, licenses, settings):
    monkeypatch.setattr(licensing, "supabase", _FakeDB(licenses, settings))


def test_active_allows(monkeypatch):
    _wire(monkeypatch, [{"status": "active", "expires_at": None}], {"provisioning_mode": "open", "trial_days": 14})
    assert TestClient(_client()).get("/gated").status_code == 200


def test_revoked_blocks(monkeypatch):
    _wire(monkeypatch, [{"status": "revoked", "expires_at": None}], {"provisioning_mode": "open", "trial_days": 14})
    assert TestClient(_client()).get("/gated").status_code == 403


def test_expired_blocks(monkeypatch):
    past = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
    _wire(monkeypatch, [{"status": "active", "expires_at": past}], {"provisioning_mode": "open", "trial_days": 14})
    assert TestClient(_client()).get("/gated").status_code == 403


def test_new_user_paywall_blocks(monkeypatch):
    _wire(monkeypatch, [], {"provisioning_mode": "paywall", "trial_days": 14})
    r = TestClient(_client()).get("/gated")
    assert r.status_code == 403 and r.json()["detail"] == "no_active_license"


def test_new_user_open_provisions_active(monkeypatch):
    db = _FakeDB([], {"provisioning_mode": "open", "trial_days": 14})
    monkeypatch.setattr(licensing, "supabase", db)
    assert TestClient(_client()).get("/gated").status_code == 200
    assert db.licenses and db.licenses[0]["status"] == "active"
    assert db.licenses[0]["expires_at"] is None


def test_new_user_trial_provisions_expiring(monkeypatch):
    db = _FakeDB([], {"provisioning_mode": "trial", "trial_days": 14})
    monkeypatch.setattr(licensing, "supabase", db)
    assert TestClient(_client()).get("/gated").status_code == 200
    exp = db.licenses[0]["expires_at"]
    assert exp is not None and datetime.fromisoformat(exp) > datetime.now(timezone.utc)


def test_get_settings_default_when_missing(monkeypatch):
    monkeypatch.setattr(licensing, "supabase", _FakeDB([], None))
    assert licensing._get_settings()["provisioning_mode"] == "open"
```

- [ ] **Step 2: Run tests to verify they fail**

Run the backend test command (above) scoped: `... -m pytest tests/test_license_gate_unit.py -q`
Expected: FAIL — `AttributeError`/`_get_settings` not defined and provisioning not implemented.

- [ ] **Step 3: Implement provisioning in `licensing.py`**

Replace the body of `hearty-api/app/licensing.py` with:

```python
import os
from datetime import datetime, timedelta, timezone

from fastapi import Depends, HTTPException
from supabase import create_client

from app.auth import get_current_user

supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])

_DEFAULT_SETTINGS = {"provisioning_mode": "open", "trial_days": 14}


def _get_settings() -> dict:
    """Owner-configured provisioning settings (single row id=1). Falls back to
    defaults if the row is somehow absent."""
    rows = (
        supabase.table("app_settings")
        .select("provisioning_mode,trial_days")
        .eq("id", 1)
        .limit(1)
        .execute()
    ).data or []
    return rows[0] if rows else dict(_DEFAULT_SETTINGS)


def _fetch(user_id: str) -> list[dict]:
    return (
        supabase.table("licenses")
        .select("status,expires_at")
        .eq("user_id", user_id)
        .limit(1)
        .execute()
    ).data or []


def _provision(user_id: str) -> None:
    """Create a license row for a brand-new user per the current provisioning mode.
    No-op for paywall. Idempotent via on_conflict/ignore_duplicates so concurrent
    first-requests can't violate the unique constraint."""
    s = _get_settings()
    mode = s.get("provisioning_mode", "open")
    if mode == "paywall":
        return
    row = {"user_id": user_id, "status": "active"}
    if mode == "trial":
        days = int(s.get("trial_days") or _DEFAULT_SETTINGS["trial_days"])
        row["activation_source"] = "trial"
        row["expires_at"] = (datetime.now(timezone.utc) + timedelta(days=days)).isoformat()
    else:  # open
        row["activation_source"] = "comp"
    supabase.table("licenses").upsert(row, on_conflict="user_id", ignore_duplicates=True).execute()


def _license_state(user_id: str) -> tuple[str, str | None]:
    """(state, expires_at_iso) — state in active|none|revoked|expired.
    Lazily provisions a brand-new user (no row) per the provisioning mode."""
    rows = _fetch(user_id)
    if not rows:
        _provision(user_id)
        rows = _fetch(user_id)
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
    """Gate user-facing data routes on an active, non-expired license."""
    state, _ = _license_state(user["id"])
    if state != "active":
        raise HTTPException(status_code=403, detail="no_active_license")
    return user
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `... -m pytest tests/test_license_gate_unit.py -q`
Expected: PASS (8 tests).

- [ ] **Step 5: Run the full unit suite (no regressions)**

Run the backend test command (above).
Expected: all unit tests pass (the autouse conftest bypass keeps endpoint tests green).

- [ ] **Step 6: Commit**

```bash
git add hearty-api/app/licensing.py hearty-api/tests/test_license_gate_unit.py
git commit -m "feat(api): lazy license provisioning by mode (open/trial/paywall)"
```

---

## Task 3: Admin settings API

**Files:**
- Modify: `hearty-api/app/routers/admin.py`
- Test: `hearty-api/tests/test_admin_endpoints_unit.py`

- [ ] **Step 1: Add settings tests**

Add a `limit` no-op to the existing fake's `_Tbl` and append these tests to `hearty-api/tests/test_admin_endpoints_unit.py`.

First, in `_Tbl` (class in that file), add this method next to `eq`:
```python
    def limit(self, *a, **k): return self
```

Then append:
```python
def test_get_settings(monkeypatch):
    _admin()
    monkeypatch.setattr(adm, "supabase", _FakeSupabase(rows=[{"provisioning_mode": "trial", "trial_days": 7}]))
    r = TestClient(app).get("/api/admin/settings")
    assert r.status_code == 200
    assert r.json()["provisioning_mode"] == "trial" and r.json()["trial_days"] == 7
    app.dependency_overrides.clear()


def test_put_settings(monkeypatch):
    _admin()
    fake = _FakeSupabase(rows=[]); monkeypatch.setattr(adm, "supabase", fake)
    r = TestClient(app).put("/api/admin/settings", json={"provisioning_mode": "paywall", "trial_days": 30})
    assert r.status_code == 200
    assert any(op == "update" and p.get("provisioning_mode") == "paywall" and p.get("updated_by") == "admin1" for (op, p, _e) in fake.log)
    app.dependency_overrides.clear()


def test_put_settings_rejects_bad_mode(monkeypatch):
    _admin()
    monkeypatch.setattr(adm, "supabase", _FakeSupabase(rows=[]))
    r = TestClient(app).put("/api/admin/settings", json={"provisioning_mode": "nope"})
    assert r.status_code == 400
    app.dependency_overrides.clear()


def test_put_settings_rejects_bad_trial_days(monkeypatch):
    _admin()
    monkeypatch.setattr(adm, "supabase", _FakeSupabase(rows=[]))
    r = TestClient(app).put("/api/admin/settings", json={"trial_days": 0})
    assert r.status_code == 400
    app.dependency_overrides.clear()
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `... -m pytest tests/test_admin_endpoints_unit.py -q`
Expected: FAIL — settings routes 404.

- [ ] **Step 3: Implement settings endpoints in `admin.py`**

Add a model near the other models in `hearty-api/app/routers/admin.py`:
```python
class SettingsUpdate(BaseModel):
    provisioning_mode: str | None = None
    trial_days: int | None = None
```

Add these two routes (after the existing license routes):
```python
@router.get("/api/admin/settings")
async def get_settings(admin=Depends(get_current_admin)) -> dict:
    rows = (
        supabase.table("app_settings")
        .select("provisioning_mode,trial_days")
        .eq("id", 1)
        .limit(1)
        .execute()
    ).data or []
    return rows[0] if rows else {"provisioning_mode": "open", "trial_days": 14}


@router.put("/api/admin/settings")
async def update_settings(body: SettingsUpdate, admin=Depends(get_current_admin)) -> dict:
    updates: dict = {}
    if body.provisioning_mode is not None:
        if body.provisioning_mode not in ("open", "trial", "paywall"):
            raise HTTPException(status_code=400, detail="invalid provisioning_mode")
        updates["provisioning_mode"] = body.provisioning_mode
    if body.trial_days is not None:
        if body.trial_days <= 0:
            raise HTTPException(status_code=400, detail="trial_days must be positive")
        updates["trial_days"] = body.trial_days
    updates["updated_at"] = _now()
    updates["updated_by"] = admin["id"]
    res = supabase.table("app_settings").update(updates).eq("id", 1).execute()
    return res.data[0]
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `... -m pytest tests/test_admin_endpoints_unit.py -q`
Expected: PASS.

- [ ] **Step 5: Run the full unit suite**

Run the backend test command. Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add hearty-api/app/routers/admin.py hearty-api/tests/test_admin_endpoints_unit.py
git commit -m "feat(api): admin settings endpoints (GET/PUT /api/admin/settings)"
```

---

## Task 4: Web — settings types, client, hook, panel

**Files:**
- Modify: `hearty-web/src/types/api.ts`
- Modify: `hearty-web/src/lib/api.ts`
- Modify: `hearty-web/src/hooks/useAdmin.ts`
- Modify: `hearty-web/src/pages/Admin.tsx`
- Modify: `hearty-web/src/test/msw/handlers.ts`
- Test: `hearty-web/src/pages/Admin.test.tsx`

- [ ] **Step 1: Add the type**

Append to `hearty-web/src/types/api.ts`:
```typescript
export type ProvisioningMode = "open" | "trial" | "paywall";
export interface AppSettings { provisioning_mode: ProvisioningMode; trial_days: number }
```

- [ ] **Step 2: Add API methods**

In `hearty-web/src/lib/api.ts`, add `AppSettings` to the type import block (the one importing `LicenseStatus, AdminUsersResponse, GrantLicenseRequest`), then add inside the returned client object (after `updateLicense`):
```typescript
    getAppSettings: () => request<AppSettings>(`/api/admin/settings`),
    updateAppSettings: (body: Partial<AppSettings>) =>
      request<AppSettings>(`/api/admin/settings`, { method: "PUT", body: JSON.stringify(body) }),
```

- [ ] **Step 3: Add hooks**

In `hearty-web/src/hooks/useAdmin.ts`, add `AppSettings` to the type import and append:
```typescript
export function useAppSettings() {
  return useQuery({
    queryKey: ["admin", "settings"],
    queryFn: () => api.getAppSettings(),
    staleTime: 30_000,
  });
}

export function useUpdateAppSettings() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: Partial<AppSettings>) => api.updateAppSettings(body),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["admin", "settings"] }),
  });
}
```

- [ ] **Step 4: Add a default MSW handler so Admin renders don't hit unhandled requests**

In `hearty-web/src/test/msw/handlers.ts`, add to the exported `handlers` array (check the file for the exact array name and `http`/`HttpResponse` import — they are already used there):
```typescript
  http.get("*/api/admin/settings", () => HttpResponse.json({ provisioning_mode: "open", trial_days: 14 })),
```

- [ ] **Step 5: Write the settings-panel test**

Append to `hearty-web/src/pages/Admin.test.tsx`:
```typescript
test("shows signup policy and saves a mode change", async () => {
  let saved: unknown = null;
  server.use(
    http.get("*/api/admin/users", () => HttpResponse.json({ users: [] })),
    http.get("*/api/admin/settings", () => HttpResponse.json({ provisioning_mode: "open", trial_days: 14 })),
    http.put("*/api/admin/settings", async ({ request }) => { saved = await request.json(); return HttpResponse.json({ provisioning_mode: "paywall", trial_days: 14 }); }),
  );
  renderWithProviders(<Admin />, { route: "/admin" });
  const select = await screen.findByLabelText(/signup policy/i);
  await userEvent.selectOptions(select, "paywall");
  await userEvent.click(screen.getByRole("button", { name: /save policy/i }));
  await vi.waitFor(() => expect(saved).toMatchObject({ provisioning_mode: "paywall" }));
});
```

- [ ] **Step 6: Run the web test to verify it fails**

Run: `cd hearty-web && npm run test -- --run src/pages/Admin.test.tsx`
Expected: FAIL — no "Signup policy" control.

- [ ] **Step 7: Add the panel to `Admin.tsx`**

At the top of `hearty-web/src/pages/Admin.tsx`, extend the hook import and add a panel component. Update the imports line to include the settings hooks:
```typescript
import { useAdminUsers, useAdminActions, useAppSettings, useUpdateAppSettings } from "../hooks/useAdmin";
import type { AdminUser, ProvisioningMode } from "@/types/api";
```

Add this component above `export default function Admin()`:
```tsx
function SignupPolicy() {
  const settings = useAppSettings();
  const update = useUpdateAppSettings();
  const [mode, setMode] = useState<ProvisioningMode>("open");
  const [trialDays, setTrialDays] = useState(14);
  const [loaded, setLoaded] = useState(false);
  if (settings.isSuccess && !loaded) {
    setMode(settings.data.provisioning_mode);
    setTrialDays(settings.data.trial_days);
    setLoaded(true);
  }
  return (
    <div className="rounded-2xl border border-surface-border bg-surface p-4 flex flex-col gap-3">
      <h2 className="font-display text-xl">Signup policy</h2>
      <p className="text-xs text-text-faint">Applies to future signups only. Existing users are unaffected.</p>
      <div className="flex flex-wrap items-end gap-4">
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-text-muted">Signup policy</span>
          <select
            aria-label="Signup policy"
            value={mode}
            onChange={(e) => setMode(e.target.value as ProvisioningMode)}
            className="rounded border border-surface-border bg-background px-2 py-1 text-text"
          >
            <option value="open">Open — auto-grant access</option>
            <option value="trial">Trial — time-limited access</option>
            <option value="paywall">Paywall — gated until granted</option>
          </select>
        </label>
        {mode === "trial" && (
          <label className="flex flex-col gap-1 text-sm">
            <span className="text-text-muted">Trial days</span>
            <input
              type="number"
              min={1}
              value={trialDays}
              onChange={(e) => setTrialDays(Number(e.target.value))}
              className="w-24 rounded border border-surface-border bg-background px-2 py-1 text-text"
            />
          </label>
        )}
        <button
          disabled={update.isPending}
          onClick={() => update.mutate({ provisioning_mode: mode, trial_days: trialDays })}
          className="rounded px-3 py-1.5 text-sm bg-brand text-black hover:opacity-80 disabled:opacity-40"
        >
          Save policy
        </button>
      </div>
    </div>
  );
}
```

Then render it just inside the page wrapper, right after the `<h1>Subscribers</h1>` line:
```tsx
      <SignupPolicy />
```

(`useState` is already imported at the top of `Admin.tsx`.)

- [ ] **Step 8: Run web test to verify it passes**

Run: `cd hearty-web && npm run test -- --run src/pages/Admin.test.tsx`
Expected: PASS (both the existing revoke test and the new policy test).

- [ ] **Step 9: Full web gate — tests, lint, build**

Run: `cd hearty-web && npm run test -- --run && npm run lint && npm run build`
Expected: all green.

- [ ] **Step 10: Commit**

```bash
git add hearty-web/src/types/api.ts hearty-web/src/lib/api.ts hearty-web/src/hooks/useAdmin.ts hearty-web/src/pages/Admin.tsx hearty-web/src/pages/Admin.test.tsx hearty-web/src/test/msw/handlers.ts
git commit -m "feat(web): admin signup-policy control"
```

---

## Task 5: Phone — gate before onboarding

**Files:**
- Modify: `hearty_app/lib/features/licensing/license_provider.dart`
- Modify: `hearty_app/lib/app/router.dart`
- Test: `hearty_app/test/features/licensing/license_provider_test.dart`

Context: today the router only runs the license gate for `hasCompletedOnboarding` users (`inAppFlow`). A gated new user therefore enters onboarding and 403s. We extract a pure `inLicensedArea(...)` helper (testable) and have the router call the gate for any authenticated user outside the auth/setup screens — including `/onboarding`.

- [ ] **Step 1: Add tests for `inLicensedArea`**

Append to `hearty_app/test/features/licensing/license_provider_test.dart`:
```dart
  group('inLicensedArea', () {
    test('false when unauthenticated', () {
      expect(inLicensedArea(isAuthenticated: false, location: '/home'), isFalse);
    });
    test('false on auth/setup screens', () {
      for (final loc in ['/sign-in', '/setup', '/notification-setup', '/conversation-style-setup']) {
        expect(inLicensedArea(isAuthenticated: true, location: loc), isFalse, reason: loc);
      }
    });
    test('true on onboarding (so gated users are diverted before onboarding)', () {
      expect(inLicensedArea(isAuthenticated: true, location: '/onboarding'), isTrue);
    });
    test('true in the app proper', () {
      expect(inLicensedArea(isAuthenticated: true, location: '/home'), isTrue);
    });
  });
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty_app && flutter test test/features/licensing/license_provider_test.dart`
Expected: FAIL — `inLicensedArea` undefined.

- [ ] **Step 3: Implement `inLicensedArea`**

Append to `hearty_app/lib/features/licensing/license_provider.dart`:
```dart
/// Whether the license gate should run at [location] for an authenticated user.
/// Excludes the pre-account auth/setup screens; INCLUDES `/onboarding` so a gated
/// (paywall/expired) user is routed to `/no-access` before entering onboarding
/// (which would otherwise call gated endpoints and 403).
bool inLicensedArea({required bool isAuthenticated, required String location}) {
  if (!isAuthenticated) return false;
  const exempt = {'/sign-in', '/setup', '/notification-setup', '/conversation-style-setup'};
  return !exempt.contains(location);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd hearty_app && flutter test test/features/licensing/license_provider_test.dart`
Expected: PASS.

- [ ] **Step 5: Wire the router to use it**

In `hearty_app/lib/app/router.dart`, replace the `inAppFlow` block (the `final inAppFlow = ...` through the closing `}` of `if (inAppFlow) { ... }`) with:
```dart
      // License gate applies to any authenticated user in the app area (incl.
      // /onboarding), so a gated user lands on /no-access instead of 403ing
      // through onboarding. Active users pass straight through.
      if (inLicensedArea(isAuthenticated: isAuthenticated, location: location)) {
        final licenseStatus = ref.read(licenseStatusProvider).valueOrNull;
        final licenseTarget = licenseRedirect(
          isAuthenticated: isAuthenticated,
          status: licenseStatus,
          location: location,
        );
        if (licenseTarget != null) return licenseTarget;
      }
```

- [ ] **Step 6: Full Flutter gate — analyze + test**

Run: `cd hearty_app && flutter analyze lib/ && flutter test`
Expected: no analyzer issues; all tests pass (294+ existing plus the new `inLicensedArea` cases).

- [ ] **Step 7: Commit**

```bash
git add hearty_app/lib/features/licensing/license_provider.dart hearty_app/lib/app/router.dart hearty_app/test/features/licensing/license_provider_test.dart
git commit -m "feat(app): apply license gate before onboarding"
```

---

## Task 6: Live verification (manual — after merge, owner-gated, before/at deploy)

Not a code task. Run after the PR merges, against the prod project `ehuanqnkqehpivwuqpqw`, using the throwaway-test-user method from the #15 verification. Requires consent to apply the migration and to run the gated backend.

- [ ] Apply `20260623120000_app_settings.sql` to prod (`supabase db push`, password from `/home/evan/projects/food-journal-assistant/.env` `SUPABASE_DB_PASSWORD`).
- [ ] Start the gated backend on `:8001` from this worktree's `hearty-api` with prod env (leave `:8000` alone).
- [ ] For each mode, set `app_settings.provisioning_mode` (SQL or `PUT /api/admin/settings`), create a fresh password test user, mint a token (`/auth/v1/token?grant_type=password` with the anon key), then hit `GET /api/preferences` on `:8001`:
  - `paywall` → **403 `no_active_license`**, `/api/license/status` → `none`.
  - `open` → **200**, a `comp` active license row was created.
  - `trial` → **200**, license row has a future `expires_at` and `activation_source='trial'`.
- [ ] Delete each test user and all its referencing rows (`notification_preferences`, `health_profile`, `licenses`, then `auth.users`), and reset `provisioning_mode` to the intended launch value (`open`).
- [ ] Stop the `:8001` backend.

---

## Self-Review (completed by plan author)

- **Spec coverage:** provisioning model (T2), `app_settings` storage (T1), lazy provisioning (T2), admin settings API (T3), `activation_source` enum (T1), web control (T4), phone onboarding-order fix (T5), live 3-mode verification (T6). Web `LicenseGate` unchanged per spec — no task needed. ✓
- **Placeholders:** none — every code step has full code; the one spec "plan's discretion" edge (un-onboarded active on `/no-access` → `/home`) is left as the existing `licenseRedirect` behavior, intentionally unchanged. ✓
- **Type/name consistency:** `_get_settings`/`_provision`/`_fetch`/`_license_state` consistent across T2–T3; `AppSettings`/`ProvisioningMode`/`getAppSettings`/`updateAppSettings`/`useAppSettings`/`useUpdateAppSettings` consistent across T4; `inLicensedArea` signature consistent T5. Migration constraint name `licenses_activation_source_check` matches Postgres' auto-name for the original inline check. ✓
