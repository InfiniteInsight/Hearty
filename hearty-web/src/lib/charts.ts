import type { SymptomResponse, MealWithSymptoms } from "@/types/api";

export const MEAL_TYPES = ["breakfast", "lunch", "dinner", "snack", "drink", "supplement", "other"] as const;

export interface ChartDatum { type: string; count: number }

export function symptomFrequency(symptoms: SymptomResponse[]): ChartDatum[] {
  const counts = new Map<string, number>();
  for (const s of symptoms) counts.set(s.symptom_type, (counts.get(s.symptom_type) ?? 0) + 1);
  return [...counts.entries()]
    .map(([type, count]) => ({ type, count }))
    .sort((a, b) => b.count - a.count);
}

export function mealTypeMix(meals: MealWithSymptoms[]): ChartDatum[] {
  const counts = new Map<string, number>();
  for (const m of meals) {
    const t = m.meal_type ?? "other";
    counts.set(t, (counts.get(t) ?? 0) + 1);
  }
  return MEAL_TYPES
    .map((type) => ({ type, count: counts.get(type) ?? 0 }))
    .filter((d) => d.count > 0);
}
