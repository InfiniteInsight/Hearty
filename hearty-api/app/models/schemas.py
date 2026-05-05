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
    symptoms: Optional[List[SymptomItem]] = None
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
    result: Optional[dict] = None
    error: Optional[str] = None

# ─── Export ───────────────────────────────────────────────────────────────────

class ExportRequest(BaseModel):
    start_date: Optional[datetime] = None
    end_date: Optional[datetime] = None
