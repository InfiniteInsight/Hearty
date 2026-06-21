import { expect, test, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import SignalCard from "./SignalCard";
import type { FoodSignal } from "@/types/api";

const signal: FoodSignal = {
  category: "milk", category_label: "Milk & Dairy", unified_score: 0.8, convergent: true,
  years_seen: [2026], recurring: false, is_new: true, strength_by_year: {},
  channels: [{ outcome_type: "symptom", outcome_name: "bloating", direction: "harmful", peak_window_minutes: 90, relative_risk: 2.4, evidence_count: 12 }],
};

test("renders label, dominant channel, relative risk, and CONVERGENT badge", () => {
  render(<SignalCard signal={signal} />);
  expect(screen.getByText("Milk & Dairy")).toBeInTheDocument();
  expect(screen.getByText(/bloating/)).toBeInTheDocument();
  expect(screen.getByText(/2\.4×/)).toBeInTheDocument();
  expect(screen.getByText("CONVERGENT")).toBeInTheDocument();
  expect(screen.getByText("NEW")).toBeInTheDocument();
});

test("fires onVerdict when an action is clicked", async () => {
  const onVerdict = vi.fn();
  render(<SignalCard signal={signal} onVerdict={onVerdict} />);
  await userEvent.click(screen.getByRole("button", { name: /confirm/i }));
  expect(onVerdict).toHaveBeenCalledWith("confirmed");
});
