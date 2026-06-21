import { expect, test, vi } from "vitest";
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { render } from "@testing-library/react";
vi.mock("../../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } },
}));
import MealCard from "./MealCard";
import type { MealWithSymptoms } from "@/types/api";

const meal: MealWithSymptoms = {
  id: "m1", description: "oatmeal with milk", logged_at: "2026-06-21T08:00:00Z",
  created_at: "2026-06-21T08:00:00Z", meal_type: "breakfast", notes: "felt fine",
  foods: [{ name: "oats" }, { name: "milk" }],
  symptoms: [{ id: "s1", symptom_type: "bloating", severity: 5, logged_at: "2026-06-21T09:00:00Z" }],
};

test("renders description, food badges, and symptom badge", () => {
  render(<ul><MealCard meal={meal} /></ul>);
  expect(screen.getByText("oatmeal with milk")).toBeInTheDocument();
  expect(screen.getByText("oats")).toBeInTheDocument();
  expect(screen.getByText(/bloating 5/)).toBeInTheDocument();
});

test("expands to show notes and raw JSON toggle", async () => {
  render(<ul><MealCard meal={meal} /></ul>);
  expect(screen.queryByText("felt fine")).not.toBeInTheDocument();
  await userEvent.click(screen.getByRole("button", { name: /oatmeal with milk/i }));
  expect(screen.getByText("felt fine")).toBeInTheDocument();
  await userEvent.click(screen.getByRole("button", { name: /show raw data/i }));
  expect(screen.getByText(/"id": "m1"/)).toBeInTheDocument();
});

test("symptomTypeFilter hides non-matching symptom badges", () => {
  render(<ul><MealCard meal={meal} symptomTypeFilter="nausea" /></ul>);
  expect(screen.queryByText(/bloating/)).not.toBeInTheDocument();
});
