# Web Dashboard — Plan 2: Journal + Trends Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Journal page (filterable, paginated meal/symptom history with edit/delete) and the Trends page (signal cards, charts, analyse, per-signal verdict) to `hearty-web/`, building on the Plan 1 foundation.

**Architecture:** Continues the Plan 1 app: Vite + React + TS, TanStack Query for server state, URL query params + Zustand for UI state, typed `lib/api.ts` client over the FastAPI backend, Aurora CSS-variable theme, Vitest + RTL + MSW. Journal filters live in the **URL** (single source of truth) to avoid two-way sync loops; trends period lives in Zustand. Recharts is added for the two Trends charts.

**Tech Stack:** React 18, TypeScript (`erasableSyntaxOnly` + `verbatimModuleSyntax`), TanStack Query v5, Zustand v4, React Router v6, Tailwind v3 + shadcn/ui v2, Recharts, Vitest + RTL + MSW v2.

---

## Branch / PR basing

This plan **stacks on the Plan 1 branch**. PR #9 (`web-dashboard-foundation` → `master`) is still OPEN. Before Task 1, create a new branch off the current foundation HEAD so PR #9 can still merge independently:

```bash
git checkout -b web-dashboard-journal-trends   # from worktree HEAD (40968d2)
```

When finishing, open PR #10 with **base = `web-dashboard-foundation`**. Gotcha: if PR #9 merges to `master` first, rebase this branch onto `master` and retarget PR #10's base to `master`.

---

## Verified backend contracts (re-validated 2026-06-21 against `hearty-api/app/routers/` + `app/models/schemas.py`)

| Endpoint | Request | Response | Notes |
|---|---|---|---|
| `GET /api/meals` | `start_date,end_date,meal_type,keyword,limit(≤200),offset` | `MealsListResponse {total, meals: MealWithSymptoms[]}` | `limit` hard-capped at 200 (`Query(50, le=200)`) |
| `PATCH /api/meals/{id}` | `{description: string, foods?: string[]}` | `MealResponse` (200) | `foods` saved verbatim as `[{name}]`; meal_type unchanged when foods supplied |
| `DELETE /api/meals/{id}` | — | 204 | 404 if not owned |
| `GET /api/symptoms` | `start_date,end_date,symptom_type,min_severity,limit` | `SymptomResponse[]` | **no `le` cap** on `limit` — safe to pass 1000 |
| `PATCH /api/symptoms/{id}` | `{description: string, severity?: number, onset_minutes?: number}` | `SymptomResponse` (200) | field is `description` (→ `raw_description`) — **not** `raw_description` |
| `DELETE /api/symptoms/{id}` | — | 204 | |
| `GET /api/trends` | — | `SignalsResponse` | runs `ensure_fresh_signals` + backfill **inline** → can block; needs real loading state |
| `POST /api/trends/analyze` | — | `AnalyzeResponse {status, analyzed_at, new_signals_count}` | **SYNCHRONOUS** — runs analysis inline, returns `status:"completed"`. No polling needed (see deviation D1) |
| `GET /api/trends/analyze/status` | — | `AnalyzeStatusResponse {last_analyzed_at?, has_new_data}` | drives the pill's "new data" state + eyebrow only |
| `POST /api/trends/signal-verdict` | `{category, outcome_type:'symptom'|'wellbeing', outcome_name, verdict:'confirmed'|'disputed'|'snoozed'}` | `{ok: boolean}` | upsert keyed by (user,category,outcome_type,outcome_name) |

`meal_type` values: `breakfast, lunch, dinner, snack, drink, supplement, other`.
`symptom_type` values (15): `acid_reflux, bloating, gas, nausea, urgency, loose_stool, constipation, stomach_pain, cramping, fatigue, brain_fog, headache, skin_reaction, heart_palpitations, other`.

---

## Deviations from spec §5.2 / §5.3 (deliberate, recorded here)

- **D1 — Analyse is synchronous, not polled.** Spec §5.3 says "polling `GET /api/trends/analyze/status` until done". The backend `POST /api/trends/analyze` runs analysis inline and returns `status:"completed"`, so there is nothing to poll for completion. We `await` the mutation (spinner on the pill), then invalidate `['trends']` + `['trends','status']`. `GET /analyze/status` is used **only** for the "new data available" pill state and the `last_analyzed_at` eyebrow.
- **D2 — Journal filters live in the URL, not Zustand.** Spec §8 lists journal filters under Zustand. Putting them in both URL and Zustand requires two opposing sync effects that loop. Instead `useSearchParams` is the single source of truth (still satisfies §5.2 "mirrored to URL query params, survive refresh"). Zustand keeps only `sidebarOpen` (existing) + `trendsPeriod`.
- **D3 — Charts are bar charts of counts.** Spec §5.3 says symptom-frequency + meal-type "stacked proportion". For Plan 2 both render as Recharts vertical **bar charts of counts** (simpler, testable). Stacked-proportion styling deferred.
- **D4 — Meal-type-mix chart is capped at 200 meals** over long periods (backend `le=200`). The chart shows a visible caption noting the cap; no silent truncation.
- **D5 — Amber token added.** Spec §9 palette omits amber, but §5.2 calls for "food-name badges (amber)" and "amber moderate" severity. Add `--warn: #FBBF24` to `tokens.css` + a `warn` Tailwind color. Used for food badges and moderate-severity badges.

---

## Existing conventions to honor (carry into every subagent dispatch)

- **TS constraints:** `erasableSyntaxOnly` + `verbatimModuleSyntax` — no parameter-properties, no enums; use `import type` for type-only imports.
- **Tailwind tokens available:** `brand` (green), `surface`, `surface-border`, `accent-violet`, `accent-red`, `good` (green), `text`, `text-muted`, `text-faint`; custom `.font-mono-data` and `font-display`/`font-sans`/`font-mono`. (Task 1 adds `warn`.)
- **Test harness:** Vitest + RTL + MSW. `server.listen({ onUnhandledRequest: "error" })` — **every** fetch needs an MSW handler. Use `renderWithProviders(ui, { route })` from `src/test/utils.tsx` (wraps QueryClient + MemoryRouter). Any test that imports `lib/api` (the `api` singleton) or a component using it **must** `vi.mock("../lib/supabase", ...)` providing `auth.getSession`. `vi.mock` factories are hoisted — use `vi.hoisted()` or inline `vi.fn()` in the factory.
- **No calories ever** — `foods[].estimated_calories` is never rendered.
- **shadcn** is pinned to v2 (`npx shadcn@2 add <c> -y`). Components already present: badge, button, card, dialog, input, scroll-area, select, separator, skeleton, sonner, tabs.
- **Commits:** conventional messages, co-author trailer `Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Push/PR only with explicit user consent.

---

## File structure

**Create:**
- `src/hooks/useJournalFilters.ts` — URL ↔ filters (single source of truth)
- `src/hooks/useJournalMeals.ts` — paginated meals query
- `src/hooks/useTrendsActions.ts` — analyze status query + analyze & verdict mutations
- `src/components/journal/MealCard.tsx` — one entry (collapsed/expanded, edit/delete)
- `src/components/signals/SignalCard.tsx` — one FoodSignal card with verdict actions
- `src/components/signals/TrendsHero.tsx` — full strongest-signal hero (3-up stats)
- `src/components/charts/SymptomFrequencyChart.tsx`, `src/components/charts/MealTypeMixChart.tsx`
- `src/lib/charts.ts` — pure chart data-shaping
- `src/pages/Journal.tsx`, `src/pages/Trends.tsx`
- Test files alongside each logic unit.

**Modify:**
- `src/types/api.ts` — add request/response types (Task 1)
- `src/lib/api.ts` + `src/lib/api.test.ts` — new client methods (Task 1)
- `src/hooks/useRealtimeSync.ts` + test — scope invalidation (Task 2)
- `src/lib/store.ts` + `src/lib/store.test.ts` — trends period (Task 3)
- `src/theme/tokens.css` + `tailwind.config.ts` — `warn` token (Task 1)
- `src/App.tsx` — wire `/journal` and `/trends` routes (Tasks 8, 13)

---

## PHASE A — Shared plumbing

### Task 1: Extend types, API client, and add the `warn` token

**Files:**
- Modify: `src/types/api.ts`
- Modify: `src/lib/api.ts`
- Modify: `src/lib/api.test.ts`
- Modify: `src/theme/tokens.css`
- Modify: `tailwind.config.ts`

- [ ] **Step 1: Add the failing API client tests**

Append to `src/lib/api.test.ts`:

```ts
test("patchMeal sends PATCH with JSON body", async () => {
  let method = "";
  let body: unknown = null;
  server.use(
    http.patch("http://api.test/api/meals/m1", async ({ request }) => {
      method = request.method;
      body = await request.json();
      return HttpResponse.json({ id: "m1", description: "edited", logged_at: "z", created_at: "z" });
    })
  );
  const { createApiClient } = await import("./api");
  await createApiClient("http://api.test").patchMeal("m1", { description: "edited", foods: ["rice"] });
  expect(method).toBe("PATCH");
  expect(body).toEqual({ description: "edited", foods: ["rice"] });
});

