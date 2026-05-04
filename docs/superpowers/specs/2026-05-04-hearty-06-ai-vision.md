# Hearty — Spec 06: AI Vision

**Version:** 1.0
**Date:** 2026-05-04
**Status:** Active
**Phase:** 4

---

## 1. Overview

Phase 4 (vision portion) adds the ability to submit photos as meal log input. Users capture a photo in the Flutter app; the backend processes it asynchronously, extracts structured data, and attaches the result to the meal record. Four photo types are supported, each routed through a different processing path:

| Photo Type | Processing Method | Output |
|---|---|---|
| Food plate | Claude Vision API (claude-sonnet-4-6) | Array of identified foods with portion descriptions (no calorie estimates) |
| Barcode | ML Kit scan on device → Spec 07 lookup | Product nutrition data |
| Nutrition label | OCR → structured macros | Full nutrition facts object |
| Food label / packaging | OCR → Spec 07 lookup | Product name, brand, ingredients |

Processing is asynchronous — the photo is stored immediately, the job is queued, and the app either polls for status or receives a push notification when complete.

---

## 2. Photo Processing Pipeline

```
User submits photo
       │
       ▼
POST /api/photos (multipart upload)
       │
       ▼
Supabase Storage: bucket "photos" (private, user-scoped path: {user_id}/{uuid}.jpg)
photo_id + "processing" status written to food_log_photos (see Spec 01)
       │
       ▼
Background job queued (FastAPI BackgroundTasks; Celery as upgrade path for scale)
       │
       ▼
Worker determines photo type:
  - Type supplied by client → use it
  - Type not supplied → run classifier (see §2.1), return type_needed=true + ask user
       │
       ▼
Worker routes to appropriate processor (§3–§6)
       │
       ▼
Structured result written to food_log_photos.extracted_data (JSONB)
Status updated: "complete" | "error" | "needs_input"
       │
       ▼
App polls GET /api/photos/{photo_id}/status
OR receives Firebase push notification (if enabled)
```

### 2.1 Auto-Classification

If the user submits without selecting a type, the worker sends a low-cost prompt to Claude:

```
Given this image, classify it as exactly one of: food_plate, barcode, nutrition_label, food_label.
Reply with only the label.
```

If confidence is low or the image is ambiguous, set `status: "needs_input"` and return a prompt for the user to confirm the type manually. Never block — if classification fails, default to `food_plate` and attempt food detection.

---

## 3. Food Photo Processing (Claude Vision API)

### 3.1 Request

Send the image to Claude (model: `claude-sonnet-4-6`) with the following prompt:

```
You are analyzing a photo of food. Identify every distinct food item visible on the plate or in the image.
For each item, return a JSON array with this structure:
[
  {
    "name": "string — common food name",
    "portion": "string — approximate portion description, e.g. 'approximately 1 fillet' or 'small side portion'",
    "confidence": float between 0 and 1
  }
]
If no food is visible, return an empty array.
Reply with only the JSON array, no prose.
```

> **Note:** Calorie data is intentionally omitted from food plate analysis. Portion estimates from photos are unreliable. Calorie information is only included when sourced from a barcode or nutrition label scan.

### 3.2 Response Structure

```json
[
  {"name": "grilled salmon", "portion": "approximately 1 fillet", "confidence": 0.85},
  {"name": "steamed broccoli", "portion": "small side portion", "confidence": 0.90}
]
```

Each identified food item is passed to the Food Intelligence pipeline (Spec 07) for nutritional lookup. No calorie or macro estimates are generated at this stage — the Vision step produces food identification only.

### 3.3 Ambiguous or Unclear Images

- Mixed/obscured plate (e.g., stew, soup) → return best-effort items, set `confidence` accordingly; do not fabricate ingredients
- Image clearly contains food but items are indistinguishable → return `[{"name": "mixed dish", "portion": "unknown", "confidence": 0.2}]`
- Image contains no food → return `[]` with message "No foods detected in this image"
- Blurry or unreadable → return error (see §7)

---

## 4. Nutrition Label OCR

### 4.1 OCR Engine

Use Google Cloud Vision API (`DOCUMENT_TEXT_DETECTION` feature) as the primary OCR engine. AWS Textract is an acceptable alternative if GCP is not available.

### 4.2 Parsing

After OCR, pass the raw text to Claude with a structured extraction prompt:

```
Extract the nutrition facts from the following label text.
Return JSON matching this schema exactly:
{
  "serving_size": "string",
  "servings_per_container": "string or null",
  "calories": integer or null,
  "total_fat_g": number or null,
  "saturated_fat_g": number or null,
  "trans_fat_g": number or null,
  "cholesterol_mg": number or null,
  "sodium_mg": number or null,
  "total_carbs_g": number or null,
  "dietary_fiber_g": number or null,
  "sugars_g": number or null,
  "added_sugars_g": number or null,
  "protein_g": number or null,
  "vitamins_minerals": [{"name": "string", "amount": "string", "dv_percent": number or null}]
}
Use null for any field not present in the text. Reply with only the JSON object.

Label text:
{raw_ocr_text}
```

