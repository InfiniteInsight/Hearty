import { expect, test, vi } from "vitest";
import userEvent from "@testing-library/user-event";
import { screen } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
import { renderWithProviders } from "../test/utils";
vi.mock("../lib/supabase", () => ({ supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } } }));
import Dashboard from "./Dashboard";

const meal = { id: "m1", description: "oatmeal", logged_at: "2026-06-21T08:00:00Z", created_at: "2026-06-21T08:00:00Z", foods: [{ name: "oats" }], symptoms: [] };

test("renders today data and submits quick-log", async () => {
  let posted = "";
  server.use(
    http.get("*/api/meals", () => HttpResponse.json({ total: 1, meals: [meal] })),
    http.get("*/api/symptoms", () => HttpResponse.json([])),
    http.get("*/api/summary", () => HttpResponse.json({ period: "week", start_date: "x", end_date: "y", summary_text: "Looking steady.", meals_logged: 5, top_symptoms: [] })),
    http.get("*/api/trends", () => HttpResponse.json({ signals: [{ category: "milk", category_label: "Milk & Dairy", unified_score: 0.8, channels: [{ outcome_type: "symptom", outcome_name: "bloating", direction: "harmful", evidence_count: 9 }], convergent: false, years_seen: [], recurring: false, is_new: true, strength_by_year: {} }], analyzed_at: null, total_meals_analyzed: 10, total_symptoms_analyzed: 3, total_wellbeing_analyzed: 0, resolved: [] })),
    http.post("*/api/meals", async ({ request }) => { posted = ((await request.json()) as { description: string }).description; return HttpResponse.json({ id: "m2", description: posted, logged_at: "z", created_at: "z" }, { status: 201 }); }),
  );
  renderWithProviders(<Dashboard />);
  expect(await screen.findByText("oatmeal")).toBeInTheDocument();
  expect(screen.getByText("Looking steady.")).toBeInTheDocument();
  expect(screen.getByText(/Milk & Dairy/)).toBeInTheDocument();
  await userEvent.type(screen.getByPlaceholderText(/log a meal/i), "banana");
  await userEvent.click(screen.getByRole("button", { name: /log/i }));
  await vi.waitFor(() => expect(posted).toBe("banana"));
});
