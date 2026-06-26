# Journal Symptom Edit/Delete — Design

**Status:** Approved (brainstorm 2026-06-26)
**Initiative:** Web dashboard (Spec 05) completion — surfaced by the web-roadmap memo (PR #24).
**Builds on:** existing `MealCard` meal edit/delete, the symptom REST endpoints (Spec 03).

## Goal

Let users **edit and delete symptoms** from the web Journal. Today the Journal shows symptoms as read-only chips inside each meal card; meals are already fully editable/deletable but symptoms are not — even though the backend `PATCH`/`DELETE /api/symptoms/{id}` endpoints and the `api.patchSymptom`/`deleteSymptom` client methods already exist (and are unit-tested). This feature wires that plumbing into the UI and adds one small backend field so a mis-classified symptom's type can be corrected.

**v1 scope:** edit (symptom_type, severity, onset_minutes, description) + delete for symptoms that appear in the Journal (i.e. symptoms attached to a meal via `meal_id`).

## Non-goals
- **Standalone (meal-less) symptoms.** The Journal query attaches symptoms by `meal_id`, so symptoms logged without a meal never appear in the Journal and remain out of reach here. Surfacing them is a separate, larger gap (changes the Journal data model) — deferred to a future spec.
- No changes to meal editing (already done: description + foods).
- No new symptom fields beyond what the table already has (no bathroom_urgency/visits/stool_consistency editing in v1 — keep the form small; can extend later).

## Architecture

### 1. Backend — allow editing `symptom_type` (small)
`hearty-api/app/routers/symptoms.py` `update_symptom` already updates `raw_description` (always) and optional `severity`/`onset_minutes`. Add `symptom_type`:
- `SymptomUpdateRequest` (pydantic schema, in `app/models/schemas.py`): add `symptom_type: str | None = None`.
- In `update_symptom`: `if body.symptom_type is not None: updates["symptom_type"] = body.symptom_type`.
- Ownership check (`.eq("user_id", ...)` + 404) and the rest are unchanged.

No validation enum on the backend in v1 (the frontend constrains via a dropdown; the column is free text today). Keep it permissive and consistent with the existing fields.

### 2. Web — shared symptom-type list
Today `Journal.tsx` hardcodes a 15-item `SYMPTOM_TYPES` subset that's missing real types (indigestion, upset_stomach, sour_stomach, gut_rot). Extract the **canonical** list to `hearty-web/src/lib/symptoms.ts` (`export const SYMPTOM_TYPES = [...]`) — the full set from the extraction prompt — and import it in both `Journal.tsx` (filter dropdown) and the new editor (so they agree).

### 3. Web — `SymptomRow` component
New `hearty-web/src/components/journal/SymptomRow.tsx`: renders one symptom with edit + delete, mirroring `MealCard`'s meal edit/delete idiom (local `editing`/`confirmDelete`/`busy`/`err` state; `useQueryClient` invalidation).
- **Read view:** `{symptom_type}{severity != null ? ` ${severity}` : ""}` + **Edit** and **Delete** buttons.
- **Edit view (inline):** `symptom_type` dropdown (from the shared list), `severity` number (1–10), `onset_minutes` number, `description` text; **Save** → `api.patchSymptom(id, { description, symptom_type, severity, onset_minutes })`; **Cancel** restores.
- **Delete:** two-step confirm ("Delete" → "Confirm delete" / "Cancel"), `api.deleteSymptom(id)`.
- On success: invalidate `["meals"]`, `["summary"]`, `["trends"]` (same set `MealCard` uses) so Journal, Dashboard, and signals refresh.

### 4. Web — `MealCard` integration
In the expanded panel (`open` section), add a **"Symptoms"** subsection listing `meal.symptoms` as `SymptomRow`s (when the meal has any). The collapsed-card symptom **chips stay unchanged** as the at-a-glance summary. `SymptomUpdateRequest` TS type gains `symptom_type?: string`.

## Data flow (edit a symptom)
1. User expands a meal card → sees the Symptoms subsection.
2. Clicks Edit on a symptom → inline form seeded from the symptom.
3. Save → `PATCH /api/symptoms/{id}` with the changed fields → on success, invalidate queries → Journal/Dashboard/Trends refetch and reflect the change.
4. Delete → confirm → `DELETE /api/symptoms/{id}` → invalidate.

## Error handling
- Per-row local `err` + `busy` state (mirrors `MealCard`): a failed save/delete shows an inline message and re-enables the controls; never throws to the page.
- Backend ownership check returns 404 for another user's symptom (already implemented).

## Security
- Symptom endpoints are `get_current_user`-scoped with an ownership check (`user_id == auth user`); editing `symptom_type` doesn't change that surface. No admin involvement.

## Testing
**Backend (pytest):** `update_symptom` persists `symptom_type` when provided and still works when omitted; ownership 404 unchanged.
**Web (Vitest + RTL + MSW):**
- `SymptomRow`: renders a symptom; Edit → change fields → Save sends a `PATCH` with the changed fields (incl. `symptom_type`); Delete → confirm → sends `DELETE`; error path shows a message.
- `MealCard`: the expanded panel renders a `SymptomRow` per symptom; existing MealCard/Journal tests stay green.

**Live (deploy-time):** redeploy backend (the symptom_type change) + web; on the Journal, edit a symptom's type/severity and confirm it persists + the dashboard reflects it; delete a symptom and confirm it disappears.

## Deferred (future)
Standalone (meal-less) symptom visibility in the Journal; editing the extended symptom fields (bathroom_urgency/visits/stool_consistency); bulk operations.
