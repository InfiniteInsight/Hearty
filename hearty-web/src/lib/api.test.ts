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

test("trendsConversation posts history and returns reply", async () => {
  let body: unknown = null;
  server.use(
    http.post("http://api.test/api/trends/conversation", async ({ request }) => {
      body = await request.json();
      return HttpResponse.json({ reply: "Hi", proposed_verdict: null, proposed_experiment: null, is_closing: false });
    })
  );
  const { createApiClient } = await import("./api");
  const r = await createApiClient("http://api.test").trendsConversation({ history: [{ role: "user", content: "hey" }] });
  expect(body).toEqual({ history: [{ role: "user", content: "hey" }] });
  expect(r.reply).toBe("Hi");
});

test("createExperiment posts the pattern", async () => {
  let body: unknown = null;
  server.use(
    http.post("http://api.test/api/experiments", async ({ request }) => {
      body = await request.json();
      return HttpResponse.json({ id: "e1", category: "milk", direction: "harmful", outcome_type: "symptom", outcome_name: "bloating", experiment_start: "x", experiment_end: "y", status: "active", nudge_suggested: false });
    })
  );
  const { createApiClient } = await import("./api");
  await createApiClient("http://api.test").createExperiment({ category: "milk", outcome_type: "symptom", outcome_name: "bloating" });
  expect(body).toEqual({ category: "milk", outcome_type: "symptom", outcome_name: "bloating" });
});

test("createExperiment surfaces 409 as ApiError with status", async () => {
  server.use(http.post("http://api.test/api/experiments", () => new HttpResponse(null, { status: 409 })));
  const { createApiClient, ApiError } = await import("./api");
  await expect(createApiClient("http://api.test").createExperiment({ category: "milk", outcome_type: "symptom", outcome_name: "bloating" }))
    .rejects.toMatchObject({ status: 409 });
  // also assert the thrown value is an ApiError
  await expect(createApiClient("http://api.test").createExperiment({ category: "milk", outcome_type: "symptom", outcome_name: "bloating" }))
    .rejects.toBeInstanceOf(ApiError);
});

test("getActiveExperiments returns the list", async () => {
  server.use(http.get("http://api.test/api/experiments/active", () => HttpResponse.json({ experiments: [] })));
  const { createApiClient } = await import("./api");
  const r = await createApiClient("http://api.test").getActiveExperiments();
  expect(r).toEqual({ experiments: [] });
});

test("evaluateExperiment posts to the evaluate endpoint", async () => {
  let hit = "";
  server.use(http.post("http://api.test/api/experiments/e1/evaluate", ({ request }) => { hit = request.method; return HttpResponse.json({ id: "e1", category: "milk", direction: "harmful", outcome_type: "symptom", outcome_name: "bloating", experiment_start: "x", experiment_end: "y", status: "completed", nudge_suggested: false }); }));
  const { createApiClient } = await import("./api");
  const r = await createApiClient("http://api.test").evaluateExperiment("e1");
  expect(hit).toBe("POST");
  expect(r.status).toBe("completed");
});

test("abandon/restart/ackNudge hit their endpoints", async () => {
  const seen: string[] = [];
  server.use(
    http.post("http://api.test/api/experiments/e1/abandon", () => { seen.push("abandon"); return HttpResponse.json({ ok: true }); }),
    http.post("http://api.test/api/experiments/e1/restart", () => { seen.push("restart"); return HttpResponse.json({ id: "e1", category: "milk", direction: "harmful", outcome_type: "symptom", outcome_name: "bloating", experiment_start: "x", experiment_end: "y", status: "active", nudge_suggested: false }); }),
    http.post("http://api.test/api/experiments/e1/ack-nudge", () => { seen.push("ack"); return HttpResponse.json({ ok: true }); }),
  );
  const { createApiClient } = await import("./api");
  const api = createApiClient("http://api.test");
  await api.abandonExperiment("e1");
  await api.restartExperiment("e1");
  await api.ackNudge("e1");
  expect(seen).toEqual(["abandon", "restart", "ack"]);
});

