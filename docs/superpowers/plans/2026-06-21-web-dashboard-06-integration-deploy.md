# Web Dashboard — Plan 6: Integration + Vercel Deploy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans for the buildable tasks. Steps use checkbox (`- [ ]`) syntax. **This plan is hybrid:** Tasks 1–4 are buildable+verifiable artifacts; the "User actions" section lists console/credential steps the agent CANNOT perform.

**Goal:** Ship `hearty-web/` to production on Vercel with SPA deep-link routing, CI on PRs, a documented deploy runbook, and a passed integration checklist (spec §10) against the merged app.

**Architecture:** `hearty-web/` is a Vite SPA in a subdirectory of the monorepo. Vercel builds it with **Root Directory = `hearty-web`** (framework preset *Vite* → `vite build` → `dist`); a `vercel.json` adds the SPA rewrite so client-side routes (`/journal`, `/trends/chat`, …) and refreshes resolve to `index.html`. GitHub Actions runs lint + tests + build on PRs (web) and pytest (api). The integration pass is manual against a Vercel preview deploy + a throwaway account, ending with the destructive delete-account flow.

**Tech Stack:** Vercel (hosting), GitHub Actions (CI), Vite/React build, existing Vitest + pytest suites.

---

## Prerequisite & branch basing

**Strongly recommended: run this plan AFTER the five-PR stack (#9–#13) has merged to `master`,** so CI and the integration pass exercise the fully-integrated app. The buildable artifacts (Tasks 1–4) are repo-level config/docs and can technically land earlier, but their value (and the integration checklist) is greatest post-merge.

- If running post-merge: branch `web-dashboard-deploy` from `master`.
- If running now (pre-merge): this branch is stacked on Plan 5 (`web-dashboard-profile`); open PR #14 with **base = `web-dashboard-profile`** and retarget to `master` once the stack lands.

Merge order for the stack (bottom-up): **#9 → #10 → #11 → #12 → #13** (each into the branch below it, or rebase-and-retarget onto `master` as each lands).

---

## Verified current state (2026-06-21)

- `hearty-web/package.json` scripts: `dev`, `build` (`tsc -b && vite build`), `lint` (`eslint .`), `preview`, `test` (`vitest` — **watch mode**; CI must use `vitest run` / `npm test -- --run`).
- `vite.config.ts`: React + `@`→`src` alias, default `base: "/"`, output `dist/`. No SPA rewrite config (Vercel needs `vercel.json`).
- No `.github/workflows/` yet. No `vercel.json` yet.
- `hearty-web/.env.example`: `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_API_URL`.
- Backend pytest runs via the project venv with dummy env (`SUPABASE_URL`/`SUPABASE_SERVICE_KEY`) — see Plan 4.
- All 8 routes are real pages (Plan 5). Auth callback route is `/auth/callback` (must be a registered Supabase redirect URL per origin).

---

## Deviations / scope decisions

- **D1 — Manual integration checklist, not automated e2e.** Spec §10's integration list is run by hand against a preview deploy + throwaway account. An optional Playwright e2e is noted as future work (needs a live backend + seeded data; out of scope here to keep the deploy lean).
- **D2 — `vercel.json` lives in `hearty-web/` with Root Directory = `hearty-web`.** Simpler than a repo-root config pointing into the subdir; matches Vercel's monorepo convention.
- **D3 — CI does not deploy.** Vercel's own Git integration owns deploys (preview per PR, production on `master`). GitHub Actions only gates quality (lint/test/build/pytest). No secrets in CI.

---

## PHASE A — Deploy config

### Task 1: `vercel.json` (SPA deep-link rewrite)

**Files:**
- Create: `hearty-web/vercel.json`

- [ ] **Step 1: Create `hearty-web/vercel.json`**

```json
{
  "$schema": "https://openapi.vercel.sh/vercel.json",
  "rewrites": [
    { "source": "/((?!assets/).*)", "destination": "/index.html" }
  ]
}
```

Rationale: a React-Router SPA must serve `index.html` for any non-asset path so deep links (`/trends/chat`) and hard refreshes don't 404. The negative-lookahead on `assets/` lets Vite's hashed bundles (served from `/assets/...`) fall through to the real files; everything else rewrites to the app shell. (Vercel also serves real static files before applying rewrites, so this is belt-and-suspenders.)

- [ ] **Step 2: Verify the JSON is valid and the build still works**

Run: `cd hearty-web && node -e "JSON.parse(require('fs').readFileSync('vercel.json','utf8')); console.log('vercel.json OK')" && npm run build`
Expected: "vercel.json OK"; build type-clean (`dist/` produced).

- [ ] **Step 3: Commit**

```bash
git add hearty-web/vercel.json
git commit -m "chore(web): vercel.json SPA rewrite for client-side routing"
```

---

### Task 2: CI workflow (lint + test + build on PRs; backend pytest)

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Create `.github/workflows/ci.yml`**

```yaml
name: CI

on:
  pull_request:
  push:
    branches: [master]

jobs:
  web:
    name: web (lint · test · build)
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: hearty-web
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
          cache-dependency-path: hearty-web/package-lock.json
      - run: npm ci
      - run: npm run lint
      - run: npm test -- --run
      - run: npm run build

  api:
    name: api (pytest)
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: hearty-api
    env:
      SUPABASE_URL: http://localhost
      SUPABASE_SERVICE_KEY: dummy-key
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - run: pip install -r requirements.txt
      - run: python -m pytest -q
```

Notes:
- The `web` job uses `npm ci` (needs the committed `hearty-web/package-lock.json`) and `npm test -- --run` (one-shot; the `test` script is watch-mode).
- The `api` job sets dummy `SUPABASE_*` env so module-level `create_client(...)` doesn't `KeyError` at import (unit tests monkeypatch the client). If the full backend suite has live-integration tests that require real credentials, scope this to the unit tests instead: `python -m pytest -q -k "unit"` — confirm by checking which `tests/test_*` files need network before finalizing.

- [ ] **Step 2: Validate the workflow YAML locally**

Run: `python -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('yaml OK')"`
Expected: "yaml OK". (The workflow's first real execution happens on GitHub when the next PR opens; verify there.)

- [ ] **Step 3: Decide the `api` pytest scope**

Run: `cd hearty-api && grep -rl "API_BASE_URL\|TEST_JWT\|requests.get\|httpx" tests | sort`
If live-integration tests exist (they use `conftest.py`'s `api_base`/`headers` env fixtures), change the `api` job's test command to target only unit tests (e.g. `-k unit` or an explicit path glob) so CI doesn't require real credentials. Record the decision in the workflow as a comment.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: lint/test/build web + pytest api on PRs"
```

---

## PHASE B — Runbook & docs

### Task 3: Deployment runbook in the web README

**Files:**
- Modify: `hearty-web/README.md`

- [ ] **Step 1: Append a "Deployment (Vercel)" section to `hearty-web/README.md`**

Include exactly this content (adjust the origin placeholder when known):

```markdown
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
```

- [ ] **Step 2: Verify `.env.example` matches the documented vars**

Run: `cd hearty-web && cat .env.example`
Confirm it lists `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_API_URL`. (It does — no change expected; fix if drifted.)

- [ ] **Step 3: Commit**

```bash
git add hearty-web/README.md
git commit -m "docs(web): Vercel deployment runbook (root dir, env, redirect URLs, CORS)"
```

---

### Task 4: Integration checklist document

**Files:**
- Create: `docs/superpowers/web-dashboard-integration-checklist.md`

- [ ] **Step 1: Create the checklist (spec §10 integration list)**

```markdown
# Web Dashboard — Integration Checklist (spec §10)

Run against a **Vercel preview deploy** (or production) with the real FastAPI backend and a **throwaway test account**. The final step is destructive — use a throwaway account.

## Setup
- [ ] Vercel env vars set (VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY / VITE_API_URL).
- [ ] Supabase redirect URL includes `<origin>/auth/callback`.
- [ ] Backend `ALLOWED_ORIGINS` includes the origin.

## Flows
- [ ] **Auth:** unauthenticated `/dashboard` → redirect to `/login`; Google sign-in → lands on Dashboard.
- [ ] **Realtime:** quick-log a meal on the dashboard → appears without a manual refresh; log a meal on the phone → appears on web (realtime, or within refetch-on-focus).
- [ ] **Journal:** filters (date/keyword/meal-type/symptom-type) reflect in the URL and survive refresh; pagination works; expand → edit a meal (foods preserved) → Dashboard/Trends update; delete (two-step) removes it.
- [ ] **Trends:** renders signal cards or a clean empty-state; period selector switches charts; Analyse refreshes; submit a signal verdict.
- [ ] **Conversation:** `/trends/chat` opener loads; send a message; confirm a proposed verdict; start a proposed experiment → it appears on Experiments.
- [ ] **Experiments:** list renders; evaluate / abandon / restart / ack-nudge behave; results render.
- [ ] **Reports:** date-range preview loads; CSV, JSON, and PDF each download.
- [ ] **Profile:** add/edit allergen + dietary protocol, Save, reload → persisted; disclaimer always visible, non-dismissable.
- [ ] **Settings:** toggle a preference + Save (health fields preserved); Export all data downloads JSON; Sign out → `/login`.
- [ ] **Delete account (throwaway account, LAST):** typed-confirmation → account + data deleted → signed out → `/login`; re-login fails / starts fresh.

## Sign-off
- [ ] All flows pass on the preview deploy.
- [ ] Production promoted from `master`.
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/web-dashboard-integration-checklist.md
git commit -m "docs: web dashboard integration checklist (spec §10)"
```

---

## User actions (cannot be automated by the agent)

These require console access / credentials and are the human's to perform:

1. **Merge the stack** (#9 → #10 → #11 → #12 → #13) to `master`.
2. **Vercel:** create the project, set **Root Directory = `hearty-web`**, add the three `VITE_*` env vars (Production + Preview).
3. **Supabase:** add `<origin>/auth/callback` redirect URLs for production + preview + localhost.
4. **Backend:** set `ALLOWED_ORIGINS` to the production/preview origins (and redeploy the API).
5. **Realtime (optional but recommended):** enable Realtime on `meals`/`symptoms` + add an `authenticated` own-rows SELECT RLS policy (else realtime is best-effort).
6. **Run the integration checklist** (Task 4) against the preview deploy with a throwaway account, including the destructive delete-account step.
7. **Promote to production** once the checklist passes.

---

## Self-Review

**1. Spec coverage (§9 phase 9 — Integration test + Vercel deploy; §11 Hosting):**
- Vercel hosting with SPA routing → Task 1 + Task 3 (Root Directory, env, preview/prod). ✅
- Preview deploys on PRs + prod on `master` → documented (Vercel Git integration, D3). ✅
- `VITE_*` env, Supabase redirect URLs, backend `ALLOWED_ORIGINS` → Task 3 runbook + User actions. ✅
- Integration test pass (spec §10 list) → Task 4 checklist (manual, D1). ✅
- CI quality gate (the spec noted no CI existed) → Task 2 (lint/test/build + pytest). ✅

**2. Placeholder scan:** Config/doc artifacts are complete; the only intentional placeholders are `<your-prod-domain>`/origin values the human fills at deploy time (flagged). ✅

**3. Consistency:** CI uses `npm test -- --run` (the `test` script is watch-mode) and `npm ci` (needs the committed lockfile); the `api` job sets dummy `SUPABASE_*` to match how pytest imports the app (Plan 4 finding); Task 3's scope-check guards against CI requiring live credentials. ✅

**4. Deviations recorded:** D1 (manual integration, optional Playwright deferred), D2 (`vercel.json` in subdir), D3 (CI doesn't deploy). ✅

---

## Execution handoff

Buildable Tasks 1–4 can run via **superpowers:subagent-driven-development** (mechanical config/docs — cheap model; two-stage review per task; final review). They produce a PR (#14) with the deploy scaffolding. The **User actions** + the **integration checklist** are performed by the human against a live preview deploy. Finish with **superpowers:finishing-a-development-branch** **only with user consent**.
