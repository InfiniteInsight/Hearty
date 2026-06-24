# New-User License Provisioning Policy — Design

**Status:** Approved (brainstorm 2026-06-23)
**Depends on:** PR #15 (admin dashboard — foundation + licensing), merged to master.
**Tracking:** task #76 (pre-deploy blocker for the `require_active_license` gate).

## Problem

The licensing gate from PR #15 returns `403 no_active_license` for any user without an
active license row. The rollout migration backfilled a license for every *existing* user,
but nothing provisions a license for a **new signup**. Once the gated backend deploys:

- A brand-new account has no license row → `_license_state` returns `none` → every gated
  data route 403s.
- The phone router gate only engages **after** onboarding (`hasCompletedOnboarding`), so a
  gated new user is routed *into* onboarding, which calls the gated `preferences` route →
  403 mid-onboarding instead of a clean gated screen.

This is the last blocker before the gate can be deployed. The resolution is a
**runtime-configurable provisioning policy** plus a small onboarding-order fix on the phone.

## Goals

1. A new signup gets access (or not) according to an owner-controlled **provisioning mode**.
2. The owner can flip the mode at runtime (no redeploy) and it applies to **future signups
   only** — existing users are never mass-affected by a toggle.
3. A gated user (paywall mode, or expired trial) sees `NoAccessScreen` immediately after
   sign-in, never entering a flow that 403s.

## Non-goals

- Web-checkout / Play Billing integration (the `activation_source` enum reserves space for
  these; wiring is a separate future spec).
- Retroactive / mass re-evaluation of existing users on toggle (deliberately excluded — the
  admin subscriber table already gives per-user control).
- Per-user provisioning overrides beyond the global mode (YAGNI).

## The provisioning model

A single global **provisioning mode**, owner-settable:

| Mode | New signup gets… | `activation_source` | `expires_at` |
|------|------------------|---------------------|--------------|
| `open` (default) | active license, no expiry | `comp` | null |
| `trial` | active license that expires | `trial` | `now + trial_days` |
| `paywall` | nothing → gated immediately | — (no row) | — |

**Default is `open`** (open beta): unblocks deploy without throttling growth. Flip to
`trial`/`paywall` later once web-checkout exists.

**Toggle scope = future signups only.** Changing the mode never reads or writes existing
users' license rows. Provisioning happens once per user, the first time their access is
evaluated; after that their row is authoritative and the mode is irrelevant to them.

## Architecture

### 1. Config storage — `app_settings` (single-row table)

```sql
create table if not exists app_settings (
  id int primary key default 1 check (id = 1),          -- singleton
  provisioning_mode text not null default 'open'
    check (provisioning_mode in ('open','trial','paywall')),
  trial_days int not null default 14 check (trial_days > 0),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);
alter table app_settings enable row level security;          -- no anon/auth policies; service-key only
insert into app_settings (id) values (1) on conflict (id) do nothing;  -- seed defaults
```

DB-backed so the toggle is instant and survives restarts. RLS on with no policies — like
`licenses`, it's read/written only via the service key from the backend.

### 2. Lazy provisioning — inside `_license_state` (`hearty-api/app/licensing.py`)

When `_license_state(user_id)` finds **no license row**, it provisions according to the
current mode, then returns the resulting state. This is the single source of truth — the
first `/api/license/status` poll the app makes after sign-in provisions the user. No
dependency on auth webhooks, no provisioning-vs-first-check race.

```python
def _get_settings() -> dict:
    rows = supabase.table("app_settings").select("provisioning_mode,trial_days").eq("id", 1).limit(1).execute().data or []
    return rows[0] if rows else {"provisioning_mode": "open", "trial_days": 14}

def _provision(user_id: str) -> None:
    """Create a license row for a brand-new user per the current provisioning mode.
    No-op for paywall. Idempotent: upsert on user_id ignores an existing row, so
    concurrent first-requests can't violate the unique constraint."""
    s = _get_settings()
    mode = s["provisioning_mode"]
    if mode == "paywall":
        return
    row = {"user_id": user_id, "status": "active"}
    if mode == "trial":
        row["activation_source"] = "trial"
        row["expires_at"] = (datetime.now(timezone.utc) + timedelta(days=s["trial_days"])).isoformat()
    else:  # open
        row["activation_source"] = "comp"
    supabase.table("licenses").upsert(row, on_conflict="user_id", ignore_duplicates=True).execute()
```

`_license_state` change: when `rows` is empty, call `_provision(user_id)` then re-query
once. If still empty (paywall), return `("none", None)` as today. `_get_settings` is only
hit for users with no row (i.e. once per user lifetime), so the gate's hot path for existing
users is unchanged — no extra query, no caching needed.

`require_active_license` is unchanged; it already treats anything but `active` as a 403.

### 3. Admin settings API (`hearty-api/app/routers/admin.py`)

Two endpoints, both `Depends(get_current_admin)`:

- `GET /api/admin/settings` → `{provisioning_mode, trial_days}`
- `PUT /api/admin/settings` body `{provisioning_mode?, trial_days?}` → validates
  `provisioning_mode in ('open','trial','paywall')` and `trial_days > 0`; updates row id=1,
  sets `updated_at=now()`, `updated_by=<admin id>`; returns the new settings.

