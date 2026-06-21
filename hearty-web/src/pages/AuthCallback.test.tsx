import { expect, test, vi } from "vitest";
import { screen, render } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router-dom";

vi.mock("../lib/supabase", () => ({
  supabase: { auth: {
    getSession: vi.fn(),
    onAuthStateChange: vi.fn(() => ({ data: { subscription: { unsubscribe: () => {} } } })),
  } },
}));
import { supabase } from "../lib/supabase";
import AuthCallback from "./AuthCallback";

function renderCallback() {
  return render(
    <MemoryRouter initialEntries={["/auth/callback"]}>
      <Routes>
        <Route path="/auth/callback" element={<AuthCallback />} />
        <Route path="/dashboard" element={<div>dashboard</div>} />
        <Route path="/login" element={<div>login</div>} />
      </Routes>
    </MemoryRouter>
  );
}

test("navigates to dashboard when a session is present", async () => {
  vi.mocked(supabase.auth.getSession).mockResolvedValue({ data: { session: { access_token: "t" } } } as never);
  renderCallback();
  expect(await screen.findByText("dashboard")).toBeInTheDocument();
});

test("navigates to login when no session (failed/empty callback)", async () => {
  vi.mocked(supabase.auth.getSession).mockResolvedValue({ data: { session: null } } as never);
  renderCallback();
  expect(await screen.findByText("login")).toBeInTheDocument();
});
