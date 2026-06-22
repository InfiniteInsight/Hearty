import { expect, test } from "vitest";
import { startOfTodayISO } from "./time";
test("startOfTodayISO zeroes the time component", () => {
  const iso = startOfTodayISO(new Date("2026-06-21T15:30:00Z"));
  const d = new Date(iso);
  expect(d.getHours()).toBe(0); expect(d.getMinutes()).toBe(0); expect(d.getSeconds()).toBe(0);
});
