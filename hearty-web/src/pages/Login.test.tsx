import { expect, test, vi } from "vitest";
import userEvent from "@testing-library/user-event";
import { screen } from "@testing-library/react";
import { renderWithProviders } from "../test/utils";

vi.mock("../lib/auth", () => ({ signInWithGoogle: vi.fn() }));

import Login from "./Login";
import { signInWithGoogle } from "../lib/auth";

test("clicking the button starts Google sign-in", async () => {
  renderWithProviders(<Login />);
  await userEvent.click(screen.getByRole("button", { name: /continue with google/i }));
  expect(signInWithGoogle).toHaveBeenCalledOnce();
});
