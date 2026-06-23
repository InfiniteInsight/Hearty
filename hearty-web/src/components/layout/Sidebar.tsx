import { useEffect, useState } from "react";
import { NavLink } from "react-router-dom";
import { isAdmin } from "../../lib/auth";
const items = [
  ["Dashboard", "/dashboard"], ["Journal", "/journal"], ["Trends", "/trends"],
  ["Experiments", "/experiments"], ["Reports", "/reports"], ["Profile", "/profile"], ["Settings", "/settings"],
] as const;
export default function Sidebar() {
  const [admin, setAdmin] = useState(false);
  useEffect(() => {
    void isAdmin().then(setAdmin);
  }, []);
  return (
    <nav className="flex flex-col gap-1 p-3">
      <div className="px-3 py-4 font-display text-2xl"><span>Heart</span><span className="text-brand">y</span></div>
      {items.map(([label, to]) => (
        <NavLink key={to} to={to}
          className={({ isActive }) => `rounded-lg px-3 py-2 text-sm ${isActive ? "bg-surface text-text" : "text-text-muted hover:text-text"}`}>
          {label}
        </NavLink>
      ))}
      {admin && (
        <NavLink to="/admin"
          className={({ isActive }) => `rounded-lg px-3 py-2 text-sm ${isActive ? "bg-surface text-text" : "text-text-muted hover:text-text"}`}>
          Admin
        </NavLink>
      )}
    </nav>
  );
}
