# Hearty — REST API Specification

**File:** `2026-05-04-hearty-03-rest-api.md`
**Phase:** 1 — Core Infrastructure
**Related:** `2026-05-04-hearty-02-mcp-server.md` (MCP path for Claude Desktop users)

---

## 1. Overview

The Hearty REST API is a FastAPI (Python) service that provides AI-agnostic access to all Hearty functionality. Any AI assistant (Gemini, GPT, third-party tools, or the Hearty Flutter/web clients) can interact with Hearty data through standard HTTP without requiring the MCP protocol.

Claude Desktop users use the MCP server instead (see `2026-05-04-hearty-02-mcp-server.md`). This API is the access layer for everything else.

**Key characteristics:**
- All endpoints accept free-form natural language input; an AI extraction service parses it into structured data
- Auth is Supabase Bearer JWT on every endpoint — one token, all endpoints
- Stateless: no persistent disk needed, safe for horizontal scaling
- Auto-generated OpenAPI docs at `/docs` (Swagger UI)

**Runtime:** Python 3.11+
**Framework:** FastAPI
**Hosting:** Fly.io free tier (stays running, no spin-down, sufficient for personal use); upgrade to Railway paid (~$5/month) when scaling to multiple users
**Database:** Supabase (PostgreSQL via `supabase-py` client)

---

## 2. File Structure

```
hearty-api/
  app/
    main.py                   — FastAPI app factory, CORS, middleware, lifespan
    auth.py                   — Supabase JWT verification dependency
    routers/
      meals.py                — POST /api/meals, GET /api/meals
      symptoms.py             — POST /api/symptoms, GET /api/symptoms
      wellbeing.py            — POST /api/wellbeing
      trends.py               — GET /api/trends, GET /api/summary
      export.py               — GET /api/export/json, /csv; POST /api/export/pdf
      health_profile.py       — GET/PUT /api/health-profile
      photos.py               — POST /api/photos, GET /api/photos/{id}/status
    services/
      ai_extraction.py        — LiteLLM calls to parse free-form text into structure (provider-agnostic)
      food_lookup.py          — tiered food lookup pipeline (barcode → DB → web → AI → fallback)
      trend_engine.py         — correlation analysis, food trigger scoring
      export_service.py       — PDF/CSV/JSON/XML generation
    models/
      schemas.py              — all Pydantic request/response models
  requirements.txt
  .env.example
```

---

## 3. Authentication

All endpoints require a valid Supabase Bearer JWT in the `Authorization` header.

```
Authorization: Bearer <supabase-user-jwt>
```

### 3.1 `auth.py` — JWT Verification Dependency

```python
# app/auth.py

from fastapi import HTTPException, Security
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from supabase import create_client
import os

security = HTTPBearer()
supabase = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_KEY"])

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Security(security)
) -> dict:
    token = credentials.credentials
    response = supabase.auth.get_user(token)
    if response.user is None:
        raise HTTPException(status_code=401, detail="Invalid or expired token")
    return {"id": response.user.id, "email": response.user.email}
```

Usage in routers:

```python
from app.auth import get_current_user
from fastapi import Depends

@router.post("/api/meals")
async def log_meal(body: MealRequest, user=Depends(get_current_user)):
    ...
```

---

## 4. Pydantic Models (`schemas.py`)

