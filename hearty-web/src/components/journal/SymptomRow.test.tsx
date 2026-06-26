import { expect, test, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { http, HttpResponse } from "msw";
import { server } from "../../test/msw/server";
vi.mock("../../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } },
}));
import SymptomRow from "./SymptomRow";
import type { SymptomResponse } from "@/types/api";

const symptom: SymptomResponse = { id: "s1", symptom_type: "bloating", severity: 5, logged_at: "2026-06-26T09:00:00Z" };

function renderRow(s: SymptomResponse) {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return render(<QueryClientProvider client={qc}><SymptomRow symptom={s} /></QueryClientProvider>);
}

test("renders the symptom badge", () => {
  renderRow(symptom);
  expect(screen.getByText(/bloating 5/)).toBeInTheDocument();
});

test("edits severity + type via PATCH", async () => {
  let body: unknown = null;
  server.use(http.patch("*/api/symptoms/s1", async ({ request }) => {
    body = await request.json();
    return HttpResponse.json({ id: "s1", symptom_type: "nausea", severity: 7, logged_at: "z" });
  }));
  renderRow(symptom);
  await userEvent.click(screen.getByRole("button", { name: /edit bloating/i }));
  await userEvent.selectOptions(screen.getByLabelText(/symptom type/i), "nausea");
  const sev = screen.getByLabelText(/severity/i);
  await userEvent.clear(sev);
  await userEvent.type(sev, "7");
  await userEvent.click(screen.getByRole("button", { name: /^save$/i }));
  await vi.waitFor(() => expect(body).toMatchObject({ symptom_type: "nausea", severity: 7 }));
});

test("delete requires a confirm then issues DELETE", async () => {
  let deleted = false;
  server.use(http.delete("*/api/symptoms/s1", () => { deleted = true; return new HttpResponse(null, { status: 204 }); }));
  renderRow(symptom);
  await userEvent.click(screen.getByRole("button", { name: /delete bloating/i }));
  expect(deleted).toBe(false);
  await userEvent.click(screen.getByRole("button", { name: /confirm delete bloating/i }));
  await vi.waitFor(() => expect(deleted).toBe(true));
});
