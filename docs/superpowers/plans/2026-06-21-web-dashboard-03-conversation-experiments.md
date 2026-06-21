# Web Dashboard — Plan 3: Trends Conversation + Experiments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Trends Conversation page (chat with Hearty over the user's signals, with one-click confirm-verdict / start-experiment actions) and the Experiments page (manage tracked elimination experiments) to `hearty-web/`.

**Architecture:** Continues Plans 1–2. Conversation is client-accumulated chat state (NOT TanStack Query) — local history, each send POSTs the full history and appends the reply; the opener fires once on mount (StrictMode-guarded). Experiments use TanStack Query (`['experiments']`) with mutations that invalidate it. Proposed verdicts reuse Plan 2's `signalVerdict`; proposed experiments call the new `createExperiment`. Aurora theme, Vitest + RTL + MSW.

**Tech Stack:** React 18, TS (`erasableSyntaxOnly` + `verbatimModuleSyntax`), TanStack Query v5, React Router v6, Tailwind v3 + shadcn/ui v2, Vitest + RTL + MSW v2.

---

## Branch / PR basing

This plan **stacks on the Plan 2 branch** (`web-dashboard-conversation-experiments` was branched from `web-dashboard-journal-trends`). It depends on Plan 2's `signalVerdict` API method and the `VerdictType` type. PRs #9 (Plan 1) and #10 (Plan 2) are both open and unmerged.

When finishing, open PR #11 with **base = `web-dashboard-journal-trends`**. Gotcha: this is a 3-deep stack (`master` ← foundation ← journal-trends ← conversation-experiments). As each lower PR merges to `master`, rebase the remaining stack and retarget the open PR's base.

---

## Verified backend contracts (re-validated 2026-06-21 against `hearty-api/app/routers/` + `app/models/schemas.py` + `app/services/`)

| Endpoint | Request | Response | Notes |
|---|---|---|---|
| `POST /api/trends/conversation` | `{history: ConversationTurn[]}` | `TrendsConversationResponse` | Empty `history` → opener turn (backend runs `ensure_fresh_signals` first). Synchronous. |
| `POST /api/experiments` | `{category, outcome_type:'symptom'|'wellbeing', outcome_name}` | `ExperimentResponse` (200) | **409** if an active experiment already exists for this pattern |
| `GET /api/experiments/active` | — | `ActiveExperimentsResponse {experiments: ExperimentResponse[]}` | active + recent; each carries computed `adherence`/`logged_days`/`nudge_suggested` |
| `POST /api/experiments/{id}/evaluate` | — | `ExperimentResponse` (200) | **404** not found; **409** if not active (unless already has a result → idempotent return) |
| `POST /api/experiments/{id}/abandon` | — | `{ok: true}` | **404** if not found |
| `POST /api/experiments/{id}/restart` | — | `ExperimentResponse` | **404** if not found |
| `POST /api/experiments/{id}/ack-nudge` | — | `{ok: true}` | **404** if not found |

**`ConversationTurn`** `{role:'user'|'assistant', content:string}`.
**`TrendsConversationResponse`** `{reply:string, proposed_verdict?:ProposedVerdict, proposed_experiment?:ProposedExperiment, is_closing:boolean}`.
**`ProposedVerdict`** `{category, outcome_type:'symptom'|'wellbeing', outcome_name, verdict:'confirmed'|'disputed'|'snoozed', category_label?}`.
**`ProposedExperiment`** `{category, outcome_type:'symptom'|'wellbeing', outcome_name, category_label?}`.
**`ExperimentResponse`** `{id, category, category_label?, direction, outcome_type, outcome_name, experiment_start, experiment_end, status, result?, nudged_at?, adherence?, logged_days?, nudge_suggested}`. `experiment_start`/`experiment_end` are **string** (ISO). `status` is a string (`"active"|"completed"|"abandoned"`).
**Experiment `result`** (from `experiment_evaluator.evaluate`): `{verdict:'improved'|'worse'|'no_change'|'inconclusive', reason?:string|null, adherence:number, logged_days:{baseline:number,experiment:number}, baseline_rate?:number|null, experiment_rate?:number|null}`.

---

## Deviations / scope decisions (recorded here)

