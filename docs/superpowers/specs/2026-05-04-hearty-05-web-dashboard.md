# Hearty — Phase 3: Web Dashboard

**Spec ID:** hearty-05
**Date:** 2026-05-04
**Phase:** 3 of 4
**Status:** Draft

---

## 1. Overview

The Hearty web dashboard is a secondary interface designed for big-screen analysis, trend review, and data export. The primary client is the Flutter Android app (Phase 2). The web dashboard does not attempt to replicate the full mobile experience — it is optimized for the tasks that benefit from a larger viewport: reading charts, filtering long history, generating reports, and managing health profile data.

### Scope of Phase 3

Phase 3 ships a React web application that:

- Authenticates users via Supabase magic link
- Reads and writes data through the FastAPI REST API (built in Phase 1)
- Displays today's summary, full journal history, trend analysis, and health profile
- Generates and exports PDF, CSV, and JSON reports
- Subscribes to real-time updates via Supabase Realtime so data stays current when mobile and web are open simultaneously

### What Does Not Ship in Phase 3

- Voice input (text-only quick log on web)
- Photo capture (photo thumbnails from mobile entries are displayed, but new photo uploads are not supported)
- Full feature parity with the Android app (deferred to Phase 4 and beyond)

---

## 2. Project Structure

```
hearty-web/
  src/
    main.tsx
    App.tsx
    router/                   — React Router v6 route definitions
    components/
      ui/                     — shadcn/ui base components
      charts/                 — Recharts wrappers
      layout/                 — Shell, Sidebar, Header
    pages/
      Dashboard.tsx           — Home view: today's summary
      Journal.tsx             — Full log history with filters
      Trends.tsx              — Correlation charts and trigger foods
      Reports.tsx             — PDF export generation
      Profile.tsx             — Health profile management
      Settings.tsx            — Notification prefs and auth
    lib/
      api.ts                  — REST API client (axios or fetch)
      auth.ts                 — Supabase Auth helpers
      supabase.ts             — Supabase client instance
    hooks/
      useJournal.ts
      useTrends.ts
      useProfile.ts
    types/
      index.ts                — Shared TypeScript types
  index.html
  vite.config.ts
  tailwind.config.ts
```

### Key Dependency Versions

| Package | Version |
|---|---|
| React | 18.x |
| Vite | 5.x |
| TailwindCSS | 3.x |
| shadcn/ui | latest |
| Recharts | 2.x |
| TanStack Query | 5.x |
| Zustand | 4.x |
| React Router | 6.x |
| Supabase JS | 2.x |

---

## 3. Design System

### Color Palette

| Role | Value |
|---|---|
| Background (primary) | `#1a1a2e` |
| Background (surface) | `#16213e` |
| Background (elevated card) | `#0f3460` |
| Amber accent | `#f59e0b` |
| Teal accent | `#14b8a6` |
| Text (primary) | `#f5f5f0` (warm white) |
| Text (muted) | `#9ca3af` |
| Destructive | `#ef4444` |
| Border | `rgba(255,255,255,0.08)` |

The aesthetic is dark, clinical-but-warm. Deep charcoal backgrounds read as focused and serious without being sterile. Amber signals attention and warmth; teal signals data and health. No pure black; no pure white.

### Typography

- **Prose / UI labels:** Inter (sans-serif)
- **Data values / timestamps / codes:** JetBrains Mono (monospace)

Numeric values in charts, severity scores, timestamps, and food identifiers use JetBrains Mono. All other text uses Inter.

### Component Library

shadcn/ui provides the base component set: Button, Card, Dialog, Sheet, Select, Popover, Badge, Tabs, Input, Label, Checkbox, ScrollArea, Separator, Tooltip, and more. All components are configured for dark mode from the start. Tailwind CSS is the styling primitive; no additional CSS-in-JS library is used.

### Charts

Recharts is the charting library. Chart wrappers live in `src/components/charts/` and expose a consistent prop interface. Chart backgrounds match the surface color (`#16213e`). Grid lines use the border color. Axes use the muted text color.

| Chart type | Used for |
|---|---|
| Line chart | Symptom frequency over time |
| Bar chart | Food frequency, meal-type distribution |
| Scatter plot | Food-symptom correlation |
| Heat map (custom) | Trigger food heat map |

---

## 4. Pages in Detail

### 4.1 Dashboard

The Dashboard is the first screen after login. It provides a snapshot of the current day and surfaces the most actionable pattern alerts.

**Components:**

