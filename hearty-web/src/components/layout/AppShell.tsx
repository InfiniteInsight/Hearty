import { Outlet } from "react-router-dom";
import Sidebar from "./Sidebar";
import Header from "./Header";
import { useRealtimeSync } from "../../hooks/useRealtimeSync";
export default function AppShell() {
  const status = useRealtimeSync();
  return (
    <div className="grid min-h-screen grid-cols-[220px_1fr]">
      <aside className="border-r border-surface-border"><Sidebar /></aside>
      <div className="flex flex-col"><Header status={status} /><main className="flex-1 p-6"><Outlet /></main></div>
    </div>
  );
}
