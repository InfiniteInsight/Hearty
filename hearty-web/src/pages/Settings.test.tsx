import { expect, test, vi } from "vitest";
import { screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
import { renderWithProviders } from "../test/utils";

vi.mock("../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t", user: { email: "me@example.com" } } } }) } },
}));
const signOut = vi.fn().mockResolvedValue(undefined);
vi.mock("../lib/auth", () => ({ signOut: () => signOut() }));
vi.mock("../lib/download", () => ({ saveBlob: vi.fn() }));
import Settings from "./Settings";

const prefs = {
  allergens: ["peanut"], conditions: [], dietary_protocols: [], medications: [],
  nudge_delay_minutes: 45, post_meal_nudge_enabled: true, daily_checkin_enabled: true,
  trends_conversation_enabled: true, weekly_digest_enabled: true, sync_error_alerts_enabled: true,
  wake_word_enabled: true, daily_checkin_hour: 8, daily_checkin_minute: 0, fcm_token: null,
  morning_checkin_enabled: true, morning_checkin_hour: 8, morning_checkin_minute: 0,
  midday_checkin_enabled: true, midday_checkin_hour: 13, midday_checkin_minute: 0,
  evening_checkin_enabled: true, evening_checkin_hour: 20, evening_checkin_minute: 0,
  conversation_style: "warm", use_cloud_when_online: false, auto_submit: true,
  auto_submit_silence_seconds: 2.5, use_on_device_model: "parakeetCtc110m",
};

test("saving preferences preserves untouched fields (allergens)", async () => {
  let put: Record<string, unknown> | null = null;
  server.use(
    http.get("*/api/preferences", () => HttpResponse.json(prefs)),
    http.put("*/api/preferences", async ({ request }) => { put = (await request.json()) as Record<string, unknown>; return HttpResponse.json(put); }),
  );
  renderWithProviders(<Settings />, { route: "/settings" });
  await userEvent.click(await screen.findByLabelText(/weekly digest/i)); // toggle one field
  await userEvent.click(screen.getByRole("button", { name: /save/i }));
  await vi.waitFor(() => expect(put).not.toBeNull());
  expect(put!.allergens).toEqual(["peanut"]); // untouched health field preserved
  expect(put!.weekly_digest_enabled).toBe(false); // toggled
});

test("delete account is gated behind the exact typed confirmation", async () => {
  let deleted = false;
  server.use(
    http.get("*/api/preferences", () => HttpResponse.json(prefs)),
    http.delete("*/api/account", () => { deleted = true; return new HttpResponse(null, { status: 204 }); }),
  );
  renderWithProviders(<Settings />, { route: "/settings" });
  await userEvent.click(await screen.findByRole("button", { name: /delete account/i }));
  const confirmBtn = screen.getByRole("button", { name: /^delete my account$/i });
  expect(confirmBtn).toBeDisabled();
  await userEvent.type(screen.getByPlaceholderText(/delete my account/i), "wrong");
  expect(confirmBtn).toBeDisabled();
  await userEvent.clear(screen.getByPlaceholderText(/delete my account/i));
  await userEvent.type(screen.getByPlaceholderText(/delete my account/i), "delete my account");
  expect(confirmBtn).toBeEnabled();
  await userEvent.click(confirmBtn);
  await vi.waitFor(() => expect(deleted).toBe(true));
  expect(signOut).toHaveBeenCalled();
});
