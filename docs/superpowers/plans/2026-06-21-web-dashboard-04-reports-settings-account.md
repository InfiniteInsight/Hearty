# Web Dashboard — Plan 4: Reports + Settings + Delete-Account Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Reports page (CSV/JSON/PDF export + summary preview) and Settings page (notification/check-in/conversation preferences + account management incl. account deletion) to `hearty-web/`, and build the new destructive `DELETE /api/account` backend endpoint it depends on.

**Architecture:** Backend first — a new `app/routers/account.py` that cascade-deletes all user-scoped rows (children-first), removes the user's storage objects, and deletes the auth user via the service-role admin API (TDD pytest, mocked Supabase). Then the web side: blob-returning export methods on the API client + a DOM download helper; Reports composes export + summary preview; Settings loads the full `UserPreferences`, edits a subset (preserving the rest), and gates account deletion behind a typed confirmation. Aurora theme, Vitest + RTL + MSW; pytest for the backend.

**Tech Stack:** FastAPI + Supabase (Python) for the backend; React 18 + TS (`erasableSyntaxOnly` + `verbatimModuleSyntax`), TanStack Query v5, React Router v6, Tailwind v3 + shadcn/ui v2, Vitest + RTL + MSW v2.

---

## Branch / PR basing

This plan **stacks on the Plan 3 branch** (`web-dashboard-reports-settings` was branched from `web-dashboard-conversation-experiments`). PRs #9 (Plan 1), #10 (Plan 2), #11 (Plan 3) are all open and unmerged. When finishing, open PR #12 with **base = `web-dashboard-conversation-experiments`**. This is now a 4-deep stack (`master` ← foundation ← journal-trends ← conversation-experiments ← reports-settings). As lower PRs merge to `master`, rebase the remaining stack and retarget the open PR's base.

---

## Verified backend contracts (re-validated 2026-06-21 against `hearty-api/app/routers/` + `supabase/migrations/`)

