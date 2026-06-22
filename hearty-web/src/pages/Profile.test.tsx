import { expect, test, vi } from "vitest";
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
import { renderWithProviders } from "../test/utils";
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } },
}));
import Profile from "./Profile";

const empty = { allergens: [], intolerances: [], conditions: [], dietary_protocols: [], updated_at: "x" };

test("shows the disclaimer and saves a quick-added allergen", async () => {
  let put: Record<string, unknown> | null = null;
  server.use(
    http.get("*/api/health-profile/defaults", () => HttpResponse.json({ allergens: ["Peanuts"], intolerances: [], conditions: [], dietary_protocols: [] })),
    http.get("*/api/health-profile", () => HttpResponse.json(empty)),
    http.put("*/api/health-profile", async ({ request }) => { put = (await request.json()) as Record<string, unknown>; return HttpResponse.json({ ...empty }); }),
  );
  renderWithProviders(<Profile />, { route: "/profile" });
  // Guard the verbatim disclaimer text (compliance-sensitive — must not drift).
  expect(await screen.findByText("Hearty is not a medical device. Information provided is for personal tracking only and does not constitute medical advice. Always consult a qualified healthcare professional.")).toBeInTheDocument();
  await userEvent.click(await screen.findByRole("button", { name: /^Peanuts$/ }));
  await userEvent.click(screen.getByRole("button", { name: /save profile/i }));
  await vi.waitFor(() => expect(put).not.toBeNull());
  expect((put!.allergens as unknown[])).toHaveLength(1);
  expect((put!.allergens as { name: string; severity: string }[])[0]).toMatchObject({ name: "Peanuts", severity: "mild" });
});
