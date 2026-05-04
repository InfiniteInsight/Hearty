# Hearty — Web Dashboard (Spec 05) — Living Plan

**Spec:** [`hearty-05-web-dashboard.md`](../specs/2026-05-04-hearty-05-web-dashboard.md)  
**Roadmap Phase:** Phase 3 — Web Dashboard  
**Plan Status:** 🔴 Not Started  
**Last Updated:** 2026-05-04  
**Last Verified Against Spec:** 2026-05-04 — re-verify if spec has changed since  
**Open Deviations:** 0

---

## How to Use This Plan

1. Always start with **Phase 0** at the beginning of any new session on this plan
2. Find the first phase/task marked **🔴 Not Started**, mark it **🟡 In Progress**
3. Paste the phase's **Activation Prompt** into a new Claude Code session
4. Follow the steps — Claude will guide you through each one
5. At natural break points, Claude will tell you to run `/compact`; do so, then start a new session with the **Activation Prompt** at the top of the next phase
6. Mark completed phases **🟢 Completed** and log any deviations as a single line at the bottom

**Status key:** 🔴 Not Started · 🟡 In Progress · 🟢 Completed · ⚠️ Blocked · ↩️ Deviated

---

## Phase Summary

| Phase | Name | Status | Depends On | Type |
|---|---|---|---|---|
| 0 | Review & Align | 🔴 Not Started | — | Claude (start of every session) |
| 1 | Project Setup | 🔴 Not Started | — | Claude |
| 2 | Auth (Magic Link) | 🔴 Not Started | Phase 1 | Claude |
| 3 | Dashboard Layout & Navigation | 🔴 Not Started | Phases 1–2 | Claude |
| 4 | Journal Page | 🔴 Not Started | Phases 2–3 | Claude |
| 5 | Trends Page | 🔴 Not Started | Phases 2–3 | Claude |
| 6 | Reports & Export | 🔴 Not Started | Phases 2–3 | Claude |
| 7 | Profile & Settings Pages | 🔴 Not Started | Phases 2–3 | Claude |
| 8 | Integration Test | 🔴 Not Started | Phases 1–7 | Claude |

---

## Phase 0: Review & Align

**Status:** 🔴 Not Started  
**Goal:** Verify the dev environment, confirm the REST API dependency plan is complete, check the spec hasn't drifted from this plan, and identify exactly which phase to start or resume.  
**Run this phase at the start of every session on this plan.**

### Activation Prompt

```
You are running Phase 0 (Review & Align) for the Hearty Web Dashboard (Spec 05).
This runs at the start of every session — it takes 5 minutes and prevents
working from stale assumptions.

Working directory: /home/evan/projects/food-journal-assistant

Steps:

1. Read both files in full:
   - docs/superpowers/plans/2026-05-04-hearty-05-web-dashboard-plan.md  (this plan)
   - docs/superpowers/specs/2026-05-04-hearty-05-web-dashboard.md

2. Check dependency plan completion — read the Plan Status line from:
   - docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md
   This plan must show Plan Status: 🟢 Completed before Phase 1 can begin.

3. Check the dev environment (run each command):
   - node --version   (need >= 18)
   - npm --version
   - git status
   - ls hearty-web/ 2>/dev/null && echo "project exists" || echo "not yet created"

4. For the first upcoming non-zero phase (Phase 1 if project not yet created), also verify:
   - npm create vite@latest is available (run: npm create vite@latest --help or equivalent)
   - Supabase Magic Link is configured in the Supabase Dashboard (can only note this,
     can't verify programmatically — remind user to check if auth isn't working)

5. Spec drift check — the plan was written on 2026-05-04. Scan the spec for any
   changes to: project structure, key package versions, page list, auth flow,
   design system tokens. If you find anything that conflicts with this plan, list it.

6. Report:
   - Dependency plans: whether Spec 03 plan is complete
   - Environment: what is/isn't installed
   - Spec alignment: any drift found, or "clean"
   - Next action: which phase to proceed with (or what to fix/unblock first)

Before running any command, verify it exists with --help or equivalent.
If a command doesn't behave as expected, stop and tell me — don't improvise.

Update the plan: set Phase 0 status to 🟢 Completed and Last Updated to today.
```

**Deviation Log:** _None_

---

## Phase 1: Project Setup

