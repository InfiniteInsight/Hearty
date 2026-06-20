from pydantic import BaseModel, Field
from typing import Optional, List, Literal, Dict
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
    meal_type: Optional[str] = None
    foods: Optional[List[FoodItem]] = None
    location: Optional[str] = None
    mood_before: Optional[int] = None
    hunger_before: Optional[int] = None
    logged_at: datetime
    input_method: Optional[str] = None
    notes: Optional[str] = None
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
    meal_id: Optional[UUID] = None
    symptom_type: str
    severity: Optional[int] = None
    onset_minutes: Optional[int] = None
    duration_minutes: Optional[int] = None
    bathroom_urgency: Optional[int] = None
    bathroom_visits: Optional[int] = None
    stool_consistency: Optional[int] = None
    notes: Optional[str] = None
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
    period: Optional[Literal['morning', 'midday', 'evening']] = None

class WellbeingResponse(WellbeingRequest):
    id: UUID
    created_at: datetime

# ─── Trends (legacy — kept for /api/summary until Plan 11 Phase 7 cleanup) ───

class TriggerFood(BaseModel):
    food_name: str
    symptom_type: str
    confidence_score: float
    occurrence_count: int
    avg_onset_minutes: Optional[int]
    avg_severity: Optional[float]
    is_confirmed: bool
    label: Optional[str] = None

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

# ─── Signals (Plan 11: Unified Signal Engine) ─────────────────────────────────

class SignalChannel(BaseModel):
    outcome_type: Literal["symptom", "wellbeing"]
    outcome_name: str
    direction: Literal["harmful", "beneficial"]
    peak_window_minutes: Optional[int] = None
    meal_slot: Optional[str] = None
    wellbeing_slot: Optional[str] = None
    relative_risk: Optional[float] = None
    score_delta: Optional[float] = None
    evidence_count: int

class FoodSignal(BaseModel):
    category: str
    category_label: Optional[str] = None
    unified_score: float
    channels: List[SignalChannel]
    convergent: bool
    # Multi-year persistence (defaults keep older responses valid).
    years_seen: List[int] = Field(default_factory=list)
    recurring: bool = False
    is_new: bool = False
    strength_by_year: Dict[str, float] = Field(default_factory=dict)

class ResolvedSignal(BaseModel):
    category: str
    category_label: Optional[str] = None
    last_year: int
    strength: float
    status: Literal["resolved", "potentially_resolved"]

class SignalsResponse(BaseModel):
    signals: List[FoodSignal]
    analyzed_at: Optional[datetime]
    total_meals_analyzed: int
    total_symptoms_analyzed: int
    total_wellbeing_analyzed: int
    resolved: List[ResolvedSignal] = Field(default_factory=list)

class AnalyzeResponse(BaseModel):
    status: Literal["started", "completed"]
    analyzed_at: datetime
    new_signals_count: int

class AnalyzeStatusResponse(BaseModel):
    last_analyzed_at: Optional[datetime]
    has_new_data: bool

# ─── Health Profile ───────────────────────────────────────────────────────────

# Health profile schemas live in app/health_profile/schemas.py (Spec 08).

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

# ─── Meals with Symptoms (GET /api/meals response) ────────────────────────────
# Defined here so SymptomResponse is already in scope.

class MealWithSymptoms(MealResponse):
    symptoms: List[SymptomResponse] = []

class MealsListResponse(BaseModel):
    total: int
    meals: List[MealWithSymptoms]

# ─── Daily Check-in ───────────────────────────────────────────────────────────

class CheckinGap(BaseModel):
    type: Literal["symptom_gap", "low_confidence", "missing_chunk"]
    prompt: str
    meal_id: Optional[str] = None
    food_name: Optional[str] = None
    window_start: Optional[str] = None
    window_end: Optional[str] = None

class CheckinGapsResponse(BaseModel):
    target_date: str           # YYYY-MM-DD, the anchored day
    expired: bool = False
    gaps: List[CheckinGap] = Field(default_factory=list)

# ─── Trends Conversation ────────────────────────────────────────────────────

VerdictType = Literal["confirmed", "disputed", "snoozed"]

class PresentedSignal(BaseModel):
    """A food_signal after the feedback overlay has been applied."""
    category: str
    outcome_type: Literal["symptom", "wellbeing"]
    outcome_name: str
    direction: Literal["harmful", "beneficial"]
    unified_score: float
    relative_risk: Optional[float] = None
    evidence_count: int
    is_new: bool = False
    is_confirmed: bool = False
    is_resurfaced: bool = False
    years_seen: List[int] = Field(default_factory=list)
    recurring: bool = False

class ConversationTurn(BaseModel):
    role: Literal["user", "assistant"]
    content: str

class ProposedVerdict(BaseModel):
    """A verdict Hearty inferred from the user's words, for client confirmation.
    NEVER written without an explicit client confirmation step."""
    category: str
    outcome_type: Literal["symptom", "wellbeing"]
    outcome_name: str
    verdict: VerdictType
    category_label: Optional[str] = None

class ProposedExperiment(BaseModel):
    """A 2-week elimination experiment Hearty offers for a harmful pattern,
    for client confirmation. NEVER started without an explicit confirm step."""
    category: str
    outcome_type: Literal["symptom", "wellbeing"]
    outcome_name: str
    category_label: Optional[str] = None

class TrendsConversationRequest(BaseModel):
    history: List[ConversationTurn] = Field(default_factory=list)

class TrendsConversationResponse(BaseModel):
    reply: str
    proposed_verdict: Optional[ProposedVerdict] = None
    proposed_experiment: Optional[ProposedExperiment] = None
    is_closing: bool = False

class SignalVerdictRequest(BaseModel):
    category: str
    outcome_type: Literal["symptom", "wellbeing"]
    outcome_name: str
    verdict: VerdictType

class SignalVerdictResponse(BaseModel):
    ok: bool

# ─── Tracked Experiments ─────────────────────────────────────────────────────

class CreateExperimentRequest(BaseModel):
    category: str
    outcome_type: Literal["symptom", "wellbeing"]
    outcome_name: str

class ExperimentResponse(BaseModel):
    id: str
    category: str
    category_label: Optional[str] = None
    direction: str
    outcome_type: str
    outcome_name: str
    experiment_start: str
    experiment_end: str
    status: str
    result: Optional[Dict] = None
    nudged_at: Optional[str] = None
    # Computed on the active fetch (not stored):
    adherence: Optional[float] = None
    logged_days: Optional[int] = None
    nudge_suggested: bool = False

class ActiveExperimentsResponse(BaseModel):
    experiments: List[ExperimentResponse] = Field(default_factory=list)

# ─── Food Intelligence ───────────────────────────────────────────────────────

class FoodLookupRequest(BaseModel):
    type: Literal["barcode", "name", "free_text"]
    value: str
    restaurant: Optional[str] = None

class FoodLookupResponse(BaseModel):
    item_name: str
    nutrition: Optional[Dict] = None
    tier_used: int
    source: Optional[str] = None
    confidence: Optional[float] = None
    allergen_warnings: List[str] = Field(default_factory=list)
    message: Optional[str] = None

class FoodCacheResponse(BaseModel):
    hit: bool
    nutrition: Optional[Dict] = None