test("deleteMeal sends DELETE and tolerates 204", async () => {
  server.use(http.delete("http://api.test/api/meals/m1", () => new HttpResponse(null, { status: 204 })));
  const { createApiClient } = await import("./api");
  await expect(createApiClient("http://api.test").deleteMeal("m1")).resolves.toBeUndefined();
});

test("patchSymptom sends description field", async () => {
  let body: unknown = null;
  server.use(
    http.patch("http://api.test/api/symptoms/s1", async ({ request }) => {
      body = await request.json();
      return HttpResponse.json({ id: "s1", symptom_type: "bloating", logged_at: "z" });
    })
  );
  const { createApiClient } = await import("./api");
  await createApiClient("http://api.test").patchSymptom("s1", { description: "less bloated", severity: 3 });
  expect(body).toEqual({ description: "less bloated", severity: 3 });
});

test("analyzeTrends posts and returns status", async () => {
  server.use(
    http.post("http://api.test/api/trends/analyze", () =>
      HttpResponse.json({ status: "completed", analyzed_at: "2026-06-21T00:00:00Z", new_signals_count: 2 })
    )
  );
  const { createApiClient } = await import("./api");
  const r = await createApiClient("http://api.test").analyzeTrends();
  expect(r.new_signals_count).toBe(2);
});

test("getAnalyzeStatus returns has_new_data", async () => {
  server.use(
    http.get("http://api.test/api/trends/analyze/status", () =>
      HttpResponse.json({ last_analyzed_at: "2026-06-20T00:00:00Z", has_new_data: true })
    )
  );
  const { createApiClient } = await import("./api");
  const r = await createApiClient("http://api.test").getAnalyzeStatus();
  expect(r.has_new_data).toBe(true);
});

test("signalVerdict posts category + verdict", async () => {
  let body: unknown = null;
  server.use(
    http.post("http://api.test/api/trends/signal-verdict", async ({ request }) => {
      body = await request.json();
      return HttpResponse.json({ ok: true });
    })
  );
  const { createApiClient } = await import("./api");
  await createApiClient("http://api.test").signalVerdict({
    category: "milk", outcome_type: "symptom", outcome_name: "bloating", verdict: "confirmed",
  });
  expect(body).toEqual({ category: "milk", outcome_type: "symptom", outcome_name: "bloating", verdict: "confirmed" });
});
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd hearty-web && npm run test -- --run src/lib/api.test.ts`
Expected: FAIL — `patchMeal`/`deleteMeal`/`patchSymptom`/`analyzeTrends`/`getAnalyzeStatus`/`signalVerdict` are not functions.

- [ ] **Step 3: Add the new types to `src/types/api.ts`**

Append:

```ts
export type VerdictType = "confirmed" | "disputed" | "snoozed";
export interface MealUpdateRequest { description: string; foods?: string[] }
export interface SymptomUpdateRequest { description: string; severity?: number; onset_minutes?: number }
export interface AnalyzeResponse { status: "started" | "completed"; analyzed_at: string; new_signals_count: number }
export interface AnalyzeStatusResponse { last_analyzed_at?: string; has_new_data: boolean }
export interface SignalVerdictRequest {
  category: string;
  outcome_type: "symptom" | "wellbeing";
  outcome_name: string;
  verdict: VerdictType;
}
export interface SignalVerdictResponse { ok: boolean }
```

- [ ] **Step 4: Add the client methods to `src/lib/api.ts`**

Extend the import block at the top:

```ts
import type {
  MealsListResponse, MealResponse, CreateMealRequest,
  SymptomResponse, SignalsResponse, SummaryResponse,
  MealUpdateRequest, SymptomUpdateRequest,
  AnalyzeResponse, AnalyzeStatusResponse,
  SignalVerdictRequest, SignalVerdictResponse,
} from "@/types/api";
```

Add these inside the object returned by `createApiClient` (after `getSummary`):

```ts
    patchMeal: (id: string, body: MealUpdateRequest) =>
      request<MealResponse>(`/api/meals/${id}`, { method: "PATCH", body: JSON.stringify(body) }),
    deleteMeal: (id: string) =>
      request<void>(`/api/meals/${id}`, { method: "DELETE" }),
    patchSymptom: (id: string, body: SymptomUpdateRequest) =>
      request<SymptomResponse>(`/api/symptoms/${id}`, { method: "PATCH", body: JSON.stringify(body) }),
    deleteSymptom: (id: string) =>
      request<void>(`/api/symptoms/${id}`, { method: "DELETE" }),
    analyzeTrends: () =>
      request<AnalyzeResponse>(`/api/trends/analyze`, { method: "POST" }),
    getAnalyzeStatus: () =>
      request<AnalyzeStatusResponse>(`/api/trends/analyze/status`),
    signalVerdict: (body: SignalVerdictRequest) =>
      request<SignalVerdictResponse>(`/api/trends/signal-verdict`, { method: "POST", body: JSON.stringify(body) }),
```

- [ ] **Step 5: Add the `warn` token**

In `src/theme/tokens.css`, add inside `:root` (after `--accent-red`):

```css
  --warn: #FBBF24;
```

In `tailwind.config.ts`, add to `theme.extend.colors` (after `'accent-red'`):

```ts
  			warn: 'var(--warn)',
```

- [ ] **Step 6: Run tests + typecheck**

Run: `cd hearty-web && npm run test -- --run src/lib/api.test.ts && npm run build`
Expected: PASS; build type-clean.

- [ ] **Step 7: Commit**

```bash
git add src/types/api.ts src/lib/api.ts src/lib/api.test.ts src/theme/tokens.css tailwind.config.ts
git commit -m "feat(web): API client methods for meal/symptom edit, trends analyze + verdict"
```

---

### Task 2: Scope realtime invalidation to specific query keys

**Files:**
- Modify: `src/hooks/useRealtimeSync.ts`
- Modify: `src/hooks/useRealtimeSync.test.ts`

This is the deferred Plan-1 follow-up: `qc.invalidateQueries()` with no args nukes everything; scope it now that more queries exist.

- [ ] **Step 1: Update the test to assert scoped keys**

In `src/hooks/useRealtimeSync.test.ts`, replace the body of the `"subscribes to meals+symptoms and invalidates on an event"` test's assertion block (the part after `h.handlers[0]?.({});`) with:

```ts
  h.handlers[0]?.({});
  expect(h.invalidateQueries).toHaveBeenCalledWith({ queryKey: ["meals"] });
  expect(h.invalidateQueries).toHaveBeenCalledWith({ queryKey: ["symptoms"] });
  expect(h.invalidateQueries).toHaveBeenCalledWith({ queryKey: ["summary"] });
  expect(h.invalidateQueries).toHaveBeenCalledWith({ queryKey: ["trends"] });
  await waitFor(() => expect(result.current).toBe("live"));
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run src/hooks/useRealtimeSync.test.ts`
Expected: FAIL — `invalidateQueries` is called with no args, not `{ queryKey: ["meals"] }`.

- [ ] **Step 3: Scope the invalidation in `useRealtimeSync.ts`**

Replace:

```ts
        const invalidate = () => qc.invalidateQueries();
```

with:

```ts
        const invalidate = () => {
          for (const key of [["meals"], ["symptoms"], ["summary"], ["trends"]]) {
            qc.invalidateQueries({ queryKey: key });
          }
        };
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd hearty-web && npm run test -- --run src/hooks/useRealtimeSync.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/hooks/useRealtimeSync.ts src/hooks/useRealtimeSync.test.ts
git commit -m "refactor(web): scope realtime invalidation to meals/symptoms/summary/trends keys"
```

---

### Task 3: Add `trendsPeriod` to the Zustand store

**Files:**
- Modify: `src/lib/store.ts`
- Modify: `src/lib/store.test.ts`

- [ ] **Step 1: Add the failing test**

In `src/lib/store.test.ts`, update `beforeEach` and append a test:

```ts
beforeEach(() => useUiStore.setState({ sidebarOpen: true, trendsPeriod: "30d" }));

