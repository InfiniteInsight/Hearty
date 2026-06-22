# Hearty Web Dashboard — Plan 1: Foundation + Live Dashboard

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Spec:** [`2026-06-21-web-dashboard-revalidated-design.md`](../specs/2026-06-21-web-dashboard-revalidated-design.md) (§2–4, §5.1, §7–10). This plan covers spec **phases 0–2**. Plans 2–4 (Journal/Trends; Conversation/Experiments/Reports/Profile/Settings + `DELETE /api/account`; integration/deploy) are written later, re-validated against the then-current code.

**Goal:** Stand up the `hearty-web/` React app so a user can sign in with Google and land on an Aurora-themed Dashboard that shows today's meals/symptoms live (Supabase Realtime + refetch fallback), the week summary, the strongest signal, and a working text quick-log.

**Architecture:** Vite + React 18 + TypeScript SPA, online-only, talking to the FastAPI REST API for data and Supabase JS for auth + realtime only. TanStack Query for server state, Zustand for UI state, Tailwind + shadcn/ui (dark) themed via Aurora CSS variables. A single typed API client injects the Supabase Bearer JWT on every request.

**Tech Stack:** React 18, Vite 5, TypeScript 5, TailwindCSS 3, shadcn/ui, TanStack Query 5, Zustand 4, React Router 6, Supabase JS 2, Vitest + React Testing Library + MSW.

**Runner:** `cd hearty-web && npm run test -- --run` (Vitest, non-watch); `npm run dev`; `npm run build` (must be type-clean); lint via `npm run lint`.

**Conventions:** TDD. Frequent commits with trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Work in a git worktree (the controller creates it via superpowers:using-git-worktrees before Task 1). `hearty-web/` is a new top-level directory in the existing repo. The dev `.env` for the web app is `hearty-web/.env` (gitignored) holding `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_API_URL`.

---

## File Structure (created across this plan)

```
hearty-web/
  index.html · vite.config.ts · tailwind.config.ts · postcss.config.js
  tsconfig.json · package.json · .env.example · .gitignore · vitest.config.ts
  src/
    main.tsx                  — React root, providers (QueryClient, Router)
    App.tsx                   — route tree + onAuthStateChange wiring
    index.css                 — Tailwind directives + @import theme tokens
    theme/tokens.css          — Aurora palette as CSS variables (:root)
    types/api.ts              — TS types mirroring backend shapes (spec §7)
    lib/
      supabase.ts             — Supabase JS client (auth + realtime only)
      api.ts                  — typed REST client; injects Bearer JWT
      auth.ts                 — signInWithGoogle, signOut, getSession
      queryClient.ts          — TanStack QueryClient (stale times, refetch-on-focus)
      store.ts                — Zustand UI store (sidebar, dismissed alerts)
      time.ts                 — startOfTodayISO() helper
    router/ProtectedRoute.tsx — session gate
    hooks/
      useRealtimeSync.ts      — Supabase Realtime on meals+symptoms → invalidate
      useMeals.ts useSymptoms.ts useSummary.ts useTrends.ts
    components/
      layout/AppShell.tsx Sidebar.tsx Header.tsx SyncIndicator.tsx
      signals/StrongestSignalHero.tsx
    pages/
      Login.tsx AuthCallback.tsx Dashboard.tsx
    test/
      setup.ts                — RTL + MSW server lifecycle
      msw/handlers.ts server.ts — mock API
      utils.tsx               — renderWithProviders()
```

---

## Phase 0 — Project Setup

### Task 1: Scaffold the Vite React-TS app

**Files:** Create `hearty-web/` (via scaffolder).

- [ ] **Step 1:** From the repo root, scaffold:

```bash
npm create vite@latest hearty-web -- --template react-ts
cd hearty-web
npm install
```

- [ ] **Step 2:** Pin/install runtime deps:

```bash
npm install react-router-dom@^6 @tanstack/react-query@^5 zustand@^4 \
  @supabase/supabase-js@^2
```

- [ ] **Step 3:** Install dev/test deps:

```bash
npm install -D vitest@^2 @testing-library/react@^16 @testing-library/jest-dom@^6 \
  @testing-library/user-event@^14 jsdom@^25 msw@^2 @types/node
```

- [ ] **Step 4:** Verify the dev server boots, then stop it:

```bash
npm run dev   # expect: "VITE vX ready", a localhost URL; Ctrl-C to stop
npm run build # expect: "built in …", zero TS errors
```

- [ ] **Step 5:** Add `.gitignore` entries (append to the generated one): `.env`, `.env.local`, `dist`, `node_modules`, `coverage`. Create `.env.example`:

```
VITE_SUPABASE_URL=
VITE_SUPABASE_ANON_KEY=
VITE_API_URL=http://localhost:8080
```

- [ ] **Step 6: Commit** — `chore(web): scaffold hearty-web Vite React-TS app`.

---

### Task 2: Tailwind + Aurora design tokens + fonts

**Files:** Create `hearty-web/tailwind.config.ts`, `postcss.config.js`, `src/theme/tokens.css`; Modify `src/index.css`, `index.html`.

- [ ] **Step 1:** Install Tailwind toolchain:

```bash
npm install -D tailwindcss@^3 postcss autoprefixer
npx tailwindcss init -p   # creates tailwind.config.js + postcss.config.js
```

Rename `tailwind.config.js` → `tailwind.config.ts` (ESM default export).

- [ ] **Step 2:** Write `src/theme/tokens.css` — the Aurora palette as CSS variables (spec §9):

```css
:root {
  /* Aurora */
  --bg-from: #0F1F2E;
  --bg-to: #112240;
  --surface: rgba(255,255,255,0.05);
  --surface-border: rgba(255,255,255,0.10);
  --accent: #34D399;        /* primary / meal */
  --accent-violet: #8B5CF6; /* mood */
  --accent-red: #F87171;    /* symptom / destructive */
  --good: #34D399;          /* beneficial / protective */
  --text: #FFFFFF;
  --text-muted: rgba(255,255,255,0.55);
  --text-faint: rgba(255,255,255,0.30);
  --glow-emerald: rgba(52,211,153,0.14);
  --glow-violet: rgba(139,92,246,0.12);
}
```

- [ ] **Step 3:** Replace `src/index.css` with Tailwind directives + token import + base background:

