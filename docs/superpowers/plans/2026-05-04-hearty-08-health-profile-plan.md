# Hearty — Health Profile (Spec 08) — Living Plan

**Spec:** [`hearty-08-health-profile.md`](../specs/2026-05-04-hearty-08-health-profile.md)
**Roadmap Phase:** Phase 1 — Foundation
**Plan Status:** 🟡 In Progress
**Last Updated:** 2026-05-05 (Phase 1 complete)
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
| 1 | Canonical Lists / Constants | 🟢 Completed | Phase 0 | Claude |
| 2 | JSONB Validation Schemas | 🔴 Not Started | Phase 1 | Claude |
| 3 | REST API Endpoints | 🔴 Not Started | Phase 2 | Claude |
| 4 | Health Profile Context Injection | 🔴 Not Started | Phase 3 | Claude |
| 5 | Integration Tests | 🔴 Not Started | Phases 1–4 | Claude |

---

## Phase 0: Review & Align

**Status:** 🟢 Completed
**Goal:** Confirm Spec 01 (Database) is complete and the `health_profile` table exists; verify this spec hasn't drifted from this plan; identify exactly which phase to start or resume.
**Run this phase at the start of every session on this plan.**

### Activation Prompt

```
You are running Phase 0 (Review & Align) for the Hearty Health Profile implementation.
This runs at the start of every session — it takes 5 minutes and prevents working from
stale assumptions.

Working directory: /home/evan/projects/food-journal-assistant

Steps:
1. Read both files in full:
   - docs/superpowers/plans/2026-05-04-hearty-08-health-profile-plan.md
   - docs/superpowers/plans/2026-05-04-hearty-01-database-plan.md

2. Confirm Spec 01 plan is marked 🟢 Completed in its header. The health_profile table
   must exist in the database before this plan can proceed. If Spec 01 is not complete,
   stop here and report that it must be finished first.

3. Verify the health_profile table exists in Supabase (run a quick schema check):
   supabase db execute --sql "SELECT column_name FROM information_schema.columns WHERE table_name = 'health_profile' ORDER BY column_name;"
   Expected columns: allergens, conditions, created_at, dietary_protocols, id, intolerances, updated_at, user_id
   If any column is missing, stop and report the gap.

4. Read the spec:
   - docs/superpowers/specs/2026-05-04-hearty-08-health-profile.md

5. Spec drift check — this plan was written on 2026-05-04. Scan the spec for any changes
   to: JSONB shapes (§2.1–2.4), severity enum values (§2.1), the Big 9 list (§3.1),
   intolerance list (§4), condition list (§5), protocol list (§6), or API endpoint list
   (§10.1). If you find anything that conflicts with the plan's task steps, list it.

6. Check git status and the dev environment:
   - git status
   - python --version  (need >= 3.11)
   - ls .env 2>/dev/null && echo "exists" || echo "missing"

7. Report:
   - Spec 01 plan status: complete or not
   - health_profile table: present or missing columns
   - Spec alignment: any drift found, or "clean"
   - Environment: what is/isn't in place
   - Next action: which phase to proceed with (or what to fix first)

Before running any command, verify it exists with --help or equivalent. If a step doesn't match what you find, stop and tell me — don't improvise.

Update the plan: set Phase 0 status to 🟢 Completed and Last Updated to today's date.
Commit: git add docs/superpowers/plans/2026-05-04-hearty-08-health-profile-plan.md && git commit -m "docs: health profile plan — phase 0 complete"
Tell me to run /compact.
Remind me that Phase 1's Activation Prompt is at the top of Phase 1 in this plan file.
```

**Deviation Log:** Extra `notes TEXT` column exists on `health_profile` table (from initial migration) — not in spec §2 CREATE TABLE, benign, ignored.

---

## Phase 1: Canonical Lists / Constants

**Status:** 🟢 Completed
**Goal:** Create a constants module that captures the well-known default lists from the spec (Big 9 allergens, common intolerances, common conditions, common dietary protocols). These are the "quick-select defaults" surfaced to the user during onboarding and in the settings UI — not seed rows in the database.
**Depends on:** Phase 0 complete