```python
# app/models/schemas.py

from pydantic import BaseModel, Field
from typing import Optional, List, Literal
from datetime import datetime
from uuid import UUID

# ─── Shared ───────────────────────────────────────────────────────────────────

class FoodItem(BaseModel):
    name: str
    quantity: Optional[str] = None
    estimated_calories: Optional[float] = None
    preparation: Optional[str] = None

# ─── Meals ────────────────────────────────────────────────────────────────────

class MealRequest(BaseModel):
    description: str = Field(..., description="Free-form description. AI extracts structure.")
    meal_type: Optional[Literal["breakfast","lunch","dinner","snack","drink","supplement","other"]] = None
    location: Optional[str] = None
    mood_before: Optional[int] = Field(None, ge=1, le=10)
    hunger_before: Optional[int] = Field(None, ge=1, le=10)
    logged_at: Optional[datetime] = None
    input_method: Optional[Literal["voice","text","photo","barcode"]] = "text"
    offline_id: Optional[str] = None
    notes: Optional[str] = None

class MealResponse(BaseModel):
    id: UUID
    description: str
    meal_type: Optional[str]
    foods: Optional[List[FoodItem]]
    location: Optional[str]
    mood_before: Optional[int]
    hunger_before: Optional[int]
    logged_at: datetime
    input_method: Optional[str]
    notes: Optional[str]
    created_at: datetime

# ─── Symptoms ─────────────────────────────────────────────────────────────────

SymptomType = Literal[
    "acid_reflux","bloating","gas","nausea","urgency","loose_stool",
    "constipation","stomach_pain","cramping","fatigue","brain_fog",
    "headache","skin_reaction","heart_palpitations","other"
]

class SymptomItem(BaseModel):
    symptom_type: SymptomType
    severity: Optional[int] = Field(None, ge=1, le=10)
    duration_minutes: Optional[int] = None
    bathroom_urgency: Optional[int] = Field(None, ge=0, le=5)
    bathroom_visits: Optional[int] = None
    stool_consistency: Optional[int] = Field(None, ge=1, le=7)

class SymptomRequest(BaseModel):
    raw_description: str = Field(..., description="Free-form symptom description. AI extracts structure.")
    meal_id: Optional[UUID] = None
    onset_minutes: Optional[int] = None
    symptoms: Optional[List[SymptomItem]] = None  # AI fills this if not provided
    notes: Optional[str] = None
    logged_at: Optional[datetime] = None

class SymptomResponse(BaseModel):
    id: UUID
    meal_id: Optional[UUID]
    symptom_type: str
    severity: Optional[int]
    onset_minutes: Optional[int]
    duration_minutes: Optional[int]
    bathroom_urgency: Optional[int]
    bathroom_visits: Optional[int]
    stool_consistency: Optional[int]
    notes: Optional[str]
    logged_at: datetime

# ─── Wellbeing ────────────────────────────────────────────────────────────────

class WellbeingRequest(BaseModel):
    energy_level: Optional[int] = Field(None, ge=1, le=10)
    mood: Optional[int] = Field(None, ge=1, le=10)
    stress_level: Optional[int] = Field(None, ge=1, le=10)
    sleep_hours: Optional[float] = None
    sleep_quality: Optional[int] = Field(None, ge=1, le=10)
    hydration: Optional[int] = Field(None, ge=1, le=10)
    exercise_minutes: Optional[int] = None
    notes: Optional[str] = None
    logged_at: Optional[datetime] = None

class WellbeingResponse(WellbeingRequest):
    id: UUID
    created_at: datetime

# ─── Trends ───────────────────────────────────────────────────────────────────

class TriggerFood(BaseModel):
    food_name: str
    symptom_type: str
    confidence_score: float
    occurrence_count: int
    avg_onset_minutes: Optional[int]
    avg_severity: Optional[float]
    is_confirmed: bool

class TrendsResponse(BaseModel):
    analysis_period_days: int
    generated_at: datetime
    triggers: List[TriggerFood]
    total_meals_analyzed: int
    total_symptoms_analyzed: int

class SummaryResponse(BaseModel):
    period: str
    start_date: datetime
    end_date: datetime
    summary_text: str
    meals_logged: int
    top_symptoms: List[dict]
    top_triggers: List[TriggerFood]

# ─── Health Profile ───────────────────────────────────────────────────────────

class HealthProfileRequest(BaseModel):
    allergens: Optional[List[str]] = None
    intolerances: Optional[List[str]] = None
    conditions: Optional[List[str]] = None
    dietary_protocols: Optional[List[str]] = None
    notes: Optional[str] = None

class HealthProfileResponse(HealthProfileRequest):
    user_id: UUID
    updated_at: datetime

# ─── Photos ───────────────────────────────────────────────────────────────────

PhotoType = Literal["food_plate", "barcode", "nutrition_label", "food_label"]

PhotoStatus = Literal["pending", "processing", "complete", "failed"]

class PhotoUploadResponse(BaseModel):
    id: UUID
    type: PhotoType
    status: PhotoStatus
    meal_id: Optional[UUID] = None
    message: str

class PhotoStatusResponse(BaseModel):
    id: UUID
    type: PhotoType
    status: PhotoStatus
    result: Optional[dict] = None   # extracted meal/food data when complete
    error: Optional[str] = None

# ─── Export ───────────────────────────────────────────────────────────────────

class ExportRequest(BaseModel):
    start_date: Optional[datetime] = None
    end_date: Optional[datetime] = None
```