test("exportCsv fetches a blob and parses the filename", async () => {
  server.use(
    http.get("http://api.test/api/export/csv", () =>
      new HttpResponse("a,b\n1,2\n", { status: 200, headers: { "Content-Type": "text/csv", "Content-Disposition": "attachment; filename=hearty-export.csv" } })
    )
  );
  const { createApiClient } = await import("./api");
  const { blob, filename } = await createApiClient("http://api.test").exportCsv({});
  expect(filename).toBe("hearty-export.csv");
  expect(await blob.text()).toContain("a,b");
});

test("exportPdf posts the date range and returns a blob", async () => {
  let body: unknown = null;
  server.use(
    http.post("http://api.test/api/export/pdf", async ({ request }) => {
      body = await request.json();
      return new HttpResponse("%PDF-1.4", { status: 200, headers: { "Content-Type": "application/pdf", "Content-Disposition": "attachment; filename=hearty-report.pdf" } });
    })
  );
  const { createApiClient } = await import("./api");
  const { filename } = await createApiClient("http://api.test").exportPdf({ start_date: "2026-06-01", end_date: "2026-06-15" });
  expect(body).toEqual({ start_date: "2026-06-01", end_date: "2026-06-15" });
  expect(filename).toBe("hearty-report.pdf");
});

test("getPreferences / putPreferences round-trip the schema", async () => {
  let put: unknown = null;
  const prefs = { conversation_style: "warm", daily_checkin_enabled: true };
  server.use(
    http.get("http://api.test/api/preferences", () => HttpResponse.json(prefs)),
    http.put("http://api.test/api/preferences", async ({ request }) => { put = await request.json(); return HttpResponse.json(prefs); }),
  );
  const { createApiClient } = await import("./api");
  const api = createApiClient("http://api.test");
  const got = await api.getPreferences();
  expect(got.conversation_style).toBe("warm");
  await api.putPreferences(got);
  expect(put).toMatchObject({ conversation_style: "warm" });
});

test("deleteAccount issues DELETE and tolerates 204", async () => {
  server.use(http.delete("http://api.test/api/account", () => new HttpResponse(null, { status: 204 })));
  const { createApiClient } = await import("./api");
  await expect(createApiClient("http://api.test").deleteAccount()).resolves.toBeUndefined();
});

test("getHealthProfile returns the four lists", async () => {
  server.use(http.get("http://api.test/api/health-profile", () => HttpResponse.json({ allergens: [], intolerances: [], conditions: [], dietary_protocols: [], updated_at: "2026-06-21T00:00:00Z" })));
  const { createApiClient } = await import("./api");
  const r = await createApiClient("http://api.test").getHealthProfile();
  expect(r.allergens).toEqual([]);
  expect(r.updated_at).toBe("2026-06-21T00:00:00Z");
});

test("putHealthProfile sends all four lists", async () => {
  let body: unknown = null;
  server.use(http.put("http://api.test/api/health-profile", async ({ request }) => { body = await request.json(); return HttpResponse.json({ allergens: [], intolerances: [], conditions: [], dietary_protocols: [], updated_at: "x" }); }));
  const { createApiClient } = await import("./api");
  await createApiClient("http://api.test").putHealthProfile({ allergens: [{ name: "peanut", severity: "severe", confirmed_by_doctor: true }], intolerances: [], conditions: [], dietary_protocols: [] });
  expect(body).toMatchObject({ allergens: [{ name: "peanut", severity: "severe", confirmed_by_doctor: true }], intolerances: [], conditions: [], dietary_protocols: [] });
});

test("getHealthProfileDefaults returns suggestion lists", async () => {
  server.use(http.get("http://api.test/api/health-profile/defaults", () => HttpResponse.json({ allergens: ["Peanuts"], intolerances: ["Lactose"], conditions: ["IBS"], dietary_protocols: ["Low FODMAP"] })));
  const { createApiClient } = await import("./api");
  const r = await createApiClient("http://api.test").getHealthProfileDefaults();
  expect(r.allergens).toEqual(["Peanuts"]);
});
