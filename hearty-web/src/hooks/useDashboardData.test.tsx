import { expect, test, vi } from "vitest";
import { screen } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
import { renderWithProviders } from "../test/utils";
vi.mock("../lib/supabase", () => ({ supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } } }));

import { useTodayMeals } from "./useMeals";
function Probe() { const q = useTodayMeals(); return <div>{q.isSuccess ? `meals:${q.data.total}` : "loading"}</div>; }

test("useTodayMeals loads today's meals", async () => {
  server.use(http.get("*/api/meals", () => HttpResponse.json({ total: 2, meals: [] })));
  renderWithProviders(<Probe />);
  expect(await screen.findByText("meals:2")).toBeInTheDocument();
});
