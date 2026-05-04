# Hearty — AI Vision (Spec 06) — Living Plan

**Spec:** [`hearty-06-ai-vision.md`](../specs/2026-05-04-hearty-06-ai-vision.md)  
**Roadmap Phase:** Phase 4 — AI Vision  
**Plan Status:** 🔴 Not Started  
**Last Updated:** 2026-05-04  
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
| 0 | Review & Align | 🔴 Not Started | — | Claude (start of every session) |
| 1 | Upload Endpoint & Processing Scaffold | 🔴 Not Started | — | Claude |
| 2 | Food Plate Vision (Claude Vision API) | 🔴 Not Started | Phase 1 | Claude |
| 3 | Nutrition Label OCR | 🔴 Not Started | Phase 1 | Claude |
| 4 | Food Label OCR | 🔴 Not Started | Phase 1 | Claude |
| 5 | Barcode Flow & API Wiring | 🔴 Not Started | Phase 1 | Claude |
| 6 | Integration Test | 🔴 Not Started | Phases 1–5 | Claude |

---

## Phase 0: Review & Align

**Status:** 🔴 Not Started  
**Goal:** Verify the dev environment, confirm all dependency plans are complete, check the spec hasn't drifted from this plan, and identify exactly which phase to start or resume.  
**Run this phase at the start of every session on this plan.**

### Activation Prompt

```
You are running Phase 0 (Review & Align) for the Hearty AI Vision pipeline (Spec 06).
This runs at the start of every session — it takes 5 minutes and prevents
working from stale assumptions.

Working directory: /home/evan/projects/food-journal-assistant

Steps:

1. Read both files in full:
   - docs/superpowers/plans/2026-05-04-hearty-06-ai-vision-plan.md  (this plan)
   - docs/superpowers/specs/2026-05-04-hearty-06-ai-vision.md

2. Check dependency plan completion — read the Plan Status line from each:
   - docs/superpowers/plans/2026-05-04-hearty-01-database-plan.md
   - docs/superpowers/plans/2026-05-04-hearty-03-rest-api-plan.md
   Both must show Plan Status: 🟢 Completed before Phase 1 can begin.

3. Check the dev environment (run each command):
   - python3 --version   (need >= 3.11)
   - git status
   - ls backend/ 2>/dev/null && echo "FastAPI project exists" || echo "not yet created"

4. For the first upcoming non-zero phase (Phase 1), also verify:
   - Check that the Anthropic Python SDK is installed in the FastAPI project:
     (run: cd backend && python3 -c "import anthropic; print(anthropic.__version__)" 2>/dev/null
     or equivalent; note the path may differ if the FastAPI project directory has a different name)
   - Check that google-cloud-vision is installed:
     (run: python3 -c "import google.cloud.vision; print('ok')" 2>/dev/null)
   - Check that the Supabase Storage bucket "photos" exists (see Spec 01 plan Phase 4);
     if not, note it as a blocker for Phase 1
   - Check that food_log_photos table exists:
     (this was created in Spec 01 migration; confirm from Spec 01 plan Phase 2 status)

5. Spec drift check — the plan was written on 2026-05-04. Scan the spec for any
   changes to: photo types, processing pipeline, API endpoints, error handling table,
   vision model names. If you find anything that conflicts with this plan, list it.

6. Report:
   - Dependency plans: which are complete, which are not
   - Environment: what is/isn't installed or configured
   - Storage bucket and food_log_photos table: present or blocked
   - Spec alignment: any drift found, or "clean"
   - Next action: which phase to proceed with (or what to fix/unblock first)

Before running any command, verify it exists with --help or equivalent.
If a command doesn't behave as expected, stop and tell me — don't improvise.

Update the plan: set Phase 0 status to 🟢 Completed and Last Updated to today.
```

**Deviation Log:** _None_

---

## Phase 1: Upload Endpoint & Processing Scaffold

**Status:** 🔴 Not Started  
**Goal:** Implement `POST /api/photos` (multipart upload to Supabase Storage), the `food_log_photos` write with initial `processing` status, and the FastAPI `BackgroundTasks` worker scaffold — so all four processors in Phases 2–5 plug into the same queue/status pattern.  
**Depends on:** Spec 01 plan complete (food_log_photos table and photos storage bucket exist); Spec 03 plan complete (FastAPI project exists)  
**Type:** Claude

