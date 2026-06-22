# Web Dashboard — Plan 5: Profile (Health Profile) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Profile page (`/profile`) — a structured health-profile editor for allergens, intolerances, conditions, and dietary protocols, seeded by canonical defaults, with a persistent non-dismissable medical disclaimer.

**Architecture:** Web-only (the backend endpoints already exist). A generic `ProfileSection<T>` renders any list of entries (add / remove / suggestion chips); the Profile page wires four typed sections over a single editable draft (loaded-prefs + edits overlay, no hydration effect), and a full-replace `PUT /api/health-profile` on save. TanStack Query for server state; Aurora theme; Vitest + RTL + MSW.

**Tech Stack:** React 18, TS (`erasableSyntaxOnly` + `verbatimModuleSyntax`), TanStack Query v5, React Router v6, Tailwind v3 + shadcn/ui v2, Vitest + RTL + MSW v2.

---

## Branch / PR basing

This plan **stacks on the Plan 4 branch** (`web-dashboard-profile` was branched from `web-dashboard-reports-settings`). PRs #9–#12 are all open and unmerged. When finishing, open PR #13 with **base = `web-dashboard-reports-settings`**. This is a 5-deep stack; as lower PRs merge to `master`, rebase the remaining stack and retarget the open PR's base.

---

## Verified backend contracts (re-validated 2026-06-21 against `hearty-api/app/health_profile/`)

| Endpoint | Request | Response | Notes |
|---|---|---|---|
| `GET /api/health-profile` | — | `HealthProfileResponse` | auto-creates an empty row if none |
| `PUT /api/health-profile` | `HealthProfilePutRequest` (all four lists required) | `HealthProfileResponse` | **full replace** (upsert) |
| `GET /api/health-profile/defaults` | — (no auth required) | `{allergens, intolerances, conditions, dietary_protocols: string[]}` | canonical quick-select names |

There are also per-sub-resource PUTs (`/allergens`, `/intolerances`, …) and a PATCH; **this plan uses only the top-level GET/PUT + defaults** (D1).

**Entry shapes (verbatim from `health_profile/schemas.py`):**
- **`AllergenEntry`** `{ name: string; severity: 'mild'|'moderate'|'severe'  (REQUIRED); reaction?: string; confirmed_by_doctor: boolean (default false); notes?: string }`
- **`IntoleranceEntry`** `{ name: string; severity?: 'mild'|'moderate'|'severe' (OPTIONAL); threshold?: string; notes?: string }`
- **`ConditionEntry`** `{ name: string; diagnosed: boolean (default false); diagnosis_year?: number; notes?: string }`
- **`DietaryProtocolEntry`** `{ name: string; active: boolean (default true); started?: string (ISO 'YYYY-MM-DD'); phase?: string; notes?: string }`
- **`HealthProfileResponse`** = the four lists + `updated_at: string`.

**Disclaimer (verbatim, spec §5.7):** "Hearty is not a medical device. Information provided is for personal tracking only and does not constitute medical advice. Always consult a qualified healthcare professional."

---

## Deviations / scope decisions (recorded here)

- **D1 — Top-level GET/PUT only.** The page loads the whole profile and saves the whole profile (full replace) — it does not use the per-sub-resource endpoints or PATCH. Simpler and atomic.
- **D2 — Defaults are quick-add suggestions.** `GET /defaults` names render as suggestion chips per section; clicking one appends a new entry pre-named (severity `mild` for allergens, `active: true` for protocols, etc.). Not an autocomplete on the free-text name field.
- **D3 — `dietary_protocols.started` must be `YYYY-MM-DD`.** The backend validates this; the UI uses `<input type="date">` (which emits that format) so invalid strings can't be sent.
- **No calories anywhere.**

---

## Existing conventions to honor (carry into every subagent dispatch)

