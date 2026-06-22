# Hearty Web Dashboard

A React big-screen companion to the Hearty phone app. Online-only (no local-first sync). Authenticates via Supabase, fetches data from the FastAPI REST API, and subscribes to live updates via Supabase Realtime.

This repository contains **Plan 1 — Foundation**: auth flow + live Dashboard page. Journal, Trends, Experiments, Reports, Profile, and Settings routes are placeholders (`ComingSoon`) to be built in later plans.

---

## Stack

| Layer | Choice |
|---|---|
| Bundler | Vite 8 |
| UI framework | React 19 + TypeScript |
| Routing | React Router 6 |
| Server state | TanStack Query v5 |
| Client state | Zustand |
| Styling | Tailwind CSS v3 + shadcn/ui (dark mode, Aurora tokens) |
| Auth + Realtime | Supabase JS v2 |
| Testing | Vitest + React Testing Library + MSW v2 |

---

## Environment Variables

Copy `.env.example` to `.env` (gitignored) and fill in the values:

```
VITE_SUPABASE_URL=        # your Supabase project URL
VITE_SUPABASE_ANON_KEY=   # your Supabase anon/public key
VITE_API_URL=http://localhost:8080   # FastAPI base URL
```

The `.env.example` file already contains the correct key names and a sensible default for `VITE_API_URL`.

---

## Scripts

```bash
npm run dev          # start Vite dev server (http://localhost:5173)
npm run build        # type-check + production build → dist/
npm run test -- --run # run all tests once (Vitest, no watch)
npm run lint         # ESLint
```

---

## Auth

Google OAuth via Supabase (same provider as the phone app). After OAuth completes, Supabase redirects to `/auth/callback`, where the Supabase SDK's `detectSessionInUrl` detects the session from the callback URL and navigates to `/dashboard`.

### Redirect URL registration (required)

In the Supabase Dashboard go to **Authentication → URL Configuration** and add:

- `http://localhost:5173/auth/callback` — development
- `https://<your-production-origin>/auth/callback` — production

Without these entries the OAuth callback will be rejected.

---

## Backend Prerequisite

The FastAPI server must allow the web origin in CORS. Set the `ALLOWED_ORIGINS` environment variable on the server to include the web app's origin. The dev default is `*`; tighten this for production.

---

## Realtime Prerequisite

Supabase Realtime `postgres_changes` delivers only rows the user's JWT can SELECT under Row Level Security. Because the backend uses the service key (bypassing RLS), the `meals` and `symptoms` tables may have RLS enabled with **no** client SELECT policy — in which case Realtime delivers nothing to the browser.

To enable live updates:

1. In the Supabase Dashboard, enable **Realtime** on the `meals` and `symptoms` tables (Table Editor → table settings → Realtime toggle).
2. Add an `authenticated` own-rows SELECT policy to each table:

```sql
-- meals
create policy "users can select own meals"
  on meals for select
  to authenticated
  using (user_id = auth.uid());

-- symptoms
create policy "users can select own symptoms"
  on symptoms for select
  to authenticated
  using (user_id = auth.uid());
```

If these policies are absent, Realtime is best-effort and the Dashboard will fall back to the guaranteed freshness paths: refetch-on-window-focus (TanStack Query) and the manual Refresh button in the Header. Verify after deploying which path is in effect.

---

## Theme

Aurora palette only in this build, implemented as CSS custom properties in `src/theme/tokens.css`. The other palettes from the design guide (Cosmic Bloom, Warm & Grounded) can be added later by swapping token values.

Brand-green utilities: `brand` color, `bg-brand`, `text-brand`. shadcn/ui uses its own `accent` variable and is kept separate from brand tokens.

---

## Testing

Vitest + React Testing Library + MSW. The MSW server is configured with `onUnhandledRequest: "error"`, so every network call made during a test must have an explicit handler. Add handlers in `src/test/msw/handlers.ts` or inline per test.

```bash
npm run test -- --run   # run once
npm run test            # watch mode
```

---

## Project Structure (src/)

```
src/
  components/
    layout/       # AppShell, Header, Sidebar, SyncIndicator
    signals/      # StrongestSignalHero
    ui/           # shadcn-generated primitives
  hooks/          # useMeals, useSymptoms, useSummary, useTrends, useRealtimeSync, useDashboardData
  lib/            # api.ts, auth.ts, supabase.ts, store.ts, queryClient.ts, time.ts, utils.ts
  pages/          # Login, AuthCallback, Dashboard, ComingSoon
  router/         # ProtectedRoute
  test/           # Vitest setup, MSW handlers, shared test utilities
  theme/          # tokens.css (Aurora CSS variables)
  types/          # shared TypeScript types
  App.tsx
  main.tsx
  index.css
```

---

## Deployment (Vercel)

The web app is a Vite SPA in `hearty-web/`. Vercel hosts it with **Root Directory = `hearty-web`** (framework preset: **Vite**, build `npm run build`, output `dist`). `vercel.json` adds the SPA rewrite so deep links and refreshes resolve to `index.html`.

### One-time setup (Vercel dashboard)
1. **Import the GitHub repo** into a new Vercel project; set **Root Directory = `hearty-web`**.
2. **Environment variables** (Production + Preview):
   - `VITE_SUPABASE_URL` — your Supabase project URL
   - `VITE_SUPABASE_ANON_KEY` — the Supabase anon/publishable key (safe for the browser; never the service key)
   - `VITE_API_URL` — the deployed FastAPI base URL (e.g. `https://api.hearty.app`)
3. **Deploys:** production builds from `master`; every PR gets a preview URL.

### Supabase Auth (per origin)
Add the app origins to **Supabase → Authentication → URL Configuration → Redirect URLs**:
- `https://<your-prod-domain>/auth/callback`
- `https://<your-vercel-preview-domain>/auth/callback` (or the wildcard preview pattern)
- `http://localhost:5173/auth/callback` (local dev)

### Backend CORS
Set the FastAPI backend's `ALLOWED_ORIGINS` env to include the production (and preview) origins, e.g. `ALLOWED_ORIGINS=https://<your-prod-domain>,https://<preview>`. (Defaults to `*`; lock it down for production.)

### Realtime prerequisite
For live sync, `meals`/`symptoms` need Realtime enabled + an `authenticated` own-rows SELECT RLS policy (see the realtime note in this README); otherwise refetch-on-focus + manual Refresh is the guaranteed path.