test("trends period updates", () => {
  useUiStore.getState().setTrendsPeriod("90d");
  expect(useUiStore.getState().trendsPeriod).toBe("90d");
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run src/lib/store.test.ts`
Expected: FAIL — `setTrendsPeriod` is not a function.

- [ ] **Step 3: Extend the store**

Replace `src/lib/store.ts` with:

```ts
import { create } from "zustand";

export type TrendsPeriod = "7d" | "30d" | "90d";

interface UiState {
  sidebarOpen: boolean;
  setSidebarOpen: (open: boolean) => void;
  trendsPeriod: TrendsPeriod;
  setTrendsPeriod: (p: TrendsPeriod) => void;
}

export const useUiStore = create<UiState>((set) => ({
  sidebarOpen: true,
  setSidebarOpen: (open) => set({ sidebarOpen: open }),
  trendsPeriod: "30d",
  setTrendsPeriod: (p) => set({ trendsPeriod: p }),
}));
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd hearty-web && npm run test -- --run src/lib/store.test.ts`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/lib/store.ts src/lib/store.test.ts
git commit -m "feat(web): trendsPeriod UI state in Zustand store"
```

---

## PHASE B — Journal

### Task 4: `useJournalFilters` hook (URL is the single source of truth)

**Files:**
- Create: `src/hooks/useJournalFilters.ts`
- Create: `src/hooks/useJournalFilters.test.tsx`

- [ ] **Step 1: Write the failing test**

Create `src/hooks/useJournalFilters.test.tsx`:

```tsx
import { expect, test } from "vitest";
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { renderWithProviders } from "../test/utils";
import { useJournalFilters } from "./useJournalFilters";

function Probe() {
  const { filters, setFilters } = useJournalFilters();
  return (
    <div>
      <span data-testid="kw">{filters.keyword ?? "none"}</span>
      <span data-testid="page">{filters.page}</span>
      <button onClick={() => setFilters({ keyword: "rice" })}>set</button>
      <button onClick={() => setFilters({ page: 2 })}>page2</button>
      <button onClick={() => setFilters({ keyword: undefined })}>clear</button>
    </div>
  );
}

test("hydrates filters from URL query params", () => {
  renderWithProviders(<Probe />, { route: "/journal?keyword=oats&page=1" });
  expect(screen.getByTestId("kw").textContent).toBe("oats");
  expect(screen.getByTestId("page").textContent).toBe("1");
});

test("setting a filter resets page to 0", async () => {
  renderWithProviders(<Probe />, { route: "/journal?page=3" });
  await userEvent.click(screen.getByText("set"));
  expect(screen.getByTestId("kw").textContent).toBe("rice");
  expect(screen.getByTestId("page").textContent).toBe("0");
});

test("explicit page set is honored", async () => {
  renderWithProviders(<Probe />, { route: "/journal?keyword=oats" });
  await userEvent.click(screen.getByText("page2"));
  expect(screen.getByTestId("page").textContent).toBe("2");
  expect(screen.getByTestId("kw").textContent).toBe("oats");
});

test("clearing a filter removes it", async () => {
  renderWithProviders(<Probe />, { route: "/journal?keyword=oats" });
  await userEvent.click(screen.getByText("clear"));
  expect(screen.getByTestId("kw").textContent).toBe("none");
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run src/hooks/useJournalFilters.test.tsx`
Expected: FAIL — module `./useJournalFilters` not found.

- [ ] **Step 3: Implement the hook**

Create `src/hooks/useJournalFilters.ts`:

```ts
import { useCallback } from "react";
import { useSearchParams } from "react-router-dom";

export interface JournalFilters {
  start_date?: string;
  end_date?: string;
  keyword?: string;
  meal_type?: string;
  symptom_type?: string;
  page: number;
}

const FILTER_KEYS = ["start_date", "end_date", "keyword", "meal_type", "symptom_type"] as const;

export function useJournalFilters() {
  const [params, setParams] = useSearchParams();

  const filters: JournalFilters = {
    start_date: params.get("start_date") || undefined,
    end_date: params.get("end_date") || undefined,
    keyword: params.get("keyword") || undefined,
    meal_type: params.get("meal_type") || undefined,
    symptom_type: params.get("symptom_type") || undefined,
    page: Math.max(0, Number(params.get("page") ?? "0") || 0),
  };

  // Single write path. A page set is honored as-is; any other (filter) change
  // resets pagination to page 0 so the user isn't stranded on an empty page.
  const setFilters = useCallback(
    (update: Partial<JournalFilters>) => {
      setParams(
        (prev) => {
          const next = new URLSearchParams(prev);
          for (const k of FILTER_KEYS) {
            if (k in update) {
              const v = update[k];
              if (v) next.set(k, v);
              else next.delete(k);
            }
          }
          if ("page" in update && update.page !== undefined) {
            next.set("page", String(update.page));
          } else {
            next.delete("page");
          }
          return next;
        },
        { replace: true }
      );
    },
    [setParams]
  );

  return { filters, setFilters };
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd hearty-web && npm run test -- --run src/hooks/useJournalFilters.test.tsx`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add src/hooks/useJournalFilters.ts src/hooks/useJournalFilters.test.tsx
git commit -m "feat(web): useJournalFilters — URL-canonical journal filter state"
```

---

### Task 5: `useJournalMeals` paginated query

**Files:**
- Create: `src/hooks/useJournalMeals.ts`
- Create: `src/hooks/useJournalMeals.test.tsx`

- [ ] **Step 1: Write the failing test**

Create `src/hooks/useJournalMeals.test.tsx`:

```tsx
import { expect, test, vi } from "vitest";
import { screen } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
import { renderWithProviders } from "../test/utils";
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } },
}));
import { useJournalMeals } from "./useJournalMeals";

function Probe() {
  const q = useJournalMeals({ keyword: "rice", page: 1 });
  return <div>{q.isSuccess ? `total:${q.data.total}` : "loading"}</div>;
}

test("requests the right page window and forwards filters", async () => {
  let seen: Record<string, string | null> = {};
  server.use(
    http.get("*/api/meals", ({ request }) => {
      const u = new URL(request.url);
      seen = {
        limit: u.searchParams.get("limit"),
        offset: u.searchParams.get("offset"),
        keyword: u.searchParams.get("keyword"),
      };
      return HttpResponse.json({ total: 30, meals: [] });
    })
  );
  renderWithProviders(<Probe />);
  expect(await screen.findByText("total:30")).toBeInTheDocument();
  expect(seen).toEqual({ limit: "25", offset: "25", keyword: "rice" });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run src/hooks/useJournalMeals.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the hook**

Create `src/hooks/useJournalMeals.ts`:

```ts
import { useQuery } from "@tanstack/react-query";
import { api } from "../lib/api";
import type { JournalFilters } from "./useJournalFilters";

export const JOURNAL_PAGE_SIZE = 25;

export function useJournalMeals(filters: JournalFilters) {
  const { start_date, end_date, keyword, meal_type, page } = filters;
  return useQuery({
    queryKey: ["meals", { start_date, end_date, keyword, meal_type, page }],
    queryFn: () =>
      api.getMeals({
        start_date,
        end_date,
        keyword,
        meal_type,
        limit: JOURNAL_PAGE_SIZE,
        offset: page * JOURNAL_PAGE_SIZE,
      }),
  });
}
```

(Note: `symptom_type` is intentionally not sent to `/api/meals` — that endpoint has no such param. It filters the rendered linked-symptom badges client-side in the Journal page.)

- [ ] **Step 4: Run to verify it passes**

Run: `cd hearty-web && npm run test -- --run src/hooks/useJournalMeals.test.tsx`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/hooks/useJournalMeals.ts src/hooks/useJournalMeals.test.tsx
git commit -m "feat(web): useJournalMeals paginated query (25/page)"
```

---

### Task 6: `MealCard` — display, expand, raw JSON

**Files:**
- Create: `src/components/journal/MealCard.tsx`
- Create: `src/components/journal/MealCard.test.tsx`

- [ ] **Step 1: Write the failing test**

Create `src/components/journal/MealCard.test.tsx`:

```tsx
import { expect, test, vi } from "vitest";
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { render } from "@testing-library/react";
vi.mock("../../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } },
}));
import MealCard from "./MealCard";
import type { MealWithSymptoms } from "@/types/api";

const meal: MealWithSymptoms = {
  id: "m1", description: "oatmeal with milk", logged_at: "2026-06-21T08:00:00Z",
  created_at: "2026-06-21T08:00:00Z", meal_type: "breakfast", notes: "felt fine",
  foods: [{ name: "oats" }, { name: "milk" }],
  symptoms: [{ id: "s1", symptom_type: "bloating", severity: 5, logged_at: "2026-06-21T09:00:00Z" }],
};

test("renders description, food badges, and symptom badge", () => {
  render(<ul><MealCard meal={meal} /></ul>);
  expect(screen.getByText("oatmeal with milk")).toBeInTheDocument();
  expect(screen.getByText("oats")).toBeInTheDocument();
  expect(screen.getByText(/bloating 5/)).toBeInTheDocument();
});

test("expands to show notes and raw JSON toggle", async () => {
  render(<ul><MealCard meal={meal} /></ul>);
  expect(screen.queryByText("felt fine")).not.toBeInTheDocument();
  await userEvent.click(screen.getByRole("button", { name: /oatmeal with milk/i }));
  expect(screen.getByText("felt fine")).toBeInTheDocument();
  await userEvent.click(screen.getByRole("button", { name: /show raw data/i }));
  expect(screen.getByText(/"id": "m1"/)).toBeInTheDocument();
});

