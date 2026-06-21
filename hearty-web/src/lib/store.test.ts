import { expect, test } from "vitest";
import { useUiStore } from "./store";
test("sidebar toggles", () => {
  useUiStore.getState().setSidebarOpen(false);
  expect(useUiStore.getState().sidebarOpen).toBe(false);
});
