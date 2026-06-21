import { useEffect } from "react";
import { useNavigate } from "react-router-dom";
import { supabase } from "../lib/supabase";
export default function AuthCallback() {
  const navigate = useNavigate();
  useEffect(() => {
    let active = true;
    const { data: sub } = supabase.auth.onAuthStateChange((_event, session) => {
      if (active && session) navigate("/dashboard", { replace: true });
    });
    // getSession resolves exactly once and is the terminal decision: success → dashboard, otherwise → login.
    supabase.auth.getSession().then(({ data }) => {
      if (active) navigate(data.session ? "/dashboard" : "/login", { replace: true });
    });
    return () => { active = false; sub.subscription.unsubscribe(); };
  }, [navigate]);
  return <div className="flex min-h-screen items-center justify-center text-text-muted">Signing you in…</div>;
}
