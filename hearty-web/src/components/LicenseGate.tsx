import type { ReactNode } from "react";
import { useLicenseStatus } from "../hooks/useLicenseStatus";
export default function LicenseGate({ children }: { children: ReactNode }) {
  const q = useLicenseStatus();
  if (q.isPending) return <div className="p-8 text-text-faint">Loading…</div>;
  if (q.isSuccess && q.data.status !== "active") {
    return (
      <div className="mx-auto mt-24 max-w-md rounded-2xl border border-surface-border bg-surface p-6 text-center">
        <h1 className="font-display text-2xl">No active access</h1>
        <p className="mt-2 text-text-muted">Your account doesn't have an active license. Please contact the owner to regain access.</p>
      </div>
    );
  }
  return <>{children}</>; // active, or error (fail-open to avoid lockout on a transient error; the API still enforces)
}