| Endpoint | Request | Response | Notes |
|---|---|---|---|
| `GET /api/export/json` | `?start_date&end_date` (optional) | `application/json` object | Full export object; download as a file |
| `GET /api/export/csv` | `?start_date&end_date` (optional) | `text/csv` stream, `Content-Disposition: attachment; filename=hearty-export.csv` | |
| `POST /api/export/pdf` | `{start_date?, end_date?}` (ISO datetimes) | `application/pdf` **bytes**, `filename=hearty-report.pdf` | NOT a signed URL — raw bytes → blob download. May take a moment. |
| `GET /api/summary` | `?period=custom&start_date&end_date` | `SummaryResponse` | `period=custom` **requires** both dates (else 422). Reuses Plan 1's `getSummary`. |
| `GET /api/preferences` | — | `UserPreferencesSchema` | merges health_profile + notification_preferences rows |
| `PUT /api/preferences` | full `UserPreferencesSchema` | `UserPreferencesSchema` | **Full replace** — must send the entire object (preserve fields the UI doesn't edit) |
| `DELETE /api/account` | — | **204** | **Does not exist yet — built in Task 1.** |

**`UserPreferencesSchema`** (verbatim field set from `preferences.py:14-49`):
`allergens:string[]`, `conditions:string[]`, `dietary_protocols:string[]`, `medications:string[]`, `nudge_delay_minutes:number`, `post_meal_nudge_enabled:boolean`, `daily_checkin_enabled:boolean`, `trends_conversation_enabled:boolean`, `weekly_digest_enabled:boolean`, `sync_error_alerts_enabled:boolean`, `wake_word_enabled:boolean`, `daily_checkin_hour:number`, `daily_checkin_minute:number`, `fcm_token:string|null`, `morning_checkin_enabled:boolean`, `morning_checkin_hour:number`, `morning_checkin_minute:number`, `midday_checkin_enabled:boolean`, `midday_checkin_hour:number`, `midday_checkin_minute:number`, `evening_checkin_enabled:boolean`, `evening_checkin_hour:number`, `evening_checkin_minute:number`, `conversation_style:'warm'|'concise'`, `use_cloud_when_online:boolean`, `auto_submit:boolean`, `auto_submit_silence_seconds:number`, `use_on_device_model:'parakeetCtc110m'|'parakeet'`.

**User-scoped tables (verified to have `user_id` in `supabase/migrations/`)** — the delete cascade targets exactly these 12, **children before parents**:
`symptoms`, `food_log_photos`, `food_triggers`, `food_signals`, `food_signals_yearly`, `signal_feedback`, `experiments`, `wellbeing_snapshots`, `meals`, `health_profile`, `notification_preferences`, `offline_queue`.
**Explicitly excluded** (not user-scoped): `food_cache` (shared nutrition cache, no `user_id`), `waitlist` (email signups, no `user_id`).
**Storage:** food photos live in bucket **`food-photos`** (private); each `food_log_photos` row has a `storage_path`. The service-key client exposes `supabase.auth.admin.delete_user(user_id)` and `supabase.storage.from_("food-photos").remove([...])`.

---

## Deviations / scope decisions (recorded here)

- **D1 — `symptom_type`-style health editing stays in Plan 5.** Settings' `UserPreferences` carries health string-lists (`allergens`/`conditions`/`dietary_protocols`/`medications`); Settings **does not edit** these (Profile, Plan 5, owns structured health data) — it passes them through unchanged on PUT so a partial save never wipes them.
- **D2 — Voice/dictation prefs are not shown.** They only affect the phone (per spec §5.8). Settings passes them through unchanged on PUT.
- **D3 — JSON/CSV/PDF download via blob, no signed URLs.** All three are fetched as blobs (PDF is raw bytes by contract) and saved client-side. The "Export all data" action in Settings reuses `exportJson` with no date range.
- **D4 — Account-delete cascade is an explicit table list, children-first**, derived by inspecting the schema (not blind). `food_cache`/`waitlist` excluded. Storage cleanup is best-effort (never blocks row/auth deletion).
- **No calories anywhere.**

---

## Existing conventions to honor (carry into every subagent dispatch)

- **Web TS:** `erasableSyntaxOnly` + `verbatimModuleSyntax` — no parameter-properties/enums; `import type` for type-only imports.
- **Tailwind tokens:** `brand`, `surface`, `surface-border`, `accent-violet`, `accent-red`, `warn`, `good`, `text`, `text-muted`, `text-faint`; `.font-mono-data`, `font-display`.
- **Web tests:** Vitest + RTL + MSW; `onUnhandledRequest:"error"` — every fetch needs a handler. `renderWithProviders(ui,{route})` (QueryClient + MemoryRouter). Tests importing `lib/api` or components using it must `vi.mock("../lib/supabase", ...)` (or correct depth) with `auth.getSession`. `vi.mock` factories hoisted. `URL.createObjectURL` is NOT implemented in jsdom — the DOM download helper must be mocked in page tests, not exercised.
- **Backend tests:** pytest with `from fastapi.testclient import TestClient`, `app.dependency_overrides[get_current_user] = lambda: {"id":"u1","email":"e"}`, and `monkeypatch.setattr(<router_module>, "supabase", fake)`. Clear overrides at test end. **Run them with the project venv + dummy env (verified working):**
  ```
  cd hearty-api && SUPABASE_URL="http://localhost" SUPABASE_SERVICE_KEY="dummy-key" ./.venv/bin/python -m pytest <path> -q
  ```
  (Module-level `create_client(os.environ["SUPABASE_URL"], …)` runs at import across all routers, so both env vars must be set even though unit tests monkeypatch the client. `get_current_user` uses `HTTPBearer()` with `auto_error=True`, so a missing `Authorization` header is rejected with **403** at the dependency layer before any Supabase call — the auth-required test asserts `in (401, 403)`.)
- **`ApiError`** (from `lib/api.ts`) carries `.status`. **shadcn** pinned to v2. **No calories ever.**
- **Commits:** conventional messages + co-author trailer `Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Push/PR only with explicit user consent.

---

## File structure

**Create (backend):**
- `hearty-api/app/routers/account.py` — `DELETE /api/account`
- `hearty-api/tests/test_account_endpoint_unit.py`

**Create (web):**
- `src/lib/download.ts` — `saveBlob(blob, filename)` DOM helper
- `src/hooks/usePreferences.ts` — preferences query + save mutation
- `src/pages/Reports.tsx`, `src/pages/Settings.tsx`
- Test files alongside.

**Modify:**
- `hearty-api/app/main.py` — register the account router (Task 1)
- `src/types/api.ts` — `UserPreferences` type (Task 2)
- `src/lib/api.ts` + `src/lib/api.test.ts` — `exportCsv`/`exportJson`/`exportPdf` (blob) + `getPreferences`/`putPreferences`/`deleteAccount` (Task 2)
- `src/App.tsx` — wire `/reports` and `/settings` routes (Tasks 3, 5)

---

## PHASE A — Backend: `DELETE /api/account`

### Task 1: Account-deletion endpoint (Python, TDD)

**Files:**
- Create: `hearty-api/app/routers/account.py`, `hearty-api/tests/test_account_endpoint_unit.py`
- Modify: `hearty-api/app/main.py`

- [ ] **Step 1: Write the failing pytest**

Create `hearty-api/tests/test_account_endpoint_unit.py`:

```python
from fastapi.testclient import TestClient
from app.main import app
from app.auth import get_current_user
from app.routers import account as acct


class _Q:
    """Records delete calls; returns empty data for selects."""
    def __init__(self, log, table):
        self.log = log
        self.table = table
        self._op = None
        self._eq = (None, None)

    def select(self, *a, **k):
        self._op = "select"
        return self

    def delete(self):
        self._op = "delete"
        return self

    def eq(self, col, val):
        self._eq = (col, val)
        return self

    def execute(self):
        if self._op == "delete":
            self.log.append(("delete", self.table, self._eq[1]))
        return type("R", (), {"data": []})()


class _Storage:
    def __init__(self, log): self.log = log
    def from_(self, bucket): self.log.append(("storage_from", bucket)); return self
    def remove(self, paths): self.log.append(("storage_remove", tuple(paths)))


class _Admin:
    def __init__(self, log): self.log = log
    def delete_user(self, uid): self.log.append(("admin_delete_user", uid))


class _Auth:
    def __init__(self, log): self.admin = _Admin(log)


class _FakeSupabase:
    def __init__(self):
        self.log = []
        self.storage = _Storage(self.log)
        self.auth = _Auth(self.log)

    def table(self, name): return _Q(self.log, name)


def test_delete_account_cascades_and_deletes_auth_user(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    fake = _FakeSupabase()
    monkeypatch.setattr(acct, "supabase", fake)
    client = TestClient(app)
    r = client.delete("/api/account")
    assert r.status_code == 204
    deleted = [t for (op, t, uid) in fake.log if op == "delete"]
    for tbl in acct.USER_TABLES:
        assert tbl in deleted, f"missing delete for {tbl}"
    assert all(uid == "u1" for (op, t, uid) in fake.log if op == "delete")
    assert ("admin_delete_user", "u1") in fake.log
    assert "food_cache" not in deleted and "waitlist" not in deleted
    app.dependency_overrides.clear()


def test_delete_account_children_before_auth_user(monkeypatch):
    app.dependency_overrides[get_current_user] = lambda: {"id": "u1", "email": "e"}
    fake = _FakeSupabase()
    monkeypatch.setattr(acct, "supabase", fake)
    client = TestClient(app)
    client.delete("/api/account")
    ops = [op for (op, *_rest) in fake.log]
    last_delete = max(i for i, op in enumerate(ops) if op == "delete")
    admin_idx = ops.index("admin_delete_user")
    assert last_delete < admin_idx
    order = [t for (op, t, uid) in fake.log if op == "delete"]
    assert order.index("symptoms") < order.index("meals")  # child before parent
    app.dependency_overrides.clear()


def test_delete_account_requires_auth():
    client = TestClient(app)
    r = client.delete("/api/account")
    assert r.status_code in (401, 403)
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-api && SUPABASE_URL="http://localhost" SUPABASE_SERVICE_KEY="dummy-key" ./.venv/bin/python -m pytest tests/test_account_endpoint_unit.py -q`
Expected: FAIL — `app.routers.account` does not exist (ImportError).

- [ ] **Step 3: Implement the router**

Create `hearty-api/app/routers/account.py`:

```python
import logging
import os

from fastapi import APIRouter, Depends
from supabase import create_client

from app.auth import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter()
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])