```css
@import "./theme/tokens.css";
@tailwind base;
@tailwind components;
@tailwind utilities;

html, body, #root { height: 100%; }
body {
  margin: 0;
  color: var(--text);
  font-family: "Plus Jakarta Sans", system-ui, sans-serif;
  background: linear-gradient(160deg, var(--bg-from) 0%, var(--bg-to) 100%);
  background-attachment: fixed;
}
.font-mono-data { font-family: "JetBrains Mono", ui-monospace, monospace; }
```

- [ ] **Step 4:** `tailwind.config.ts` — point `content` at the app and map tokens to Tailwind colors:

```ts
import type { Config } from "tailwindcss";
export default {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        surface: "var(--surface)",
        "surface-border": "var(--surface-border)",
        accent: "var(--accent)",
        "accent-violet": "var(--accent-violet)",
        "accent-red": "var(--accent-red)",
        good: "var(--good)",
        text: "var(--text)",
        "text-muted": "var(--text-muted)",
        "text-faint": "var(--text-faint)",
      },
      fontFamily: {
        sans: ["Plus Jakarta Sans", "system-ui", "sans-serif"],
        display: ["Fraunces", "Georgia", "serif"],
        mono: ["JetBrains Mono", "ui-monospace", "monospace"],
      },
    },
  },
  plugins: [],
} satisfies Config;
```

- [ ] **Step 5:** Load fonts in `index.html` `<head>` (Google Fonts) and set the page title to `Hearty`:

```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Fraunces:wght@600;700&family=Plus+Jakarta+Sans:wght@400;600;800&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
```

- [ ] **Step 6:** Verify: in `src/App.tsx` temporarily render `<h1 className="font-display text-3xl text-accent">Hearty</h1>`; `npm run dev` and confirm a dark-gradient page with an emerald serif heading. Revert the temp change.
- [ ] **Step 7: Commit** — `feat(web): tailwind + Aurora design tokens + fonts`.

---

### Task 3: shadcn/ui base components

**Files:** Created by the shadcn CLI under `src/components/ui/`; Modify `tsconfig.json`, `vite.config.ts` (path alias `@`).

- [ ] **Step 1:** Add the `@` → `src` path alias. In `tsconfig.json` `compilerOptions`: `"baseUrl": ".", "paths": { "@/*": ["./src/*"] }`. In `vite.config.ts`:

```ts
import path from "node:path";
// inside defineConfig: resolve: { alias: { "@": path.resolve(__dirname, "src") } }
```

- [ ] **Step 2:** Init shadcn (dark, choose the existing `index.css`):

```bash
npx shadcn@latest init   # style: default; base color: slate; CSS vars: yes; global: src/index.css
```

- [ ] **Step 3:** Add the base components used across the dashboard:

```bash
npx shadcn@latest add button card input badge dialog select tabs separator scroll-area skeleton sonner
```

- [ ] **Step 4:** Verify `npm run build` is type-clean.
- [ ] **Step 5: Commit** — `feat(web): shadcn/ui base components + @ alias`.

---

### Task 4: Test harness (Vitest + RTL + MSW)

**Files:** Create `vitest.config.ts`, `src/test/setup.ts`, `src/test/msw/handlers.ts`, `src/test/msw/server.ts`, `src/test/utils.tsx`, `src/test/sanity.test.ts`.

- [ ] **Step 1:** Write `vitest.config.ts`:

```ts
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import path from "node:path";
export default defineConfig({
  plugins: [react()],
  resolve: { alias: { "@": path.resolve(__dirname, "src") } },
  test: { environment: "jsdom", globals: true, setupFiles: ["./src/test/setup.ts"] },
});
```

Add `"test": "vitest"` to `package.json` scripts (keep `dev`/`build`/`preview`).

- [ ] **Step 2:** `src/test/msw/server.ts` + `handlers.ts` (empty handler list for now):

```ts
// handlers.ts
import { http } from "msw";
export const handlers: ReturnType<typeof http.get>[] = [];
// server.ts
import { setupServer } from "msw/node";
import { handlers } from "./handlers";
export const server = setupServer(...handlers);
```

- [ ] **Step 3:** `src/test/setup.ts` — jest-dom + MSW lifecycle:

```ts
import "@testing-library/jest-dom/vitest";
import { afterAll, afterEach, beforeAll } from "vitest";
import { server } from "./msw/server";
beforeAll(() => server.listen({ onUnhandledRequest: "error" }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

- [ ] **Step 4:** `src/test/sanity.test.ts` (failing first — asserts a value that doesn't exist yet, then make it pass):

```ts
import { expect, test } from "vitest";
test("test harness runs", () => { expect(1 + 1).toBe(2); });
```

- [ ] **Step 5:** Run `npm run test -- --run` → 1 passing test, MSW server boots with no unhandled-request errors.
- [ ] **Step 6:** `src/test/utils.tsx` — `renderWithProviders` (QueryClient + MemoryRouter):

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { render } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import type { ReactElement } from "react";

export function renderWithProviders(ui: ReactElement, { route = "/" } = {}) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter initialEntries={[route]}>{ui}</MemoryRouter>
    </QueryClientProvider>
  );
}
```

- [ ] **Step 7: Commit** — `test(web): vitest + RTL + MSW harness`.

---

### Task 5: API TypeScript types

**Files:** Create `src/types/api.ts`.

- [ ] **Step 1:** Define the types mirroring the backend shapes (spec §7 — verbatim field names). Include only what Plan 1 needs now; later plans extend this file.

