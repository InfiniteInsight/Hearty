import { afterEach, expect, test, vi } from "vitest";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";

vi.mock("./supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "tok-123" } } }) } },
}));

afterEach(() => vi.clearAllMocks());

test("getMeals attaches Bearer token and returns parsed body", async () => {
  let seen = "";
  server.use(
    http.get("http://api.test/api/meals", ({ request }) => {
      seen = request.headers.get("authorization") ?? "";
      const url = new URL(request.url);
      expect(url.searchParams.get("start_date")).toBe("2026-06-21T00:00:00.000Z");
      return HttpResponse.json({ total: 0, meals: [] });
    })
  );
  const { createApiClient } = await import("./api");
  const api = createApiClient("http://api.test");
  const res = await api.getMeals({ start_date: "2026-06-21T00:00:00.000Z" });
  expect(seen).toBe("Bearer tok-123");
  expect(res).toEqual({ total: 0, meals: [] });
});

test("throws ApiError on 401", async () => {
  server.use(http.get("http://api.test/api/trends", () => new HttpResponse(null, { status: 401 })));
  const { createApiClient, ApiError } = await import("./api");
  await expect(createApiClient("http://api.test").getTrends()).rejects.toBeInstanceOf(ApiError);
});
