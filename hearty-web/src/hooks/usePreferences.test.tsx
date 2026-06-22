import { expect, test, vi } from "vitest";
import { renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } },
}));
import { usePreferences, useSavePreferences } from "./usePreferences";

function wrap() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={qc}>{children}</QueryClientProvider>
  );
}

test("usePreferences loads prefs", async () => {
  server.use(http.get("*/api/preferences", () => HttpResponse.json({ conversation_style: "warm", daily_checkin_enabled: true })));
  const { result } = renderHook(() => usePreferences(), { wrapper: wrap() });
  await waitFor(() => expect(result.current.data?.conversation_style).toBe("warm"));
});

test("useSavePreferences PUTs and resolves", async () => {
  server.use(http.put("*/api/preferences", () => HttpResponse.json({ conversation_style: "concise" })));
  const { result } = renderHook(() => useSavePreferences(), { wrapper: wrap() });
  // minimal partial cast is fine for the test
  await result.current.mutateAsync({ conversation_style: "concise" } as never);
  await waitFor(() => expect(result.current.isSuccess).toBe(true));
});
