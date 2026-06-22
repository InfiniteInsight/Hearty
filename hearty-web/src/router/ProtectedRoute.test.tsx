import { expect, test, vi } from "vitest";
import { screen } from "@testing-library/react";
import { Route, Routes } from "react-router-dom";
import { renderWithProviders } from "../test/utils";

vi.mock("../lib/auth", () => ({ getSession: vi.fn() }));
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { onAuthStateChange: () => ({ data: { subscription: { unsubscribe: () => {} } } }) } },
}));

import ProtectedRoute from "./ProtectedRoute";
import { getSession } from "../lib/auth";

function tree() {
  return (
    <Routes>
      <Route path="/login" element={<div>login page</div>} />
      <Route element={<ProtectedRoute />}>
        <Route path="/dashboard" element={<div>secret</div>} />
      </Route>
    </Routes>
  );
}

test("redirects to /login with no session", async () => {
  vi.mocked(getSession).mockResolvedValue(null);
  renderWithProviders(tree(), { route: "/dashboard" });
  expect(await screen.findByText("login page")).toBeInTheDocument();
});

test("renders children with a session", async () => {
  vi.mocked(getSession).mockResolvedValue({ access_token: "t" } as never);
  renderWithProviders(tree(), { route: "/dashboard" });
  expect(await screen.findByText("secret")).toBeInTheDocument();
});
