import { expect, test, vi } from "vitest";
import { screen } from "@testing-library/react";
import { Route, Routes } from "react-router-dom";
import { http, HttpResponse } from "msw";
import { server } from "../../test/msw/server";
import { renderWithProviders } from "../../test/utils";
vi.mock("../../hooks/useRealtimeSync", () => ({ useRealtimeSync: () => "live" }));
vi.mock("../../lib/auth", () => ({ signOut: vi.fn(), isAdmin: vi.fn().mockResolvedValue(false) }));
vi.mock("../../lib/supabase", () => ({ supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } } }));
import AppShell from "./AppShell";

test("shell shows primary nav and child route", async () => {
  server.use(http.get("*/api/license/status", () => HttpResponse.json({ status: "active" })));
  renderWithProviders(
    <Routes><Route element={<AppShell />}><Route path="/dashboard" element={<div>child</div>} /></Route></Routes>,
    { route: "/dashboard" }
  );
  for (const label of ["Dashboard", "Journal", "Trends", "Experiments", "Reports", "Profile", "Settings"]) {
    expect(screen.getByRole("link", { name: label })).toBeInTheDocument();
  }
  expect(await screen.findByText("child")).toBeInTheDocument();
});