**Key deliverables:**
- `POST /api/photos` endpoint: accepts multipart image upload (JPEG/PNG, max 10 MB enforced at API layer); validates file type; uploads to Supabase Storage at `{user_id}/{photo_id}.jpg`
- Writes initial row to `food_log_photos`: `photo_id`, `user_id`, `storage_path`, `photo_type` (from client or null for auto-classify), `status: "processing"`
- FastAPI `BackgroundTasks` worker entry point: `process_photo(photo_id, photo_type, user_id)` dispatches to per-type processor based on `photo_type`; updates `status` to `"complete"` / `"error"` / `"needs_input"` / `"timeout"` on completion
- Auto-classification via Claude: if `photo_type` is null, sends low-cost classification prompt (spec Section 2.1); sets `status: "needs_input"` if ambiguous, defaults to `food_plate` if classification fails entirely
- `GET /api/photos/{photo_id}/status` endpoint: returns current `status` and `extracted_data` (null while processing)
- `POST /api/photos/{photo_id}/retry` endpoint: resets status to `"processing"` and re-enqueues the job
- 30-second processing timeout: if worker exceeds this, sets `status: "timeout"`
- Error handling table from spec Section 7 implemented for all defined conditions

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 2: Food Plate Vision (Claude Vision API)

**Status:** 🔴 Not Started  
**Goal:** Implement the food plate processor: send the photo to Claude Vision API (`claude-sonnet-4-6`) with the spec-defined prompt, parse the JSON array response, and write identified food items to `food_log_photos.extracted_data`.  
**Depends on:** Phase 1  
**Type:** Claude

**Key deliverables:**
- `processors/food_plate.py` — retrieves image from Supabase Storage, sends to Claude (`claude-sonnet-4-6`) with exact prompt from spec Section 3.1
- Response parsed into the spec's array structure: `[{"name", "portion", "confidence"}]`; no calorie data generated at this stage
- Ambiguous/empty image handling per spec Section 3.3: mixed dish → best-effort; no food → empty array; blurry → `status: "error"`
- Result written to `food_log_photos.extracted_data`; cache check before Claude call (if `extracted_data` already populated and `status == "complete"`, return cached result without re-calling Claude)
- Each identified food item passed to Spec 07 Food Intelligence pipeline for nutritional lookup (via `POST /api/food/lookup`); enriched results stored alongside raw vision output

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 3: Nutrition Label OCR

**Status:** 🔴 Not Started  
**Goal:** Implement the nutrition label processor: OCR the image via Google Cloud Vision API (`DOCUMENT_TEXT_DETECTION`), extract structured nutrition facts via Claude, and write the parsed nutrition object to `food_log_photos.extracted_data`.  
**Depends on:** Phase 1  
**Type:** Claude

**Key deliverables:**
- `processors/nutrition_label.py` — retrieves image from Supabase Storage; calls Google Cloud Vision `DOCUMENT_TEXT_DETECTION`
- Raw OCR text passed to Claude with exact extraction prompt from spec Section 4.2; returns the full nutrition facts schema (serving size, calories, macros, vitamins/minerals — all fields nullable)
- Format support: US FDA panel (primary), Canadian bilingual (English values used), EU declarations (kJ/kcal mapping), Supplement facts panels
- Parsed result written to `food_log_photos.extracted_data` with `source: "nutrition_label_ocr"`; attached to meal's `foods` JSONB array as a single food item
- OCR returns no text → `status: "error"` with appropriate message from error table

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 4: Food Label OCR

**Status:** 🔴 Not Started  
**Goal:** Implement the food label/packaging processor: OCR via Google Cloud Vision, extract product name, brand, ingredients, and allergen warnings via Claude, then feed product identity into the Spec 07 Tier 2 pipeline for nutritional lookup.  
**Depends on:** Phase 1  
**Type:** Claude