- **TS:** `erasableSyntaxOnly` + `verbatimModuleSyntax` — no parameter-properties/enums; `import type` for type-only imports. Generic components are fine in `.tsx` via a function declaration (`export default function ProfileSection<T>(...)`).
- **Tailwind tokens:** `brand`, `surface`, `surface-border`, `accent-violet`, `accent-red`, `warn`, `good`, `text`, `text-muted`, `text-faint`; `.font-mono-data`, `font-display`.
- **Tests:** Vitest + RTL + MSW; `onUnhandledRequest:"error"` — every fetch needs a handler. `renderWithProviders(ui,{route})` (QueryClient + MemoryRouter). Tests importing `lib/api` or a component using it must `vi.mock("../lib/supabase", ...)` (correct depth) with `auth.getSession`. `vi.mock` factories hoisted. Avoid setState-in-effect (lint error) — derive the draft as `{ ...data, ...edits }`, don't hydrate via effect.
- **shadcn** pinned to v2. **No calories ever.**
- **Commits:** conventional + co-author trailer `Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Push/PR only with explicit user consent.

---

## File structure

**Create:**
- `src/hooks/useHealthProfile.ts` — profile + defaults queries, save mutation
- `src/components/profile/ProfileSection.tsx` — generic list-section editor
- `src/pages/Profile.tsx`
- Test files alongside.

**Modify:**
- `src/types/api.ts` — health-profile types (Task 1)
- `src/lib/api.ts` + `src/lib/api.test.ts` — `getHealthProfile`/`putHealthProfile`/`getHealthProfileDefaults` (Task 1)
- `src/App.tsx` — wire `/profile` route (Task 4)

---

## PHASE A — Plumbing

### Task 1: Health-profile types + API methods

**Files:**
- Modify: `src/types/api.ts`, `src/lib/api.ts`, `src/lib/api.test.ts`

- [ ] **Step 1: Add failing API client tests**

Append to `src/lib/api.test.ts`:

```ts
test("getHealthProfile returns the four lists", async () => {
  server.use(http.get("http://api.test/api/health-profile", () => HttpResponse.json({ allergens: [], intolerances: [], conditions: [], dietary_protocols: [], updated_at: "2026-06-21T00:00:00Z" })));
  const { createApiClient } = await import("./api");
  const r = await createApiClient("http://api.test").getHealthProfile();
  expect(r.allergens).toEqual([]);
  expect(r.updated_at).toBe("2026-06-21T00:00:00Z");
});

test("putHealthProfile sends all four lists", async () => {
  let body: unknown = null;
  server.use(http.put("http://api.test/api/health-profile", async ({ request }) => { body = await request.json(); return HttpResponse.json({ allergens: [], intolerances: [], conditions: [], dietary_protocols: [], updated_at: "x" }); }));
  const { createApiClient } = await import("./api");
  await createApiClient("http://api.test").putHealthProfile({ allergens: [{ name: "peanut", severity: "severe", confirmed_by_doctor: true }], intolerances: [], conditions: [], dietary_protocols: [] });
  expect(body).toMatchObject({ allergens: [{ name: "peanut", severity: "severe", confirmed_by_doctor: true }], intolerances: [], conditions: [], dietary_protocols: [] });
});