### 4. `activation_source` enum migration

Extend the `licenses.activation_source` check to add `'trial'`:

```sql
alter table licenses drop constraint licenses_activation_source_check;
alter table licenses add constraint licenses_activation_source_check
  check (activation_source in ('manual','web_checkout','play_billing','comp','trial'));
```

### 5. Web — admin settings control (`hearty-web`)

- `types/api.ts`: `AppSettings { provisioning_mode: 'open'|'trial'|'paywall'; trial_days: number }`.
- `lib/api.ts`: `getAppSettings()`, `updateAppSettings(body)`.
- `hooks/useAdmin.ts`: `useAppSettings()` query + `useUpdateAppSettings()` mutation.
- `pages/Admin.tsx`: a small "Signup policy" panel above the subscribers table — a mode
  selector (open / trial / paywall) and a `trial_days` number input (shown when mode=trial),
  with a Save button. Uses the existing Aurora tokens and the page's `run()` error pattern.

**Web `LicenseGate` needs no change.** It already wraps the dashboard and shows the no-access
screen when status ≠ active (fail-open on error). The onboarding-order problem is phone-only.

### 6. Phone — gate before onboarding (`hearty_app/lib/app/router.dart`)

Today the license gate is inside an `inAppFlow` guard that requires `hasCompletedOnboarding`.
Remove that requirement so the gate also covers authenticated-but-not-yet-onboarded users:

```dart
// License gate applies to any authenticated user in the app area (incl. /onboarding),
// so a gated (paywall/expired) user lands on /no-access instead of 403ing through onboarding.
final inAppArea = isAuthenticated &&
    !isOnSignIn && !isOnSetup && !isOnNotificationSetup && !isOnConversationStyleSetup;
if (inAppArea) {
  final licenseStatus = ref.read(licenseStatusProvider).valueOrNull;
  final target = licenseRedirect(
    isAuthenticated: isAuthenticated, status: licenseStatus, location: location);
  if (target != null) return target;
}
```

`licenseRedirect` is unchanged (fail-open on null/loading; active users pass through; a
non-active status routes to `/no-access`). An `open`/`trial` new user has an active license,
so they proceed to onboarding exactly as before; only a non-active user is diverted.

**Known minor edge:** if a *not-yet-onboarded* user is sitting on `/no-access` and is then
granted access, `licenseRedirect` returns `/home` rather than `/onboarding`. This is rare
(requires a grant while the user waits on the gate) and harmless; the implementation may
leave it or redirect un-onboarded actives to `/onboarding` — plan's discretion.

## Data flow (new signup)

1. User signs up + signs in (phone). `licenseStatusProvider` fetches `/api/license/status`.
2. Backend `_license_state` finds no row → `_provision` reads `app_settings`:
   - `open`/`trial` → inserts an active license → status `active`/`active(expiring)`.
   - `paywall` → no row → status `none`.
3. Phone router: active → `/onboarding` (or `/home`); non-active → `/no-access`.
4. Existing users: row already present → step 2 provisioning never runs; mode is irrelevant.

## Error handling

- `_get_settings` falls back to `{open, 14}` if the row is somehow missing (defensive; the
  migration seeds it).
- `_provision` upsert is idempotent (`ignore_duplicates`) → concurrent first requests are safe.
- Admin `PUT` rejects invalid mode / non-positive `trial_days` with 422 (Pydantic) or 400.
- Gate fail-open behavior (phone/web) is unchanged: transient status-fetch failure never
  locks a user out; the server remains the enforcer.

## Security

- `app_settings`: RLS enabled, no anon/authenticated policies (service-key only).
- Settings endpoints gated by `get_current_admin` (server-side `app_metadata.role=="admin"`).
- No user-editable metadata is consulted for authorization.

## Testing

**Backend (pytest):**
- `_provision`/`_license_state`: mode `open` → creates active comp license; `trial` → active
  with future `expires_at` + source `trial`; `paywall` → no row, state `none`.
- Idempotent: second call with a row present does not duplicate/overwrite.
- `_get_settings` default fallback when row absent.
- `GET/PUT /api/admin/settings`: returns defaults; updates persist; invalid mode/`trial_days`
  rejected; non-admin → 403.
- Existing gate tests stay green (autouse conftest bypass already in place).

**Web (vitest/RTL):** settings panel renders current mode, saves changes, shows `trial_days`
only for trial; admin page still lists subscribers.

**Phone (flutter):** router gate redirects an authenticated non-active **un-onboarded** user
to `/no-access`; an active un-onboarded user still reaches `/onboarding`.

**Live (prod, post-merge, owner-gated):** re-run the throwaway-test-user verification used for
#15, now across all three modes: set `paywall` → new user `none`/403; set `open` → new user
auto-active/200; set `trial` → new user active with expiry. Clean up the test user.

## Out of scope / follow-ups

- Web-checkout & Play Billing activation flows (`activation_source` reserved).
- Backend deploy + the phone-device visual verify of the gated first-run (after this lands).
