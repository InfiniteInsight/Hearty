# Hearty — Web Dashboard (Re-validated Design)

**Spec ID:** hearty-05-web-dashboard (re-validated)
**Date:** 2026-06-21
**Status:** Approved (brainstorming)
**Supersedes:** [`2026-05-04-hearty-05-web-dashboard.md`](2026-05-04-hearty-05-web-dashboard.md) — the original is preserved for history; this document is the source of truth for implementation.

---

## 1. Why this re-validation exists

The original Spec 05 (2026-05-04) is directionally sound — a read-focused, big-screen companion to the Flutter phone app — but its API contract, auth flow, and feature set predate almost everything Hearty has shipped since (the unified signal engine, trends conversation, tracked experiments, food-intelligence, structured health profile, offline-first sync). Executing it as-written would build against endpoints and tables that do not exist. This document re-validates the design against the **actual** backend as of 2026-06-21 and folds in four product decisions made during brainstorming.

### 1.1 Re-validation deltas (original spec → this spec)

| Original spec | Reality / decision |
|---|---|
| Magic-link auth | **Google OAuth** — matches the phone (`signInWithIdToken(provider: google)`); Supabase already configured |
| `GET/POST /journal` | `GET/POST /api/meals` + separate `/api/symptoms` |
| `GET/PUT /profile` | `GET/PUT/PATCH /api/health-profile` (structured) |
| `GET/PUT /settings` | `GET/PUT /api/preferences` |
| Generic "Recharts everything" Trends | **Signal-engine Trends** off `GET /api/trends` (design-guide vocabulary) |
| (absent) | **Trends-conversation chat** + **Experiments page** added |
| `POST /reports/generate` → Supabase Storage signed URL | `POST /api/export/pdf` returns **raw PDF bytes**; CSV/JSON are GET downloads |
| Photo thumbnails on journal entries | **Dropped** — meal payloads carry no photo URL; no backend support |
| Realtime on `journal_entries` table | Realtime on **`meals` + `symptoms`** tables (the real tables) |
| Dark-clinical `#1a1a2e` palette | **Aurora** palette, built on CSS variables (themeable later) |
| `DELETE /account` exists | **Does not exist** — we build a new `DELETE /api/account` |
| Per-item calories shown | **No calories** anywhere — Hearty is a trigger journal, not a calorie counter |

### 1.2 Decisions locked in brainstorming
- **Scope:** full re-validated dashboard (all pages) **+** signal-engine Trends **+** trends-conversation chat **+** Experiments page.
- **Account deletion:** included — build a real `DELETE /api/account` (destructive cascade + Supabase auth-user deletion).
- **Live sync:** **Both** — Supabase Realtime when connected, refetch-on-focus + light polling as fallback.
- **Visual identity:** **Aurora** palette now, implemented via CSS variables so the other two design-guide palettes (Cosmic Bloom, Warm & Grounded) drop in later. No backend theme field this build.

---

## 2. Architecture

