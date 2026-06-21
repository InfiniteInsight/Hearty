import { beforeEach, expect, test } from "vitest";
import { useUiStore } from "./store";
beforeEach(() => useUiStore.setState({ sidebarOpen: true, trendsPeriod: "30d" }));
test("sidebar toggles", () => {
  useUiStore.getState().setSidebarOpen(false);
  expect(useUiStore.getState().sidebarOpen).toBe(false);
});

test("trends period updates", () => {
  useUiStore.getState().setTrendsPeriod("90d");
  expect(useUiStore.getState().trendsPeriod).toBe("90d");
});