PHOTO_BUCKET = os.environ.get("PHOTO_BUCKET", "food-photos")

# Children before parents (symptoms + food_log_photos reference meals; meals last).
# food_cache and waitlist are intentionally excluded — they are not user-scoped.
USER_TABLES = [
    "symptoms",
    "food_log_photos",
    "food_triggers",
    "food_signals",
    "food_signals_yearly",
    "signal_feedback",
    "experiments",
    "wellbeing_snapshots",
    "meals",
    "health_profile",
    "notification_preferences",
    "offline_queue",
]


@router.delete("/api/account", status_code=204)
async def delete_account(user=Depends(get_current_user)):
    """Permanently delete the authenticated user's data and auth account.

    Order matters: child rows first, then parent rows, then the auth user.
    Storage cleanup is best-effort and must never block row/auth deletion.
    """
    user_id = user["id"]

    # 1. Best-effort removal of the user's photo objects from Storage.
    try:
        photos = (
            supabase.table("food_log_photos")
            .select("storage_path")
            .eq("user_id", user_id)
            .execute()
        ).data or []
        paths = [p["storage_path"] for p in photos if p.get("storage_path")]
        if paths:
            supabase.storage.from_(PHOTO_BUCKET).remove(paths)
    except Exception as e:  # pragma: no cover - defensive
        logger.error("account photo storage cleanup failed: %s", e, exc_info=True)

    # 2. Delete all user-scoped rows (children first).
    for table in USER_TABLES:
        supabase.table(table).delete().eq("user_id", user_id).execute()

    # 3. Delete the auth user (admin API, service-role key).
    supabase.auth.admin.delete_user(user_id)
```

- [ ] **Step 4: Register the router in `app/main.py`**

Add `account` to the routers import line (`from app.routers import auth_hooks, chat, meals, symptoms, trends, export, photos, preferences, transcribe, checkin, experiments, food, account`) and add `app.include_router(account.router)` alongside the other `include_router` calls.

- [ ] **Step 5: Run to verify it passes**

Run: `cd hearty-api && SUPABASE_URL="http://localhost" SUPABASE_SERVICE_KEY="dummy-key" ./.venv/bin/python -m pytest tests/test_account_endpoint_unit.py -q`
Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
git add hearty-api/app/routers/account.py hearty-api/tests/test_account_endpoint_unit.py hearty-api/app/main.py
git commit -m "feat(api): DELETE /api/account — cascade user data + storage + auth user"
```

---

## PHASE B — Web plumbing

### Task 2: Export (blob) + preferences + delete-account API methods, types, download helper

**Files:**
- Modify: `src/types/api.ts`, `src/lib/api.ts`, `src/lib/api.test.ts`
- Create: `src/lib/download.ts`, `src/lib/download.test.ts`

- [ ] **Step 1: Add failing API client tests**

Append to `src/lib/api.test.ts`:

```ts
test("exportCsv fetches a blob and parses the filename", async () => {
  server.use(
    http.get("http://api.test/api/export/csv", () =>
      new HttpResponse("a,b\n1,2\n", { status: 200, headers: { "Content-Type": "text/csv", "Content-Disposition": "attachment; filename=hearty-export.csv" } })
    )
  );
  const { createApiClient } = await import("./api");
  const { blob, filename } = await createApiClient("http://api.test").exportCsv({});
  expect(filename).toBe("hearty-export.csv");
  expect(await blob.text()).toContain("a,b");
});

test("exportPdf posts the date range and returns a blob", async () => {
  let body: unknown = null;
  server.use(
    http.post("http://api.test/api/export/pdf", async ({ request }) => {
      body = await request.json();
      return new HttpResponse("%PDF-1.4", { status: 200, headers: { "Content-Type": "application/pdf", "Content-Disposition": "attachment; filename=hearty-report.pdf" } });
    })
  );
  const { createApiClient } = await import("./api");
  const { filename } = await createApiClient("http://api.test").exportPdf({ start_date: "2026-06-01", end_date: "2026-06-15" });
  expect(body).toEqual({ start_date: "2026-06-01", end_date: "2026-06-15" });
  expect(filename).toBe("hearty-report.pdf");
});

test("getPreferences / putPreferences round-trip the schema", async () => {
  let put: unknown = null;
  const prefs = { conversation_style: "warm", daily_checkin_enabled: true };
  server.use(
    http.get("http://api.test/api/preferences", () => HttpResponse.json(prefs)),
    http.put("http://api.test/api/preferences", async ({ request }) => { put = await request.json(); return HttpResponse.json(prefs); }),
  );
  const { createApiClient } = await import("./api");
  const api = createApiClient("http://api.test");
  const got = await api.getPreferences();
  expect(got.conversation_style).toBe("warm");
  await api.putPreferences(got);
  expect(put).toMatchObject({ conversation_style: "warm" });
});

test("deleteAccount issues DELETE and tolerates 204", async () => {
  server.use(http.delete("http://api.test/api/account", () => new HttpResponse(null, { status: 204 })));
  const { createApiClient } = await import("./api");
  await expect(createApiClient("http://api.test").deleteAccount()).resolves.toBeUndefined();
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run src/lib/api.test.ts`
Expected: FAIL — the new methods don't exist.

