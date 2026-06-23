# Hearty — Admin / Owner Dashboard (Design)

**Status:** Draft for review
**Date:** 2026-06-22

## 1. Why this exists

The server owner needs owner-only tooling to administer how the app serves its users: control who has access (licensing), monitor the running services, and (later) route individual subscribers to specific LLM backends. Today none of this exists — there is no admin/role concept, no license/subscription concept, and LLM selection is a single **global** env config (`LLM_MODEL` + optional `LLM_BASE_URL`) used by `ai_extraction` and `trends_conversation`.

## 2. Decomposition (this spec vs later specs)

The admin dashboard is three independent subsystems on a shared foundation. They ship as separate spec → plan → build cycles:

| # | Capability | Status |
|---|---|---|
| **Foundation** | Owner-only admin auth + a gated `/admin` surface + a subscriber view | **This spec** |
| **#2 Licensing / access control** | Grant / revoke / expire per-user access; gate all app data on an active license | **This spec** |
| #3 Service monitoring | Health + usage of backend / Supabase / LLM endpoints | Next spec (separate) |
| #1 Per-user LLM routing | Assign a subscriber an LLM backend (incl. their own local LLM) | **Deferred** — blocked on Spec 12 (local-LLM) actually being built into the app first |

**This spec covers the Foundation + Licensing (#2) only.** Payment/billing is explicitly out of scope (see §8).

## 3. Decisions locked in brainstorming

- **Surface:** a gated `/admin` area inside the existing `hearty-web` React app (reuses its auth, API client, Aurora UI, build/deploy) — not a separate admin app.
- **Owner auth:** Supabase **`app_metadata.role = "admin"`**, set once via the Supabase admin API, **enforced server-side** on every `/api/admin/*` endpoint. The `/admin` UI gate is convenience only; security is the API. Never `user_metadata` (user-editable).
- **License gates all data access:** no/revoked/expired license → the user-facing data API returns **403**; the client shows a "no active access — contact the owner" state. Login (Supabase) still works; the *data layer* is gated.
- **Manual grant/revoke only**, from `/admin`. **No billing.** The license is **payment-channel-agnostic**: an `activation_source` field (`manual` / `web_checkout` / `play_billing` / `comp`) leaves a seam so a future web-checkout (Stripe) or Play-Billing webhook just writes the same row.
- **Distribution model (informs the design, not built here):** the Android app stays a **free, license-gated SaaS client**; purchase/account management happens **on the web, outside the app** (the "reader app" pattern) to sidestep Play billing/anti-steering rules and the store fee cut. The app never sells or links to checkout. ⚠️ Play billing/anti-steering policy is in flux (post-*Epic*, EU DMA) and region-dependent — verify current policy before adding any web-checkout path; not relevant to this spec since payment is out of scope.
- **Model shape:** `gate-all-access` + `expires_at` (nullable) + `tier` (reserved, no behavior yet) + `activation_source`.

## 4. Architecture

- **Backend:** new `app/routers/admin.py` (`/api/admin/*`, admin-only) + a new `licenses` table + a license-gate dependency layered onto the existing auth.
- **Admin auth dependency:** `get_current_admin` — validates the bearer token via `supabase.auth.get_user(token)`, then checks `user.app_metadata["role"] == "admin"`; else 403. Used by all `/api/admin/*`.
- **License gate dependency:** `require_active_license` — runs after `get_current_user`, looks up the caller's `licenses` row (service-key client), allows iff `status == "active"` and (`expires_at` is null or in the future); else 403 `{"detail": "no_active_license"}`. Applied to user-facing data routers (meals, symptoms, trends, summary, experiments, export, preferences, health-profile, photos, food, checkin). **Not** applied to: auth/hooks, `GET /api/license/status`, and `/api/admin/*` (admin gated by role instead).
- **Web:** a gated `/admin` route tree in `hearty-web` (owner role), built with the existing Aurora UI + an extended API client.

## 5. Data model — `licenses`

A new Supabase table (migration via the project's dry-run-then-apply flow):

| column | type | notes |
|---|---|---|
| `id` | uuid pk | default gen_random_uuid() |
| `user_id` | uuid | FK → `auth.users(id)` on delete cascade; **unique** (one license per user) |
| `status` | text | `'active'` \| `'revoked'` (check constraint) |
| `expires_at` | timestamptz null | null = indefinite; past = expired (gate treats as inactive) |
| `tier` | text null | reserved; no behavior in this spec |
| `activation_source` | text | `'manual'`\|`'web_checkout'`\|`'play_billing'`\|`'comp'`; default `'manual'` |
| `granted_by` | uuid null | admin `user_id` who granted/last-changed |
| `notes` | text null | free-form owner note |
| `created_at` | timestamptz | default now() |
| `updated_at` | timestamptz | default now() |

**RLS:** enabled; **no `anon`/`authenticated` policies** (service-key writes/reads only — the gate runs server-side with the service key). This keeps license state server-authoritative and off the client.

**Account-deletion:** the FK `on delete cascade` covers DB cleanup; also add `licenses` to the `DELETE /api/account` cascade list (Plan 4 / web) for explicitness.

## 6. Endpoints

### Access-state (auth required, NOT license-gated)
- `GET /api/license/status` → `{ status: 'active'|'none'|'revoked'|'expired', expires_at? }` — lets any logged-in client render the gated state without tripping the 403.

### Admin (require `get_current_admin`)
- `GET /api/admin/users` → list of `{ user_id, email, created_at, license: {status, expires_at, tier, activation_source}|null }` (joins auth users via the admin API + the `licenses` table). Small scale now; pagination deferred.
- `POST /api/admin/licenses` → grant/upsert: `{ user_id, expires_at?, tier?, notes? }` → active license, `activation_source='manual'`, `granted_by=<admin>`.
- `PATCH /api/admin/licenses/{user_id}` → edit `{ expires_at?, tier?, status?, notes? }`.
- `POST /api/admin/licenses/{user_id}/revoke` → `status='revoked'`.
- `POST /api/admin/licenses/{user_id}/reactivate` → `status='active'`.

(Grant by `user_id`; the users list provides the id + email lookup.)

## 7. Rollout safety

The migration that creates `licenses` also **backfills an `active` license (`activation_source='comp'`) for every existing `auth.users` row**, so enabling the gate never locks out current users. The owner then: (1) gets `app_metadata.role='admin'` set once (documented runbook step / a one-off script), (2) manages everyone from `/admin`.

## 8. Web `/admin` UI

- Gated `/admin` route (owner role; redirect non-admins). Reuses Aurora components + an extended `api.ts` (`getAdminUsers`, `grantLicense`, `revokeLicense`, `reactivateLicense`, `updateLicense`, `getLicenseStatus`).
- **Subscribers view:** table of users — email, signup date, license status (active/revoked/expired/none), expiry, tier. Row actions: **Grant** (with optional expiry/tier/notes), **Revoke**, **Reactivate**, **Edit expiry**.
- **Gated-state UX (all clients):** on `403 no_active_license` (or via `GET /api/license/status`), the web app and the phone app show a non-dismissable "No active access — contact the owner" screen instead of the dashboard.

## 9. Out of scope (this spec)

- **Payment / billing** (separate later spec; `activation_source` seam is ready).
- **Per-user LLM routing (#1)** — deferred until Spec 12 (local-LLM) is built into the app.
- **Service monitoring (#3)** — its own next spec.
- **Multi-tier capability differences** — `tier` column reserved only.
- **Phone-side "no access" screen polish** — backend returns the 403/status; phone UI wiring can be a small follow-up if not done with this.

## 10. Testing

- **Backend (pytest):** `require_active_license` (active → allow; revoked / expired / missing → 403 `no_active_license`); `get_current_admin` (non-admin → 403 on `/api/admin/*`; admin → allow); grant / revoke / reactivate / edit endpoints (mocked supabase); `GET /api/license/status` shapes; rollout backfill logic. Mirror the existing endpoint-unit test style (`TestClient` + `dependency_overrides` + monkeypatched `supabase`).
- **Web (Vitest + RTL + MSW):** `/admin` route gates non-admins out; subscribers list renders; grant/revoke/reactivate flows hit the right endpoints; the gated "no access" state renders on `no_active_license`.
- **Migration:** dry-run, verify `licenses` schema + RLS + backfill, then apply.

## 11. Security checklist (Supabase)

- Admin role in **`app_metadata`**, validated **server-side** from the token; never trust client/`user_metadata`.
- `licenses` RLS **enabled**, **no anon/authenticated access** — service-key only.
- License gate enforced in the **API** (the UI gate is cosmetic).
- Account deletion removes the `licenses` row (FK cascade + explicit cascade list).

---

*Sub-spec of the Admin/Owner Dashboard initiative. Next sub-spec: Service Monitoring (#3). Deferred: Per-user LLM routing (#1, blocked on Spec 12).*
