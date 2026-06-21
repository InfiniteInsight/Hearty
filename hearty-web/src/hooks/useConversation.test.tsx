import { expect, test, vi } from "vitest";
import { renderHook, act, waitFor } from "@testing-library/react";
import { http, HttpResponse } from "msw";
import { server } from "../test/msw/server";
vi.mock("../lib/supabase", () => ({
  supabase: { auth: { getSession: vi.fn().mockResolvedValue({ data: { session: { access_token: "t" } } }) } },
}));
import { useConversation } from "./useConversation";

test("fetches an opener on mount, then sends and appends a reply", async () => {
  let calls = 0;
  server.use(
    http.post("*/api/trends/conversation", async ({ request }) => {
      calls += 1;
      const body = (await request.json()) as { history: { role: string; content: string }[] };
      if (body.history.length === 0) {
        return HttpResponse.json({ reply: "Hey — want to talk about milk?", proposed_verdict: null, proposed_experiment: null, is_closing: false });
      }
      return HttpResponse.json({ reply: "Got it.", proposed_verdict: { category: "milk", outcome_type: "symptom", outcome_name: "bloating", verdict: "confirmed" }, proposed_experiment: null, is_closing: false });
    })
  );
  const { result } = renderHook(() => useConversation());
  await waitFor(() => expect(result.current.history.some((t) => t.content.includes("milk"))).toBe(true));
  await act(async () => { await result.current.send("yes"); });
  expect(result.current.history.at(-1)).toEqual({ role: "assistant", content: "Got it." });
  expect(result.current.proposedVerdict?.outcome_name).toBe("bloating");
});