---

## 5. Endpoints

### 5.1 `POST /api/meals` — Log a Meal

Accepts a free-form meal description. AI extraction parses it into structured food items.

**Request:** `MealRequest`
```json
{
  "description": "Had a big bowl of pasta arrabiata with garlic bread and two glasses of red wine",
  "meal_type": "dinner",
  "location": "home",
  "mood_before": 7,
  "hunger_before": 8,
  "logged_at": "2026-05-04T19:30:00Z"
}
```

**Response `201`:** `MealResponse`
```json
{
  "id": "a1b2c3d4-...",
  "description": "Had a big bowl of pasta arrabiata...",
  "meal_type": "dinner",
  "foods": [
    {"name": "pasta arrabiata", "quantity": "1 large bowl", "estimated_calories": 620},
    {"name": "garlic bread", "quantity": "2 slices", "estimated_calories": 180},
    {"name": "red wine", "quantity": "2 glasses", "estimated_calories": 250}
  ],
  "location": "home",
  "mood_before": 7,
  "hunger_before": 8,
  "logged_at": "2026-05-04T19:30:00Z",
  "input_method": "text",
  "notes": null,
  "created_at": "2026-05-04T19:31:02Z"
}
```

**Behavior:**
1. Call `ai_extraction.extract_meal(description)` to populate `foods[]` and infer `meal_type` if not provided.
2. Insert into `meals` table.
3. If `offline_id` is present, check for duplicate before inserting (idempotency).

---

### 5.2 `POST /api/symptoms` — Log Symptoms

Accepts a free-form symptom description. AI extraction parses severity, type, and onset.

**Request:** `SymptomRequest`
```json
{
  "raw_description": "Really bad heartburn about 45 minutes after dinner, maybe a 7 out of 10. Also some bloating.",
  "meal_id": "a1b2c3d4-..."
}
```

**Response `201`:** `List[SymptomResponse]` (one record per symptom type)
```json
[
  {
    "id": "e5f6g7h8-...",
    "meal_id": "a1b2c3d4-...",
    "symptom_type": "acid_reflux",
    "severity": 7,
    "onset_minutes": 45,
    "duration_minutes": null,
    "bathroom_urgency": null,
    "bathroom_visits": null,
    "stool_consistency": null,
    "notes": null,
    "logged_at": "2026-05-04T20:15:00Z"
  },
  {
    "id": "i9j0k1l2-...",
    "meal_id": "a1b2c3d4-...",
    "symptom_type": "bloating",
    "severity": 5,
    "onset_minutes": 45,
    ...
  }
]
```

**Behavior:**
1. If `symptoms` not provided in request, call `ai_extraction.extract_symptoms(raw_description)`.
2. Insert one row per extracted symptom into `symptoms` table.

---

### 5.3 `POST /api/wellbeing` — Log Wellbeing Snapshot

**Request:** `WellbeingRequest`
```json
{
  "energy_level": 6,
  "mood": 7,
  "stress_level": 4,
  "sleep_hours": 7.5,
  "sleep_quality": 7,
  "hydration": 6,
  "exercise_minutes": 30,
  "notes": "Good run this morning"
}
```

**Response `201`:** `WellbeingResponse`

---

### 5.4 `GET /api/meals` — Query Meals

**Query parameters:**

| Parameter    | Type   | Description                                      |
|--------------|--------|--------------------------------------------------|
| `start_date` | string | ISO 8601. Default: 7 days ago.                   |
| `end_date`   | string | ISO 8601. Default: now.                          |
| `meal_type`  | string | Filter by meal type enum.                        |
| `keyword`    | string | Case-insensitive search in description + foods.  |
| `limit`      | int    | Max records. Default: 50, max: 200.              |
| `offset`     | int    | Pagination offset. Default: 0.                   |

**Response `200`:**
```json
{
  "total": 14,
  "meals": [ /* MealResponse[] with nested symptoms */ ]
}
```

Meals include a `symptoms` array of associated `SymptomResponse` objects (joined on `meal_id`).

---

### 5.5 `GET /api/symptoms` — Query Symptoms

**Query parameters:**