```ts
export interface FoodItem { name: string; quantity?: string; estimated_calories?: number; preparation?: string }
export interface SymptomResponse {
  id: string; meal_id?: string; symptom_type: string; severity?: number;
  onset_minutes?: number; duration_minutes?: number; bathroom_urgency?: number;
  bathroom_visits?: number; stool_consistency?: number; notes?: string; logged_at: string;
}
export interface MealWithSymptoms {
  id: string; description: string; meal_type?: string; foods?: FoodItem[];
  location?: string; mood_before?: number; hunger_before?: number; logged_at: string;
  input_method?: string; notes?: string; created_at: string; symptoms: SymptomResponse[];
}
export interface MealsListResponse { total: number; meals: MealWithSymptoms[] }
export interface MealResponse {
  id: string; description: string; meal_type?: string; foods?: FoodItem[];
  location?: string; mood_before?: number; hunger_before?: number; logged_at: string;
  input_method?: string; notes?: string; created_at: string;
}
export interface SignalChannel {
  outcome_type: "symptom" | "wellbeing"; outcome_name: string;
  direction: "harmful" | "beneficial"; peak_window_minutes?: number;
  meal_slot?: string; wellbeing_slot?: string; relative_risk?: number;
  score_delta?: number; evidence_count: number;
}
export interface FoodSignal {
  category: string; category_label?: string; unified_score: number;
  channels: SignalChannel[]; convergent: boolean; years_seen: number[];
  recurring: boolean; is_new: boolean; strength_by_year: Record<string, number>;
}
export interface ResolvedSignal {
  category: string; category_label?: string; last_year: number;
  strength: number; status: "resolved" | "potentially_resolved";
}
export interface SignalsResponse {
  signals: FoodSignal[]; analyzed_at?: string;
  total_meals_analyzed: number; total_symptoms_analyzed: number;
  total_wellbeing_analyzed: number; resolved: ResolvedSignal[];
}
export interface SummaryResponse {
  period: string; start_date: string; end_date: string; summary_text: string;
  meals_logged: number;
  top_symptoms: { symptom_type: string; count: number; avg_severity?: number }[];
}
export interface CreateMealRequest {
  description: string;
  meal_type?: "breakfast" | "lunch" | "dinner" | "snack" | "drink" | "supplement" | "other";
  logged_at?: string;
  input_method?: "voice" | "text" | "photo" | "barcode";
  notes?: string;
}
```

