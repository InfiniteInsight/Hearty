import { expect, test, vi } from "vitest";
import { renderHook, waitFor } from "@testing-library/react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } },
}));
import { useHealthProfile, useHealthProfileDefaults, useSaveHealthProfile } from "./useHealthProfile";

function wrap() {
  const qc = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  return ({ children }: { children: React.ReactNode }) => (
    <QueryClientProvider client={qc}>{children}</QueryClientProvider>
  );
}

test("useHealthProfile loads the profile", async () => {
  server.use(http.get("*/api/health-profile", () => HttpResponse.json({ allergens: [{ name: "peanut", severity: "severe", confirmed_by_doctor: true }], intolerances: [], conditions: [], dietary_protocols: [], updated_at: "x" })));
  const { result } = renderHook(() => useHealthProfile(), { wrapper: wrap() });
  await waitFor(() => expect(result.current.data?.allergens).toHaveLength(1));
});

test("useHealthProfileDefaults loads suggestions", async () => {
  server.use(http.get("*/api/health-profile/defaults", () => HttpResponse.json({ allergens: ["Peanuts"], intolerances: [], conditions: [], dietary_protocols: [] })));
  const { result } = renderHook(() => useHealthProfileDefaults(), { wrapper: wrap() });
  await waitFor(() => expect(result.current.data?.allergens).toEqual(["Peanuts"]));
});

test("useSaveHealthProfile PUTs and resolves", async () => {
  server.use(http.put("*/api/health-profile", () => HttpResponse.json({ allergens: [], intolerances: [], conditions: [], dietary_protocols: [], updated_at: "x" })));
  const { result } = renderHook(() => useSaveHealthProfile(), { wrapper: wrap() });
  await result.current.mutateAsync({ allergens: [], intolerances: [], conditions: [], dietary_protocols: [] });
  await waitFor(() => expect(result.current.isSuccess).toBe(true));
});
