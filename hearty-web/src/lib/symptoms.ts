// Canonical symptom types (mirrors the backend extraction enum in ai_extraction.py).
export const SYMPTOM_TYPES = [
  "acid_reflux", "bloating", "gas", "nausea", "urgency", "loose_stool",
  "constipation", "stomach_pain", "cramping", "fatigue", "brain_fog", "headache",
  "skin_reaction", "heart_palpitations", "indigestion", "upset_stomach",
  "sour_stomach", "gut_rot", "other",
] as const;

// Tailwind classes for a severity badge (moved out of MealCard so SymptomRow can
// reuse it without importing MealCard — avoids a circular import).
export function severityClass(sev?: number): string {
  if (sev == null) return "bg-surface text-text-muted";
  if (sev <= 3) return "bg-brand/15 text-brand";
  if (sev <= 6) return "bg-warn/15 text-warn";
  return "bg-accent-red/15 text-accent-red";
}