- [ ] **Step 2:** `npm run build` → type-clean (the file is referenced once it's imported in Task 7; for now confirm it compiles).
- [ ] **Step 3: Commit** — `feat(web): API TypeScript types (meals, symptoms, signals, summary)`.

---

### Task 6: Supabase client + env

**Files:** Create `src/lib/supabase.ts`, `src/lib/time.ts`.

- [ ] **Step 1:** `src/lib/supabase.ts`:

```ts
import { createClient } from "@supabase/supabase-js";
const url = import.meta.env.VITE_SUPABASE_URL as string;
const anon = import.meta.env.VITE_SUPABASE_ANON_KEY as string;
if (!url || !anon) console.warn("Supabase env vars missing — auth/realtime will not work.");
export const supabase = createClient(url ?? "", anon ?? "", {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
});
```

- [ ] **Step 2:** `src/lib/time.ts`:

```ts
export function startOfTodayISO(now: Date = new Date()): string {
  const d = new Date(now); d.setHours(0, 0, 0, 0); return d.toISOString();
}
```

- [ ] **Step 3:** Test `src/lib/time.test.ts` (TDD):

```ts
import { expect, test } from "vitest";
import { startOfTodayISO } from "./time";
test("startOfTodayISO zeroes the time component", () => {
  const iso = startOfTodayISO(new Date("2026-06-21T15:30:00Z"));
  const d = new Date(iso);
  expect(d.getHours()).toBe(0); expect(d.getMinutes()).toBe(0); expect(d.getSeconds()).toBe(0);
});
```

Run `npm run test -- --run` → passes.

- [ ] **Step 4: Commit** — `feat(web): supabase client + time helper`.

---

### Task 7: Typed API client with Bearer injection

**Files:** Create `src/lib/api.ts`, `src/lib/api.test.ts`.

- [ ] **Step 1: Write the failing test** — the client attaches the Supabase access token as a Bearer header and parses JSON. Mock `getSession` and use MSW to capture the header.

```ts
import { afterEach, expect, test, vi } from "vitest";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";

vi.mock("./supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "tok-123" } } }) } },
}));

afterEach(() => vi.clearAllMocks());

test("getMeals attaches Bearer token and returns parsed body", async () => {
  let seen = "";
  server.use(
    http.get("http://api.test/api/meals", ({ request }) => {
      seen = request.headers.get("authorization") ?? "";
      const url = new URL(request.url);
      expect(url.searchParams.get("start_date")).toBe("2026-06-21T00:00:00.000Z");
      return HttpResponse.json({ total: 0, meals: [] });
    })
  );
  const { createApiClient } = await import("./api");
  const api = createApiClient("http://api.test");
  const res = await api.getMeals({ start_date: "2026-06-21T00:00:00.000Z" });
  expect(seen).toBe("Bearer tok-123");
  expect(res).toEqual({ total: 0, meals: [] });
});
```

- [ ] **Step 2:** Run it → FAIL (`./api` has no `createApiClient`).
- [ ] **Step 3: Implement `src/lib/api.ts`:**

```ts
import { supabase } from "./supabase";
import type {
  MealsListResponse, MealResponse, CreateMealRequest,
  SymptomResponse, SignalsResponse, SummaryResponse,
} from "@/types/api";

export class ApiError extends Error {
  constructor(public status: number, message: string) { super(message); }
}

async function authHeader(): Promise<Record<string, string>> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  return token ? { Authorization: `Bearer ${token}` } : {};
}

function qs(params: Record<string, string | number | undefined>): string {
  const u = new URLSearchParams();
  for (const [k, v] of Object.entries(params)) if (v !== undefined && v !== "") u.set(k, String(v));
  const s = u.toString();
  return s ? `?${s}` : "";
}

export function createApiClient(baseUrl: string) {
  async function request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const res = await fetch(`${baseUrl}${path}`, {
      ...init,
      headers: { "Content-Type": "application/json", ...(await authHeader()), ...(init.headers ?? {}) },
    });
    if (!res.ok) throw new ApiError(res.status, `${res.status} ${res.statusText}`);
    if (res.status === 204) return undefined as T;
    return (await res.json()) as T;
  }
  return {
    getMeals: (p: { start_date?: string; end_date?: string; meal_type?: string; keyword?: string; limit?: number; offset?: number } = {}) =>
      request<MealsListResponse>(`/api/meals${qs(p)}`),
    createMeal: (body: CreateMealRequest) =>
      request<MealResponse>(`/api/meals`, { method: "POST", body: JSON.stringify(body) }),
    getSymptoms: (p: { start_date?: string; end_date?: string; symptom_type?: string; min_severity?: number; limit?: number } = {}) =>
      request<SymptomResponse[]>(`/api/symptoms${qs(p)}`),
    getTrends: () => request<SignalsResponse>(`/api/trends`),
    getSummary: (p: { period?: string; start_date?: string; end_date?: string } = {}) =>
      request<SummaryResponse>(`/api/summary${qs(p)}`),
  };
}

export const api = createApiClient(import.meta.env.VITE_API_URL as string);
export type ApiClient = ReturnType<typeof createApiClient>;
```

- [ ] **Step 4:** Run `npm run test -- --run` → the api test passes; whole suite green.
- [ ] **Step 5:** Add a test that a non-OK response throws `ApiError` with the status:

```ts
test("throws ApiError on 401", async () => {
  server.use(http.get("http://api.test/api/trends", () => new HttpResponse(null, { status: 401 })));
  const { createApiClient, ApiError } = await import("./api");
  await expect(createApiClient("http://api.test").getTrends()).rejects.toBeInstanceOf(ApiError);
});
```

Run → passes.

- [ ] **Step 6: Commit** — `feat(web): typed API client with Bearer injection (TDD)`.

---

### Task 8: QueryClient + Zustand store

**Files:** Create `src/lib/queryClient.ts`, `src/lib/store.ts`.

- [ ] **Step 1:** `src/lib/queryClient.ts`:

```ts
import { QueryClient } from "@tanstack/react-query";
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: { refetchOnWindowFocus: true, staleTime: 60_000, retry: 1 },
  },
});
```

- [ ] **Step 2:** `src/lib/store.ts` (Zustand UI state used in Plan 1; extended later):

```ts
import { create } from "zustand";
interface UiState {
  sidebarOpen: boolean;
  setSidebarOpen: (open: boolean) => void;
}
export const useUiStore = create<UiState>((set) => ({
  sidebarOpen: true,
  setSidebarOpen: (open) => set({ sidebarOpen: open }),
}));
```

- [ ] **Step 3:** Test `src/lib/store.test.ts`:

```ts
import { expect, test } from "vitest";
import { useUiStore } from "./store";
test("sidebar toggles", () => {
  useUiStore.getState().setSidebarOpen(false);
  expect(useUiStore.getState().sidebarOpen).toBe(false);
});
```

Run → passes.

- [ ] **Step 4: Commit** — `feat(web): QueryClient config + Zustand UI store`.

---

## Phase 1 — Auth (Google OAuth)

### Task 9: Auth helpers

**Files:** Create `src/lib/auth.ts`, `src/lib/auth.test.ts`.

- [ ] **Step 1: Write the failing test** — `signInWithGoogle` calls Supabase OAuth with the google provider and a callback redirect:

```ts
import { expect, test, vi } from "vitest";
const signInWithOAuth = vi.fn().mockResolvedValue({ data: {}, error: null });
const signOut = vi.fn().mockResolvedValue({ error: null });
vi.mock("./supabase", () => ({ supabase: { auth: { signInWithOAuth, signOut } } }));

test("signInWithGoogle requests google provider with callback redirect", async () => {
  const { signInWithGoogle } = await import("./auth");
  await signInWithGoogle("http://localhost:5173");
  expect(signInWithOAuth).toHaveBeenCalledWith({
    provider: "google",
    options: { redirectTo: "http://localhost:5173/auth/callback" },
  });
});
```

- [ ] **Step 2:** Run → FAIL. **Implement `src/lib/auth.ts`:**

```ts
import { supabase } from "./supabase";
export async function signInWithGoogle(origin: string = window.location.origin) {
  const { error } = await supabase.auth.signInWithOAuth({
    provider: "google",
    options: { redirectTo: `${origin}/auth/callback` },
  });
  if (error) throw error;
}
export async function signOut() {
  const { error } = await supabase.auth.signOut();
  if (error) throw error;
}
export async function getSession() {
  const { data } = await supabase.auth.getSession();
  return data.session;
}
```

- [ ] **Step 3:** Run `npm run test -- --run` → passes.
- [ ] **Step 4: Commit** — `feat(web): Google OAuth auth helpers (TDD)`.

---

### Task 10: Login + AuthCallback pages

**Files:** Create `src/pages/Login.tsx`, `src/pages/AuthCallback.tsx`, `src/pages/Login.test.tsx`.

- [ ] **Step 1: Write the failing test** — Login renders a "Continue with Google" button that calls `signInWithGoogle`:

```tsx
import { expect, test, vi } from "vitest";
import userEvent from "@testing-library/user-event";
import { screen } from "@testing-library/react";
import { renderWithProviders } from "../test/utils";
const signInWithGoogle = vi.fn();
vi.mock("../lib/auth", () => ({ signInWithGoogle }));
import Login from "./Login";

test("clicking the button starts Google sign-in", async () => {
  renderWithProviders(<Login />);
  await userEvent.click(screen.getByRole("button", { name: /continue with google/i }));
  expect(signInWithGoogle).toHaveBeenCalledOnce();
});
```

- [ ] **Step 2:** Run → FAIL. **Implement `src/pages/Login.tsx`:**

```tsx
import { Button } from "@/components/ui/button";
import { signInWithGoogle } from "../lib/auth";
export default function Login() {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-6 px-6 text-center">
      <h1 className="font-display text-5xl">
        <span>Heart</span><span className="text-accent">y</span>
      </h1>
      <p className="text-text-muted">Your food &amp; symptom journal, on the big screen.</p>
      <Button onClick={() => signInWithGoogle()} className="bg-accent text-black">
        Continue with Google
      </Button>
    </div>
  );
}
```

- [ ] **Step 3:** **Implement `src/pages/AuthCallback.tsx`** — wait for Supabase to detect the session from the URL, then redirect:

```tsx
import { useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { supabase } from "../lib/supabase";
export default function AuthCallback() {
  const navigate = useNavigate();
  useEffect(() => {
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      if (session) navigate("/dashboard", { replace: true });
    });
    supabase.auth.getSession().then(({ data }) => { if (data.session) navigate("/dashboard", { replace: true }); });
    return () => sub.subscription.unsubscribe();
  }, [navigate]);
  return <div className="flex min-h-screen items-center justify-center text-text-muted">Signing you in…</div>;
}
```

- [ ] **Step 4:** Run `npm run test -- --run` → Login test passes. `npm run build` type-clean.
- [ ] **Step 5: Commit** — `feat(web): Login + AuthCallback pages`.

---

### Task 11: ProtectedRoute + router + auth lifecycle

**Files:** Create `src/router/ProtectedRoute.tsx`, `src/router/ProtectedRoute.test.tsx`; Modify `src/App.tsx`, `src/main.tsx`.

- [ ] **Step 1: Write the failing test** — ProtectedRoute shows children when a session exists, redirects to `/login` when none:

```tsx
import { expect, test, vi } from "vitest";
import { screen } from "@testing-library/react";
import { Route, Routes } from "react-router-dom";
import { renderWithProviders } from "../test/utils";

const getSession = vi.fn();
vi.mock("../lib/auth", () => ({ getSession }));
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => {} } } }) } },
}));
import ProtectedRoute from "./ProtectedRoute";

function tree() {
  return (
    <Routes>
      <Route path="/login" element={<div>login page</div>} />
      <Route element={<ProtectedRoute />}>
        <Route path="/dashboard" element={<div>secret</div>} />
      </Route>
    </Routes>
  );
}

test("redirects to /login with no session", async () => {
  getSession.mockResolvedValue(null);
  renderWithProviders(tree(), { route: "/dashboard" });
  expect(await screen.findByText("login page")).toBeInTheDocument();
});

test("renders children with a session", async () => {
  getSession.mockResolvedValue({ access_token: "t" });
  renderWithProviders(tree(), { route: "/dashboard" });
  expect(await screen.findByText("secret")).toBeInTheDocument();
});
```

- [ ] **Step 2:** Run → FAIL. **Implement `src/router/ProtectedRoute.tsx`** (resolves session once, then renders `<Outlet/>` or redirects; subscribes to changes to re-evaluate):

```tsx
import { useEffect, useState } from "react";
import { Navigate, Outlet } from "react-router-dom";
import { getSession } from "../lib/auth";
import { supabase } from "../lib/supabase";
type State = "loading" | "in" | "out";
export default function ProtectedRoute() {
  const [state, setState] = useState<State>("loading");
  useEffect(() => {
    let active = true;
    getSession().then((s) => { if (active) setState(s ? "in" : "out"); });
    const { data: sub } = supabase.auth.onAuthStateChange((_e, session) => {
      if (active) setState(session ? "in" : "out");
    });
    return () => { active = false; sub.subscription.unsubscribe(); };
  }, []);
  if (state === "loading") return <div className="flex min-h-screen items-center justify-center text-text-muted">Loading…</div>;
  if (state === "out") return <Navigate to="/login" replace />;
  return <Outlet />;
}
```

- [ ] **Step 3:** **Wire `src/App.tsx`** — route tree (Dashboard placeholder until Task 15; real shell in Task 12):

```tsx
import { Route, Routes } from "react-router-dom";
import Login from "./pages/Login";
import AuthCallback from "./pages/AuthCallback";
import ProtectedRoute from "./router/ProtectedRoute";
import Dashboard from "./pages/Dashboard";
export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />
      <Route path="/auth/callback" element={<AuthCallback />} />
      <Route element={<ProtectedRoute />}>
        <Route path="/dashboard" element={<Dashboard />} />
        <Route path="/" element={<Dashboard />} />
      </Route>
    </Routes>
  );
}
```

(`Dashboard` is created in Task 15; until then, stub `src/pages/Dashboard.tsx` to `export default function Dashboard(){return <div>Dashboard</div>;}` so the app compiles.)

- [ ] **Step 4:** **Wire `src/main.tsx`** — providers:

```tsx
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter } from "react-router-dom";
import { Toaster } from "@/components/ui/sonner";
import App from "./App";
import { queryClient } from "./lib/queryClient";
import "./index.css";
createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <BrowserRouter><App /><Toaster /></BrowserRouter>
    </QueryClientProvider>
  </StrictMode>
);
```

- [ ] **Step 5:** Run `npm run test -- --run` → both ProtectedRoute tests pass; suite green. `npm run build` type-clean.
- [ ] **Step 6: Commit** — `feat(web): ProtectedRoute + router + auth lifecycle wiring`.

---

## Phase 2 — App Shell + Dashboard + Live Sync

### Task 12: App shell (Sidebar + Header)

**Files:** Create `src/components/layout/AppShell.tsx`, `Sidebar.tsx`, `Header.tsx`, `SyncIndicator.tsx`, `src/components/layout/AppShell.test.tsx`; Modify `src/App.tsx` (wrap protected routes in `<AppShell>`).

- [ ] **Step 1: Write the failing test** — the shell renders nav links for all the planned pages and the outlet content:

```tsx
import { expect, test } from "vitest";
import { screen } from "@testing-library/react";
import { Route, Routes } from "react-router-dom";
import { renderWithProviders } from "../../test/utils";
import AppShell from "./AppShell";

test("shell shows primary nav and child route", () => {
  renderWithProviders(
    <Routes><Route element={<AppShell />}><Route path="/dashboard" element={<div>child</div>} /></Route></Routes>,
    { route: "/dashboard" }
  );
  for (const label of ["Dashboard", "Journal", "Trends", "Experiments", "Reports", "Profile", "Settings"]) {
    expect(screen.getByRole("link", { name: label })).toBeInTheDocument();
  }
  expect(screen.getByText("child")).toBeInTheDocument();
});
```

- [ ] **Step 2:** Run → FAIL. **Implement** the four files. `Sidebar.tsx` (nav list — links point at routes built in later plans; they exist as routes-to-be):

```tsx
import { NavLink } from "react-router-dom";
const items = [
  ["Dashboard", "/dashboard"], ["Journal", "/journal"], ["Trends", "/trends"],
  ["Experiments", "/experiments"], ["Reports", "/reports"], ["Profile", "/profile"], ["Settings", "/settings"],
] as const;
export default function Sidebar() {
  return (
    <nav className="flex flex-col gap-1 p-3">
      <div className="px-3 py-4 font-display text-2xl"><span>Heart</span><span className="text-accent">y</span></div>
      {items.map(([label, to]) => (
        <NavLink key={to} to={to}
          className={({ isActive }) => `rounded-lg px-3 py-2 text-sm ${isActive ? "bg-surface text-text" : "text-text-muted hover:text-text"}`}>
          {label}
        </NavLink>
      ))}
    </nav>
  );
}
```

`SyncIndicator.tsx` (presentational; status driven later by the realtime hook via store/prop — here a prop):

```tsx
export type SyncStatus = "live" | "reconnecting" | "offline";
export default function SyncIndicator({ status }: { status: SyncStatus }) {
  const color = status === "live" ? "bg-accent" : status === "reconnecting" ? "bg-yellow-400 animate-pulse" : "bg-accent-red";
  const label = status === "live" ? "Live" : status === "reconnecting" ? "Reconnecting…" : "Offline";
  return <span className="flex items-center gap-2 text-xs text-text-muted"><span className={`h-2 w-2 rounded-full ${color}`} /> {label}</span>;
}
```

`Header.tsx` (holds the sync indicator + manual refresh):

```tsx
import { useQueryClient } from "@tanstack/react-query";
import SyncIndicator, { type SyncStatus } from "./SyncIndicator";
import { Button } from "@/components/ui/button";
export default function Header({ status }: { status: SyncStatus }) {
  const qc = useQueryClient();
  return (
    <header className="flex items-center justify-between border-b border-surface-border px-6 py-3">
      <SyncIndicator status={status} />
      <Button variant="ghost" size="sm" onClick={() => qc.invalidateQueries()}>Refresh</Button>
    </header>
  );
}
```

`AppShell.tsx` (lays out sidebar + header + outlet; owns the realtime status via the Task 13 hook):

```tsx
import { Outlet } from "react-router-dom";
import Sidebar from "./Sidebar";
import Header from "./Header";
import { useRealtimeSync } from "../../hooks/useRealtimeSync";
export default function AppShell() {
  const status = useRealtimeSync();
  return (
    <div className="grid min-h-screen grid-cols-[220px_1fr]">
      <aside className="border-r border-surface-border">< Sidebar /></aside>
      <div className="flex flex-col"><Header status={status} /><main className="flex-1 p-6"><Outlet /></main></div>
    </div>
  );
}
```

> Note: `useRealtimeSync` is built in Task 13. To keep this task's test green before Task 13 exists, implement a temporary `useRealtimeSync` stub returning `"live"` in `src/hooks/useRealtimeSync.ts`, which Task 13 replaces with the real implementation (its tests will drive it).

- [ ] **Step 3:** Wrap the protected routes in `<AppShell>` in `App.tsx`:

```tsx
<Route element={<ProtectedRoute />}>
  <Route element={<AppShell />}>
    <Route path="/dashboard" element={<Dashboard />} />
    <Route path="/" element={<Dashboard />} />
  </Route>
</Route>
```

- [ ] **Step 4:** Run `npm run test -- --run` → shell test passes; suite green.
- [ ] **Step 5: Commit** — `feat(web): app shell (sidebar + header + sync indicator)`.

---

### Task 13: Realtime sync hook

**Files:** Replace `src/hooks/useRealtimeSync.ts` (the Task 12 stub); Create `src/hooks/useRealtimeSync.test.ts`.

> **PREREQUISITE — verify before trusting realtime (infra, not unit-testable).** Supabase `postgres_changes` only delivers rows the subscribing user's JWT is authorized to **SELECT under RLS**. This backend uses the service-key client (bypasses RLS), so the `authenticated` role may have **no** client SELECT policy on `meals`/`symptoms` — in which case the channel subscribes "SUBSCRIBED" but delivers **zero events** (and all of this task's mocked tests still pass). Before relying on realtime:
> 1. Check policies: in Supabase SQL, `select tablename, policyname, cmd, roles from pg_policies where tablename in ('meals','symptoms');` (or the dashboard → Auth → Policies). Confirm Realtime is enabled for both tables (`supabase_realtime` publication).
> 2. If there is **no** SELECT policy for `authenticated` scoped to `user_id = auth.uid()`, either add one (own-rows SELECT) **or** accept realtime as best-effort. Either way it is non-blocking: because we chose **"Both"**, the refetch-on-focus + polling fallback (Task 8 `refetchOnWindowFocus` + the polling interval) is the **guaranteed** freshness path. The sync indicator must therefore degrade gracefully (status `reconnecting`/`offline` is acceptable, not an error state). Record the finding in the PR + README.