| Parameter      | Type   | Description                                  |
|----------------|--------|----------------------------------------------|
| `start_date`   | string | ISO 8601. Default: 7 days ago.               |
| `end_date`     | string | ISO 8601. Default: now.                      |
| `symptom_type` | string | Filter by symptom type enum value.           |
| `min_severity` | int    | Only return symptoms at or above severity.   |
| `limit`        | int    | Default: 50.                                 |

**Response `200`:** `List[SymptomResponse]`

---

### 5.6 `GET /api/trends` — Run Trend Analysis

Returns ranked food-symptom correlations. Triggers a fresh analysis if data is stale (>24h).

**Query parameters:**

| Parameter             | Type   | Description                                  |
|-----------------------|--------|----------------------------------------------|
| `analysis_period_days`| int    | Days to analyze. Default: 30.               |
| `focus_symptom`       | string | Narrow to one symptom type.                  |
| `min_occurrences`     | int    | Min co-occurrences to appear. Default: 2.    |

**Response `200`:** `TrendsResponse`
```json
{
  "analysis_period_days": 30,
  "generated_at": "2026-05-04T21:00:00Z",
  "total_meals_analyzed": 87,
  "total_symptoms_analyzed": 34,
  "triggers": [
    {
      "food_name": "tomato sauce",
      "symptom_type": "acid_reflux",
      "confidence_score": 0.78,
      "occurrence_count": 6,
      "avg_onset_minutes": 42,
      "avg_severity": 7.2,
      "is_confirmed": false
    }
  ]
}
```

---

### 5.7 `GET /api/summary` — Natural Language Summary

Returns an AI-generated natural language health summary for the requested period.

**Query parameters:**

| Parameter    | Type   | Description                                        |
|--------------|--------|----------------------------------------------------|
| `period`     | string | `week`, `month`, or `custom`. Default: `week`.     |
| `start_date` | string | Required when `period=custom`. ISO 8601.           |
| `end_date`   | string | Required when `period=custom`. ISO 8601.           |

**Response `200`:** `SummaryResponse`
```json
{
  "period": "week",
  "start_date": "2026-04-27T00:00:00Z",
  "end_date": "2026-05-04T23:59:59Z",
  "summary_text": "Over the past week you logged 21 meals and 9 symptom events. Acid reflux appeared 4 times, always following meals that included tomato sauce or red wine. Your best days were Tuesday and Thursday — no symptoms logged. Average energy was 6.4/10, slightly below your 30-day average of 7.1.",
  "meals_logged": 21,
  "top_symptoms": [
    {"symptom_type": "acid_reflux", "count": 4, "avg_severity": 7.0},
    {"symptom_type": "bloating", "count": 3, "avg_severity": 5.3}
  ],
  "top_triggers": [ /* TriggerFood[] */ ]
}
```

**Behavior:**
1. Query aggregated stats for the period.
2. Call `ai_extraction.generate_summary(stats)` to produce the natural language `summary_text`.

---

### 5.8 `GET /api/export/json` — Full Data Export (JSON)

**Query parameters:** `start_date`, `end_date` (optional)

**Response `200`:** `application/json` — full nested export:
```json
{
  "exported_at": "2026-05-04T21:00:00Z",
  "user_id": "...",
  "period": {"start": "...", "end": "..."},
  "meals": [
    {
      /* MealResponse fields */
      "symptoms": [ /* SymptomResponse[] */ ]
    }
  ],
  "wellbeing_snapshots": [ /* WellbeingResponse[] */ ],
  "food_triggers": [ /* TriggerFood[] */ ],
  "health_profile": { /* HealthProfileResponse */ }
}
```

---

### 5.9 `GET /api/export/csv` — CSV Export

**Query parameters:** `start_date`, `end_date` (optional)

**Response `200`:** `text/csv`

Flat structure, one row per symptom event with denormalized meal fields. Column headers are human-readable (e.g. `Meal Description`, `Food Items`, `Symptom Type`, `Severity`, `Onset (minutes)`).

---

### 5.10 `POST /api/export/pdf` — Generate PDF Trend Report

**Request:** `ExportRequest`
```json
{
  "start_date": "2026-04-01T00:00:00Z",
  "end_date": "2026-05-04T23:59:59Z"
}
```

**Response `200`:** `application/pdf` — binary file stream.

