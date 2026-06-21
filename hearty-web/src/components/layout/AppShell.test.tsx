import { expect, test, vi } from "vitest";
import { screen } from "@testing-library/react";
import { Route, Routes } from "react-router-dom";
import { renderWithProviders } from "../../test/utils";
vi.mock("../../hooks/useRealtimeSync", () => ({ useRealtimeSync: () => "live" }));
import AppShell from "./AppShell";

test("shell shows primary nav and child route", () => {
  renderWithProviders(
    <Routes><Route element={<AppShell />}><Route path="/dashboard" element={<div>child</div>} /></Route></Routes>,
    { route: "/dashboard" }
  );
  for (const label of ["Dashboard", "Journal", "Trends", "Experiments", "Reports", "Profile", "Settings"]) {
    expect(screen.getByRole("link", { name: label })).toBeInTheDocument();
  }
  expect(screen.getByText("child")).toBeInTheDocument();
});