- [ ] **Step 3: Add the `UserPreferences` type to `src/types/api.ts`**

Append:

```ts
export interface UserPreferences {
  allergens: string[];
  conditions: string[];
  dietary_protocols: string[];
  medications: string[];
  nudge_delay_minutes: number;
  post_meal_nudge_enabled: boolean;
  daily_checkin_enabled: boolean;
  trends_conversation_enabled: boolean;
  weekly_digest_enabled: boolean;
  sync_error_alerts_enabled: boolean;
  wake_word_enabled: boolean;
  daily_checkin_hour: number;
  daily_checkin_minute: number;
  fcm_token: string | null;
  morning_checkin_enabled: boolean;
  morning_checkin_hour: number;
  morning_checkin_minute: number;
  midday_checkin_enabled: boolean;
  midday_checkin_hour: number;
  midday_checkin_minute: number;
  evening_checkin_enabled: boolean;
  evening_checkin_hour: number;
  evening_checkin_minute: number;
  conversation_style: "warm" | "concise";
  use_cloud_when_online: boolean;
  auto_submit: boolean;
  auto_submit_silence_seconds: number;
  use_on_device_model: "parakeetCtc110m" | "parakeet";
}
export interface ExportDateRange { start_date?: string; end_date?: string }
export interface BlobDownload { blob: Blob; filename: string }
```

- [ ] **Step 4: Add the client methods to `src/lib/api.ts`**

Extend the import block to include `UserPreferences, ExportDateRange, BlobDownload`.

Inside `createApiClient`, add a blob helper next to `request` (before the `return {`):

```ts
  async function requestBlob(path: string, init: RequestInit = {}): Promise<BlobDownload> {
    const headers: Record<string, string> = { ...(await authHeader()) };
    if (init.method && init.method !== "GET") headers["Content-Type"] = "application/json";
    const res = await fetch(`${baseUrl}${path}`, { ...init, headers });
    if (!res.ok) throw new ApiError(res.status, `${res.status} ${res.statusText}`);
    const blob = await res.blob();
    const cd = res.headers.get("Content-Disposition") ?? "";
    const match = /filename="?([^";]+)"?/.exec(cd);
    return { blob, filename: match?.[1] ?? "download" };
  }
```

Add these methods to the returned object:

```ts
    exportCsv: (p: ExportDateRange = {}) => requestBlob(`/api/export/csv${qs(p)}`),
    exportJson: (p: ExportDateRange = {}) => requestBlob(`/api/export/json${qs(p)}`),
    exportPdf: (body: ExportDateRange) => requestBlob(`/api/export/pdf`, { method: "POST", body: JSON.stringify(body) }),
    getPreferences: () => request<UserPreferences>(`/api/preferences`),
    putPreferences: (body: UserPreferences) => request<UserPreferences>(`/api/preferences`, { method: "PUT", body: JSON.stringify(body) }),
    deleteAccount: () => request<void>(`/api/account`, { method: "DELETE" }),
```

- [ ] **Step 5: Write the download-helper test + implementation**

Create `src/lib/download.test.ts`:

```ts
import { afterEach, expect, test, vi } from "vitest";
import { saveBlob } from "./download";

afterEach(() => vi.restoreAllMocks());

test("saveBlob creates an object URL, clicks an anchor, and revokes", () => {
  const create = vi.fn(() => "blob:fake");
  const revoke = vi.fn();
  // jsdom doesn't implement these — stub them.
  vi.stubGlobal("URL", { ...URL, createObjectURL: create, revokeObjectURL: revoke });
  const click = vi.spyOn(HTMLAnchorElement.prototype, "click").mockImplementation(() => {});
  saveBlob(new Blob(["x"]), "f.csv");
  expect(create).toHaveBeenCalled();
  expect(click).toHaveBeenCalled();
  expect(revoke).toHaveBeenCalledWith("blob:fake");
});
```

Create `src/lib/download.ts`:

```ts
// Trigger a browser download for a blob. Not used in SSR; DOM-only.
export function saveBlob(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}
```

- [ ] **Step 6: Run tests + build + lint**

Run: `cd hearty-web && npm run test -- --run src/lib/api.test.ts src/lib/download.test.ts && npm run build && npm run lint`
Expected: PASS; type-clean; 0 lint problems.

- [ ] **Step 7: Commit**

```bash
git add src/types/api.ts src/lib/api.ts src/lib/api.test.ts src/lib/download.ts src/lib/download.test.ts
git commit -m "feat(web): export blob methods, preferences + deleteAccount API, saveBlob helper"
```