- [ ] **Step 1: Write the failing test** — the hook subscribes to `meals` and `symptoms` postgres-changes for the user and invalidates queries on an event; returns a status string. Mock the supabase channel.

```ts
import { expect, test, vi } from "vitest";
import { renderHook } from "@testing-library/react";

const handlers: Array<(p: unknown) => void> = [];
const channelObj = {
  on: vi.fn(function (this: unknown, _type: string, _filter: unknown, cb: (p: unknown) => void) { handlers.push(cb); return channelObj; }),
  subscribe: vi.fn((cb?: (s: string) => void) => { cb?.("SUBSCRIBED"); return channelObj; }),
};
const removeChannel = vi.fn();
vi.mock("../lib/supabase", () => ({
  supabase: {
    channel: vi.fn(() => channelObj),
    removeChannel,
    auth: { getUser: vi.fn().mockResolvedValue({ data: { user: { id: "u1" } } }) },
  },
}));
const invalidateQueries = vi.fn();
vi.mock("@tanstack/react-query", async (orig) => ({ ...(await orig() as object), useQueryClient: () => ({ invalidateQueries }) }));

import { useRealtimeSync } from "./useRealtimeSync";

test("subscribes and invalidates on a meal event", async () => {
  const { result } = renderHook(() => useRealtimeSync());
  // allow the async getUser + subscribe to settle
  await vi.waitFor(() => expect(channelObj.subscribe).toHaveBeenCalled());
  handlers[0]?.({});
  expect(invalidateQueries).toHaveBeenCalled();
  expect(["live", "reconnecting", "offline"]).toContain(result.current);
});
```

