import { http, HttpResponse } from "msw";
import type { HttpHandler } from "msw";
export const handlers: HttpHandler[] = [
  http.get("*/api/admin/settings", () => HttpResponse.json({ provisioning_mode: "open", trial_days: 14 })),
  http.get("*/api/admin/health", () => HttpResponse.json({
    backend: { status: "ok", version: "1.0.0", revision: "local", time: "2026-06-25T00:00:00Z" },
    supabase: { status: "ok", latency_ms: 12 },
    llm: { status: "idle", model: null },
  })),
];
