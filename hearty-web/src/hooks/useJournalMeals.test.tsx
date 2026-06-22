import { expect, test, vi } from "vitest";
import { screen } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
import { renderWithProviders } from "../test/utils";
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } },
}));
import { useJournalMeals } from "./useJournalMeals";

function Probe() {
  const q = useJournalMeals({ keyword: "rice", page: 1 });
  return <div>{q.isSuccess ? `total:${q.data.total}` : "loading"}</div>;
}

test("requests the right page window and forwards filters", async () => {
  let seen: Record<string, string | null> = {};
  server.use(
    http.get("*/api/meals", ({ request }) => {
      const u = new URL(request.url);
      seen = {
        limit: u.searchParams.get("limit"),
        offset: u.searchParams.get("offset"),
        keyword: u.searchParams.get("keyword"),
      };
      return HttpResponse.json({ total: 30, meals: [] });
    })
  );
  renderWithProviders(<Probe />);
  expect(await screen.findByText("total:30")).toBeInTheDocument();
  expect(seen).toEqual({ limit: "25", offset: "25", keyword: "rice" });
});
