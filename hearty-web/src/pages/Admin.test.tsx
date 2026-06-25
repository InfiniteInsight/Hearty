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

test("shows signup policy and saves a mode change", async () => {
  let saved: unknown = null;
  server.use(
    http.get("*/api/admin/users", () => HttpResponse.json({ users: [] })),
    http.get("*/api/admin/settings", () => HttpResponse.json({ provisioning_mode: "open", trial_days: 14 })),
    http.put("*/api/admin/settings", async ({ request }) => { saved = await request.json(); return HttpResponse.json({ provisioning_mode: "paywall", trial_days: 14 }); }),
  );
  renderWithProviders(<Admin />, { route: "/admin" });
  const select = await screen.findByLabelText(/signup policy/i);
  await userEvent.selectOptions(select, "paywall");
  await userEvent.click(screen.getByRole("button", { name: /save policy/i }));
  await vi.waitFor(() => expect(saved).toMatchObject({ provisioning_mode: "paywall" }));
});

test("shows system health and runs an LLM test", async () => {
  let tested = false;
  server.use(
    http.get("*/api/admin/users", () => HttpResponse.json({ users: [] })),
    http.get("*/api/admin/health", () => HttpResponse.json({
      backend: { status: "ok", version: "1.0.0", revision: "r1", time: "2026-06-25T00:00:00Z" },
      supabase: { status: "down", error: "timeout" },
      llm: { status: "degraded", last_error: "boom", model: "m" },
    })),
    http.post("*/api/admin/health/llm-test", () => { tested = true; return HttpResponse.json({ ok: true, model: "m", latency_ms: 9 }); }),
  );
  renderWithProviders(<Admin />, { route: "/admin" });
  expect(await screen.findByText(/system health/i)).toBeInTheDocument();
  expect(await screen.findByText(/down/i)).toBeInTheDocument();
  await userEvent.click(screen.getByRole("button", { name: /test llm/i }));
  await vi.waitFor(() => expect(tested).toBe(true));
});