**Report contents:**
- Cover: date range, user name
- Section 1: Summary statistics (meals logged, symptom frequency, best/worst days)
- Section 2: Top trigger foods (ranked table with confidence scores)
- Section 3: Symptom timeline chart (embedded PNG via Matplotlib)
- Section 4: Wellbeing trends chart
- Section 5: Pattern observations — what the data shows, framed as correlations only (always included)
- Section 6: AI-generated recommendations — only included if `notification_preferences.ai_recommendations_enabled = true`; clearly labeled "Not medical advice. For personal awareness only."

**Behavior:** `export_service.generate_pdf(user_id, start_date, end_date)` — assembles data, renders charts with Matplotlib, compiles PDF with `reportlab` or `weasyprint`.

---

### 5.11 `GET /api/health-profile` — Get Health Profile

**Response `200`:** `HealthProfileResponse`
```json
{
  "user_id": "...",
  "allergens": ["peanuts"],
  "intolerances": ["lactose", "fructose"],
  "conditions": ["GERD", "IBS-D"],
  "dietary_protocols": ["low-FODMAP"],
  "notes": "Symptoms worse in the morning and after high-fat meals.",
  "updated_at": "2026-04-15T10:00:00Z"
}
```

---

### 5.12 `PUT /api/health-profile` — Update Health Profile

**Request:** `HealthProfileRequest` (all fields optional — partial updates merge with existing)

**Response `200`:** `HealthProfileResponse`

**Behavior:** Upsert on `user_id`. Arrays replace fully on update (not append). Caller sends complete array values.

---

### 5.13 `POST /api/photos` — Upload Photo

Accepts a photo upload and triggers the appropriate processing pipeline based on type.

**Request:** `multipart/form-data`

| Field   | Type   | Description                                                  |
|---------|--------|--------------------------------------------------------------|
| `file`  | binary | Image file (JPEG, PNG, HEIC, WEBP)                          |
| `type`  | string | `food_plate`, `barcode`, `nutrition_label`, or `food_label` |

**Response `202`:** `PhotoUploadResponse`
```json
{
  "id": "p1q2r3s4-...",
  "type": "food_plate",
  "status": "pending",
  "meal_id": null,
  "message": "Photo received. Processing typically takes 5–10 seconds."
}
```

**Processing pipelines by type:**
- `food_plate`: Upload to Supabase Storage → call Claude Vision API → extract food items → auto-create a draft meal record
- `barcode`: Decode barcode → query Open Food Facts / USDA API → return nutrition data
- `nutrition_label`: OCR via Claude Vision → extract macros and ingredient list
- `food_label`: OCR via Claude Vision → extract product name, ingredients, allergens

---

### 5.14 `GET /api/photos/{id}/status` — Check Photo Processing Status

**Response `200`:** `PhotoStatusResponse`
```json
{
  "id": "p1q2r3s4-...",
  "type": "food_plate",
  "status": "complete",
  "result": {
    "meal_id": "a1b2c3d4-...",
    "foods": [
      {"name": "grilled salmon", "quantity": "1 fillet", "estimated_calories": 350},
      {"name": "steamed broccoli", "quantity": "1 cup", "estimated_calories": 55}
    ]
  },
  "error": null
}
```

Status values: `pending` → `processing` → `complete` | `failed`

---

## 6. AI Extraction Service (`ai_extraction.py`)

The extraction service uses **LiteLLM** to parse free-form text into structured data. LiteLLM provides a single, unified interface that routes to the correct provider based on the model string — no code changes needed to swap providers.

```python
import litellm
import os

response = litellm.completion(
    model=os.environ.get("LLM_MODEL", "claude-sonnet-4-6"),
    messages=[{"role": "user", "content": prompt}],
    api_base=os.environ.get("LLM_BASE_URL"),  # None = use provider default
)
```

LiteLLM automatically routes to the correct provider based on the model string:
- `claude-sonnet-4-6` → Anthropic
- `gemini/gemini-2.0-flash` → Google Gemini
- `gpt-4o` → OpenAI
- `ollama/llama3.3` → local Ollama (future)

This service is used by the meals, symptoms, and summary endpoints.

### 6.1 `extract_meal(description: str) -> dict`

```python
# Calls Claude with a structured extraction prompt.
# Returns: {"foods": [...], "inferred_meal_type": "..."}

MEAL_EXTRACTION_PROMPT = """
You are a precise food data extractor. Given a natural language meal description,
extract a structured list of food items.

Return ONLY valid JSON with this shape:
{
  "foods": [
    {
      "name": "food item name",
      "quantity": "serving size or null",
      "estimated_calories": number_or_null,
      "preparation": "cooking method or null"
    }
  ],
  "inferred_meal_type": "breakfast|lunch|dinner|snack|drink|supplement|other"
}

Be conservative with calorie estimates — omit them rather than guess wildly.
Do not add commentary. Return only the JSON object.
"""
```

