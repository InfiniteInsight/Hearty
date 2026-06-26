# Journal Symptom Edit/Delete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users edit (symptom_type, severity, onset) and delete symptoms from the web Journal, wiring the existing-but-UI-less `patchSymptom`/`deleteSymptom` plumbing into `MealCard`, plus a small backend change so `symptom_type` is editable and `raw_description` isn't clobbered.

**Architecture:** A small backend change (symptom PATCH: description optional + symptom_type, conditional updates). A new `SymptomRow` web component (edit/delete, mirrors `MealCard`'s idiom) rendered in `MealCard`'s expanded panel. A shared `lib/symptoms.ts` (canonical `SYMPTOM_TYPES` + the `severityClass` helper, moved out of `MealCard` to avoid a circular import).

**Tech Stack:** FastAPI (Python), React 19 + TanStack Query v5 + Vitest/RTL/MSW.

**Spec:** `docs/superpowers/specs/2026-06-26-journal-symptom-edit-design.md`

**Worktree:** `~/.config/superpowers/worktrees/journal-symptom-edit` (branch `journal-symptom-edit`, off master). Backend tests (no local venv): from `hearty-api/`, `set -a; source /home/evan/projects/food-journal-assistant/.env; set +a` then `/home/evan/projects/food-journal-assistant/hearty-api/.venv/bin/python -m pytest <paths> -q`. Web: `cd hearty-web && npm install` (fresh worktree) then `npm run test -- --run`.

**Key existing code (verified on master):**
- Backend `SymptomUpdateRequest` is in `hearty-api/app/routers/symptoms.py` (lines ~88-91): `{description: str, severity: Optional[int], onset_minutes: Optional[int]}`. `update_symptom` (~94-122) always does `updates = {"raw_description": body.description}` then conditionally adds severity/onset, then `.update(updates)`.
- `SymptomResponse` (schemas.py + web `types/api.ts`) has NO description field: `{id, meal_id?, symptom_type, severity?, onset_minutes?, duration_minutes?, bathroom_*?, stool_consistency?, notes?, logged_at}`.
- Web `MealCard.tsx` exports `severityClass(sev?)` (with an eslint-disable for react-refresh) and renders symptom **chips** (read-only). `api.patchSymptom`/`deleteSymptom` exist (`lib/api.ts` ~70-72). `MealCard.test.tsx` queries the meal buttons with anchored regexes `/^edit$/i`, `/^delete$/i`, `/confirm delete/i`.

---

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `hearty-api/app/routers/symptoms.py` | symptom PATCH: description optional + symptom_type (modify) | 1 |
| `hearty-api/tests/test_symptom_update_unit.py` | unit test for the PATCH (create) | 1 |
| `hearty-web/src/lib/symptoms.ts` | canonical `SYMPTOM_TYPES` + `severityClass` (create) | 2 |
| `hearty-web/src/pages/Journal.tsx` | use shared `SYMPTOM_TYPES` (modify) | 2 |
| `hearty-web/src/components/journal/MealCard.tsx` | import `severityClass` from lib (modify) | 2; render `SymptomRow` | 4 |
| `hearty-web/src/types/api.ts` | `SymptomUpdateRequest` (modify) | 2 |
| `hearty-web/src/components/journal/SymptomRow.tsx` | edit/delete a symptom (create) | 3 |
| `hearty-web/src/components/journal/SymptomRow.test.tsx` | SymptomRow tests (create) | 3 |
| `hearty-web/src/components/journal/MealCard.test.tsx` | expanded-panel symptom test (modify) | 4 |
| live deploy | redeploy backend + web, verify | 5 |

---

### Task 1: Backend — editable `symptom_type`, no `raw_description` clobber

**Files:**
- Modify: `hearty-api/app/routers/symptoms.py` (`SymptomUpdateRequest` ~88-91; `update_symptom` ~94-122)
- Test: `hearty-api/tests/test_symptom_update_unit.py`

- [ ] **Step 1: Write the failing test**

```python
import types
from uuid import uuid4
from fastapi.testclient import TestClient
from app.main import app
from app.auth import get_current_user
from app.routers import symptoms as sym


class _Q:
    def __init__(self, store):
        self.store = store; self._op = None; self._payload = None
    def select(self, *a, **k): self._op = "select"; return self
    def update(self, payload): self._op = "update"; self._payload = payload; return self
    def eq(self, *a, **k): return self
    def execute(self):
        if self._op == "update":
            self.store["update_payload"] = self._payload
            row = {"id": self.store["sid"], "symptom_type": self._payload.get("symptom_type", "bloating"),
                   "severity": self._payload.get("severity"), "onset_minutes": self._payload.get("onset_minutes"),
                   "logged_at": "2026-06-26T00:00:00Z"}
            return types.SimpleNamespace(data=[row])
        # select (ownership check)
        return types.SimpleNamespace(data=[{"id": self.store["sid"], "user_id": "u1"}])


class _Supa:
    def __init__(self, store): self.store = store
    def table(self, name): return _Q(self.store)


def _setup(monkeypatch):
    sid = str(uuid4())
    store = {"sid": sid}
    monkeypatch.setattr(sym, "supabase", _Supa(store))
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    return sid, store


def test_patch_sets_symptom_type_without_touching_description(monkeypatch):
    sid, store = _setup(monkeypatch)
    r = TestClient(app).patch(f"/api/symptoms/{sid}", json={"symptom_type": "nausea", "severity": 4})
    assert r.status_code == 200
    assert store["update_payload"]["symptom_type"] == "nausea"
    assert store["update_payload"]["severity"] == 4
    assert "raw_description" not in store["update_payload"]  # description omitted -> not clobbered
    app.dependency_overrides.clear()


def test_patch_with_description_updates_raw_description(monkeypatch):
    sid, store = _setup(monkeypatch)
    r = TestClient(app).patch(f"/api/symptoms/{sid}", json={"description": "less bloated"})
    assert r.status_code == 200
    assert store["update_payload"]["raw_description"] == "less bloated"
    app.dependency_overrides.clear()


def test_patch_requires_auth():
    from uuid import uuid4 as u
    assert TestClient(app).patch(f"/api/symptoms/{u()}", json={"severity": 1}).status_code in (401, 403)
```

- [ ] **Step 2: Run to verify it fails**

Run: `tests/test_symptom_update_unit.py -v`
Expected: FAIL — currently `description` is required, so `{"symptom_type": "nausea", ...}` → 422; and `symptom_type` isn't applied.

- [ ] **Step 3: Modify `SymptomUpdateRequest`**

In `symptoms.py`, change the model (currently `description: str` required):

```python
class SymptomUpdateRequest(BaseModel):
    description: Optional[str] = None
    symptom_type: Optional[str] = None
    severity: Optional[int] = None
    onset_minutes: Optional[int] = None
```

(`Optional` is already imported in this module — it's used by the model today.)

- [ ] **Step 4: Modify `update_symptom`'s update-building**

Replace the current updates block (which is `updates: dict = {"raw_description": body.description}` followed by the `if body.severity` / `if body.onset_minutes` adds and the `.update(updates)` call) with conditional building + an empty-guard:

```python
    updates: dict = {}
    if body.description is not None:
        updates["raw_description"] = body.description
    if body.symptom_type is not None:
        updates["symptom_type"] = body.symptom_type
    if body.severity is not None:
        updates["severity"] = body.severity
    if body.onset_minutes is not None:
        updates["onset_minutes"] = body.onset_minutes

    if not updates:
        # nothing to change — return the current row unmodified
        current = (
            supabase.table("symptoms").select("*").eq("id", str(symptom_id)).execute()
        )
        return SymptomResponse(**current.data[0])

    result = (
        supabase.table("symptoms")
        .update(updates)
        .eq("id", str(symptom_id))
        .execute()
    )
    return SymptomResponse(**result.data[0])
```

(Leave the ownership-check select + 404 above it unchanged.)

- [ ] **Step 5: Run to verify pass**

Run: `tests/test_symptom_update_unit.py -v` → 3 passed.

- [ ] **Step 6: Commit**

```bash
git add hearty-api/app/routers/symptoms.py hearty-api/tests/test_symptom_update_unit.py
git commit -m "feat(journal): symptom PATCH allows symptom_type, no longer clobbers raw_description"
```

---

### Task 2: Web — shared `symptoms.ts` (types list + severityClass) + type update

**Files:**
- Create: `hearty-web/src/lib/symptoms.ts`
- Modify: `hearty-web/src/pages/Journal.tsx` (use shared `SYMPTOM_TYPES`)
- Modify: `hearty-web/src/components/journal/MealCard.tsx` (import `severityClass` from lib)
- Modify: `hearty-web/src/types/api.ts` (`SymptomUpdateRequest`)

- [ ] **Step 1: Create the shared module**

`hearty-web/src/lib/symptoms.ts`:

```typescript
// Canonical symptom types (mirrors the backend extraction enum in ai_extraction.py).
export const SYMPTOM_TYPES = [
  "acid_reflux", "bloating", "gas", "nausea", "urgency", "loose_stool",
  "constipation", "stomach_pain", "cramping", "fatigue", "brain_fog", "headache",
  "skin_reaction", "heart_palpitations", "indigestion", "upset_stomach",
  "sour_stomach", "gut_rot", "other",
] as const;

// Tailwind classes for a severity badge (moved out of MealCard so SymptomRow can
// reuse it without importing MealCard — avoids a circular import).
export function severityClass(sev?: number): string {
  if (sev == null) return "bg-surface text-text-muted";
  if (sev <= 3) return "bg-brand/15 text-brand";
  if (sev <= 6) return "bg-warn/15 text-warn";
  return "bg-accent-red/15 text-accent-red";
}
```

- [ ] **Step 2: Refactor `Journal.tsx`** — remove the local `SYMPTOM_TYPES` const (the ~10-line array) and import the shared one. Change the import block at the top to add:

```typescript
import { SYMPTOM_TYPES } from "../lib/symptoms";
```

and delete the local `const SYMPTOM_TYPES = [ ... ];` block. (The JSX `{SYMPTOM_TYPES.map(...)}` usage stays.)

- [ ] **Step 3: Refactor `MealCard.tsx`** — remove its local `severityClass` definition (the `// eslint-disable-next-line react-refresh/only-export-components` line plus the `export function severityClass(...) {...}` block) and import it instead. Add to the import block:

```typescript
import { severityClass } from "../../lib/symptoms";
```

(The `severityClass(s.severity)` call site stays. Removing the local export also removes the need for the eslint-disable.)

- [ ] **Step 4: Update the TS request type** — in `hearty-web/src/types/api.ts`, change:

```typescript
export interface SymptomUpdateRequest { description?: string; symptom_type?: string; severity?: number; onset_minutes?: number }
```

(was `{ description: string; severity?: number; onset_minutes?: number }` — relax `description` to optional, add `symptom_type`.)

- [ ] **Step 5: Verify build + existing tests**

Run: `cd hearty-web && npm install && npm run build && npm run test -- --run MealCard Journal`
Expected: build clean; existing MealCard + Journal tests pass (severityClass still renders the same classes; SYMPTOM_TYPES dropdown still populated). The existing `api.test.ts` `patchSymptom` test still type-checks (description optional is a superset).

- [ ] **Step 6: Commit**

```bash
git add hearty-web/src/lib/symptoms.ts hearty-web/src/pages/Journal.tsx hearty-web/src/components/journal/MealCard.tsx hearty-web/src/types/api.ts
git commit -m "refactor(journal): shared SYMPTOM_TYPES + severityClass; SymptomUpdateRequest gains symptom_type"
```

---

### Task 3: Web — `SymptomRow` component + tests

**Files:**
- Create: `hearty-web/src/components/journal/SymptomRow.tsx`
- Test: `hearty-web/src/components/journal/SymptomRow.test.tsx`

- [ ] **Step 1: Write the failing test**

`hearty-web/src/components/journal/SymptomRow.test.tsx`:

```typescript
import { expect, test, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { http, HttpResponse } from "msw";
import { server } from "../../test/msw/server";
vi.mock("../../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } },
}));
import SymptomRow from "./SymptomRow";
import type { SymptomResponse } from "@/types/api";

const symptom: SymptomResponse = { id: "s1", symptom_type: "bloating", severity: 5, logged_at: "2026-06-26T09:00:00Z" };

function renderRow(s: SymptomResponse) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(<QueryClientProvider client={qc}><SymptomRow symptom={s} /></QueryClientProvider>);
}

test("renders the symptom badge", () => {
  renderRow(symptom);
  expect(screen.getByText(/bloating 5/)).toBeInTheDocument();
});

test("edits severity + type via PATCH", async () => {
  let body: unknown = null;
  server.use(http.patch("*/api/symptoms/s1", async ({ request }) => {
    body = await request.json();
    return HttpResponse.json({ id: "s1", symptom_type: "nausea", severity: 7, logged_at: "z" });
  }));
  renderRow(symptom);
  await userEvent.click(screen.getByRole("button", { name: /edit bloating/i }));
  await userEvent.selectOptions(screen.getByLabelText(/symptom type/i), "nausea");
  const sev = screen.getByLabelText(/severity/i);
  await userEvent.clear(sev);
  await userEvent.type(sev, "7");
  await userEvent.click(screen.getByRole("button", { name: /^save$/i }));
  await vi.waitFor(() => expect(body).toMatchObject({ symptom_type: "nausea", severity: 7 }));
});

test("delete requires a confirm then issues DELETE", async () => {
  let deleted = false;
  server.use(http.delete("*/api/symptoms/s1", () => { deleted = true; return new HttpResponse(null, { status: 204 }); }));
  renderRow(symptom);
  await userEvent.click(screen.getByRole("button", { name: /delete bloating/i }));
  expect(deleted).toBe(false);
  await userEvent.click(screen.getByRole("button", { name: /confirm delete bloating/i }));
  await vi.waitFor(() => expect(deleted).toBe(true));
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run SymptomRow`
Expected: FAIL — `Cannot find module './SymptomRow'`.

- [ ] **Step 3: Create the component**

`hearty-web/src/components/journal/SymptomRow.tsx`:

```tsx
import { useState } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { api } from "../../lib/api";
import { SYMPTOM_TYPES, severityClass } from "../../lib/symptoms";
import type { SymptomResponse } from "@/types/api";

export default function SymptomRow({ symptom }: { symptom: SymptomResponse }) {
  const qc = useQueryClient();
  const [editing, setEditing] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [busy, setBusy] = useState(false);
  const [err, setErr] = useState<string | null>(null);
  const [type, setType] = useState(symptom.symptom_type);
  const [severity, setSeverity] = useState(symptom.severity?.toString() ?? "");
  const [onset, setOnset] = useState(symptom.onset_minutes?.toString() ?? "");

  function invalidate() {
    for (const k of [["meals"], ["summary"], ["trends"]]) qc.invalidateQueries({ queryKey: k });
  }
  async function save() {
    if (busy) return;
    setBusy(true); setErr(null);
    try {
      await api.patchSymptom(symptom.id, {
        symptom_type: type,
        severity: severity === "" ? undefined : Number(severity),
        onset_minutes: onset === "" ? undefined : Number(onset),
      });
      invalidate();
      setEditing(false);
    } catch { setErr("Couldn't save."); } finally { setBusy(false); }
  }
  async function remove() {
    if (busy) return;
    setBusy(true); setErr(null);
    try { await api.deleteSymptom(symptom.id); invalidate(); }
    catch { setErr("Couldn't delete."); setBusy(false); }
  }

  function reset() {
    setEditing(false);
    setType(symptom.symptom_type);
    setSeverity(symptom.severity?.toString() ?? "");
    setOnset(symptom.onset_minutes?.toString() ?? "");
  }

  return (
    <div className="flex flex-col gap-1 py-1.5">
      {err && <p className="text-xs text-accent-red">{err}</p>}
      {!editing ? (
        <div className="flex items-center justify-between gap-3">
          <span className={`rounded-full px-2 py-0.5 text-xs ${severityClass(symptom.severity)}`}>
            {symptom.symptom_type}{symptom.severity != null ? ` ${symptom.severity}` : ""}
          </span>
          <div className="flex gap-2">
            <button aria-label={`Edit ${symptom.symptom_type}`} onClick={() => setEditing(true)}
              className="rounded-lg border border-surface-border px-2 py-1 text-xs">Edit</button>
            {!confirmDelete ? (
              <button aria-label={`Delete ${symptom.symptom_type}`} onClick={() => setConfirmDelete(true)}
                className="rounded-lg border border-surface-border px-2 py-1 text-xs text-accent-red">Delete</button>
            ) : (
              <>
                <button aria-label={`Confirm delete ${symptom.symptom_type}`} onClick={remove} disabled={busy}
                  className="rounded-lg bg-accent-red px-2 py-1 text-xs text-black disabled:opacity-40">Confirm delete</button>
                <button onClick={() => setConfirmDelete(false)}
                  className="rounded-lg border border-surface-border px-2 py-1 text-xs">Cancel</button>
              </>
            )}
          </div>
        </div>
      ) : (
        <div className="flex flex-col gap-2">
          <label className="flex flex-col gap-1 text-xs text-text-muted">
            Symptom type
            <select aria-label="Symptom type" value={type} onChange={(e) => setType(e.target.value)}
              className="rounded-lg border border-surface-border bg-surface px-2 py-1 text-sm">
              {SYMPTOM_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
            </select>
          </label>
          <label className="flex flex-col gap-1 text-xs text-text-muted">
            Severity (1–10)
            <input aria-label="Severity" type="number" min={1} max={10} value={severity}
              onChange={(e) => setSeverity(e.target.value)}
              className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
          </label>
          <label className="flex flex-col gap-1 text-xs text-text-muted">
            Onset (minutes)
            <input aria-label="Onset minutes" type="number" min={0} value={onset}
              onChange={(e) => setOnset(e.target.value)}
              className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
          </label>
          <div className="flex gap-2">
            <button onClick={save} disabled={busy} className="rounded-lg bg-brand px-2 py-1 text-xs text-black disabled:opacity-40">Save</button>
            <button onClick={reset} className="rounded-lg border border-surface-border px-2 py-1 text-xs">Cancel</button>
          </div>
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 4: Run to verify pass**

Run: `cd hearty-web && npm run test -- --run SymptomRow` → 3 passed.

- [ ] **Step 5: Commit**

```bash
git add hearty-web/src/components/journal/SymptomRow.tsx hearty-web/src/components/journal/SymptomRow.test.tsx
git commit -m "feat(journal): SymptomRow component (edit symptom_type/severity/onset + delete)"
```

---

### Task 4: Web — render `SymptomRow` in `MealCard`'s expanded panel

**Files:**
- Modify: `hearty-web/src/components/journal/MealCard.tsx` (import + render in `open` panel)
- Test: `hearty-web/src/components/journal/MealCard.test.tsx` (add a test)

- [ ] **Step 1: Add the failing test**

Append to `hearty-web/src/components/journal/MealCard.test.tsx`:

```typescript
test("expanded panel renders an editable SymptomRow", async () => {
  renderCard(<MealCard meal={meal} />);
  await userEvent.click(screen.getByRole("button", { name: /oatmeal with milk/i }));
  // the symptom's own edit control is distinct from the meal's "Edit"
  expect(screen.getByRole("button", { name: /edit bloating/i })).toBeInTheDocument();
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run MealCard`
Expected: the new test FAILS (`Unable to find ... edit bloating`); existing MealCard tests still pass.

- [ ] **Step 3: Import `SymptomRow`** in `MealCard.tsx`:

```typescript
import SymptomRow from "./SymptomRow";
```

- [ ] **Step 4: Render the Symptoms subsection** inside the `{open && ( ... )}` block, after the meal edit/delete controls (the block that ends with the editing `</div>` / `)}` near the bottom of the expanded panel) and before the closing `</div>` of the panel. Use the already-computed `symptoms` variable (filtered by `symptomTypeFilter`, matching the chips):

```tsx
          {symptoms.length > 0 && (
            <div className="mt-3 border-t border-surface-border pt-3">
              <p className="mb-1 text-xs text-text-muted">Symptoms</p>
              {symptoms.map((s) => <SymptomRow key={s.id} symptom={s} />)}
            </div>
          )}
```

> The symptom Edit/Delete buttons carry accessible names `Edit {type}` / `Delete {type}` (from Task 3), so they do NOT collide with the meal's own `Edit` / `Delete` buttons (the existing MealCard tests query those with anchored `/^edit$/i` and `/^delete$/i`, which still match only the meal buttons). This keeps the existing tests green.

- [ ] **Step 5: Run MealCard tests**

Run: `cd hearty-web && npm run test -- --run MealCard`
Expected: the new test passes AND all existing MealCard tests stay green (meal edit/delete button queries remain unambiguous).

- [ ] **Step 6: Full web suite + lint + build**

Run: `cd hearty-web && npm run test -- --run && npm run lint && npm run build`
Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add hearty-web/src/components/journal/MealCard.tsx hearty-web/src/components/journal/MealCard.test.tsx
git commit -m "feat(journal): edit/delete symptoms in MealCard's expanded panel"
```

---

### Task 5: Deploy + live verification (MANUAL — requires user consent)

> Live actions (Cloud Run redeploy + Vercel redeploy). No DB migration, no new env vars. Do NOT run without explicit go-ahead.

- [ ] **Step 1: Redeploy backend** (the symptom_type change) per `docs/DEPLOYMENT.md` — build `/tmp/hearty-env.yaml` from `.env` (full key list) and `gcloud run deploy hearty-api --source . ... --env-vars-file /tmp/hearty-env.yaml`; `shred -u` after.
- [ ] **Step 2: Redeploy web** — `cd hearty-web && npx vercel@latest deploy --prod --yes`.
- [ ] **Step 3: Verify** — on the Journal, expand a meal with a symptom → edit its type/severity → confirm it persists (reload) and the Dashboard/Trends reflect it; delete a symptom → confirm it disappears. Confirm editing a symptom does NOT blank its underlying raw text (a symptom you only changed severity on keeps its original description in the raw-data dump).
- [ ] **Step 4: Finish the branch** — superpowers:finishing-a-development-branch.

---

## Self-Review

**1. Spec coverage:**
- §1 Backend (description optional, symptom_type, conditional updates, no clobber) → Task 1 ✓
- §2 Shared SYMPTOM_TYPES + Journal refactor + TS type → Task 2 ✓
- §3 SymptomRow (read view + edit symptom_type/severity/onset + two-step delete + invalidation) → Task 3 ✓
- §4 MealCard integration (expanded panel, chips unchanged) → Task 4 ✓
- Error handling (per-row busy/err) → Task 3 ✓; Security (ownership unchanged) → Task 1 ✓
- Testing (backend unit, SymptomRow, MealCard integration) → Tasks 1/3/4 ✓; Live → Task 5 ✓
- Non-goal (standalone symptoms deferred) → honored (only `meal.symptoms` rendered) ✓

**2. Placeholder scan:** none — every code step shows complete code.

**3. Type/name consistency:** `severityClass`/`SYMPTOM_TYPES` defined in Task 2 (`lib/symptoms.ts`), imported by `SymptomRow` (Task 3) and `MealCard` (Task 2 import + Task 4 render). `SymptomUpdateRequest` shape (`{description?, symptom_type?, severity?, onset_minutes?}`) consistent between Task 2 (TS), Task 1 (backend pydantic), and Task 3 (`patchSymptom` call sends `{symptom_type, severity, onset_minutes}`). `SymptomResponse` fields used in `SymptomRow` (symptom_type, severity, onset_minutes, id) all exist. The circular-import risk (SymptomRow↔MealCard) is removed by housing `severityClass` in `lib/symptoms.ts`. The duplicate-button-name risk is removed by the `Edit {type}`/`Delete {type}` accessible names; existing MealCard tests use anchored `/^edit$/i`/`/^delete$/i` that stay unique to the meal buttons.
