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
    http.get("*/api/admin/knowledge", () => HttpResponse.json({ entries: [] })),
    http.get("*/api/admin/prompt-overlays", () => HttpResponse.json({ overlays: [] })),
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
    http.get("*/api/admin/knowledge", () => HttpResponse.json({ entries: [] })),
    http.get("*/api/admin/prompt-overlays", () => HttpResponse.json({ overlays: [] })),
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
    http.get("*/api/admin/knowledge", () => HttpResponse.json({ entries: [] })),
    http.get("*/api/admin/prompt-overlays", () => HttpResponse.json({ overlays: [] })),
  );
  renderWithProviders(<Admin />, { route: "/admin" });
  expect(await screen.findByText(/system health/i)).toBeInTheDocument();
  expect(await screen.findByText(/down/i)).toBeInTheDocument();
  await userEvent.click(screen.getByRole("button", { name: /test llm/i }));
  await vi.waitFor(() => expect(tested).toBe(true));
});

test("knowledge base lists entries and adds one", async () => {
  let created: unknown = null;
  server.use(
    http.get("*/api/admin/users", () => HttpResponse.json({ users: [] })),
    http.get("*/api/admin/settings", () => HttpResponse.json({ provisioning_mode: "open", trial_days: 14 })),
    http.get("*/api/admin/health", () => HttpResponse.json({
      backend: { status: "ok", version: "1", revision: "r", time: "2026-06-25T00:00:00Z" },
      supabase: { status: "ok", latency_ms: 5 }, llm: { status: "idle" },
    })),
    http.get("*/api/admin/knowledge", () => HttpResponse.json({ entries: [
      { id: "kb1", title: "Low-FODMAP and IBS", source: "manual", conditions: ["ibs"], active: true, created_at: "2026-06-01" },
    ] })),
    http.post("*/api/admin/knowledge", async ({ request }) => {
      created = await request.json();
      return HttpResponse.json({ id: "kb2", title: "New", source: "manual", conditions: [], active: true, created_at: "2026-06-25" });
    }),
  );
  renderWithProviders(<Admin />, { route: "/admin" });
  expect(await screen.findByText(/Low-FODMAP and IBS/)).toBeInTheDocument();
  await userEvent.type(screen.getByLabelText("Content"), "New research excerpt");
  await userEvent.click(screen.getByRole("button", { name: /add entry/i }));
  await vi.waitFor(() => expect(created).toMatchObject({ content: "New research excerpt" }));
});

test("prompt tuning saves a guidance overlay", async () => {
  let saved: unknown = null;
  server.use(
    http.get("*/api/admin/users", () => HttpResponse.json({ users: [] })),
    http.get("*/api/admin/settings", () => HttpResponse.json({ provisioning_mode: "open", trial_days: 14 })),
    http.get("*/api/admin/health", () => HttpResponse.json({
      backend: { status: "ok", version: "1", revision: "r", time: "2026-06-26T00:00:00Z" },
      supabase: { status: "ok", latency_ms: 5 }, llm: { status: "idle" },
    })),
    http.get("*/api/admin/knowledge", () => HttpResponse.json({ entries: [] })),
    http.get("*/api/admin/prompt-overlays", () => HttpResponse.json({ overlays: [
      { surface: "summary", guidance: "", updated_at: "2026-06-26" },
      { surface: "trends_conversation", guidance: "", updated_at: "2026-06-26" },
    ] })),
    http.put("*/api/admin/prompt-overlays/summary", async ({ request }) => {
      saved = await request.json();
      return HttpResponse.json({ surface: "summary", guidance: "Keep it short.", updated_at: "2026-06-26" });
    }),
  );
  renderWithProviders(<Admin />, { route: "/admin" });
  const box = await screen.findByLabelText("summary overlay");
  await userEvent.type(box, "Keep it short.");
  await userEvent.click(screen.getByRole("button", { name: /save weekly summary/i }));
  await vi.waitFor(() => expect(saved).toMatchObject({ guidance: "Keep it short." }));
});
