import { expect, test, vi } from "vitest";
import { renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } },
}));
import { useActiveExperiments, useExperimentActions } from "./useExperiments";

function wrap() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={qc}>{children}</QueryClientProvider>
  );
}

test("useActiveExperiments loads the list", async () => {
  server.use(http.get("*/api/experiments/active", () => HttpResponse.json({ experiments: [{ id: "e1", category: "milk", direction: "harmful", outcome_type: "symptom", outcome_name: "bloating", experiment_start: "x", experiment_end: "y", status: "active", nudge_suggested: false }] })));
  const { result } = renderHook(() => useActiveExperiments(), { wrapper: wrap() });
  await waitFor(() => expect(result.current.data?.experiments).toHaveLength(1));
});

test("create mutation posts and resolves", async () => {
  server.use(http.post("*/api/experiments", () => HttpResponse.json({ id: "e2", category: "milk", direction: "harmful", outcome_type: "symptom", outcome_name: "bloating", experiment_start: "x", experiment_end: "y", status: "active", nudge_suggested: false })));
  const { result } = renderHook(() => useExperimentActions(), { wrapper: wrap() });
  await result.current.create.mutateAsync({ category: "milk", outcome_type: "symptom", outcome_name: "bloating" });
  await waitFor(() => expect(result.current.create.isSuccess).toBe(true));
});
