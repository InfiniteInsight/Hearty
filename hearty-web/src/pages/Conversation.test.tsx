import { expect, test, vi } from "vitest";
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
import { renderWithProviders } from "../test/utils";
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } },
}));
import Conversation from "./Conversation";

test("shows opener, sends a message, and confirms a proposed verdict", async () => {
  let verdictPosted = false;
  server.use(
    http.post("*/api/trends/conversation", async ({ request }) => {
      const body = (await request.json()) as { history: unknown[] };
      if (body.history.length === 0) {
        return HttpResponse.json({ reply: "Hey, noticed milk lately.", proposed_verdict: null, proposed_experiment: null, is_closing: false });
      }
      return HttpResponse.json({ reply: "Want to confirm?", proposed_verdict: { category: "milk", category_label: "Milk & Dairy", outcome_type: "symptom", outcome_name: "bloating", verdict: "confirmed" }, proposed_experiment: null, is_closing: false });
    }),
    http.post("*/api/trends/signal-verdict", () => { verdictPosted = true; return HttpResponse.json({ ok: true }); }),
  );
  renderWithProviders(<Conversation />, { route: "/trends/chat" });
  expect(await screen.findByText(/noticed milk/i)).toBeInTheDocument();
  await userEvent.type(screen.getByPlaceholderText(/message/i), "tell me more");
  await userEvent.click(screen.getByRole("button", { name: /send/i }));
  await screen.findByText(/want to confirm/i);
  await userEvent.click(screen.getByRole("button", { name: /^confirm$/i }));
  await vi.waitFor(() => expect(verdictPosted).toBe(true));
});
