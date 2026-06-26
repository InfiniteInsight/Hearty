import { expect, test, vi } from "vitest";
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { render } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { MemoryRouter } from "react-router-dom";
import { http, HttpResponse } from "msw";
import { server } from "../../test/msw/server";
vi.mock("../../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } },
}));
import MealCard from "./MealCard";
import type { MealWithSymptoms } from "@/types/api";

const meal: MealWithSymptoms = {
  id: "m1", description: "oatmeal with milk", logged_at: "2026-06-21T08:00:00Z",
  created_at: "2026-06-21T08:00:00Z", meal_type: "breakfast", notes: "felt fine",
  foods: [{ name: "oats", estimated_calories: 150 }, { name: "milk", estimated_calories: 60 }],
  symptoms: [{ id: "s1", symptom_type: "bloating", severity: 5, logged_at: "2026-06-21T09:00:00Z" }],
};

function renderCard(ui: React.ReactElement) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(
    <QueryClientProvider client={qc}>
      <MemoryRouter>
        <ul>{ui}</ul>
      </MemoryRouter>
    </QueryClientProvider>
  );
}

test("renders description, food badges, and symptom badge", () => {
  renderCard(<MealCard meal={meal} />);
  expect(screen.getByText("oatmeal with milk")).toBeInTheDocument();
  expect(screen.getByText("oats")).toBeInTheDocument();
  expect(screen.getByText(/bloating 5/)).toBeInTheDocument();
});

test("expands to show notes and raw JSON toggle", async () => {
  renderCard(<MealCard meal={meal} />);
  expect(screen.queryByText("felt fine")).not.toBeInTheDocument();
  await userEvent.click(screen.getByRole("button", { name: /oatmeal with milk/i }));
  expect(screen.getByText("felt fine")).toBeInTheDocument();
  await userEvent.click(screen.getByRole("button", { name: /show raw data/i }));
  expect(screen.getByText(/"id": "m1"/)).toBeInTheDocument();
});

test("symptomTypeFilter hides non-matching symptom badges", () => {
  renderCard(<MealCard meal={meal} symptomTypeFilter="nausea" />);
  expect(screen.queryByText(/bloating/)).not.toBeInTheDocument();
});

test("edits description + foods via PATCH", async () => {
  let body: unknown = null;
  server.use(
    http.patch("*/api/meals/m1", async ({ request }) => {
      body = await request.json();
      return HttpResponse.json({ id: "m1", description: "edited", logged_at: "z", created_at: "z" });
    })
  );
  renderCard(<MealCard meal={meal} />);
  await userEvent.click(screen.getByRole("button", { name: /oatmeal with milk/i }));
  await userEvent.click(screen.getByRole("button", { name: /^edit$/i }));
  const desc = screen.getByLabelText(/description/i);
  await userEvent.clear(desc);
  await userEvent.type(desc, "edited");
  await userEvent.click(screen.getByRole("button", { name: /^save$/i }));
  await vi.waitFor(() => expect((body as { description: string }).description).toBe("edited"));
});

test("delete requires a confirm then issues DELETE", async () => {
  let deleted = false;
  server.use(http.delete("*/api/meals/m1", () => { deleted = true; return new HttpResponse(null, { status: 204 }); }));
  renderCard(<MealCard meal={meal} />);
  await userEvent.click(screen.getByRole("button", { name: /oatmeal with milk/i }));
  await userEvent.click(screen.getByRole("button", { name: /^delete$/i }));
  expect(deleted).toBe(false); // first click only arms the confirm
  await userEvent.click(screen.getByRole("button", { name: /confirm delete/i }));
  await vi.waitFor(() => expect(deleted).toBe(true));
});

test("raw data dump does not expose estimated_calories", async () => {
  renderCard(<MealCard meal={meal} />);
  await userEvent.click(screen.getByRole("button", { name: /oatmeal with milk/i }));
  await userEvent.click(screen.getByRole("button", { name: /show raw data/i }));
  // The food names should appear but calories must be stripped
  const pre = document.querySelector("pre");
  expect(pre?.textContent).toContain("oats");
  expect(pre?.textContent).not.toContain("estimated_calories");
});

test("expanded card shows a link to the Trends page", async () => {
  renderCard(<MealCard meal={meal} />);
  await userEvent.click(screen.getByRole("button", { name: /oatmeal with milk/i }));
  expect(screen.getByRole("link", { name: /view trends/i })).toHaveAttribute("href", "/trends");
});

test("expanded panel renders an editable SymptomRow", async () => {
  renderCard(<MealCard meal={meal} />);
  await userEvent.click(screen.getByRole("button", { name: /oatmeal with milk/i }));
  // the symptom's own edit control is distinct from the meal's "Edit"
  expect(screen.getByRole("button", { name: /edit bloating/i })).toBeInTheDocument();
});
