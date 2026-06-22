import { expect, test, vi } from "vitest";
import { renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } },
}));
import { useAnalyzeStatus, useAnalyze, useSignalVerdict } from "./useTrendsActions";

function wrap() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={qc}>{children}</QueryClientProvider>
  );
}

test("useAnalyzeStatus loads has_new_data", async () => {
  server.use(http.get("*/api/trends/analyze/status", () => HttpResponse.json({ last_analyzed_at: "x", has_new_data: true })));
  const { result } = renderHook(() => useAnalyzeStatus(), { wrapper: wrap() });
  await waitFor(() => expect(result.current.data?.has_new_data).toBe(true));
});

test("useAnalyze posts and resolves", async () => {
  server.use(http.post("*/api/trends/analyze", () => HttpResponse.json({ status: "completed", analyzed_at: "x", new_signals_count: 1 })));
  const { result } = renderHook(() => useAnalyze(), { wrapper: wrap() });
  await result.current.mutateAsync();
  await waitFor(() => expect(result.current.isSuccess).toBe(true));
});

test("useSignalVerdict posts the verdict", async () => {
  let body: unknown = null;
  server.use(http.post("*/api/trends/signal-verdict", async ({ request }) => { body = await request.json(); return HttpResponse.json({ ok: true }); }));
  const { result } = renderHook(() => useSignalVerdict(), { wrapper: wrap() });
  await result.current.mutateAsync({ category: "milk", outcome_type: "symptom", outcome_name: "bloating", verdict: "snoozed" });
  expect((body as { verdict: string }).verdict).toBe("snoozed");
});