test("getHealthProfileDefaults returns suggestion lists", async () => {
  server.use(http.get("http://api.test/api/health-profile/defaults", () => HttpResponse.json({ allergens: ["Peanuts"], intolerances: ["Lactose"], conditions: ["IBS"], dietary_protocols: ["Low FODMAP"] })));
  const { createApiClient } = await import("./api");
  const r = await createApiClient("http://api.test").getHealthProfileDefaults();
  expect(r.allergens).toEqual(["Peanuts"]);
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run src/lib/api.test.ts`
Expected: FAIL — methods don't exist.

- [ ] **Step 3: Add types to `src/types/api.ts`**

Append:

```ts
export type Severity = "mild" | "moderate" | "severe";
export interface AllergenEntry { name: string; severity: Severity; reaction?: string; confirmed_by_doctor: boolean; notes?: string }
export interface IntoleranceEntry { name: string; severity?: Severity; threshold?: string; notes?: string }
export interface ConditionEntry { name: string; diagnosed: boolean; diagnosis_year?: number; notes?: string }
export interface DietaryProtocolEntry { name: string; active: boolean; started?: string; phase?: string; notes?: string }
export interface HealthProfileResponse {
  allergens: AllergenEntry[];
  intolerances: IntoleranceEntry[];
  conditions: ConditionEntry[];
  dietary_protocols: DietaryProtocolEntry[];
  updated_at: string;
}
export interface HealthProfilePutRequest {
  allergens: AllergenEntry[];
  intolerances: IntoleranceEntry[];
  conditions: ConditionEntry[];
  dietary_protocols: DietaryProtocolEntry[];
}
export interface HealthProfileDefaults {
  allergens: string[];
  intolerances: string[];
  conditions: string[];
  dietary_protocols: string[];
}
```

- [ ] **Step 4: Add the client methods to `src/lib/api.ts`**

Extend the import block to include `HealthProfileResponse, HealthProfilePutRequest, HealthProfileDefaults`. Add to the returned object:

```ts
    getHealthProfile: () => request<HealthProfileResponse>(`/api/health-profile`),
    putHealthProfile: (body: HealthProfilePutRequest) => request<HealthProfileResponse>(`/api/health-profile`, { method: "PUT", body: JSON.stringify(body) }),
    getHealthProfileDefaults: () => request<HealthProfileDefaults>(`/api/health-profile/defaults`),
```

- [ ] **Step 5: Run tests + build**

Run: `cd hearty-web && npm run test -- --run src/lib/api.test.ts && npm run build`
Expected: PASS; type-clean.

- [ ] **Step 6: Commit**

```bash
git add src/types/api.ts src/lib/api.ts src/lib/api.test.ts
git commit -m "feat(web): health-profile API methods + types"
```

---

## PHASE B — Hook

### Task 2: `useHealthProfile` hooks

**Files:**
- Create: `src/hooks/useHealthProfile.ts`, `src/hooks/useHealthProfile.test.tsx`

- [ ] **Step 1: Write the failing test**

Create `src/hooks/useHealthProfile.test.tsx`:

```tsx
import { expect, test, vi } from "vitest";
import { renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } },
}));
import { useHealthProfile, useHealthProfileDefaults, useSaveHealthProfile } from "./useHealthProfile";

function wrap() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={qc}>{children}</QueryClientProvider>
  );
}

test("useHealthProfile loads the profile", async () => {
  server.use(http.get("*/api/health-profile", () => HttpResponse.json({ allergens: [{ name: "peanut", severity: "severe", confirmed_by_doctor: true }], intolerances: [], conditions: [], dietary_protocols: [], updated_at: "x" })));
  const { result } = renderHook(() => useHealthProfile(), { wrapper: wrap() });
  await waitFor(() => expect(result.current.data?.allergens).toHaveLength(1));
});

test("useHealthProfileDefaults loads suggestions", async () => {
  server.use(http.get("*/api/health-profile/defaults", () => HttpResponse.json({ allergens: ["Peanuts"], intolerances: [], conditions: [], dietary_protocols: [] })));
  const { result } = renderHook(() => useHealthProfileDefaults(), { wrapper: wrap() });
  await waitFor(() => expect(result.current.data?.allergens).toEqual(["Peanuts"]));
});

