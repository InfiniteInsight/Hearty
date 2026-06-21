import { expect, test, vi } from "vitest";
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
import { renderWithProviders } from "../test/utils";
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } },
}));
// Recharts ResponsiveContainer needs a non-zero size; stub it so children render in jsdom.
vi.mock("recharts", async (orig) => {
  const actual = await orig<typeof import("recharts")>();
  return { ...actual, ResponsiveContainer: ({ children }: { children: React.ReactNode }) => <div style={{ width: 400, height: 200 }}>{children}</div> };
});
import Trends from "./Trends";

const trends = {
  analyzed_at: "2026-06-21T00:00:00Z", total_meals_analyzed: 40, total_symptoms_analyzed: 8, total_wellbeing_analyzed: 0, resolved: [],
  signals: [{ category: "milk", category_label: "Milk & Dairy", unified_score: 0.8, convergent: false, years_seen: [], recurring: false, is_new: false, strength_by_year: {}, channels: [{ outcome_type: "symptom", outcome_name: "bloating", direction: "harmful", relative_risk: 2.1, evidence_count: 9 }] }],
};

function baseHandlers(postSpy?: () => void) {
  return [
    http.get("*/api/trends", () => HttpResponse.json(trends)),
    http.get("*/api/trends/analyze/status", () => HttpResponse.json({ last_analyzed_at: "2026-06-21T00:00:00Z", has_new_data: false })),
    http.get("*/api/symptoms", () => HttpResponse.json([])),
    http.get("*/api/meals", () => HttpResponse.json({ total: 0, meals: [] })),
    http.post("*/api/trends/analyze", () => { postSpy?.(); return HttpResponse.json({ status: "completed", analyzed_at: "x", new_signals_count: 0 }); }),
  ];
}

test("renders a signal card", async () => {
  server.use(...baseHandlers());
  renderWithProviders(<Trends />, { route: "/trends" });
  // "Milk & Dairy" appears in both TrendsHero and SignalCard; use findAllByText
  expect((await screen.findAllByText("Milk & Dairy")).length).toBeGreaterThan(0);
});

test("Analyse pill triggers POST /api/trends/analyze", async () => {
  let posted = false;
  server.use(...baseHandlers(() => { posted = true; }));
  renderWithProviders(<Trends />, { route: "/trends" });
  await screen.findAllByText("Milk & Dairy");
  await userEvent.click(screen.getByRole("button", { name: /analyse/i }));
  await vi.waitFor(() => expect(posted).toBe(true));
});
