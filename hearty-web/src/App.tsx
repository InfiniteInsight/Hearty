import { Navigate, Route, Routes } from "react-router-dom";
import Login from "./pages/Login";
import AuthCallback from "./pages/AuthCallback";
import ProtectedRoute from "./router/ProtectedRoute";
import AppShell from "./components/layout/AppShell";
import Dashboard from "./pages/Dashboard";
import ComingSoon from "./pages/ComingSoon";
import Journal from "./pages/Journal";
import Trends from "./pages/Trends";
import Experiments from "./pages/Experiments";
import Conversation from "./pages/Conversation";
import Reports from "./pages/Reports";
import Settings from "./pages/Settings";
export default function App() {
  return (
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
          <Route path="/profile" element={<ComingSoon />} />
          <Route path="/settings" element={<Settings />} />
        </Route>
      </Route>
      <Route path="*" element={<Navigate to="/dashboard" replace />} />
    </Routes>
  );
}
