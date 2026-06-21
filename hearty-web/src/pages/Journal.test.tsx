import { expect, test, vi } from "vitest";
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
import { renderWithProviders } from "../test/utils";
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } },
}));
import Journal from "./Journal";

const meal = {
  id: "m1", description: "rice bowl", logged_at: "2026-06-21T12:00:00Z", created_at: "2026-06-21T12:00:00Z",
  meal_type: "lunch", foods: [{ name: "rice" }], symptoms: [],
};

test("lists meals and forwards keyword filter to the API", async () => {
  let lastKeyword: string | null = null;
  server.use(
    http.get("*/api/meals", ({ request }) => {
      lastKeyword = new URL(request.url).searchParams.get("keyword");
      return HttpResponse.json({ total: 1, meals: [meal] });
    })
  );
  renderWithProviders(<Journal />, { route: "/journal" });
  expect(await screen.findByText("rice bowl")).toBeInTheDocument();
  await userEvent.type(screen.getByPlaceholderText(/search/i), "rice{enter}");
  await vi.waitFor(() => expect(lastKeyword).toBe("rice"));
});

test("shows empty state when no meals", async () => {
  server.use(http.get("*/api/meals", () => HttpResponse.json({ total: 0, meals: [] })));
  renderWithProviders(<Journal />, { route: "/journal" });
  expect(await screen.findByText(/no entries/i)).toBeInTheDocument();
});
