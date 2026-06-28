import { lazy, Suspense } from "react";
import { Navigate, Route, Routes } from "react-router-dom";
import ProtectedRoute from "./router/ProtectedRoute";
import RequireAdmin from "./router/RequireAdmin";
import AppShell from "./components/layout/AppShell";

// Route-level code-splitting: each page (and its heavy deps, e.g. recharts on
// Trends) loads on demand instead of in one ~929 KB initial bundle. The router
// shell + auth guards stay eager so navigation/redirects are instant.
const Login = lazy(() => import("./pages/Login"));
const AuthCallback = lazy(() => import("./pages/AuthCallback"));
const Dashboard = lazy(() => import("./pages/Dashboard"));
const Journal = lazy(() => import("./pages/Journal"));
const Trends = lazy(() => import("./pages/Trends"));
const Experiments = lazy(() => import("./pages/Experiments"));
const Conversation = lazy(() => import("./pages/Conversation"));
const Reports = lazy(() => import("./pages/Reports"));
const Settings = lazy(() => import("./pages/Settings"));
const Profile = lazy(() => import("./pages/Profile"));
const Admin = lazy(() => import("./pages/Admin"));

function PageFallback() {
  return <div className="flex min-h-screen items-center justify-center text-text-muted">Loading…</div>;
}

export default function App() {
  return (
    <Suspense fallback={<PageFallback />}>
      <Routes>
        <Route path="/login" element={<Login />} />
        <Route path="/auth/callback" element={<AuthCallback />} />
        <Route element={<ProtectedRoute />}>
          <Route element={<AppShell />}>
            <Route path="/dashboard" element={<Dashboard />} />
            <Route path="/" element={<Dashboard />} />
            <Route path="/journal" element={<Journal />} />
            <Route path="/trends" element={<Trends />} />
            <Route path="/trends/chat" element={<Conversation />} />
            <Route path="/experiments" element={<Experiments />} />
            <Route path="/reports" element={<Reports />} />
            <Route path="/profile" element={<Profile />} />
            <Route path="/settings" element={<Settings />} />
            <Route element={<RequireAdmin />}>
              <Route path="/admin" element={<Admin />} />
            </Route>
          </Route>
        </Route>
        <Route path="*" element={<Navigate to="/dashboard" replace />} />
      </Routes>
    </Suspense>
  );
}