test("symptomTypeFilter hides non-matching symptom badges", () => {
  render(<ul><MealCard meal={meal} symptomTypeFilter="nausea" /></ul>);
  expect(screen.queryByText(/bloating/)).not.toBeInTheDocument();
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run src/components/journal/MealCard.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the component (display only — edit/delete added in Task 7)**

Create `src/components/journal/MealCard.tsx`:

```tsx
import { useState } from "react";
import type { MealWithSymptoms } from "@/types/api";

function fmt(iso: string) {
  return new Date(iso).toLocaleString([], { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
}

export function severityClass(sev?: number) {
  if (sev == null) return "bg-surface text-text-muted";
  if (sev <= 3) return "bg-brand/15 text-brand";
  if (sev <= 6) return "bg-warn/15 text-warn";
  return "bg-accent-red/15 text-accent-red";
}

export default function MealCard({
  meal,
  symptomTypeFilter,
}: {
  meal: MealWithSymptoms;
  symptomTypeFilter?: string;
}) {
  const [open, setOpen] = useState(false);
  const [showRaw, setShowRaw] = useState(false);
  const symptoms = symptomTypeFilter
    ? meal.symptoms.filter((s) => s.symptom_type === symptomTypeFilter)
    : meal.symptoms;

  return (
    <li className="rounded-xl border border-surface-border bg-surface">
      <button
        onClick={() => setOpen((v) => !v)}
        className="flex w-full items-center gap-3 px-4 py-3 text-left"
      >
        <span className="font-mono-data text-xs text-text-faint">{fmt(meal.logged_at)}</span>
        <span className="flex-1">{meal.description}</span>
        {meal.meal_type && <span className="font-mono-data text-xs text-text-faint">{meal.meal_type}</span>}
        <span className="text-text-faint">{open ? "▲" : "▼"}</span>
      </button>

      {((meal.foods?.length ?? 0) > 0 || symptoms.length > 0) && (
        <div className="flex flex-wrap gap-1 px-4 pb-3">
          {(meal.foods ?? []).map((f, i) => (
            <span key={`f${i}`} className="rounded-full bg-warn/15 px-2 py-0.5 text-xs text-warn">
              {f.name}
            </span>
          ))}
          {symptoms.map((s) => (
            <span key={s.id} className={`rounded-full px-2 py-0.5 text-xs ${severityClass(s.severity)}`}>
              {s.symptom_type}{s.severity != null ? ` ${s.severity}` : ""}
            </span>
          ))}
        </div>
      )}

      {open && (
        <div className="border-t border-surface-border px-4 py-3 text-sm">
          {meal.notes && <p className="text-text-muted">{meal.notes}</p>}
          <button
            onClick={() => setShowRaw((v) => !v)}
            className="mt-2 font-mono-data text-xs text-text-faint underline"
          >
            {showRaw ? "Hide raw data" : "Show raw data"}
          </button>
          {showRaw && (
            <pre className="mt-2 overflow-x-auto rounded-lg bg-black/30 p-2 font-mono-data text-xs text-text-muted">
              {JSON.stringify(meal, null, 2)}
            </pre>
          )}
        </div>
      )}
    </li>
  );
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd hearty-web && npm run test -- --run src/components/journal/MealCard.test.tsx`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/components/journal/MealCard.tsx src/components/journal/MealCard.test.tsx
git commit -m "feat(web): MealCard — collapsed/expanded entry with food + severity badges"
```

---

### Task 7: `MealCard` — edit + delete

**Files:**
- Modify: `src/components/journal/MealCard.tsx`
- Modify: `src/components/journal/MealCard.test.tsx`

Edit and delete live in the expanded view. Delete uses a two-step inline confirm (testable without `window.confirm`). Mutations invalidate `['meals']`, `['summary']`, `['trends']`.

- [ ] **Step 1: Add the failing tests**

The `MealCard` test currently renders the card bare. Edit/delete fire API calls, so wrap renders in a QueryClient. Add this helper + tests to `src/components/journal/MealCard.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { http, HttpResponse } from "msw";
import { server } from "../../test/msw/server";

function renderCard(ui: React.ReactElement) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(<QueryClientProvider client={qc}><ul>{ui}</ul></QueryClientProvider>);
}

test("edits description + foods via PATCH", async () => {
  let body: unknown = null;
  server.use(
    http.patch("*/api/meals/m1", async ({ request }) => {
      body = await request.json();
      return HttpResponse.json({ id: "m1", description: "edited", logged_at: "z", created_at: "z" });
    })
  );
  renderCard(<MealCard meal={meal} />);
  await userEvent.click(screen.getByRole("button", { name: /oatmeal with milk/i }));
  await userEvent.click(screen.getByRole("button", { name: /^edit$/i }));
  const desc = screen.getByLabelText(/description/i);
  await userEvent.clear(desc);
  await userEvent.type(desc, "edited");
  await userEvent.click(screen.getByRole("button", { name: /^save$/i }));
  await vi.waitFor(() => expect((body as { description: string }).description).toBe("edited"));
});

test("delete requires a confirm then issues DELETE", async () => {
  let deleted = false;
  server.use(http.delete("*/api/meals/m1", () => { deleted = true; return new HttpResponse(null, { status: 204 }); }));
  renderCard(<MealCard meal={meal} />);
  await userEvent.click(screen.getByRole("button", { name: /oatmeal with milk/i }));
  await userEvent.click(screen.getByRole("button", { name: /^delete$/i }));
  expect(deleted).toBe(false); // first click only arms the confirm
  await userEvent.click(screen.getByRole("button", { name: /confirm delete/i }));
  await vi.waitFor(() => expect(deleted).toBe(true));
});
```

Note: the existing display-only tests `render(<ul>...</ul>)` without a QueryClient still pass because edit/delete handlers aren't invoked there.

- [ ] **Step 2: Run to verify the new tests fail**

Run: `cd hearty-web && npm run test -- --run src/components/journal/MealCard.test.tsx`
Expected: FAIL — no Edit/Delete buttons.

- [ ] **Step 3: Add edit/delete to `MealCard.tsx`**

Add imports at the top:

```tsx
import { useQueryClient } from "@tanstack/react-query";
import { api } from "../../lib/api";
```

Inside the component (after the `showRaw` state), add:

```tsx
  const qc = useQueryClient();
  const [editing, setEditing] = useState(false);
  const [desc, setDesc] = useState(meal.description);
  const [foods, setFoods] = useState((meal.foods ?? []).map((f) => f.name).join(", "));
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);

  function invalidate() {
    for (const k of [["meals"], ["summary"], ["trends"]]) qc.invalidateQueries({ queryKey: k });
  }
  async function save() {
    if (busy) return;
    setBusy(true);
    setErr(null);
    try {
      await api.patchMeal(meal.id, {
        description: desc.trim(),
        foods: foods.split(",").map((s) => s.trim()).filter(Boolean),
      });
      invalidate();
      setEditing(false);
    } catch {
      setErr("Couldn't save changes.");
    } finally {
      setBusy(false);
    }
  }
  async function remove() {
    if (busy) return;
    setBusy(true);
    setErr(null);
    try {
      await api.deleteMeal(meal.id);
      invalidate();
    } catch {
      setErr("Couldn't delete.");
      setBusy(false);
    }
  }
```

Then, inside the `{open && (...)}` block, **after** the raw-data section, add the edit/delete UI:

```tsx
          {err && <p className="mt-2 text-xs text-accent-red">{err}</p>}
          {!editing ? (
            <div className="mt-3 flex gap-2">
              <button onClick={() => setEditing(true)} className="rounded-lg border border-surface-border px-2 py-1 text-xs">Edit</button>
              {!confirmDelete ? (
                <button onClick={() => setConfirmDelete(true)} className="rounded-lg border border-surface-border px-2 py-1 text-xs text-accent-red">Delete</button>
              ) : (
                <>
                  <button onClick={remove} disabled={busy} className="rounded-lg bg-accent-red px-2 py-1 text-xs text-black">Confirm delete</button>
                  <button onClick={() => setConfirmDelete(false)} className="rounded-lg border border-surface-border px-2 py-1 text-xs">Cancel</button>
                </>
              )}
            </div>
          ) : (
            <div className="mt-3 flex flex-col gap-2">
              <label className="flex flex-col gap-1 text-xs text-text-muted">
                Description
                <input value={desc} onChange={(e) => setDesc(e.target.value)} className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
              </label>
              <label className="flex flex-col gap-1 text-xs text-text-muted">
                Foods (comma-separated)
                <input value={foods} onChange={(e) => setFoods(e.target.value)} className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
              </label>
              <div className="flex gap-2">
                <button onClick={save} disabled={busy} className="rounded-lg bg-brand px-2 py-1 text-xs text-black">Save</button>
                <button onClick={() => { setEditing(false); setDesc(meal.description); }} className="rounded-lg border border-surface-border px-2 py-1 text-xs">Cancel</button>
              </div>
            </div>
          )}