- **Today's timeline** — chronological list of meal and symptom entries logged today. Each entry shows time (JetBrains Mono), meal description, and any linked symptoms with severity badges.
- **Wellbeing score card** — today's aggregate wellbeing score, derived from symptom severity data. Displayed as a numeric score (0–10) with a color indicator (teal = good, amber = caution, red = poor).
- **Trend alert card** — AI-surfaced pattern alert, e.g., "⚠ Acid reflux 3x this week — possible trigger: tomatoes." Shown only when the API returns an active alert. Dismissable per session.
- **Quick log input** — single text field to log a meal or symptom. Text only (no voice on web). Submits to the REST API. Clears and refreshes the timeline on success.
- **Sync status indicator** — shows when data was last synced with the mobile app. Pulses amber if a Supabase Realtime connection drops.

### 4.2 Journal

The Journal page shows the full entry history with filtering and pagination.

**Layout:** Two-panel on wide viewports (filter sidebar + entry list). Single column on narrow viewports.

**Filters:**
- Date range picker (start / end)
- Food keyword search (free text)
- Symptom type (multi-select from known symptom types)
- Meal type (breakfast, lunch, dinner, snack, drink, other)

Filters are stored in Zustand UI state and reflected in URL query params via React Router so they survive page refresh.

**Entry list:** Infinite scroll (or paginated — 25 entries per page). Each entry card shows:
- Timestamp (JetBrains Mono)
- Meal description
- Parsed food tags (amber badge per food item)
- Linked symptoms with severity (teal badge for mild, amber for moderate, red for severe)
- Photo thumbnail if a photo was logged from mobile
- Expand / collapse chevron for detail view

**Expanded detail view** shows the full free-form note, raw structured JSON for the symptom record (collapsed by default behind a "Show raw data" toggle), and a link to the Trends page filtered to foods from that entry.

### 4.3 Trends

The Trends page is the analytical core of the web dashboard.

**Period selector:** 7d / 30d / 90d / custom date range. Stored in Zustand; applies to all charts on the page.

**Sections:**

1. **Trigger food ranking** — ranked list of foods by correlation confidence score. Each row shows the food name, associated symptom(s), confidence percentage, and occurrence count. A heat map variant is available as a toggle (food on one axis, symptom on the other, cell color = correlation strength).

2. **Symptom frequency over time** — line chart. One line per symptom type. X axis = date, Y axis = daily occurrence count. Hovering a data point shows the specific entries that day.

3. **Correlation matrix** — scatter plot or matrix visualization. Foods on one axis, symptoms on the other. Cell/point size and color encodes correlation confidence.

4. **Time-of-day analysis** — bar chart showing when symptoms most commonly occur (binned by hour or meal type). Helps identify whether timing (not just food) is a factor.

All trend data is fetched from the FastAPI `/trends` endpoints and cached via TanStack Query with a 5-minute stale time. No trend computation is done client-side.

### 4.4 Reports

The Reports page generates structured summaries for personal review or sharing with a physician.

**Flow:**
1. User selects a date range.
2. Preview panel renders a summary of what will be included.
3. User selects export format: PDF, CSV, or JSON.
4. Download is triggered.

**PDF report contents:**
- Summary narrative (AI-generated, returned from the API)
- Food log table (date, time, description, parsed foods, meal type)
- Symptom log table (date, time, description, severity, linked meal)
- Top trigger foods with confidence scores
- Symptom frequency chart (embedded image)

**CSV export:** Flat-table format. One row per journal entry. Includes all structured fields. Suitable for import into spreadsheet tools.

**JSON export:** Full structured export of all entries within the date range, including raw symptom JSON. Suitable for backup or programmatic analysis.

PDF generation is handled server-side by the FastAPI API. The web client sends a POST to `/reports/generate` with the date range and receives a signed URL to download the generated PDF from Supabase Storage.

### 4.5 Profile

The Profile page manages the user's health profile. Data is read from and written to the FastAPI `/profile` endpoint.

**Sections:**

- **Allergens** — the Big 9 allergens (milk, eggs, fish, shellfish, tree nuts, peanuts, wheat, soybeans, sesame) displayed as toggle chips. Custom allergens can be added via a text input. Allergens are stored in the health profile and used by the AI to flag relevant entries.

