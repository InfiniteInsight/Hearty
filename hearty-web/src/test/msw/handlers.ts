import { http, HttpResponse } from "msw";
import type { HttpHandler } from "msw";
export const handlers: HttpHandler[] = [
  http.get("*/api/admin/settings", () => HttpResponse.json({ provisioning_mode: "open", trial_days: 14 })),
];