- [ ] **Step 2:** Run → FAIL. **Implement `src/hooks/useRealtimeSync.ts`:**

```ts
import { useEffect, useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { supabase } from "../lib/supabase";
import type { SyncStatus } from "../components/layout/SyncIndicator";

export function useRealtimeSync(): SyncStatus {
  const qc = useQueryClient();
  const [status, setStatus] = useState<SyncStatus>("reconnecting");
  useEffect(() => {
    let channel: ReturnType<typeof supabase.channel> | null = null;
    let active = true;
    (async () => {
      const { data } = await supabase.auth.getUser();
      const uid = data.user?.id;
      if (!uid || !active) return;
      const invalidate = () => qc.invalidateQueries();
      channel = supabase.channel(`rt-${uid}`);
      for (const table of ["meals", "symptoms"]) {
        channel.on("postgres_changes", { event: "*", schema: "public", table, filter: `user_id=eq.${uid}` }, invalidate);
      }
      channel.subscribe((s: string) => {
        if (!active) return;
        if (s === "SUBSCRIBED") setStatus("live");
        else if (s === "CHANNEL_ERROR" || s === "TIMED_OUT" || s === "CLOSED") setStatus("reconnecting");
      });
    })();
    return () => { active = false; if (channel) supabase.removeChannel(channel); };
  }, [qc]);
  return status;
}
```

