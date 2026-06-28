import { useEffect, useState } from "react";
import { Navigate, Outlet } from "react-router-dom";
import { isAdmin } from "../lib/auth";

type State = "loading" | "admin" | "denied";

// Defense-in-depth route guard: the backend already enforces admin-only access on
// every /api/admin/* route, but this keeps non-admins from rendering the Admin
// page shell (and seeing empty error states) at all.
export default function RequireAdmin() {
  const [state, setState] = useState<State>("loading");
  useEffect(() => {
    let active = true;
    isAdmin()
      .then((ok) => { if (active) setState(ok ? "admin" : "denied"); })
      .catch(() => { if (active) setState("denied"); });
    return () => { active = false; };
  }, []);
  if (state === "loading") return <div className="flex min-h-screen items-center justify-center text-text-muted">Loading…</div>;
  if (state === "denied") return <Navigate to="/dashboard" replace />;
  return <Outlet />;
}
