# Hearty — REST API (Spec 03) — Living Plan

**Spec:** [`hearty-03-rest-api.md`](../specs/2026-05-04-hearty-03-rest-api.md)
**Roadmap Phase:** Phase 1 — Foundation
**Plan Status:** 🔴 Not Started
**Last Updated:** 2026-05-05
**Last Verified Against Spec:** 2026-05-04 — re-verify if spec has changed since
**Open Deviations:** 0

---

## How to Use This Plan

1. Always start with **Phase 0** at the beginning of any new session on this plan
2. Find the first phase/task marked **🔴 Not Started**, mark it **🟡 In Progress**
3. Paste the phase's **Activation Prompt** into a new Claude Code session
4. Follow the steps — Claude will guide you through each one
5. At natural break points, Claude will tell you to run `/compact`; do so, then start a new session with the **Activation Prompt** at the top of the next phase
6. Mark completed phases **🟢 Completed** and log any deviations as a single line at the bottom

**Status key:** 🔴 Not Started · 🟡 In Progress · 🟢 Completed · ⚠️ Blocked · ↩️ Deviated

---

## Phase Summary

| Phase | Name | Status | Depends On | Type |
|---|---|---|---|---|
| 0 | Review & Align | 🟢 Completed | — | Claude (start of every session) |
| 1 | Project Setup | 🔴 Not Started | Spec 01 plan 🟢, Spec 08 Phases 1-2 🟢 | Claude |
| 2 | Auth & JWT Middleware | 🔴 Not Started | Phase 1 | Claude |
| 3 | Auth Webhook | 🔴 Not Started | Phase 2 | Claude |
| 4 | AI Extraction Service | 🔴 Not Started | Phase 2 | Claude |
| 5 | Core Logging Endpoints | 🔴 Not Started | Phases 3, 4 | Claude |
| 6 | Trend Engine & Summary | 🔴 Not Started | Phase 5 | Claude |
| 7 | Export Endpoints | 🔴 Not Started | Phase 5 | Claude |
| 8 | Health Profile Endpoints | 🔴 Not Started | Phase 2 | Claude |
| 9 | Photo Stubs | 🔴 Not Started | Phase 2 | Claude |
| 10 | Fly.io Deployment | 🔴 Not Started | Phases 5–9 | Claude |
| 11 | Integration Tests | 🔴 Not Started | Phase 10 | Claude |

---

## Phase 0: Review & Align

**Status:** 🟢 Completed
**Goal:** Verify the dev environment, confirm prerequisite plans are complete, confirm the spec hasn't drifted from this plan, and identify exactly which phase to start or resume.
**Run this phase at the start of every session on this plan.**

### Activation Prompt

```
You are running Phase 0 (Review & Align) for the Hearty REST API setup.
This runs at the start of every session — it takes about 5 minutes and prevents
working from stale assumptions.

Working directory: /home/evan/projects/food-journal-assistant

Before running any command, verify it exists with --help or equivalent.
If a step doesn't match what you find, stop and tell me — don't improvise.

Steps:

1. Read these three files in full:
   - docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md  (this plan)
   - docs/superpowers/plans/2026-05-04-hearty-01-database-plan.md  (Spec 01 plan)
   - docs/superpowers/plans/2026-05-04-hearty-08-health-profile-plan.md  (Spec 08 plan, if it exists)

2. Confirm prerequisites:
   - The Spec 01 (Database) plan must be marked 🟢 Completed before Phase 1 can begin.
     The auth/on-login webhook upserts rows into health_profile and notification_preferences —
     those tables must already exist (created in Spec 01).
   - Spec 08 (Health Profile) **Phases 1-2** must be 🟢 Completed before Phase 1 can begin —
     the Pydantic schemas from Phase 2 are needed by Phase 3 of this plan (Auth Webhook) and
     Phase 8 (Health Profile Endpoints). Spec 08 Phases 3-5 (REST router, context injection,
     tests) depend on this plan's Phase 2 (auth middleware) and run after it.
     If the Spec 08 plan file doesn't exist yet, report it and stop.

3. Check the dev environment (run each command, note missing items):
   - git status
   - python3 --version   (need >= 3.11)
   - pip3 --version
   - python3 -m virtualenv --version  (or virtualenv --version)
   - pip index versions litellm 2>/dev/null | head -5   (show latest available litellm version)
   - fly version   (Fly.io CLI; note if not found — Phase 10 will install it)
   - ls hearty-api/ 2>/dev/null && echo "directory exists" || echo "not yet created"

4. Spec drift check — this plan was written on 2026-05-04. Scan the spec for any changes to:
   endpoint paths, request/response shapes, auth mechanism, LiteLLM usage, file structure,
   hosting target, or requirements.txt contents.
   If anything conflicts with this plan's task steps, list it.

5. Report:
   - Prerequisite plan statuses: Spec 01 is / Spec 08 is
   - Environment: what is/isn't installed, litellm latest version
   - Spec alignment: any drift found, or "clean"
   - Next action: which phase to proceed with (or what to fix first)

Update this plan: set Phase 0 status to 🟢 Completed and Last Updated to today.
Commit: git add docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md && git commit -m "docs: REST API plan Phase 0 complete"
Tell me to run /compact, and remind me that the next phase's Activation Prompt is at the top of Phase 1 in this plan file.
```

**Deviation Log:** _None_

---

## Phase 1: Project Setup

**Status:** 🔴 Not Started
**Goal:** Create the `hearty-api/` directory tree, virtualenv, `requirements.txt`, `.env.example`, and stub `main.py` — enough to run `uvicorn app.main:app --reload` without error.
**Depends on:** Spec 01 plan 🟢 Completed, Spec 08 Phases 1-2 🟢 Completed

### Activation Prompt

```
You are implementing Phase 1 (Project Setup) of the Hearty REST API.

Working directory: /home/evan/projects/food-journal-assistant

Context:
- Spec: docs/superpowers/specs/2026-05-04-hearty-03-rest-api.md
- Plan: docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md

Before running any command, verify it exists with --help or equivalent.
If a step doesn't match what you find, stop and tell me — don't improvise.

Read the plan file, then execute Tasks 1.1 through 1.3 in order.

When all tasks are done:
- Mark Phase 1 status as 🟢 Completed in the plan file
- Commit: git add hearty-api/ docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md && git commit -m "feat: REST API project scaffold"
- Tell me to run /compact
- Remind me that the next phase's Activation Prompt is at the top of Phase 2 in this plan file
```

