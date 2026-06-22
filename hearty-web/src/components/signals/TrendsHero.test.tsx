import { expect, test } from "vitest";
import { render, screen } from "@testing-library/react";
import TrendsHero from "./TrendsHero";
import type { SignalsResponse } from "@/types/api";

const data: SignalsResponse = {
  analyzed_at: "2026-06-21T00:00:00Z", total_meals_analyzed: 50, total_symptoms_analyzed: 10,
  total_wellbeing_analyzed: 5, resolved: [],
  signals: [
    { category: "milk", category_label: "Milk & Dairy", unified_score: 0.9, convergent: false, years_seen: [], recurring: false, is_new: false, strength_by_year: {}, channels: [{ outcome_type: "symptom", outcome_name: "bloating", direction: "harmful", peak_window_minutes: 60, relative_risk: 3.1, evidence_count: 20 }] },
    { category: "coffee", category_label: "Coffee", unified_score: 0.4, convergent: false, years_seen: [], recurring: false, is_new: false, strength_by_year: {}, channels: [] },
  ],
};

test("renders the highest-score signal with a 3-up stat row", () => {
  render(<TrendsHero data={data} />);
  expect(screen.getByText("Milk & Dairy")).toBeInTheDocument();
  expect(screen.getByText(/3\.1×/)).toBeInTheDocument();
  expect(screen.getByText(/60\s*min/)).toBeInTheDocument();
  expect(screen.getByText(/20/)).toBeInTheDocument();
});

test("renders nothing when there are no signals", () => {
  const { container } = render(<TrendsHero data={{ ...data, signals: [] }} />);
  expect(container).toBeEmptyDOMElement();
});