- [ ] **Step 3:** Run `npm run test -- --run` → passes; suite green. `npm run build` type-clean.
- [ ] **Step 4: Commit** — `feat(web): realtime sync hook (meals + symptoms → invalidate)`.

---

### Task 14: Data hooks (meals, symptoms, summary, trends)

**Files:** Create `src/hooks/useMeals.ts`, `useSymptoms.ts`, `useSummary.ts`, `useTrends.ts`, `src/hooks/useDashboardData.test.tsx`.

- [ ] **Step 1: Write the failing test** — `useTodayMeals` fetches meals from today via the API client (MSW), exposed through TanStack Query:

```tsx
import { expect, test, vi } from "vitest";
import { screen } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
import { renderWithProviders } from "../test/utils";
vi.mock("../lib/supabase", () => ({ supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } } }));

import { useTodayMeals } from "./useMeals";
function Probe() { const q = useTodayMeals(); return <div>{q.isSuccess ? `meals:${q.data.total}` : "loading"}</div>; }

test("useTodayMeals loads today's meals", async () => {
  server.use(http.get("*/api/meals", () => HttpResponse.json({ total: 2, meals: [] })));
  renderWithProviders(<Probe />);
  expect(await screen.findByText("meals:2")).toBeInTheDocument();
});
```

- [ ] **Step 2:** Run → FAIL. **Implement the hooks.** `useMeals.ts`:

```ts
import { useQuery } from "@tanstack/react-query";
import { api } from "../lib/api";
import { startOfTodayISO } from "../lib/time";
export function useTodayMeals() {
  const start = startOfTodayISO();
  return useQuery({ queryKey: ["meals", { start }], queryFn: () => api.getMeals({ start_date: start }) });
}
```

`useSymptoms.ts`:

```ts
import { useQuery } from "@tanstack/react-query";
import { api } from "../lib/api";
import { startOfTodayISO } from "../lib/time";
export function useTodaySymptoms() {
  const start = startOfTodayISO();
  return useQuery({ queryKey: ["symptoms", { start }], queryFn: () => api.getSymptoms({ start_date: start }) });
}
```

`useSummary.ts`:

```ts
import { useQuery } from "@tanstack/react-query";
import { api } from "../lib/api";
export function useWeekSummary() {
  return useQuery({ queryKey: ["summary", { period: "week" }], queryFn: () => api.getSummary({ period: "week" }), staleTime: 300_000 });
}
```

`useTrends.ts`:

```ts
import { useQuery } from "@tanstack/react-query";
import { api } from "../lib/api";
export function useTrends() {
  return useQuery({ queryKey: ["trends"], queryFn: () => api.getTrends(), staleTime: 300_000 });
}
```

- [ ] **Step 3:** Run `npm run test -- --run` → passes.
- [ ] **Step 4: Commit** — `feat(web): dashboard data hooks (meals/symptoms/summary/trends)`.

---

### Task 15: Dashboard page

**Files:** Replace `src/pages/Dashboard.tsx` (the Task 11 stub); Create `src/components/signals/StrongestSignalHero.tsx`, `src/pages/Dashboard.test.tsx`.

- [ ] **Step 1: Write the failing test** — the Dashboard renders today's timeline rows (meals + symptoms merged), the summary text, the strongest signal label, and a quick-log that POSTs and clears:

```tsx
import { expect, test, vi } from "vitest";
import userEvent from "@testing-library/user-event";
import { screen } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
import { renderWithProviders } from "../test/utils";
vi.mock("../lib/supabase", () => ({ supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } } }));
import Dashboard from "./Dashboard";

const meal = { id: "m1", description: "oatmeal", logged_at: "2026-06-21T08:00:00Z", created_at: "2026-06-21T08:00:00Z", foods: [{ name: "oats" }], symptoms: [] };

test("renders today data and submits quick-log", async () => {
  let posted = "";
  server.use(
    http.get("*/api/meals", () => HttpResponse.json({ total: 1, meals: [meal] })),
    http.get("*/api/symptoms", () => HttpResponse.json([])),
    http.get("*/api/summary", () => HttpResponse.json({ period: "week", start_date: "x", end_date: "y", summary_text: "Looking steady.", meals_logged: 5, top_symptoms: [] })),
    http.get("*/api/trends", () => HttpResponse.json({ signals: [{ category: "milk", category_label: "Milk & Dairy", unified_score: 0.8, channels: [{ outcome_type: "symptom", outcome_name: "bloating", direction: "harmful", evidence_count: 9 }], convergent: false, years_seen: [], recurring: false, is_new: true, strength_by_year: {} }], analyzed_at: null, total_meals_analyzed: 10, total_symptoms_analyzed: 3, total_wellbeing_analyzed: 0, resolved: [] })),
    http.post("*/api/meals", async ({ request }) => { posted = (await request.json() as { description: string }).description; return HttpResponse.json({ id: "m2", description: posted, logged_at: "z", created_at: "z" }, { status: 201 }); }),
  );
  renderWithProviders(<Dashboard />);
  expect(await screen.findByText("oatmeal")).toBeInTheDocument();
  expect(screen.getByText("Looking steady.")).toBeInTheDocument();
  expect(screen.getByText(/Milk & Dairy/)).toBeInTheDocument();
  await userEvent.type(screen.getByPlaceholderText(/log a meal/i), "banana");
  await userEvent.click(screen.getByRole("button", { name: /log/i }));
  await vi.waitFor(() => expect(posted).toBe("banana"));
});
```

- [ ] **Step 2:** Run → FAIL. **Implement `StrongestSignalHero.tsx`:**

```tsx
import type { SignalsResponse } from "@/types/api";
export default function StrongestSignalHero({ data }: { data?: SignalsResponse }) {
  const top = data?.signals?.slice().sort((a, b) => b.unified_score - a.unified_score)[0];
  if (!top) return null;
  const ch = top.channels[0];
  const label = top.category_label ?? top.category;
  return (
    <div className="rounded-2xl border border-surface-border bg-surface p-4">
      <div className="font-mono-data text-xs text-text-faint">⚡ STRONGEST SIGNAL</div>
      <div className="mt-1 text-lg">{label}{ch ? <> → <span className="text-text-muted">{ch.outcome_name}</span></> : null}</div>
    </div>
  );
}
```

**Implement `Dashboard.tsx`:**