### 4.3 Format Support

| Format | Notes |
|---|---|
| US FDA (standard panel) | Primary target; well-supported |
| Canadian bilingual labels | Both columns parsed; English values used |
| EU nutrition declarations | kJ/kcal mapping applied; field names mapped |
| Supplement facts panels | Same schema; vitamins_minerals populated from supplement facts |

### 4.4 Output

The parsed nutrition object is stored in `food_log_photos.extracted_data` and attached to the meal's `foods` JSONB array as a single food item with `source: "nutrition_label_ocr"`.

---

## 5. Food Label OCR (Packaging / Ingredients List)

### 5.1 What It Captures

This path handles photos of the front or back of packaged food: brand name, product name, and ingredients list. It does not attempt to parse a nutrition facts panel — use §4 for that.

### 5.2 Process

1. OCR the image using Google Cloud Vision API (`TEXT_DETECTION`)
2. Pass raw text to Claude to extract:

```
From this product packaging text, extract:
{
  "product_name": "string or null",
  "brand": "string or null",
  "ingredients": ["string"] or null,
  "allergen_warnings": ["string"] or null
}
Allergen warnings are statements like "Contains: wheat, soy" or "May contain: tree nuts".
Reply with only the JSON object.

Packaging text:
{raw_ocr_text}
```

3. Feed `product_name` + `brand` into the Food Intelligence pipeline (Spec 07, Tier 2 entry point) for nutritional lookup
4. Store extracted object in `food_log_photos.extracted_data`

### 5.3 Output

```json
{
  "product_name": "Organic Oat Milk",
  "brand": "Oatly",
  "ingredients": ["water", "oats", "rapeseed oil", "salt"],
  "allergen_warnings": ["Contains: gluten (oats)"]
}
```

---

## 6. Barcode Scanning

Barcode decoding is handled entirely on-device using the `mobile_scanner` Flutter package (ML Kit backend). No server-side barcode decoding is required.

**Client flow:**

1. User selects "Barcode" photo type (or activates barcode scanner mode)
2. `mobile_scanner` decodes the barcode (EAN-13, UPC-A, QR, etc.)
3. Raw barcode string sent to `POST /api/food/lookup` with `type: "barcode"` (Spec 07)
4. No image upload to Supabase Storage is needed for barcode-only flows; if the user also takes a photo, it is stored normally

---

## 7. Error Handling

| Condition | Status | Message Returned |
|---|---|---|
| Blurry or unreadable image | `error` | "Image unclear — please retake or enter details manually" |
| No foods detected (food_plate) | `complete` | Empty array + "No foods detected in this image" |
| OCR returns no text | `error` | "Could not read text from this image — please retake or enter details manually" |
| Claude API timeout or error | `error` | "Vision processing failed — please try again or enter details manually" |
| Processing exceeds 30 seconds | `timeout` | Status set to `timeout`; user can retry via `POST /api/photos/{photo_id}/retry` |
| Unsupported image format | `error` | "Unsupported file type — please use JPEG or PNG" |

All errors are non-blocking. The meal log entry is preserved regardless of photo processing outcome. The UI displays the error inline and offers manual entry as a fallback.

---

## 8. Infrastructure

### 8.1 Processing Worker

- **Primary:** FastAPI `BackgroundTasks` — job enqueued on the same request that accepts the photo upload; suitable for low-to-moderate volume
- **Upgrade path:** Celery + Redis queue for horizontal scaling when concurrent photo processing volume warrants it; no API contract changes required

### 8.2 Storage

- Supabase Storage bucket: `photos`
- Access: private; files served only via signed URLs (1-hour TTL for display in app)
- Path convention: `{user_id}/{photo_id}.jpg`
- Max upload size: 10 MB; enforced at API layer before storage
- See Spec 01 for `food_log_photos` table schema

### 8.3 Vision APIs

| Purpose | Service | SDK |
|---|---|---|
| Food plate identification | Claude API (claude-sonnet-4-6) | `anthropic` Python SDK |
| OCR (nutrition label, food label) | Google Cloud Vision API | `google-cloud-vision` Python SDK |
| Auto-classification (photo type) | Claude API (claude-sonnet-4-6) | `anthropic` Python SDK |

### 8.4 Cost Management

- Claude Vision API charges per image and per token; cache `extracted_data` on the first successful processing run so the image is never sent to Claude twice
- If `food_log_photos.extracted_data` is already populated and `status` is `complete`, return the cached result without re-processing
- Google Cloud Vision: `DOCUMENT_TEXT_DETECTION` is more accurate than `TEXT_DETECTION` for dense label text; use it for nutrition and food labels
- Log per-request API costs to a `api_cost_log` table (optional, for monitoring)

---

*For nutritional data lookup after food identification, see Spec 07: Food Intelligence.*
*For `food_log_photos` table schema and RLS, see Spec 01: Database.*
*For API authentication and JWT handling, see Spec 03: REST API.*