```

- [ ] **Step 4: Run to verify all MealCard tests pass**

Run: `cd hearty-web && npm run test -- --run src/components/journal/MealCard.test.tsx`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add src/components/journal/MealCard.tsx src/components/journal/MealCard.test.tsx
git commit -m "feat(web): MealCard inline edit (PATCH) + two-step delete (DELETE)"
```

---

### Task 8: `Journal` page + route

**Files:**
- Create: `src/pages/Journal.tsx`
- Create: `src/pages/Journal.test.tsx`
- Modify: `src/App.tsx`

- [ ] **Step 1: Write the failing test**

Create `src/pages/Journal.test.tsx`:

```tsx
import { expect, test, vi } from "vitest";
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
import { renderWithProviders } from "../test/utils";
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } },
}));
import Journal from "./Journal";

const meal = {
  id: "m1", description: "rice bowl", logged_at: "2026-06-21T12:00:00Z", created_at: "2026-06-21T12:00:00Z",
  meal_type: "lunch", foods: [{ name: "rice" }], symptoms: [],
};

test("lists meals and forwards keyword filter to the API", async () => {
  let lastKeyword: string | null = null;
  server.use(
    http.get("*/api/meals", ({ request }) => {
      lastKeyword = new URL(request.url).searchParams.get("keyword");
      return HttpResponse.json({ total: 1, meals: [meal] });
    })
  );
  renderWithProviders(<Journal />, { route: "/journal" });
  expect(await screen.findByText("rice bowl")).toBeInTheDocument();
  await userEvent.type(screen.getByPlaceholderText(/search/i), "rice{enter}");
  await vi.waitFor(() => expect(lastKeyword).toBe("rice"));
});

test("shows empty state when no meals", async () => {
  server.use(http.get("*/api/meals", () => HttpResponse.json({ total: 0, meals: [] })));
  renderWithProviders(<Journal />, { route: "/journal" });
  expect(await screen.findByText(/no entries/i)).toBeInTheDocument();
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run src/pages/Journal.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the page**

Create `src/pages/Journal.tsx`:

```tsx
import { useJournalFilters } from "../hooks/useJournalFilters";
import { useJournalMeals, JOURNAL_PAGE_SIZE } from "../hooks/useJournalMeals";
import MealCard from "../components/journal/MealCard";

const MEAL_TYPES = ["breakfast", "lunch", "dinner", "snack", "drink", "supplement", "other"];
const SYMPTOM_TYPES = [
  "acid_reflux", "bloating", "gas", "nausea", "urgency", "loose_stool", "constipation",
  "stomach_pain", "cramping", "fatigue", "brain_fog", "headache", "skin_reaction",
  "heart_palpitations", "other",
];

export default function Journal() {
  const { filters, setFilters } = useJournalFilters();
  const meals = useJournalMeals(filters);
  const total = meals.data?.total ?? 0;
  const lastPage = Math.max(0, Math.ceil(total / JOURNAL_PAGE_SIZE) - 1);

  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-6 md:flex-row">
      {/* Filter panel */}
      <aside className="flex shrink-0 flex-col gap-3 md:w-60">
        <h1 className="font-display text-3xl">Journal</h1>
        <input
          defaultValue={filters.keyword ?? ""}
          placeholder="Search descriptions…"
          onKeyDown={(e) => { if (e.key === "Enter") setFilters({ keyword: (e.target as HTMLInputElement).value }); }}
          className="rounded-lg border border-surface-border bg-transparent px-3 py-2 text-sm"
        />
        <label className="flex flex-col gap-1 text-xs text-text-muted">
          From
          <input type="date" value={filters.start_date ?? ""} onChange={(e) => setFilters({ start_date: e.target.value || undefined })} className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
        </label>
        <label className="flex flex-col gap-1 text-xs text-text-muted">
          To
          <input type="date" value={filters.end_date ?? ""} onChange={(e) => setFilters({ end_date: e.target.value || undefined })} className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
        </label>
        <label className="flex flex-col gap-1 text-xs text-text-muted">
          Meal type
          <select value={filters.meal_type ?? ""} onChange={(e) => setFilters({ meal_type: e.target.value || undefined })} className="rounded-lg border border-surface-border bg-surface px-2 py-1 text-sm">
            <option value="">All</option>
            {MEAL_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-xs text-text-muted">
          Symptom type
          <select value={filters.symptom_type ?? ""} onChange={(e) => setFilters({ symptom_type: e.target.value || undefined })} className="rounded-lg border border-surface-border bg-surface px-2 py-1 text-sm">
            <option value="">All</option>
            {SYMPTOM_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
          </select>
        </label>
      </aside>

      {/* Entry list */}
      <section className="flex-1">
        {meals.isPending && <p className="text-text-faint">Loading…</p>}
        {meals.isError && <p className="text-sm text-accent-red">Couldn't load entries.</p>}
        {meals.isSuccess && total === 0 && <p className="text-text-faint">No entries match these filters.</p>}
        {meals.isSuccess && total > 0 && (
          <>
            <ul className="flex flex-col gap-2">
              {meals.data.meals.map((m) => (
                <MealCard key={m.id} meal={m} symptomTypeFilter={filters.symptom_type} />
              ))}
            </ul>
            <div className="mt-4 flex items-center justify-between font-mono-data text-xs text-text-faint">
              <button disabled={filters.page <= 0} onClick={() => setFilters({ page: filters.page - 1 })} className="rounded-lg border border-surface-border px-3 py-1 disabled:opacity-40">Prev</button>
              <span>Page {filters.page + 1} of {lastPage + 1} · {total} entries</span>
              <button disabled={filters.page >= lastPage} onClick={() => setFilters({ page: filters.page + 1 })} className="rounded-lg border border-surface-border px-3 py-1 disabled:opacity-40">Next</button>
            </div>
          </>
        )}
      </section>
    </div>
  );
}
```

- [ ] **Step 4: Wire the route in `src/App.tsx`**

Add the import:

```tsx
import Journal from "./pages/Journal";
```

Replace:

```tsx
        <Route path="/journal" element={<ComingSoon />} />
```

with:

```tsx
        <Route path="/journal" element={<Journal />} />
```

- [ ] **Step 5: Run tests + build**

Run: `cd hearty-web && npm run test -- --run src/pages/Journal.test.tsx && npm run build`
Expected: PASS; build type-clean.

- [ ] **Step 6: Commit**

```bash
git add src/pages/Journal.tsx src/pages/Journal.test.tsx src/App.tsx
git commit -m "feat(web): Journal page — filters, pagination, entry cards; wire /journal route"
```

---

## PHASE C — Trends

### Task 9: Trends action hooks (status query, analyze + verdict mutations)

**Files:**
- Create: `src/hooks/useTrendsActions.ts`
- Create: `src/hooks/useTrendsActions.test.tsx`

- [ ] **Step 1: Write the failing test**

Create `src/hooks/useTrendsActions.test.tsx`:

```tsx
import { expect, test, vi } from "vitest";
import { renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } },
}));
import { useAnalyzeStatus, useAnalyze, useSignalVerdict } from "./useTrendsActions";

function wrap() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={qc}>{children}</QueryClientProvider>
  );
}

test("useAnalyzeStatus loads has_new_data", async () => {
  server.use(http.get("*/api/trends/analyze/status", () => HttpResponse.json({ last_analyzed_at: "x", has_new_data: true })));
  const { result } = renderHook(() => useAnalyzeStatus(), { wrapper: wrap() });
  await waitFor(() => expect(result.current.data?.has_new_data).toBe(true));
});

test("useAnalyze posts and resolves", async () => {
  server.use(http.post("*/api/trends/analyze", () => HttpResponse.json({ status: "completed", analyzed_at: "x", new_signals_count: 1 })));
  const { result } = renderHook(() => useAnalyze(), { wrapper: wrap() });
  await result.current.mutateAsync();
  await waitFor(() => expect(result.current.isSuccess).toBe(true));
});