- **D1 — Conversation is a route, not a tab.** Spec §5.4 allows "`/trends/chat`, or a tab within Trends." We use a dedicated route `/trends/chat`, linked from the Trends header (the Trends page is already dense). No Sidebar entry (it's a sub-surface of Trends).
- **D2 — Experiments are started from the Conversation, not from a manual form.** Spec §5.5 lists "Start (from a signal or manual)". The primary spec flow is the Conversation's `proposed_experiment` (§5.4). A manual "pick a category" start form, and a "Start experiment" affordance on Plan 2's `SignalCard`, are deferred to a later plan (recorded so they aren't lost). The Experiments page manages existing experiments (evaluate/restart/abandon/ack-nudge) and shows results.
- **D3 — Chat state is local, not TanStack Query.** The conversation is turn-by-turn accumulated client state; queries don't model it. History lives in `useState`; sends are awaited mutations.
- **No calories anywhere** (these surfaces don't render food payloads, but keep the rule in mind for any result rendering).

---

## Existing conventions to honor (carry into every subagent dispatch)

- **TS:** `erasableSyntaxOnly` + `verbatimModuleSyntax` — no parameter-properties/enums; `import type` for type-only imports.
- **Tailwind tokens:** `brand`, `surface`, `surface-border`, `accent-violet`, `accent-red`, `warn`, `good`, `text`, `text-muted`, `text-faint`; `.font-mono-data`, `font-display`.
- **Test harness:** Vitest + RTL + MSW; `onUnhandledRequest:"error"` — every fetch needs a handler. `renderWithProviders(ui,{route})` from `src/test/utils.tsx` (QueryClient + MemoryRouter). Any test importing `lib/api` or a component using it must `vi.mock("../lib/supabase", ...)` (or `../../lib/supabase`) with `auth.getSession`. `vi.mock` factories are hoisted — use `vi.hoisted()`/inline `vi.fn()`.
- **StrictMode is ON** (`main.tsx`) — effects double-fire in dev; guard one-shot effects (the conversation opener) with a `useRef`.
- **`ApiError`** (from `lib/api.ts`) carries `.status` — use it to distinguish 409 from other failures.
- **shadcn** pinned to v2. **No calories ever.**
- **Commits:** conventional messages + co-author trailer `Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Push/PR only with explicit user consent.

---

## File structure

**Create:**
- `src/hooks/useExperiments.ts` — `useActiveExperiments` query + `useExperimentActions` (create/evaluate/abandon/restart/ackNudge mutations)
- `src/hooks/useConversation.ts` — local chat state + opener + send
- `src/components/experiments/ExperimentCard.tsx` — one experiment (status, window, adherence, actions, result)
- `src/pages/Experiments.tsx`, `src/pages/Conversation.tsx`
- Test files alongside each logic unit.

**Modify:**
- `src/types/api.ts` — conversation + experiment types (Task 1)
- `src/lib/api.ts` + `src/lib/api.test.ts` — new client methods (Task 1)
- `src/App.tsx` — wire `/experiments` and `/trends/chat` routes (Tasks 4, 6)
- `src/pages/Trends.tsx` — add a "Chat about trends" link to `/trends/chat` (Task 6)

---

## PHASE A — Shared plumbing

### Task 1: Extend types + API client (conversation + experiments)

**Files:**
- Modify: `src/types/api.ts`, `src/lib/api.ts`, `src/lib/api.test.ts`

- [ ] **Step 1: Add the failing API client tests**

Append to `src/lib/api.test.ts`:

```ts
test("trendsConversation posts history and returns reply", async () => {
  let body: unknown = null;
  server.use(
    http.post("http://api.test/api/trends/conversation", async ({ request }) => {
      body = await request.json();
      return HttpResponse.json({ reply: "Hi", proposed_verdict: null, proposed_experiment: null, is_closing: false });
    })
  );
  const { createApiClient } = await import("./api");
  const r = await createApiClient("http://api.test").trendsConversation({ history: [{ role: "user", content: "hey" }] });
  expect(body).toEqual({ history: [{ role: "user", content: "hey" }] });
  expect(r.reply).toBe("Hi");
});

test("createExperiment posts the pattern", async () => {
  let body: unknown = null;
  server.use(
    http.post("http://api.test/api/experiments", async ({ request }) => {
      body = await request.json();
      return HttpResponse.json({ id: "e1", category: "milk", direction: "harmful", outcome_type: "symptom", outcome_name: "bloating", experiment_start: "x", experiment_end: "y", status: "active", nudge_suggested: false });
    })
  );
  const { createApiClient } = await import("./api");
  await createApiClient("http://api.test").createExperiment({ category: "milk", outcome_type: "symptom", outcome_name: "bloating" });
  expect(body).toEqual({ category: "milk", outcome_type: "symptom", outcome_name: "bloating" });
});

test("createExperiment surfaces 409 as ApiError with status", async () => {
  server.use(http.post("http://api.test/api/experiments", () => new HttpResponse(null, { status: 409 })));
  const { createApiClient, ApiError } = await import("./api");
  await expect(createApiClient("http://api.test").createExperiment({ category: "milk", outcome_type: "symptom", outcome_name: "bloating" }))
    .rejects.toMatchObject({ status: 409 });
  // also assert the thrown value is an ApiError
  await expect(createApiClient("http://api.test").createExperiment({ category: "milk", outcome_type: "symptom", outcome_name: "bloating" }))
    .rejects.toBeInstanceOf(ApiError);
});

test("getActiveExperiments returns the list", async () => {
  server.use(http.get("http://api.test/api/experiments/active", () => HttpResponse.json({ experiments: [] })));
  const { createApiClient } = await import("./api");
  const r = await createApiClient("http://api.test").getActiveExperiments();
  expect(r).toEqual({ experiments: [] });
});

test("evaluateExperiment posts to the evaluate endpoint", async () => {
  let hit = "";
  server.use(http.post("http://api.test/api/experiments/e1/evaluate", ({ request }) => { hit = request.method; return HttpResponse.json({ id: "e1", category: "milk", direction: "harmful", outcome_type: "symptom", outcome_name: "bloating", experiment_start: "x", experiment_end: "y", status: "completed", nudge_suggested: false }); }));
  const { createApiClient } = await import("./api");
  const r = await createApiClient("http://api.test").evaluateExperiment("e1");
  expect(hit).toBe("POST");
  expect(r.status).toBe("completed");
});

test("abandon/restart/ackNudge hit their endpoints", async () => {
  const seen: string[] = [];
  server.use(
    http.post("http://api.test/api/experiments/e1/abandon", () => { seen.push("abandon"); return HttpResponse.json({ ok: true }); }),
    http.post("http://api.test/api/experiments/e1/restart", () => { seen.push("restart"); return HttpResponse.json({ id: "e1", category: "milk", direction: "harmful", outcome_type: "symptom", outcome_name: "bloating", experiment_start: "x", experiment_end: "y", status: "active", nudge_suggested: false }); }),
    http.post("http://api.test/api/experiments/e1/ack-nudge", () => { seen.push("ack"); return HttpResponse.json({ ok: true }); }),
  );
  const { createApiClient } = await import("./api");
  const api = createApiClient("http://api.test");
  await api.abandonExperiment("e1");
  await api.restartExperiment("e1");
  await api.ackNudge("e1");
  expect(seen).toEqual(["abandon", "restart", "ack"]);
});
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd hearty-web && npm run test -- --run src/lib/api.test.ts`
Expected: FAIL — the new methods don't exist.

- [ ] **Step 3: Add the types to `src/types/api.ts`**

Append:

```ts
export interface ConversationTurn { role: "user" | "assistant"; content: string }
export interface ProposedVerdict {
  category: string;
  outcome_type: "symptom" | "wellbeing";
  outcome_name: string;
  verdict: VerdictType;
  category_label?: string;
}
export interface ProposedExperiment {
  category: string;
  outcome_type: "symptom" | "wellbeing";
  outcome_name: string;
  category_label?: string;
}
export interface TrendsConversationRequest { history: ConversationTurn[] }
export interface TrendsConversationResponse {
  reply: string;
  proposed_verdict?: ProposedVerdict | null;
  proposed_experiment?: ProposedExperiment | null;
  is_closing: boolean;
}
export interface CreateExperimentRequest {
  category: string;
  outcome_type: "symptom" | "wellbeing";
  outcome_name: string;
}
export interface ExperimentResult {
  verdict: "improved" | "worse" | "no_change" | "inconclusive";
  reason?: string | null;
  adherence: number;
  logged_days: { baseline: number; experiment: number };
  baseline_rate?: number | null;
  experiment_rate?: number | null;
}
export interface ExperimentResponse {
  id: string;
  category: string;
  category_label?: string;
  direction: string;
  outcome_type: string;
  outcome_name: string;
  experiment_start: string;
  experiment_end: string;
  status: string;
  result?: ExperimentResult | null;
  nudged_at?: string;
  adherence?: number;
  logged_days?: number;
  nudge_suggested: boolean;
}
export interface ActiveExperimentsResponse { experiments: ExperimentResponse[] }
```

(`VerdictType` already exists in this file from Plan 2.)

- [ ] **Step 4: Add the client methods to `src/lib/api.ts`**

Extend the import block:

```ts
import type {
  MealsListResponse, MealResponse, CreateMealRequest,
  SymptomResponse, SignalsResponse, SummaryResponse,
  MealUpdateRequest, SymptomUpdateRequest,
  AnalyzeResponse, AnalyzeStatusResponse,
  SignalVerdictRequest, SignalVerdictResponse,
  TrendsConversationRequest, TrendsConversationResponse,
  CreateExperimentRequest, ExperimentResponse, ActiveExperimentsResponse,
} from "@/types/api";
```

Add inside the object returned by `createApiClient` (after `signalVerdict`):

```ts
    trendsConversation: (body: TrendsConversationRequest) =>
      request<TrendsConversationResponse>(`/api/trends/conversation`, { method: "POST", body: JSON.stringify(body) }),
    createExperiment: (body: CreateExperimentRequest) =>
      request<ExperimentResponse>(`/api/experiments`, { method: "POST", body: JSON.stringify(body) }),
    getActiveExperiments: () =>
      request<ActiveExperimentsResponse>(`/api/experiments/active`),
    evaluateExperiment: (id: string) =>
      request<ExperimentResponse>(`/api/experiments/${id}/evaluate`, { method: "POST" }),
    abandonExperiment: (id: string) =>
      request<{ ok: boolean }>(`/api/experiments/${id}/abandon`, { method: "POST" }),
    restartExperiment: (id: string) =>
      request<ExperimentResponse>(`/api/experiments/${id}/restart`, { method: "POST" }),
    ackNudge: (id: string) =>
      request<{ ok: boolean }>(`/api/experiments/${id}/ack-nudge`, { method: "POST" }),
```

- [ ] **Step 5: Run tests + build**

Run: `cd hearty-web && npm run test -- --run src/lib/api.test.ts && npm run build`
Expected: PASS; type-clean.

- [ ] **Step 6: Commit**

```bash
git add src/types/api.ts src/lib/api.ts src/lib/api.test.ts
git commit -m "feat(web): API client methods for trends conversation + experiments"
```

---

## PHASE B — Experiments

### Task 2: Experiments hooks

**Files:**
- Create: `src/hooks/useExperiments.ts`, `src/hooks/useExperiments.test.tsx`

- [ ] **Step 1: Write the failing test**

Create `src/hooks/useExperiments.test.tsx`:

```tsx
import { expect, test, vi } from "vitest";
import { renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } },
}));
import { useActiveExperiments, useExperimentActions } from "./useExperiments";

