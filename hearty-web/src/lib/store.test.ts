import { beforeEach, expect, test } from "vitest";
import { useUiStore } from "./store";
beforeEach(() => useUiStore.setState({ sidebarOpen: true }));
test("sidebar toggles", () => {
  useUiStore.getState().setSidebarOpen(false);
  expect(useUiStore.getState().sidebarOpen).toBe(false);
});