test("useSignalVerdict posts the verdict", async () => {
  let body: unknown = null;
  server.use(http.post("*/api/trends/signal-verdict", async ({ request }) => { body = await request.json(); return HttpResponse.json({ ok: true }); }));
  const { result } = renderHook(() => useSignalVerdict(), { wrapper: wrap() });
  await result.current.mutateAsync({ category: "milk", outcome_type: "symptom", outcome_name: "bloating", verdict: "snoozed" });
  expect((body as { verdict: string }).verdict).toBe("snoozed");
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run src/hooks/useTrendsActions.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the hooks**

Create `src/hooks/useTrendsActions.ts`:

```ts
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "../lib/api";
import type { SignalVerdictRequest } from "@/types/api";

export function useAnalyzeStatus() {
  return useQuery({
    queryKey: ["trends", "status"],
    queryFn: () => api.getAnalyzeStatus(),
    staleTime: 60_000,
  });
}

export function useAnalyze() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: () => api.analyzeTrends(),
    // POST /analyze is synchronous (returns status:"completed"); just refresh.
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["trends"] });
    },
  });
}

export function useSignalVerdict() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: SignalVerdictRequest) => api.signalVerdict(body),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ["trends"] });
    },
  });
}
```

Note: `["trends"]` invalidation also matches `["trends","status"]` (prefix match), so the eyebrow refreshes after analyze.

- [ ] **Step 4: Run to verify it passes**

Run: `cd hearty-web && npm run test -- --run src/hooks/useTrendsActions.test.tsx`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add src/hooks/useTrendsActions.ts src/hooks/useTrendsActions.test.tsx
git commit -m "feat(web): trends action hooks — analyze status query, analyze + verdict mutations"
```

---

### Task 10: `SignalCard` component

**Files:**
- Create: `src/components/signals/SignalCard.tsx`
- Create: `src/components/signals/SignalCard.test.tsx`

- [ ] **Step 1: Write the failing test**

Create `src/components/signals/SignalCard.test.tsx`:

```tsx
import { expect, test, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import SignalCard from "./SignalCard";
import type { FoodSignal } from "@/types/api";

const signal: FoodSignal = {
  category: "milk", category_label: "Milk & Dairy", unified_score: 0.8, convergent: true,
  years_seen: [2026], recurring: false, is_new: true, strength_by_year: {},
  channels: [{ outcome_type: "symptom", outcome_name: "bloating", direction: "harmful", peak_window_minutes: 90, relative_risk: 2.4, evidence_count: 12 }],
};

test("renders label, dominant channel, relative risk, and CONVERGENT badge", () => {
  render(<SignalCard signal={signal} />);
  expect(screen.getByText("Milk & Dairy")).toBeInTheDocument();
  expect(screen.getByText(/bloating/)).toBeInTheDocument();
  expect(screen.getByText(/2\.4×/)).toBeInTheDocument();
  expect(screen.getByText("CONVERGENT")).toBeInTheDocument();
  expect(screen.getByText("NEW")).toBeInTheDocument();
});

test("fires onVerdict when an action is clicked", async () => {
  const onVerdict = vi.fn();
  render(<SignalCard signal={signal} onVerdict={onVerdict} />);
  await userEvent.click(screen.getByRole("button", { name: /confirm/i }));
  expect(onVerdict).toHaveBeenCalledWith("confirmed");
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run src/components/signals/SignalCard.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the component**

Create `src/components/signals/SignalCard.tsx`:

```tsx
import type { FoodSignal, VerdictType } from "@/types/api";

function dominantChannel(s: FoodSignal) {
  return s.channels.slice().sort((a, b) => (b.relative_risk ?? 0) - (a.relative_risk ?? 0))[0];
}

export default function SignalCard({
  signal,
  onVerdict,
}: {
  signal: FoodSignal;
  onVerdict?: (v: VerdictType) => void;
}) {
  const ch = dominantChannel(signal);
  const label = signal.category_label ?? signal.category;
  const harmful = ch?.direction === "harmful";
  const rrColor = harmful ? "text-accent-red" : "text-good";
  const barColor = harmful ? "bg-accent-red" : "bg-good";
  const pct = Math.round(Math.min(1, Math.max(0, signal.unified_score)) * 100);

  return (
    <div className="rounded-2xl border border-surface-border bg-surface p-4">
      <div className="flex items-start justify-between gap-3">
        <div>
          <div className="text-lg">{label}</div>
          {ch && (
            <div className="text-sm text-text-muted">
              → {ch.outcome_name}
              {ch.peak_window_minutes ? ` · peaks ~${ch.peak_window_minutes}min` : ""}
            </div>
          )}
        </div>
        {ch?.relative_risk != null && (
          <div className={`font-mono-data text-lg ${rrColor}`}>{ch.relative_risk.toFixed(1)}×</div>
        )}
      </div>

      <div className="mt-3 h-2 w-full rounded-full bg-white/5">
        <div className={`h-2 rounded-full ${barColor}`} style={{ width: `${pct}%` }} />
      </div>

      <div className="mt-2 flex flex-wrap items-center gap-2 font-mono-data text-xs text-text-faint">
        {ch && <span>based on {ch.evidence_count} logs</span>}
        {signal.convergent && <span className="rounded bg-accent-violet/20 px-1.5 py-0.5 text-accent-violet">CONVERGENT</span>}
        {signal.is_new && <span className="rounded bg-brand/20 px-1.5 py-0.5 text-brand">NEW</span>}
        {signal.recurring && <span className="rounded bg-white/10 px-1.5 py-0.5">RECURRING</span>}
      </div>

      {onVerdict && (
        <div className="mt-3 flex gap-2">
          <button onClick={() => onVerdict("confirmed")} className="rounded-lg border border-surface-border px-2 py-1 text-xs">Confirm</button>
          <button onClick={() => onVerdict("disputed")} className="rounded-lg border border-surface-border px-2 py-1 text-xs">Dispute</button>
          <button onClick={() => onVerdict("snoozed")} className="rounded-lg border border-surface-border px-2 py-1 text-xs">Snooze</button>
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd hearty-web && npm run test -- --run src/components/signals/SignalCard.test.tsx`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/components/signals/SignalCard.tsx src/components/signals/SignalCard.test.tsx
git commit -m "feat(web): SignalCard — strength bar, relative risk by direction, verdict actions"
```

---

### Task 11: `TrendsHero` (full hero with 3-up stat row)

**Files:**
- Create: `src/components/signals/TrendsHero.tsx`
- Create: `src/components/signals/TrendsHero.test.tsx`

- [ ] **Step 1: Write the failing test**

Create `src/components/signals/TrendsHero.test.tsx`:

```tsx
import { expect, test } from "vitest";
import { render, screen } from "@testing-library/react";
import TrendsHero from "./TrendsHero";
import type { SignalsResponse } from "@/types/api";

const data: SignalsResponse = {
  analyzed_at: "2026-06-21T00:00:00Z", total_meals_analyzed: 50, total_symptoms_analyzed: 10,
  total_wellbeing_analyzed: 5, resolved: [],
  signals: [
    { category: "milk", category_label: "Milk & Dairy", unified_score: 0.9, convergent: false, years_seen: [], recurring: false, is_new: false, strength_by_year: {}, channels: [{ outcome_type: "symptom", outcome_name: "bloating", direction: "harmful", peak_window_minutes: 60, relative_risk: 3.1, evidence_count: 20 }] },
    { category: "coffee", category_label: "Coffee", unified_score: 0.4, convergent: false, years_seen: [], recurring: false, is_new: false, strength_by_year: {}, channels: [] },
  ],
};

test("renders the highest-score signal with a 3-up stat row", () => {
  render(<TrendsHero data={data} />);
  expect(screen.getByText("Milk & Dairy")).toBeInTheDocument();
  expect(screen.getByText(/3\.1×/)).toBeInTheDocument();
  expect(screen.getByText(/60\s*min/)).toBeInTheDocument();
  expect(screen.getByText(/20/)).toBeInTheDocument();
});

test("renders nothing when there are no signals", () => {
  const { container } = render(<TrendsHero data={{ ...data, signals: [] }} />);
  expect(container).toBeEmptyDOMElement();
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run src/components/signals/TrendsHero.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the component**

Create `src/components/signals/TrendsHero.tsx`:

```tsx
import type { SignalsResponse } from "@/types/api";

export default function TrendsHero({ data }: { data?: SignalsResponse }) {
  const top = data?.signals?.slice().sort((a, b) => b.unified_score - a.unified_score)[0];
  if (!top) return null;
  const ch = top.channels[0];
  const label = top.category_label ?? top.category;

  return (
    <div className="rounded-2xl border border-surface-border bg-surface p-6"
      style={{ boxShadow: "0 0 40px var(--glow-emerald)" }}>
      <div className="font-mono-data text-xs text-text-faint">⚡ STRONGEST SIGNAL</div>
      <div className="mt-1 font-display text-2xl">{label}</div>
      {ch && <div className="text-text-muted">→ {ch.outcome_name}</div>}
      {ch && (
        <div className="mt-4 grid grid-cols-3 gap-3 font-mono-data text-sm">
          <div>
            <div className="text-text-faint text-xs">RELATIVE RISK</div>
            <div className="text-accent-red">{ch.relative_risk != null ? `${ch.relative_risk.toFixed(1)}×` : "—"}</div>
          </div>
          <div>
            <div className="text-text-faint text-xs">PEAK WINDOW</div>
            <div>{ch.peak_window_minutes != null ? `${ch.peak_window_minutes} min` : "—"}</div>
          </div>
          <div>
            <div className="text-text-faint text-xs">EVIDENCE</div>
            <div>{ch.evidence_count} logs</div>
          </div>
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd hearty-web && npm run test -- --run src/components/signals/TrendsHero.test.tsx`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add src/components/signals/TrendsHero.tsx src/components/signals/TrendsHero.test.tsx
git commit -m "feat(web): TrendsHero — strongest-signal hero with 3-up stat row"
```

---

### Task 12: Chart data-shaping + chart components (Recharts)

**Files:**
- Create: `src/lib/charts.ts`
- Create: `src/lib/charts.test.ts`
- Create: `src/components/charts/SymptomFrequencyChart.tsx`
- Create: `src/components/charts/MealTypeMixChart.tsx`
- Modify: `package.json` (add recharts)

Per the advisor: Recharts' `ResponsiveContainer` measures DOM dimensions that are 0 in jsdom, so charts render empty and RTL finds nothing. **Test the pure transforms only**; do not assert on chart SVG. The chart components are thin wrappers given an explicit height.

- [ ] **Step 1: Install Recharts**

Run: `cd hearty-web && npm install recharts`
Expected: adds `recharts` to dependencies.

- [ ] **Step 2: Write the failing transform tests**

Create `src/lib/charts.test.ts`:

```ts
import { expect, test } from "vitest";
import { symptomFrequency, mealTypeMix } from "./charts";
import type { SymptomResponse, MealWithSymptoms } from "@/types/api";

const sym = (symptom_type: string): SymptomResponse => ({ id: Math.random().toString(), symptom_type, logged_at: "x" });
const meal = (meal_type?: string): MealWithSymptoms => ({ id: Math.random().toString(), description: "x", logged_at: "x", created_at: "x", meal_type, symptoms: [] });

test("symptomFrequency counts per type, sorted desc", () => {
  const out = symptomFrequency([sym("bloating"), sym("bloating"), sym("nausea")]);
  expect(out).toEqual([{ type: "bloating", count: 2 }, { type: "nausea", count: 1 }]);
});

test("mealTypeMix counts per meal type in canonical order, drops zero buckets", () => {
  const out = mealTypeMix([meal("lunch"), meal("lunch"), meal("breakfast")]);
  expect(out).toEqual([{ type: "breakfast", count: 1 }, { type: "lunch", count: 2 }]);
});

test("mealTypeMix buckets missing meal_type as other", () => {
  const out = mealTypeMix([meal(undefined)]);
  expect(out).toEqual([{ type: "other", count: 1 }]);
});
```

- [ ] **Step 3: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run src/lib/charts.test.ts`
Expected: FAIL — module not found.

- [ ] **Step 4: Implement the transforms**

Create `src/lib/charts.ts`:

```ts
import type { SymptomResponse, MealWithSymptoms } from "@/types/api";

export const MEAL_TYPES = ["breakfast", "lunch", "dinner", "snack", "drink", "supplement", "other"] as const;

export interface ChartDatum { type: string; count: number }

export function symptomFrequency(symptoms: SymptomResponse[]): ChartDatum[] {
  const counts = new Map<string, number>();
  for (const s of symptoms) counts.set(s.symptom_type, (counts.get(s.symptom_type) ?? 0) + 1);
  return [...counts.entries()]
    .map(([type, count]) => ({ type, count }))
    .sort((a, b) => b.count - a.count);
}

export function mealTypeMix(meals: MealWithSymptoms[]): ChartDatum[] {
  const counts = new Map<string, number>();
  for (const m of meals) {
    const t = m.meal_type ?? "other";
    counts.set(t, (counts.get(t) ?? 0) + 1);
  }
  return MEAL_TYPES
    .map((type) => ({ type, count: counts.get(type) ?? 0 }))
    .filter((d) => d.count > 0);
}
```

- [ ] **Step 5: Run to verify transforms pass**

Run: `cd hearty-web && npm run test -- --run src/lib/charts.test.ts`
Expected: PASS (3 tests).

- [ ] **Step 6: Implement the chart components (not unit-tested for SVG)**

Create `src/components/charts/SymptomFrequencyChart.tsx`:

```tsx
import { Bar, BarChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import type { ChartDatum } from "../../lib/charts";

export default function SymptomFrequencyChart({ data }: { data: ChartDatum[] }) {
  if (data.length === 0) return <p className="text-text-faint text-sm">No symptoms in this period.</p>;
  return (
    <div className="h-56 w-full">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={data}>
          <XAxis dataKey="type" tick={{ fill: "var(--text-faint)", fontSize: 11 }} interval={0} angle={-30} textAnchor="end" height={60} />
          <YAxis allowDecimals={false} tick={{ fill: "var(--text-faint)", fontSize: 11 }} />
          <Tooltip contentStyle={{ background: "#112240", border: "1px solid var(--surface-border)", borderRadius: 8 }} />
          <Bar dataKey="count" fill="var(--accent-red)" radius={[4, 4, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
```

Create `src/components/charts/MealTypeMixChart.tsx`:

```tsx
import { Bar, BarChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from "recharts";
import type { ChartDatum } from "../../lib/charts";

export default function MealTypeMixChart({ data }: { data: ChartDatum[] }) {
  if (data.length === 0) return <p className="text-text-faint text-sm">No meals in this period.</p>;
  return (
    <div className="h-56 w-full">
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={data}>
          <XAxis dataKey="type" tick={{ fill: "var(--text-faint)", fontSize: 11 }} interval={0} angle={-30} textAnchor="end" height={60} />
          <YAxis allowDecimals={false} tick={{ fill: "var(--text-faint)", fontSize: 11 }} />
          <Tooltip contentStyle={{ background: "#112240", border: "1px solid var(--surface-border)", borderRadius: 8 }} />
          <Bar dataKey="count" fill="var(--brand)" radius={[4, 4, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
```

- [ ] **Step 7: Build to confirm Recharts types resolve**

Run: `cd hearty-web && npm run build`
Expected: type-clean.

- [ ] **Step 8: Commit**

```bash
git add src/lib/charts.ts src/lib/charts.test.ts src/components/charts/ package.json package-lock.json
git commit -m "feat(web): chart transforms + Recharts symptom-frequency & meal-type-mix charts"
```

---

### Task 13: `Trends` page + route

**Files:**
- Create: `src/pages/Trends.tsx`
- Create: `src/pages/Trends.test.tsx`
- Modify: `src/App.tsx`

Composes: header (title + eyebrow with `analyzed_at`/counts + **Analyse** pill), period selector (7d/30d/90d via Zustand), `TrendsHero`, signal list (`SignalCard` wired to `useSignalVerdict`), and the two period-scoped charts.

- [ ] **Step 1: Write the failing test**

Create `src/pages/Trends.test.tsx`:

```tsx
import { expect, test, vi } from "vitest";
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
import { renderWithProviders } from "../test/utils";
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } },
}));
// Recharts ResponsiveContainer needs a non-zero size; stub it so children render in jsdom.
vi.mock("recharts", async (orig) => {
  const actual = await orig<typeof import("recharts")>();
  return { ...actual, ResponsiveContainer: ({ children }: { children: React.ReactNode }) => <div style={{ width: 400, height: 200 }}>{children}</div> };
});
import Trends from "./Trends";

const trends = {
  analyzed_at: "2026-06-21T00:00:00Z", total_meals_analyzed: 40, total_symptoms_analyzed: 8, total_wellbeing_analyzed: 0, resolved: [],
  signals: [{ category: "milk", category_label: "Milk & Dairy", unified_score: 0.8, convergent: false, years_seen: [], recurring: false, is_new: false, strength_by_year: {}, channels: [{ outcome_type: "symptom", outcome_name: "bloating", direction: "harmful", relative_risk: 2.1, evidence_count: 9 }] }],
};

function baseHandlers(postSpy?: () => void) {
  return [
    http.get("*/api/trends", () => HttpResponse.json(trends)),
    http.get("*/api/trends/analyze/status", () => HttpResponse.json({ last_analyzed_at: "2026-06-21T00:00:00Z", has_new_data: false })),
    http.get("*/api/symptoms", () => HttpResponse.json([])),
    http.get("*/api/meals", () => HttpResponse.json({ total: 0, meals: [] })),
    http.post("*/api/trends/analyze", () => { postSpy?.(); return HttpResponse.json({ status: "completed", analyzed_at: "x", new_signals_count: 0 }); }),
  ];
}

test("renders a signal card", async () => {
  server.use(...baseHandlers());
  renderWithProviders(<Trends />, { route: "/trends" });
  expect(await screen.findByText("Milk & Dairy")).toBeInTheDocument();
});

test("Analyse pill triggers POST /api/trends/analyze", async () => {
  let posted = false;
  server.use(...baseHandlers(() => { posted = true; }));
  renderWithProviders(<Trends />, { route: "/trends" });
  await screen.findByText("Milk & Dairy");
  await userEvent.click(screen.getByRole("button", { name: /analyse/i }));
  await vi.waitFor(() => expect(posted).toBe(true));
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run src/pages/Trends.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the page**

Create `src/pages/Trends.tsx`:

```tsx
import { useQuery } from "@tanstack/react-query";
import { api } from "../lib/api";
import { useTrends } from "../hooks/useTrends";
import { useAnalyzeStatus, useAnalyze, useSignalVerdict } from "../hooks/useTrendsActions";
import { useUiStore, type TrendsPeriod } from "../lib/store";
import TrendsHero from "../components/signals/TrendsHero";
import SignalCard from "../components/signals/SignalCard";
import SymptomFrequencyChart from "../components/charts/SymptomFrequencyChart";
import MealTypeMixChart from "../components/charts/MealTypeMixChart";
import { symptomFrequency, mealTypeMix } from "../lib/charts";
import type { VerdictType } from "@/types/api";

const PERIODS: TrendsPeriod[] = ["7d", "30d", "90d"];
const DAYS: Record<TrendsPeriod, number> = { "7d": 7, "30d": 30, "90d": 90 };
const MEAL_CHART_CAP = 200;

function startDateFor(period: TrendsPeriod): string {
  const d = new Date();
  d.setDate(d.getDate() - DAYS[period]);
  return d.toISOString();
}

export default function Trends() {
  const trends = useTrends();
  const status = useAnalyzeStatus();
  const analyze = useAnalyze();
  const verdict = useSignalVerdict();
  const period = useUiStore((s) => s.trendsPeriod);
  const setPeriod = useUiStore((s) => s.setTrendsPeriod);
  const start = startDateFor(period);

  const symptoms = useQuery({
    queryKey: ["symptoms", { period }],
    queryFn: () => api.getSymptoms({ start_date: start, limit: 1000 }),
  });
  const chartMeals = useQuery({
    queryKey: ["meals", { period, chart: true }],
    queryFn: () => api.getMeals({ start_date: start, limit: MEAL_CHART_CAP }),
  });

  const analyzedAt = trends.data?.analyzed_at
    ? new Date(trends.data.analyzed_at).toLocaleDateString()
    : "never";

  function onVerdict(category: string, outcome_type: "symptom" | "wellbeing", outcome_name: string, v: VerdictType) {
    verdict.mutate({ category, outcome_type, outcome_name, verdict: v });
  }

  return (
    <div className="mx-auto flex max-w-4xl flex-col gap-6">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h1 className="font-display text-3xl">Trends</h1>
          <div className="font-mono-data text-xs text-text-faint">
            analysed {analyzedAt} · {trends.data?.total_meals_analyzed ?? 0} meals · {trends.data?.total_symptoms_analyzed ?? 0} symptoms
          </div>
        </div>
        <button
          onClick={() => analyze.mutate()}
          disabled={analyze.isPending}
          className="rounded-full bg-brand px-4 py-2 text-sm text-black disabled:opacity-50"
        >
          {analyze.isPending ? "Analysing…" : status.data?.has_new_data ? "Analyse (new data)" : "Analyse"}
        </button>
      </div>

      {/* Period selector (drives the charts) */}
      <div className="flex gap-1 font-mono-data text-xs">
        {PERIODS.map((p) => (
          <button
            key={p}
            onClick={() => setPeriod(p)}
            className={`rounded-lg px-3 py-1 ${p === period ? "bg-surface text-text" : "text-text-muted hover:text-text"}`}
          >
            {p}
          </button>
        ))}
      </div>

      {trends.isPending && <p className="text-text-faint">Loading signals…</p>}
      {trends.isError && <p className="text-sm text-accent-red">Couldn't load trends.</p>}
      {trends.isSuccess && (
        <>
          <TrendsHero data={trends.data} />

          <section className="flex flex-col gap-3">
            <h2 className="text-sm text-text-muted">Food signals</h2>
            {trends.data.signals.length === 0 ? (
              <p className="text-text-faint">No signals yet — keep logging and check back.</p>
            ) : (
              trends.data.signals.map((s) => {
                const ch = s.channels[0];
                return (
                  <SignalCard
                    key={s.category}
                    signal={s}
                    onVerdict={ch ? (v) => onVerdict(s.category, ch.outcome_type, ch.outcome_name, v) : undefined}
                  />
                );
              })
            )}
          </section>

          <section className="grid gap-4 md:grid-cols-2">
            <div className="rounded-2xl border border-surface-border bg-surface p-4">
              <h3 className="mb-2 text-sm text-text-muted">Symptom frequency · {period}</h3>
              {symptoms.isSuccess
                ? <SymptomFrequencyChart data={symptomFrequency(symptoms.data)} />
                : <p className="text-text-faint text-sm">Loading…</p>}
            </div>
            <div className="rounded-2xl border border-surface-border bg-surface p-4">
              <h3 className="mb-2 text-sm text-text-muted">Meal-type mix · {period}</h3>
              {chartMeals.isSuccess
                ? <>
                    <MealTypeMixChart data={mealTypeMix(chartMeals.data.meals)} />
                    {chartMeals.data.total > MEAL_CHART_CAP && (
                      <p className="mt-1 font-mono-data text-xs text-text-faint">showing first {MEAL_CHART_CAP} of {chartMeals.data.total} meals</p>
                    )}
                  </>
                : <p className="text-text-faint text-sm">Loading…</p>}
            </div>
          </section>
        </>
      )}
    </div>
  );
}
```

- [ ] **Step 4: Wire the route in `src/App.tsx`**

Add the import:

```tsx
import Trends from "./pages/Trends";
```

Replace:

```tsx
        <Route path="/trends" element={<ComingSoon />} />
```

with:

```tsx
        <Route path="/trends" element={<Trends />} />
```

- [ ] **Step 5: Run tests + build + lint**

Run: `cd hearty-web && npm run test -- --run src/pages/Trends.test.tsx && npm run build && npm run lint`
Expected: tests PASS; build type-clean; lint 0 problems.

- [ ] **Step 6: Full suite green**

Run: `cd hearty-web && npm run test -- --run`
Expected: all tests pass (Plan 1's 18 + the new ones).

- [ ] **Step 7: Commit**

```bash
git add src/pages/Trends.tsx src/pages/Trends.test.tsx src/App.tsx
git commit -m "feat(web): Trends page — hero, signal cards + verdict, charts, analyse; wire /trends route"
```

---

## Self-Review (run before final code review)

**1. Spec coverage (§5.2 Journal, §5.3 Trends):**
- §5.2 two-panel filter + list → Task 8. ✅
- §5.2 filters → URL query params (date range, keyword, meal_type, symptom_type), survive refresh → Tasks 4, 8 (D2 noted). ✅
- §5.2 pagination 25/page → Task 5 (`JOURNAL_PAGE_SIZE`), Task 8 controls. ✅
- §5.2 card: timestamp mono, description, food badges (amber), symptom severity badges (mild/moderate/severe), expand → Task 6. ✅
- §5.2 expanded: notes, raw JSON toggle, no photo → Task 6. ✅
- §5.2 edit/delete meals → Task 7 (PATCH/DELETE, foods verbatim list). ✅ (Symptom edit/delete API methods exist (Task 1) but symptom-specific edit UI is out of Plan 2 scope — Journal edits the meal; linked symptoms are display-only. Noted.)
- §5.3 header eyebrow + Analyse pill → Task 13 (D1: synchronous, no poll). ✅
- §5.3 strongest-signal hero (3-up stats) → Task 11. ✅
- §5.3 signal cards (strength bar, RR by direction, peak window, evidence, CONVERGENT, is_new/recurring) → Task 10. ✅
- §5.3 charts (symptom-frequency, meal-type-mix) + period selector in Zustand → Tasks 3, 12, 13 (D3 bar charts, D4 200-cap). ✅
- §5.3 per-signal verdict → Tasks 9, 10, 13. ✅
- Realtime invalidation scoped now that more queries exist → Task 2. ✅

**2. Placeholder scan:** No "TBD"/"handle edge cases"/"similar to" — every code step has complete code. ✅

**3. Type consistency:** `JournalFilters` (Task 4) consumed verbatim by `useJournalMeals` (Task 5). `ChartDatum` (Task 12) consumed by both charts. `VerdictType`/`SignalVerdictRequest` (Task 1) used in Tasks 9, 10, 13. `TrendsPeriod` (Task 3) used in Task 13. `severityClass`/`dominantChannel` exported where reused. API method names (`patchMeal`, `deleteMeal`, `analyzeTrends`, `getAnalyzeStatus`, `signalVerdict`) consistent across Tasks 1, 7, 9. ✅

**4. Deviations recorded:** D1–D5 documented above with rationale. ✅

---

## Execution handoff

Execute via **superpowers:subagent-driven-development**: fresh implementer per task (Tasks 1–13 are mostly mechanical → cheap/standard model; the Trends page Task 13 is integration → standard model), two-stage review (spec compliance → code quality) per task, then a final whole-implementation review. Continuous execution — no check-ins between tasks. Finish with **superpowers:finishing-a-development-branch** (push + PR #10, base `web-dashboard-foundation`) **only with user consent**.