A new **`hearty-web/`** Vite + React + TypeScript single-page app. It is **online-only** (no offline-first; that is the phone's job) and talks **exclusively** to the FastAPI REST API for application data, plus Supabase directly for **auth** and **Realtime** only.

```
hearty-web/
  index.html
  vite.config.ts
  tailwind.config.ts
  src/
    main.tsx
    App.tsx
    router/                 — React Router v6 routes + <ProtectedRoute>
    lib/
      supabase.ts           — Supabase JS client (auth + realtime only)
      api.ts                — REST client; attaches Bearer JWT; typed methods
      auth.ts               — signInWithGoogle, signOut, getSession
      queryClient.ts        — TanStack QueryClient config (stale times, refetch-on-focus)
      store.ts              — Zustand UI state (filters, period, dismissed alerts, sidebar)
    theme/
      tokens.css            — Aurora palette as CSS variables (:root), one block per palette later
    types/
      api.ts                — TypeScript types mirroring backend Pydantic shapes (Section 7)
    hooks/
      useRealtimeSync.ts    — Supabase Realtime on meals + symptoms → invalidate queries
      useMeals.ts useSymptoms.ts useTrends.ts useConversation.ts
      useExperiments.ts useProfile.ts usePreferences.ts useSummary.ts
    components/
      ui/                   — shadcn/ui base (dark)
      charts/               — Recharts wrappers (Aurora-themed)
      layout/               — AppShell, Sidebar, Header (sync indicator)
      signals/              — StrongestSignalHero, SignalCard, StrengthBar
    pages/
      Dashboard.tsx Journal.tsx Trends.tsx Conversation.tsx
      Experiments.tsx Reports.tsx Profile.tsx Settings.tsx
      Login.tsx AuthCallback.tsx
```

### 2.1 Key dependency versions
React 18.x · Vite 5.x · TypeScript 5.x · TailwindCSS 3.x · shadcn/ui (latest) · Recharts 2.x · TanStack Query 5.x · Zustand 4.x · React Router 6.x · Supabase JS 2.x · Vitest + React Testing Library + MSW (tests).

### 2.2 Environment variables
| Variable | Purpose |
|---|---|
| `VITE_SUPABASE_URL` | Supabase project URL (auth + realtime) |
| `VITE_SUPABASE_ANON_KEY` | Supabase anon key (client-safe; RLS enforces access) |
| `VITE_API_URL` | FastAPI base URL |

Backend prerequisite: set `ALLOWED_ORIGINS` to the web origin(s) in production (dev defaults to `*`). Supabase Auth → URL Configuration must register the web redirect URLs (`http://localhost:5173` for dev + the production origin) for the Google OAuth callback.

---

## 3. Auth flow (Google OAuth)

1. Unauthenticated visit → `<ProtectedRoute>` redirects to `/login`.
2. Login page: a single **"Continue with Google"** button → `supabase.auth.signInWithOAuth({ provider: 'google', options: { redirectTo: <origin>/auth/callback } })`.
3. Google consent → redirect to `/auth/callback`; the Supabase JS client establishes the session from the URL; redirect to `/dashboard`.
4. The session JWT is stored by Supabase JS (localStorage). `lib/api.ts` reads the current session and attaches `Authorization: Bearer <token>` to every FastAPI request. The backend `get_current_user` (`app/auth.py`) validates it via `supabase.auth.get_user(token)`.
5. `supabase.auth.onAuthStateChange` at the app root reacts to expiry/sign-out (clears React Query cache, redirects to `/login`).

Same Supabase project + same Google identity as the phone ⇒ **same user**, same data, across devices.

---

## 4. Live sync (Both)

- `useRealtimeSync` (mounted in the authenticated shell): subscribes via Supabase Realtime to `INSERT` (and `UPDATE`/`DELETE`) events on `public.meals` and `public.symptoms`, filtered to the authenticated `user_id`. On any event → `queryClient.invalidateQueries` for `['meals']` / `['symptoms']` / `['summary']` / `['trends']` as appropriate.
- **Fallback:** TanStack Query `refetchOnWindowFocus: true` plus a modest polling interval (e.g. 60s) on the journal/dashboard queries, so freshness survives a dropped socket.
- **Indicator:** the header shows a sync dot — steady when the Realtime channel is `SUBSCRIBED`, pulsing amber when `CHANNEL_ERROR`/`TIMED_OUT`/closed. A manual refresh button is always present.
- **Prereq:** Realtime must be enabled for the `meals` and `symptoms` tables in Supabase; the subscription relies on RLS scoping with the anon key + the user session.
- **Offline-first caveat (documented, not a bug):** the phone writes locally and syncs later, so web "live" updates land when the phone's background sync push reaches the backend — near-instant in practice, but not before the phone syncs.

---

## 5. Pages

All list/data fetches go through TanStack Query; mutations invalidate the relevant keys. Numeric values, timestamps, and codes render in **JetBrains Mono**; everything else in the design-guide UI font. **No calories** are ever displayed (the `foods[].estimated_calories` field is ignored).

### 5.1 Dashboard (`/dashboard`)
- **Today's timeline** — merge of `GET /api/meals?start=<today>` and `GET /api/symptoms?start=<today>`, chronological. Each row: time (mono), description, food-name badges, linked symptom severity badges.
- **Today/period card** — `GET /api/summary?period=week`: `summary_text`, `meals_logged`, `top_symptoms`.
- **Strongest signal card** — the highest `unified_score` signal from `GET /api/trends` (the hero, condensed), linking to Trends.
- **Quick log** — single text field → `POST /api/meals` (`{ description, input_method: 'text' }`); AI extraction runs server-side; on success clears + invalidates `['meals']`/`['summary']`. Text only (no voice/photo on web).
- **Sync indicator** in the header (Section 4).

### 5.2 Journal (`/journal`)
- Two-panel on wide viewports (filter sidebar + list); single column when narrow.
- **Filters → query params:** date range (`start_date`/`end_date`), keyword (`keyword`), meal type (`meal_type`), symptom type (filters the symptom view). Stored in Zustand, mirrored to URL query params (survive refresh).
- **Entry list:** `GET /api/meals` with `limit`/`offset` pagination (25/page). Card: timestamp (mono), description, food-name badges (amber), linked-symptom severity badges (teal mild / amber moderate / red severe), expand chevron.
- **Expanded detail:** full `notes`, raw structured JSON behind a "Show raw data" toggle, link to Trends. **No photo thumbnail** (unsupported by the payload).
- Editing/deleting an entry (`PATCH`/`DELETE /api/meals/{id}`, `/api/symptoms/{id}`) is available from the expanded view (foods edited as a verbatim name list, mirroring the phone's edit semantics).

### 5.3 Trends (`/trends`)
Built to the design guide's Trends vocabulary off `GET /api/trends` (`SignalsResponse`).
- **Header** — "Trends" + eyebrow (`analyzed_at` + `total_meals_analyzed` etc.) + **Analyse** pill → `POST /api/trends/analyze`, polling `GET /api/trends/analyze/status` until done, then invalidate `['trends']`.
- **Strongest-signal hero** — highest `unified_score`: `category_label`, the dominant channel's `outcome_name`, a 3-up stat row (relative risk · peak window · evidence count).
- **Food Signals list** — one card per `FoodSignal`: gradient icon chip, `category_label` + dominant channel subline (`→ outcome · peaks ~Nmin`), right-aligned relative risk colored by `direction` (harmful = accent, beneficial = `--good`), a **strength bar** (width ∝ `unified_score`), meta row (`based on N logs` from `evidence_count`) + **CONVERGENT** badge when `convergent`. New/recurring/resolved states reflected (`is_new`, `recurring`, `resolved[]`).
- **Charts (Recharts):** symptom-frequency over the period; meal-type mix (stacked proportion). Period selector (7d/30d/90d/custom) in Zustand.
- **Per-signal verdict** — confirm/dispute/snooze → `POST /api/trends/signal-verdict`.

### 5.4 Trends Conversation (`/trends/chat`, or a tab within Trends)
- Chat UI over `POST /api/trends/conversation` (sends `history: ConversationTurn[]`). Renders `reply`.
- When the response carries `proposed_verdict`, show a one-click **confirm/dispute/snooze** action → `POST /api/trends/signal-verdict`.
- When it carries `proposed_experiment`, show a **Start experiment** action → `POST /api/experiments`.
- `is_closing` ends the session gracefully.

### 5.5 Experiments (`/experiments`)
- `GET /api/experiments/active` → list of `ExperimentResponse` (active + recent), showing `category_label`, direction/outcome, window, `status`, computed `adherence` / `logged_days`, and a nudge indicator when `nudge_suggested`.
- Actions: **Start** (`POST /api/experiments` — from a signal or manual), **Evaluate** (`/evaluate`), **Restart** (`/restart`), **Abandon** (`/abandon`), **Ack nudge** (`/ack-nudge`). Mutations invalidate `['experiments']`.
- Result rendering when `result` is present (verdict + supporting numbers).

### 5.6 Reports (`/reports`)
- Date range picker → **preview** (entry counts + `summary_text` from `GET /api/summary?period=custom&start&end`).
- **Export formats:**
  - **PDF** — `POST /api/export/pdf` with `{ start_date, end_date }` → response is **`application/pdf` bytes**; client turns the blob into a download (not a signed URL).
  - **CSV** — `GET /api/export/csv?start_date&end_date` → `text/csv` stream → download.
  - **JSON** — `GET /api/export/json?start_date&end_date` → JSON object → download.
- Loading + error states for each; PDF generation may take a moment (synchronous byte response).

### 5.7 Profile (`/profile`)
- Structured health profile via `GET /api/health-profile` (`HealthProfileResponse`) and `PUT /api/health-profile` (full replace) — optionally `PATCH` for partial saves.
  - **Allergens** — `AllergenEntry{ name, severity(mild|moderate|severe), reaction?, confirmed_by_doctor, notes? }`; seed suggestions from `GET /api/health-profile/defaults`.
  - **Intolerances** — `IntoleranceEntry{ name, severity?, threshold?, notes? }`.
  - **Conditions** — `ConditionEntry{ name, diagnosed, diagnosis_year?, notes? }`.
  - **Dietary protocols** — `DietaryProtocolEntry{ name, active, started?, phase?, notes? }`.
- Persistent, **non-dismissable disclaimer** (verbatim): "Hearty is not a medical device. Information provided is for personal tracking only and does not constitute medical advice. Always consult a qualified healthcare professional."

### 5.8 Settings (`/settings`)
- **Notifications & behavior** via `GET/PUT /api/preferences` (`UserPreferencesSchema`): nudge delay, post-meal nudge, daily/weekly toggles, the three check-in slots (enabled + hour/minute), conversation style (`warm`/`concise`), and the voice prefs (read-only or hidden on web where they only affect the phone).
- **Account:** authenticated email; **Sign out** (clears session → `/login`).
- **Data management:** **Export all data** (JSON, no date range); **Delete account** — typed-confirmation modal ("delete my account") → `DELETE /api/account` (Section 6), then sign out + redirect.

---

## 6. New backend work: `DELETE /api/account`

No deletion endpoint exists today. Add `DELETE /api/account` (auth required) in a new `app/routers/account.py`:

1. Resolve `user_id` from `get_current_user`.
2. Service-key cascade delete of all rows where `user_id = <id>` across every user-scoped table: `meals`, `symptoms`, `photos` (and their Supabase Storage objects), `experiments`, `wellbeing_snapshots`, `food_triggers`, `health_profile`, `notification_prefs` (and any preferences row), plus any other user-scoped tables present at implementation time (enumerate by inspecting the schema; do not hardcode blindly).
3. Delete the Supabase **auth user** via the admin API (`supabase.auth.admin.delete_user(user_id)` with the service-role key).
4. Return `204`. Idempotent-ish: a second call for an already-deleted user returns `204`/`404` cleanly.

TDD: a pytest test mocks the supabase client and asserts every table delete is issued for the user and `admin.delete_user` is called; an auth-required test; an ordering test (child rows before auth user). The destructive nature is gated client-side by typed confirmation.

---

## 7. TypeScript types (mirror these backend shapes)

Define in `src/types/api.ts`, mirroring the verified Pydantic models. Key shapes (field names verbatim):

- **FoodItem** `{ name: string; quantity?: string; estimated_calories?: number; preparation?: string }` — `estimated_calories` ignored in UI.
- **SymptomResponse** `{ id; meal_id?; symptom_type; severity?(1-10); onset_minutes?; duration_minutes?; bathroom_urgency?(0-5); bathroom_visits?; stool_consistency?(1-7); notes?; logged_at }`.
- **MealWithSymptoms** `{ id; description; meal_type?; foods?: FoodItem[]; location?; mood_before?; hunger_before?; logged_at; input_method?; notes?; created_at; symptoms: SymptomResponse[] }`.
- **MealsListResponse** `{ total: number; meals: MealWithSymptoms[] }`.
- **SignalChannel** `{ outcome_type:'symptom'|'wellbeing'; outcome_name; direction:'harmful'|'beneficial'; peak_window_minutes?; meal_slot?; wellbeing_slot?; relative_risk?; score_delta?; evidence_count }`.
- **FoodSignal** `{ category; category_label?; unified_score; channels: SignalChannel[]; convergent; years_seen:number[]; recurring; is_new; strength_by_year: Record<string,number> }`.
- **SignalsResponse** `{ signals: FoodSignal[]; analyzed_at?; total_meals_analyzed; total_symptoms_analyzed; total_wellbeing_analyzed; resolved: { category; category_label?; last_year; strength; status:'resolved'|'potentially_resolved' }[] }`.
- **TrendsConversationRequest** `{ history: { role:'user'|'assistant'; content:string }[] }`; **TrendsConversationResponse** `{ reply; proposed_verdict?; proposed_experiment?; is_closing }`.
- **ExperimentResponse** `{ id; category; category_label?; direction; outcome_type; outcome_name; experiment_start; experiment_end; status; result?; nudged_at?; adherence?; logged_days?; nudge_suggested }`.
- **UserPreferencesSchema** — full notification/check-in/conversation/voice + health string lists (see `preferences.py:14-49`).
- **HealthProfileResponse** — allergens/intolerances/conditions/dietary_protocols entries + `updated_at` (see `health_profile/schemas.py:60`).
- **SummaryResponse** `{ period; start_date; end_date; summary_text; meals_logged; top_symptoms: {symptom_type;count;avg_severity?}[]; top_triggers: TriggerFood[] }`.

(Endpoints, params, and citations are catalogued from the backend at brainstorming time; the plan re-verifies any shape it touches.)

---

## 8. State management
- **Server state — TanStack Query.** Namespaced keys: `['meals',{filters,page}]`, `['symptoms',{filters}]`, `['trends']`, `['summary',{period}]`, `['experiments']`, `['profile']`, `['preferences']`. Stale times: trends/summary 5 min, meals/symptoms 1 min. `refetchOnWindowFocus: true`. Mutations invalidate relevant keys; Realtime events invalidate too.
- **UI state — Zustand** (`lib/store.ts`): journal filters, trends period, dashboard session-dismissed alerts, sidebar collapse.

---

## 9. Design system (Aurora, CSS variables)
- Implement the design-guide **Aurora** palette as CSS variables in `theme/tokens.css` under `:root` (bg gradient `#0F1F2E→#112240`, `--accent-green #34D399`, `--accent-violet #8B5CF6`, `--accent-red #F87171`, `--good #34D399`, text/muted/border tokens, glass card surfaces). Tailwind reads these via `theme.extend.colors`. Structuring as variables means Cosmic Bloom / Warm & Grounded ship later by adding palette blocks — no component rewrites.
- Typography per guide: a serif display (Fraunces or equivalent) for headings/wordmark, a sans (Plus Jakarta Sans) for body, **JetBrains Mono** for data/timestamps. The split "Heart**y**" wordmark (accent "y").
- shadcn/ui configured dark; Recharts wrappers themed to the surface/border/muted tokens.
- Trends uses the guide's **direction encoding**: trigger signals use the accent gradient + "up/risk" reading; beneficial signals use `--good` + a lower bar — the one intentional divergence from a single accent.

---

## 10. Testing
- **Unit/component:** Vitest + React Testing Library. Mock `lib/api.ts` and the Supabase client. Cover: `<ProtectedRoute>` redirect; quick-log mutation; journal filter→URL sync; SignalCard direction/convergent rendering; conversation proposed-action wiring; experiment actions; profile save; settings delete-account typed-confirmation gating.
- **Contract:** MSW handlers shaped to Section 7 types, asserting requests/queries match the documented endpoints.
- **Build gate:** `npm run build` is type-clean; no console errors in the production build.
- **Backend:** pytest for `DELETE /api/account` (cascade issued per table, `admin.delete_user` called, auth required, child-before-user ordering).
- **Integration (final phase):** auth → land on dashboard; quick-log appears without manual refresh (Realtime); journal filters reflect in URL; Trends renders signals or empty-states; PDF/CSV/JSON download; profile persists across reload; delete-account flow end-to-end against a throwaway user.

---

## 11. Hosting
Vercel, auto-deploy from the web repo's main branch; preview deploys on PRs. Set `VITE_*` env vars in Vercel; set backend `ALLOWED_ORIGINS` + Supabase redirect URLs to include the production origin. Deployment configured after the integration phase passes.

---

## 12. Delivery shape (phases — detailed in the implementation plan)
One spec, one phased plan; each phase independently testable:
0. Project setup (Vite/TS/Tailwind/shadcn/Aurora tokens/typed API client skeleton).
1. Auth (Google OAuth + ProtectedRoute + session lifecycle).
2. App shell + Dashboard + Realtime/refetch sync.
3. Journal (filters→URL, pagination, expand, edit/delete).
4. Trends (signal hero + cards + charts + analyse + verdict).
5. Trends Conversation (chat + proposed verdict/experiment actions).
6. Experiments (list + lifecycle actions).
7. Reports (PDF/CSV/JSON + preview).
8. Profile + Settings + **`DELETE /api/account`** (backend + UI).
9. Integration test + Vercel deploy.

---

## 13. Out of scope (this build)
Voice input; photo capture/upload and photo thumbnails; the three-palette theme switcher and a synced `theme` preference (Aurora-only now, architected for later); check-in gap-resolution UI (phone-centric nudge flow — may be a later web add); any calorie/macro display.

---

*End of re-validated spec.*
