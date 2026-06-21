import { useEffect, useState } from "react";
import { Navigate, Outlet } from "react-router-dom";
import { getSession } from "../lib/auth";
import { supabase } from "../lib/supabase";

type State = "loading" | "in" | "out";

export default function ProtectedRoute() {
  const [state, setState] = useState<State>("loading");
  useEffect(() => {
    let active = true;
    getSession().then((s) => { if (active) setState(s ? "in" : "out"); }).catch(() => { if (active) setState("out"); });
    const { data: sub } = supabase.auth.onAuthStateChange((_e, session) => {
      if (active) setState(session ? "in" : "out");
    });
    return () => { active = false; sub.subscription.unsubscribe(); };
  }, []);
  if (state === "loading") return <div className="flex min-h-screen items-center justify-center text-text-muted">Loading…</div>;
  if (state === "out") return <Navigate to="/login" replace />;
  return <Outlet />;
}