---

## PHASE C — Reports

### Task 3: `Reports` page + route

**Files:**
- Create: `src/pages/Reports.tsx`, `src/pages/Reports.test.tsx`
- Modify: `src/App.tsx`

Date-range pickers → a **preview** (`getSummary` with `period=custom`, only when both dates set) + three export buttons (CSV / JSON / PDF). Each export fetches the blob via the API client and hands it to `saveBlob`; per-action busy + error state. Empty date range → exports send no dates (full history).

- [ ] **Step 1: Write the failing test**

Create `src/pages/Reports.test.tsx`:

```tsx
import { expect, test, vi } from "vitest";
import { fireEvent, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
import { renderWithProviders } from "../test/utils";
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } },
}));
const saveBlob = vi.fn();
vi.mock("../lib/download", () => ({ saveBlob: (...a: unknown[]) => saveBlob(...a) }));
import Reports from "./Reports";

test("CSV export fetches a blob and saves it", async () => {
  server.use(
    http.get("*/api/export/csv", () => new HttpResponse("a,b\n", { headers: { "Content-Type": "text/csv", "Content-Disposition": "attachment; filename=hearty-export.csv" } })),
  );
  renderWithProviders(<Reports />, { route: "/reports" });
  await userEvent.click(screen.getByRole("button", { name: /csv/i }));
  await vi.waitFor(() => expect(saveBlob).toHaveBeenCalledWith(expect.any(Blob), "hearty-export.csv"));
});

test("preview loads a summary when both dates are set", async () => {
  server.use(
    http.get("*/api/summary", () => HttpResponse.json({ period: "custom", start_date: "x", end_date: "y", summary_text: "Steady fortnight.", meals_logged: 12, top_symptoms: [] })),
  );
  renderWithProviders(<Reports />, { route: "/reports" });
  // <input type="date"> doesn't accept userEvent.type reliably in jsdom — set value directly.
  fireEvent.change(screen.getByLabelText(/from/i), { target: { value: "2026-06-01" } });
  fireEvent.change(screen.getByLabelText(/to/i), { target: { value: "2026-06-15" } });
  await userEvent.click(screen.getByRole("button", { name: /preview/i }));
  expect(await screen.findByText("Steady fortnight.")).toBeInTheDocument();
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run src/pages/Reports.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the page**

Create `src/pages/Reports.tsx`:

```tsx
import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { api } from "../lib/api";
import { saveBlob } from "../lib/download";
import type { ExportDateRange } from "@/types/api";

export default function Reports() {
  const [start, setStart] = useState("");
  const [end, setEnd] = useState("");
  const [range, setRange] = useState<{ start_date: string; end_date: string } | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const [err, setErr] = useState<string | null>(null);

  const params: ExportDateRange = {};
  if (start) params.start_date = start;
  if (end) params.end_date = end;

  const preview = useQuery({
    queryKey: ["summary", { period: "custom", ...range }],
    queryFn: () => api.getSummary({ period: "custom", start_date: range!.start_date, end_date: range!.end_date }),
    enabled: range != null,
  });

  async function download(kind: "csv" | "json" | "pdf") {
    setBusy(kind);
    setErr(null);
    try {
      const dl = kind === "pdf" ? await api.exportPdf(params) : kind === "csv" ? await api.exportCsv(params) : await api.exportJson(params);
      saveBlob(dl.blob, dl.filename);
    } catch {
      setErr(`Couldn't export ${kind.toUpperCase()}. Try again.`);
    } finally {
      setBusy(null);
    }
  }

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-6">
      <h1 className="font-display text-3xl">Reports</h1>

      <div className="rounded-2xl border border-surface-border bg-surface p-4">
        <div className="flex flex-wrap gap-3">
          <label className="flex flex-col gap-1 text-xs text-text-muted">
            From
            <input type="date" value={start} onChange={(e) => setStart(e.target.value)} className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
          </label>
          <label className="flex flex-col gap-1 text-xs text-text-muted">
            To
            <input type="date" value={end} onChange={(e) => setEnd(e.target.value)} className="rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
          </label>
          <button
            onClick={() => start && end && setRange({ start_date: start, end_date: end })}
            disabled={!start || !end}
            className="self-end rounded-lg border border-surface-border px-3 py-1 text-sm disabled:opacity-40"
          >
            Preview
          </button>
        </div>
        <p className="mt-2 font-mono-data text-xs text-text-faint">Leave dates empty to export your full history.</p>
      </div>

      {range && (
        <div className="rounded-2xl border border-surface-border bg-surface p-4">
          {preview.isPending && <p className="text-text-faint">Loading preview…</p>}
          {preview.isError && <p className="text-sm text-accent-red">Couldn't load the preview.</p>}
          {preview.isSuccess && (
            <>
              <div className="font-mono-data text-xs text-text-faint">{preview.data.meals_logged} meals logged</div>
              <p className="mt-1 text-text-muted">{preview.data.summary_text}</p>
            </>
          )}
        </div>
      )}

      <div className="flex flex-wrap gap-2">
        <button onClick={() => download("csv")} disabled={busy != null} className="rounded-lg bg-brand px-3 py-2 text-sm text-black disabled:opacity-50">{busy === "csv" ? "Exporting…" : "Export CSV"}</button>
        <button onClick={() => download("json")} disabled={busy != null} className="rounded-lg border border-surface-border px-3 py-2 text-sm disabled:opacity-50">{busy === "json" ? "Exporting…" : "Export JSON"}</button>
        <button onClick={() => download("pdf")} disabled={busy != null} className="rounded-lg border border-surface-border px-3 py-2 text-sm disabled:opacity-50">{busy === "pdf" ? "Generating…" : "Export PDF"}</button>
      </div>
      {err && <p className="text-sm text-accent-red">{err}</p>}
    </div>
  );
}
```

- [ ] **Step 4: Wire the route in `src/App.tsx`**

Add `import Reports from "./pages/Reports";` and replace `<Route path="/reports" element={<ComingSoon />} />` with `<Route path="/reports" element={<Reports />} />`.

- [ ] **Step 5: Run tests + build + lint**

Run: `cd hearty-web && npm run test -- --run src/pages/Reports.test.tsx && npm run build && npm run lint`
Expected: PASS; type-clean; 0 lint.

- [ ] **Step 6: Commit**

```bash
git add src/pages/Reports.tsx src/pages/Reports.test.tsx src/App.tsx
git commit -m "feat(web): Reports page — date range preview + CSV/JSON/PDF export; wire /reports route"
```

---

## PHASE D — Settings

### Task 4: `usePreferences` hook

**Files:**
- Create: `src/hooks/usePreferences.ts`, `src/hooks/usePreferences.test.tsx`

- [ ] **Step 1: Write the failing test**

Create `src/hooks/usePreferences.test.tsx`:

```tsx
import { expect, test, vi } from "vitest";
import { renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } },
}));
import { usePreferences, useSavePreferences } from "./usePreferences";

