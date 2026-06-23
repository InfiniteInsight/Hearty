import { expect, test, vi } from "vitest";
import { screen } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
import { renderWithProviders } from "../test/utils";
vi.mock("../lib/supabase", () => ({ supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } } }));
import LicenseGate from "./LicenseGate";

test("renders children when license active", async () => {
  server.use(http.get("*/api/license/status", () => HttpResponse.json({ status: "active" })));
  renderWithProviders(<LicenseGate><div>dashboard</div></LicenseGate>);
  expect(await screen.findByText("dashboard")).toBeInTheDocument();
});

test("shows no-access screen when not active", async () => {
  server.use(http.get("*/api/license/status", () => HttpResponse.json({ status: "none" })));
  renderWithProviders(<LicenseGate><div>dashboard</div></LicenseGate>);
  expect(await screen.findByText(/no active access/i)).toBeInTheDocument();
  expect(screen.queryByText("dashboard")).not.toBeInTheDocument();
});