- **Known conditions** — multi-select list of common GI and dietary conditions (IBS, Crohn's, GERD, celiac, lactose intolerance, etc.) plus a custom text input for conditions not in the list.

- **Dietary protocols** — multi-select (low-FODMAP, gluten-free, dairy-free, vegan, vegetarian, low-histamine, elimination diet, etc.) plus custom input.

- **Disclaimer** — a persistent, non-dismissable notice: "Hearty is not a medical device. Information provided is for personal tracking only and does not constitute medical advice. Always consult a qualified healthcare professional."

### 4.6 Settings

**Auth section:**
- Displays the authenticated email address.
- Sign out button (clears Supabase session and redirects to login).
- Re-send magic link option.

**Notification preferences:**
- Mirrors the notification settings from the Android app (e.g., daily log reminders, weekly trend digest).
- Changes are written to the user preferences via the REST API and sync back to the mobile app.

**Data management:**
- Export all data (triggers a full JSON export with no date range filter).
- Delete account — confirmation modal with typed confirmation ("delete my account"). Calls the REST API account deletion endpoint. Irreversible.

---

## 5. Auth Flow

Authentication uses Supabase Auth with magic link (passwordless email). There are no passwords.

**Flow:**

1. User visits the app. If no active Supabase session exists, they are redirected to `/login`.
2. The login page presents a single email input field.
3. On submit, the app calls `supabase.auth.signInWithOtp({ email })`.
4. The user receives an email containing a magic link.
5. Clicking the link redirects to the app's configured redirect URL (e.g., `https://hearty.app/auth/callback`).
6. The auth callback route exchanges the token, establishes the session, and redirects to `/dashboard`.
7. The Supabase session token is stored in `localStorage` by the Supabase JS client. Subsequent API calls attach the JWT as `Authorization: Bearer <token>`.

**Route protection:** All routes except `/login` and `/auth/callback` are wrapped in a `<ProtectedRoute>` component that checks for an active session. Unauthenticated requests redirect to `/login`.

**Session refresh:** The Supabase JS client handles token refresh automatically. The app listens to `supabase.auth.onAuthStateChange` to react to session expiry or sign-out events.

---

## 6. State Management

### Server State — TanStack Query

All data fetched from the REST API is managed by TanStack Query. This covers:

- Journal entries (paginated)
- Trend data
- Health profile
- User settings
- Report generation status

Query keys are namespaced (e.g., `['journal', { page, filters }]`, `['trends', { period }]`). Mutations invalidate relevant query keys on success. Stale times are set conservatively (5 minutes for trends, 1 minute for journal) to keep data fresh without over-fetching.

### UI State — Zustand

Local UI state that does not need to be persisted to the server is managed by Zustand stores. This includes:

- Active date range / period selector for Trends
- Active filters on the Journal page
- Dashboard session-dismissed alerts
- Sidebar open/closed state on mobile-width viewports

Zustand stores are defined in `src/lib/store.ts` and imported directly into components. No context providers are needed.

---

## 7. Hosting

The web app is deployed to Vercel with automatic deploys from the `main` branch of the `hearty-web` repository.

### Environment Variables

| Variable | Purpose |
|---|---|
| `VITE_SUPABASE_URL` | Supabase project URL |
| `VITE_SUPABASE_ANON_KEY` | Supabase anonymous (public) key |
| `VITE_API_URL` | FastAPI REST API base URL |

All `VITE_` prefixed variables are injected into the client bundle at build time by Vite. No secrets are stored in client-side env vars — the Supabase anon key is designed for client use with RLS enforcing access control.

Vercel preview deployments are enabled for pull requests. The production deployment maps to the custom domain configured in the Vercel project settings.

---

## 8. Integration Points

### FastAPI REST API

The web client communicates exclusively with the FastAPI backend (built in Phase 1). All reads and writes go through the REST API — the client does not query Supabase PostgreSQL directly for application data.

The API client is defined in `src/lib/api.ts`. It attaches the Supabase JWT from the active session to every request as `Authorization: Bearer <token>`. The FastAPI server validates the JWT against Supabase and enforces per-user data isolation.

Key endpoint groups consumed by the web client:

| Endpoint group | Used by |
|---|---|
| `GET /journal` | Journal page, Dashboard |
| `POST /journal` | Dashboard quick log |
| `GET /trends` | Trends page |
| `GET /profile` | Profile page |
| `PUT /profile` | Profile page |
| `POST /reports/generate` | Reports page |
| `GET /settings` | Settings page |
| `PUT /settings` | Settings page |
| `DELETE /account` | Settings page |

### Supabase Realtime

When both the web dashboard and the Android app are open simultaneously, the web app subscribes to Supabase Realtime to receive live updates when the mobile app logs new entries.

The subscription is established in a `useRealtimeSync` hook that listens to `INSERT` events on the `journal_entries` table for the authenticated user's `user_id`. On receiving an event, the hook calls `queryClient.invalidateQueries(['journal'])` to trigger a refresh of the journal and dashboard data.

The subscription is established on mount of the authenticated app shell and torn down on unmount or sign-out.

---

*End of spec.*