function wrap() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={qc}>{children}</QueryClientProvider>
  );
}

test("usePreferences loads prefs", async () => {
  server.use(http.get("*/api/preferences", () => HttpResponse.json({ conversation_style: "warm", daily_checkin_enabled: true })));
  const { result } = renderHook(() => usePreferences(), { wrapper: wrap() });
  await waitFor(() => expect(result.current.data?.conversation_style).toBe("warm"));
});

test("useSavePreferences PUTs and resolves", async () => {
  server.use(http.put("*/api/preferences", () => HttpResponse.json({ conversation_style: "concise" })));
  const { result } = renderHook(() => useSavePreferences(), { wrapper: wrap() });
  // minimal partial cast is fine for the test
  await result.current.mutateAsync({ conversation_style: "concise" } as never);
  await waitFor(() => expect(result.current.isSuccess).toBe(true));
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run src/hooks/usePreferences.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the hook**

Create `src/hooks/usePreferences.ts`:

```ts
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { api } from "../lib/api";
import type { UserPreferences } from "@/types/api";

export function usePreferences() {
  return useQuery({ queryKey: ["preferences"], queryFn: () => api.getPreferences(), staleTime: 300_000 });
}

export function useSavePreferences() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: (body: UserPreferences) => api.putPreferences(body),
    onSuccess: (data) => qc.setQueryData(["preferences"], data),
  });
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `cd hearty-web && npm run test -- --run src/hooks/usePreferences.test.tsx`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/hooks/usePreferences.ts src/hooks/usePreferences.test.tsx
git commit -m "feat(web): usePreferences — load + save preferences (cache write-through)"
```

---

### Task 5: `Settings` page + route

**Files:**
- Create: `src/pages/Settings.tsx`, `src/pages/Settings.test.tsx`
- Modify: `src/App.tsx`

Loads the full prefs, edits a subset (notification/check-in/conversation), **preserves the rest** (health + voice fields) on save by spreading the loaded object. Account section: authenticated email (from `getSession`), Sign out (`signOut` → `/login`), Export all data (`exportJson({})` → `saveBlob`), and **Delete account** behind a typed-confirmation modal (input must equal `delete my account`) → `deleteAccount()` → `signOut()` → `/login`.

- [ ] **Step 1: Write the failing test**

Create `src/pages/Settings.test.tsx`:

```tsx
import { expect, test, vi } from "vitest";
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
import { renderWithProviders } from "../test/utils";

vi.mock("../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t", user: { email: "me@example.com" } } } }) } },
}));
const signOut = vi.fn().mockResolvedValue(undefined);
vi.mock("../lib/auth", () => ({ signOut: () => signOut() }));
vi.mock("../lib/download", () => ({ saveBlob: vi.fn() }));
import Settings from "./Settings";

const prefs = {
  allergens: ["peanut"], conditions: [], dietary_protocols: [], medications: [],
  nudge_delay_minutes: 45, post_meal_nudge_enabled: true, daily_checkin_enabled: true,
  trends_conversation_enabled: true, weekly_digest_enabled: true, sync_error_alerts_enabled: true,
  wake_word_enabled: true, daily_checkin_hour: 8, daily_checkin_minute: 0, fcm_token: null,
  morning_checkin_enabled: true, morning_checkin_hour: 8, morning_checkin_minute: 0,
  midday_checkin_enabled: true, midday_checkin_hour: 13, midday_checkin_minute: 0,
  evening_checkin_enabled: true, evening_checkin_hour: 20, evening_checkin_minute: 0,
  conversation_style: "warm", use_cloud_when_online: false, auto_submit: true,
  auto_submit_silence_seconds: 2.5, use_on_device_model: "parakeetCtc110m",
};

test("saving preferences preserves untouched fields (allergens)", async () => {
  let put: Record<string, unknown> | null = null;
  server.use(
    http.get("*/api/preferences", () => HttpResponse.json(prefs)),
    http.put("*/api/preferences", async ({ request }) => { put = (await request.json()) as Record<string, unknown>; return HttpResponse.json(put); }),
  );
  renderWithProviders(<Settings />, { route: "/settings" });
  await userEvent.click(await screen.findByLabelText(/weekly digest/i)); // toggle one field
  await userEvent.click(screen.getByRole("button", { name: /save/i }));
  await vi.waitFor(() => expect(put).not.toBeNull());
  expect(put!.allergens).toEqual(["peanut"]); // untouched health field preserved
  expect(put!.weekly_digest_enabled).toBe(false); // toggled
});

test("delete account is gated behind the exact typed confirmation", async () => {
  let deleted = false;
  server.use(
    http.get("*/api/preferences", () => HttpResponse.json(prefs)),
    http.delete("*/api/account", () => { deleted = true; return new HttpResponse(null, { status: 204 }); }),
  );
  renderWithProviders(<Settings />, { route: "/settings" });
  await userEvent.click(await screen.findByRole("button", { name: /delete account/i }));
  const confirmBtn = screen.getByRole("button", { name: /^delete my account$/i });
  expect(confirmBtn).toBeDisabled();
  await userEvent.type(screen.getByPlaceholderText(/delete my account/i), "wrong");
  expect(confirmBtn).toBeDisabled();
  await userEvent.clear(screen.getByPlaceholderText(/delete my account/i));
  await userEvent.type(screen.getByPlaceholderText(/delete my account/i), "delete my account");
  expect(confirmBtn).toBeEnabled();
  await userEvent.click(confirmBtn);
  await vi.waitFor(() => expect(deleted).toBe(true));
  expect(signOut).toHaveBeenCalled();
});
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd hearty-web && npm run test -- --run src/pages/Settings.test.tsx`
Expected: FAIL — module not found.

- [ ] **Step 3: Implement the page**

Create `src/pages/Settings.tsx`:

```tsx
import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { usePreferences, useSavePreferences } from "../hooks/usePreferences";
import { api } from "../lib/api";
import { signOut } from "../lib/auth";
import { supabase } from "../lib/supabase";
import { saveBlob } from "../lib/download";
import type { UserPreferences } from "@/types/api";

const CONFIRM_PHRASE = "delete my account";

export default function Settings() {
  const navigate = useNavigate();
  const prefsQuery = usePreferences();
  const save = useSavePreferences();
  const [draft, setDraft] = useState<UserPreferences | null>(null);
  const [email, setEmail] = useState<string | null>(null);
  const [showDelete, setShowDelete] = useState(false);
  const [confirmText, setConfirmText] = useState("");
  const [busy, setBusy] = useState(false);
  const [msg, setMsg] = useState<string | null>(null);

  // Hydrate the editable draft once prefs load; keep the full object so untouched
  // fields (health, voice) are preserved on PUT (which is a full replace).
  useEffect(() => { if (prefsQuery.data && !draft) setDraft(prefsQuery.data); }, [prefsQuery.data, draft]);
  useEffect(() => { supabase.auth.getSession().then(({ data }) => setEmail(data.session?.user?.email ?? null)); }, []);

  function set<K extends keyof UserPreferences>(key: K, value: UserPreferences[K]) {
    setDraft((d) => (d ? { ...d, [key]: value } : d));
  }

  async function onSave() {
    if (!draft) return;
    setMsg(null);
    try { await save.mutateAsync(draft); setMsg("Saved."); }
    catch { setMsg("Couldn't save."); }
  }

  async function exportAll() {
    setMsg(null);
    try { const dl = await api.exportJson({}); saveBlob(dl.blob, dl.filename); }
    catch { setMsg("Couldn't export your data."); }
  }

  async function confirmDelete() {
    if (confirmText !== CONFIRM_PHRASE || busy) return;
    setBusy(true);
    try { await api.deleteAccount(); await signOut(); navigate("/login", { replace: true }); }
    catch { setMsg("Couldn't delete your account."); setBusy(false); }
  }

  if (prefsQuery.isPending) return <p className="text-text-faint">Loading…</p>;
  if (prefsQuery.isError || !draft) return <p className="text-sm text-accent-red">Couldn't load settings.</p>;

  const toggle = (key: keyof UserPreferences, label: string) => (
    <label className="flex items-center justify-between gap-3 py-1 text-sm">
      <span>{label}</span>
      <input type="checkbox" checked={Boolean(draft[key])} onChange={(e) => set(key, e.target.checked as never)} />
    </label>
  );

  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-6">
      <h1 className="font-display text-3xl">Settings</h1>

      <section className="rounded-2xl border border-surface-border bg-surface p-4">
        <h2 className="mb-2 text-sm text-text-muted">Notifications</h2>
        {toggle("post_meal_nudge_enabled", "Post-meal nudge")}
        {toggle("daily_checkin_enabled", "Daily check-in")}
        {toggle("trends_conversation_enabled", "Trends conversation")}
        {toggle("weekly_digest_enabled", "Weekly digest")}
        {toggle("sync_error_alerts_enabled", "Sync error alerts")}
        <label className="flex items-center justify-between gap-3 py-1 text-sm">
          <span>Nudge delay (minutes)</span>
          <input type="number" value={draft.nudge_delay_minutes} onChange={(e) => set("nudge_delay_minutes", Number(e.target.value))} className="w-20 rounded-lg border border-surface-border bg-transparent px-2 py-1" />
        </label>
        <label className="flex items-center justify-between gap-3 py-1 text-sm">
          <span>Conversation style</span>
          <select value={draft.conversation_style} onChange={(e) => set("conversation_style", e.target.value as UserPreferences["conversation_style"])} className="rounded-lg border border-surface-border bg-surface px-2 py-1">
            <option value="warm">warm</option>
            <option value="concise">concise</option>
          </select>
        </label>
      </section>

      <section className="rounded-2xl border border-surface-border bg-surface p-4">
        <h2 className="mb-2 text-sm text-text-muted">Check-in slots</h2>
        {toggle("morning_checkin_enabled", "Morning")}
        {toggle("midday_checkin_enabled", "Midday")}
        {toggle("evening_checkin_enabled", "Evening")}
      </section>

      <div className="flex items-center gap-3">
        <button onClick={onSave} disabled={save.isPending} className="rounded-lg bg-brand px-4 py-2 text-sm text-black disabled:opacity-50">{save.isPending ? "Saving…" : "Save"}</button>
        {msg && <span className="text-sm text-text-muted">{msg}</span>}
      </div>

      <section className="rounded-2xl border border-surface-border bg-surface p-4">
        <h2 className="mb-2 text-sm text-text-muted">Account</h2>
        <div className="font-mono-data text-xs text-text-faint">{email ?? "—"}</div>
        <div className="mt-3 flex flex-wrap gap-2">
          <button onClick={() => signOut().then(() => navigate("/login", { replace: true }))} className="rounded-lg border border-surface-border px-3 py-1 text-sm">Sign out</button>
          <button onClick={exportAll} className="rounded-lg border border-surface-border px-3 py-1 text-sm">Export all data</button>
          <button onClick={() => setShowDelete(true)} className="rounded-lg border border-accent-red/50 px-3 py-1 text-sm text-accent-red">Delete account</button>
        </div>
      </section>

      {showDelete && (
        <div className="rounded-2xl border border-accent-red/50 bg-surface p-4">
          <p className="text-sm text-text-muted">This permanently deletes your account and all data. Type <span className="font-mono-data text-accent-red">{CONFIRM_PHRASE}</span> to confirm.</p>
          <input value={confirmText} onChange={(e) => setConfirmText(e.target.value)} placeholder={CONFIRM_PHRASE} className="mt-2 w-full rounded-lg border border-surface-border bg-transparent px-2 py-1 text-sm" />
          <div className="mt-2 flex gap-2">
            <button onClick={confirmDelete} disabled={confirmText !== CONFIRM_PHRASE || busy} className="rounded-lg bg-accent-red px-3 py-1 text-sm text-black disabled:opacity-40">Delete my account</button>
            <button onClick={() => { setShowDelete(false); setConfirmText(""); }} className="rounded-lg border border-surface-border px-3 py-1 text-sm">Cancel</button>
          </div>
        </div>
      )}
    </div>
  );
}
```

- [ ] **Step 4: Wire the route in `src/App.tsx`**

Add `import Settings from "./pages/Settings";` and replace `<Route path="/settings" element={<ComingSoon />} />` with `<Route path="/settings" element={<Settings />} />`.

- [ ] **Step 5: Run tests + build + lint**

Run: `cd hearty-web && npm run test -- --run src/pages/Settings.test.tsx && npm run build && npm run lint`
Expected: PASS; type-clean; 0 lint.

- [ ] **Step 6: Full suite green**

Run: `cd hearty-web && npm run test -- --run`
Expected: all tests pass (Plan 1-3's 68 + the new ones).

- [ ] **Step 7: Commit**

```bash
git add src/pages/Settings.tsx src/pages/Settings.test.tsx src/App.tsx
git commit -m "feat(web): Settings page — preferences edit + account mgmt + typed-confirm delete; wire /settings route"
```

---

## Self-Review

**1. Spec coverage (§5.6 Reports, §5.8 Settings, §6 DELETE /api/account):**
- §5.6 date range → preview (`getSummary period=custom`) → Task 3. ✅
- §5.6 PDF (`POST /api/export/pdf` → bytes → blob), CSV (`GET …/csv` → stream), JSON (`GET …/json`) downloads + per-format loading/error → Tasks 2, 3. ✅
- §5.8 notifications/check-in/conversation via `GET/PUT /api/preferences`; voice prefs hidden (passed through) → Tasks 4, 5 (D1/D2). ✅
- §5.8 account: email, sign out, export all (JSON, no date range), delete account (typed confirmation → `DELETE /api/account` → sign out + redirect) → Task 5. ✅
- §6 `DELETE /api/account`: cascade per user-scoped table, storage objects, `admin.delete_user`, 204, children-before-user ordering, auth required, idempotent-ish → Task 1 (D4). ✅
- (Profile §5.7 is Plan 5 — out of scope, stated up front.)

**2. Placeholder scan:** No "TBD"/"handle errors"/"similar to" — every code step has complete code. ✅

**3. Type consistency:** `UserPreferences`/`ExportDateRange`/`BlobDownload` defined in Task 2, consumed by Tasks 3, 4, 5. `USER_TABLES` defined + asserted by the Task 1 test. API method names (`exportCsv`/`exportJson`/`exportPdf`/`getPreferences`/`putPreferences`/`deleteAccount`) consistent across Tasks 2–5. `saveBlob` (Task 2) used by Tasks 3, 5. `usePreferences`/`useSavePreferences` (Task 4) used by Task 5. ✅

**4. Deviations recorded:** D1–D4 documented with rationale; Profile explicitly deferred to Plan 5. ✅

---

## Execution handoff

Execute via **superpowers:subagent-driven-development**: Task 1 is backend (Python/pytest) — dispatch a backend-capable implementer (standard model); Tasks 2–5 are web (mechanical → cheap/standard; the two pages are integration → standard). Two-stage review (spec → quality) per unit + a final whole-implementation review. Continuous execution. Finish with **superpowers:finishing-a-development-branch** (push + PR #12, base `web-dashboard-conversation-experiments`) **only with user consent**.
