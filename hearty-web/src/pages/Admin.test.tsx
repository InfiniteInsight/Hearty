import { expect, test, vi } from "vitest";
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
import { renderWithProviders } from "../test/utils";
vi.mock("../lib/supabase", () => ({ supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t", user: { app_metadata: { role: "admin" } } } } }) } } }));
import Admin from "./Admin";

test("lists subscribers and revokes a license", async () => {
  let revoked = false;
  server.use(
    http.get("*/api/admin/users", () => HttpResponse.json({ users: [{ user_id: "u1", email: "a@x.com", created_at: "2026-01-01", license: { status: "active" } }] })),
    http.post("*/api/admin/licenses/u1/revoke", () => { revoked = true; return HttpResponse.json({ user_id: "u1", status: "revoked" }); }),
  );
  renderWithProviders(<Admin />, { route: "/admin" });
  expect(await screen.findByText("a@x.com")).toBeInTheDocument();
  await userEvent.click(screen.getByRole("button", { name: /revoke/i }));
  await vi.waitFor(() => expect(revoked).toBe(true));
});
