import { expect, test } from "vitest";
import { symptomFrequency, mealTypeMix } from "./charts";
import type { SymptomResponse, MealWithSymptoms } from "@/types/api";

const sym = (symptom_type: string): SymptomResponse => ({ id: Math.random().toString(), symptom_type, logged_at: "x" });
const meal = (meal_type?: string): MealWithSymptoms => ({ id: Math.random().toString(), description: "x", logged_at: "x", created_at: "x", meal_type, symptoms: [] });

test("symptomFrequency counts per type, sorted desc", () => {
  const out = symptomFrequency([sym("bloating"), sym("bloating"), sym("nausea")]);
  expect(out).toEqual([{ type: "bloating", count: 2 }, { type: "nausea", count: 1 }]);
});

test("mealTypeMix counts per meal type in canonical order, drops zero buckets", () => {
  const out = mealTypeMix([meal("lunch"), meal("lunch"), meal("breakfast")]);
  expect(out).toEqual([{ type: "breakfast", count: 1 }, { type: "lunch", count: 2 }]);
});

test("mealTypeMix buckets missing meal_type as other", () => {
  const out = mealTypeMix([meal(undefined)]);
  expect(out).toEqual([{ type: "other", count: 1 }]);
});