### 6.2 `extract_symptoms(raw_description: str) -> list[dict]`

```python
SYMPTOM_EXTRACTION_PROMPT = """
You are a medical data extractor specializing in GI and systemic symptoms.
Given a natural language symptom description, extract structured symptom records.

Return ONLY valid JSON with this shape:
{
  "symptoms": [
    {
      "symptom_type": "one of: acid_reflux|bloating|gas|nausea|urgency|loose_stool|constipation|stomach_pain|cramping|fatigue|brain_fog|headache|skin_reaction|heart_palpitations|other",
      "severity": 1-10_or_null,
      "onset_minutes": number_or_null,
      "duration_minutes": number_or_null,
      "bathroom_urgency": 0-5_or_null,
      "bathroom_visits": number_or_null,
      "stool_consistency": 1-7_or_null
    }
  ]
}

Extract multiple symptoms if the description mentions more than one.
Do not diagnose. Extract only what is stated.
Return only the JSON object.
"""
```

### 6.3 `generate_summary(stats: dict) -> str`

Called by `GET /api/summary`. Passes aggregated stats to Claude and returns a natural language paragraph.

```python
SUMMARY_PROMPT = """
You are Hearty, a personal health journal assistant.
Given the following health data statistics for a user, write a concise, 
warm, and informative health summary in 3–5 sentences.

Focus on: notable patterns, symptom frequency, best days, and any 
correlations visible in the data. 

Never diagnose. Never recommend medications. Clearly frame correlations 
as observations, not medical conclusions.

Data:
{stats_json}
"""
```

---

## 7. Food Lookup Pipeline (`food_lookup.py`)

Implements the tiered food lookup pipeline used when processing barcodes and enriching meal entries with nutritional data.

```
Tier 1: Barcode scan → Open Food Facts API (openfoodfacts.org)
Tier 2: Restaurant / menu item → Nutritionix API or USDA FoodData Central
Tier 3: Web search → scrape top result for nutritional info
Tier 4: Claude AI estimate → best-effort from food name + quantity
Tier 5: Honest fallback → log the food by name, mark calories as null
```

**Principle:** Always log. Never block logging because nutritional data is unavailable. Set `estimated_calories: null` and move on. The user can correct later.

---

## 8. Trend Engine (`trend_engine.py`)

Implements the co-occurrence analysis algorithm that populates the `food_triggers` table.

```python
# Confidence formula (matches gut-journal-spec.md Section 7):
# confidence = (co_occurrence_rate * 0.5) + (avg_severity / 10 * 0.3) + (frequency_bonus * 0.2)
#
# Two-tier pattern classification:
#   "Emerging patterns"   — 3–5 co-occurrences  — surfaced with label "early signal, needs more data"
#   "Established triggers" — 6+ co-occurrences  — surfaced as confirmed patterns
```

**User expectation setting:** The app informs users on first launch and in the Trends view that approximately 6 months of consistent logging is needed to build statistically meaningful confidence in trigger patterns.

Triggered:
- On demand via `GET /api/trends`
- As a scheduled background job (e.g. daily via Railway cron or Supabase Edge Function)

---

## 9. System Prompt for External AI Assistants

Users who want to use Gemini, GPT, or other AI assistants with Hearty paste the following into that assistant's system instructions or custom instructions field once:

```
You are connected to Hearty, a personal food and symptom journal.
Base URL: [YOUR_DEPLOYED_API_URL]
Auth: Include "Authorization: Bearer [YOUR_SUPABASE_JWT]" on all requests.

BEHAVIOR:
- When the user mentions eating or drinking anything, call POST /api/meals immediately.
  Pass the description verbatim in the "description" field. The API will extract structure.
- After logging a meal, follow up 30–90 minutes later to ask about symptoms.
- When the user mentions physical symptoms, call POST /api/symptoms with their words
  in the "raw_description" field.
- When asked about patterns or triggers, call GET /api/trends.
- When asked for a review or summary, call GET /api/summary.
- Never ask for information that has already been captured in previous logs.
- Never diagnose. You can describe correlations — never make medical conclusions.
```