---

### Task 1.1: Create directory structure

**Status:** 🔴 Not Started

- [ ] `hearty-api/app/health_profile/` may already exist from Spec 08 Phase 1 — do not remove it. Create the remaining directories (`mkdir -p` is safe if they already exist):
  ```bash
  mkdir -p hearty-api/app/routers
  mkdir -p hearty-api/app/services
  mkdir -p hearty-api/app/models
  ```

- [ ] Create placeholder `__init__.py` files (skip any that already exist from Spec 08):
  ```bash
  touch hearty-api/app/__init__.py
  touch hearty-api/app/routers/__init__.py
  touch hearty-api/app/services/__init__.py
  touch hearty-api/app/models/__init__.py
  ```

- [ ] Verify the structure matches spec Section 2 exactly (all files listed, all directories present).

**Deviation Log:** _None_

---

### Task 1.2: Create `requirements.txt` and virtualenv

**Status:** 🔴 Not Started

- [ ] Create `hearty-api/requirements.txt` with the exact pinned versions from spec Section 12:
  ```
  fastapi>=0.111.0
  uvicorn[standard]>=0.29.0
  supabase>=2.4.0
  pydantic>=2.7.0
  litellm>=1.40.0
  python-multipart>=0.0.9
  reportlab>=4.2.0
  matplotlib>=3.9.0
  requests>=2.32.0
  ```

- [ ] Create and activate a virtualenv:
  ```bash
  cd hearty-api
  python3 -m venv venv
  source venv/bin/activate
  pip install -r requirements.txt
  ```

- [ ] Verify key packages installed:
  ```bash
  python -c "import fastapi, litellm, supabase; print('OK')"
  ```
  Expected: `OK`

- [ ] Add `hearty-api/venv/` to `.gitignore` if not already present.

**Deviation Log:** _None_

---

### Task 1.3: Create `.env.example` and stub `main.py`

**Status:** 🔴 Not Started

- [ ] Create `hearty-api/.env.example` from spec Section 11 (verbatim).

- [ ] Create `hearty-api/app/main.py` from spec Section 10 (verbatim), but with all
  router imports stubbed as empty modules for now — each router file doesn't exist yet.
  Comment out `app.include_router(...)` lines that reference non-existent files.
  Include: `@app.get("/health")` endpoint — this must work now.

- [ ] Create `hearty-api/app/models/schemas.py` with the full Pydantic models from spec Section 4 (verbatim).
  This is a pure schema file — no imports from other app modules.

- [ ] Verify the app starts and the health endpoint responds:
  ```bash
  cd hearty-api && source venv/bin/activate
  set -a && source .env 2>/dev/null; set +a
  uvicorn app.main:app --port 8000 &
  sleep 2
  curl -s http://localhost:8000/health
  kill %1
  ```
  Expected curl output: `{"status":"ok"}`

**Deviation Log:** _None_

---

## Phase 2: Auth & JWT Middleware

**Status:** 🔴 Not Started
**Goal:** Implement `app/auth.py` (Supabase JWT verification dependency) and verify it blocks unauthenticated requests.
**Depends on:** Phase 1 complete

### Activation Prompt

```
You are implementing Phase 2 (Auth & JWT Middleware) of the Hearty REST API.

Working directory: /home/evan/projects/food-journal-assistant

Context:
- Spec: docs/superpowers/specs/2026-05-04-hearty-03-rest-api.md  (Section 3)
- Plan: docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md

Before running any command, verify it exists with --help or equivalent.
If a step doesn't match what you find, stop and tell me — don't improvise.

Read the plan file, then execute Tasks 2.1 and 2.2 in order.

When all tasks are done:
- Mark Phase 2 status as 🟢 Completed in the plan file
- Commit: git add hearty-api/app/ docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md && git commit -m "feat: REST API auth middleware"
- Tell me to run /compact
- Remind me that the next phase's Activation Prompt is at the top of Phase 3 in this plan file
```

---

### Task 2.1: Implement `app/auth.py`

**Status:** 🔴 Not Started

- [ ] Create `hearty-api/app/auth.py` from spec Section 3.1 (verbatim):
  - `security = HTTPBearer()`
  - `supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])`
  - `async def get_current_user(credentials: HTTPAuthorizationCredentials = Security(security)) -> dict`
  - Raises `HTTPException(status_code=401, detail="Invalid or expired token")` on bad token
  - Returns `{"id": response.user.id, "email": response.user.email}` on success