**Key deliverables:**
- `processors/food_label.py` — retrieves image; calls Google Cloud Vision `TEXT_DETECTION` (lighter mode than DOCUMENT_TEXT_DETECTION, sufficient for packaging text)
- Raw text passed to Claude with exact extraction prompt from spec Section 5.2; extracts `product_name`, `brand`, `ingredients` array, `allergen_warnings` array
- `product_name` + `brand` forwarded to Spec 07 Food Intelligence at Tier 2 entry point (`POST /api/food/lookup` with `type: "name"`)
- Extracted object stored in `food_log_photos.extracted_data` per spec Section 5.3 structure
- Allergen warnings cross-referenced against user health profile (this cross-reference is handled by the Spec 07 pipeline; the label processor passes allergen data through)

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 5: Barcode Flow & API Wiring

**Status:** 🔴 Not Started  
**Goal:** Wire the client-side barcode scan (decoded on-device by `mobile_scanner`) into the server-side pipeline: validate that `POST /api/food/lookup` with `type: "barcode"` routes correctly to Spec 07 Tier 1, and confirm no server-side barcode decoding is needed.  
**Depends on:** Phase 1  
**Type:** Claude

**Key deliverables:**
- Confirm `POST /api/photos/barcode` (or `POST /api/food/lookup` with `type: "barcode"`) endpoint exists and accepts raw barcode string from the Flutter client
- No image upload to Supabase Storage required for barcode-only flows — document this clearly in the API
- Barcode string forwarded directly to Spec 07 Tier 1 lookup pipeline; response returned to client
- If the user took a photo in addition to scanning the barcode, the photo is stored normally via `POST /api/photos` but photo processing is skipped for the `food_log_photos` row (marked `complete` with `source: "barcode_scan"`)
- End-to-end test: scan a known EAN-13/UPC-A barcode → confirm Tier 1 returns product data

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Phase 6: Integration Test

**Status:** 🔴 Not Started  
**Goal:** Run integration tests for all four photo types against a live environment, confirm error handling, verify cost-control caching, and confirm the full pipeline from upload to structured data in `food_log_photos`.  
**Depends on:** Phases 1–5  
**Type:** Claude

**Key deliverables:**
- Food plate: upload a photo of a recognizable meal → confirm `extracted_data` contains food array with `name`, `portion`, `confidence`; re-upload same photo → confirm cached result returned without second Claude Vision call
- Nutrition label: upload a clear nutrition label photo → confirm parsed nutrition facts schema with at least calories, macros populated
- Food label: upload a packaged food photo → confirm product name, brand, and ingredients extracted; allergen warnings returned if applicable
- Barcode: submit a known EAN-13 barcode string → confirm Tier 1 lookup returns product name and nutrition data
- Error cases: blurry image → `status: "error"` with correct message; processing exceeds 30s mock → `status: "timeout"`; retry endpoint resets and reprocesses successfully
- `GET /api/photos/{photo_id}/status` polling returns correct status transitions: `processing` → `complete`

_Tasks and activation prompt will be written at the start of this phase using current spec and dependency state._

**Deviation Log:** _None_

---

## Deviation Log

_Format: `[date] — Phase X, Task Y — changed X because Y`_

---

## Notes

- **Google Cloud Vision API key:** `GOOGLE_CLOUD_VISION_API_KEY` (or service account credentials) must be configured in the FastAPI project's environment before Phase 3 or Phase 4 can succeed. This is a manual setup step outside of Claude's scope.
- **`ANTHROPIC_API_KEY`:** Must be set in the FastAPI environment for Phase 2 (food plate) and auto-classification. Assumed to exist from Spec 03 work.
- **Celery upgrade path:** The spec notes FastAPI `BackgroundTasks` as the primary worker with Celery as a scale upgrade. This plan implements `BackgroundTasks` only. A Celery migration would be a separate plan.
- **Cost control:** Claude Vision caching is implemented in Phase 2 (do not re-send a photo to Claude if `extracted_data` is already populated). Google Cloud Vision costs are per image; no caching is needed as OCR results are stored in `food_log_photos`.
- **Spec 07 dependency:** Phases 2, 4, and 5 forward data to the Spec 07 Food Intelligence pipeline. Those phases will produce partial results (food identification without nutrition data) if Spec 07 is not yet deployed. The pipeline is designed to be non-blocking — partial results are valid.
