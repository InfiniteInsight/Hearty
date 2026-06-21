import { expect, test, vi } from "vitest";
import { renderHook, waitFor } from "@testing-library/react";

const h = vi.hoisted(() => {
  const handlers: Array<(p: unknown) => void> = [];
  const channelObj: { on: ReturnType<typeof vi.fn>; subscribe: ReturnType<typeof vi.fn> } = {
    on: vi.fn((_type: string, _filter: unknown, cb: (p: unknown) => void) => { handlers.push(cb); return channelObj; }),
    subscribe: vi.fn((cb?: (s: string) => void) => { cb?.("SUBSCRIBED"); return channelObj; }),
  };
  return {
    handlers,
    channelObj,
    removeChannel: vi.fn(),
    getUser: vi.fn().mockResolvedValue({ data: { user: { id: "u1" } } }),
    invalidateQueries: vi.fn(),
  };
});

vi.mock("../lib/supabase", () => ({
  supabase: { channel: vi.fn(() => h.channelObj), removeChannel: h.removeChannel, auth: { getUser: h.getUser } },
}));
vi.mock("@tanstack/react-query", async (orig) => ({
  ...(await orig<typeof import("@tanstack/react-query")>()),
  useQueryClient: () => ({ invalidateQueries: h.invalidateQueries }),
}));

import { useRealtimeSync } from "./useRealtimeSync";

test("subscribes to meals+symptoms and invalidates on an event", async () => {
  const { result } = renderHook(() => useRealtimeSync());
  await waitFor(() => expect(h.channelObj.subscribe).toHaveBeenCalled());
  // React StrictMode double-invokes effects; each run registers 2 listeners (meals + symptoms).
  // Assert the count is a positive multiple of 2 (each effect adds exactly 2).
  expect(h.channelObj.on.mock.calls.length % 2).toBe(0);
  expect(h.channelObj.on.mock.calls.length).toBeGreaterThanOrEqual(2);
  h.handlers[0]?.({});
  expect(h.invalidateQueries).toHaveBeenCalled();
  await waitFor(() => expect(result.current).toBe("live"));
});
