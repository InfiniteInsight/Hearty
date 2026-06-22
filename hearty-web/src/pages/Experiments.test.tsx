import { expect, test, vi } from "vitest";
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
import { renderWithProviders } from "../test/utils";
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } },
}));
import Experiments from "./Experiments";

const exp = { id: "e1", category: "milk", category_label: "Milk & Dairy", direction: "harmful", outcome_type: "symptom", outcome_name: "bloating", experiment_start: "2026-06-01T00:00:00Z", experiment_end: "2026-06-15T00:00:00Z", status: "active", adherence: 0.8, logged_days: 10, nudge_suggested: false };

test("lists active experiments", async () => {
  server.use(http.get("*/api/experiments/active", () => HttpResponse.json({ experiments: [exp] })));
  renderWithProviders(<Experiments />, { route: "/experiments" });
  expect(await screen.findByText("Milk & Dairy")).toBeInTheDocument();
});

test("empty state when none", async () => {
  server.use(http.get("*/api/experiments/active", () => HttpResponse.json({ experiments: [] })));
  renderWithProviders(<Experiments />, { route: "/experiments" });
  expect(await screen.findByText(/no experiments/i)).toBeInTheDocument();
});

test("Evaluate calls the evaluate endpoint", async () => {
  let evaluated = false;
  server.use(
    http.get("*/api/experiments/active", () => HttpResponse.json({ experiments: [exp] })),
    http.post("*/api/experiments/e1/evaluate", () => { evaluated = true; return HttpResponse.json({ ...exp, status: "completed", result: { verdict: "no_change", reason: null, adherence: 0.8, logged_days: { baseline: 7, experiment: 10 }, baseline_rate: 0.2, experiment_rate: 0.2 } }); }),
  );
  renderWithProviders(<Experiments />, { route: "/experiments" });
  await userEvent.click(await screen.findByRole("button", { name: /evaluate/i }));
  await vi.waitFor(() => expect(evaluated).toBe(true));
});
