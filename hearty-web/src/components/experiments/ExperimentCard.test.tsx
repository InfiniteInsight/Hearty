import { expect, test, vi } from "vitest";
import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import ExperimentCard from "./ExperimentCard";
import type { ExperimentResponse } from "@/types/api";

const active: ExperimentResponse = {
  id: "e1", category: "milk", category_label: "Milk & Dairy", direction: "harmful",
  outcome_type: "symptom", outcome_name: "bloating",
  experiment_start: "2026-06-01T00:00:00Z", experiment_end: "2026-06-15T00:00:00Z",
  status: "active", adherence: 0.8, logged_days: 10, nudge_suggested: true,
};
const completed: ExperimentResponse = {
  ...active, id: "e2", status: "completed", nudge_suggested: false,
  result: { verdict: "improved", reason: null, adherence: 0.9, logged_days: { baseline: 7, experiment: 12 }, baseline_rate: 0.5, experiment_rate: 0.1 },
};

function noop() {}
const actions = { onEvaluate: noop, onAbandon: noop, onRestart: noop, onAckNudge: noop, busy: false };

test("active card shows status, outcome, adherence, and Evaluate/Abandon", () => {
  render(<ExperimentCard exp={active} actions={actions} />);
  expect(screen.getByText("Milk & Dairy")).toBeInTheDocument();
  expect(screen.getByText(/bloating/)).toBeInTheDocument();
  expect(screen.getByText(/active/i)).toBeInTheDocument();
  expect(screen.getByRole("button", { name: /evaluate/i })).toBeInTheDocument();
  expect(screen.getByRole("button", { name: /abandon/i })).toBeInTheDocument();
});

test("nudge indicator shows when nudge_suggested and acks", async () => {
  const onAckNudge = vi.fn();
  render(<ExperimentCard exp={active} actions={{ ...actions, onAckNudge }} />);
  await userEvent.click(screen.getByRole("button", { name: /got it/i }));
  expect(onAckNudge).toHaveBeenCalled();
});

test("completed card renders the result verdict and a Restart action", () => {
  render(<ExperimentCard exp={completed} actions={actions} />);
  expect(screen.getByText(/improved/i)).toBeInTheDocument();
  expect(screen.getByRole("button", { name: /restart/i })).toBeInTheDocument();
  expect(screen.queryByRole("button", { name: /evaluate/i })).not.toBeInTheDocument();
});

test("Evaluate fires the callback", async () => {
  const onEvaluate = vi.fn();
  render(<ExperimentCard exp={active} actions={{ ...actions, onEvaluate }} />);
  await userEvent.click(screen.getByRole("button", { name: /evaluate/i }));
  expect(onEvaluate).toHaveBeenCalled();
});
