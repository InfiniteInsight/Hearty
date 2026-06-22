import { expect, test, vi } from "vitest";
import { fireEvent, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
import { renderWithProviders } from "../test/utils";
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } },
}));
const saveBlob = vi.fn();
vi.mock("../lib/download", () => ({ saveBlob: (...a: unknown[]) => saveBlob(...a) }));
import Reports from "./Reports";

test("CSV export fetches a blob and saves it", async () => {
  server.use(
    http.get("*/api/export/csv", () => new HttpResponse("a,b\n", { headers: { "Content-Type": "text/csv", "Content-Disposition": "attachment; filename=hearty-export.csv" } })),
  );
  renderWithProviders(<Reports />, { route: "/reports" });
  await userEvent.click(screen.getByRole("button", { name: /csv/i }));
  await vi.waitFor(() => expect(saveBlob).toHaveBeenCalledWith(expect.anything(), "hearty-export.csv"));
});

test("preview loads a summary when both dates are set", async () => {
  server.use(
    http.get("*/api/summary", () => HttpResponse.json({ period: "custom", start_date: "x", end_date: "y", summary_text: "Steady fortnight.", meals_logged: 12, top_symptoms: [] })),
  );
  renderWithProviders(<Reports />, { route: "/reports" });
  // <input type="date"> doesn't accept userEvent.type reliably in jsdom — set value directly.
  fireEvent.change(screen.getByLabelText(/from/i), { target: { value: "2026-06-01" } });
  fireEvent.change(screen.getByLabelText(/to/i), { target: { value: "2026-06-15" } });
  await userEvent.click(screen.getByRole("button", { name: /preview/i }));
  expect(await screen.findByText("Steady fortnight.")).toBeInTheDocument();
});