function wrap() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={qc}>{children}</QueryClientProvider>
  );
}

test("useActiveExperiments loads the list", async () => {
  server.use(http.get("*/api/experiments/active", () => HttpResponse.json({ experiments: [{ id: "e1", category: "milk", direction: "harmful", outcome_type: "symptom", outcome_name: "bloating", experiment_start: "x", experiment_end: "y", status: "active", nudge_suggested: false }] })));
  const { result } = renderHook(() => useActiveExperiments(), { wrapper: wrap() });
  await waitFor(() => expect(result.current.data?.experiments).toHaveLength(1));
});

test("create mutation posts and resolves", async () => {
  server.use(http.post("*/api/experiments", () => HttpResponse.json({ id: "e2", category: "milk", direction: "harmful", outcome_type: "symptom", outcome_name: "bloating", experiment_start: "x", experiment_end: "y", status: "active", nudge_suggested: false })));
  const { result } = renderHook(() => useExperimentActions(), { wrapper: wrap() });
  await result.current.create.mutateAsync({ category: "milk", outcome_type: "symptom", outcome_name: "bloating" });
  await waitFor(() => expect(result.current.create.isSuccess).toBe(true));
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run src/hooks/useExperiments.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the hooks**

Create `src/hooks/useExperiments.ts`:

```ts
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "../lib/api";
import type { CreateExperimentRequest } from "@/types/api";

export function useActiveExperiments() {
  return useQuery({
    queryKey: ["experiments"],
    queryFn: () => api.getActiveExperiments(),
    staleTime: 60_000,
  });
}

export function useExperimentActions() {
  const qc = useQueryClient();
  const invalidate = () => qc.invalidateQueries({ queryKey: ["experiments"] });
  return {
    create: useMutation({ mutationFn: (b: CreateExperimentRequest) => api.createExperiment(b), onSuccess: invalidate }),
    evaluate: useMutation({ mutationFn: (id: string) => api.evaluateExperiment(id), onSuccess: invalidate }),
    abandon: useMutation({ mutationFn: (id: string) => api.abandonExperiment(id), onSuccess: invalidate }),
    restart: useMutation({ mutationFn: (id: string) => api.restartExperiment(id), onSuccess: invalidate }),
    ackNudge: useMutation({ mutationFn: (id: string) => api.ackNudge(id), onSuccess: invalidate }),
  };
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd hearty-web && npm run test -- --run src/hooks/useExperiments.test.tsx`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/hooks/useExperiments.ts src/hooks/useExperiments.test.tsx
git commit -m "feat(web): useExperiments — active query + action mutations"
```

---

### Task 3: `ExperimentCard` component

**Files:**
- Create: `src/components/experiments/ExperimentCard.tsx`, `src/components/experiments/ExperimentCard.test.tsx`

The card shows: status badge, `category_label` → outcome (with direction), window dates (mono), and — when active — an adherence bar + `logged_days` + a nudge indicator (with an "Got it" ack when `nudge_suggested`). Action buttons depend on status: **active** → Evaluate, Abandon; **completed/abandoned** → Restart. When `result` is present, render the result block (verdict colored: improved → good, worse → accent-red, else muted; reason if inconclusive; baseline→experiment rate; adherence). Actions are passed in as callbacks + a `busy` flag (the page owns the mutations).

- [ ] **Step 1: Write the failing test**

Create `src/components/experiments/ExperimentCard.test.tsx`:

```tsx
import { expect, test, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import ExperimentCard from "./ExperimentCard";
import type { ExperimentResponse } from "@/types/api";

const active: ExperimentResponse = {
  id: "e1", category: "milk", category_label: "Milk & Dairy", direction: "harmful",
  outcome_type: "symptom", outcome_name: "bloating",
  experiment_start: "2026-06-01T00:00:00Z", experiment_end: "2026-06-15T00:00:00Z",
  status: "active", adherence: 0.8, logged_days: 10, nudge_suggested: true,
};
const completed: ExperimentResponse = {
  ...active, id: "e2", status: "completed", nudge_suggested: false,
  result: { verdict: "improved", reason: null, adherence: 0.9, logged_days: { baseline: 7, experiment: 12 }, baseline_rate: 0.5, experiment_rate: 0.1 },
};

function noop() {}
const actions = { onEvaluate: noop, onAbandon: noop, onRestart: noop, onAckNudge: noop, busy: false };

test("active card shows status, outcome, adherence, and Evaluate/Abandon", () => {
  render(<ExperimentCard exp={active} actions={actions} />);
  expect(screen.getByText("Milk & Dairy")).toBeInTheDocument();
  expect(screen.getByText(/bloating/)).toBeInTheDocument();
  expect(screen.getByText(/active/i)).toBeInTheDocument();
  expect(screen.getByRole("button", { name: /evaluate/i })).toBeInTheDocument();
  expect(screen.getByRole("button", { name: /abandon/i })).toBeInTheDocument();
});

test("nudge indicator shows when nudge_suggested and acks", async () => {
  const onAckNudge = vi.fn();
  render(<ExperimentCard exp={active} actions={{ ...actions, onAckNudge }} />);
  await userEvent.click(screen.getByRole("button", { name: /got it/i }));
  expect(onAckNudge).toHaveBeenCalled();
});

test("completed card renders the result verdict and a Restart action", () => {
  render(<ExperimentCard exp={completed} actions={actions} />);
  expect(screen.getByText(/improved/i)).toBeInTheDocument();
  expect(screen.getByRole("button", { name: /restart/i })).toBeInTheDocument();
  expect(screen.queryByRole("button", { name: /evaluate/i })).not.toBeInTheDocument();
});

test("Evaluate fires the callback", async () => {
  const onEvaluate = vi.fn();
  render(<ExperimentCard exp={active} actions={{ ...actions, onEvaluate }} />);
  await userEvent.click(screen.getByRole("button", { name: /evaluate/i }));
  expect(onEvaluate).toHaveBeenCalled();
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run src/components/experiments/ExperimentCard.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the component**

Create `src/components/experiments/ExperimentCard.tsx`:

```tsx
import type { ExperimentResponse, ExperimentResult } from "@/types/api";

function fmtDate(iso: string) {
  return new Date(iso).toLocaleDateString();
}
function verdictClass(v: ExperimentResult["verdict"]) {
  if (v === "improved") return "text-good";
  if (v === "worse") return "text-accent-red";
  return "text-text-muted";
}

export interface ExperimentActions {
  onEvaluate: () => void;
  onAbandon: () => void;
  onRestart: () => void;
  onAckNudge: () => void;
  busy: boolean;
}

export default function ExperimentCard({
  exp,
  actions,
}: {
  exp: ExperimentResponse;
  actions: ExperimentActions;
}) {
  const label = exp.category_label ?? exp.category;
  const isActive = exp.status === "active";
  const pct = Math.round(Math.min(1, Math.max(0, exp.adherence ?? 0)) * 100);

  return (
    <div className="rounded-2xl border border-surface-border bg-surface p-4">
      <div className="flex items-start justify-between gap-3">
        <div>
          <div className="text-lg">{label}</div>
          <div className="text-sm text-text-muted">
            {exp.direction} → {exp.outcome_name}
          </div>
        </div>
        <span className="font-mono-data text-xs text-text-faint uppercase">{exp.status}</span>
      </div>

      <div className="mt-2 font-mono-data text-xs text-text-faint">
        {fmtDate(exp.experiment_start)} – {fmtDate(exp.experiment_end)}
      </div>

      {isActive && (
        <div className="mt-3">
          <div className="flex justify-between font-mono-data text-xs text-text-faint">
            <span>adherence</span>
            <span>{pct}% · {exp.logged_days ?? 0} days logged</span>
          </div>
          <div className="mt-1 h-2 w-full rounded-full bg-white/5">
            <div className="h-2 rounded-full bg-brand" style={{ width: `${pct}%` }} />
          </div>
        </div>
      )}

      {isActive && exp.nudge_suggested && (
        <div className="mt-3 flex items-center justify-between rounded-lg border border-warn/40 bg-warn/10 px-3 py-2 text-sm text-warn">
          <span>Logging has dipped — keep it up to get a clear result.</span>
          <button onClick={actions.onAckNudge} disabled={actions.busy} className="rounded-lg border border-warn/40 px-2 py-1 text-xs">Got it</button>
        </div>
      )}

      {exp.result && (
        <div className="mt-3 rounded-lg border border-surface-border bg-black/20 p-3 text-sm">
          <div>
            Result: <span className={`font-mono-data ${verdictClass(exp.result.verdict)}`}>{exp.result.verdict}</span>
            {exp.result.reason ? <span className="text-text-faint"> ({exp.result.reason})</span> : null}
          </div>
          {exp.result.baseline_rate != null && exp.result.experiment_rate != null && (
            <div className="mt-1 font-mono-data text-xs text-text-faint">
              rate {exp.result.baseline_rate} → {exp.result.experiment_rate} · adherence {Math.round(exp.result.adherence * 100)}%
            </div>
          )}
        </div>
      )}

      <div className="mt-3 flex flex-wrap gap-2">
        {isActive ? (
          <>
            <button onClick={actions.onEvaluate} disabled={actions.busy} className="rounded-lg bg-brand px-2 py-1 text-xs text-black">Evaluate</button>
            <button onClick={actions.onAbandon} disabled={actions.busy} className="rounded-lg border border-surface-border px-2 py-1 text-xs text-accent-red">Abandon</button>
          </>
        ) : (
          <button onClick={actions.onRestart} disabled={actions.busy} className="rounded-lg border border-surface-border px-2 py-1 text-xs">Restart</button>
        )}
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd hearty-web && npm run test -- --run src/components/experiments/ExperimentCard.test.tsx`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add src/components/experiments/ExperimentCard.tsx src/components/experiments/ExperimentCard.test.tsx
git commit -m "feat(web): ExperimentCard — status, adherence, result, lifecycle actions"
```

---

### Task 4: `Experiments` page + route

**Files:**
- Create: `src/pages/Experiments.tsx`, `src/pages/Experiments.test.tsx`
- Modify: `src/App.tsx`

The page wires `useActiveExperiments` + `useExperimentActions` to a list of `ExperimentCard`s, with loading/error/empty states. A failed `evaluate` (409 "not active") or other action surfaces a small error line. Mutations' shared pending state drives the cards' `busy`.

- [ ] **Step 1: Write the failing test**

Create `src/pages/Experiments.test.tsx`:

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
import Experiments from "./Experiments";

const exp = { id: "e1", category: "milk", category_label: "Milk & Dairy", direction: "harmful", outcome_type: "symptom", outcome_name: "bloating", experiment_start: "2026-06-01T00:00:00Z", experiment_end: "2026-06-15T00:00:00Z", status: "active", adherence: 0.8, logged_days: 10, nudge_suggested: false };

test("lists active experiments", async () => {
  server.use(http.get("*/api/experiments/active", () => HttpResponse.json({ experiments: [exp] })));
  renderWithProviders(<Experiments />, { route: "/experiments" });
  expect(await screen.findByText("Milk & Dairy")).toBeInTheDocument();
});

test("empty state when none", async () => {
  server.use(http.get("*/api/experiments/active", () => HttpResponse.json({ experiments: [] })));
  renderWithProviders(<Experiments />, { route: "/experiments" });
  expect(await screen.findByText(/no experiments/i)).toBeInTheDocument();
});

test("Evaluate calls the evaluate endpoint", async () => {
  let evaluated = false;
  server.use(
    http.get("*/api/experiments/active", () => HttpResponse.json({ experiments: [exp] })),
    http.post("*/api/experiments/e1/evaluate", () => { evaluated = true; return HttpResponse.json({ ...exp, status: "completed", result: { verdict: "no_change", reason: null, adherence: 0.8, logged_days: { baseline: 7, experiment: 10 }, baseline_rate: 0.2, experiment_rate: 0.2 } }); }),
  );
  renderWithProviders(<Experiments />, { route: "/experiments" });
  await userEvent.click(await screen.findByRole("button", { name: /evaluate/i }));
  await vi.waitFor(() => expect(evaluated).toBe(true));
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run src/pages/Experiments.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the page**

Create `src/pages/Experiments.tsx`:

```tsx
import { useState } from "react";
import { useActiveExperiments, useExperimentActions } from "../hooks/useExperiments";
import ExperimentCard from "../components/experiments/ExperimentCard";
import { ApiError } from "../lib/api";

export default function Experiments() {
  const list = useActiveExperiments();
  const a = useExperimentActions();
  const [err, setErr] = useState<string | null>(null);
  const busy = a.create.isPending || a.evaluate.isPending || a.abandon.isPending || a.restart.isPending || a.ackNudge.isPending;

  function run(p: Promise<unknown>) {
    setErr(null);
    p.catch((e) => {
      if (e instanceof ApiError && e.status === 409) setErr("That action is no longer available — refreshing.");
      else setErr("Something went wrong. Try again.");
    });
  }

  return (
    <div className="mx-auto flex max-w-3xl flex-col gap-6">
      <h1 className="font-display text-3xl">Experiments</h1>
      {err && <p className="text-sm text-accent-red">{err}</p>}
      {list.isPending && <p className="text-text-faint">Loading…</p>}
      {list.isError && <p className="text-sm text-accent-red">Couldn't load experiments.</p>}
      {list.isSuccess && list.data.experiments.length === 0 && (
        <p className="text-text-faint">No experiments yet. Start one from a trend in the chat.</p>
      )}
      {list.isSuccess && list.data.experiments.length > 0 && (
        <div className="flex flex-col gap-3">
          {list.data.experiments.map((exp) => (
            <ExperimentCard
              key={exp.id}
              exp={exp}
              actions={{
                busy,
                onEvaluate: () => run(a.evaluate.mutateAsync(exp.id)),
                onAbandon: () => run(a.abandon.mutateAsync(exp.id)),
                onRestart: () => run(a.restart.mutateAsync(exp.id)),
                onAckNudge: () => run(a.ackNudge.mutateAsync(exp.id)),
              }}
            />
          ))}
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 4: Wire the route in `src/App.tsx`**

Add import `import Experiments from "./pages/Experiments";` and replace `<Route path="/experiments" element={<ComingSoon />} />` with `<Route path="/experiments" element={<Experiments />} />`.

- [ ] **Step 5: Run tests + build + lint**

Run: `cd hearty-web && npm run test -- --run src/pages/Experiments.test.tsx && npm run build && npm run lint`
Expected: tests PASS; type-clean; 0 lint problems.

- [ ] **Step 6: Commit**

```bash
git add src/pages/Experiments.tsx src/pages/Experiments.test.tsx src/App.tsx
git commit -m "feat(web): Experiments page — list, lifecycle actions, results; wire /experiments route"
```

---

## PHASE C — Trends Conversation

### Task 5: `useConversation` hook

**Files:**
- Create: `src/hooks/useConversation.ts`, `src/hooks/useConversation.test.tsx`

Local chat state. On mount (StrictMode-guarded via a ref), POST with empty history to get the opener. `send(content)` appends the user turn, POSTs the full history, appends the assistant reply, and tracks the latest response's proposed actions + `is_closing`. `clearProposals()` lets the page hide a proposed-action card once acted upon.

- [ ] **Step 1: Write the failing test**

Create `src/hooks/useConversation.test.tsx`:

```tsx
import { expect, test, vi } from "vitest";
import { renderHook, act, waitFor } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } },
}));
import { useConversation } from "./useConversation";

test("fetches an opener on mount, then sends and appends a reply", async () => {
  let calls = 0;
  server.use(
    http.post("*/api/trends/conversation", async ({ request }) => {
      calls += 1;
      const body = (await request.json()) as { history: { role: string; content: string }[] };
      if (body.history.length === 0) {
        return HttpResponse.json({ reply: "Hey — want to talk about milk?", proposed_verdict: null, proposed_experiment: null, is_closing: false });
      }
      return HttpResponse.json({ reply: "Got it.", proposed_verdict: { category: "milk", outcome_type: "symptom", outcome_name: "bloating", verdict: "confirmed" }, proposed_experiment: null, is_closing: false });
    })
  );
  const { result } = renderHook(() => useConversation());
  await waitFor(() => expect(result.current.history.some((t) => t.content.includes("milk"))).toBe(true));
  await act(async () => { await result.current.send("yes"); });
  expect(result.current.history.at(-1)).toEqual({ role: "assistant", content: "Got it." });
  expect(result.current.proposedVerdict?.outcome_name).toBe("bloating");
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run src/hooks/useConversation.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the hook**

Create `src/hooks/useConversation.ts`:

```ts
import { useCallback, useEffect, useRef, useState } from "react";
import { api } from "../lib/api";
import type { ConversationTurn, ProposedVerdict, ProposedExperiment } from "@/types/api";

export function useConversation() {
  const [history, setHistory] = useState<ConversationTurn[]>([]);
  const [proposedVerdict, setProposedVerdict] = useState<ProposedVerdict | null>(null);
  const [proposedExperiment, setProposedExperiment] = useState<ProposedExperiment | null>(null);
  const [isClosing, setIsClosing] = useState(false);
  const [isSending, setIsSending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const didInit = useRef(false);

  const apply = useCallback((res: { reply: string; proposed_verdict?: ProposedVerdict | null; proposed_experiment?: ProposedExperiment | null; is_closing: boolean }) => {
    setHistory((h) => [...h, { role: "assistant", content: res.reply }]);
    setProposedVerdict(res.proposed_verdict ?? null);
    setProposedExperiment(res.proposed_experiment ?? null);
    if (res.is_closing) setIsClosing(true);
  }, []);

  // Opener (guarded against StrictMode double-invoke).
  useEffect(() => {
    if (didInit.current) return;
    didInit.current = true;
    setIsSending(true);
    api.trendsConversation({ history: [] })
      .then(apply)
      .catch(() => setError("Couldn't start the conversation."))
      .finally(() => setIsSending(false));
  }, [apply]);

  const send = useCallback(async (content: string) => {
    const text = content.trim();
    if (!text || isSending || isClosing) return;
    const next = [...history, { role: "user" as const, content: text }];
    setHistory(next);
    setProposedVerdict(null);
    setProposedExperiment(null);
    setIsSending(true);
    setError(null);
    try {
      const res = await api.trendsConversation({ history: next });
      apply(res);
    } catch {
      setError("Couldn't send. Try again.");
    } finally {
      setIsSending(false);
    }
  }, [history, isSending, isClosing, apply]);

  const clearProposals = useCallback(() => {
    setProposedVerdict(null);
    setProposedExperiment(null);
  }, []);

  return { history, proposedVerdict, proposedExperiment, isClosing, isSending, error, send, clearProposals };
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd hearty-web && npm run test -- --run src/hooks/useConversation.test.tsx`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/hooks/useConversation.ts src/hooks/useConversation.test.tsx
git commit -m "feat(web): useConversation — local chat state, opener, send, proposed actions"
```

---

### Task 6: `Conversation` page + route + Trends link

**Files:**
- Create: `src/pages/Conversation.tsx`, `src/pages/Conversation.test.tsx`
- Modify: `src/App.tsx`, `src/pages/Trends.tsx`

Chat UI: message bubbles (user right/`bg-brand` text-black, assistant left/`bg-surface`), an input row (disabled while sending or closed), a proposed-verdict card (confirm/dispute/snooze → `signalVerdict` then `clearProposals`), a proposed-experiment card ("Start experiment" → `createExperiment`, 409 → "already running" note, then `clearProposals`), and a closing notice when `is_closing`.

- [ ] **Step 1: Write the failing test**

Create `src/pages/Conversation.test.tsx`:

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
import Conversation from "./Conversation";

test("shows opener, sends a message, and confirms a proposed verdict", async () => {
  let verdictPosted = false;
  server.use(
    http.post("*/api/trends/conversation", async ({ request }) => {
      const body = (await request.json()) as { history: unknown[] };
      if (body.history.length === 0) {
        return HttpResponse.json({ reply: "Hey, noticed milk lately.", proposed_verdict: null, proposed_experiment: null, is_closing: false });
      }
      return HttpResponse.json({ reply: "Want to confirm?", proposed_verdict: { category: "milk", category_label: "Milk & Dairy", outcome_type: "symptom", outcome_name: "bloating", verdict: "confirmed" }, proposed_experiment: null, is_closing: false });
    }),
    http.post("*/api/trends/signal-verdict", () => { verdictPosted = true; return HttpResponse.json({ ok: true }); }),
  );
  renderWithProviders(<Conversation />, { route: "/trends/chat" });
  expect(await screen.findByText(/noticed milk/i)).toBeInTheDocument();
  await userEvent.type(screen.getByPlaceholderText(/message/i), "tell me more");
  await userEvent.click(screen.getByRole("button", { name: /send/i }));
  await screen.findByText(/want to confirm/i);
  await userEvent.click(screen.getByRole("button", { name: /^confirm$/i }));
  await vi.waitFor(() => expect(verdictPosted).toBe(true));
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run src/pages/Conversation.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the page**

Create `src/pages/Conversation.tsx`:

```tsx
import { useState } from "react";
import { useConversation } from "../hooks/useConversation";
import { api, ApiError } from "../lib/api";
import type { VerdictType } from "@/types/api";

export default function Conversation() {
  const c = useConversation();
  const [draft, setDraft] = useState("");
  const [actionMsg, setActionMsg] = useState<string | null>(null);

  async function submit() {
    const text = draft.trim();
    if (!text) return;
    setDraft("");
    await c.send(text);
  }

  async function verdict(v: VerdictType) {
    if (!c.proposedVerdict) return;
    const { category, outcome_type, outcome_name } = c.proposedVerdict;
    setActionMsg(null);
    try {
      await api.signalVerdict({ category, outcome_type, outcome_name, verdict: v });
      setActionMsg(`Marked as ${v}.`);
      c.clearProposals();
    } catch {
      setActionMsg("Couldn't save that.");
    }
  }

  async function startExperiment() {
    if (!c.proposedExperiment) return;
    const { category, outcome_type, outcome_name } = c.proposedExperiment;
    setActionMsg(null);
    try {
      await api.createExperiment({ category, outcome_type, outcome_name });
      setActionMsg("Experiment started — track it on the Experiments page.");
      c.clearProposals();
    } catch (e) {
      setActionMsg(e instanceof ApiError && e.status === 409 ? "An experiment for this is already running." : "Couldn't start the experiment.");
    }
  }

  return (
    <div className="mx-auto flex h-full max-w-2xl flex-col gap-4">
      <h1 className="font-display text-3xl">Chat about your trends</h1>

      <div className="flex flex-1 flex-col gap-3">
        {c.history.map((t, i) => (
          <div key={i} className={t.role === "user" ? "self-end max-w-[80%]" : "self-start max-w-[80%]"}>
            <div className={`rounded-2xl px-4 py-2 ${t.role === "user" ? "bg-brand text-black" : "bg-surface text-text"}`}>
              {t.content}
            </div>
          </div>
        ))}
        {c.isSending && <div className="self-start text-text-faint text-sm">Hearty is typing…</div>}
      </div>

      {c.proposedVerdict && (
        <div className="rounded-2xl border border-surface-border bg-surface p-3">
          <div className="text-sm text-text-muted">
            Confirm {c.proposedVerdict.category_label ?? c.proposedVerdict.category} → {c.proposedVerdict.outcome_name}?
          </div>
          <div className="mt-2 flex gap-2">
            <button onClick={() => verdict("confirmed")} className="rounded-lg border border-surface-border px-2 py-1 text-xs">Confirm</button>
            <button onClick={() => verdict("disputed")} className="rounded-lg border border-surface-border px-2 py-1 text-xs">Dispute</button>
            <button onClick={() => verdict("snoozed")} className="rounded-lg border border-surface-border px-2 py-1 text-xs">Snooze</button>
          </div>
        </div>
      )}

      {c.proposedExperiment && (
        <div className="rounded-2xl border border-surface-border bg-surface p-3">
          <div className="text-sm text-text-muted">
            Start a 2-week experiment on {c.proposedExperiment.category_label ?? c.proposedExperiment.category}?
          </div>
          <button onClick={startExperiment} className="mt-2 rounded-lg bg-brand px-2 py-1 text-xs text-black">Start experiment</button>
        </div>
      )}

      {actionMsg && <p className="text-sm text-text-muted">{actionMsg}</p>}
      {c.error && <p className="text-sm text-accent-red">{c.error}</p>}
      {c.isClosing && <p className="text-sm text-text-faint">This conversation has wrapped up.</p>}

      <div className="flex gap-2">
        <input
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter") submit(); }}
          disabled={c.isSending || c.isClosing}
          placeholder="Message Hearty…"
          className="flex-1 rounded-lg border border-surface-border bg-transparent px-3 py-2 text-sm disabled:opacity-50"
        />
        <button onClick={submit} disabled={c.isSending || c.isClosing} className="rounded-lg bg-brand px-4 py-2 text-sm text-black disabled:opacity-50">Send</button>
      </div>
    </div>
  );
}
```

- [ ] **Step 4: Wire the route + Trends link**

In `src/App.tsx`: add `import Conversation from "./pages/Conversation";` and add a route **inside** the `AppShell` block (next to `/trends`):

```tsx
          <Route path="/trends/chat" element={<Conversation />} />
```

In `src/pages/Trends.tsx`: add `import { Link } from "react-router-dom";` (if not already imported) and, in the header next to the Analyse pill, add:

```tsx
        <Link to="/trends/chat" className="rounded-full border border-surface-border px-4 py-2 text-sm text-text-muted hover:text-text">Chat</Link>
```

(Place it adjacent to the Analyse button so the header reads: title/eyebrow … Chat · Analyse.)

- [ ] **Step 5: Run tests + build + lint**

Run: `cd hearty-web && npm run test -- --run src/pages/Conversation.test.tsx && npm run build && npm run lint`
Expected: tests PASS; type-clean; 0 lint problems.

- [ ] **Step 6: Full suite green**

Run: `cd hearty-web && npm run test -- --run`
Expected: all tests pass (Plan 1+2's 51 + the new ones).

- [ ] **Step 7: Commit**

```bash
git add src/pages/Conversation.tsx src/pages/Conversation.test.tsx src/App.tsx src/pages/Trends.tsx
git commit -m "feat(web): Conversation page — chat, proposed verdict/experiment actions; wire /trends/chat + Trends link"
```

---

## Self-Review

**1. Spec coverage (§5.4 Conversation, §5.5 Experiments):**
- §5.4 chat over `POST /api/trends/conversation` sending `history`, renders `reply` → Tasks 5, 6. ✅
- §5.4 `proposed_verdict` → confirm/dispute/snooze → `signal-verdict` → Task 6 (reuses Plan 2 `signalVerdict`). ✅
- §5.4 `proposed_experiment` → Start experiment → `POST /api/experiments` → Task 6. ✅
- §5.4 `is_closing` ends gracefully → Task 6 (input disabled + notice). ✅
- §5.5 `GET /api/experiments/active` → list → Tasks 2, 4. ✅
- §5.5 actions Start/Evaluate/Restart/Abandon/Ack-nudge → Tasks 2, 3, 4 (Start from chat per D2). ✅
- §5.5 `result` rendering + nudge indicator → Task 3. ✅
- Mutations invalidate `['experiments']` → Task 2. ✅

**2. Placeholder scan:** No "TBD"/"handle errors"/"similar to" — every code step has complete code. ✅

**3. Type consistency:** `ConversationTurn`/`ProposedVerdict`/`ProposedExperiment`/`TrendsConversationResponse` defined in Task 1, consumed by Tasks 5–6. `ExperimentResponse`/`ExperimentResult`/`ActiveExperimentsResponse` defined in Task 1, consumed by Tasks 2–4. `ExperimentActions` interface (Task 3) consumed by Task 4. API method names (`trendsConversation`, `createExperiment`, `getActiveExperiments`, `evaluateExperiment`, `abandonExperiment`, `restartExperiment`, `ackNudge`) consistent across Tasks 1, 2, 4, 6. `signalVerdict` reused from Plan 2. ✅

**4. Deviations recorded:** D1–D3 documented with rationale; manual/signal-card experiment start explicitly deferred. ✅

---

## Execution handoff

Execute via **superpowers:subagent-driven-development** (mechanical units → cheap/standard model; the two pages are integration → standard), two-stage review (spec → quality) per unit + a final whole-implementation review. Continuous execution. Finish with **superpowers:finishing-a-development-branch** (push + PR #11, base `web-dashboard-journal-trends`) **only with user consent**.
