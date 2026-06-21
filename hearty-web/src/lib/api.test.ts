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

test("patchMeal sends PATCH with JSON body", async () => {
  let method = "";
  let body: unknown = null;
  server.use(
    http.patch("http://api.test/api/meals/m1", async ({ request }) => {
      method = request.method;
      body = await request.json();
      return HttpResponse.json({ id: "m1", description: "edited", logged_at: "z", created_at: "z" });
    })
  );
  const { createApiClient } = await import("./api");
  await createApiClient("http://api.test").patchMeal("m1", { description: "edited", foods: ["rice"] });
  expect(method).toBe("PATCH");
  expect(body).toEqual({ description: "edited", foods: ["rice"] });
});

test("deleteMeal sends DELETE and tolerates 204", async () => {
  server.use(http.delete("http://api.test/api/meals/m1", () => new HttpResponse(null, { status: 204 })));
  const { createApiClient } = await import("./api");
  await expect(createApiClient("http://api.test").deleteMeal("m1")).resolves.toBeUndefined();
});

test("patchSymptom sends description field", async () => {
  let body: unknown = null;
  server.use(
    http.patch("http://api.test/api/symptoms/s1", async ({ request }) => {
      body = await request.json();
      return HttpResponse.json({ id: "s1", symptom_type: "bloating", logged_at: "z" });
    })
  );
  const { createApiClient } = await import("./api");
  await createApiClient("http://api.test").patchSymptom("s1", { description: "less bloated", severity: 3 });
  expect(body).toEqual({ description: "less bloated", severity: 3 });
});

test("analyzeTrends posts and returns status", async () => {
  server.use(
    http.post("http://api.test/api/trends/analyze", () =>
      HttpResponse.json({ status: "completed", analyzed_at: "2026-06-21T00:00:00Z", new_signals_count: 2 })
    )
  );
  const { createApiClient } = await import("./api");
  const r = await createApiClient("http://api.test").analyzeTrends();
  expect(r.new_signals_count).toBe(2);
});

test("getAnalyzeStatus returns has_new_data", async () => {
  server.use(
    http.get("http://api.test/api/trends/analyze/status", () =>
      HttpResponse.json({ last_analyzed_at: "2026-06-20T00:00:00Z", has_new_data: true })
    )
  );
  const { createApiClient } = await import("./api");
  const r = await createApiClient("http://api.test").getAnalyzeStatus();
  expect(r.has_new_data).toBe(true);
});

test("signalVerdict posts category + verdict", async () => {
  let body: unknown = null;
  server.use(
    http.post("http://api.test/api/trends/signal-verdict", async ({ request }) => {
      body = await request.json();
      return HttpResponse.json({ ok: true });
    })
  );
  const { createApiClient } = await import("./api");
  await createApiClient("http://api.test").signalVerdict({
    category: "milk", outcome_type: "symptom", outcome_name: "bloating", verdict: "confirmed",
  });
  expect(body).toEqual({ category: "milk", outcome_type: "symptom", outcome_name: "bloating", verdict: "confirmed" });
});