test("useSaveHealthProfile PUTs and resolves", async () => {
  server.use(http.put("*/api/health-profile", () => HttpResponse.json({ allergens: [], intolerances: [], conditions: [], dietary_protocols: [], updated_at: "x" })));
  const { result } = renderHook(() => useSaveHealthProfile(), { wrapper: wrap() });
  await result.current.mutateAsync({ allergens: [], intolerances: [], conditions: [], dietary_protocols: [] });
  await waitFor(() => expect(result.current.isSuccess).toBe(true));
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run src/hooks/useHealthProfile.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the hooks**

Create `src/hooks/useHealthProfile.ts`:

```ts
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "../lib/api";
import type { HealthProfilePutRequest } from "@/types/api";

export function useHealthProfile() {
  return useQuery({ queryKey: ["health-profile"], queryFn: () => api.getHealthProfile(), staleTime: 300_000 });
}

export function useHealthProfileDefaults() {
  return useQuery({ queryKey: ["health-profile", "defaults"], queryFn: () => api.getHealthProfileDefaults(), staleTime: Infinity });
}

export function useSaveHealthProfile() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: HealthProfilePutRequest) => api.putHealthProfile(body),
    onSuccess: (data) => qc.setQueryData(["health-profile"], data),
  });
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd hearty-web && npm run test -- --run src/hooks/useHealthProfile.test.tsx`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/hooks/useHealthProfile.ts src/hooks/useHealthProfile.test.tsx
git commit -m "feat(web): useHealthProfile — profile + defaults queries, save mutation"
```

---

## PHASE C — Generic section editor

### Task 3: `ProfileSection<T>` component

**Files:**
- Create: `src/components/profile/ProfileSection.tsx`, `src/components/profile/ProfileSection.test.tsx`

A generic, type-safe list editor: renders a titled card; each entry gets a sub-card with caller-supplied `renderFields(entry, update)` + a Remove button; an Add button appends `newEntry()`; optional suggestion chips append `suggestionToEntry(name)`.

- [ ] **Step 1: Write the failing test**

Create `src/components/profile/ProfileSection.test.tsx`:

```tsx
import { expect, test, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import ProfileSection from "./ProfileSection";

interface Row { name: string }

function Harness({ initial = [] as Row[] }) {
  const [rows, setRows] = (globalThis as unknown as { React: typeof import("react") }).React.useState<Row[]>(initial);
  return (
    <ProfileSection<Row>
      title="Things"
      entries={rows}
      onChange={setRows}
      newEntry={() => ({ name: "" })}
      suggestions={["Peanuts"]}
      suggestionToEntry={(name) => ({ name })}
      renderFields={(e, update) => (
        <input aria-label="name" value={e.name} onChange={(ev) => update({ name: ev.target.value })} />
      )}
    />
  );
}

test("adds, edits, removes, and quick-adds a suggestion", async () => {
  render(<Harness />);
  await userEvent.click(screen.getByRole("button", { name: /add things/i }));
  const input = screen.getByLabelText("name");
  await userEvent.type(input, "oats");
  expect(screen.getByLabelText("name")).toHaveValue("oats");
  await userEvent.click(screen.getByRole("button", { name: /^Peanuts$/ }));
  expect(screen.getAllByLabelText("name")).toHaveLength(2);
  await userEvent.click(screen.getAllByRole("button", { name: /remove/i })[0]);
  expect(screen.getAllByLabelText("name")).toHaveLength(1);
});
```

(The `Harness` reads `React` from a global to avoid an extra import line in the snippet; in the actual test file just `import { useState } from "react"` and use it directly — see implementation note.)

**Implementation note for the engineer:** write the test's `Harness` with a normal `import { useState } from "react";` and `const [rows, setRows] = useState<Row[]>(initial);` — the global indirection above is only to keep the snippet self-contained. Keep the assertions identical.

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run src/components/profile/ProfileSection.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the component**

Create `src/components/profile/ProfileSection.tsx`:

```tsx
import type { ReactNode } from "react";

export default function ProfileSection<T>({
  title,
  entries,
  onChange,
  newEntry,
  renderFields,
  suggestions,
  suggestionToEntry,
}: {
  title: string;
  entries: T[];
  onChange: (entries: T[]) => void;
  newEntry: () => T;
  renderFields: (entry: T, update: (patch: Partial<T>) => void) => ReactNode;
  suggestions?: string[];
  suggestionToEntry?: (name: string) => T;
}) {
  function update(index: number, patch: Partial<T>) {
    onChange(entries.map((e, i) => (i === index ? { ...e, ...patch } : e)));
  }
  function remove(index: number) {
    onChange(entries.filter((_, i) => i !== index));
  }

  return (
    <section className="rounded-2xl border border-surface-border bg-surface p-4">
      <h2 className="mb-3 text-sm text-text-muted">{title}</h2>

      <div className="flex flex-col gap-3">
        {entries.map((entry, i) => (
          <div key={i} className="rounded-xl border border-surface-border p-3">
            <div className="flex flex-col gap-2">{renderFields(entry, (patch) => update(i, patch))}</div>
            <button onClick={() => remove(i)} className="mt-2 text-xs text-accent-red underline">Remove</button>
          </div>
        ))}
        {entries.length === 0 && <p className="text-text-faint text-sm">None added.</p>}
      </div>

      <button onClick={() => onChange([...entries, newEntry()])} className="mt-3 rounded-lg border border-surface-border px-3 py-1 text-sm">
        Add {title.toLowerCase()}
      </button>

      {suggestions && suggestions.length > 0 && suggestionToEntry && (
        <div className="mt-3 flex flex-wrap gap-1">
          {suggestions.map((name) => (
            <button
              key={name}
              onClick={() => onChange([...entries, suggestionToEntry(name)])}
              className="rounded-full border border-surface-border px-2 py-0.5 text-xs text-text-muted hover:text-text"
            >
              {name}
            </button>
          ))}
        </div>
      )}
    </section>
  );
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd hearty-web && npm run test -- --run src/components/profile/ProfileSection.test.tsx`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/components/profile/ProfileSection.tsx src/components/profile/ProfileSection.test.tsx
git commit -m "feat(web): generic ProfileSection list editor (add/remove/suggest)"
```

---

## PHASE D — Profile page

### Task 4: `Profile` page + route

**Files:**
- Create: `src/pages/Profile.tsx`, `src/pages/Profile.test.tsx`
- Modify: `src/App.tsx`

Loads profile + defaults; editable draft = `{ ...data, ...edits }` (overlay, no effect); four `ProfileSection`s with per-type `renderFields`/`newEntry`/`suggestionToEntry`; full-replace `PUT` on Save; persistent non-dismissable disclaimer banner.

- [ ] **Step 1: Write the failing test**

Create `src/pages/Profile.test.tsx`:

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
import Profile from "./Profile";

const empty = { allergens: [], intolerances: [], conditions: [], dietary_protocols: [], updated_at: "x" };

test("shows the disclaimer and saves a quick-added allergen", async () => {
  let put: Record<string, unknown> | null = null;
  server.use(
    http.get("*/api/health-profile/defaults", () => HttpResponse.json({ allergens: ["Peanuts"], intolerances: [], conditions: [], dietary_protocols: [] })),
    http.get("*/api/health-profile", () => HttpResponse.json(empty)),
    http.put("*/api/health-profile", async ({ request }) => { put = (await request.json()) as Record<string, unknown>; return HttpResponse.json({ ...empty }); }),
  );
  renderWithProviders(<Profile />, { route: "/profile" });
  expect(await screen.findByText(/not a medical device/i)).toBeInTheDocument();
  await userEvent.click(await screen.findByRole("button", { name: /^Peanuts$/ }));
  await userEvent.click(screen.getByRole("button", { name: /save profile/i }));
  await vi.waitFor(() => expect(put).not.toBeNull());
  expect((put!.allergens as unknown[])).toHaveLength(1);
  expect((put!.allergens as { name: string; severity: string }[])[0]).toMatchObject({ name: "Peanuts", severity: "mild" });
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run src/pages/Profile.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the page**

Create `src/pages/Profile.tsx`:

```tsx
import { useState } from "react";
import { useHealthProfile, useHealthProfileDefaults, useSaveHealthProfile } from "../hooks/useHealthProfile";
import ProfileSection from "../components/profile/ProfileSection";
import type {
  AllergenEntry, IntoleranceEntry, ConditionEntry, DietaryProtocolEntry,
  HealthProfilePutRequest, Severity,
} from "@/types/api";

const DISCLAIMER = "Hearty is not a medical device. Information provided is for personal tracking only and does not constitute medical advice. Always consult a qualified healthcare professional.";
const SEVERITIES: Severity[] = ["mild", "moderate", "severe"];

export default function Profile() {
  const profile = useHealthProfile();
  const defaults = useHealthProfileDefaults();
  const save = useSaveHealthProfile();
  const [edits, setEdits] = useState<Partial<HealthProfilePutRequest>>({});
  const [msg, setMsg] = useState<string | null>(null);

  const draft: HealthProfilePutRequest | null = profile.data
    ? {
        allergens: edits.allergens ?? profile.data.allergens,
        intolerances: edits.intolerances ?? profile.data.intolerances,
        conditions: edits.conditions ?? profile.data.conditions,
        dietary_protocols: edits.dietary_protocols ?? profile.data.dietary_protocols,
      }
    : null;

  async function onSave() {
    if (!draft) return;
    setMsg(null);
    try { await save.mutateAsync(draft); setEdits({}); setMsg("Saved."); }
    catch { setMsg("Couldn't save."); }
  }

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-6">
      <h1 className="font-display text-3xl">Profile</h1>

      {/* Persistent, non-dismissable disclaimer */}
      <div className="rounded-2xl border border-warn/40 bg-warn/10 p-3 text-sm text-warn">{DISCLAIMER}</div>

      {profile.isPending && <p className="text-text-faint">Loading…</p>}
      {profile.isError && <p className="text-sm text-accent-red">Couldn't load your profile.</p>}

      {draft && (
        <>
          <ProfileSection<AllergenEntry>
            title="Allergens"
            entries={draft.allergens}
            onChange={(allergens) => setEdits((e) => ({ ...e, allergens }))}
            newEntry={() => ({ name: "", severity: "mild", confirmed_by_doctor: false })}
            suggestions={defaults.data?.allergens}
            suggestionToEntry={(name) => ({ name, severity: "mild", confirmed_by_doctor: false })}
            renderFields={(a, update) => (
              <>
                <input aria-label="allergen name" value={a.name} onChange={(e) => update({ name: e.target.value })} placeholder="Name" className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
                <select aria-label="allergen severity" value={a.severity} onChange={(e) => update({ severity: e.target.value as Severity })} className="rounded-lg border border-surface-border bg-surface px-2 py-1 text-sm">
                  {SEVERITIES.map((s) => <option key={s} value={s}>{s}</option>)}
                </select>
                <input aria-label="allergen reaction" value={a.reaction ?? ""} onChange={(e) => update({ reaction: e.target.value || undefined })} placeholder="Reaction (optional)" className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
                <label className="flex items-center gap-2 text-xs text-text-muted">
                  <input type="checkbox" checked={a.confirmed_by_doctor} onChange={(e) => update({ confirmed_by_doctor: e.target.checked })} />
                  Confirmed by doctor
                </label>
                <input aria-label="allergen notes" value={a.notes ?? ""} onChange={(e) => update({ notes: e.target.value || undefined })} placeholder="Notes (optional)" className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
              </>
            )}
          />

          <ProfileSection<IntoleranceEntry>
            title="Intolerances"
            entries={draft.intolerances}
            onChange={(intolerances) => setEdits((e) => ({ ...e, intolerances }))}
            newEntry={() => ({ name: "" })}
            suggestions={defaults.data?.intolerances}
            suggestionToEntry={(name) => ({ name })}
            renderFields={(it, update) => (
              <>
                <input aria-label="intolerance name" value={it.name} onChange={(e) => update({ name: e.target.value })} placeholder="Name" className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
                <select aria-label="intolerance severity" value={it.severity ?? ""} onChange={(e) => update({ severity: (e.target.value || undefined) as Severity | undefined })} className="rounded-lg border border-surface-border bg-surface px-2 py-1 text-sm">
                  <option value="">unset</option>
                  {SEVERITIES.map((s) => <option key={s} value={s}>{s}</option>)}
                </select>
                <input aria-label="intolerance threshold" value={it.threshold ?? ""} onChange={(e) => update({ threshold: e.target.value || undefined })} placeholder="Threshold (optional)" className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
                <input aria-label="intolerance notes" value={it.notes ?? ""} onChange={(e) => update({ notes: e.target.value || undefined })} placeholder="Notes (optional)" className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
              </>
            )}
          />

          <ProfileSection<ConditionEntry>
            title="Conditions"
            entries={draft.conditions}
            onChange={(conditions) => setEdits((e) => ({ ...e, conditions }))}
            newEntry={() => ({ name: "", diagnosed: false })}
            suggestions={defaults.data?.conditions}
            suggestionToEntry={(name) => ({ name, diagnosed: false })}
            renderFields={(c, update) => (
              <>
                <input aria-label="condition name" value={c.name} onChange={(e) => update({ name: e.target.value })} placeholder="Name" className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
                <label className="flex items-center gap-2 text-xs text-text-muted">
                  <input type="checkbox" checked={c.diagnosed} onChange={(e) => update({ diagnosed: e.target.checked })} />
                  Diagnosed
                </label>
                <input aria-label="condition diagnosis year" type="number" value={c.diagnosis_year ?? ""} onChange={(e) => update({ diagnosis_year: e.target.value ? Number(e.target.value) : undefined })} placeholder="Year (optional)" className="w-28 rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
                <input aria-label="condition notes" value={c.notes ?? ""} onChange={(e) => update({ notes: e.target.value || undefined })} placeholder="Notes (optional)" className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
              </>
            )}
          />

          <ProfileSection<DietaryProtocolEntry>
            title="Dietary protocols"
            entries={draft.dietary_protocols}
            onChange={(dietary_protocols) => setEdits((e) => ({ ...e, dietary_protocols }))}
            newEntry={() => ({ name: "", active: true })}
            suggestions={defaults.data?.dietary_protocols}
            suggestionToEntry={(name) => ({ name, active: true })}
            renderFields={(p, update) => (
              <>
                <input aria-label="protocol name" value={p.name} onChange={(e) => update({ name: e.target.value })} placeholder="Name" className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
                <label className="flex items-center gap-2 text-xs text-text-muted">
                  <input type="checkbox" checked={p.active} onChange={(e) => update({ active: e.target.checked })} />
                  Active
                </label>
                <input aria-label="protocol started" type="date" value={p.started ?? ""} onChange={(e) => update({ started: e.target.value || undefined })} className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
                <input aria-label="protocol phase" value={p.phase ?? ""} onChange={(e) => update({ phase: e.target.value || undefined })} placeholder="Phase (optional)" className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
                <input aria-label="protocol notes" value={p.notes ?? ""} onChange={(e) => update({ notes: e.target.value || undefined })} placeholder="Notes (optional)" className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
              </>
            )}
          />

          <div className="flex items-center gap-3">
            <button onClick={onSave} disabled={save.isPending} className="rounded-lg bg-brand px-4 py-2 text-sm text-black disabled:opacity-50">{save.isPending ? "Saving…" : "Save profile"}</button>
            {msg && <span className="text-sm text-text-muted">{msg}</span>}
          </div>
        </>
      )}
    </div>
  );
}
```

- [ ] **Step 4: Wire the route in `src/App.tsx`**

Add `import Profile from "./pages/Profile";` and replace `<Route path="/profile" element={<ComingSoon />} />` with `<Route path="/profile" element={<Profile />} />`. (`ComingSoon` is now unused in App.tsx — remove its import to keep lint clean.)

- [ ] **Step 5: Run tests + build + lint**

Run: `cd hearty-web && npm run test -- --run src/pages/Profile.test.tsx && npm run build && npm run lint`
Expected: tests PASS; type-clean; 0 lint.

- [ ] **Step 6: Full suite green**

Run: `cd hearty-web && npm run test -- --run`
Expected: all tests pass (Plan 1–4's 79 + the new ones).

- [ ] **Step 7: Commit**

```bash
git add src/pages/Profile.tsx src/pages/Profile.test.tsx src/App.tsx
git commit -m "feat(web): Profile page — health profile editor + disclaimer; wire /profile route"
```

---

## Self-Review

**1. Spec coverage (§5.7 Profile):**
- `GET /api/health-profile` + `PUT` (full replace) → Tasks 1, 2, 4. ✅
- Allergens `AllergenEntry{name, severity(mild|moderate|severe), reaction?, confirmed_by_doctor, notes?}` → Task 4. ✅
- Intolerances `IntoleranceEntry{name, severity?, threshold?, notes?}` → Task 4. ✅
- Conditions `ConditionEntry{name, diagnosed, diagnosis_year?, notes?}` → Task 4. ✅
- Dietary protocols `DietaryProtocolEntry{name, active, started?, phase?, notes?}` → Task 4 (date input → YYYY-MM-DD, D3). ✅
- Seed suggestions from `GET /api/health-profile/defaults` → Tasks 1, 2, 4 (quick-add chips, D2). ✅
- Persistent non-dismissable disclaimer (verbatim) → Task 4. ✅

**2. Placeholder scan:** No "TBD"/"handle errors"/"similar to" — every code step has complete code. ✅

**3. Type consistency:** `AllergenEntry`/`IntoleranceEntry`/`ConditionEntry`/`DietaryProtocolEntry`/`Severity`/`HealthProfileResponse`/`HealthProfilePutRequest`/`HealthProfileDefaults` defined in Task 1, used by Tasks 2, 4. `ProfileSection<T>` generic (Task 3) instantiated four times in Task 4. API method names (`getHealthProfile`/`putHealthProfile`/`getHealthProfileDefaults`) consistent across Tasks 1, 2. Hook names (`useHealthProfile`/`useHealthProfileDefaults`/`useSaveHealthProfile`) consistent across Tasks 2, 4. ✅

**4. Deviations recorded:** D1–D3 documented with rationale. ✅

---

## Execution handoff

Execute via **superpowers:subagent-driven-development** (Tasks 1–3 mechanical → cheap/standard model; the page Task 4 is integration → standard). Two-stage review (spec → quality) per unit + a final whole-implementation review. Continuous execution. Finish with **superpowers:finishing-a-development-branch** (push + PR #13, base `web-dashboard-reports-settings`) **only with user consent**.
