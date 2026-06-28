import { expect, test, vi } from "vitest";
import { screen } from "@testing-library/react";
import { Route, Routes } from "react-router-dom";
import { renderWithProviders } from "../test/utils";

vi.mock("../lib/auth", () => ({ isAdmin: vi.fn() }));

import RequireAdmin from "./RequireAdmin";
import { isAdmin } from "../lib/auth";

function tree() {
  return (
    <Routes>
      <Route path="/dashboard" element={<div>dashboard</div>} />
      <Route element={<RequireAdmin />}>
        <Route path="/admin" element={<div>admin panel</div>} />
      </Route>
    </Routes>
  );
}

test("renders admin page for an admin", async () => {
  vi.mocked(isAdmin).mockResolvedValue(true);
  renderWithProviders(tree(), { route: "/admin" });
  expect(await screen.findByText("admin panel")).toBeInTheDocument();
});

test("redirects non-admins to /dashboard", async () => {
  vi.mocked(isAdmin).mockResolvedValue(false);
  renderWithProviders(tree(), { route: "/admin" });
  expect(await screen.findByText("dashboard")).toBeInTheDocument();
  expect(screen.queryByText("admin panel")).not.toBeInTheDocument();
});

test("redirects to /dashboard when the admin check errors", async () => {
  vi.mocked(isAdmin).mockRejectedValue(new Error("boom"));
  renderWithProviders(tree(), { route: "/admin" });
  expect(await screen.findByText("dashboard")).toBeInTheDocument();
});