**Status:** 🔴 Not Started  
**Goal:** Scaffold `hearty-web/` with Vite + React + TypeScript, configure TailwindCSS and shadcn/ui for dark mode, install all dependencies at spec-pinned versions, and verify the dev server starts cleanly.  
**Depends on:** Spec 03 plan complete  
**Type:** Claude

**Key deliverables:**
- `hearty-web/` created via `npm create vite@latest` with React + TypeScript template
- TailwindCSS 3.x configured with the dark-mode color palette from spec Section 3 (backgrounds `#1a1a2e`, `#16213e`, `#0f3460`; amber `#f59e0b`; teal `#14b8a6`)
- shadcn/ui initialized in dark mode; Inter and JetBrains Mono loaded via Google Fonts or local assets
- All spec-pinned packages installed: React 18.x, Vite 5.x, Recharts 2.x, TanStack Query 5.x, Zustand 4.x, React Router 6.x, Supabase JS 2.x
- Full directory structure from spec Section 2 created (`pages/`, `components/ui/`, `components/charts/`, `components/layout/`, `lib/`, `hooks/`, `types/`)
- `vite.config.ts` with `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_API_URL` env var references
- `npm run dev` starts without errors; `npm run build` produces clean output

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 2: Auth (Magic Link)

**Status:** 🔴 Not Started  
**Goal:** Implement Supabase magic link auth — login page, auth callback route, `ProtectedRoute` wrapper, session refresh handling, and sign-out — so all non-auth routes are gated.  
**Depends on:** Phase 1  
**Type:** Claude

**Key deliverables:**
- `lib/supabase.ts` — Supabase JS client initialized from `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`
- `lib/auth.ts` — helpers: `signInWithMagicLink(email)`, `signOut()`, `getSession()`
- `/login` page: email input + submit button; calls `supabase.auth.signInWithOtp({ email })`; shows "Check your email" confirmation
- `/auth/callback` route: exchanges token, establishes session, redirects to `/dashboard`
- `<ProtectedRoute>` component wrapping all app routes; unauthenticated requests redirect to `/login`
- `supabase.auth.onAuthStateChange` listener wired up at app root to handle session expiry and sign-out
- Sign-out button in Settings clears session and redirects to `/login`

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 3: Dashboard Layout & Navigation

**Status:** 🔴 Not Started  
**Goal:** Build the authenticated app shell with sidebar/header layout, React Router routes for all five pages, the Dashboard page with today's timeline and quick log input, and Supabase Realtime subscription for live sync.  
**Depends on:** Phases 1–2  
**Type:** Claude

**Key deliverables:**
- `components/layout/` — app shell with sidebar navigation (Dashboard, Journal, Trends, Reports, Profile, Settings) and header; responsive collapse on narrow viewports
- React Router v6 routes defined for all pages; lazy-loaded page components stub in for non-Dashboard pages
- Dashboard page: today's timeline (meals, symptoms, wellbeing), wellbeing score card, trend alert card (dismissable per session via Zustand), quick log text input wired to `POST /journal`
- Sync status indicator in header: pulses amber on Realtime disconnect
- `useRealtimeSync` hook: subscribes to Supabase Realtime `INSERT` events on `journal_entries` for the authenticated user; calls `queryClient.invalidateQueries(['journal'])` on event
- TanStack Query `QueryClient` provider wrapping the app; Zustand stores defined in `lib/store.ts`

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 4: Journal Page

**Status:** 🔴 Not Started  
**Goal:** Build the full Journal page with date-range + keyword + meal-type + symptom-type filters, paginated entry list, expanded detail view, and URL-persisted filter state.  
**Depends on:** Phases 2–3  
**Type:** Claude

**Key deliverables:**
- Two-panel layout on wide viewports (filter sidebar + entry list); single column on narrow
- Filters: date range picker, food keyword search, symptom type multi-select, meal type select — stored in Zustand and reflected in URL query params via React Router
- Entry list: 25-per-page pagination (or infinite scroll); each card shows timestamp (JetBrains Mono), description, food tags (amber badge), symptom severity (teal/amber/red badge), photo thumbnail if present
- Expandable detail view: full note, raw structured JSON behind "Show raw data" toggle, link to Trends page filtered to foods from that entry
- All data fetched from `GET /journal` via TanStack Query with 1-minute stale time

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 5: Trends Page

