export interface FoodItem { name: string; quantity?: string; estimated_calories?: number; preparation?: string }
export interface SymptomResponse {
  id: string; meal_id?: string; symptom_type: string; severity?: number;
  onset_minutes?: number; duration_minutes?: number; bathroom_urgency?: number;
  bathroom_visits?: number; stool_consistency?: number; notes?: string; logged_at: string;
}
export interface MealWithSymptoms {
  id: string; description: string; meal_type?: string; foods?: FoodItem[];
  location?: string; mood_before?: number; hunger_before?: number; logged_at: string;
  input_method?: string; notes?: string; created_at: string; symptoms: SymptomResponse[];
}
export interface MealsListResponse { total: number; meals: MealWithSymptoms[] }
export interface MealResponse {
  id: string; description: string; meal_type?: string; foods?: FoodItem[];
  location?: string; mood_before?: number; hunger_before?: number; logged_at: string;
  input_method?: string; notes?: string; created_at: string;
}
export interface SignalChannel {
  outcome_type: "symptom" | "wellbeing"; outcome_name: string;
  direction: "harmful" | "beneficial"; peak_window_minutes?: number;
  meal_slot?: string; wellbeing_slot?: string; relative_risk?: number;
  score_delta?: number; evidence_count: number;
}
export interface FoodSignal {
  category: string; category_label?: string; unified_score: number;
  channels: SignalChannel[]; convergent: boolean; years_seen: number[];
  recurring: boolean; is_new: boolean; strength_by_year: Record<string, number>;
}
export interface ResolvedSignal {
  category: string; category_label?: string; last_year: number;
  strength: number; status: "resolved" | "potentially_resolved";
}
export interface SignalsResponse {
  signals: FoodSignal[]; analyzed_at?: string;
  total_meals_analyzed: number; total_symptoms_analyzed: number;
  total_wellbeing_analyzed: number; resolved: ResolvedSignal[];
}
export interface SummaryResponse {
  period: string; start_date: string; end_date: string; summary_text: string;
  meals_logged: number;
  top_symptoms: { symptom_type: string; count: number; avg_severity?: number }[];
}
export interface CreateMealRequest {
  description: string;
  meal_type?: "breakfast" | "lunch" | "dinner" | "snack" | "drink" | "supplement" | "other";
  logged_at?: string;
  input_method?: "voice" | "text" | "photo" | "barcode";
  notes?: string;
}