- [ ] Verify the file is importable:
  ```bash
  cd hearty-api && source venv/bin/activate
  python -c "from app.auth import get_current_user; print('OK')"
  ```
  Expected: `OK` (note: this import will read env vars at module-level — a missing `SUPABASE_URL` will raise `KeyError`; if `.env` is not populated yet, that's expected)

**Deviation Log:** _None_

---

### Task 2.2: Add a protected test route and verify 401

**Status:** 🔴 Not Started

- [ ] In `hearty-api/app/main.py`, temporarily add a protected test route:
  ```python
  from app.auth import get_current_user
  from fastapi import Depends

  @app.get("/health/authed")
  async def health_authed(user=Depends(get_current_user)):
      return {"status": "ok", "user_id": user["id"]}
  ```

- [ ] With a real Supabase project URL and service key in `hearty-api/.env`, start the server in the background and run both checks:
  ```bash
  cd hearty-api && source venv/bin/activate
  set -a && source .env && set +a
  uvicorn app.main:app --port 8000 &
  sleep 2

  # Check unauthenticated — HTTPBearer returns 403 when no token is provided
  echo "No token (expect 403):"
  curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8000/health/authed

  # Check bad token — JWT verification returns 401
  echo "Bad token (expect 401):"
  curl -s -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer bad-token" http://localhost:8000/health/authed

  kill %1
  ```
  Expected: `403` for no token (HTTPBearer behavior); `401` for bad token.

- [ ] Remove the temporary `/health/authed` route after verification (keep `main.py` clean).

**Deviation Log:** _None_

---

## Phase 3: Auth Webhook

**Status:** 🔴 Not Started
**Goal:** Implement `POST /auth/on-login` — the Supabase Auth webhook that bootstraps `health_profile` and `notification_preferences` rows for new users.
**Depends on:** Phase 2 complete

### Activation Prompt

```
You are implementing Phase 3 (Auth Webhook) of the Hearty REST API.

Working directory: /home/evan/projects/food-journal-assistant

Context:
- Spec: docs/superpowers/specs/2026-05-04-hearty-03-rest-api.md  (Section 14)
- Plan: docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md

Before running any command, verify it exists with --help or equivalent.
If a step doesn't match what you find, stop and tell me — don't improvise.

Read the plan file, then execute Tasks 3.1 and 3.2 in order.

When all tasks are done:
- Mark Phase 3 status as 🟢 Completed in the plan file
- Commit: git add hearty-api/ docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md && git commit -m "feat: auth on-login webhook"
- Tell me to run /compact
- Remind me that the next phase's Activation Prompt is at the top of Phase 4 in this plan file
```

---

### Task 3.1: Create `app/routers/auth_hooks.py`

**Status:** 🔴 Not Started

- [ ] Create `hearty-api/app/routers/auth_hooks.py`:

  ```python
  # app/routers/auth_hooks.py
  from fastapi import APIRouter, HTTPException, Request
  import os
  from supabase import create_client

  router = APIRouter()

  supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])
  WEBHOOK_SECRET = os.environ.get("SUPABASE_WEBHOOK_SECRET", "")

  @router.post("/auth/on-login")
  async def on_login(request: Request):
      # Verify webhook secret
      auth_header = request.headers.get("Authorization", "")
      if WEBHOOK_SECRET and auth_header != f"Bearer {WEBHOOK_SECRET}":
          raise HTTPException(status_code=401, detail="Invalid webhook secret")

      payload = await request.json()
      user = payload.get("user") or payload.get("record", {})
      user_id = user.get("id")
      if not user_id:
          raise HTTPException(status_code=400, detail="No user id in payload")

      # Upsert health_profile (blank row — no-op if already exists)
      supabase.table("health_profile").upsert(
          {"user_id": user_id},
          on_conflict="user_id"
      ).execute()

      # Upsert notification_preferences (all defaults — no-op if already exists)
      supabase.table("notification_preferences").upsert(
          {"user_id": user_id},
          on_conflict="user_id"
      ).execute()

      return {"ok": True}
  ```

- [ ] Add `SUPABASE_WEBHOOK_SECRET=` to `hearty-api/.env.example`.

**Deviation Log:** _None_

---

### Task 3.2: Wire into `main.py` and verify

**Status:** 🔴 Not Started

- [ ] In `hearty-api/app/main.py`, add:
  ```python
  from app.routers import auth_hooks
  app.include_router(auth_hooks.router)
  ```

- [ ] Verify the route appears in the OpenAPI schema:
  ```bash
  cd hearty-api && source venv/bin/activate
  set -a && source .env && set +a
  uvicorn app.main:app --reload --port 8000 &
  curl -s http://localhost:8000/openapi.json | python3 -c "import sys,json; paths=json.load(sys.stdin)['paths']; print('/auth/on-login' in paths)"
  ```
  Expected: `True`
  Kill the background server after verification.

- [ ] Register the webhook in the Supabase Dashboard manually (browser step):
  - Dashboard → Database → Webhooks → Create new webhook
  - Event: `INSERT` on `auth.users`
  - URL: `[API_BASE_URL]/auth/on-login`
  - HTTP Headers: `Authorization: Bearer [SUPABASE_WEBHOOK_SECRET]`
  - This step is manual — record it in the deviation log if the dashboard UI differs.

**Deviation Log:** _None_

---

## Phase 4: AI Extraction Service

**Status:** 🔴 Not Started
**Goal:** Implement `app/services/ai_extraction.py` — `extract_meal()`, `extract_symptoms()`, and `generate_summary()` — using LiteLLM.
**Depends on:** Phase 2 complete (virtualenv and schemas are in place)

### Activation Prompt

```
You are implementing Phase 4 (AI Extraction Service) of the Hearty REST API.

Working directory: /home/evan/projects/food-journal-assistant

Context:
- Spec: docs/superpowers/specs/2026-05-04-hearty-03-rest-api.md  (Section 6)
- Plan: docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md

Before running any command, verify it exists with --help or equivalent.
If a step doesn't match what you find, stop and tell me — don't improvise.

Read the plan file, then execute Tasks 4.1 and 4.2 in order.

When all tasks are done:
- Mark Phase 4 status as 🟢 Completed in the plan file
- Commit: git add hearty-api/app/services/ docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md && git commit -m "feat: AI extraction service"
- Tell me to run /compact
- Remind me that the next phase's Activation Prompt is at the top of Phase 5 in this plan file
```

---

### Task 4.1: Implement `app/services/ai_extraction.py`

**Status:** 🔴 Not Started

- [ ] Create `hearty-api/app/services/ai_extraction.py` with all three functions from spec Section 6:

  - `extract_meal(description: str) -> dict`
    - Uses `MEAL_EXTRACTION_PROMPT` from spec Section 6.1 (verbatim)
    - Returns parsed JSON: `{"foods": [...], "inferred_meal_type": "..."}`
    - LiteLLM call: `litellm.completion(model=os.environ.get("LLM_MODEL", "claude-sonnet-4-6"), messages=[{"role": "user", "content": prompt}], api_base=os.environ.get("LLM_BASE_URL"))`
    - Parse response content as JSON; raise `ValueError` with message if JSON parse fails

  - `extract_symptoms(raw_description: str) -> list[dict]`
    - Uses `SYMPTOM_EXTRACTION_PROMPT` from spec Section 6.2 (verbatim)
    - Returns parsed JSON list of symptom dicts

  - `generate_summary(stats: dict) -> str`
    - Uses `SUMMARY_PROMPT` from spec Section 6.3 (verbatim), with `{stats_json}` replaced by `json.dumps(stats)`
    - Returns the response text as a plain string

- [ ] Add `hearty-api/app/services/__init__.py` (empty) if not already present.

**Deviation Log:** _None_

---

### Task 4.2: Smoke test AI extraction locally

**Status:** 🔴 Not Started

- [ ] With a valid `ANTHROPIC_API_KEY` (or whichever provider key matches `LLM_MODEL`) set in `.env`:
  ```bash
  cd hearty-api && source venv/bin/activate
  set -a && source .env && set +a
  python3 -c "
  from app.services.ai_extraction import extract_meal
  result = extract_meal('Scrambled eggs with toast and orange juice')
  print(result)
  assert 'foods' in result, 'Missing foods key'
  assert len(result['foods']) >= 2, 'Expected at least 2 food items'
  print('extract_meal: OK')
  "
  ```
  Expected: JSON output with `foods` array containing eggs, toast, and juice entries.

- [ ] Test symptom extraction:
  ```bash
  python3 -c "
  from app.services.ai_extraction import extract_symptoms
  result = extract_symptoms('Mild bloating about 20 minutes after eating, maybe a 4 out of 10')
  print(result)
  assert isinstance(result, list), 'Expected a list'
  assert result[0]['symptom_type'] == 'bloating', f'Expected bloating, got {result[0][\"symptom_type\"]}'
  print('extract_symptoms: OK')
  "
  ```

**Deviation Log:** _None_

---

## Phase 5: Core Logging Endpoints

**Status:** 🔴 Not Started
**Goal:** Implement the three POST logging endpoints and two GET query endpoints: meals, symptoms, wellbeing — wired to the AI extraction service and Supabase.
**Depends on:** Phase 3 (auth_hooks router pattern established), Phase 4 (AI extraction available)

### Activation Prompt

```
You are implementing Phase 5 (Core Logging Endpoints) of the Hearty REST API.

Working directory: /home/evan/projects/food-journal-assistant

Context:
- Spec: docs/superpowers/specs/2026-05-04-hearty-03-rest-api.md  (Sections 5.1–5.5)
- Plan: docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md

Before running any command, verify it exists with --help or equivalent.
If a step doesn't match what you find, stop and tell me — don't improvise.

Read the plan file, then execute Tasks 5.1 through 5.3 in order.

When all tasks are done:
- Mark Phase 5 status as 🟢 Completed in the plan file
- Commit: git add hearty-api/app/routers/ docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md && git commit -m "feat: core logging endpoints"
- Tell me to run /compact
- Remind me that the next phase's Activation Prompt is at the top of Phase 6 in this plan file
```

---

### Task 5.1: Implement meals router (`app/routers/meals.py`)

**Status:** 🔴 Not Started

- [ ] Create `hearty-api/app/routers/meals.py` implementing:

  - `POST /api/meals` (spec Section 5.1):
    - Accepts `MealRequest`, requires `user=Depends(get_current_user)`
    - Calls `ai_extraction.extract_meal(body.description)` to populate `foods[]` and infer `meal_type` if not provided
    - Checks for duplicate `offline_id` before inserting (idempotency: if row with same `offline_id` for this user exists, return existing record with `200` instead of `201`)
    - Inserts into `meals` table via Supabase client
    - Returns `MealResponse` with status `201`

  - `GET /api/meals` (spec Section 5.4):
    - Query params: `start_date`, `end_date`, `meal_type`, `keyword`, `limit` (default 50, max 200), `offset` (default 0)
    - Defaults: `start_date = 7 days ago`, `end_date = now`
    - Joins symptoms on `meal_id` — each meal in the response includes a `symptoms` array
    - Returns `{"total": int, "meals": [MealResponse with symptoms]}`

- [ ] Wire `meals.router` into `main.py`: uncomment or add `app.include_router(meals.router)`.

- [ ] Verify routes appear: `curl -s http://localhost:8000/openapi.json | python3 -c "import sys,json; d=json.load(sys.stdin); print([p for p in d['paths'] if 'meals' in p])"`
  Expected: `['/api/meals']`

**Deviation Log:** _None_

---

### Task 5.2: Implement symptoms router (`app/routers/symptoms.py`)

**Status:** 🔴 Not Started

- [ ] Create `hearty-api/app/routers/symptoms.py` implementing:

  - `POST /api/symptoms` (spec Section 5.2):
    - Accepts `SymptomRequest`, requires `user=Depends(get_current_user)`
    - If `body.symptoms` is not provided, calls `ai_extraction.extract_symptoms(body.raw_description)`
    - Inserts one row per extracted symptom into `symptoms` table
    - Returns `List[SymptomResponse]` with status `201`

  - `GET /api/symptoms` (spec Section 5.5):
    - Query params: `start_date`, `end_date`, `symptom_type`, `min_severity`, `limit` (default 50)
    - Defaults: `start_date = 7 days ago`, `end_date = now`
    - Returns `List[SymptomResponse]`

- [ ] Wire `symptoms.router` into `main.py`.

**Deviation Log:** _None_

---

### Task 5.3: Implement wellbeing router (`app/routers/wellbeing.py`)

**Status:** 🔴 Not Started

- [ ] Create `hearty-api/app/routers/wellbeing.py` implementing:

  - `POST /api/wellbeing` (spec Section 5.3):
    - Accepts `WellbeingRequest`, requires `user=Depends(get_current_user)`
    - Inserts into `wellbeing_snapshots` table
    - Returns `WellbeingResponse` with status `201`

- [ ] Wire `wellbeing.router` into `main.py`.

- [ ] End-to-end smoke test — start the server in the background, send a request with a valid `TEST_JWT`, then stop:
  ```bash
  cd hearty-api && source venv/bin/activate
  set -a && source .env && set +a
  uvicorn app.main:app --port 8000 &
  sleep 2
  curl -s -w "\nHTTP %{http_code}\n" -X POST http://localhost:8000/api/wellbeing \
    -H "Authorization: Bearer $TEST_JWT" \
    -H "Content-Type: application/json" \
    -d '{"energy_level": 7, "mood": 8, "sleep_hours": 7.5}'
  kill %1
  ```
  Expected: `HTTP 201` with a `WellbeingResponse` JSON body containing an `id` UUID.
  (`TEST_JWT` must be set in `.env` — get it from the Supabase Dashboard → Authentication → Users → select a test user → copy the JWT, or sign in programmatically and print `session.access_token`.)

**Deviation Log:** _None_

---

## Phase 6: Trend Engine & Summary

**Status:** 🔴 Not Started
**Goal:** Implement `app/services/trend_engine.py` (co-occurrence analysis with two-tier classification) and the `GET /api/trends` and `GET /api/summary` endpoints.
**Depends on:** Phase 5 complete (data exists in meals and symptoms tables to analyze)

### Activation Prompt

```
You are implementing Phase 6 (Trend Engine & Summary) of the Hearty REST API.

Working directory: /home/evan/projects/food-journal-assistant

Context:
- Spec: docs/superpowers/specs/2026-05-04-hearty-03-rest-api.md  (Sections 5.6, 5.7, 8)
- Plan: docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md

Before running any command, verify it exists with --help or equivalent.
If a step doesn't match what you find, stop and tell me — don't improvise.

Read the plan file, then execute Tasks 6.1 and 6.2 in order.

When all tasks are done:
- Mark Phase 6 status as 🟢 Completed in the plan file
- Commit: git add hearty-api/app/services/trend_engine.py hearty-api/app/routers/trends.py docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md && git commit -m "feat: trend engine and summary endpoint"
- Tell me to run /compact
- Remind me that the next phase's Activation Prompt is at the top of Phase 7 in this plan file
```

---

### Task 6.1: Implement `app/services/trend_engine.py`

**Status:** 🔴 Not Started

- [ ] Create `hearty-api/app/services/trend_engine.py` implementing the co-occurrence analysis algorithm from spec Section 8:

  - `analyze_triggers(user_id: str, analysis_period_days: int, focus_symptom: str | None, min_occurrences: int) -> dict`
    - Queries `meals` and `symptoms` for the given period
    - For each food item in a meal, checks for symptom occurrences within 0–240 minutes of that meal
    - Calculates confidence score per spec formula:
      `confidence = (co_occurrence_rate * 0.5) + (avg_severity / 10 * 0.3) + (frequency_bonus * 0.2)`
    - Two-tier classification:
      - 3–5 co-occurrences → label `"early signal, needs more data"`, `is_confirmed = false`
      - 6+ co-occurrences → label `"established"`, `is_confirmed = false` (spec says `is_confirmed` is not set by the engine — that is a user action)
    - Filters out entries below `min_occurrences`
    - Returns data shaped to populate `TrendsResponse`

  - `update_food_triggers_table(user_id: str, analysis_period_days: int) -> None`
    - Runs `analyze_triggers` and upserts results into the `food_triggers` table
    - Used by the scheduled background job (documented here; the scheduler itself is a Supabase Edge Function or Railway cron, out of scope for this plan)

**Deviation Log:** _None_

---

### Task 6.2: Implement trends router (`app/routers/trends.py`)

**Status:** 🔴 Not Started

- [ ] Create `hearty-api/app/routers/trends.py` implementing:

  - `GET /api/trends` (spec Section 5.6):
    - Query params: `analysis_period_days` (default 30), `focus_symptom`, `min_occurrences` (default 2)
    - Requires `user=Depends(get_current_user)`
    - Calls `trend_engine.analyze_triggers(...)` on demand
    - Returns `TrendsResponse`

  - `GET /api/summary` (spec Section 5.7):
    - Query params: `period` (default `"week"`, values: `"week"`, `"month"`, `"custom"`), `start_date`, `end_date`
    - `start_date` and `end_date` are required when `period = "custom"` — return `422` if missing
    - Aggregates stats for the period: meals logged, top symptoms with counts and avg severity, top triggers
    - Calls `ai_extraction.generate_summary(stats)` to produce `summary_text`
    - Returns `SummaryResponse`

- [ ] Wire `trends.router` into `main.py`.

**Deviation Log:** _None_

---

## Phase 7: Export Endpoints

**Status:** 🔴 Not Started
**Goal:** Implement `app/services/export_service.py` and the JSON, CSV, and PDF export endpoints.
**Depends on:** Phase 5 complete (meals and symptoms data available)

### Activation Prompt

```
You are implementing Phase 7 (Export Endpoints) of the Hearty REST API.

Working directory: /home/evan/projects/food-journal-assistant

Context:
- Spec: docs/superpowers/specs/2026-05-04-hearty-03-rest-api.md  (Sections 5.8–5.10)
- Plan: docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md

Before running any command, verify it exists with --help or equivalent.
If a step doesn't match what you find, stop and tell me — don't improvise.

Read the plan file, then execute Tasks 7.1, 7.2a, 7.2b, and 7.3 in order.

When all tasks are done:
- Mark Phase 7 status as 🟢 Completed in the plan file
- Commit: git add hearty-api/app/services/export_service.py hearty-api/app/routers/export.py docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md && git commit -m "feat: export endpoints"
- Tell me to run /compact
- Remind me that the next phase's Activation Prompt is at the top of Phase 8 in this plan file
```

---

### Task 7.1: Implement JSON and CSV export

**Status:** 🔴 Not Started

- [ ] Create `hearty-api/app/routers/export.py` implementing:

  - `GET /api/export/json` (spec Section 5.8):
    - Query params: `start_date`, `end_date` (optional, default: all time)
    - Returns `application/json` with the full nested structure from spec Section 5.8:
      `exported_at`, `user_id`, `period`, `meals` (with nested symptoms), `wellbeing_snapshots`, `food_triggers`, `health_profile`

  - `GET /api/export/csv` (spec Section 5.9):
    - Query params: `start_date`, `end_date` (optional)
    - Returns `text/csv` — flat structure, one row per symptom event with denormalized meal fields
    - Column headers: `Meal Description`, `Food Items`, `Symptom Type`, `Severity`, `Onset (minutes)`, `Meal Type`, `Logged At`
    - Uses Python's built-in `csv` module and FastAPI's `StreamingResponse`

- [ ] Wire `export.router` into `main.py`.

**Deviation Log:** _None_

---

### Task 7.2a: Implement PDF data aggregation and chart rendering

**Status:** 🔴 Not Started

- [ ] Create `hearty-api/app/services/export_service.py` with a `gather_export_data(user_id, start_date, end_date)` helper:
    - Queries: meals + nested symptoms, wellbeing snapshots, food triggers, health profile, notification_preferences
    - Returns a dict with all data needed by the PDF sections

- [ ] Add `render_symptom_timeline(meals_data) -> bytes` using Matplotlib:
    - X-axis: date, Y-axis: symptom severity per day
    - Use `io.BytesIO` + `fig.savefig(buf, format='png')` — no temp files on disk
    - Returns PNG bytes

- [ ] Add `render_wellbeing_trends(wellbeing_data) -> bytes` using Matplotlib:
    - X-axis: date, Y-axis: energy/mood/sleep lines
    - Same in-memory PNG approach

- [ ] Smoke test the helpers in isolation (no Supabase needed — pass mock data):
  ```bash
  cd hearty-api && source venv/bin/activate
  python3 -c "
  from app.services.export_service import render_symptom_timeline
  png = render_symptom_timeline([])  # empty data — should return valid PNG bytes
  assert png[:4] == b'\x89PNG', 'Not a PNG'
  print('chart render: OK')
  "
  ```

**Deviation Log:** _None_

---

### Task 7.2b: Assemble PDF with reportlab

**Status:** 🔴 Not Started

- [ ] Add `generate_pdf(user_id: str, start_date: datetime | None, end_date: datetime | None) -> bytes` to `export_service.py`:
    - Calls `gather_export_data()` and both chart renderers
    - Compiles with `reportlab.platypus` (`SimpleDocTemplate`, `Paragraph`, `Table`, `Image`) — all 6 sections from spec Section 5.10:
      1. Cover: date range, user email
      2. Summary statistics
      3. Top trigger foods table with confidence scores
      4. Symptom timeline chart (embedded PNG via `reportlab.platypus.Image`)
      5. Wellbeing trends chart
      6. Pattern observations (always included)
      7. AI-generated recommendations — **only if `notification_preferences.ai_recommendations_enabled = true`**; labeled "Not medical advice. For personal awareness only."
    - Returns PDF as `bytes` via `io.BytesIO`

- [ ] Smoke test PDF assembly:
  ```bash
  cd hearty-api && source venv/bin/activate
  set -a && source .env && set +a
  python3 -c "
  from app.services.export_service import generate_pdf
  pdf = generate_pdf('00000000-0000-0000-0000-000000000001', None, None)
  assert pdf[:4] == b'%PDF', 'Not a PDF'
  print('generate_pdf: OK, size =', len(pdf), 'bytes')
  "
  ```
  Expected: `generate_pdf: OK, size = <N> bytes`

**Deviation Log:** _None_

---

### Task 7.3: Wire PDF export into the router

**Status:** 🔴 Not Started

- [ ] In `hearty-api/app/routers/export.py`, add:

  - `POST /api/export/pdf` (spec Section 5.10):
    - Accepts `ExportRequest` (optional `start_date`, `end_date`)
    - Requires `user=Depends(get_current_user)`
    - Calls `export_service.generate_pdf(user["id"], start_date, end_date)`
    - Returns `Response(content=pdf_bytes, media_type="application/pdf", headers={"Content-Disposition": "attachment; filename=hearty-report.pdf"})`

- [ ] Smoke test PDF generation with a real user JWT:
  ```bash
  curl -s -X POST http://localhost:8000/api/export/pdf \
    -H "Authorization: Bearer $TEST_JWT" \
    -H "Content-Type: application/json" \
    -d '{}' \
    --output /tmp/hearty-test.pdf
  file /tmp/hearty-test.pdf
  ```
  Expected: `PDF document, version 1.x`

**Deviation Log:** _None_

---

## Phase 8: Health Profile Endpoints

**Status:** 🔴 Not Started
**Goal:** Implement `GET /api/health-profile` and `PUT /api/health-profile`.
**Depends on:** Phase 2 complete (auth middleware)

### Activation Prompt

```
You are implementing Phase 8 (Health Profile Endpoints) of the Hearty REST API.

Working directory: /home/evan/projects/food-journal-assistant

Context:
- Spec: docs/superpowers/specs/2026-05-04-hearty-03-rest-api.md  (Sections 5.11–5.12)
- Plan: docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md

Before running any command, verify it exists with --help or equivalent.
If a step doesn't match what you find, stop and tell me — don't improvise.

Read the plan file, then execute Task 8.1.

When done:
- Mark Phase 8 status as 🟢 Completed in the plan file
- Commit: git add hearty-api/app/routers/health_profile.py docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md && git commit -m "feat: health profile endpoints"
- Tell me to run /compact
- Remind me that the next phase's Activation Prompt is at the top of Phase 9 in this plan file
```

---

### Task 8.1: Wire Spec 08's health_profile router into main.py

**Status:** 🔴 Not Started

> **Note:** The `health_profile` router is implemented in Spec 08 Phase 3 (`hearty-api/app/health_profile/router.py`), not here. By the time this phase runs, that router already exists. This task's only job is to mount it in `main.py` and smoke-test it.
> The execution order is: Spec 08 Phases 1–2 → Spec 03 Phases 1–2 → **Spec 08 Phases 3–5** → Spec 03 Phases 3+.
> If Spec 08 Phase 3 is not yet 🟢 Completed, stop and complete it before proceeding.

- [ ] Confirm `hearty-api/app/health_profile/router.py` exists and exports a `router` object.

- [ ] In `hearty-api/app/main.py`, add:
  ```python
  from app.health_profile import router as health_profile_router
  app.include_router(health_profile_router.router)
  ```

- [ ] Smoke test:
  ```bash
  curl -s -X PUT http://localhost:8000/api/health-profile \
    -H "Authorization: Bearer $TEST_JWT" \
    -H "Content-Type: application/json" \
    -d '{"allergens": [{"name": "peanuts", "severity": "mild"}]}'
  ```
  Expected: `200` with `HealthProfileResponse` showing the updated `allergens` array.

**Deviation Log:** _None_

---

## Phase 9: Photo Stubs

**Status:** 🔴 Not Started
**Goal:** Add `POST /api/photos` and `GET /api/photos/{id}/status` as stubs returning `501 Not Implemented`. These endpoints are owned by Spec 06 (AI Vision) — this phase ensures the routes are registered so the OpenAPI schema is complete, without implementing the pipelines.
**Depends on:** Phase 2 complete (auth middleware)

### Activation Prompt

```
You are implementing Phase 9 (Photo Stubs) of the Hearty REST API.

Working directory: /home/evan/projects/food-journal-assistant

Context:
- Spec: docs/superpowers/specs/2026-05-04-hearty-03-rest-api.md  (Sections 5.13–5.14)
- Plan: docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md

Before running any command, verify it exists with --help or equivalent.
If a step doesn't match what you find, stop and tell me — don't improvise.

Read the plan file, then execute Task 9.1.

When done:
- Mark Phase 9 status as 🟢 Completed in the plan file
- Commit: git add hearty-api/app/routers/photos.py docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md && git commit -m "feat: photo endpoint stubs (501 until Spec 06)"
- Tell me to run /compact
- Remind me that the next phase's Activation Prompt is at the top of Phase 10 in this plan file
```

---

### Task 9.1: Create photo router stubs

**Status:** 🔴 Not Started

- [ ] Create `hearty-api/app/routers/photos.py`:

  ```python
  # app/routers/photos.py
  # Photo processing is implemented in Spec 06 (AI Vision — Phase 4 roadmap).
  # These stubs register the routes in the OpenAPI schema and return 501 until Spec 06 is complete.
  from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
  from uuid import UUID
  from app.auth import get_current_user
  from app.models.schemas import PhotoUploadResponse, PhotoStatusResponse

  router = APIRouter()

  @router.post("/api/photos", status_code=202)
  async def upload_photo(
      file: UploadFile = File(...),
      type: str = Form(...),
      user=Depends(get_current_user)
  ) -> PhotoUploadResponse:
      raise HTTPException(status_code=501, detail="Photo upload not yet implemented. See Spec 06.")

  @router.get("/api/photos/{photo_id}/status")
  async def get_photo_status(
      photo_id: UUID,
      user=Depends(get_current_user)
  ) -> PhotoStatusResponse:
      raise HTTPException(status_code=501, detail="Photo status not yet implemented. See Spec 06.")
  ```

- [ ] Note in `food_lookup.py`: create a stub service file with a module-level docstring indicating it is implemented in Spec 07 (Food Intelligence):

  ```python
  # app/services/food_lookup.py
  # The tiered food lookup pipeline (barcode → DB → web → AI → fallback) is implemented
  # in Spec 07 (Food Intelligence — Phase 4 roadmap). This file is a placeholder.
  ```

- [ ] Wire `photos.router` into `main.py`.

**Deviation Log:** _None_

---

## Phase 10: Fly.io Deployment

**Status:** 🔴 Not Started
**Goal:** Deploy the `hearty-api` service to Fly.io free tier and verify the live `/health` endpoint.
**Depends on:** Phases 5–9 complete

### Activation Prompt

```
You are implementing Phase 10 (Fly.io Deployment) of the Hearty REST API.

Working directory: /home/evan/projects/food-journal-assistant/hearty-api

Context:
- Spec: docs/superpowers/specs/2026-05-04-hearty-03-rest-api.md  (Section 13)
- Plan: docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md

Before running any command, verify it exists with --help or equivalent.
If a step doesn't match what you find, stop and tell me — don't improvise.

Read the plan file, then execute Tasks 10.1 and 10.2 in order.

When all tasks are done:
- Mark Phase 10 status as 🟢 Completed in the plan file
- Commit: git add hearty-api/fly.toml docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md && git commit -m "feat: Fly.io deployment config"
- Tell me to run /compact
- Remind me that the next phase's Activation Prompt is at the top of Phase 11 in this plan file
```

---

### Task 10.1: Configure Fly.io

**Status:** 🔴 Not Started

- [ ] Verify Fly CLI is installed: `fly version`
  If missing, install per https://fly.io/docs/hands-on/install-flyctl/ and log in: `fly auth login`

- [ ] From `hearty-api/`, run the one-time setup:
  ```bash
  fly launch
  ```
  - App name: `hearty-api` (or `hearty-api-[username]` if taken)
  - Region: choose closest
  - Do **not** create a Postgres database (using Supabase instead)
  - This creates `fly.toml`

- [ ] Set all secrets from `.env` (never commit secrets; use Fly secrets):
  ```bash
  fly secrets set SUPABASE_URL="..." SUPABASE_SERVICE_KEY="..." ANTHROPIC_API_KEY="..." LLM_MODEL="claude-sonnet-4-6" SUPABASE_WEBHOOK_SECRET="..."
  ```
  Set any additional keys from `.env.example` that are needed.

**Deviation Log:** _None_

---

### Task 10.2: Deploy and verify

**Status:** 🔴 Not Started

- [ ] Create a minimal `Dockerfile` in `hearty-api/` if `fly launch` did not generate one:
  ```dockerfile
  FROM python:3.11-slim
  WORKDIR /app
  COPY requirements.txt .
  RUN pip install --no-cache-dir -r requirements.txt
  COPY . .
  CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
  ```
  Port 8080 is Fly.io's default internal port.

- [ ] Deploy:
  ```bash
  fly deploy
  ```
  Expected: `v1 deployed successfully`

- [ ] Verify live health endpoint:
  ```bash
  fly status
  curl https://hearty-api.fly.dev/health
  ```
  Expected: `{"status":"ok"}`

- [ ] Update `hearty-api/.env.example`: add `API_BASE_URL=https://hearty-api.fly.dev`

- [ ] Register the auth/on-login webhook in Supabase Dashboard with the live URL:
  `https://hearty-api.fly.dev/auth/on-login`

**Deviation Log:** _None_

---

## Phase 11: Integration Tests

**Status:** 🔴 Not Started
**Goal:** Write and run a set of integration tests against the live deployed API covering the core happy-path flows and key error cases.
**Depends on:** Phase 10 complete (live deployment available)

### Activation Prompt

```
You are implementing Phase 11 (Integration Tests) of the Hearty REST API.

Working directory: /home/evan/projects/food-journal-assistant

Context:
- Spec: docs/superpowers/specs/2026-05-04-hearty-03-rest-api.md
- Plan: docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md

Before running any command, verify it exists with --help or equivalent.
If a step doesn't match what you find, stop and tell me — don't improvise.

Read the plan file, then execute Tasks 11.0 through 11.2 in order.

When all tasks are done:
- Mark Phase 11 status as 🟢 Completed in the plan file
- Mark Plan Status as 🟢 Completed in the plan header
- Commit: git add hearty-api/tests/ docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md && git commit -m "test: REST API integration tests — plan complete"
- Tell me to run /compact
- Remind me that this plan is complete and the next spec to implement is Spec 04 (Android App)
```

---

### Task 11.0: Obtain a test JWT

**Status:** 🔴 Not Started

- [ ] Get a real Supabase JWT for a test user (needed by every test). Two options — use whichever works:

  **Option A — Sign in with supabase-py (requires a test user account):**
  ```bash
  cd hearty-api && source venv/bin/activate
  set -a && source .env && set +a
  python3 -c "
  from supabase import create_client
  import os
  sb = create_client(os.environ['SUPABASE_URL'], os.environ['SUPABASE_ANON_KEY'])
  session = sb.auth.sign_in_with_password({'email': 'testuser@example.com', 'password': 'testpassword'})
  print(session.session.access_token)
  "
  ```

  **Option B — Supabase Dashboard:**
  - Dashboard → Authentication → Users → select or create a test user
  - Use the "Generate link" option or sign in via Magic Link, then grab the `access_token` from the URL fragment

- [ ] Add `TEST_JWT=<the-token>` and `API_BASE_URL=https://hearty-api.fly.dev` to `hearty-api/.env`.
  (For local testing use `API_BASE_URL=http://localhost:8000`)

**Deviation Log:** _None_

---

### Task 11.1: Create test scaffolding

**Status:** 🔴 Not Started

- [ ] Create `hearty-api/tests/__init__.py` (empty).

- [ ] Create `hearty-api/tests/conftest.py`:
  - Loads `API_BASE_URL` and `TEST_JWT` from environment (set via `.env` + `set -a && source .env`)
  - Provides an `api_base` fixture (the base URL string) and a `headers` fixture with the Bearer token

- [ ] Add `pytest>=8.0.0` and `httpx>=0.27.0` to `requirements.txt` (test dependencies).

**Deviation Log:** _None_

---

### Task 11.2: Write and run integration tests

**Status:** 🔴 Not Started

- [ ] Create `hearty-api/tests/test_api.py` covering these cases:

  ```python
  # Happy paths
  test_health_check()                  # GET /health → 200
  test_log_meal()                      # POST /api/meals → 201, foods[] populated by AI
  test_log_meal_idempotency()          # POST /api/meals with same offline_id → 200, no duplicate
  test_query_meals()                   # GET /api/meals → 200, list includes the just-logged meal
  test_log_symptoms()                  # POST /api/symptoms → 201, list of SymptomResponse
  test_log_wellbeing()                 # POST /api/wellbeing → 201
  test_get_trends()                    # GET /api/trends → 200, TrendsResponse
  test_get_summary_week()              # GET /api/summary?period=week → 200, summary_text not empty
  test_export_json()                   # GET /api/export/json → 200, application/json
  test_export_csv()                    # GET /api/export/csv → 200, text/csv
  test_export_pdf()                    # POST /api/export/pdf → 200, application/pdf
  test_get_health_profile()            # GET /api/health-profile → 200
  test_update_health_profile()         # PUT /api/health-profile → 200, arrays updated

  # Error paths
  test_unauthenticated_request()       # GET /api/meals no token → 403
  test_invalid_token()                 # GET /api/meals bad token → 401
  test_summary_custom_missing_dates()  # GET /api/summary?period=custom → 422
  test_photo_stub()                    # POST /api/photos → 501
  ```

- [ ] Run tests against the live API:
  ```bash
  cd hearty-api && source venv/bin/activate
  set -a && source .env && set +a
  pytest tests/ -v
  ```
  Expected: all tests pass (or a clear failure report showing which ones need fixing).

**Deviation Log:** _None_

---

## Deviation Log

_Format: `[date] — Phase X, Task Y — changed X because Y`_

---

## Notes

- **Spec 08 cross-spec dependency:** Spec 08 (Health Profile) owns the `health_profile` Pydantic schemas and REST endpoints. This plan's Phase 3 (Auth Webhook) upserts blank `health_profile` rows — it does not depend on Spec 08's schemas, only on the table existing (Spec 01). This plan's Phase 8 (Health Profile Endpoints) wires Spec 08's router into `main.py`; the router itself is implemented in Spec 08 Phase 3. Execution order: Spec 08 Phases 1-2 → this plan Phases 1-2 → Spec 08 Phases 3-5 → this plan Phases 3+.

- **`food_lookup.py`** (spec Section 7, tiered food lookup pipeline) is Phase 4 roadmap work owned by Spec 07 (Food Intelligence). Phase 9 creates a stub file with an explanatory docstring. Do not implement the pipeline in this plan.

- **`POST /api/photos` and `GET /api/photos/{id}/status`** (spec Sections 5.13–5.14) are Phase 4 roadmap work owned by Spec 06 (AI Vision). Phase 9 registers the routes as 501 stubs so the OpenAPI schema is complete.

- **Scheduled trend analysis** (background job triggered daily, referenced in spec Section 8): the trend engine itself is implemented in Phase 6. The scheduler (Supabase Edge Function or Railway cron) is infrastructure outside this plan's scope — document in a future ops plan.

- **CORS policy**: `allow_origins=["*"]` is the spec default to support AI assistant tool use from arbitrary clients. If deploying with a known frontend domain, set `ALLOWED_ORIGINS` in `.env` and load it at startup per spec Section 10.

- **LiteLLM model string**: the default is `claude-sonnet-4-6`. Swap by setting `LLM_MODEL` in `.env` — no code changes needed. Supported out of the box: `gemini/gemini-2.0-flash`, `gpt-4o`, `ollama/llama3.3`.