**Status:** 🔴 Not Started  
**Goal:** Build the Trends page with all four Recharts visualizations — trigger food ranking + heat map, symptom frequency line chart, correlation scatter/matrix, and time-of-day bar chart — with a shared period selector.  
**Depends on:** Phases 2–3  
**Type:** Claude

**Key deliverables:**
- Period selector (7d / 30d / 90d / custom date range) in Zustand; applies to all charts on the page
- `components/charts/` — Recharts wrappers with consistent dark-theme styling (surface `#16213e` background, muted axis labels, JetBrains Mono tick values)
- Trigger food ranking: ranked list with confidence score + occurrence count; toggle to heat map (food × symptom matrix, cell color = correlation strength)
- Symptom frequency line chart: one line per symptom type, hover shows specific entries
- Correlation scatter plot: food vs. symptom axes, point size/color encodes confidence
- Time-of-day bar chart: symptom occurrence by hour or meal-type bin
- All chart data from FastAPI `/trends` endpoints via TanStack Query, 5-minute stale time; loading skeletons shown while fetching

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 6: Reports & Export

**Status:** 🔴 Not Started  
**Goal:** Build the Reports page — date range picker, format selector (PDF/CSV/JSON), preview panel, and download trigger — wired to the FastAPI report generation endpoint.  
**Depends on:** Phases 2–3  
**Type:** Claude

**Key deliverables:**
- Date range picker with preview summary of what will be included
- Format selector: PDF, CSV, JSON
- PDF: POST to `/reports/generate` → receive signed Supabase Storage URL → trigger download
- CSV and JSON: GET to `/api/export/csv` and `/api/export/json` within selected date range → file download
- Preview panel: summary narrative (AI-generated, from API), counts of entries in range
- Loading state and error handling for report generation (PDF generation is async; poll or handle signed URL response)

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 7: Profile & Settings Pages

**Status:** 🔴 Not Started  
**Goal:** Build the Profile page (allergens, conditions, dietary protocols, non-dismissable disclaimer) and the Settings page (auth section, notification preferences, data management including account deletion).  
**Depends on:** Phases 2–3  
**Type:** Claude

**Key deliverables:**
- Profile page: Big 9 allergen toggle chips + custom allergen input; conditions multi-select list + custom text; dietary protocols multi-select + custom; persistent non-dismissable disclaimer (exact text from spec Section 4.5)
- Settings page: authenticated email display, sign-out, re-send magic link; notification preferences mirroring Android app (sync via `PUT /settings`); "Export all data" button; "Delete account" with typed-confirmation modal (calls `DELETE /account`)
- All profile changes written immediately to `PUT /profile`; TanStack Query mutations invalidate `['profile']` on success
- Notification preference changes written to `PUT /settings` and confirmed to sync back to mobile app

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 8: Integration Test

**Status:** 🔴 Not Started  
**Goal:** Run end-to-end integration tests against a live Supabase + FastAPI environment to confirm all pages load correctly, auth works, data flows are wired, and real-time sync functions.  
**Depends on:** Phases 1–7  
**Type:** Claude

**Key deliverables:**
- Auth flow: enter email → receive magic link → click link → land on Dashboard with session established
- Quick log: submit a meal from the Dashboard text input → confirm it appears in today's timeline without page refresh (Realtime sync)
- Journal: apply date + keyword filters → confirm URL query params update and entries filter correctly
- Trends: select 30d period → confirm all four charts render with data (or empty-state gracefully)
- Reports: generate a PDF for a 7-day range → confirm signed URL returned and file downloads
- Profile save: toggle an allergen → confirm saved to API → reload page → confirm persisted
- `npm run build` produces zero TypeScript errors; no console errors in production build

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Deviation Log

_Format: `[date] — Phase X, Task Y — changed X because Y`_

---

## Notes

- **Supabase Magic Link redirect URL:** Must be configured in the Supabase Dashboard (Authentication → URL Configuration) before Phase 2 auth works end-to-end. Production URL and `localhost:5173` redirect URLs both need to be registered.
- **Vercel deployment:** The spec specifies Vercel for hosting with automatic deploys from `main`. Deployment setup is not a phase in this plan — configure after Phase 8 integration test passes.
- **Photo uploads:** Web dashboard displays photo thumbnails from mobile entries (via signed Supabase Storage URLs) but does not support new photo uploads. Do not implement a camera/upload flow on web.
- **Voice input:** Not in scope for the web dashboard. The quick log input is text-only.