```tsx
import { useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { api } from "../lib/api";
import { useTodayMeals } from "../hooks/useMeals";
import { useTodaySymptoms } from "../hooks/useSymptoms";
import { useWeekSummary } from "../hooks/useSummary";
import { useTrends } from "../hooks/useTrends";
import StrongestSignalHero from "../components/signals/StrongestSignalHero";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

function timeOf(iso: string) { return new Date(iso).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }); }

export default function Dashboard() {
  const qc = useQueryClient();
  const meals = useTodayMeals();
  const symptoms = useTodaySymptoms();
  const summary = useWeekSummary();
  const trends = useTrends();
  const [text, setText] = useState("");
  const [busy, setBusy] = useState(false);

  const rows = [
    ...(meals.data?.meals ?? []).map((m) => ({ kind: "meal" as const, at: m.logged_at, label: m.description })),
    ...(symptoms.data ?? []).map((s) => ({ kind: "symptom" as const, at: s.logged_at, label: s.symptom_type })),
  ].sort((a, b) => a.at.localeCompare(b.at));

  async function submit() {
    if (!text.trim()) return;
    setBusy(true);
    try { await api.createMeal({ description: text.trim(), input_method: "text" }); setText(""); qc.invalidateQueries({ queryKey: ["meals"] }); qc.invalidateQueries({ queryKey: ["summary"] }); }
    finally { setBusy(false); }
  }

  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-6">
      <h1 className="font-display text-3xl">Today</h1>
      <div className="flex gap-2">
        <Input value={text} onChange={(e) => setText(e.target.value)} placeholder="Log a meal…"
          onKeyDown={(e) => { if (e.key === "Enter") submit(); }} />
        <Button onClick={submit} disabled={busy} className="bg-accent text-black">Log</Button>
      </div>
      {summary.data && (
        <div className="rounded-2xl border border-surface-border bg-surface p-4">
          <div className="font-mono-data text-xs text-text-faint">THIS WEEK · {summary.data.meals_logged} meals</div>
          <p className="mt-1 text-text-muted">{summary.data.summary_text}</p>
        </div>
      )}
      <StrongestSignalHero data={trends.data} />
      <section>
        <h2 className="mb-2 text-sm text-text-muted">Today's timeline</h2>
        {rows.length === 0 ? <p className="text-text-faint">Nothing logged yet today.</p> : (
          <ul className="flex flex-col gap-2">
            {rows.map((r, i) => (
              <li key={i} className="flex items-center gap-3 rounded-xl border border-surface-border bg-surface px-4 py-2">
                <span className="font-mono-data text-xs text-text-faint">{timeOf(r.at)}</span>
                <span className={`h-2 w-2 rounded-full ${r.kind === "meal" ? "bg-accent" : "bg-accent-red"}`} />
                <span>{r.label}</span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
```

- [ ] **Step 3:** Run `npm run test -- --run` → Dashboard test passes; full suite green.
- [ ] **Step 4:** `npm run build` → type-clean; `npm run dev` → manual smoke (with real `.env`): login → dashboard shows today's data.
- [ ] **Step 5: Commit** — `feat(web): Dashboard (timeline + summary + strongest signal + quick-log)`.

---

### Task 16: Phase review + manual device/browser verification notes

**Files:** Create `hearty-web/README.md`.

- [ ] **Step 1:** Write `hearty-web/README.md` documenting: env vars, `npm run dev|build|test`, the Supabase redirect-URL requirement (`http://localhost:5173/auth/callback` + prod), the backend `ALLOWED_ORIGINS` requirement, and the **Realtime prerequisite** (Realtime enabled on `meals`+`symptoms` **and** an `authenticated` own-rows SELECT RLS policy on each; if absent, realtime is best-effort and the polling fallback is the guaranteed freshness path — record which is in effect).
- [ ] **Step 2:** Run the full suite + build once more:

```bash
npm run test -- --run   # all green
npm run build           # type-clean
npm run lint            # clean (or note/fix)
```

- [ ] **Step 3: Manual verification checklist** (record results in the PR description; live auth/realtime are browser-verified, not unit-testable):
  - Visit `/dashboard` unauthenticated → redirected to `/login`.
  - "Continue with Google" → Google consent → lands on `/dashboard`.
  - Dashboard shows today's meals/symptoms, week summary, strongest signal.
  - Quick-log a meal → appears in the timeline (after invalidate) without a full reload.
  - With the phone app, log a meal → web timeline updates within the polling/realtime window; sync indicator reads "Live".
  - Sign out → redirected to `/login`; `/dashboard` no longer accessible.
- [ ] **Step 4: Commit** — `docs(web): README + Plan 1 verification checklist`.

---

## Self-Review

- **Spec coverage (phases 0–2):** Setup (T1–T4) · Aurora tokens/theme §9 (T2) · typed client + Bearer §3/§7 (T5, T7) · Supabase client (T6) · QueryClient/Zustand §8 (T8) · Google OAuth §3 (T9–T11) · ProtectedRoute/lifecycle §3 (T11) · shell + sync indicator §2/§4 (T12) · Realtime + fallback §4 (T13, T8 refetch-on-focus) · Dashboard §5.1 incl. quick-log, summary, strongest signal, timeline (T14–T15). Photo thumbnails correctly absent. No calories rendered. Out-of-scope items (other pages, account-delete) belong to Plans 2–4.
- **Placeholder scan:** no "TBD"/"add error handling"/"similar to Task N"; every code step shows real code; the one forward-reference (Task 12 → Task 13 hook) is resolved by an explicit temporary stub the later task replaces, with both tasks self-contained.
- **Type consistency:** `createApiClient`/`api` methods (`getMeals`, `createMeal`, `getSymptoms`, `getTrends`, `getSummary`) are used identically in hooks (T14) and Dashboard (T15); `SyncStatus` defined in `SyncIndicator` (T12) is imported by `useRealtimeSync` (T13) and `Header` (T12); types in `types/api.ts` (T5) match the fields read in T15.
- **YAGNI:** Zustand store holds only what Plan 1 uses; types file holds only Plan-1 shapes; later plans extend both.
- **Note for executor:** the `@vitejs/plugin-react` import in `vitest.config.ts` (T4) comes with the Vite scaffold; confirm it's present (it is, via the react-ts template). If MSW v2's `http`/`HttpResponse` import path differs in the installed version, align to the installed API (`msw` exports `http`, `HttpResponse`).
```
