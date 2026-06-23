import { supabase } from "./supabase";

export async function signInWithGoogle(origin: string = window.location.origin) {
  const { error } = await supabase.auth.signInWithOAuth({
    provider: "google",
    options: { redirectTo: `${origin}/auth/callback` },
  });
  if (error) throw error;
}

export async function signOut() {
  const { error } = await supabase.auth.signOut();
  if (error) throw error;
}

export async function getSession() {
  const { data } = await supabase.auth.getSession();
  return data.session;
}

export async function isAdmin(): Promise<boolean> {
  const { data } = await supabase.auth.getSession();
  return ((data.session?.user?.app_metadata as { role?: string } | undefined)?.role) === "admin";
}