---

## 10. `main.py` — App Setup

```python
# app/main.py

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
from app.routers import meals, symptoms, wellbeing, trends, export, health_profile, photos

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: verify Supabase connection
    yield
    # Shutdown: cleanup

app = FastAPI(
    title="Hearty API",
    version="1.0.0",
    description="Personal food and symptom journal REST API",
    lifespan=lifespan
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],          # Open for AI assistant use; tighten for production web-only
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(meals.router)
app.include_router(symptoms.router)
app.include_router(wellbeing.router)
app.include_router(trends.router)
app.include_router(export.router)
app.include_router(health_profile.router)
app.include_router(photos.router)

@app.get("/health")
async def health_check():
    return {"status": "ok"}
```

**CORS policy:** Allow all origins by default to support AI assistant tool use from arbitrary clients. If restricting to known frontend domains, add `ALLOWED_ORIGINS` to `.env` and load at startup.

---

## 11. `.env.example`

```
# Supabase
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=eyJhbGci...

# LLM Provider (LiteLLM — swap model string to change provider)
LLM_MODEL=claude-sonnet-4-6
LLM_BASE_URL=                    # leave blank for cloud providers

# API keys — only set the one matching your LLM_MODEL provider
ANTHROPIC_API_KEY=sk-ant-...     # for Claude
GEMINI_API_KEY=                  # for Gemini (free tier available)
OPENAI_API_KEY=                  # for GPT-4

# Optional: Nutritionix for restaurant food lookup (Tier 2)
NUTRITIONIX_APP_ID=
NUTRITIONIX_API_KEY=

# Supabase Storage bucket for photo uploads
SUPABASE_STORAGE_BUCKET=hearty-photos

# CORS (comma-separated; leave empty to allow all)
ALLOWED_ORIGINS=https://hearty.yourdomain.com,http://localhost:5173
```

---

## 12. `requirements.txt`

```
fastapi>=0.111.0
uvicorn[standard]>=0.29.0
supabase>=2.4.0
pydantic>=2.7.0
litellm>=1.40.0
python-multipart>=0.0.9
reportlab>=4.2.0          # PDF generation
matplotlib>=3.9.0          # Chart rendering for PDF reports
requests>=2.32.0           # Food lookup HTTP calls
```

---

## 13. Hosting

**Primary:** Fly.io free tier — stays running with no spin-down, sufficient for personal use. **Upgrade path:** Railway paid (~$5/month) when scaling to multiple users. Render is not recommended — its free tier spins down after inactivity, causing unacceptable cold starts for a mobile app.

- Stateless — no persistent disk required. Supabase holds all state.
- Supabase Storage handles photo file persistence.
- Deploy to Fly.io: run `fly launch` once from `hearty-api/` to configure, then `fly deploy` for all subsequent deployments.
- Set all `.env` values as secrets via `fly secrets set KEY=VALUE`.
- Health check: `GET /health` → `{"status": "ok"}`

**Local development:**
```bash
cd hearty-api
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env   # fill in values
uvicorn app.main:app --reload --port 8000
# Swagger UI: http://localhost:8000/docs
```

**Fly.io deployment:**
```bash
# Initial setup (once)
fly launch   # from the hearty-api/ directory

# All subsequent deploys
fly deploy   # from the hearty-api/ directory
```

---

## 14. `POST /auth/on-login` — New User Bootstrap Webhook

Called by a Supabase Auth webhook on every new user signup. Creates default rows for `health_profile` and `notification_preferences` so the rest of the app can assume these records always exist.

**Trigger:** Supabase Auth → Webhook → `POST /auth/on-login`

**Request:** Supabase Auth webhook payload (contains `event`, `user.id`, `user.email`)

**Behavior:**
1. Verify the request is from Supabase using the webhook secret (`SUPABASE_WEBHOOK_SECRET` env var).
2. Upsert a blank `health_profile` row for the user (no-op if already exists).
3. Upsert a `notification_preferences` row with all defaults (no-op if already exists).

**Response `200`:** `{"ok": true}`

**Note:** This endpoint must be registered in Supabase Dashboard → Database → Webhooks, pointing to `[API_BASE_URL]/auth/on-login` with the shared webhook secret. Add the router at `app/routers/auth_hooks.py` and include it in `main.py`.