### Activation Prompt

```
You are implementing Phase 1 (Canonical Lists / Constants) of the Hearty Health Profile.

Working directory: /home/evan/projects/food-journal-assistant

Context:
- Spec: docs/superpowers/specs/2026-05-04-hearty-08-health-profile.md
- Plan: docs/superpowers/plans/2026-05-04-hearty-08-health-profile-plan.md

Read the plan file in full, then execute Tasks 1.1 through 1.2 in order.

Before running any command, verify it exists with --help or equivalent. If a step doesn't match what you find, stop and tell me — don't improvise.

When all tasks are done:
- Mark Phase 1 status as 🟢 Completed in the plan file
- Commit all new files: git add <files> && git commit -m "feat: add health profile canonical constants"
- Tell me to run /compact
- Remind me that Phase 2's Activation Prompt is at the top of Phase 2 in this plan file
```

---

### Task 1.1: Locate or create the constants module

**Status:** 🟢 Completed

- [ ] `<app_root>` is `hearty-api/app/` (established in Phase 0 deviation log — no FastAPI backend existed at plan start; Spec 03 Phase 1 will create the sibling directories). Create the health_profile package:
  ```bash
  mkdir -p hearty-api/app/health_profile
  touch hearty-api/app/health_profile/__init__.py
  ```
