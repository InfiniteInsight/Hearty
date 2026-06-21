import { expect, test, vi } from "vitest";
const signInWithOAuth = vi.fn().mockResolvedValue({ data: {}, error: null });
const signOut = vi.fn().mockResolvedValue({ error: null });
vi.mock("./supabase", () => ({ supabase: { auth: { signInWithOAuth, signOut } } }));

test("signInWithGoogle requests google provider with callback redirect", async () => {
  const { signInWithGoogle } = await import("./auth");
  await signInWithGoogle("http://localhost:5173");
  expect(signInWithOAuth).toHaveBeenCalledWith({
    provider: "google",
    options: { redirectTo: "http://localhost:5173/auth/callback" },
  });
});
