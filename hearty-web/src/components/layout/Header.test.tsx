import { expect, test, vi } from "vitest";
import userEvent from "@testing-library/user-event";
import { screen } from "@testing-library/react";
import { renderWithProviders } from "../../test/utils";

vi.mock("../../lib/auth", () => ({ signOut: vi.fn() }));

import Header from "./Header";
import { signOut } from "../../lib/auth";

test("sign out button calls signOut", async () => {
  renderWithProviders(<Header status="live" />);
  await userEvent.click(screen.getByRole("button", { name: /sign out/i }));
  expect(signOut).toHaveBeenCalledOnce();
});