- [ ] Create `hearty-api/app/health_profile/constants.py`
- [ ] The module must export four lists of strings, matching exactly what the spec defines:
  - `BIG_9_ALLERGENS` — the 9 FASTER Act allergens from spec §3.1 (normalised names): `"milk"`, `"eggs"`, `"fish"`, `"shellfish"`, `"tree nuts"`, `"peanuts"`, `"wheat"`, `"soybeans"`, `"sesame"`
  - `COMMON_INTOLERANCES` — the 12 items from spec §4 (use the spec's exact name strings)
  - `COMMON_CONDITIONS` — the 14 conditions from spec §5 (use the spec's exact condition-name strings, e.g. `"IBS-C"`, `"IBS-D"`, `"Crohn's disease"`, etc.)
  - `COMMON_DIETARY_PROTOCOLS` — the 12 protocols from spec §6 (use the spec's exact protocol-name strings, e.g. `"Low-FODMAP"`, `"Elimination diet"`, etc.)
- [ ] Names only in this module — no display labels, descriptions, or notes; the UI layer handles those

**Deviation Log:** _None_

---

### Task 1.2: Expose constants via a read-only API endpoint

**Status:** 🟢 Completed

- [ ] Add `GET /api/health-profile/defaults` endpoint that returns all four lists as JSON:
  ```json
  {
    "allergens": [...],
    "intolerances": [...],
    "conditions": [...],
    "dietary_protocols": [...]
  }
  ```
- [ ] This endpoint does **not** require authentication — it returns static reference data only
- [ ] Add a docstring noting this is the canonical source of quick-select options for onboarding and settings UI
- [ ] Smoke-check: call the endpoint and verify all four keys are present and non-empty

**Deviation Log:** _None_

---

## Phase 2: JSONB Validation Schemas

**Status:** 🔴 Not Started
**Goal:** Define Pydantic models for the four JSONB shapes from spec §2.1–2.4. These models are used by the REST API layer (Phase 3) to validate incoming data and by the context-injection helper (Phase 4) to serialise outgoing data.
**Depends on:** Phase 1 complete

### Activation Prompt

```
You are implementing Phase 2 (JSONB Validation Schemas) of the Hearty Health Profile.

Working directory: /home/evan/projects/food-journal-assistant

Context:
- Spec: docs/superpowers/specs/2026-05-04-hearty-08-health-profile.md (focus on §2.1–2.4)
- Plan: docs/superpowers/plans/2026-05-04-hearty-08-health-profile-plan.md

Read the plan file in full, then execute Tasks 2.1 through 2.2 in order.

Before running any command, verify it exists with --help or equivalent. If a step doesn't match what you find, stop and tell me — don't improvise.

When all tasks are done:
- Mark Phase 2 status as 🟢 Completed in the plan file
- Commit: git add <files> && git commit -m "feat: add health profile Pydantic validation schemas"
- Tell me to run /compact
- Remind me that Phase 3's Activation Prompt is at the top of Phase 3 in this plan file
```

---

### Task 2.1: Define the four entry models

**Status:** 🔴 Not Started

- [ ] Create `<app_root>/health_profile/schemas.py` (confirm location fits existing layout)
- [ ] Define `SeverityEnum` with values `mild`, `moderate`, `severe` (from spec §2.1)
- [ ] Define `AllergenEntry` model (from spec §2.1):
  - `name: str`
  - `severity: SeverityEnum`
  - `reaction: str | None = None`
  - `confirmed_by_doctor: bool = False`
  - `notes: str | None = None`
- [ ] Define `IntoleranceEntry` model (from spec §2.2):
  - `name: str`
  - `severity: SeverityEnum | None = None`
  - `threshold: str | None = None`
  - `notes: str | None = None`
- [ ] Define `ConditionEntry` model (from spec §2.3):
  - `name: str`
  - `diagnosed: bool = False`
  - `diagnosis_year: int | None = None`
  - `notes: str | None = None`
- [ ] Define `DietaryProtocolEntry` model (from spec §2.4):
  - `name: str`
  - `active: bool = True`
  - `started: str | None = None`  (ISO 8601 date string — validate format)
  - `phase: str | None = None`
  - `notes: str | None = None`

**Deviation Log:** _None_

---

### Task 2.2: Define the top-level profile request and response models

**Status:** 🔴 Not Started

- [ ] Define `HealthProfileResponse` — all four arrays plus `updated_at: datetime`
- [ ] Define `HealthProfilePutRequest` — all four arrays required (full replace)
- [ ] Define `HealthProfilePatchRequest` — all four arrays optional (partial update)
- [ ] Define sub-resource request models for the individual field endpoints (spec §10.1):
  - `AllergensUpdateRequest` — `allergens: list[AllergenEntry]`
  - `IntolerancesUpdateRequest` — `intolerances: list[IntoleranceEntry]`
  - `ConditionsUpdateRequest` — `conditions: list[ConditionEntry]`
  - `DietaryProtocolsUpdateRequest` — `dietary_protocols: list[DietaryProtocolEntry]`
- [ ] All models must tolerate an empty list `[]` — no field in the profile is required

**Deviation Log:** _None_

---

## Phase 3: REST API Endpoints

**Status:** 🔴 Not Started
**Goal:** Implement all 12 REST endpoints defined in spec §10.1. All endpoints require `Authorization: Bearer <supabase_jwt>` and enforce RLS via the authenticated user context.
**Depends on:** Phase 2 complete

### Activation Prompt

```
You are implementing Phase 3 (REST API Endpoints) of the Hearty Health Profile.

Working directory: /home/evan/projects/food-journal-assistant

Context:
- Spec: docs/superpowers/specs/2026-05-04-hearty-08-health-profile.md (focus on §10.1)
- Plan: docs/superpowers/plans/2026-05-04-hearty-08-health-profile-plan.md

Read the plan file in full, then execute Tasks 3.1 through 3.3 in order.

Before running any command, verify it exists with --help or equivalent. If a step doesn't match what you find, stop and tell me — don't improvise.

When all tasks are done:
- Mark Phase 3 status as 🟢 Completed in the plan file
- Commit: git add <files> && git commit -m "feat: implement health profile REST endpoints"
- Tell me to run /compact
- Remind me that Phase 4's Activation Prompt is at the top of Phase 4 in this plan file
```

---

### Task 3.1: Router setup and shared auth dependency

**Status:** 🔴 Not Started

> **Depends on Spec 03 Phase 2 (Auth & JWT Middleware)** — the auth dependency pattern (`get_current_user` or equivalent) is defined there. Do not start this task until Spec 03 Phase 2 is 🟢 Completed. `<app_root>` = `hearty-api/app/`.

- [ ] Create `hearty-api/app/health_profile/router.py`
- [ ] Register a FastAPI `APIRouter` with prefix `/api/health-profile`
- [ ] Confirm the existing auth dependency pattern (how other routes extract the authenticated user from the JWT — defined in Spec 03 Phase 2) — use the same approach; do not invent a new one
- [ ] Apply the auth dependency at router level so all endpoints in this router require authentication (the `GET /api/health-profile/defaults` endpoint from Phase 1 is separate and unauthenticated)
- [ ] Wire `health_profile.router` into `hearty-api/app/main.py`

**Deviation Log:** _None_

---

### Task 3.2: Top-level profile endpoints

**Status:** 🔴 Not Started

Implement the four top-level endpoints from spec §10.1:

- [ ] `GET /api/health-profile` — return the user's full profile row (all four arrays + `updated_at`) via `HealthProfileResponse`; if no row exists yet, return empty arrays with a 200 (the row is normally auto-created by the on-login webhook defined in Spec 03, but handle the missing-row case gracefully — not a 404). **Do not expose the `notes TEXT` column** — it exists in the DB table (see Phase 0 deviation log) but is not part of the spec §2 data model and is not included in `HealthProfileResponse`. The MCP server (`context.ts`) uses it separately.
- [ ] `PUT /api/health-profile` — full replace: validate all four arrays with `HealthProfilePutRequest`; upsert the row; update `updated_at`
- [ ] `PATCH /api/health-profile` — partial update: validate present fields only with `HealthProfilePatchRequest`; merge into existing row; update `updated_at`
- [ ] `DELETE /api/health-profile` — reset: set all four arrays back to `[]`; do not delete the row itself (per spec §7 rules: empty profile row is kept for future use)

**Deviation Log:** _None_

---

### Task 3.3: Sub-resource endpoints

**Status:** 🔴 Not Started

Implement the eight sub-resource endpoints from spec §10.1:

- [ ] `GET /api/health-profile/allergens` — return `allergens` array only
- [ ] `PUT /api/health-profile/allergens` — replace `allergens` array; validate with `AllergensUpdateRequest`; update `updated_at`
- [ ] `GET /api/health-profile/intolerances` — return `intolerances` array only
- [ ] `PUT /api/health-profile/intolerances` — replace `intolerances` array; validate with `IntolerancesUpdateRequest`; update `updated_at`
- [ ] `GET /api/health-profile/conditions` — return `conditions` array only
- [ ] `PUT /api/health-profile/conditions` — replace `conditions` array; validate with `ConditionsUpdateRequest`; update `updated_at`
- [ ] `GET /api/health-profile/dietary-protocols` — return `dietary_protocols` array only
- [ ] `PUT /api/health-profile/dietary-protocols` — replace `dietary_protocols` array; validate with `DietaryProtocolsUpdateRequest`; update `updated_at`

**Deviation Log:** _None_

---

## Phase 4: Health Profile Context Injection

**Status:** 🔴 Not Started
**Goal:** Implement the helper that formats a user's health profile row into the system-prompt text block defined in spec §9.1. Both the MCP Server (Spec 02) and FastAPI trend/summary endpoints (Spec 03) will call this helper.
**Depends on:** Phase 3 complete

### Activation Prompt

```
You are implementing Phase 4 (Health Profile Context Injection) of the Hearty Health Profile.

Working directory: /home/evan/projects/food-journal-assistant

Context:
- Spec: docs/superpowers/specs/2026-05-04-hearty-08-health-profile.md (focus on §9.1 and §9.2)
- Plan: docs/superpowers/plans/2026-05-04-hearty-08-health-profile-plan.md

Read the plan file in full, then execute Tasks 4.1 through 4.2 in order.

Before running any command, verify it exists with --help or equivalent. If a step doesn't match what you find, stop and tell me — don't improvise.

When all tasks are done:
- Mark Phase 4 status as 🟢 Completed in the plan file
- Commit: git add <files> && git commit -m "feat: add health profile context injection helper"
- Tell me to run /compact
- Remind me that Phase 5's Activation Prompt is at the top of Phase 5 in this plan file
```

---

### Task 4.1: Implement the context-formatting helper

**Status:** 🔴 Not Started

- [ ] Create `<app_root>/health_profile/context.py`
- [ ] Implement `def build_health_profile_context(profile: HealthProfileResponse) -> str` that produces a string matching the format shown in spec §9.1:
  - Header line: `User health profile:`
  - One bullet per non-empty domain, formatted as:
    - Allergens: `name (severity, confirmed)` for confirmed entries, `name (severity)` otherwise
    - Intolerances: `name (threshold)` if threshold set, `name` otherwise
    - Conditions: `name (diagnosed YYYY)` if `diagnosis_year` set, `name` otherwise
    - Dietary protocols: `name phase (started DATE)` if active and phase/date set, `name` otherwise
  - Followed by a `When analyzing meals and symptoms:` block with condition-specific and protocol-specific instructions drawn from spec §3.2, §5.1, and §6.1 — include only bullets for conditions and protocols actually present in the profile
- [ ] If the entire profile is empty (all four arrays empty), return `""` so callers can skip injecting context rather than inject an empty block
- [ ] Do not invent AI behaviours beyond what is enumerated in spec §3.2, §5.1, and §6.1

**Deviation Log:** _None_

---

### Task 4.2: Wire up callers

**Status:** 🔴 Not Started

- [ ] In the FastAPI `/api/trends` and `/api/summary` route handlers (wherever they currently live — confirm before editing), add a call to `build_health_profile_context` and pass the result as context when calling the Claude API. If these endpoints do not exist yet (Spec 03 may not be implemented), leave a clearly labelled stub comment at the call site so the Spec 03 implementer knows exactly what to add.
- [ ] Add a comment in `context.py` noting that the MCP Server's `get_health_profile` tool (Spec 02) should also call this function — do not implement the MCP tool here; it lives in the Spec 02 plan.

**Deviation Log:** _None_

---

## Phase 5: Integration Tests

**Status:** 🔴 Not Started
**Goal:** Verify the full stack end-to-end: CRUD round-trips work, RLS isolates profiles between users, Pydantic validation rejects bad shapes, and the context-injection helper produces the correct output format.
**Depends on:** Phases 1–4 complete

### Activation Prompt

```
You are implementing Phase 5 (Integration Tests) of the Hearty Health Profile.

Working directory: /home/evan/projects/food-journal-assistant

Context:
- Spec: docs/superpowers/specs/2026-05-04-hearty-08-health-profile.md
- Plan: docs/superpowers/plans/2026-05-04-hearty-08-health-profile-plan.md

Read the plan file in full, then execute Tasks 5.1 through 5.3 in order.

Before running any command, verify it exists with --help or equivalent. If a step doesn't match what you find, stop and tell me — don't improvise.

When all tasks are done:
- Mark Phase 5 status as 🟢 Completed in the plan file
- Mark Plan Status as 🟢 Completed in the plan header
- Commit: git add docs/superpowers/plans/ <test files> && git commit -m "feat: health profile integration tests; plan complete"
- Tell me to run /compact
- Remind me that this spec is complete and the next relevant plans are Spec 02 (MCP Server) and Spec 03 (REST API), depending on what is next in the roadmap.
```

---

### Task 5.1: CRUD round-trip tests

**Status:** 🔴 Not Started

Confirm which test framework is in use (pytest is expected) before writing any tests.

- [ ] Test `GET /api/health-profile` returns empty defaults when no data has been set
- [ ] Test `PUT /api/health-profile` with a full valid payload returns 200 and the stored data matches
- [ ] Test `PATCH /api/health-profile` with one field updates only that field; other fields are unchanged
- [ ] Test `DELETE /api/health-profile` resets all arrays to `[]` without deleting the row
- [ ] Test `PUT /api/health-profile/allergens` with a valid allergen list round-trips correctly
- [ ] Test `PUT /api/health-profile/allergens` with an invalid severity value (e.g. `"extreme"`) returns 422
- [ ] Test a `DietaryProtocolEntry` with a non-date string in `started` returns 422

**Deviation Log:** _None_

---

### Task 5.2: RLS isolation test

**Status:** 🔴 Not Started

- [ ] Create two test users (User A and User B) using service-role credentials
- [ ] Set allergens for User A via `PUT /api/health-profile/allergens` authenticated as User A
- [ ] Attempt `GET /api/health-profile` authenticated as User B — verify the response is empty (User A's profile is not visible)
- [ ] Clean up test user rows after the test

**Deviation Log:** _None_

---

### Task 5.3: Context-injection helper unit tests

**Status:** 🔴 Not Started

- [ ] Test `build_health_profile_context` with an empty profile returns `""` (empty string)
- [ ] Test with one allergen (severity `severe`, `confirmed_by_doctor=True`) — verify output matches the §9.1 example format
- [ ] Test with allergens + conditions + protocols set — verify each section appears in the output and the `When analyzing meals and symptoms:` block is appended
- [ ] Test with intolerances only (no allergens, no conditions, no protocols) — verify the `When analyzing meals and symptoms:` block is **not** appended. Rationale: spec §9.1 enumerates AI behaviours only for allergens (§3.2), conditions (§5.1), and protocols (§6.1); intolerances have no enumerated AI instruction block in the spec.

**Deviation Log:** _None_

---

## Deviation Log

_Format: `[date] — Phase X, Task Y — changed X because Y`_

[2026-05-05] — Phase 0 — `health_profile` table has extra `notes TEXT` column (from migration); not in spec §2; benign.
[2026-05-05] — Phase 0 — No FastAPI backend (`hearty-api/`) exists yet; `<app_root>` = `hearty-api/app/`; Phase 1 Task 1.1 will create the directory structure.
[2026-05-05] — Phase 1, Task 1.2 — Smoke-check (live endpoint call) deferred: no `main.py` exists until Spec 03 Phase 1. Verified instead by direct import and function call confirming all four keys present and non-empty.

---

## Notes

- **Execution ordering (cross-spec dependency):** Phases 1-2 of this plan (constants + Pydantic schemas) create standalone Python modules that do not require a running FastAPI app — run them first. Then run Spec 03 Phases 1-2 (FastAPI project setup + auth middleware). Then return to this plan for Phases 3-5 (REST endpoints, context injection, tests), which require Spec 03 Phase 2's auth pattern to be in place.
- The `health_profile` table is defined in Spec 01 (Database). This plan owns only the JSONB shapes inside that table and the API/logic around them. Do not re-define the table structure here.
- The `health_profile` row is auto-created on first login via the `/auth/on-login` webhook defined in Spec 03. Phase 3 of this plan handles the missing-row case gracefully but does not implement the webhook — that lives in the Spec 03 plan.
- REST endpoint implementation lives in this plan because the data shapes originate here. The Spec 03 (REST API) plan will reference these endpoints as already-implemented rather than re-implementing them.
- The MCP Server's `get_health_profile` tool (spec §10.2) is defined in Spec 02. Phase 4 of this plan provides the formatting helper the MCP tool will call; it does not implement the tool itself.
- The onboarding flow UI (spec §7) and the Settings → Health Profile page (spec §10.3) are frontend concerns. They live in the Spec 04 (Android) and Spec 05 (Web Dashboard) plans respectively.
- JSONB shapes are not enforced at the database level — Postgres accepts any valid JSON. Severity-enum validation and required-key checks are enforced by the Pydantic models added in Phase 2.
- **`GET /api/health-profile/defaults` (Phase 1, Task 1.2):** This endpoint is not listed in spec §10.1. It is added here because the onboarding flow (§7) and settings UI (§10.3) need a server-side source of truth for quick-select chips (Big 9, intolerances, conditions, protocols). It is intentionally unauthenticated and returns only static reference data. If the decision is made to ship these lists with the frontend bundle instead, Task 1.2 can be dropped without affecting any other phase.
